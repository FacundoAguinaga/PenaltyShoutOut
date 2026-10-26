extends CanvasLayer

## HUD del partido, con el mismo estilo que el menu (EstiloUI): texto alineado
## a la izquierda, sin cajas, acento dorado.
##   - arriba a la izquierda: tiro actual, marcador e historial de tiros
##   - arriba a la derecha: PAUSA
##   - abajo a la izquierda: potencia (con la zona optima marcada) y ayuda
##   - centro: cartel del resultado (GOLAZO, ATAJADA, AFUERA)
##   - en el arco: la mira

@export var game_manager: GameManager
@export var kicker: PlayerKicker
@export var goalkeeper: PlayerGoalkeeper
@export var goal_zone: GoalZone

@export_group("Sub-Menus")
@export var pause_menu: CanvasLayer
@export var game_over_modal: CanvasLayer

@export_group("Reticle & Bar Settings")
@export var reticle_color_default: Color = EstiloUI.COLOR_TEXTO
@export var reticle_color_optimal: Color = EstiloUI.COLOR_ACENTO
@export var reticle_color_danger: Color = EstiloUI.COLOR_PELIGRO
@export var show_reticle_only_when_aiming: bool = true

const ANCHO_POTENCIA := 280.0
const COLOR_GOL := EstiloUI.COLOR_ACENTO
const COLOR_ATAJADA := EstiloUI.COLOR_PELIGRO
const COLOR_AFUERA := EstiloUI.COLOR_GRIS

var _shot_history: Array[String] = [] # "goal", "save", "miss"
var _raiz: Control
var _contador: Label
var _goles_tirador: Label
var _goles_arquero: Label
var _historial: HBoxContainer
var _mira: Control
var _potencia: Control
var _potencia_valor: Label
var _potencia_relleno: ColorRect
var _cartel: VBoxContainer
var _cartel_texto: Label
var _cartel_linea: ColorRect
var _cartel_tween: Tween
var _ayuda: Label
var _btn_pausa: Button


func _ready():
	# sigue corriendo en pausa para poder esconderse detras de la pausa y el fin
	process_mode = Node.PROCESS_MODE_ALWAYS
	_find_references()
	_armar()
	_connect_signals()
	_update_score_display()
	_update_shot_counter()
	_refresh_shot_history_ui()
	_setup_controls_help()
	_animar_entrada()


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


# ------------------------------------------------------------------- armado

func _armar() -> void:
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.theme = EstiloUI.tema()
	add_child(_raiz)
	# sombra arriba, para que se lean el marcador y la pausa sobre el estadio
	var c := EstiloUI.COLOR_OSCURO
	var arriba := EstiloUI.degradado(PackedColorArray([Color(c, 0.6), Color(c, 0.0)]), PackedFloat32Array([0.0, 1.0]), true)
	arriba.set_anchors_preset(Control.PRESET_TOP_WIDE)
	arriba.offset_bottom = 200
	_raiz.add_child(arriba)
	var abajo := EstiloUI.degradado(PackedColorArray([Color(c, 0.0), Color(c, 0.55)]), PackedFloat32Array([0.0, 1.0]), true)
	abajo.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	abajo.offset_top = -170
	_raiz.add_child(abajo)

	_armar_marcador()
	_armar_mira()
	_armar_potencia()
	_armar_cartel()

	_btn_pausa = EstiloUI.item("PAUSA", 18, 150)
	_btn_pausa.anchor_left = 1.0
	_btn_pausa.anchor_right = 1.0
	_btn_pausa.offset_left = -56 - 150
	_btn_pausa.offset_top = 36
	_btn_pausa.focus_mode = Control.FOCUS_NONE
	_btn_pausa.pressed.connect(_on_pause_button_pressed)
	_raiz.add_child(_btn_pausa)


func _armar_marcador() -> void:
	var v := VBoxContainer.new()
	v.name = "Marcador"
	v.position = Vector2(56, 36)
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(v)

	_contador = EstiloUI.label("TIRO 1 / 5", 13, EstiloUI.COLOR_ACENTO, EstiloUI.fuente(600, 5))
	v.add_child(_contador)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 22)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fila)
	_goles_tirador = _columna_marcador(fila, "TIRADOR")
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(sep)
	_goles_arquero = _columna_marcador(fila, "ARQUERO")

	_historial = HBoxContainer.new()
	_historial.add_theme_constant_override("separation", 8)
	_historial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_historial)


func _columna_marcador(padre: Control, nombre: String) -> Label:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", -6)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padre.add_child(c)
	c.add_child(EstiloUI.label(nombre, 12, EstiloUI.COLOR_GRIS, EstiloUI.fuente(600, 4)))
	var n := EstiloUI.label("0", 46, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(300, 0))
	EstiloUI.sombra(n, 0.3, 3)
	c.add_child(n)
	return n


## Mira: un aro fino con un punto en el centro.
func _armar_mira() -> void:
	_mira = Control.new()
	_mira.size = Vector2(46, 46)
	_mira.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aro := Panel.new()
	var e := StyleBoxFlat.new()
	e.draw_center = false
	e.set_border_width_all(2)
	e.border_color = Color.WHITE
	e.set_corner_radius_all(23)
	e.shadow_color = Color(0, 0, 0, 0.35)
	e.shadow_size = 6
	e.anti_aliasing_size = 1.2
	aro.add_theme_stylebox_override("panel", e)
	aro.set_anchors_preset(Control.PRESET_FULL_RECT)
	aro.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mira.add_child(aro)
	var punto := Panel.new()
	var ep := StyleBoxFlat.new()
	ep.bg_color = Color.WHITE
	ep.set_corner_radius_all(3)
	punto.add_theme_stylebox_override("panel", ep)
	punto.position = Vector2(20, 20)
	punto.size = Vector2(6, 6)
	punto.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mira.add_child(punto)
	_raiz.add_child(_mira)
	# late suave mientras se apunta
	var t := create_tween().set_loops()
	_mira.pivot_offset = _mira.size * 0.5
	t.tween_property(_mira, "scale", Vector2(1.08, 1.08), 0.7).set_trans(Tween.TRANS_SINE)
	t.tween_property(_mira, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)


## Potencia: texto chico, una linea fina que se llena y la zona optima marcada.
func _armar_potencia() -> void:
	_potencia = Control.new()
	_potencia.anchor_top = 1.0
	_potencia.anchor_bottom = 1.0
	_potencia.offset_left = EstiloUI.MARGEN * 0.6
	_potencia.offset_top = -92
	_potencia.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_potencia)

	var titulo := EstiloUI.label("POTENCIA", 12, EstiloUI.COLOR_GRIS, EstiloUI.fuente(600, 5))
	_potencia.add_child(titulo)
	_potencia_valor = EstiloUI.label("0", 28, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(300, 1))
	_potencia_valor.position = Vector2(0, 14)
	EstiloUI.sombra(_potencia_valor, 0.3, 2)
	_potencia.add_child(_potencia_valor)

	var riel := ColorRect.new()
	riel.color = Color(1, 1, 1, 0.14)
	riel.position = Vector2(0, 58)
	riel.size = Vector2(ANCHO_POTENCIA, 3)
	riel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potencia.add_child(riel)
	if kicker:
		var optima := ColorRect.new()
		optima.color = Color(EstiloUI.COLOR_ACENTO, 0.35)
		var desde: float = kicker.optimal_power_min / kicker.max_power
		var hasta: float = kicker.optimal_power_max / kicker.max_power
		optima.position = Vector2(ANCHO_POTENCIA * desde, 54)
		optima.size = Vector2(ANCHO_POTENCIA * (hasta - desde), 11)
		optima.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_potencia.add_child(optima)
	_potencia_relleno = ColorRect.new()
	_potencia_relleno.position = Vector2(0, 57)
	_potencia_relleno.size = Vector2(0, 5)
	_potencia_relleno.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_potencia.add_child(_potencia_relleno)

	_ayuda = EstiloUI.label("WASD  apuntar      ESPACIO  mantener y soltar para patear", 12,
		Color(EstiloUI.COLOR_GRIS, 0.8), EstiloUI.fuente(500, 2))
	_ayuda.anchor_top = 1.0
	_ayuda.anchor_bottom = 1.0
	_ayuda.offset_left = EstiloUI.MARGEN * 0.6
	_ayuda.offset_top = -132
	_raiz.add_child(_ayuda)


## Cartel del resultado, centrado: texto grande con una linea dorada abajo.
func _armar_cartel() -> void:
	_cartel = VBoxContainer.new()
	_cartel.set_anchors_preset(Control.PRESET_CENTER)
	_cartel.alignment = BoxContainer.ALIGNMENT_CENTER
	_cartel.add_theme_constant_override("separation", 10)
	_cartel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(_cartel)
	_cartel_texto = EstiloUI.label("", 84, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(800, 8))
	_cartel_texto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	EstiloUI.sombra(_cartel_texto, 0.4, 6)
	_cartel.add_child(_cartel_texto)
	_cartel_linea = ColorRect.new()
	_cartel_linea.color = EstiloUI.COLOR_ACENTO
	_cartel_linea.custom_minimum_size = Vector2(0, 3)
	_cartel_linea.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_cartel_linea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartel.add_child(_cartel_linea)
	_cartel.modulate.a = 0.0


func _animar_entrada() -> void:
	var marcador: Control = _raiz.get_node("Marcador")
	marcador.modulate.a = 0.0
	_btn_pausa.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(marcador, "modulate:a", 1.0, 0.8).set_delay(0.3)
	t.tween_property(_btn_pausa, "modulate:a", 1.0, 0.8).set_delay(0.5)


# ------------------------------------------------------------------- señales

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


func _process(delta: float):
	# el HUD se va mientras estan la pausa o el fin (tienen su propio titulo)
	var tapado: bool = (pause_menu and pause_menu.visible) or (game_over_modal and game_over_modal.visible)
	_raiz.modulate.a = move_toward(_raiz.modulate.a, 0.0 if tapado else 1.0, delta * 5.0)
	if get_tree().paused:
		return
	_update_aim_reticle()
	_update_power_bar()


func _color_potencia() -> Color:
	var power = kicker.get_power()
	if power >= kicker.optimal_power_min and power <= kicker.optimal_power_max:
		return reticle_color_optimal
	elif power > 95.0:
		return reticle_color_danger
	return reticle_color_default


func _update_aim_reticle():
	if not _mira or not kicker:
		return

	var is_aiming = kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	_mira.visible = is_aiming or not show_reticle_only_when_aiming

	if not is_aiming and show_reticle_only_when_aiming:
		return

	var aim_local = kicker.get_current_aim()
	var goal_pos = goal_zone.global_position if goal_zone else Vector3(0, 1.22, -12)
	var aim_world = Vector3(goal_pos.x + aim_local.x, aim_local.y, goal_pos.z)

	var camera = get_viewport().get_camera_3d()
	if camera:
		if camera.is_position_behind(aim_world):
			_mira.visible = false
			return
		_mira.position = camera.unproject_position(aim_world) - _mira.size / 2
	else:
		_mira.position = Vector2(640, 360)
	_mira.modulate = _color_potencia()


func _update_power_bar():
	if not _potencia or not kicker:
		return
	var is_active = kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	_potencia.visible = is_active
	if not is_active:
		return
	var power_percent = kicker.get_power_percent() * 100.0
	var color := _color_potencia()
	_potencia_relleno.size.x = ANCHO_POTENCIA * kicker.get_power_percent()
	_potencia_relleno.color = color
	_potencia_valor.text = "%d" % int(power_percent)
	_potencia_valor.add_theme_color_override("font_color", color)


func _update_score_display():
	if game_manager:
		_goles_tirador.text = str(game_manager.kicker_score)
		_goles_arquero.text = str(game_manager.goalkeeper_score)


func _update_shot_counter():
	if game_manager:
		_contador.text = "TIRO %d / %d" % [game_manager.current_shot, game_manager.shots_per_round]


## Un punto por tiro: dorado gol, rojo atajada, gris afuera, aro vacio el que falta.
func _refresh_shot_history_ui():
	for child in _historial.get_children():
		child.queue_free()

	var total_shots = game_manager.shots_per_round if game_manager else 5
	# a lo sumo 10 puntos para que no se desborde
	var max_visible_dots = min(total_shots, 10)

	for i in range(max_visible_dots):
		var dot = Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(5)
		if i < _shot_history.size():
			var res = _shot_history[i]
			style.bg_color = COLOR_GOL if res == "goal" else (COLOR_ATAJADA if res == "save" else COLOR_AFUERA)
		else:
			style.draw_center = false
			style.set_border_width_all(1)
			style.border_color = Color(1, 1, 1, 0.35)
		dot.add_theme_stylebox_override("panel", style)
		_historial.add_child(dot)


## Cartel del resultado: aparece agrandandose apenas, dibuja la linea y se va
## hacia arriba.
func _show_status_banner(text: String, color: Color):
	_cartel_texto.text = text
	_cartel_texto.add_theme_color_override("font_color", color)
	_cartel_linea.color = color
	if _cartel_tween and _cartel_tween.is_running():
		_cartel_tween.kill()
	_cartel.reset_size()
	_cartel.position = (_raiz.size - _cartel.size) * 0.5 - Vector2(0, _raiz.size.y * 0.12)
	_cartel.pivot_offset = _cartel.size * 0.5
	_cartel.modulate.a = 0.0
	_cartel.scale = Vector2(0.92, 0.92)
	_cartel_linea.custom_minimum_size.x = 0.0
	var y := _cartel.position.y
	_cartel_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_cartel_tween.tween_property(_cartel, "modulate:a", 1.0, 0.25)
	_cartel_tween.tween_property(_cartel, "scale", Vector2.ONE, 0.45)
	_cartel_tween.tween_property(_cartel_linea, "custom_minimum_size:x", 120.0, 0.6).set_delay(0.1).set_trans(Tween.TRANS_EXPO)
	_cartel_tween.chain().tween_interval(1.0)
	_cartel_tween.chain().tween_property(_cartel, "modulate:a", 0.0, 0.45)
	_cartel_tween.tween_property(_cartel, "position:y", y - 24.0, 0.45).set_ease(Tween.EASE_IN)


func _setup_controls_help():
	var settings = get_node_or_null("/root/SettingsManager")
	_ayuda.visible = settings.show_controls_help if settings else true


func _on_penalty_started():
	_update_score_display()
	_update_shot_counter()


func _on_kick_released(_power: float, _kick_target: Vector3):
	if _ayuda.visible:
		# la ayuda se va despues del primer tiro
		var tween = create_tween()
		tween.tween_property(_ayuda, "modulate:a", 0.0, 0.5)
		await tween.finished
		_ayuda.visible = false


func _on_goal_scored(_kicker_name: String):
	_show_status_banner("GOLAZO", COLOR_GOL)
	_update_score_display()
	_shot_history.append("goal")
	_refresh_shot_history_ui()


func _on_ball_saved():
	_show_status_banner("ATAJADA", COLOR_ATAJADA)
	_update_score_display()
	_shot_history.append("save")
	_refresh_shot_history_ui()


func _on_ball_missed():
	_show_status_banner("AFUERA", EstiloUI.COLOR_TEXTO)
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
