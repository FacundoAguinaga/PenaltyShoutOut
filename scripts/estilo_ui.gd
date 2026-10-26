class_name EstiloUI
extends RefCounted

## Estilo comun de toda la interfaz (menu, partido, pausa y fin): colores,
## letras, opciones de texto con animacion y el panel de opciones. Si se
## cambia algo aca, cambia en todas las pantallas.

const COLOR_TEXTO := Color(0.96, 0.95, 0.92)
const COLOR_TENUE := Color(0.96, 0.95, 0.92, 0.55)
const COLOR_ACENTO := Color(0.91, 0.76, 0.42)
const COLOR_GRIS := Color(0.62, 0.66, 0.72)
const COLOR_PANEL := Color(0.055, 0.07, 0.095, 0.94)
const COLOR_OSCURO := Color(0.025, 0.035, 0.055)
const COLOR_PELIGRO := Color(0.93, 0.42, 0.38)

## Margen izquierdo de los textos en todas las pantallas.
const MARGEN := 96.0

const ANCHO_BARRA := 30.0
const T_HOVER := 0.28

static var _fuentes := {}


static func fuente(peso: int, espaciado: int = 0) -> Font:
	var clave := "%d_%d" % [peso, espaciado]
	if _fuentes.has(clave):
		return _fuentes[clave]
	var base := SystemFont.new()
	base.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial", "sans-serif"])
	base.font_weight = peso
	var f := FontVariation.new()
	f.base_font = base
	f.spacing_glyph = espaciado
	_fuentes[clave] = f
	return f


static func label(texto: String, tam: int, color: Color, f: Font) -> Label:
	var l := Label.new()
	l.text = texto
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", tam)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Sombra suave para textos grandes sobre el juego.
static func sombra(l: Label, alfa: float = 0.3, dy: int = 4) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, alfa))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", dy)
	l.add_theme_constant_override("shadow_outline_size", 3)


## Titulo grande con la linea dorada abajo (la linea se anima en entrar()).
static func titulo(texto: String, tam: int = 68) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var t := label(texto, tam, COLOR_TEXTO, fuente(800, 2))
	t.name = "Texto"
	t.add_theme_constant_override("line_spacing", -int(tam * 0.24))
	sombra(t, 0.28, 5)
	v.add_child(t)
	var linea := ColorRect.new()
	linea.name = "Linea"
	linea.color = COLOR_ACENTO
	linea.custom_minimum_size = Vector2(0, 3)
	linea.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	linea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(linea)
	return v


static func rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func degradado(colores: PackedColorArray, puntos: PackedFloat32Array, vertical: bool) -> TextureRect:
	var g := Gradient.new()
	g.colors = colores
	g.offsets = puntos
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill_to = Vector2(0, 1) if vertical else Vector2(1, 0)
	var t := TextureRect.new()
	t.texture = tex
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Velo oscuro de izquierda a derecha, para que se lea el texto sobre el juego.
static func velo_izquierdo(alfa: float = 0.95) -> TextureRect:
	return degradado(
		PackedColorArray([Color(COLOR_OSCURO, alfa), Color(COLOR_OSCURO, alfa * 0.85), Color(COLOR_OSCURO, alfa * 0.3), Color(COLOR_OSCURO, alfa * 0.1)]),
		PackedFloat32Array([0.0, 0.32, 0.62, 1.0]), false)


static func estilo_panel() -> StyleBoxFlat:
	var e := StyleBoxFlat.new()
	e.bg_color = COLOR_PANEL
	e.set_corner_radius_all(16)
	e.shadow_color = Color(0, 0, 0, 0.55)
	e.shadow_size = 36
	e.shadow_offset = Vector2(0, 14)
	e.border_width_left = 1
	e.border_color = Color(1, 1, 1, 0.06)
	e.content_margin_left = 44
	e.content_margin_right = 44
	e.content_margin_top = 38
	e.content_margin_bottom = 34
	return e


# ------------------------------------------------------------ opciones de texto

## Una opcion de menu: texto solo, sin caja. Con mouse o teclado se resalta
## (aparece una barra dorada, el texto se corre y se ilumina, las demas de la
## misma lista se atenuan) y al apretar hace un pulso.
static func item(texto: String, tam: int = 36, ancho: float = 460.0) -> Button:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(ancho, tam + 30)
	b.focus_mode = Control.FOCUS_ALL
	var vacio := StyleBoxEmpty.new()
	for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(s, vacio)

	# el contenido va en un Control libre para poder correrlo con tweens
	var cont := Control.new()
	cont.name = "Contenido"
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.size = b.custom_minimum_size
	b.add_child(cont)

	var barra := ColorRect.new()
	barra.name = "Barra"
	barra.color = COLOR_ACENTO
	barra.position = Vector2(0, (tam + 30) * 0.5 - 1)
	barra.size = Vector2(0, 2)
	barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cont.add_child(barra)

	var lab := label(texto, tam, COLOR_TENUE, fuente(300, int(tam * 0.14)))
	lab.name = "Texto"
	lab.position = Vector2(0, 8)
	sombra(lab, 0.3, 3)
	cont.add_child(lab)

	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	b.focus_entered.connect(func(): resaltar(b, true))
	b.focus_exited.connect(func(): resaltar(b, false))
	b.button_down.connect(func(): pulso(b))
	return b


static func resaltar(b: Button, activo: bool) -> void:
	if not b.is_inside_tree():
		return
	var cont: Control = b.get_node("Contenido")
	var t := b.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(cont.get_node("Barra"), "size:x", ANCHO_BARRA if activo else 0.0, T_HOVER)
	t.tween_property(cont.get_node("Texto"), "position:x", ANCHO_BARRA + 16.0 if activo else 0.0, T_HOVER)
	t.tween_property(cont.get_node("Texto"), "theme_override_colors/font_color", COLOR_TEXTO if activo else COLOR_TENUE, T_HOVER)
	# las demas opciones de la misma lista se apagan un poco (con el modulate
	# del boton: el del contenido es para mostrar u ocultar la lista)
	var hermanos := b.get_parent().get_children()
	var alguno := false
	for h in hermanos:
		if h is Button and h.has_focus():
			alguno = true
	for h in hermanos:
		if h is Button and h.has_node("Contenido"):
			var apagado: bool = alguno and not h.has_focus()
			h.create_tween().tween_property(h, "modulate", Color(1, 1, 1, 0.5) if apagado else Color.WHITE, T_HOVER)


static func pulso(b: Button) -> void:
	var cont: Control = b.get_node("Contenido")
	var texto: Label = cont.get_node("Texto")
	texto.pivot_offset = Vector2(0, texto.size.y * 0.5)
	var t := b.create_tween()
	t.tween_property(texto, "scale", Vector2(0.94, 0.94), 0.07)
	t.tween_property(texto, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var barra: ColorRect = cont.get_node("Barra")
	var tb := b.create_tween()
	tb.tween_property(barra, "size:x", ANCHO_BARRA * 1.8, 0.1)
	tb.tween_property(barra, "size:x", ANCHO_BARRA, 0.3).set_trans(Tween.TRANS_CUBIC)


## Muestra u oculta una lista de opciones: salen o entran desde la izquierda,
## escalonadas.
static func mostrar_lista(nodo: Node, items: Array, mostrar: bool, demora_inicial: float = 0.0) -> Tween:
	var t := nodo.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var demora := demora_inicial
	for b in items:
		var cont: Control = b.get_node("Contenido")
		b.disabled = not mostrar
		b.focus_mode = Control.FOCUS_ALL if mostrar else Control.FOCUS_NONE
		if mostrar and cont.modulate.a < 0.01:
			cont.position.x = -40.0
		t.tween_property(cont, "modulate:a", 1.0 if mostrar else 0.0, 0.45 if mostrar else 0.3).set_delay(demora)
		t.tween_property(cont, "position:x", 0.0 if mostrar else -50.0, 0.6 if mostrar else 0.4).set_delay(demora)
		demora += 0.08 if mostrar else 0.05
	return t


## Entrada de un titulo: aparece, baja un poco y dibuja la linea dorada.
static func entrar_titulo(nodo: Node, tit: VBoxContainer, demora: float = 0.0) -> Tween:
	var t := nodo.create_tween().set_parallel()
	var y := tit.position.y
	tit.modulate.a = 0.0
	tit.position.y = y - 16
	var linea: Control = tit.get_node("Linea")
	linea.custom_minimum_size.x = 0.0
	t.tween_property(tit, "modulate:a", 1.0, 0.6).set_delay(demora)
	t.tween_property(tit, "position:y", y, 0.9).set_delay(demora).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(linea, "custom_minimum_size:x", 72.0, 0.8).set_delay(demora + 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return t


# ---------------------------------------------------------------- tema y panel

## Tema para los controles de opciones: lineas finas y acento dorado.
static func tema() -> Theme:
	var t := Theme.new()
	t.default_font = fuente(400, 1)
	t.default_font_size = 16

	var riel := StyleBoxFlat.new()
	riel.bg_color = Color(1, 1, 1, 0.12)
	riel.set_corner_radius_all(2)
	riel.content_margin_top = 2
	riel.content_margin_bottom = 2
	var lleno := riel.duplicate()
	lleno.bg_color = COLOR_ACENTO
	var lleno_hover := riel.duplicate()
	lleno_hover.bg_color = COLOR_ACENTO.lightened(0.15)
	t.set_stylebox("slider", "HSlider", riel)
	t.set_stylebox("grabber_area", "HSlider", lleno)
	t.set_stylebox("grabber_area_highlight", "HSlider", lleno_hover)
	t.set_icon("grabber", "HSlider", _circulo(14, COLOR_TEXTO))
	t.set_icon("grabber_highlight", "HSlider", _circulo(16, Color.WHITE))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(1, 1, 1, 0.05)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 14
	normal.content_margin_right = 10
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.1)
	var foco := normal.duplicate()
	foco.draw_center = false
	foco.border_color = Color(COLOR_ACENTO, 0.8)
	foco.set_border_width_all(1)
	for clase in ["OptionButton", "CheckButton"]:
		var es_opcion: bool = clase == "OptionButton"
		t.set_stylebox("normal", clase, normal if es_opcion else StyleBoxEmpty.new())
		t.set_stylebox("hover", clase, hover if es_opcion else StyleBoxEmpty.new())
		t.set_stylebox("pressed", clase, hover if es_opcion else StyleBoxEmpty.new())
		t.set_stylebox("focus", clase, foco)
		t.set_color("font_color", clase, COLOR_TEXTO)
		t.set_color("font_hover_color", clase, Color.WHITE)
		t.set_color("font_pressed_color", clase, COLOR_ACENTO)
		t.set_color("font_focus_color", clase, Color.WHITE)
	t.set_icon("unchecked", "CheckButton", _pastilla(false))
	t.set_icon("checked", "CheckButton", _pastilla(true))

	var popup := StyleBoxFlat.new()
	popup.bg_color = Color(0.08, 0.1, 0.13, 0.98)
	popup.set_corner_radius_all(10)
	popup.shadow_color = Color(0, 0, 0, 0.5)
	popup.shadow_size = 16
	popup.content_margin_top = 6
	popup.content_margin_bottom = 6
	var popup_hover := StyleBoxFlat.new()
	popup_hover.bg_color = Color(COLOR_ACENTO, 0.16)
	popup_hover.set_corner_radius_all(6)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", popup_hover)
	t.set_color("font_color", "PopupMenu", COLOR_TEXTO)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 10)
	return t


## Panel de opciones (audio, pantalla, dificultad, tiros), igual en el menu y
## en la pausa. Guarda en SettingsManager al cambiar cada cosa. Su opcion
## VOLVER queda en la meta "volver" y el primer control en "primero".
static func panel_opciones(settings: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", estilo_panel())
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -520
	panel.offset_right = -64
	panel.offset_top = -240
	panel.offset_bottom = 240
	panel.visible = false

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(label("Opciones", 38, COLOR_TEXTO, fuente(300, 2)))
	v.add_child(_espacio(6))

	var s_master := _fila_slider(v, "Volumen general")
	var s_music := _fila_slider(v, "Música")
	var s_sfx := _fila_slider(v, "Efectos")
	v.add_child(_espacio(4))
	var pantalla := CheckButton.new()
	_fila(v, "Pantalla completa", pantalla)
	var dificultad := OptionButton.new()
	_fila(v, "Dificultad del arquero", dificultad)
	var tiros := OptionButton.new()
	_fila(v, "Tiros por ronda", tiros)
	v.add_child(_espacio(10))
	var volver := item("VOLVER", 30, 360)
	v.add_child(volver)
	panel.set_meta("volver", volver)
	panel.set_meta("primero", s_master)

	if settings:
		s_master.value = settings.master_volume
		s_music.value = settings.music_volume
		s_sfx.value = settings.sfx_volume
		pantalla.button_pressed = settings.fullscreen
	s_master.value_changed.connect(func(val): _guardar(settings, "master_volume", val))
	s_music.value_changed.connect(func(val): _guardar(settings, "music_volume", val))
	s_sfx.value_changed.connect(func(val): _guardar(settings, "sfx_volume", val))
	pantalla.toggled.connect(func(val): _guardar(settings, "fullscreen", val))

	dificultad.add_item("Fácil", 0)
	dificultad.add_item("Medio", 1)
	dificultad.add_item("Difícil", 2)
	if settings:
		dificultad.selected = settings.difficulty
	dificultad.item_selected.connect(func(idx): _guardar(settings, "difficulty", idx))

	var opciones_tiros := [5, 10, 20, 40]
	for i in opciones_tiros.size():
		tiros.add_item("%d tiros" % opciones_tiros[i], i)
	if settings:
		var actual := opciones_tiros.find(settings.shots_per_round)
		tiros.selected = actual if actual != -1 else 0
	tiros.item_selected.connect(func(idx): _guardar(settings, "shots_per_round", opciones_tiros[idx]))
	return panel


## Entra (desde la derecha) o sale el panel de opciones.
static func mostrar_panel(nodo: Node, panel: Control, mostrar: bool) -> Tween:
	var t := nodo.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC)
	var x := panel.position.x
	if mostrar:
		panel.visible = true
		panel.modulate.a = 0.0
		panel.position.x = x + 60.0
		t.set_ease(Tween.EASE_OUT)
		t.tween_property(panel, "modulate:a", 1.0, 0.35).set_delay(0.1)
		t.tween_property(panel, "position:x", x, 0.5).set_delay(0.1)
	else:
		t.set_ease(Tween.EASE_IN)
		t.tween_property(panel, "modulate:a", 0.0, 0.25)
		t.tween_property(panel, "position:x", x + 60.0, 0.3)
		t.chain().tween_callback(func():
			panel.visible = false
			panel.position.x = x)
	return t


static func _guardar(settings: Node, campo: String, valor) -> void:
	if settings:
		settings.set(campo, valor)
		settings.save_settings()


static func _espacio(alto: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, alto)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _fila(padre: Control, texto: String, control: Control) -> void:
	var h := HBoxContainer.new()
	var l := label(texto, 16, COLOR_GRIS, fuente(400, 1))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	control.custom_minimum_size.x = 170
	h.add_child(control)
	padre.add_child(h)


static func _fila_slider(padre: Control, texto: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fila(padre, texto, s)
	return s


static func _pastilla(prendida: bool) -> Texture2D:
	var w := 44
	var h := 24
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fondo := Color(COLOR_ACENTO, 0.9) if prendida else Color(1, 1, 1, 0.16)
	var r := h * 0.5
	var cx := w - r if prendida else r
	for y in h:
		for x in w:
			var px := Vector2(x + 0.5, y + 0.5)
			# pastilla: rectangulo con extremos redondos, y la perilla encima
			var borde := clampf(r - px.distance_to(Vector2(clampf(px.x, r, w - r), r)), 0.0, 1.0)
			var col := Color(fondo, fondo.a * borde)
			var perilla := clampf(r - 3.0 - px.distance_to(Vector2(cx, r)), 0.0, 1.0)
			img.set_pixel(x, y, col.blend(Color(COLOR_TEXTO, perilla)))
	return ImageTexture.create_from_image(img)


static func _circulo(diametro: int, color: Color) -> Texture2D:
	var img := Image.create(diametro, diametro, false, Image.FORMAT_RGBA8)
	var r := diametro * 0.5
	for y in diametro:
		for x in diametro:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(color, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
