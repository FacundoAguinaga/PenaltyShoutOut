extends CanvasLayer

## Fin de la tanda, con el estilo del menu (EstiloUI): el juego queda atras
## oscurecido; arriba a la izquierda quien gano, el marcador grande y las
## opciones de texto.

var _raiz: Control
var _fondo: ColorRect
var _titulo: VBoxContainer
var _marcador: HBoxContainer
var _goles_tirador: Label
var _goles_arquero: Label
var _items: Array[Button] = []


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.theme = EstiloUI.tema()
	add_child(_raiz)

	_fondo = EstiloUI.rect(Color(EstiloUI.COLOR_OSCURO, 0.6))
	_fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(_fondo)
	_raiz.add_child(EstiloUI.velo_izquierdo(0.92))

	var v := VBoxContainer.new()
	v.position = Vector2(EstiloUI.MARGEN, 72)
	v.add_theme_constant_override("separation", 18)
	_raiz.add_child(v)

	_titulo = EstiloUI.titulo("GANASTE", 64)
	v.add_child(_titulo)

	_marcador = HBoxContainer.new()
	_marcador.add_theme_constant_override("separation", 34)
	v.add_child(_marcador)
	_goles_tirador = _columna("TIRADOR")
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.18)
	sep.custom_minimum_size = Vector2(1, 0)
	_marcador.add_child(sep)
	_goles_arquero = _columna("ARQUERO")

	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 2)
	v.add_child(lista)
	for a in [["JUGAR DE NUEVO", _on_replay_pressed], ["MENÚ PRINCIPAL", _on_main_menu_pressed]]:
		var b := EstiloUI.item(a[0], 30, 440)
		b.pressed.connect(a[1])
		lista.add_child(b)
		_items.append(b)


func _columna(nombre: String) -> Label:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", -10)
	_marcador.add_child(c)
	c.add_child(EstiloUI.label(nombre, 12, EstiloUI.COLOR_GRIS, EstiloUI.fuente(600, 4)))
	var n := EstiloUI.label("0", 88, EstiloUI.COLOR_TEXTO, EstiloUI.fuente(200, 0))
	EstiloUI.sombra(n, 0.3, 4)
	c.add_child(n)
	return n


func setup_results(kicker_score: int, gk_score: int, _total_shots: int):
	visible = true
	get_tree().paused = true

	_goles_tirador.text = str(kicker_score)
	_goles_arquero.text = str(gk_score)

	var texto: Label = _titulo.get_node("Texto")
	if kicker_score > gk_score:
		texto.text = "GANASTE"
		_goles_tirador.add_theme_color_override("font_color", EstiloUI.COLOR_ACENTO)
	elif gk_score > kicker_score:
		texto.text = "GANÓ EL ARQUERO"
		_goles_arquero.add_theme_color_override("font_color", EstiloUI.COLOR_ACENTO)
	else:
		texto.text = "EMPATE"

	# entrada: fondo, titulo, marcador y opciones escalonados
	_fondo.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_fondo, "modulate:a", 1.0, 0.5)
	_marcador.modulate.a = 0.0
	EstiloUI.entrar_titulo(self, _titulo, 0.3)
	t.tween_property(_marcador, "modulate:a", 1.0, 0.6).set_delay(0.6)
	for b in _items:
		b.get_node("Contenido").modulate.a = 0.0
	EstiloUI.mostrar_lista(self, _items, true, 0.9).chain().tween_callback(func(): _items[0].grab_focus())


func _on_replay_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
