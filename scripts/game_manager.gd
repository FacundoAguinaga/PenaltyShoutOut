extends Node3D
class_name GameManager

const DepurarAnimaciones := preload("res://scripts/depurar_animaciones.gd")
const Cinematicas := preload("res://scripts/cinematicas.gd")

enum PenaltyState {
	IDLE,
	AIMING,
	BALL_FLYING,
	RESULT
}

## Lado que patea en cada turno de la tanda.
enum Lado {
	JUGADOR,
	RIVAL
}

@export var kicker: PlayerKicker
@export var goalkeeper: PlayerGoalkeeper
@export var ball: SoccerBall
@export var goal_zone: GoalZone

@export var kicker_start_position: Marker3D
@export var goalkeeper_start_position: Marker3D
@export var ball_spawn_position: Marker3D
@export var sound_manager: Node

@export_group("Game Settings")
## Rondas reglamentarias: una por cada pateador de cada lado (5 = tanda real).
@export var shots_per_round: int = 5
@export var turn_timeout: float = 30.0
## Dibuja un rectangulo rojo en la boca del arco para verificar la alineacion.
## Solo para debug: tapa la vista del arco durante el juego.
@export var show_debug_goal: bool = false

@export_group("Tanda")
## Cuanto espera el rival antes de patear: le da tiempo al jugador a acomodar
## al arquero y elegir el lado.
@export var espera_tiro_rival: float = 2.2
## Probabilidad de que el rival intente una vaselina.
@export var prob_picada_rival: float = 0.05
## Probabilidad de que el rival la mande afuera (para que no sea un robot).
@export var prob_fuera_rival: float = 0.08
## Potencia del rival (0-100).
@export var potencia_rival: Vector2 = Vector2(52.0, 94.0)

var current_state: PenaltyState = PenaltyState.IDLE

# ---------------------------------------------------------------- marcador
## Goles del equipo del jugador y del rival. Se mantienen los nombres viejos
## (kicker_score/goalkeeper_score) porque los usan las cinematicas y el final.
var kicker_score: int = 0
var goalkeeper_score: int = 0
var goles_jugador: int = 0
var goles_rival: int = 0
var tiros_jugador: int = 0
var tiros_rival: int = 0
var resultados_jugador: Array[String] = []
var resultados_rival: Array[String] = []
var turno: Lado = Lado.JUGADOR
var tanda_terminada: bool = false
## Total de tiros ejecutados + 1, para el HUD y los logs.
var current_shot: int = 0
## Equipacion del pateador y del arquero de este turno ("rojo"/"azul").
var equipo_pateador: String = "rojo"
var equipo_arquero: String = "azul"

var _shot_resolved: bool = false
var _shot_timeout_timer: SceneTreeTimer
var _turno_id: int = 0
var _esperando_tiro_rival: bool = false
var _pateador_turno: Dictionary = {}
var _indice_pateador_jugador: int = 0
var _indice_pateador_rival: int = 0
var _mat_arquero_local: StandardMaterial3D
var _mat_arquero_rival: StandardMaterial3D

## Cada equipo tiene cinco pateadores con distinta piel/pelo. Los kits ya
## existen en Player/kits (rojo/azul + variantes moreno/rubio/canela).
const PLANTEL_JUGADOR := [
	{"nombre": "ACOSTA", "kit": "rojo"},
	{"nombre": "BENÍTEZ", "kit": "rojo_moreno"},
	{"nombre": "CARRIZO", "kit": "rojo_rubio"},
	{"nombre": "DÍAZ", "kit": "rojo_canela"},
	{"nombre": "ESCOBAR", "kit": "rojo"},
]
const PLANTEL_RIVAL := [
	{"nombre": "MOLINA", "kit": "azul"},
	{"nombre": "SOSA", "kit": "azul_moreno"},
	{"nombre": "PERALTA", "kit": "azul_rubio"},
	{"nombre": "VIDAL", "kit": "azul_canela"},
	{"nombre": "LUNA", "kit": "azul"},
]

signal penalty_started
signal kick_released(power: float, kick_target: Vector3)
signal ball_hit(velocity: Vector3)
signal goal_scored(kicker_name: String)
signal ball_saved
signal ball_missed
signal ball_deflected
signal shot_complete(result: String)
signal tanda_actualizada
signal game_over(kicker_score: int, goalkeeper_score: int, total_shots: int)

func _ready():
	_apply_settings()
	_auto_discover_nodes()
	_connect_signals()
	_apply_goalkeeper_difficulty()
	if kicker and goalkeeper:
		add_child(DepurarAnimaciones.new(kicker, goalkeeper, self))
		_cinematicas = Cinematicas.new(self, kicker, goalkeeper, get_node("Camera3D"))
		add_child(_cinematicas)
		var intro := get_node_or_null("CinematicIntro")
		if intro:
			intro.intro_finished.connect(_cinematicas.jugar_previa, CONNECT_ONE_SHOT)
	if show_debug_goal:
		_draw_debug_goal()
	_reset_tanda()
	start_penalty()

func _apply_settings():
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		shots_per_round = maxi(1, settings.shots_per_round)

func _apply_goalkeeper_difficulty():
	var settings = get_node_or_null("/root/SettingsManager")
	if settings and goalkeeper:
		var res_path = settings.get_difficulty_resource_path()
		if ResourceLoader.exists(res_path):
			var stats_res = load(res_path) as GoalkeeperStats
			if stats_res:
				goalkeeper.stats = stats_res
				print("[GameManager] Applied GK difficulty: %s" % settings.get_difficulty_name())

func _draw_debug_goal():
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(7.32, 2.44, 0.1) # Goal width, height, thickness
	mesh_instance.mesh = mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 0.5) # Red semi-transparent
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.flags_unshaded = true
	mesh.surface_set_material(0, mat)

	add_child(mesh_instance)
	# Center of the goal. The bottom is at y=0, so center is at y=2.44/2 = 1.22
	mesh_instance.global_position = Vector3(0, 1.22, -12.0)

func _auto_discover_nodes():
	if not kicker:
		kicker = _find_node_by_type(self, PlayerKicker) as PlayerKicker
	if not goalkeeper:
		goalkeeper = _find_node_by_type(self, PlayerGoalkeeper) as PlayerGoalkeeper
	if not ball:
		ball = _find_node_by_type(self, SoccerBall) as SoccerBall
	if not goal_zone:
		goal_zone = get_node_or_null("World/GoalZone") as GoalZone
	if not goal_zone:
		goal_zone = _find_node_by_type(self, GoalZone) as GoalZone
	if not sound_manager:
		sound_manager = get_node_or_null("/root/SoundManager")
		if not sound_manager:
			sound_manager = get_node_or_null("SoundManager")

func _find_node_by_type(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found = _find_node_by_type(child, type)
		if found:
			return found
	return null

func _connect_signals():
	if kicker:
		kicker.kick_connecting.connect(_on_kick_connecting)
		kicker.ball_launch_requested.connect(_on_ball_launch_requested)

	if ball:
		ball.ball_stopped.connect(_on_ball_stopped)
		if ball.has_signal("crossed_goal_line"):
			ball.crossed_goal_line.connect(_on_ball_crossed_goal_line)
		if ball.has_signal("impacto"):
			ball.impacto.connect(func(tipo: String, fuerza: float):
				if sound_manager and sound_manager.has_method("play_impacto"):
					sound_manager.play_impacto(tipo, fuerza))

	if goal_zone:
		goal_zone.goal_detected.connect(_on_goal_detected)

	if goalkeeper:
		goalkeeper.keeper_save.connect(_on_keeper_save)
		goalkeeper.keeper_deflect.connect(_on_keeper_deflect)

		if goalkeeper and ball:
			ball.shot_taken.connect(goalkeeper.on_ball_kicked)

# --------------------------------------------------------------- tanda

func _reset_tanda() -> void:
	kicker_score = 0
	goalkeeper_score = 0
	goles_jugador = 0
	goles_rival = 0
	tiros_jugador = 0
	tiros_rival = 0
	resultados_jugador.clear()
	resultados_rival.clear()
	turno = Lado.JUGADOR
	tanda_terminada = false
	current_shot = 0
	_shot_resolved = false
	_esperando_tiro_rival = false
	_pateador_turno = {}
	_indice_pateador_jugador = 0
	_indice_pateador_rival = 0
	equipo_pateador = "rojo"
	equipo_arquero = "azul"

## Arranca (o reinicia) la tanda desde el primer turno.
func start_penalty():
	_iniciar_turno()

func _iniciar_turno():
	if tanda_terminada:
		return
	current_state = PenaltyState.AIMING
	current_shot = tiros_jugador + tiros_rival + 1
	_shot_resolved = false
	_esperando_tiro_rival = false
	_turno_id += 1

	equipo_pateador = "rojo" if turno == Lado.JUGADOR else "azul"
	equipo_arquero = "azul" if turno == Lado.JUGADOR else "rojo"
	_elegir_pateador_del_turno()
	_equipar_pateador()
	_equipar_arquero()

	reset_positions()
	if _cinematicas:
		_cinematicas.limpiar()

	if turno == Lado.JUGADOR:
		# El jugador patea contra el arquero de la IA.
		if goalkeeper:
			goalkeeper.control_humano = false
			goalkeeper.reset_to_idle()
		if kicker:
			kicker.start_aiming(false)
	else:
		# Patea el rival: el jugador ataja.
		if kicker:
			kicker.start_aiming(true)
		if goalkeeper:
			goalkeeper.iniciar_control_humano()
		_programar_tiro_rival(_turno_id)

	penalty_started.emit()
	tanda_actualizada.emit()
	print("[GameManager] Turno %d: %s patea (%s) | %d-%d" % [
		current_shot, _pateador_turno.get("nombre", "?"), Lado.keys()[turno],
		goles_jugador, goles_rival])

## El rival no tira enseguida: deja pasar un momento para que el jugador
## acomode al arquero y elija el lado. Cuando patea, la estirada reacciona
## recien al contacto con la pelota.
func _programar_tiro_rival(id: int) -> void:
	_esperando_tiro_rival = true
	await get_tree().create_timer(espera_tiro_rival).timeout
	if not is_inside_tree() or tanda_terminada:
		return
	if id != _turno_id or turno != Lado.RIVAL or current_state != PenaltyState.AIMING:
		return
	_esperando_tiro_rival = false
	if not kicker:
		return
	var potencia := randf_range(potencia_rival.x, potencia_rival.y)
	var picada := randf() < prob_picada_rival
	kicker.patear_automatico(_objetivo_rival(), potencia, picada)

## Apunta a una zona razonable del arco. Casi siempre adentro; a veces busca el
## palo, a veces el centro y muy de vez en cuando la manda afuera.
func _objetivo_rival() -> Vector3:
	if randf() < prob_fuera_rival:
		var lado_fuera := -1.0 if randf() < 0.5 else 1.0
		return Vector3(lado_fuera * randf_range(3.95, 4.3), randf_range(0.4, 2.2), 0.0)

	var x := randf_range(-3.2, 3.2)
	if randf() < 0.68:
		# La mayoria de los penales van a un costado.
		x = randf_range(1.35, 3.2) * (-1.0 if randf() < 0.5 else 1.0)
	var y := randf_range(0.3, 2.15)
	if randf() < 0.35:
		y = randf_range(1.5, 2.15)
	return Vector3(x, y, 0.0)

func _elegir_pateador_del_turno() -> void:
	if turno == Lado.JUGADOR:
		_pateador_turno = PLANTEL_JUGADOR[_indice_pateador_jugador % PLANTEL_JUGADOR.size()]
		_indice_pateador_jugador += 1
	else:
		_pateador_turno = PLANTEL_RIVAL[_indice_pateador_rival % PLANTEL_RIVAL.size()]
		_indice_pateador_rival += 1

func _malla_pateador() -> MeshInstance3D:
	if not kicker:
		return null
	return kicker.get_node_or_null("player2/Node/Skeleton3D/Ch36") as MeshInstance3D

func _malla_arquero() -> MeshInstance3D:
	if not goalkeeper:
		return null
	return goalkeeper.get_node_or_null("player/Node/Skeleton3D/Ch36") as MeshInstance3D

## Le pone al modelo del pateador el kit/piel del companero que le toca.
func _equipar_pateador() -> void:
	var malla := _malla_pateador()
	if not malla:
		return
	var kit := str(_pateador_turno.get("kit", "rojo"))
	var path := "res://Player/kits/material_%s.tres" % kit
	if ResourceLoader.exists(path):
		malla.set_surface_override_material(0, load(path))

## El arquero del rival se ve azulado; el del jugador mantiene el kit de arquero.
func _equipar_arquero() -> void:
	var malla := _malla_arquero()
	if not malla:
		return
	if _mat_arquero_local == null:
		var base := load("res://Player/kits/material_arquero.tres") as StandardMaterial3D
		if base:
			_mat_arquero_local = base.duplicate() as StandardMaterial3D
			_mat_arquero_rival = base.duplicate() as StandardMaterial3D
			_mat_arquero_rival.albedo_color = Color(0.62, 0.76, 1.0)
	if _mat_arquero_local == null:
		return
	malla.set_surface_override_material(0, _mat_arquero_local if equipo_arquero == "rojo" else _mat_arquero_rival)

func nombre_pateador_actual() -> String:
	return str(_pateador_turno.get("nombre", ""))

func plantel_del_turno() -> Array:
	return PLANTEL_JUGADOR if turno == Lado.JUGADOR else PLANTEL_RIVAL

## Indice (0-4) del companero que esta pateando ahora, para resaltarlo en la fila.
func indice_pateador_actual() -> int:
	var plantel := plantel_del_turno()
	var i := _indice_pateador_jugador if turno == Lado.JUGADOR else _indice_pateador_rival
	return posmod(i - 1, plantel.size())

func nombre_siguiente_pateador() -> String:
	var plantel := PLANTEL_JUGADOR if turno == Lado.JUGADOR else PLANTEL_RIVAL
	var idx := _indice_pateador_jugador if turno == Lado.JUGADOR else _indice_pateador_rival
	return str(plantel[idx % plantel.size()]["nombre"])

func en_muerte_subita() -> bool:
	return tiros_jugador >= shots_per_round and tiros_rival >= shots_per_round

func texto_ronda() -> String:
	if en_muerte_subita():
		var n := maxi(1, mini(tiros_jugador, tiros_rival) - shots_per_round + 1)
		return "MUERTE SÚBITA %d" % n
	var ronda := tiros_jugador
	if current_state != PenaltyState.RESULT and turno == Lado.JUGADOR:
		ronda += 1
	return "RONDA %d / %d" % [mini(maxi(1, ronda), shots_per_round), shots_per_round]

## La tanda se define cuando un equipo ya no puede alcanzar al otro, o cuando
## en muerte subita ambos tiraron y quedaron distintos.
func _tanda_decidida() -> bool:
	if tiros_jugador < shots_per_round or tiros_rival < shots_per_round:
		var restantes_j := maxi(0, shots_per_round - tiros_jugador)
		var restantes_r := maxi(0, shots_per_round - tiros_rival)
		if goles_jugador > goles_rival + restantes_r:
			return true
		if goles_rival > goles_jugador + restantes_j:
			return true
		return false
	if tiros_jugador == tiros_rival:
		return goles_jugador != goles_rival
	return false

func reset_positions():
	if kicker and kicker_start_position:
		kicker.global_position = kicker_start_position.global_position
	if goalkeeper and goalkeeper_start_position:
		goalkeeper.global_position = goalkeeper_start_position.global_position
	if ball and ball_spawn_position:
		ball.reset_to(ball_spawn_position.global_position)

func _on_kick_connecting(power: float, kick_target: Vector3):
	kick_released.emit(power, kick_target)
	if sound_manager and sound_manager.has_method("play_anticipation"):
		sound_manager.play_anticipation()
	# El arquero de la IA empieza a leer el tiro cuando arranca la carrera.
	# Con control humano no se le sopla nada: decide el jugador.
	if goalkeeper and kicker and ball and goalkeeper.control_humano:
		goalkeeper.bloquear_movimiento_humano()
	elif goalkeeper and kicker and ball and goalkeeper.has_method("anticipar"):
		goalkeeper.anticipar(ball.global_position, kicker.shot_velocity(), kicker.seconds_until_contact(), kicker.es_picada())

func _on_ball_launch_requested(velocity: Vector3):
	if ball:
		ball.kick(velocity, kicker != null and kicker.es_picada())
	if sound_manager and sound_manager.has_method("play_kick"):
		sound_manager.play_kick(velocity.length())
	current_state = PenaltyState.BALL_FLYING
	_shot_resolved = false
	ball_hit.emit(velocity)

	# Fail-safe timeout: resolve shot if unresolved after 4.5 seconds
	_start_shot_timeout_failsafe()

func _start_shot_timeout_failsafe():
	var shot_id = current_shot
	await get_tree().create_timer(4.5).timeout
	if current_shot == shot_id and not _shot_resolved and current_state == PenaltyState.BALL_FLYING:
		print("[GameManager] Fail-safe timeout: Shot unresolved after 4.5s. Resolving as MISS.")
		_on_ball_stopped()

# ------------------------------------------------------------ resolucion

func _registrar_resultado(resultado: String) -> void:
	var gol := resultado == "goal"
	if turno == Lado.JUGADOR:
		resultados_jugador.append(resultado)
		tiros_jugador += 1
		if gol:
			goles_jugador += 1
	else:
		resultados_rival.append(resultado)
		tiros_rival += 1
		if gol:
			goles_rival += 1
	# Compatibilidad con las cinematicas y el final.
	kicker_score = goles_jugador
	goalkeeper_score = goles_rival
	tanda_actualizada.emit()

func _on_keeper_save(ball_hit_ref: SoccerBall):
	if _shot_resolved or current_state != PenaltyState.BALL_FLYING:
		return
	_shot_resolved = true
	current_state = PenaltyState.RESULT
	_registrar_resultado("save")
	if sound_manager and sound_manager.has_method("play_save"):
		# El arquero avisa igual si la agarra o la rechaza; ya sabe cual fue.
		sound_manager.play_save(goalkeeper == null or goalkeeper.get("_agarrada") != false)
	ball_saved.emit()
	shot_complete.emit("save")
	if kicker:
		kicker.reaccionar(false)
	print("[GameManager] SAVE! Hand collision detected")
	_next_shot("save")

func _on_keeper_deflect(ball_hit_ref: SoccerBall):
	if current_state != PenaltyState.BALL_FLYING:
		return
	if sound_manager and sound_manager.has_method("play_save"):
		sound_manager.play_save(false)
	ball_deflected.emit()
	print("[GameManager] DEFLECTED! Body collision")

func _on_ball_crossed_goal_line(pos: Vector3):
	if _shot_resolved or current_state != PenaltyState.BALL_FLYING:
		return
	# Check if inside goal frame bounds (Width: 7.32 -> [-3.66, 3.66], Height: 2.44 -> [0.0, 2.44])
	if abs(pos.x) <= 3.7 and pos.y >= -0.1 and pos.y <= 2.5:
		print("[GameManager] GOAL detected via goal line crossing fail-safe!")
		_on_goal_detected()

func _on_goal_detected():
	if _shot_resolved or current_state != PenaltyState.BALL_FLYING:
		return
	_shot_resolved = true
	current_state = PenaltyState.RESULT
	_registrar_resultado("goal")
	if sound_manager and sound_manager.has_method("play_goal"):
		sound_manager.play_goal()
	goal_scored.emit(nombre_pateador_actual())
	if kicker:
		kicker.reaccionar(true)
	get_tree().call_group("crowd_clusters", "celebrate_goal", 5.0)
	shot_complete.emit("goal")
	print("[GameManager] GOAL!")
	_next_shot("goal")

func _on_ball_stopped():
	if _shot_resolved or current_state != PenaltyState.BALL_FLYING:
		return
	_shot_resolved = true
	current_state = PenaltyState.RESULT
	_registrar_resultado("miss")
	if sound_manager and sound_manager.has_method("play_miss"):
		sound_manager.play_miss()
	ball_missed.emit()
	shot_complete.emit("miss")
	if kicker:
		kicker.reaccionar(false)
	print("[GameManager] MISS! Ball stopped outside goal")
	_next_shot("miss")

const FUNDIDO_ENTRE_TIROS := 0.3
const NEGRO_ENTRE_TIROS := 0.15

## La cinematica de la jugada dura hasta el proximo turno.
func _next_shot(resultado: String):
	if _cinematicas:
		await _cinematicas.jugar(resultado)
	if not is_inside_tree():
		return

	if _tanda_decidida():
		tanda_terminada = true
		_preparar_final()
		if _cinematicas:
			await _cinematicas.jugar_fin()
		_end_game()
		return

	turno = Lado.RIVAL if turno == Lado.JUGADOR else Lado.JUGADOR
	# Los jugadores vuelven a su lugar: se tapa con un fundido a negro.
	var negro := _capa_negra()
	var salida := create_tween()
	salida.tween_property(negro, "color:a", 1.0, FUNDIDO_ENTRE_TIROS)
	await salida.finished
	_iniciar_turno()
	# Un instante en negro para que no se vea ni un cuadro del acomodo.
	var entrada := create_tween()
	entrada.tween_interval(NEGRO_ENTRE_TIROS)
	entrada.tween_property(negro, "color:a", 0.0, FUNDIDO_ENTRE_TIROS)
	# El arbitro habilita el tiro.
	entrada.tween_callback(func():
		if sound_manager and sound_manager.has_method("play_whistle"):
			sound_manager.play_whistle())

var _negro: ColorRect
var _cinematicas: Node

## Va a negro o vuelve (alfa 1 o 0). La ceremonia final lo usa para armar la escena.
func fundido(alfa: float) -> void:
	var t := create_tween()
	t.tween_property(_capa_negra(), "color:a", alfa, FUNDIDO_ENTRE_TIROS)
	await t.finished

func _capa_negra() -> ColorRect:
	if _negro == null:
		var capa := CanvasLayer.new()
		capa.layer = 50
		add_child(capa)
		_negro = ColorRect.new()
		_negro.color = Color(0, 0, 0, 0)
		_negro.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_negro.set_anchors_preset(Control.PRESET_FULL_RECT)
		capa.add_child(_negro)
	return _negro

## El final muestra a los dos equipos, no al ultimo que pateo: se deja al
## pateador con el kit del equipo del jugador y al arquero con el del rival.
func _preparar_final() -> void:
	equipo_pateador = "rojo"
	equipo_arquero = "azul"
	_pateador_turno = {"nombre": "", "kit": "rojo"}
	_equipar_pateador()
	_equipar_arquero()

func _end_game():
	tanda_terminada = true
	current_state = PenaltyState.IDLE
	print("[GameManager] Tanda terminada: Jugador %d - Rival %d" % [goles_jugador, goles_rival])
	if sound_manager and sound_manager.has_method("play_whistle_long"):
		sound_manager.play_whistle_long()
	game_over.emit(kicker_score, goalkeeper_score, tiros_jugador + tiros_rival)
