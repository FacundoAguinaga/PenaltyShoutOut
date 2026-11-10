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

@export var kicker: PlayerKicker
@export var goalkeeper: PlayerGoalkeeper
@export var ball: SoccerBall
@export var goal_zone: GoalZone

@export var kicker_start_position: Marker3D
@export var goalkeeper_start_position: Marker3D
@export var ball_spawn_position: Marker3D
@export var sound_manager: Node

@export_group("Game Settings")
@export var shots_per_round: int = 5
@export var turn_timeout: float = 30.0
## Dibuja un rectangulo rojo en la boca del arco para verificar la alineacion.
## Solo para debug: tapa la vista del arco durante el juego.
@export var show_debug_goal: bool = false

var current_state: PenaltyState = PenaltyState.IDLE
var kicker_score: int = 0
var goalkeeper_score: int = 0
var current_shot: int = 0
var _shot_resolved: bool = false
var _shot_timeout_timer: SceneTreeTimer

signal penalty_started
signal kick_released(power: float, kick_target: Vector3)
signal ball_hit(velocity: Vector3)
signal goal_scored(kicker_name: String)
signal ball_saved
signal ball_missed
signal ball_deflected
signal shot_complete(result: String)
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
	start_penalty()

func _apply_settings():
	var settings = get_node_or_null("/root/SettingsManager")
	if settings:
		shots_per_round = settings.shots_per_round

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
		if not sound_manager:
			sound_manager = _find_node_by_type(self, SoundManager)

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

	if goal_zone:
		goal_zone.goal_detected.connect(_on_goal_detected)

	if goalkeeper:
		goalkeeper.keeper_save.connect(_on_keeper_save)
		goalkeeper.keeper_deflect.connect(_on_keeper_deflect)

		if goalkeeper and ball:
			ball.shot_taken.connect(goalkeeper.on_ball_kicked)

func start_penalty():
	current_state = PenaltyState.AIMING
	current_shot += 1
	_shot_resolved = false

	reset_positions()
	if _cinematicas:
		_cinematicas.limpiar()

	if kicker:
		kicker.start_aiming()
	if goalkeeper:
		goalkeeper.reset_to_idle()

	penalty_started.emit()
	print("[GameManager] Penalty %d started" % current_shot)

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
	# The keeper starts reading the shot as the shooter starts the run-up.
	if goalkeeper and kicker and ball and goalkeeper.has_method("anticipar"):
		goalkeeper.anticipar(ball.global_position, kicker.shot_velocity(), kicker.seconds_until_contact(), kicker.es_picada())

func _on_ball_launch_requested(velocity: Vector3):
	if ball:
		ball.kick(velocity, kicker != null and kicker.es_picada())
	if sound_manager and sound_manager.has_method("play_kick"):
		sound_manager.play_kick()
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

func _on_keeper_save(ball_hit_ref: SoccerBall):
	if _shot_resolved or current_state != PenaltyState.BALL_FLYING:
		return
	_shot_resolved = true
	current_state = PenaltyState.RESULT
	goalkeeper_score += 1
	if sound_manager and sound_manager.has_method("play_save"):
		sound_manager.play_save()
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
		sound_manager.play_save()
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
	kicker_score += 1
	if sound_manager and sound_manager.has_method("play_goal"):
		sound_manager.play_goal()
	goal_scored.emit("Kicker")
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

## La cinematica de la jugada dura hasta el proximo tiro.
func _next_shot(resultado: String):
	await _cinematicas.jugar(resultado)
	if current_shot < shots_per_round:
		# Los jugadores vuelven a su lugar: se tapa con un fundido a negro.
		var negro := _capa_negra()
		var salida := create_tween()
		salida.tween_property(negro, "color:a", 1.0, FUNDIDO_ENTRE_TIROS)
		await salida.finished
		start_penalty()
		# Un instante en negro para que no se vea ni un cuadro del acomodo.
		var entrada := create_tween()
		entrada.tween_interval(NEGRO_ENTRE_TIROS)
		entrada.tween_property(negro, "color:a", 0.0, FUNDIDO_ENTRE_TIROS)
	else:
		await _cinematicas.jugar_fin()
		_end_game()

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

func _end_game():
	print("[GameManager] Game Over! Kicker: %d - Goalkeeper: %d" % [kicker_score, goalkeeper_score])
	if sound_manager and sound_manager.has_method("play_whistle_long"):
		sound_manager.play_whistle_long()
	game_over.emit(kicker_score, goalkeeper_score, current_shot)
