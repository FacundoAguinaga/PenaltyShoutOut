extends RigidBody3D
class_name SoccerBall

@export var min_speed_threshold: float = 0.5
@export var max_lifetime: float = 6.0
@export var bounce_factor: float = 0.6
@export var air_resistance: float = 0.998
@export var spin_decay: float = 0.95
@export var goal_line_z: float = -12.0

signal shot_taken(shot_data: ShotData)
signal crossed_goal_line(ball_world_pos: Vector3)
signal ball_stopped
## Un golpe para el sonido: "palo", "travesano", "red" o "pique", con su fuerza (0 a 1).
## Los del arquero los avisa el arquero (atajada o rebote).
signal impacto(tipo: String, fuerza: float)

## El arco (RedArco en game.tscn, el mismo que esquiva el arquero): los palos y el
## travesano son cilindros de este radio, con el centro en x = +-ARCO_PALO_X y en
## y = ARCO_TRAVESANO_Y, sobre la linea z = ARCO_Z. La escena no les da colision: sin esto
## la pelota los atravesaba y frenaba recien en la red de costado.
const ARCO_Z := -10.995
const ARCO_PALO_X := 3.79
const ARCO_TRAVESANO_Y := 2.57
const RADIO_PALO := 0.125
const RADIO_PELOTA := 0.11
## Cuanto rebota la pelota en el metal (1 = sin perder nada) y cuanto frena de costado.
const REBOTE_PALO := 0.6
const ROCE_PALO := 0.85
## Pasada esta profundidad adentro del arco, la pelota ya esta en la red.
const PROFUNDIDAD_RED := 0.3

## Aire en la picada. Con una parabola perfecta la picada "flota" sin peso. Una pelota de
## verdad (0,43 kg, radio 0,11 m) tiene roce cuadratico con el aire y, picada por abajo,
## sale con efecto hacia atras: el efecto Magnus la sostiene arriba y el roce la frena, asi
## que sube, se queda colgada y cae mas parada y muerta. Aceleraciones por unidad:
## ROCE = 0,5 * rho * Cd * A / m  (rho 1,2; Cd 0,25; A 0,038 m2)
## MAGNUS = 0,5 * rho * A * r / m  (multiplica a giro x velocidad)
const ROCE_AIRE := 0.0133
const MAGNUS := 0.0058
## Efecto hacia atras de la picada (rad/s), 2 a 3 vueltas por segundo segun lo suave. Con
## mas, el Magnus la sostiene tanto que vuelve a flotar; con esto manda el roce: sube
## rapido, se frena y cae mas parada y muerta. El efecto hace que frene al picar.
const GIRO_PICADA_SUAVE := 20.0
const GIRO_PICADA_FUERTE := 13.0
## Cuanto efecto pierde por segundo en el aire (el real casi no baja en un segundo).
const FRENO_GIRO_AIRE := 0.25
## Un poco de efecto de costado al azar: ninguna picada sale exactamente igual.
const GIRO_LATERAL_MAX := 6.0

var is_in_play: bool = false
var has_been_kicked: bool = false
var lifetime_timer: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var _prev_z: float = 0.0
var _crossed_emitted: bool = false
var _last_shot_data: ShotData
var _sin_freno: bool = false
## Picada en vuelo: el giro que usa el Magnus (rad/s, mundo). Cero = sin aire de picada.
var _giro_aire := Vector3.ZERO
var _en_el_aire := false
var _vel_esperada := Vector3.ZERO
var _vel_previa := Vector3.ZERO
var _red_sonada := false
var _ultimo_golpe := {}

func _ready():
	spawn_position = global_position
	_prev_z = global_position.z
	freeze = true
	continuous_cd = true
	# Antes que la red (red_arco.gd), que tambien se adelanta a la pelota: si no, frena
	# el tiro contra el borde de la tela atado al palo antes de que llegue a rebotar.
	process_physics_priority = -10
	collision_layer = 1

func _physics_process(delta: float):
	if not is_in_play:
		return

	lifetime_timer += delta

	if freeze:
		reset_to(spawn_position)
		return

	_apply_air_resistance()
	_aire_picada(delta)
	_chocar_con_el_arco(delta)
	_detectar_golpes()
	_check_goal_line_crossing()
	_check_out_of_bounds()

	if linear_velocity.length() < min_speed_threshold and has_been_kicked:
		linear_velocity = Vector3.ZERO
		is_in_play = false
		ball_stopped.emit()

	if lifetime_timer > max_lifetime:
		is_in_play = false
		ball_stopped.emit()

func _check_goal_line_crossing():
	if _crossed_emitted:
		return
	var curr_z = global_position.z
	var crossed = (_prev_z > goal_line_z and curr_z <= goal_line_z) or \
				  (_prev_z < goal_line_z and curr_z >= goal_line_z)
	_prev_z = curr_z
	if crossed:
		_crossed_emitted = true
		crossed_goal_line.emit(global_position)

## La red y el piso, para el sonido. La red se mueve de a poco (red_arco.gd), asi que se
## avisa al entrar en ella; el piso, cuando la pelota venia bajando y deja de bajar.
func _detectar_golpes() -> void:
	var p := global_position
	if not _red_sonada and p.z < ARCO_Z - PROFUNDIDAD_RED and absf(p.x) < ARCO_PALO_X - RADIO_PALO and p.y < ARCO_TRAVESANO_Y - RADIO_PALO:
		_red_sonada = true
		_golpe("red", _vel_previa.length() / 30.0)
	elif p.y < 0.35 and _vel_previa.y < -1.0 and linear_velocity.y > _vel_previa.y + 1.0:
		_golpe("pique", -_vel_previa.y / 10.0)
	_vel_previa = linear_velocity

## Rebote contra los palos y el travesano. Se mira el tramo que la pelota va a recorrer
## en este cuadro (a 30 m/s son 0,5 m, mas que el palo): si toca un cilindro, se la deja
## en el punto de contacto y se refleja la velocidad sobre la normal del metal.
func _chocar_con_el_arco(delta: float) -> void:
	var desde := global_position
	var hasta := desde + linear_velocity * delta
	if absf(hasta.z - ARCO_Z) > 1.0 and absf(desde.z - ARCO_Z) > 1.0:
		return
	var r := RADIO_PALO + RADIO_PELOTA
	var mejor := INF
	var normal := Vector3.ZERO
	var tipo := ""
	for lado in [-1.0, 1.0]:
		# Palo: cilindro vertical, se mira en el plano xz.
		var c := Vector2(lado * ARCO_PALO_X, ARCO_Z)
		var u := _corte(Vector2(desde.x, desde.z) - c, Vector2(hasta.x - desde.x, hasta.z - desde.z), r)
		var y := lerpf(desde.y, hasta.y, u)
		if u < mejor and y < ARCO_TRAVESANO_Y:
			var punto := Vector2(lerpf(desde.x, hasta.x, u), lerpf(desde.z, hasta.z, u)) - c
			mejor = u
			normal = Vector3(punto.x, 0.0, punto.y).normalized()
			tipo = "palo"
	# Travesano: cilindro horizontal a lo ancho, se mira en el plano yz.
	var ct := Vector2(ARCO_TRAVESANO_Y, ARCO_Z)
	var ut := _corte(Vector2(desde.y, desde.z) - ct, Vector2(hasta.y - desde.y, hasta.z - desde.z), r)
	if ut < mejor and absf(lerpf(desde.x, hasta.x, ut)) < ARCO_PALO_X:
		var punto := Vector2(lerpf(desde.y, hasta.y, ut), lerpf(desde.z, hasta.z, ut)) - ct
		mejor = ut
		normal = Vector3(0.0, punto.x, punto.y).normalized()
		tipo = "travesano"
	if tipo == "":
		return
	var v := linear_velocity
	var hacia := v.dot(normal)
	if hacia >= 0.0:
		return
	global_position = desde.lerp(hasta, mejor) + normal * 0.005
	var tangente := v - normal * hacia
	linear_velocity = tangente * ROCE_PALO - normal * hacia * REBOTE_PALO
	_golpe(tipo, -hacia / 25.0)

## En que fraccion (0 a 1) del tramo p0 -> p0 + d entra al circulo de radio r alrededor del
## origen, o INF si no entra (ni empieza adentro).
static func _corte(p0: Vector2, d: Vector2, r: float) -> float:
	var a := d.dot(d)
	var b := 2.0 * p0.dot(d)
	var c := p0.dot(p0) - r * r
	if c <= 0.0:
		return 0.0
	if a < 1e-8:
		return INF
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return INF
	var u := (-b - sqrt(disc)) / (2.0 * a)
	return u if u >= 0.0 and u <= 1.0 else INF

func _golpe(tipo: String, fuerza: float) -> void:
	var ahora := lifetime_timer
	if ahora - float(_ultimo_golpe.get(tipo, -1.0)) < 0.2:
		return
	_ultimo_golpe[tipo] = ahora
	impacto.emit(tipo, clampf(fuerza, 0.0, 1.0))

func _check_out_of_bounds():
	if not is_in_play:
		return
	# If ball goes way behind goal line (-14.5m) or far wide (> 9m) or too high (> 6m)
	if global_position.z < -14.5 or abs(global_position.x) > 9.0 or global_position.y > 6.0:
		is_in_play = false
		ball_stopped.emit()

## picada: `velocity` es la parabola sin aire que calculo el pateador (la que predice el
## arquero). La pelota sale con efecto hacia atras y con la velocidad que, con roce y
## Magnus, cruza la linea en el mismo punto y en el mismo momento que esa parabola.
func kick(velocity: Vector3, picada: bool = false):
	var sin_freno := picada
	_sin_freno = sin_freno
	_giro_aire = Vector3.ZERO
	_en_el_aire = false
	_vel_esperada = Vector3.ZERO
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE if sin_freno else RigidBody3D.DAMP_MODE_COMBINE
	linear_damp = 0.0
	freeze = false
	is_in_play = true
	has_been_kicked = true
	lifetime_timer = 0.0
	_crossed_emitted = false
	_prev_z = global_position.z
	_red_sonada = false
	_ultimo_golpe.clear()
	_vel_previa = velocity

	linear_velocity = velocity

	var lateral_spin = velocity.x * 0.05
	var vertical_spin = velocity.y * 0.02
	angular_velocity = Vector3(vertical_spin, lateral_spin, 0.0)

	if picada:
		_giro_aire = giro_de_picada(velocity, randf_range(-1.0, 1.0))
		linear_velocity = salida_picada(global_position, velocity, _giro_aire)
		angular_velocity = _giro_aire
		_en_el_aire = true

	_last_shot_data = ShotData.new(global_position, velocity, 1.0, 0.0)
	shot_taken.emit(_last_shot_data)

func reset_to(pos: Vector3):
	_en_el_aire = false
	freeze = true
	is_in_play = false
	has_been_kicked = false
	lifetime_timer = 0.0
	_crossed_emitted = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = pos
	_prev_z = pos.z

## El arquero la agarra: deja de moverse sola y de contar como en juego (el
## arquero la va moviendo con las manos). reset_to() la vuelve a soltar.
func agarrar():
	_en_el_aire = false
	is_in_play = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

func _apply_air_resistance():
	if not _sin_freno:
		linear_velocity *= air_resistance
	if not _en_el_aire:
		angular_velocity *= spin_decay

## Roce y Magnus mientras la picada vuela. Al primer pique (o al tocar la red, el palo o
## al arquero, que le cambian la velocidad) se apaga: desde ahi la mueve la fisica comun, y
## el efecto que le queda la hace frenar al picar en vez de seguir rodando.
func _aire_picada(delta: float) -> void:
	if not _en_el_aire:
		return
	# Un cambio brusco de velocidad es un golpe (arquero, palo, red): ya no vuela libre.
	var golpeada := _vel_esperada != Vector3.ZERO and linear_velocity.distance_to(_vel_esperada) > 1.0
	if freeze or golpeada or global_position.y < RADIO_PELOTA + 0.03 or global_position.z < ARCO_Z - 0.05:
		_en_el_aire = false
		return
	linear_velocity += aceleracion_aire(linear_velocity, _giro_aire) * delta
	_vel_esperada = linear_velocity + Vector3.DOWN * 9.8 * delta
	_giro_aire *= exp(-FRENO_GIRO_AIRE * delta)
	angular_velocity = _giro_aire

## Efecto de una picada que sale con `velocidad`: hacia atras (alrededor del eje que
## cruza la direccion del tiro) y un poco de costado. lateral entre -1 y 1.
static func giro_de_picada(velocidad: Vector3, lateral: float) -> Vector3:
	var plano := Vector3(velocidad.x, 0.0, velocidad.z)
	if plano.length() < 0.01:
		return Vector3.ZERO
	var dir := plano.normalized()
	# Mas lenta = mas picada por abajo = mas efecto.
	var giro := remap(clampf(plano.length(), 6.0, 12.0), 6.0, 12.0, GIRO_PICADA_SUAVE, GIRO_PICADA_FUERTE)
	return dir.cross(Vector3.UP) * giro + Vector3.UP * lateral * GIRO_LATERAL_MAX

static func aceleracion_aire(v: Vector3, giro: Vector3) -> Vector3:
	return -ROCE_AIRE * v.length() * v + MAGNUS * giro.cross(v)

## La velocidad de salida con aire que llega al mismo punto de la linea que la parabola
## `parabola`, en el mismo tiempo. Se simula con el mismo paso que la fisica y se corrige
## la salida por lo que erra, hasta que erra menos de un centimetro.
static func salida_picada(desde: Vector3, parabola: Vector3, giro: Vector3) -> Vector3:
	if parabola.z > -0.1:
		return parabola
	var g := 9.8
	var t_linea := (PredictionModule.Z_GOAL - desde.z) / parabola.z
	var destino := desde + parabola * t_linea + Vector3.DOWN * 0.5 * g * t_linea * t_linea
	var v0 := parabola
	for _i in 8:
		var llega := _simular_hasta(desde, v0, giro, t_linea)
		var error := destino - llega
		if error.length() < 0.01:
			break
		v0 += error / t_linea
	return v0

static func _simular_hasta(desde: Vector3, v0: Vector3, giro: Vector3, t_total: float) -> Vector3:
	var h := 1.0 / float(Engine.physics_ticks_per_second)
	var p := desde
	var v := v0
	var w := giro
	var t := 0.0
	while t + h <= t_total:
		# El mismo orden que en el juego: _physics_process suma el aire y despues el
		# motor suma la gravedad y mueve.
		v += aceleracion_aire(v, w) * h
		w *= exp(-FRENO_GIRO_AIRE * h)
		v += Vector3.DOWN * 9.8 * h
		p += v * h
		t += h
	var resto := t_total - t
	return p + v * resto + Vector3.DOWN * 0.5 * 9.8 * resto * resto

func get_speed() -> float:
	return linear_velocity.length()

func get_velocity() -> Vector3:
	return linear_velocity
