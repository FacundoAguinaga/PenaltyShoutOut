extends CanvasLayer

@export var game_manager: GameManager
@export var kicker: PlayerKicker
@export var goalkeeper: PlayerGoalkeeper
@export var goal_zone: GoalZone

@export_group("UI Elements")
@export var power_bar: ProgressBar
@export var power_label: Label
@export var aim_reticle: Control
@export var kicker_score_label: Label
@export var goalkeeper_score_label: Label
@export var status_banner_label: Label
@export var status_banner_container: Control
@export var shot_counter_label: Label
@export var shot_history_container: HBoxContainer
@export var controls_help_panel: Control
@export var btn_pause: Button

@export_group("Sub-Menus")
@export var pause_menu: CanvasLayer
@export var game_over_modal: CanvasLayer

@export_group("Reticle & Bar Settings")
@export var reticle_color_default: Color = Color.WHITE
@export var reticle_color_optimal: Color = Color(0.2, 0.9, 0.4, 1.0)
@export var reticle_color_danger: Color = Color(0.95, 0.25, 0.25, 1.0)
@export var show_reticle_only_when_aiming: bool = true

var _shot_history: Array[String] = [] # "goal", "save", "miss"
var _status_tween: Tween

func _ready():
	_find_references()
	_connect_signals()
	_update_score_display()
	_update_shot_counter()
	_init_shot_history()
	_setup_controls_help()

	if status_banner_container:
		status_banner_container.modulate.a = 0.0
		status_banner_container.scale = Vector2(0.5, 0.5)

	if btn_pause:
		btn_pause.pressed.connect(_on_pause_button_pressed)

func _find_references():
	var root = owner if owner else get_tree().root
	if not game_manager:
		game_manager = _find_node_by_type(root, GameManager) as GameManager
	if not kicker:
		kicker = _find_node_by_type(root, PlayerKicker) as PlayerKicker
	if not goalkeeper:
		goalkeeper = _find_node_by_type(root, PlayerGoalkeeper) as PlayerGoalkeeper
	if not goal_zone:
		goal_zone = _find_node_by_type(root, GoalZone) as GoalZone

func _find_node_by_type(node: Node, type) -> Node:
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found = _find_node_by_type(child, type)
		if found:
			return found
	return null

func _connect_signals():
	if game_manager:
		game_manager.penalty_started.connect(_on_penalty_started)
		game_manager.kick_released.connect(_on_kick_released)
		game_manager.goal_scored.connect(_on_goal_scored)
		game_manager.ball_saved.connect(_on_ball_saved)
		game_manager.ball_missed.connect(_on_ball_missed)
		game_manager.shot_complete.connect(_on_shot_complete)
		if game_manager.has_signal("game_over"):
			game_manager.game_over.connect(_on_game_over)

func _process(_delta: float):
	_update_aim_reticle()
	_update_power_bar()

func _update_aim_reticle():
	if not aim_reticle or not kicker:
		return

	var is_aiming = kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	aim_reticle.visible = is_aiming or not show_reticle_only_when_aiming

	if not is_aiming and show_reticle_only_when_aiming:
		return

	var aim_local = kicker.get_current_aim()
	var goal_pos = goal_zone.global_position if goal_zone else Vector3(0, 1.22, -12)
	var aim_world = Vector3(goal_pos.x + aim_local.x, aim_local.y, goal_pos.z)

	var camera = get_viewport().get_camera_3d()
	if camera:
		if camera.is_position_behind(aim_world):
			aim_reticle.visible = false
			return
		var screen_pos = camera.unproject_position(aim_world)
		aim_reticle.position = screen_pos - aim_reticle.size / 2
	else:
		aim_reticle.position = Vector2(640, 360)

	# Dynamic Reticle Tint
	var power = kicker.get_power()
	var is_optimal = power >= kicker.optimal_power_min and power <= kicker.optimal_power_max
	if is_optimal:
		aim_reticle.modulate = reticle_color_optimal
	elif power > 95.0:
		aim_reticle.modulate = reticle_color_danger
	else:
		aim_reticle.modulate = reticle_color_default

func _update_power_bar():
	if not power_bar or not kicker:
		return

	var power_percent = kicker.get_power_percent() * 100.0
	power_bar.value = power_percent

	var is_active = kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	power_bar.visible = is_active

	var power = kicker.get_power()
	var is_optimal = power >= kicker.optimal_power_min and power <= kicker.optimal_power_max

	if is_optimal:
		power_bar.modulate = reticle_color_optimal
	elif power > 95.0:
		power_bar.modulate = reticle_color_danger
	else:
		power_bar.modulate = reticle_color_default

	if power_label:
		power_label.text = "POTENCIA: %d%%" % int(power_percent)
		power_label.visible = is_active

func _update_score_display():
	if kicker_score_label and game_manager:
		kicker_score_label.text = str(game_manager.kicker_score)
	if goalkeeper_score_label and game_manager:
		goalkeeper_score_label.text = str(game_manager.goalkeeper_score)

func _update_shot_counter():
	if shot_counter_label and game_manager:
		shot_counter_label.text = "TIRO %d DE %d" % [game_manager.current_shot, game_manager.shots_per_round]

func _init_shot_history():
	if not shot_history_container:
		return
	_refresh_shot_history_ui()

func _refresh_shot_history_ui():
	if not shot_history_container:
		return

	for child in shot_history_container.get_children():
		child.queue_free()

	var total_shots = game_manager.shots_per_round if game_manager else 5
	# Show at most 10 dots visually to prevent overflow
	var max_visible_dots = min(total_shots, 10)

	for i in range(max_visible_dots):
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(16, 16)
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8

		if i < _shot_history.size():
			var res = _shot_history[i]
			if res == "goal":
				style.bg_color = Color(0.2, 0.9, 0.3, 1) # Green check
			elif res == "save":
				style.bg_color = Color(0.9, 0.25, 0.25, 1) # Red save
			else:
				style.bg_color = Color(0.9, 0.6, 0.2, 1) # Orange miss
		else:
			style.bg_color = Color(0.3, 0.4, 0.5, 0.5) # Gray pending

		dot.add_theme_stylebox_override("panel", style)
		shot_history_container.add_child(dot)

func _show_status_banner(text: String, color: Color):
	if not status_banner_label or not status_banner_container:
		return

	status_banner_label.text = text
	status_banner_label.modulate = color

	if _status_tween and _status_tween.is_running():
		_status_tween.kill()

	status_banner_container.modulate.a = 0.0
	status_banner_container.scale = Vector2(0.5, 0.5)
	status_banner_container.pivot_offset = status_banner_container.size / 2.0

	_status_tween = create_tween().set_parallel(true)
	_status_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_status_tween.tween_property(status_banner_container, "modulate:a", 1.0, 0.25)
	_status_tween.tween_property(status_banner_container, "scale", Vector2.ONE, 0.3)

	# Fade out after delay
	var fade_tween = create_tween()
	fade_tween.tween_interval(1.2)
	fade_tween.tween_property(status_banner_container, "modulate:a", 0.0, 0.4)

func _setup_controls_help():
	var settings = get_node_or_null("/root/SettingsManager")
	if controls_help_panel:
		if settings:
			controls_help_panel.visible = settings.show_controls_help
		else:
			controls_help_panel.visible = true

func _on_penalty_started():
	_update_score_display()
	_update_shot_counter()

func _on_kick_released(_power: float, _kick_target: Vector3):
	_show_status_banner("¡TIRO!", Color(0.9, 0.95, 1))
	if controls_help_panel:
		# Auto-hide controls after first kick
		var tween = create_tween()
		tween.tween_property(controls_help_panel, "modulate:a", 0.0, 0.5)
		await tween.finished
		controls_help_panel.visible = false

func _on_goal_scored(_kicker_name: String):
	_show_status_banner("¡GOLAZO!", Color(0.2, 0.95, 0.4))
	_update_score_display()
	_shot_history.append("goal")
	_refresh_shot_history_ui()

func _on_ball_saved():
	_show_status_banner("¡ATAJADA!", Color(0.95, 0.3, 0.3))
	_update_score_display()
	_shot_history.append("save")
	_refresh_shot_history_ui()

func _on_ball_missed():
	_show_status_banner("¡FUERA!", Color(0.9, 0.6, 0.2))
	_shot_history.append("miss")
	_refresh_shot_history_ui()

func _on_shot_complete(_result: String):
	_update_shot_counter()

func _on_game_over(kicker_score: int, gk_score: int, total_shots: int):
	if game_over_modal and game_over_modal.has_method("setup_results"):
		game_over_modal.setup_results(kicker_score, gk_score, total_shots)

func _on_pause_button_pressed():
	if pause_menu and pause_menu.has_method("toggle_pause"):
		pause_menu.toggle_pause()
