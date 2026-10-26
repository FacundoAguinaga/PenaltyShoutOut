extends Node3D
class_name PlayerGoalkeeper

enum GKState { IDLE, ANTICIPATING, DIVING, RESULT, RECOVERING, RESET }

@export var stats: GoalkeeperStats
@export var animation_player: AnimationPlayer
@export var animation_tree: AnimationTree
@export var skeleton: Skeleton3D
@export var left_hand_ik: TwoBoneIK3D
@export var right_hand_ik: TwoBoneIK3D
@export var ball: SoccerBall

@export_group("System Config")
@export var dificultad: float = 0.4
## Para probar: el arquero siempre elige la zona correcta y reacciona sin
## demora (nunca es gol por tirarse al otro lado). Apagarlo para jugar.
@export var siempre_adivina: bool = false
@export var libreria_animaciones: Array[DiveAnimData]
@export var goal_width: float = 7.32
@export var goal_height: float = 2.44
## Centro de los palos (x, z) y su radio: el arquero no los puede atravesar.
@export var palos: Array[Vector2] = [Vector2(-3.79, -10.995), Vector2(3.796, -10.995)]
@export var radio_palo: float = 0.125

signal keeper_save(ball: SoccerBall)
signal keeper_deflect(ball: SoccerBall)

var state: GKState = GKState.IDLE
var reposition_module: RepositionModule
var _current_anim: DiveAnimData
var _base_position: Vector3
## Como termina la jugada (ResultModule.Resultado). Se decide al elegir la
## animacion, no al momento del contacto.
var _resultado: int = ResultModule.Resultado.GOL
## Ya hubo contacto (rebote o agarre): no se vuelve a procesar.
var _contacto_hecho: bool = false
## La tiene en las manos: la pelota sigue a las manos cada cuadro.
var _agarrada: bool = false
var _t_agarre: float = 0.0
## Velocidad de la pelota antes de tocar al arquero (el choque fisico con los
## colisionadores del cuerpo se la come, y el rebote sale de esta).
var _vel_llegada: Vector3 = Vector3.ZERO
## Corrimiento hacia la cancha para no atravesar un palo (ver _esquivar_palos).
var _empuje_palo: float = 0.0
var _empuje_objetivo: float = 0.0
var _pos_huesos_prev: Dictionary = {}
## Solo para pruebas (tools/test_tiros): fuerza el resultado. -1 = normal.
var forzar_resultado: int = -1
## El plan salio de anticipar() (antes de la patada): al patear se resincroniza.
var _anticipado: bool = false
## Cada plan nuevo invalida las esperas del anterior.
var _plan_id: int = 0
var _objetivo: Vector2

@export_group("Rebote")
## Velocidad maxima para agarrarla si no hay GoalkeeperStats asignado.
@export var velocidad_max_atajar: float = 24.0
## Que fraccion de la velocidad de llegada conserva la pelota al rebotar.
@export var rebote_conserva: Vector2 = Vector2(0.25, 0.4)
## Velocidad lateral minima y maxima con la que la despeja hacia el costado.
@export var rebote_lateral: Vector2 = Vector2(3.0, 7.0)

func _ready():
	_base_position = global_position
	
	if not animation_player:
		animation_player = _find_node_of_type(self, "AnimationPlayer") as AnimationPlayer
	if not animation_tree:
		animation_tree = _find_node_of_type(self, "AnimationTree") as AnimationTree
		
	if animation_tree:
		animation_tree.active = false

	if not skeleton:
		skeleton = _find_node_of_type(self, "Skeleton3D") as Skeleton3D

	# Inicializamos el RepositionModule con IK en la mano derecha por ahora (se podría mejorar para usar la correcta según lado)
	var main_ik = right_hand_ik if right_hand_ik else left_hand_ik
	reposition_module = RepositionModule.new(self, animation_player, main_ik)
	
	reset_to_idle()

func _process(delta: float) -> void:
	if state == GKState.DIVING:
		reposition_module.process_frame(delta)
		if animation_player.current_animation_position >= _current_anim.contact_time:
			_on_dive_terminado()
	if state == GKState.DIVING or state == GKState.RESULT:
		_esquivar_palos(delta)

## Huesos que se revisan contra los palos, con el grosor aproximado del cuerpo
## alrededor de cada uno.
const HUESOS_CUERPO := {
	"mixamorig1Hips": 0.15, "mixamorig1Spine2": 0.15, "mixamorig1Head": 0.12,
	"mixamorig1LeftArm": 0.08, "mixamorig1LeftForeArm": 0.06, "mixamorig1LeftHand": 0.06,
	"mixamorig1RightArm": 0.08, "mixamorig1RightForeArm": 0.06, "mixamorig1RightHand": 0.06,
	"mixamorig1LeftUpLeg": 0.09, "mixamorig1LeftLeg": 0.07, "mixamorig1LeftFoot": 0.06,
	"mixamorig1RightUpLeg": 0.09, "mixamorig1RightLeg": 0.07, "mixamorig1RightFoot": 0.06,
}
## Cuanto se adelanta la prediccion de cada hueso, y que tan rapido se puede
## correr el arquero hacia la cancha.
const ANTICIPO_PALO := 0.15
const VELOCIDAD_EMPUJE := 3.0

## Algunas palomitas al palo siguen de largo despues del contacto y el cuerpo
## pasaria a traves del palo. Cada cuadro se predice donde va a estar cada
## hueso un instante despues (con su velocidad) y, si se va a meter en un
## palo, se corre al arquero hacia la cancha (+z) lo justo para que pase por
## delante. Asi conserva la inercia de la palomita y cae delante del palo.
func _esquivar_palos(delta: float) -> void:
	if not skeleton or delta <= 0.0:
		return
	for hueso in HUESOS_CUERPO:
		var p := _pos_hueso(hueso)
		var prev: Vector3 = _pos_huesos_prev.get(hueso, p)
		_pos_huesos_prev[hueso] = p
		var q := p + (p - prev) / delta * ANTICIPO_PALO
		if q.y > goal_height + 0.2:
			continue
		var r: float = radio_palo + HUESOS_CUERPO[hueso]
		for palo in palos:
			var dx := q.x - palo.x
			# distancia en z desde el palo, ya contando lo que se lo corrio
			var dz := q.z + (_empuje_objetivo - _empuje_palo) - palo.y
			if dx * dx + dz * dz < r * r:
				var necesario := sqrt(r * r - dx * dx) - dz
				_empuje_objetivo = maxf(_empuje_objetivo, _empuje_palo + necesario)
	_empuje_palo = move_toward(_empuje_palo, _empuje_objetivo, VELOCIDAD_EMPUJE * delta)
	# absoluto: mientras se tira, reposition_module vuelve a poner la posicion
	# en cada cuadro
	global_position.z = _base_position.z + reposition_module.offset_actual.z + _empuje_palo

func _physics_process(delta: float) -> void:
	if _agarrada:
		_seguir_manos(delta)
		return
	# El contacto es cuando la pelota llega al plano de las manos (no al
	# terminar el timer de la animacion): asi sale de donde esta la mano.
	if _resultado == ResultModule.Resultado.GOL or _contacto_hecho or not _current_anim or not ball:
		return
	if state != GKState.DIVING and state != GKState.RESULT:
		return
	var v := ball.linear_velocity
	var plano_manos := _base_position.z + _current_anim.canonical_target.z
	var llego := ball.global_position.z <= plano_manos + 0.11
	# si ya pego en un colisionador del cuerpo, frena de golpe: tambien cuenta
	var pego_en_el_cuerpo := _vel_llegada != Vector3.ZERO and v.length() < _vel_llegada.length() * 0.6
	if not pego_en_el_cuerpo and v.z < -1.0:
		_vel_llegada = v
	if llego or pego_en_el_cuerpo:
		_contacto_hecho = true
		if _resultado == ResultModule.Resultado.ATAJA:
			_agarrar()
		else:
			_rebotar()

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null

## Se llama cuando el pateador suelta el tiro y arranca la carrera. El tiro ya
## esta definido (fuerza y direccion), asi que el arquero lo "lee" y empieza a
## moverse antes de la patada, como un arquero de verdad: la animacion tiene
## tiempo de reproducirse entera a velocidad normal. t_hasta_patada es
## estimado; cuando se patea de verdad (on_ball_kicked) se resincroniza.
func anticipar(origen: Vector3, velocidad: Vector3, t_hasta_patada: float) -> void:
	_anticipado = true
	_planear(origen, velocidad, t_hasta_patada)

func on_ball_kicked(shot: ShotData) -> void:
	if _anticipado and (state == GKState.ANTICIPATING or state == GKState.DIVING):
		_resincronizar(shot)
		return
	# Sin anticipacion (la pelota se pateo sin pasar por el pateador): el
	# arquero reacciona recien ahora y la animacion se acelera para llegar.
	_planear(shot.origin, shot.initial_velocity, 0.0)

## Decide la jugada y la animacion, y programa cuando arrancarla.
## t_extra: segundos que faltan para que salga la pelota.
func _planear(origen: Vector3, velocidad: Vector3, t_extra: float) -> void:
	var prediccion := PredictionModule.calcular_target_real(origen, velocidad)

	if not prediccion.es_gol_potencial:
		# Va afuera, nos quedamos quietos o simulamos reacción tardía/corta
		return

	var error := ErrorModule.aplicar_error(prediccion.target, dificultad)
	if siempre_adivina:
		error = {"target_percibido": prediccion.target, "delay_extra": 0.0}

	# 1. El arquero elige zona con lo que cree (con error de percepcion).
	var zona_elegida: DiveAnimData.Zone = DiveAnimData.AnimSelector.clasificar_zona(error.target_percibido, goal_width, goal_height)
	var zona_real: DiveAnimData.Zone = DiveAnimData.AnimSelector.clasificar_zona(prediccion.target, goal_width, goal_height)

	# 2. El desenlace se decide aca, ANTES de arrancar la animacion, para que
	# la animacion no mienta.
	var vel_max: float = stats.velocidad_max_atajar if stats else velocidad_max_atajar
	_resultado = ResultModule.decidir(zona_elegida, zona_real, velocidad.length(), vel_max)
	if forzar_resultado >= 0:
		_resultado = forzar_resultado
	_contacto_hecho = false
	_agarrada = false
	_vel_llegada = Vector3.ZERO

	# 3. La animacion: SAVE si la agarra, DIVE si rebota o es gol. Se elige la
	# que toca mas cerca de por donde el arquero cree que pasa la pelota.
	var tipo := DiveAnimData.Tipo.SAVE if _resultado == ResultModule.Resultado.ATAJA else DiveAnimData.Tipo.DIVE
	var anim := DiveAnimData.AnimSelector.elegir(libreria_animaciones, zona_elegida, tipo, error.target_percibido)
	if not anim:
		print("[Goalkeeper] No hay animación disponible en la librería.")
		return
	_current_anim = anim

	# El contacto es cuando la pelota cruza el plano de las manos de la
	# animacion elegida (el arquero sale a achicar). Ahi se mide por donde
	# pasa: todavia va mas baja y mas al centro que en la linea de gol.
	var en_manos := PredictionModule.punto_en_z(origen, velocidad, _base_position.z + anim.canonical_target.z)
	_objetivo = en_manos.punto
	var plan := TimingModule.planificar(anim, t_extra + en_manos.tiempo, error.delay_extra)
	print("[Goalkeeper] %s | zona elegida %s, real %s | %.1f m/s | %s | arranca en %.2f s desde %.2f s a %.2fx" % [
		ResultModule.Resultado.keys()[_resultado], DiveAnimData.Zone.keys()[zona_elegida],
		DiveAnimData.Zone.keys()[zona_real], velocidad.length(), anim.anim_name,
		plan.delay, plan.inicio, plan.velocidad])
	_programar(plan)

func _programar(plan: Dictionary) -> void:
	_plan_id += 1
	var id := _plan_id
	state = GKState.ANTICIPATING
	await get_tree().create_timer(plan.delay).timeout
	if state == GKState.ANTICIPATING and id == _plan_id:
		iniciar_dive(_current_anim, _objetivo, plan.inicio, plan.velocidad)

## La patada de verdad: se ajusta la velocidad de la animacion para que la
## mano llegue justo cuando llega la pelota (la estimacion del momento de la
## patada puede errar por unos cuadros).
func _resincronizar(shot: ShotData) -> void:
	var en_manos := PredictionModule.punto_en_z(shot.origin, shot.initial_velocity, _base_position.z + _current_anim.canonical_target.z)
	if state == GKState.ANTICIPATING:
		_programar(TimingModule.planificar(_current_anim, en_manos.tiempo, 0.0))
		return
	var falta_anim := _current_anim.contact_time - animation_player.current_animation_position
	if falta_anim > 0.0:
		animation_player.speed_scale = clampf(falta_anim / maxf(en_manos.tiempo, 0.05), 0.5, TimingModule.VELOCIDAD_MAXIMA)

## objetivo: donde cruza la pelota. Si la ataja o le rebota, la mano va ahi;
## si es gol se usa para que la pelota pase lejos del arquero.
## inicio y velocidad vienen de TimingModule.planificar: si no hay tiempo, la
## animacion arranca mas adelante y mas rapido para llegar justo al contacto.
## El contacto (_on_dive_terminado) lo detecta _process cuando la animacion
## llega a su contact_time.
func iniciar_dive(anim: DiveAnimData, objetivo: Vector2, inicio: float = 0.0, velocidad: float = 1.0) -> void:
	state = GKState.DIVING
	_current_anim = anim

	# Restaurar pos base antes del dive por si acaso
	global_position = _base_position
	_empuje_palo = 0.0
	_empuje_objetivo = 0.0
	_pos_huesos_prev.clear()

	var llega := _resultado != ResultModule.Resultado.GOL
	reposition_module.iniciar_offset(objetivo, anim, _base_position, llega, inicio)

	if animation_player.has_animation(anim.anim_name):
		# fundido desde la postura de espera; mas largo si se arranca la
		# animacion por la mitad, para tapar el salto de pose
		animation_player.speed_scale = velocidad
		animation_player.play(anim.anim_name, 0.2 if inicio < 0.05 else 0.3)
		animation_player.seek(inicio, true)

func _on_dive_terminado() -> void:
	state = GKState.RESULT
	# despues del contacto la animacion sigue a velocidad normal (la caida)
	animation_player.speed_scale = 1.0

	# El desenlace ya se decidio en on_ball_kicked, cuando se eligio la
	# animacion. La atajada se avisa al contacto (_agarrar o _rebotar).

## Despeje: la pelota sale para afuera y hacia la cancha, nunca hacia el arco.
## Las de arriba salen mas altas (por encima del travesano), las de abajo
## rasantes. Mientras mas fuerte llega, mas fuerte sale.
func _rebotar() -> void:
	var v := _vel_llegada if _vel_llegada != Vector3.ZERO else ball.linear_velocity
	var fila := int(_current_anim.zone) / 3  # 0 arriba, 1 medio, 2 abajo
	var dx := ball.global_position.x - global_position.x
	var lado := signf(dx) if absf(dx) > 0.15 else (1.0 if randf() < 0.5 else -1.0)
	var fuerza := clampf(v.length() / 25.0, 0.4, 1.3)

	var nueva := Vector3.ZERO
	nueva.x = lado * randf_range(rebote_lateral.x, rebote_lateral.y) * fuerza
	nueva.z = absf(v.z) * randf_range(rebote_conserva.x, rebote_conserva.y)
	match fila:
		0: nueva.y = randf_range(5.0, 8.0) * fuerza
		1: nueva.y = randf_range(1.5, 3.5) * fuerza
		_: nueva.y = randf_range(0.5, 2.0) * fuerza
	ball.linear_velocity = nueva
	ball.angular_velocity = Vector3(randf_range(-15, 15), randf_range(-15, 15), randf_range(-15, 15))
	_avisar_contacto("rebote")

## Atajada: la pelota queda en las manos y las sigue hasta que termina la
## jugada (no rebota, no es gol).
func _agarrar() -> void:
	ball.agarrar()
	_agarrada = true
	_t_agarre = 0.0
	_avisar_contacto("agarra")

## En los primeros cuadros la pelota se acerca rapido al punto entre las manos
## (las manos pueden haber quedado a unos cm) y despues va pegada.
func _seguir_manos(delta: float) -> void:
	_t_agarre += delta
	var destino := _punto_entre_manos()
	var peso := clampf(_t_agarre / 0.08, 0.35, 1.0)
	ball.global_position = ball.global_position.lerp(destino, peso)

## Entre los nudillos de las dos manos si estan juntas; si no, en la mano del
## contacto.
func _punto_entre_manos() -> Vector3:
	var izq := _pos_hueso("mixamorig1LeftHandMiddle1")
	var der := _pos_hueso("mixamorig1RightHandMiddle1")
	if izq.distance_to(der) < 0.45:
		return (izq + der) * 0.5
	return izq if _current_anim.hand_bone.contains("Left") else der

func _pos_hueso(nombre: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(nombre)).origin

func _avisar_contacto(que: String) -> void:
	var t_anim := animation_player.current_animation_position
	print("[Goalkeeper] Contacto (%s): %s en %.2f s de la animacion (cuadro %d), esperado %.2f s" % [
		que, _current_anim.anim_name, t_anim, roundi(t_anim * 30.0), _current_anim.contact_time])
	keeper_save.emit(ball)

func reset_to_idle():
	state = GKState.IDLE
	_empuje_palo = 0.0
	_empuje_objetivo = 0.0
	_pos_huesos_prev.clear()
	_anticipado = false
	_plan_id += 1
	_resultado = ResultModule.Resultado.GOL
	_contacto_hecho = false
	_agarrada = false
	_vel_llegada = Vector3.ZERO
	global_position = _base_position
	if animation_player:
		animation_player.speed_scale = 1.0
	if animation_player and animation_player.has_animation("Goalkeeperidle"):
		animation_player.play("Goalkeeperidle")
	if reposition_module:
		reposition_module._stop_ik()
