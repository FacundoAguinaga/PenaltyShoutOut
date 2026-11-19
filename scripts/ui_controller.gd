extends CanvasLayer

## HUD del partido, con el mismo estilo que el menu (EstiloUI): texto alineado
## a la izquierda, sin cajas, acento dorado.
##   - arriba a la izquierda: ronda, marcador de la tanda (circulos verdes y
##     rojos por tiro), equipos y quien patea
##   - arriba a la derecha: PAUSA
##   - abajo a la izquierda: potencia (con la zona optima marcada) y ayuda
##   - centro: cartel del resultado (GOLAZO, ATAJADA, AFUERA)
##   - en el arco: la mira del pateador o la zona elegida por el arquero
##
## La mira del pateador NUNCA se muestra cuando el jugador ataja: si no, el
## rival estaria delatando adonde va a patear.

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
## Circulos del marcador de tanda: verde gol, rojo errado (atajada o afuera).
const COLOR_DOT_GOL := Color(0.24, 0.84, 0.38)
const COLOR_DOT_FALLO := Color(0.90, 0.22, 0.22)
const TAMANO_DOT := 15

var _raiz: Control
var _contador: Label
var _turno: Label
var _goles_tirador: Label
var _goles_arquero: Label
var _historial_jugador: HBoxContainer
var _historial_rival: HBoxContainer
var _sale: Label
var _sigue: Label
var _lineup: HBoxContainer
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
	_update_turno_info()
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
	arriba.offset_bottom = 250
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
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_raiz.add_child(v)

	_contador = EstiloUI.label("RONDA 1 / 5", 13, EstiloUI.COLOR_ACENTO, EstiloUI.fuente(600, 5))
	v.add_child(_contador)

	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 22)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fila)
	_goles_tirador = _columna_marcador(fila, "TU EQUIPO")
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(sep)
	_goles_arquero = _columna_marcador(fila, "RIVAL")

	_turno = EstiloUI.label("PATEÁS VOS", 13, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(700, 3))
	v.add_child(_turno)

	# Una fila por equipo, como el marcador de tanda de la tele.
	_historial_jugador = _fila_historial(v, "VOS")
	_historial_rival = _fila_historial(v, "RIVAL")

	var sale_vacio := Control.new()
	sale_vacio.custom_minimum_size = Vector2(0, 2)
	sale_vacio.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sale_vacio)

	_sale = EstiloUI.label("SALE: ACOSTA", 14, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(700, 2))
	v.add_child(_sale)
	_sigue = EstiloUI.label("SIGUE: BENÍTEZ", 11, Color(EstiloUI.COLOR_GRIS, 0.9), EstiloUI.fuente(500, 1))
	v.add_child(_sigue)

	_lineup = HBoxContainer.new()
	_lineup.add_theme_constant_override("separation", 10)
	_lineup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_lineup)


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


func _fila_historial(padre: Control, nombre: String) -> HBoxContainer:
	var fila := HBoxContainer.new()
	fila.add_theme_constant_override("separation", 8)
	fila.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padre.add_child(fila)
	var etiqueta := EstiloUI.label(nombre, 10, EstiloUI.COLOR_GRIS, EstiloUI.fuente(600, 3))
	etiqueta.custom_minimum_size = Vector2(44, 0)
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fila.add_child(etiqueta)
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 5)
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fila.add_child(dots)
	return dots


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

	_ayuda = EstiloUI.label("", 12, Color(EstiloUI.COLOR_GRIS, 0.85), EstiloUI.fuente(500, 2))
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
		if game_manager.has_signal("tanda_actualizada"):
			game_manager.tanda_actualizada.connect(_on_tanda_actualizada)
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


func _jugador_patea() -> bool:
	if not game_manager:
		return true
	return game_manager.turno == GameManager.Lado.JUGADOR


func _color_potencia() -> Color:
	var power = kicker.get_power()
	if power >= kicker.optimal_power_min and power <= kicker.optimal_power_max:
		return reticle_color_optimal
	elif power > 95.0:
		return reticle_color_danger
	return reticle_color_default


func _update_aim_reticle():
	if not _mira:
		return
	if _jugador_patea():
		_update_kicker_reticle()
	else:
		_update_keeper_reticle()


## Mira del pateador: solo existe cuando patea el jugador. Mientras ataja, no
## se muestra nada del tiro rival.
func _update_kicker_reticle():
	if not kicker:
		_mira.visible = false
		return

	var is_aiming = kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	_mira.visible = is_aiming or not show_reticle_only_when_aiming

	if not is_aiming and show_reticle_only_when_aiming:
		return

	var aim_local = kicker.get_current_aim()
	var goal_pos = goal_zone.global_position if goal_zone else Vector3(0, 1.22, -12)
	var aim_world = Vector3(goal_pos.x + aim_local.x, aim_local.y, goal_pos.z)
	var pos := _proyectar(aim_world)
	if pos == Vector2.INF:
		_mira.visible = false
		return
	_mira.position = pos - _mira.size / 2
	_mira.modulate = _color_potencia()


## Mientras el jugador ataja, la mira muestra la zona elegida para tirarse
## (no la del pateador rival).
func _update_keeper_reticle():
	if not goalkeeper or not goalkeeper.es_control_humano():
		_mira.visible = false
		return
	var activo: bool = goalkeeper.state in [
		PlayerGoalkeeper.GKState.CONTROL,
		PlayerGoalkeeper.GKState.DIVING,
		PlayerGoalkeeper.GKState.ANTICIPATING,
	]
	if not activo or not goalkeeper.tirada_elegida():
		_mira.visible = false
		return
	var p := goalkeeper.get_objetivo_tirada_visual()
	if absf(p.x) > 100.0:
		_mira.visible = false
		return
	var goal_pos = goal_zone.global_position if goal_zone else Vector3(0, 1.22, -12)
	var world = Vector3(goal_pos.x + p.x, p.y, goal_pos.z)
	var pos := _proyectar(world)
	if pos == Vector2.INF:
		_mira.visible = false
		return
	_mira.visible = true
	_mira.position = pos - _mira.size / 2
	_mira.modulate = reticle_color_optimal


func _proyectar(world: Vector3) -> Vector2:
	var camera = get_viewport().get_camera_3d()
	if not camera or camera.is_position_behind(world):
		return Vector2.INF
	return camera.unproject_position(world)


func _update_power_bar():
	if not _potencia or not kicker:
		return
	var is_active = _jugador_patea() and kicker.current_state in [PlayerKicker.KickState.AIMING, PlayerKicker.KickState.CHARGING]
	_potencia.visible = is_active
	if not is_active:
		return
	var power_percent = kicker.get_power_percent() * 100.0
	var color := _color_potencia()
	_potencia_relleno.size.x = ANCHO_POTENCIA * kicker.get_power_percent()
	_potencia_relleno.color = color
	_potencia_valor.text = "%d" % int(power_percent)
	_potencia_valor.add_theme_color_override("font_color", color)


# --------------------------------------------------------------- marcador

func _update_score_display():
	if game_manager:
		_goles_tirador.text = str(game_manager.goles_jugador)
		_goles_arquero.text = str(game_manager.goles_rival)


func _update_shot_counter():
	if not game_manager:
		return
	_contador.text = game_manager.texto_ronda()
	if game_manager.en_muerte_subita():
		_contador.add_theme_color_override("font_color", COLOR_ATAJADA)
	else:
		_contador.add_theme_color_override("font_color", EstiloUI.COLOR_ACENTO)


func _update_turno_info():
	if not game_manager:
		return
	if game_manager.turno == GameManager.Lado.JUGADOR:
		_turno.text = "PATEÁS VOS"
		_turno.add_theme_color_override("font_color", EstiloUI.COLOR_ACENTO)
		_sale.text = "SALE: %s" % game_manager.nombre_pateador_actual()
		_sigue.text = "SIGUE: %s" % game_manager.nombre_siguiente_pateador()
	else:
		_turno.text = "ATAJÁS VOS"
		_turno.add_theme_color_override("font_color", EstiloUI.COLOR_PELIGRO)
		_sale.text = "PATEA: %s" % game_manager.nombre_pateador_actual()
		_sigue.text = "ELEGÍ LADO Y ALTURA, Y TIRATE"
	_actualizar_lineup()


## La fila de cinco companeros del equipo que patea, con el que sale resaltado.
func _actualizar_lineup():
	if not _lineup or not game_manager:
		return
	for child in _lineup.get_children():
		child.queue_free()
	var plantel: Array = game_manager.plantel_del_turno()
	var actual: int = game_manager.indice_pateador_actual()
	var etiqueta := EstiloUI.label("FILA", 9, EstiloUI.COLOR_GRIS, EstiloUI.fuente(600, 3))
	etiqueta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lineup.add_child(etiqueta)
	for i in plantel.size():
		var es_actual := i == actual
		var col := EstiloUI.COLOR_ACENTO if es_actual else Color(EstiloUI.COLOR_GRIS, 0.7)
		var l := EstiloUI.label(str(plantel[i]["nombre"]), 10, col, EstiloUI.fuente(700 if es_actual else 500, 1))
		_lineup.add_child(l)


## Cuantos circulos mostrar: 5 por lado, mas los que haga falta en muerte subita.
func _dots_totales() -> int:
	if not game_manager:
		return 5
	var rj: int = game_manager.resultados_jugador.size()
	var rr: int = game_manager.resultados_rival.size()
	var n: int = maxi(5, maxi(rj, rr))
	if not game_manager.tanda_terminada and rj >= 5 and rr >= 5 and rj == rr:
		n += 1
	return n


## Un punto por tiro: verde gol, rojo errado (atajada o afuera), aro el que
## falta. El que esta por patear se marca en dorado.
func _refresh_shot_history_ui():
	if not game_manager:
		return
	var total := _dots_totales()
	_llenar_dots(_historial_jugador, game_manager.resultados_jugador, total, 0)
	_llenar_dots(_historial_rival, game_manager.resultados_rival, total, 1)


func _llenar_dots(contenedor: HBoxContainer, resultados: Array[String], total: int, lado: int) -> void:
	for child in contenedor.get_children():
		child.queue_free()

	var es_turno: bool = game_manager.turno == lado and not game_manager.tanda_terminada \
		and game_manager.current_state != GameManager.PenaltyState.RESULT
	for i in range(total):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(TAMANO_DOT, TAMANO_DOT)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(TAMANO_DOT / 2)
		if i < resultados.size():
			style.bg_color = COLOR_DOT_GOL if resultados[i] == "goal" else COLOR_DOT_FALLO
		else:
			style.draw_center = false
			style.set_border_width_all(2)
			if es_turno and i == resultados.size():
				style.border_color = EstiloUI.COLOR_ACENTO
			else:
				style.border_color = Color(1, 1, 1, 0.28)
		dot.add_theme_stylebox_override("panel", style)
		contenedor.add_child(dot)


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


func _texto_ayuda() -> String:
	if not _jugador_patea():
		return "FLECHAS  mover al arquero      ESPACIO + flecha  tirarse      ↑↓  altura"
	return "WASD  apuntar      ESPACIO  mantener y soltar para patear      SHIFT + soltar  picarla"


func _setup_controls_help():
	var settings = get_node_or_null("/root/SettingsManager")
	_ayuda.visible = settings.show_controls_help if settings else true
	_ayuda.text = _texto_ayuda()


# ------------------------------------------------------------------ eventos

func _on_penalty_started():
	_update_score_display()
	_update_shot_counter()
	_update_turno_info()
	_refresh_shot_history_ui()
	_ayuda.text = _texto_ayuda()


func _on_tanda_actualizada():
	_update_score_display()
	_update_shot_counter()
	_update_turno_info()
	_refresh_shot_history_ui()


func _on_kick_released(_power: float, _kick_target: Vector3):
	# La ayuda queda visible: en la tanda cambia de significado entre patear y
	# atajar, asi que no conviene esconderla despues del primer tiro.
	pass


func _on_goal_scored(_kicker_name: String):
	if _jugador_patea():
		_show_status_banner("GOLAZO", COLOR_GOL)
	else:
		_show_status_banner("GOL DEL RIVAL", COLOR_ATAJADA)
	_update_score_display()
	_refresh_shot_history_ui()


func _on_ball_saved():
	if _jugador_patea():
		_show_status_banner("ATAJADA", COLOR_ATAJADA)
	else:
		_show_status_banner("ATAJADÓN TUYO", COLOR_GOL)
	_update_score_display()
	_refresh_shot_history_ui()


func _on_ball_missed():
	if _jugador_patea():
		_show_status_banner("AFUERA", EstiloUI.COLOR_TEXTO)
	else:
		_show_status_banner("AFUERA DEL RIVAL", EstiloUI.COLOR_TEXTO)
	_refresh_shot_history_ui()


func _on_shot_complete(_result: String):
	_update_shot_counter()


func _on_game_over(kicker_score: int, gk_score: int, total_shots: int):
	if game_over_modal and game_over_modal.has_method("setup_results"):
		game_over_modal.setup_results(kicker_score, gk_score, total_shots)


func _on_pause_button_pressed():
	if pause_menu and pause_menu.has_method("toggle_pause"):
		pause_menu.toggle_pause()
