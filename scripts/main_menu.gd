extends Control

## Menu principal con fondo 3D en vivo del estadio: tomas cinematográficas lentas
## con rotación y paneo suave, luces de estadio nocturnas, humo y atmósfera,
## combinadas con la interfaz tipográfica moderna y opciones de EstiloUI.
## Incluye reproducción aleatoria de música con indicador 'Now Playing' en la esquina inferior derecha.

const ESCENA_JUEGO := "res://scenes/game.tscn"
const SCENE_STADIUM := "res://scenes/stadium.tscn"
const RES_ENV := "res://resources/stadium_environment.tres"
const Y_TITULO := 72.0

var _viewport_container: SubViewportContainer
var _sub_viewport: SubViewport
var _camera: Camera3D
var _cam_pivot: Node3D
var _stadium: Node3D
var _world_env: WorldEnvironment

var _titulo: VBoxContainer
var _lista: VBoxContainer
var _items: Array[Button] = []
var _panel_opciones: PanelContainer
var _negro: ColorRect
var _mouse_suave := Vector2.ZERO
var _ocupado := false

# Cartel de 'Now Playing' en la esquina inferior derecha
var _music_badge: PanelContainer
var _badge_label_title: Label
var _badge_label_artist: Label

# Secuencia cinematográfica de tomas para el menú
var _shots: Array[Dictionary] = [
	{
		# Toma 1: Panorámica aérea sobrevolando las gradas hacia el arco
		"pos": Vector3(-12.0, 16.0, 20.0),
		"look": Vector3(0.0, 1.5, -11.0),
		"fov": 58.0,
		"target_pos": Vector3(-5.0, 14.5, 10.0),
		"duration": 14.0
	},
	{
		# Toma 2: A ras de césped en el centro del campo mirando las torres de luz y arco
		"pos": Vector3(8.0, 1.2, 8.0),
		"look": Vector3(-2.0, 2.0, -11.0),
		"fov": 50.0,
		"target_pos": Vector3(2.0, 1.0, -2.0),
		"duration": 12.0
	},
	{
		# Toma 3: Desde la tribuna lateral alta con vista panorámica completa de todo el estadio
		"pos": Vector3(32.0, 19.0, -5.0),
		"look": Vector3(0.0, 2.0, 15.0),
		"fov": 62.0,
		"target_pos": Vector3(28.0, 17.5, 5.0),
		"duration": 15.0
	},
	{
		# Toma 4: Detrás del arco mirando hacia el campo abierto y la hinchada
		"pos": Vector3(0.0, 2.2, -18.0),
		"look": Vector3(0.0, 4.0, 10.0),
		"fov": 55.0,
		"target_pos": Vector3(3.0, 2.5, -14.0),
		"duration": 13.0
	}
]
var _current_shot_idx: int = 0
var _cam_tween: Tween


func _ready() -> void:
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = EstiloUI.tema()
	
	_armar_fondo_3d()

	_titulo = EstiloUI.titulo("PENALTY
SHOOTOUT")
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

	_armar_badge_musica()

	_negro = EstiloUI.rect(EstiloUI.COLOR_OSCURO)
	add_child(_negro)
	_animar_entrada()

	# Iniciar música de menú aleatoria a través del SoundManager
	_iniciar_musica()


func _process(delta: float) -> void:
	# Paralaje 3D sutil con el movimiento del ratón
	if _cam_pivot and is_instance_valid(_cam_pivot):
		var centro := size * 0.5
		var objetivo := (get_local_mouse_position() - centro) / maxf(centro.x, 1.0)
		_mouse_suave = _mouse_suave.lerp(objetivo.clamp(-Vector2.ONE, Vector2.ONE), 1.0 - exp(-3.0 * delta))
		_cam_pivot.rotation.y = -_mouse_suave.x * 0.05
		_cam_pivot.rotation.x = -_mouse_suave.y * 0.03


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _panel_opciones.visible and not _ocupado:
		_cerrar_opciones()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			_on_skip_pressed()
			get_viewport().set_input_as_handled()


func _armar_fondo_3d() -> void:
	# Contenedor para renderizar el mundo 3D debajo de la interfaz 2D
	_viewport_container = SubViewportContainer.new()
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.handle_input_locally = false
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport_container.add_child(_sub_viewport)

	# World3D con iluminación y ambiente nocturno
	var world_3d := World3D.new()
	_sub_viewport.world_3d = world_3d

	_world_env = WorldEnvironment.new()
	if ResourceLoader.exists(RES_ENV):
		_world_env.environment = load(RES_ENV)
	_sub_viewport.add_child(_world_env)

	# Instanciar el estadio completo con toda la iluminación
	if ResourceLoader.exists(SCENE_STADIUM):
		_stadium = load(SCENE_STADIUM).instantiate()
		_sub_viewport.add_child(_stadium)

	# Sistema de cámara cinemática
	_cam_pivot = Node3D.new()
	_sub_viewport.add_child(_cam_pivot)

	_camera = Camera3D.new()
	_camera.current = true
	_cam_pivot.add_child(_camera)

	# Gradiente de velo oscuro en el lado izquierdo para asegurar legibilidad impecable de los textos
	add_child(EstiloUI.velo_izquierdo(0.88))

	# Viñeta oscura sutil arriba y abajo
	var c := EstiloUI.COLOR_OSCURO
	add_child(EstiloUI.degradado(
		PackedColorArray([Color(c, 0.45), Color(c, 0.0), Color(c, 0.0), Color(c, 0.75)]),
		PackedFloat32Array([0.0, 0.25, 0.65, 1.0]), true))

	_reproducir_toma(0)


func _armar_badge_musica() -> void:
	_music_badge = PanelContainer.new()
	_music_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Estilo elegante traslúcido
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.78)
	sb.border_width_left = 3
	sb.border_color = EstiloUI.COLOR_ACENTO
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_music_badge.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	_music_badge.add_child(hb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)

	var tag := Label.new()
	tag.text = "EN REPRODUCCIÓN ♪"
	tag.add_theme_font_override("font", EstiloUI.fuente(500, 1))
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", EstiloUI.COLOR_ACENTO)
	vb.add_child(tag)

	_badge_label_title = Label.new()
	_badge_label_title.text = "---"
	_badge_label_title.add_theme_font_override("font", EstiloUI.fuente(400, 0))
	_badge_label_title.add_theme_font_size_override("font_size", 14)
	_badge_label_title.add_theme_color_override("font_color", EstiloUI.COLOR_TEXTO)
	vb.add_child(_badge_label_title)

	# Botón interactivo para saltar de pista
	var btn_skip := Button.new()
	btn_skip.text = "⏭ SALTEAR"
	btn_skip.flat = true
	btn_skip.focus_mode = Control.FOCUS_NONE
	btn_skip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn_skip.add_theme_font_override("font", EstiloUI.fuente(500, 1))
	btn_skip.add_theme_font_size_override("font_size", 12)
	btn_skip.add_theme_color_override("font_color", EstiloUI.COLOR_TENUE)
	btn_skip.add_theme_color_override("font_hover_color", EstiloUI.COLOR_ACENTO)
	btn_skip.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn_skip.pressed.connect(_on_skip_pressed)
	hb.add_child(btn_skip)

	add_child(_music_badge)
	_ubicar_badge_musica()
	resized.connect(_ubicar_badge_musica)

func _on_skip_pressed() -> void:
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("skip_track"):
		sm.skip_track()


func _ubicar_badge_musica() -> void:
	if _music_badge:
		var s := _music_badge.get_combined_minimum_size()
		_music_badge.position = Vector2(size.x - s.x - 36.0, size.y - s.y - 28.0)


func _iniciar_musica() -> void:
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		if not sm.song_changed.is_connected(_on_song_changed):
			sm.song_changed.connect(_on_song_changed)
		sm.play_random_music()
		var info = sm.get_current_track_info()
		_mostrar_cancion(info.get("title", ""), info.get("artist", ""))


func _on_song_changed(title: String, artist: String) -> void:
	_mostrar_cancion(title, artist)


func _mostrar_cancion(title: String, artist: String) -> void:
	if _badge_label_title:
		_badge_label_title.text = title if artist.is_empty() else ("%s  -  %s" % [title, artist])
		_ubicar_badge_musica.call_deferred()
		
		# Animación de pulso/fade al cambiar de pista
		if _music_badge:
			var t := create_tween()
			_music_badge.modulate.a = 0.0
			t.tween_property(_music_badge, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)


func _reproducir_toma(idx: int) -> void:
	if idx >= _shots.size():
		idx = 0
	_current_shot_idx = idx
	var shot = _shots[idx]

	if _cam_tween:
		_cam_tween.kill()

	_camera.fov = shot["fov"]
	_camera.global_position = shot["pos"]
	_camera.look_at(shot["look"], Vector3.UP)

	_cam_tween = create_tween()
	_cam_tween.tween_property(_camera, "global_position", shot["target_pos"], shot["duration"]).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_callback(func(): _reproducir_toma(idx + 1))


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
	# Detener música suavemente al iniciar el partido
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_method("stop_music"):
		sm.stop_music(0.8)

	var t := EstiloUI.mostrar_lista(self, _items, false)
	t.tween_property(_titulo, "modulate:a", 0.0, 0.4)
	if _music_badge:
		t.tween_property(_music_badge, "modulate:a", 0.0, 0.3)
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
