extends CanvasLayer

## Pausa, con el estilo del menu (EstiloUI): el juego queda atras oscurecido,
## titulo arriba a la izquierda, opciones de texto a la izquierda y el panel
## de opciones entra desde la derecha. ESC abre y cierra (y si estan abiertas
## las opciones, primero las cierra).

var _raiz: Control
var _fondo: ColorRect
var _velo: TextureRect
var _titulo: VBoxContainer
var _items: Array[Button] = []
var _panel_opciones: PanelContainer
var _ocupado := false


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_raiz = Control.new()
	_raiz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_raiz.theme = EstiloUI.tema()
	add_child(_raiz)

	_fondo = EstiloUI.rect(Color(EstiloUI.COLOR_OSCURO, 0.55))
	_fondo.mouse_filter = Control.MOUSE_FILTER_STOP
	_raiz.add_child(_fondo)
	_velo = EstiloUI.velo_izquierdo(0.9)
	_raiz.add_child(_velo)

	_titulo = EstiloUI.titulo("PAUSA", 64)
	_titulo.position = Vector2(EstiloUI.MARGEN, 72)
	_raiz.add_child(_titulo)

	var lista := VBoxContainer.new()
	lista.add_theme_constant_override("separation", 2)
	lista.position = Vector2(EstiloUI.MARGEN, 220)
	_raiz.add_child(lista)
	var acciones := [
		["CONTINUAR", resume],
		["REINICIAR", _on_restart_pressed],
		["OPCIONES", _abrir_opciones],
		["MENÚ PRINCIPAL", _on_main_menu_pressed],
		["SALIR", _on_quit_pressed],
	]
	for a in acciones:
		var b := EstiloUI.item(a[0], 30, 420)
		b.pressed.connect(a[1])
		lista.add_child(b)
		_items.append(b)

	_panel_opciones = EstiloUI.panel_opciones(get_node_or_null("/root/SettingsManager"))
	_panel_opciones.get_meta("volver").pressed.connect(_cerrar_opciones)
	_raiz.add_child(_panel_opciones)


func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		if _panel_opciones.visible:
			_cerrar_opciones()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()


func toggle_pause():
	if _ocupado:
		return
	if get_tree().paused:
		resume()
	else:
		_abrir()


func _abrir() -> void:
	get_tree().paused = true
	visible = true
	_ocupado = true
	_panel_opciones.visible = false
	_fondo.modulate.a = 0.0
	_velo.modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(_fondo, "modulate:a", 1.0, 0.3)
	t.tween_property(_velo, "modulate:a", 1.0, 0.4)
	EstiloUI.entrar_titulo(self, _titulo, 0.05)
	for b in _items:
		b.get_node("Contenido").modulate.a = 0.0
	EstiloUI.mostrar_lista(self, _items, true, 0.15).chain().tween_callback(func():
		_ocupado = false
		_items[0].grab_focus())


func resume():
	if _ocupado:
		return
	_ocupado = true
	var t := EstiloUI.mostrar_lista(self, _items, false)
	t.tween_property(_titulo, "modulate:a", 0.0, 0.25)
	t.tween_property(_fondo, "modulate:a", 0.0, 0.3)
	t.tween_property(_velo, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(func():
		visible = false
		get_tree().paused = false
		_ocupado = false)


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
		_items[2].grab_focus())


func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_quit_pressed():
	get_tree().quit()
