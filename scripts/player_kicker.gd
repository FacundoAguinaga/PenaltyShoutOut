extends Node3D
class_name PlayerKicker

enum KickState {
	IDLE,
	AIMING,
	CHARGING,
	RUN_UP,
	KICK_CONTACT,
	FOLLOW_THROUGH
}

@export var animation_player: AnimationPlayer
@export var skeleton: Skeleton3D
@export var ball: SoccerBall

@export_group("IK Setup (Godot 4.7 TwoBoneIK3D)")
@export var plant_foot_ik: TwoBoneIK3D
@export var kick_foot_ik: TwoBoneIK3D
@export var plant_foot_target: Marker3D
@export var kick_foot_target: Marker3D

@export_group("Bone Names")
@export var plant_leg_bone: String = "mixamorig1LeftUpLeg"
@export var plant_knee_bone: String = "mixamorig1LeftLeg"
@export var plant_foot_bone: String = "mixamorig1LeftFoot"
@export var kick_leg_bone: String = "mixamorig1RightUpLeg"
@export var kick_knee_bone: String = "mixamorig1RightLeg"
@export var kick_foot_bone: String = "mixamorig1RightFoot"

@export_group("Kick Parameters")
## Veces por segundo que se llena la barra.
@export var power_speed: float = 1.0
@export var max_power: float = 100.0
@export var optimal_power_min: float = 75.0
@export var optimal_power_max: float = 90.0
## Second of the kick animation where the kicking foot hits the ball: the
## foot is at its lowest point and at full speed (12.5 m/s), right beside the
## plant foot. Measured on "Soccerpenaltykick" (a hair early: the check runs
## once per frame and the foot moves ~20 cm per frame there).
@export var kick_contact_time: float = 0.715
## Pause between releasing the shot and starting the approach. The kick
## animation already contains the run-up steps, so there is no jog.
@export var run_up_duration: float = 0.4
## Distance from the toe joint to the ball centre at contact (the ball sits a
## bit ahead of the toe).
@export var toe_to_ball: float = 0.12
## Foot IK during the kick. Off: the animation, with the kicker placed so the
## foot goes through the ball, already hits it; the IK pinned the plant foot
## at the start of the approach and stretched the leg.
@export var use_kick_ik: bool = false
@export var max_aim_goal_height: float = 2.8
@export var min_aim_goal_height: float = 0.0
@export var aim_horizontal_range: float = 4.2
@export var goal_z_position: float = -12.0

@export_group("Aim Feel (FIFA-style)")
@export var aim_smooth_speed: float = 6.0
@export var aim_center_pull: float = 4.0
@export var aim_edge_instability: float = 0.15
@export var aim_edge_threshold: float = 0.7

var current_state: KickState = KickState.IDLE
var _smooth_aim: Vector2 = Vector2.ZERO
var aim_target_3d: Vector3 = Vector3.ZERO
var power: float = 0.0
var final_power: float = 0.0
var final_target: Vector3 = Vector3.ZERO
var run_up_timer: float = 0.0
var is_kick_complete: bool = false
var plant_foot_world_pos: Vector3
var _last_shot_data: ShotData
## Where the ball must be, relative to the kicker, for the kick animation to
## hit it (measured once in _ready from the animation itself).
var _contact_offset := Vector3.ZERO
## Animaciones de PES (ver PesAnimaciones): cada remate es una carrera unida a un
## golpe, y hay varios por estilo de carrera, direccion, potencia y forma de golpear.
var _pes := false
var _remates_por_estilo := {}
var _estilo := ""
var _remate: Dictionary = {}
var _inicio_remate := 0.0
var _reaccion := ""
var _picada := false
## Una cinematica maneja al pateador: no reacciona por su cuenta.
var en_cinematica := false
## Lo maneja la IA (el rival patea): no lee el teclado, el GameManager elige
## el tiro y llama a patear_automatico().
var automatico := false
var _ultima_picada := ""
var _base_basis: Basis
const VELOCIDAD_CARRERA := 0.72
## La carrera arranca a esta fraccion de su velocidad y llega a la normal en
## ARRANQUE_CARRERA segundos de clip: sale de estar parado, no a mitad de un trote.
const VELOCIDAD_ARRANQUE := 0.4
## Picada: segundos de vuelo hasta la linea y a que altura minima la cruza.
const VUELO_PICADA_LENTA := 1.5
const VUELO_PICADA_RAPIDA := 1.05
const ALTURA_MINIMA_PICADA := 1.3
## Entre los remates casi igual de buenos se elige al azar, y con mas libertad en la
## picada: el que ataja no tiene que poder reconocerla por el gesto.
const MARGEN_VARIEDAD_REMATE := 0.1
const MARGEN_VARIEDAD_PICADA := 0.7
const ARRANQUE_CARRERA := 0.4

signal kick_connecting(power: float, kick_target: Vector3)
signal ball_launch_requested(velocity: Vector3)
signal shot_taken(shot_data: ShotData)

func _ready():
	_find_skeleton_and_anim_player()
	_setup_ik()
	if PesAnimaciones.disponible():
		_cargar_pes()
	else:
		_measure_contact_offset()

func _cargar_pes() -> void:
	_pes = true
	_base_basis = global_basis
	PesAnimaciones.cargar_libreria(animation_player, "pateador.res")
	PesAnimaciones.cuidar_piso(self, skeleton)
	animation_player.animation_finished.connect(_al_terminar_animacion)
	for r: Dictionary in PesAnimaciones.datos()["remates"]:
		if not _remates_por_estilo.has(r["estilo"]):
			_remates_por_estilo[r["estilo"]] = []
		_remates_por_estilo[r["estilo"]].append(r)

## Donde tiene que estar la raiz para que el pie de este remate le pegue a la pelota.
func _raiz_para(remate: Dictionary) -> Vector3:
	var dedo := PesAnimaciones.v3(remate["dedo"])
	var dir := Vector3(remate["dir_pie"][0], 0.0, remate["dir_pie"][2]).normalized()
	var raiz := ball.global_position - dedo - dir * toe_to_ball
	raiz.y = 0.0
	return raiz

## Se para donde arranca la carrera, con la postura de espera del penal. Todavia
## no se sabe a donde va a patear: se usa un remate del estilo como referencia y
## al soltar el tiro se ajusta lo poco que falte (_jugar_remate).
func _preparar_pes() -> void:
	# La reaccion del tiro anterior lo pudo haber dejado girado.
	# Se elige antes de saber como va a patear: tiene que tener de los dos tipos.
	_estilo = _remates_por_estilo.keys().filter(func(e: String): return _remates_por_estilo[e].any(func(r: Dictionary): return r["lob"])).pick_random()
	_remate = {}
	_reaccion = ""
	var referencia: Dictionary = _remates_por_estilo[_estilo][0]
	var espera := "pes/" + str(PesAnimaciones.datos()["esperas_pateador"].pick_random())
	# Sin fundido: se ve recien cuando se va el negro entre tiros, ya en su lugar.
	animation_player.speed_scale = 1.0
	animation_player.play(espera, 0.0)
	animation_player.seek(0.0, true)
	# Espera mirando hacia la pelota, sobre la linea de su carrera.
	var desde_golpe := PesAnimaciones.v3(referencia["cadera_inicio"]) - PesAnimaciones.v3(referencia["dedo"])
	global_basis = Basis(Vector3.UP, atan2(desde_golpe.x, desde_golpe.z)) * _base_basis
	global_position = _raiz_para(referencia)
	var cadera_espera := PesAnimaciones.cadera_en(animation_player, skeleton, self, espera, 0.0)
	var desfase := PesAnimaciones.v3(referencia["cadera_inicio"]) - cadera_espera
	desfase.y = 0.0
	global_position += desfase

## Elige el golpe segun el tiro: el pie sale hacia donde va la pelota y la potencia
## se parece a la pedida. Un tiro alto o fuerte va de empeine; uno bajo y suave,
## colocado con la cara interna.
func _elegir_remate() -> void:
	var hacia := Vector3(final_target.x, 0.0, goal_z_position) - ball.global_position
	hacia.y = 0.0
	hacia = hacia.normalized()
	var colocado := final_target.y < 1.2 and final_power / max_power < 0.7
	var potencia := "long" if final_power / max_power >= 0.55 else "mid"
	var mejor_costo := INF
	var costos := {}
	for r: Dictionary in _remates_por_estilo[_estilo]:
		if r["lob"] != _picada:
			continue
		var dir := Vector3(r["dir_pie"][0], 0.0, r["dir_pie"][2]).normalized()
		var costo := dir.angle_to(hacia)
		if not _picada:
			costo += 0.0 if r["potencia"] == potencia else 0.2
			costo += 0.15 if (r["metodo"] == "inside") != colocado else 0.0
		costos[r] = costo
		mejor_costo = minf(mejor_costo, costo)
	var margen := MARGEN_VARIEDAD_PICADA if _picada else MARGEN_VARIEDAD_REMATE
	var parecidos: Array = costos.keys().filter(func(r: Dictionary): return costos[r] <= mejor_costo + margen and (not _picada or r["anim"] != _ultima_picada))
	_remate = parecidos.pick_random() if not parecidos.is_empty() else costos.keys().pick_random()
	if _picada:
		_ultima_picada = _remate["anim"]
	# Un cuadro antes del golpe exacto: el pie va a 20 m/s (33 cm por cuadro) y la
	# comprobacion recien se entera despues de que paso ese momento.
	kick_contact_time = float(_remate["t"]) - 1.0 / 60.0
	_inicio_remate = _remate["inicio"]

func _jugar_remate() -> void:
	const FUNDIDO := 0.35
	var raiz := Transform3D(_base_basis, _raiz_para(_remate))
	PesAnimaciones.transicion(self, animation_player, skeleton, raiz, "pes/" + str(_remate["anim"]), _inicio_remate, FUNDIDO)
	animation_player.speed_scale = _velocidad_carrera(kick_contact_time - _inicio_remate)

## La carrera se ve tranquila: va mas lenta que el clip y acelera hasta la velocidad
## normal justo antes del golpe. falta: segundos de clip hasta el golpe.
func _velocidad_carrera(falta: float) -> float:
	var hecho := kick_contact_time - _inicio_remate - falta
	var arranque := lerpf(VELOCIDAD_ARRANQUE, 1.0, clampf(hecho / ARRANQUE_CARRERA, 0.0, 1.0))
	return lerpf(1.0, VELOCIDAD_CARRERA, clampf((falta - 0.1) / 0.4, 0.0, 1.0)) * arranque

## Segundos reales que tarda en recorrer esos segundos de clip.
func _duracion_carrera(falta: float) -> float:
	const PASO := 1.0 / 120.0
	var total := 0.0
	while falta > 0.0:
		total += PASO
		falta -= PASO * _velocidad_carrera(falta)
	return total

## El GameManager avisa como termino el tiro: festeja o se lamenta.
func reaccionar(gol: bool) -> void:
	if _pes and not _remate.is_empty() and _reaccion == "":
		_reaccion = "gol" if gol else "fallo"

func _seguir_reaccion() -> void:
	var sig: Dictionary = _remate["sig"][_reaccion]
	var en_remate: bool = animation_player.current_animation == "pes/" + str(_remate["anim"])
	if en_remate and animation_player.is_playing() and animation_player.current_animation_position < float(sig["t_salto"]):
		return
	_reaccion = "hecha"
	PesAnimaciones.empalmar(self, animation_player, skeleton, "pes/" + str(sig["anim"]), sig["t_inicio"], 0.3)

## Se termino el remate o la reaccion y la jugada sigue en pantalla: se queda parado.
func _al_terminar_animacion(_nombre: StringName) -> void:
	if not en_cinematica and not _remate.is_empty() and (current_state == KickState.KICK_CONTACT or current_state == KickState.FOLLOW_THROUGH):
		PesAnimaciones.empalmar(self, animation_player, skeleton, "pes/pk_idle", 0.0, 0.5)

## Poses the kick animation at kick_contact_time and reads where the kicking
## toe is. The ball has to be there (plus toe_to_ball forward), so before every
## shot the kicker stands at ball - offset and the foot goes right through it.
func _measure_contact_offset():
	if not animation_player or not skeleton:
		return
	var kick_anim := _kick_animation_name()
	if kick_anim == "":
		return
	animation_player.play(kick_anim)
	animation_player.seek(kick_contact_time, true)
	skeleton.force_update_all_bone_transforms()
	var toe := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig1RightToeBase")).origin
	var forward := -global_transform.basis.z
	_contact_offset = global_transform.basis.inverse() * (toe - global_position + forward * toe_to_ball)
	_contact_offset.y = 0.0
	animation_player.stop()

## Stands the kicker so the kick animation hits the ball.
func _place_behind_ball():
	if ball and _contact_offset != Vector3.ZERO:
		global_position = ball.global_position - global_transform.basis * _contact_offset
		global_position.y = 0.0

func _find_skeleton_and_anim_player():
	if not skeleton:
		skeleton = _find_node_of_type(self, "Skeleton3D") as Skeleton3D
	if not animation_player:
		animation_player = _find_node_of_type(self, "AnimationPlayer") as AnimationPlayer

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _process(delta: float):
	match current_state:
		KickState.AIMING:
			_process_aiming(delta)
		KickState.CHARGING:
			_process_charging(delta)
		KickState.RUN_UP:
			_process_run_up(delta)
		KickState.KICK_CONTACT:
			if animation_player and not animation_player.is_playing():
				notify_follow_through()
	if (_reaccion == "gol" or _reaccion == "fallo") and not en_cinematica:
		_seguir_reaccion()

func start_aiming(es_automatico: bool = false):
	en_cinematica = false
	automatico = es_automatico
	current_state = KickState.AIMING
	if not _pes:
		_place_behind_ball()
	_smooth_aim = Vector2.ZERO
	power = 0.0
	_picada = false
	_last_shot_data = null
	if _pes:
		_preparar_pes()
	else:
		play_idle()

func _process_aiming(delta: float):
	if automatico:
		return
	var input := Input.get_vector("move_left", "move_right", "move_down", "move_up")

	# Smooth aim follows input with momentum
	_smooth_aim = _smooth_aim.lerp(input, aim_smooth_speed * delta)

	# Centering force: pull back to center when stick released
	if input.length() < 0.15:
		_smooth_aim = _smooth_aim.lerp(Vector2.ZERO, aim_center_pull * delta)

	# Edge instability: harder to hold at extremes
	if _smooth_aim.length() > aim_edge_threshold:
		var edge := _smooth_aim.length()
		var wobble := randf_range(-aim_edge_instability, aim_edge_instability) * (edge - aim_edge_threshold) * 2.0
		_smooth_aim += _smooth_aim.orthogonal() * wobble

	_smooth_aim = _smooth_aim.limit_length(1.0)
	aim_target_3d = _aim_to_goal_position(_smooth_aim)

	if Input.is_action_just_pressed("kick_charge"):
		start_charging()

func _process_charging(delta: float):
	if automatico:
		return
	var input := Input.get_vector("move_left", "move_right", "move_down", "move_up")

	# Same smooth aim, but more instability at high power
	_smooth_aim = _smooth_aim.lerp(input, aim_smooth_speed * delta)

	if input.length() < 0.15:
		_smooth_aim = _smooth_aim.lerp(Vector2.ZERO, aim_center_pull * delta)

	var power_ratio := power / max_power
	if _smooth_aim.length() > aim_edge_threshold:
		var edge := _smooth_aim.length()
		var extra_wobble := 1.0 + power_ratio * 2.0
		var wobble := randf_range(-aim_edge_instability, aim_edge_instability) * (edge - aim_edge_threshold) * extra_wobble
		_smooth_aim += _smooth_aim.orthogonal() * wobble

	_smooth_aim = _smooth_aim.limit_length(1.0)
	aim_target_3d = _aim_to_goal_position(_smooth_aim)

	# Solo sube: si te pasas se queda al maximo (y el tiro se va, ver _release_kick).
	power = minf(power + power_speed * max_power * delta, max_power)

	if Input.is_action_just_released("kick_charge"):
		_release_kick()

func _release_kick(picada: bool = Input.is_action_pressed("kick_picar")):
	_picada = picada
	final_power = power
	final_target = aim_target_3d

	if final_power > 95.0:
		var overshoot = (final_power - 95.0) / 5.0
		final_target += Vector3(
			randf_range(-1.0, 1.0) * overshoot * 4.0,
			randf_range(-0.5, 1.0) * overshoot * 2.0,
			0.0
		)

	current_state = KickState.RUN_UP
	run_up_timer = 0.0
	is_kick_complete = false
	if _pes:
		_elegir_remate()

	kick_connecting.emit(final_power, final_target)


## El rival patea: el tiro ya viene elegido por el GameManager. Se saltea la
## carga y arranca la carrera como si el jugador hubiera soltado el tiro.
func patear_automatico(objetivo: Vector3, potencia: float, picada: bool = false) -> void:
	if current_state != KickState.AIMING:
		return
	_picada = picada
	final_target = objetivo
	final_power = clampf(potencia, 0.0, max_power)
	_smooth_aim = Vector2(
		clampf(objetivo.x / aim_horizontal_range, -1.0, 1.0),
		clampf(inverse_lerp(min_aim_goal_height, max_aim_goal_height, objetivo.y), -1.0, 1.0)
	)
	aim_target_3d = objetivo

	current_state = KickState.RUN_UP
	run_up_timer = 0.0
	is_kick_complete = false
	if _pes:
		_elegir_remate()

	kick_connecting.emit(final_power, final_target)

func _process_run_up(delta: float):
	run_up_timer += delta
	if run_up_timer >= run_up_duration and not is_kick_complete:
		is_kick_complete = true
		play_kick()
		if use_kick_ik:
			_enable_kick_ik()

	if _pes and is_kick_complete:
		animation_player.speed_scale = _velocidad_carrera(kick_contact_time - animation_player.current_animation_position)
	_check_animation_contact()

func _check_animation_contact():
	if is_kick_complete and current_state != KickState.KICK_CONTACT and current_state != KickState.FOLLOW_THROUGH:
		if animation_player and animation_player.is_playing():
			if animation_player.current_animation_position >= kick_contact_time:
				notify_animation_contact()

func notify_animation_contact():
	if current_state != KickState.KICK_CONTACT:
		current_state = KickState.KICK_CONTACT
		animation_player.speed_scale = 1.0
		_update_kick_foot_ik_target()

		var ball_pos = _get_ball_world_position()
		var power_ratio = final_power / max_power
		var velocity = _calculate_ball_velocity()

		_last_shot_data = ShotData.new(ball_pos, velocity, power_ratio, 0.0)
		shot_taken.emit(_last_shot_data)
		ball_launch_requested.emit(velocity)

func notify_follow_through():
	current_state = KickState.FOLLOW_THROUGH
	disable_all_ik()

func _aim_to_goal_position(analog_input: Vector2) -> Vector3:
	var x = analog_input.x * aim_horizontal_range
	var y = clamp(remap(analog_input.y, -1.0, 1.0, min_aim_goal_height, max_aim_goal_height), 0.0, max_aim_goal_height)
	return Vector3(x, y, 0.0)

func _setup_ik():
	if not skeleton:
		push_warning("PlayerKicker: Skeleton3D not found. IK disabled.")
		return
	if plant_foot_ik:
		if plant_foot_ik.setting_count < 1:
			plant_foot_ik.setting_count = 1
		plant_foot_ik.set_root_bone_name(0, plant_leg_bone)
		plant_foot_ik.set_middle_bone_name(0, plant_knee_bone)
		plant_foot_ik.set_end_bone_name(0, plant_foot_bone)
		plant_foot_ik.influence = 1.0
		plant_foot_ik.active = false
		if plant_foot_target:
			plant_foot_ik.set_target_node(0, plant_foot_ik.get_path_to(plant_foot_target))

	if kick_foot_ik:
		if kick_foot_ik.setting_count < 1:
			kick_foot_ik.setting_count = 1
		kick_foot_ik.set_root_bone_name(0, kick_leg_bone)
		kick_foot_ik.set_middle_bone_name(0, kick_knee_bone)
		kick_foot_ik.set_end_bone_name(0, kick_foot_bone)
		kick_foot_ik.influence = 1.0
		kick_foot_ik.active = false
		if kick_foot_target:
			kick_foot_ik.set_target_node(0, kick_foot_ik.get_path_to(kick_foot_target))

func _enable_kick_ik():
	if not skeleton:
		return
	var bone_idx = skeleton.find_bone(plant_foot_bone)
	if bone_idx >= 0:
		plant_foot_world_pos = skeleton.to_global(skeleton.get_bone_global_pose(bone_idx).origin)
	if plant_foot_ik and plant_foot_target:
		plant_foot_target.global_position = plant_foot_world_pos
		plant_foot_ik.active = true
	if kick_foot_ik and kick_foot_target:
		kick_foot_ik.active = true

func _update_kick_foot_ik_target():
	if not kick_foot_target:
		return
	var ball_pos = _get_ball_world_position()
	kick_foot_target.global_position = ball_pos

func _calculate_ball_velocity() -> Vector3:
	var power_ratio = final_power / max_power
	var ball_pos = _get_ball_world_position()
	if _picada:
		return _velocidad_picada(ball_pos, power_ratio)
	var target_world = Vector3(final_target.x, final_target.y, goal_z_position)
	var direction = (target_world - ball_pos).normalized()
	var speed = 15.0 + power_ratio * 25.0
	var distance = ball_pos.distance_to(target_world)
	var flight_time = distance / speed
	var gravity = 9.8
	var height_diff = target_world.y - ball_pos.y
	var vy_needed = (height_diff + 0.5 * gravity * flight_time * flight_time) / flight_time
	var velocity = direction * speed
	velocity.y = vy_needed * power_ratio + 2.0 * (1.0 - power_ratio)
	return velocity

## Globo lento que baja hacia donde se apunto, cruzando la linea a esa altura. Mas
## potencia lo hace llegar antes, pero sigue siendo lento.
func _velocidad_picada(ball_pos: Vector3, power_ratio: float) -> Vector3:
	var t := lerpf(VUELO_PICADA_LENTA, VUELO_PICADA_RAPIDA, power_ratio)
	var hacia := Vector3(final_target.x, maxf(final_target.y, ALTURA_MINIMA_PICADA), PredictionModule.Z_GOAL) - ball_pos
	return Vector3(hacia.x / t, (hacia.y + 0.5 * PredictionModule.GRAVITY * t * t) / t, hacia.z / t)

func es_picada() -> bool:
	return _picada

func disable_all_ik():
	if plant_foot_ik:
		plant_foot_ik.active = false
	if kick_foot_ik:
		kick_foot_ik.active = false

func _get_ball_world_position() -> Vector3:
	if not ball:
		var root = owner if owner else get_tree().root
		ball = _find_node_of_type(root, "SoccerBall") as SoccerBall
	if ball:
		return ball.global_position
	return global_position + Vector3(0, 0, -2.0)

func play_idle():
	if animation_player and animation_player.has_animation("Offensiveidle"):
		animation_player.play("Offensiveidle")

func _kick_animation_name() -> String:
	if animation_player.has_animation("Soccerpenaltykick"):
		return "Soccerpenaltykick"
	elif final_target.x < -0.5 and animation_player.has_animation("Kicksoccerball"):
		return "Kicksoccerball"
	elif final_target.x > 0.5 and animation_player.has_animation("Kicksoccerball(2)"):
		return "Kicksoccerball(2)"
	elif animation_player.has_animation("Kicksoccerball"):
		return "Kicksoccerball"
	return ""

## Seconds from now until the foot hits the ball (pause + kick animation up to
## kick_contact_time). Used by the goalkeeper to start moving
## before the kick, like a real keeper reading the shooter.
func seconds_until_contact() -> float:
	if current_state == KickState.RUN_UP:
		if not is_kick_complete:
			if _pes:
				return maxf(0.0, run_up_duration - run_up_timer) + _duracion_carrera(kick_contact_time - _inicio_remate)
			return maxf(0.0, run_up_duration - run_up_timer) + kick_contact_time
		if animation_player:
			var falta := maxf(0.0, kick_contact_time - animation_player.current_animation_position)
			return _duracion_carrera(falta) if _pes else falta
	return 0.0

## Velocity the ball will get when kicked. Already fixed once the kick is
## released (final_power and final_target don't change during the run-up).
func shot_velocity() -> Vector3:
	return _calculate_ball_velocity()

func play_kick():
	if not animation_player:
		return
	if _pes:
		_jugar_remate()
		return
	var kick_anim := _kick_animation_name()

	if kick_anim != "":
		animation_player.play(kick_anim, 0.15)
	else:
		notify_animation_contact()

func start_charging():
	current_state = KickState.CHARGING
	power = 0.0

func get_current_aim() -> Vector3:
	return aim_target_3d

func get_power() -> float:
	return power

func get_power_percent() -> float:
	return power / max_power

func get_final_power() -> float:
	return final_power

func get_final_target() -> Vector3:
	return final_target

func is_optimal_power() -> bool:
	return final_power >= optimal_power_min and final_power <= optimal_power_max
