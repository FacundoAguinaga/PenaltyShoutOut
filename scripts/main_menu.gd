extends Control

## Menu principal minimalista: titulo arriba a la izquierda, opciones como
## texto alineado a la izquierda (sin cajas) y un panel de opciones que entra
## desde la derecha. El estilo (colores, letras, animaciones de las opciones)
## es el de EstiloUI, el mismo del partido, la pausa y el fin.
##
## Animaciones propias del menu:
##   - entrada: fundido desde negro, el titulo baja y dibuja su linea, las
##     opciones entran escalonadas desde la izquierda
##   - fondo: zoom y paneo lentos (Ken Burns) + paralaje con el mouse
##   - JUGAR: las opciones salen y la pantalla funde a negro

const FONDO := "res://assets/ui/menu_fondo.jpg"
const ESCENA_JUEGO := "res://scenes/game.tscn"
const Y_TITULO := 72.0

var _fondo: TextureRect
var _titulo: VBoxContainer
var _lista: VBoxContainer
var _items: Array[Button] = []
var _panel_opciones: PanelContainer
var _negro: ColorRect
var _mouse_suave := Vector2.ZERO
var _ocupado := false


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = EstiloUI.tema()
	_armar_fondo()

	_titulo = EstiloUI.titulo("PENALTY\nSHOOTOUT")
	_titulo.position = Vector2(EstiloUI.MARGEN, Y_TITULO)
	add_child(_titulo)

	_lista = VBoxContainer.new()
	_lista.add_theme_constant_override("separation", 6)
	add_child(_lista)
	for texto in ["JUGAR", "OPCIONES", "SALIR"]:
		var b := EstiloUI.item(texto)
		_lista.add_child(b)
		_items.append(b)
	_items[0].pressed.connect(_on_jugar)
	_items[1].pressed.connect(_abrir_opciones)
	_items[2].pressed.connect(_on_salir)
	resized.connect(_ubicar_lista)
	_ubicar_lista.call_deferred()

	_panel_opciones = EstiloUI.panel_opciones(get_node_or_null("/root/SettingsManager"))
	_panel_opciones.get_meta("volver").pressed.connect(_cerrar_opciones)
	add_child(_panel_opciones)

	_negro = EstiloUI.rect(EstiloUI.COLOR_OSCURO)
	add_child(_negro)
	_animar_entrada()


func _process(delta: float) -> void:
	# paralaje: el fondo se corre un poco al reves del mouse
	var centro := size * 0.5
	var objetivo := (get_local_mouse_position() - centro) / maxf(centro.x, 1.0)
	_mouse_suave = _mouse_suave.lerp(objetivo.clamp(-Vector2.ONE, Vector2.ONE), 1.0 - exp(-3.0 * delta))
	_fondo.position = -_mouse_suave * 14.0 - Vector2(20, 20)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel_opciones.visible and not _ocupado:
		_cerrar_opciones()
		get_viewport().set_input_as_handled()


func _armar_fondo() -> void:
	add_child(EstiloUI.rect(EstiloUI.COLOR_OSCURO))
	_fondo = TextureRect.new()
	_fondo.texture = load(FONDO)
	_fondo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fondo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fondo)
	_ajustar_fondo()
	resized.connect(_ajustar_fondo)
	# zoom muy lento, de ida y vuelta
	var kb := create_tween().set_loops()
	kb.tween_property(_fondo, "scale", Vector2(1.09, 1.09), 18.0).set_trans(Tween.TRANS_SINE)
	kb.tween_property(_fondo, "scale", Vector2(1.03, 1.03), 18.0).set_trans(Tween.TRANS_SINE)
	add_child(EstiloUI.velo_izquierdo(0.97))
	# un poco mas oscuro arriba y abajo
	var c := EstiloUI.COLOR_OSCURO
	add_child(EstiloUI.degradado(
		PackedColorArray([Color(c, 0.55), Color(c, 0.0), Color(c, 0.0), Color(c, 0.85)]),
		PackedFloat32Array([0.0, 0.25, 0.65, 1.0]), true))


func _ajustar_fondo() -> void:
	# un poco mas grande que la pantalla para el paralaje y el zoom
	_fondo.size = size + Vector2(40, 40)
	_fondo.pivot_offset = _fondo.size * 0.5


## Las opciones van abajo a la izquierda, pero nunca encima del titulo.
func _ubicar_lista() -> void:
	var debajo_titulo := Y_TITULO + _titulo.get_combined_minimum_size().y + 48.0
	_lista.position = Vector2(EstiloUI.MARGEN, maxf(debajo_titulo, size.y - 300.0))


func _animar_entrada() -> void:
	_ocupado = true
	var t := create_tween()
	t.tween_property(_negro, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	EstiloUI.entrar_titulo(self, _titulo, 0.25)
	for b in _items:
		b.get_node("Contenido").modulate.a = 0.0
	var tl := EstiloUI.mostrar_lista(self, _items, true, 0.75)
	tl.chain().tween_callback(func():
		_ocupado = false
		_items[0].grab_focus())


func _on_jugar() -> void:
	if _ocupado:
		return
	_ocupado = true
	var t := EstiloUI.mostrar_lista(self, _items, false)
	t.tween_property(_titulo, "modulate:a", 0.0, 0.4)
	t.tween_property(_negro, "color:a", 1.0, 0.55).set_delay(0.15).set_trans(Tween.TRANS_SINE)
	t.chain().tween_callback(func(): get_tree().change_scene_to_file(ESCENA_JUEGO))


func _on_salir() -> void:
	if _ocupado:
		return
	_ocupado = true
	var t := create_tween()
	t.tween_property(_negro, "color:a", 1.0, 0.4)
	t.tween_callback(func(): get_tree().quit())


func _abrir_opciones() -> void:
	if _ocupado:
		return
	_ocupado = true
	EstiloUI.mostrar_lista(self, _items, false)
	EstiloUI.mostrar_panel(self, _panel_opciones, true).chain().tween_callback(func():
		_ocupado = false
		_panel_opciones.get_meta("primero").grab_focus())


func _cerrar_opciones() -> void:
	if _ocupado:
		return
	_ocupado = true
	EstiloUI.mostrar_panel(self, _panel_opciones, false).chain().tween_callback(func():
		EstiloUI.mostrar_lista(self, _items, true)
		_ocupado = false
		_items[1].grab_focus())
