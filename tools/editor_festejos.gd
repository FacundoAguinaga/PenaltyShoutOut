extends Node3D

## Editor de festejos y escenas de equipo (F6 sobre tools/editor_festejos.tscn, o
## `godot --path . res://tools/editor_festejos.tscn`).
##
## Reproduce cada festejo grupal, cada escena de equipo y la copa con todos sus actores,
## como los pone el juego, y deja corregir a mano lo que la extraccion de PES dejo corrido:
## mover y girar a cada jugador, adelantar o atrasar su clip, ocultarlo, y sacar del juego
## los festejos que no sirven. Se guarda en resources/festejos_ajustes.json
## (FestejosAjustes), que el juego aplica encima de lo extraido.
##
## Mouse: clic elige jugador, arrastrar lo mueve por el piso; boton derecho gira la camara,
## la ruedita acerca, el boton del medio la corre.
## Teclado: flechas mueven 5 cm (Shift: 25 cm, Alt: 1 cm) segun hacia donde mira la camara,
## Q / E giran 5 grados (Shift: 15, Alt: 1), Z / X atrasan o adelantan su clip 0,05 s
## (Shift: 0,25), Tab pasa al siguiente, H lo oculta, Espacio reproduce o pausa, Inicio
## vuelve al principio, , y . avanzan de a un cuadro, Ctrl+Z deshace, Ctrl+S guarda.

const Cin := preload("res://scripts/cinematicas.gd")
const COLORES := [Color("ffd166"), Color("06d6a0"), Color("4cc9f0"), Color("f72585"), Color("b5179e"), Color("fb8500"),
	Color("8ac926"), Color("ff595e"), Color("c0c0c0"), Color("7209b7"), Color("3a86ff"), Color("ffbe0b")]
const KITS := ["rojo", "rojo_moreno", "rojo_rubio", "rojo_canela"]
const PASO_CUADRO := 1.0 / 30.0
const MUESTRAS_CAMINO := 0.1

var _escenas_crudas: Dictionary = {}
var _grupales_crudos: Array = []
var _descartados_crudos: Array = []
## Cada escena del menu: nombre, tipo ("grupal", "escena", "solo"), elenco (corte, actor,
## escala), desde (segundo de los clips en que arranca en el juego), largo (lo que se ve).
var _menu: Array[Dictionary] = []
var _escena: Dictionary = {}
var _ajustes: Dictionary = {}
var _deshacer: Array[String] = []
var _sin_guardar := false

var _modelo: Node3D
var _actores: Array[Dictionary] = []
var _elegido := -1
var _t := 0.0
var _reproduciendo := true
var _velocidad := 1.0
var _origen := Vector3.ZERO

var _camara: Camera3D
var _foco := Vector3(0, 0.9, 0)
var _yaw := 0.6
var _pitch := -0.45
var _distancia := 12.0
var _arrastrando := false
var _arrastre_inicio := Vector3.ZERO
var _arrastre_ajuste := Vector2.ZERO
var _podio: Node3D

# UI
var _ui_escena: OptionButton
var _ui_usar: CheckBox
var _ui_desde: SpinBox
var _ui_lista: ItemList
var _ui_x: SpinBox
var _ui_z: SpinBox
var _ui_giro: SpinBox
var _ui_desfase: SpinBox
var _ui_oculto: CheckBox
var _ui_info: Label
var _ui_tiempo: HSlider
var _ui_t: Label
var _ui_play: Button
var _ui_estado: Label
var _ui_caminos: CheckBox
var _actualizando := false
var _cargando: Label

func _ready() -> void:
	_armar_mundo()
	_cargando = Label.new()
	_cargando.text = "Cargando jugadores y animaciones..."
	_cargando.add_theme_font_size_override("font_size", 24)
	_cargando.position = Vector2(40, 40)
	var capa := CanvasLayer.new()
	capa.add_child(_cargando)
	add_child(capa)
	if not PesAnimaciones.disponible():
		_cargando.text = "No estan las animaciones de PES (animaciones_pes/). Ver docs/animaciones_pes.md."
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_cargar()

func _cargar() -> void:
	_escenas_crudas = JSON.parse_string(FileAccess.get_file_as_string(PesAnimaciones.DIR + "escenas.json"))
	var datos: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PesAnimaciones.DIR + "datos.json"))
	_grupales_crudos = datos.get("festejos_grupales", [])
	_descartados_crudos = datos.get("festejos_grupales_descartados", [])
	_ajustes = FestejosAjustes.todos().duplicate(true)

	var juego: Node = load("res://scenes/game.tscn").instantiate()
	_modelo = juego.get_node("Kicker/player2").duplicate()
	juego.free()
	var sk: Skeleton3D = _modelo.get_node("Node/Skeleton3D")
	for hijo in sk.get_children():
		if not hijo is MeshInstance3D:
			sk.remove_child(hijo)
			hijo.free()

	_armar_menu(datos.get("festejos_gol", []))
	_cargando.get_parent().queue_free()
	_armar_ui()
	_elegir_escena(0)

# ---------------------------------------------------------------------------
# Que se puede editar
# ---------------------------------------------------------------------------

func _armar_menu(solos: Array) -> void:
	for g: Dictionary in _grupales_crudos:
		var corte := str(g["corte"])
		_menu.append({"nombre": "Grupal %s (%d)" % [corte.replace("goal_", "").replace("_base", ""), (g["actores"] as Array).size()],
			"tipo": "grupal", "corte": corte, "elenco": _elenco(corte, g["actores"], PesAnimaciones.ESCALA_CON_CARRERA),
			"desde": 0.0, "largo": float(g["largo"])})
	# Los que la build descarta: no salen en el juego hasta que se los activa.
	for g: Dictionary in _descartados_crudos:
		var corte := str(g["corte"])
		_menu.append({"nombre": "Descartado %s (%d): %s" % [corte.replace("goal_", "").replace("_base", ""), (g["actores"] as Array).size(), g.get("motivo", "")],
			"tipo": "grupal", "descartado": true, "motivo": str(g.get("motivo", "")), "corte": corte,
			"elenco": _elenco(corte, g["actores"], PesAnimaciones.ESCALA_CON_CARRERA), "desde": 0.0, "largo": float(g["largo"])})
	var esc := PesAnimaciones.ESCALA_ESCENAS
	var con_carrera := PesAnimaciones.ESCALA_CON_CARRERA
	_agregar_escena("Previa: ronda", Cin.ESCENA_RONDA, func(_a): return true, esc, Cin.DESDE_RONDA, Cin.DURACION_RONDA)
	var sobran := _puntas_sobrantes(Cin.ESCENA_FILAS)
	_agregar_escena("Previa: filas", Cin.ESCENA_FILAS, func(a): return absf(float(a["pos"][0])) < Cin.ANCHO_FILAS and not a in sobran,
		esc, Cin.ADELANTO_FILAS, Cin.DURACION_FILA + Cin.DURACION_CARAS)
	_agregar_escena("Filas tras un fallo", Cin.ESCENA_REACCION_FALLO, func(_a): return true, esc, 0.0, Cin.DURACION_PLANO_EQUIPO)
	_agregar_escena("Final: abrazo del ganador", Cin.ESCENA_ABRAZO, func(_a): return true, con_carrera, Cin.DESDE_ABRAZO, Cin.DURACION_ABRAZO)
	_agregar_escena("Final: perdedores abatidos", Cin.ESCENA_ABATIDOS, func(_a): return true, esc, 0.0, Cin.DURACION_ABATIDOS)
	# La copa: el capitan sale de otro corte y todo se pone para que el quede en el centro.
	var capitan: Dictionary = (_escenas_crudas.get(Cin.ESCENA_CAPITAN, []) as Array)[0]
	var elenco := _elenco(Cin.ESCENA_CAPITAN, [capitan], esc)
	var equipo: Array = (_escenas_crudas.get(Cin.ESCENA_COPA, []) as Array).filter(func(a): return str(a["clip"]).begins_with("dml_end_trophy01"))
	elenco.append_array(_elenco(Cin.ESCENA_COPA, equipo, esc, _escenas_crudas[Cin.ESCENA_COPA]))
	var p: Array = capitan["pos"]
	_menu.append({"nombre": "Final: copa", "tipo": "escena", "corte": Cin.ESCENA_COPA, "elenco": elenco,
		"desde": Cin.DESDE_COPA, "largo": Cin.LARGO_COPA - Cin.DESDE_COPA, "origen": -PesAnimaciones.lugar_pes(float(p[0]), 0.0, float(p[2])), "podio": true})
	var vistos := {}
	for f: Array in Cin.FESTEJOS:
		vistos[f[0]] = true
	for n in solos:
		vistos[n] = true
	for n: String in vistos:
		_menu.append({"nombre": "Solo: " + n.replace("dml_goal_celebrate_", "celebrate ").replace("dm_goal_", "").replace("dm_pfm_", ""),
			"tipo": "solo", "corte": n, "elenco": [{"corte": n, "actor": {"clip": n, "pos": [0, 0, 0], "giro": 0.0}, "clave": n + "#0", "escala": 1.0}],
			"desde": 0.0, "largo": 0.0})

func _agregar_escena(nombre: String, corte: String, filtro: Callable, escala: float, desde: float, largo: float) -> void:
	if not _escenas_crudas.has(corte):
		return
	var todos: Array = _escenas_crudas[corte]
	_menu.append({"nombre": nombre, "tipo": "escena", "corte": corte, "elenco": _elenco(corte, todos.filter(filtro), escala, todos),
		"desde": desde, "largo": largo})

## Los actores de un corte con su clave (calculada sobre la lista completa del corte, como
## en el juego).
func _elenco(corte: String, actores: Array, escala: float, lista_completa: Array = []) -> Array:
	var completa := lista_completa if not lista_completa.is_empty() else actores
	var claves := FestejosAjustes.claves(completa)
	var salida := []
	for a: Dictionary in actores:
		salida.append({"corte": corte, "actor": a, "clave": claves[completa.find(a)], "escala": escala})
	return salida

## La misma cuenta que Cinematicas._puntas_sobrantes, sobre las escenas sin ajustar.
func _puntas_sobrantes(corte: String) -> Array:
	var sobran := []
	for lado in [-1.0, 1.0]:
		var fila: Array = (_escenas_crudas.get(corte, []) as Array).filter(func(a): return absf(float(a["pos"][0])) < Cin.ANCHO_FILAS and signf(float(a["pos"][2])) == lado)
		if fila.is_empty():
			continue
		fila.sort_custom(func(a, b): return float(a["pos"][2]) < float(b["pos"][2]))
		for punta: Dictionary in [fila[0], fila[-1]]:
			if fila.filter(func(a): return a["clip"] == punta["clip"]).size() > 1:
				sobran.append(punta)
	return sobran

# ---------------------------------------------------------------------------
# Ajustes
# ---------------------------------------------------------------------------

func _ajuste_escena(corte: String, crear := false) -> Dictionary:
	if not _ajustes.has(corte):
		if not crear:
			return {}
		_ajustes[corte] = {}
	return _ajustes[corte]

func _ajuste(i: int, crear := false) -> Dictionary:
	var e: Dictionary = _escena["elenco"][i]
	var de_escena := _ajuste_escena(e["corte"], crear)
	if not de_escena.has("actores"):
		if not crear:
			return {}
		de_escena["actores"] = {}
	var actores: Dictionary = de_escena["actores"]
	if not actores.has(e["clave"]):
		if not crear:
			return {}
		actores[e["clave"]] = {}
	return actores[e["clave"]]

## El ajuste del actor como lo arma FestejosAjustes.de_actor: con el adelanto de la escena.
func _ajuste_completo(i: int) -> Dictionary:
	var a := _ajuste(i).duplicate()
	var e: Dictionary = _escena["elenco"][i]
	a["desfase"] = float(a.get("desfase", 0.0)) + float(_ajuste_escena(e["corte"]).get("desde", 0.0))
	return a

func _recordar() -> void:
	_deshacer.append(JSON.stringify(_ajustes))
	if _deshacer.size() > 200:
		_deshacer.pop_front()

func _cambio() -> void:
	_sin_guardar = true
	_colocar_todos()
	_refrescar_ui()

func _cambiar(i: int, campo: String, valor) -> void:
	if i < 0:
		return
	_recordar()
	_ajuste(i, true)[campo] = valor
	_cambio()

func _sumar(i: int, campo: String, cuanto: float) -> void:
	if i < 0:
		return
	_cambiar(i, campo, snappedf(float(_ajuste(i).get(campo, 0.0)) + cuanto, 0.001))

func _deshacer_ultimo() -> void:
	if _deshacer.is_empty():
		return
	_ajustes = JSON.parse_string(_deshacer.pop_back())
	_cambio()

func _guardar() -> void:
	var copia := _ajustes.duplicate(true)
	var err := FestejosAjustes.guardar(copia)
	if err != OK:
		_ui_estado.text = "No se pudo guardar (%s)" % error_string(err)
		return
	_ajustes = copia.duplicate(true)
	PesAnimaciones.recargar()
	_sin_guardar = false
	_refrescar_ui()

# ---------------------------------------------------------------------------
# Escena en pantalla
# ---------------------------------------------------------------------------

func _elegir_escena(indice: int) -> void:
	_escena = _menu[indice]
	_origen = _escena.get("origen", Vector3.ZERO)
	while _actores.size() < (_escena["elenco"] as Array).size():
		_actores.append(_crear_actor(_actores.size()))
	for i in _actores.size():
		var c := _actores[i]
		var usado := i < (_escena["elenco"] as Array).size()
		(c["raiz"] as Node3D).visible = usado
		(c["camino"] as Node3D).visible = usado
		(c["marca"] as Node3D).visible = usado
		if not usado:
			(c["ap"] as AnimationPlayer).stop()
			continue
		var e: Dictionary = _escena["elenco"][i]
		var ap: AnimationPlayer = c["ap"]
		var anim := "pes/" + str(e["actor"]["clip"])
		c["anim"] = anim if ap.has_animation(anim) else ""
		if c["anim"] != "":
			ap.play(anim, 0.0)
			ap.speed_scale = 0.0
	if _escena["tipo"] == "solo" and _actores[0]["anim"] != "":
		_escena["largo"] = (_actores[0]["ap"] as AnimationPlayer).get_animation(_actores[0]["anim"]).length
	if _podio:
		_podio.queue_free()
		_podio = null
	if _escena.get("podio", false):
		_podio = _armar_podio()
		add_child(_podio)
	_elegido = 0
	_t = 0.0
	_colocar_todos()
	_encuadrar()
	_refrescar_ui()

func _crear_actor(i: int) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = "Actor%d" % i
	add_child(raiz)
	var modelo: Node3D = _modelo.duplicate()
	raiz.add_child(modelo)
	var sk: Skeleton3D = modelo.get_node("Node/Skeleton3D")
	var malla: MeshInstance3D = sk.get_child(0)
	malla.set_surface_override_material(0, load("res://Player/kits/material_%s.tres" % KITS[i % KITS.size()]))
	var ap: AnimationPlayer = modelo.get_node("AnimationPlayer")
	PesAnimaciones.cargar_libreria(ap, "pateador.res", true)
	PesAnimaciones.cuidar_piso(raiz, sk)
	var color: Color = COLORES[i % COLORES.size()]

	var camino := MeshInstance3D.new()
	camino.mesh = ImmediateMesh.new()
	camino.top_level = true
	camino.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camino.material_override = _material_linea(color)
	add_child(camino)

	var marca := MeshInstance3D.new()
	var anillo := TorusMesh.new()
	anillo.inner_radius = 0.32
	anillo.outer_radius = 0.4
	anillo.rings = 24
	marca.mesh = anillo
	marca.material_override = _material_linea(color)
	marca.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marca.top_level = true
	add_child(marca)
	var nombre := Label3D.new()
	nombre.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nombre.no_depth_test = true
	nombre.font_size = 48
	nombre.pixel_size = 0.005
	nombre.outline_size = 10
	nombre.modulate = color
	nombre.position = Vector3(0, 2.15, 0)
	marca.add_child(nombre)
	return {"raiz": raiz, "ap": ap, "sk": sk, "malla": malla, "camino": camino, "marca": marca, "nombre": nombre, "anim": "", "color": color}

func _material_linea(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = false
	return m

## En que segundo de su clip esta el actor i cuando la escena va por `t`.
func _t_clip(i: int, t: float) -> float:
	return float(_escena["desde"]) + t + float(_ajuste_completo(i).get("desfase", 0.0))

func _colocar_todos() -> void:
	for i in (_escena["elenco"] as Array).size():
		var e: Dictionary = _escena["elenco"][i]
		var c := _actores[i]
		var actor: Dictionary = (e["actor"] as Dictionary).duplicate()
		actor["ajuste"] = _ajuste_completo(i)
		(c["raiz"] as Node3D).global_transform = PesAnimaciones.lugar_actor(actor, _origen, float(e["escala"]))
		var oculto: bool = _ajuste(i).get("oculto", false)
		(c["malla"] as GeometryInstance3D).transparency = 0.8 if oculto else 0.0
		var nombre: String = str(e["actor"]["clip"]).get_slice("_", str(e["actor"]["clip"]).get_slice_count("_") - 1)
		(c["nombre"] as Label3D).text = ("%d %s" % [i + 1, nombre]) + (" (oculto)" if oculto else "")
		(c["malla"] as MeshInstance3D).material_overlay = _resaltado() if i == _elegido else null
	_mostrar_tiempo()
	_dibujar_caminos()

var _mat_resaltado: StandardMaterial3D
func _resaltado() -> StandardMaterial3D:
	if _mat_resaltado == null:
		_mat_resaltado = StandardMaterial3D.new()
		_mat_resaltado.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat_resaltado.albedo_color = Color(1.0, 0.85, 0.2, 0.28)
		_mat_resaltado.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat_resaltado.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return _mat_resaltado

func _mostrar_tiempo() -> void:
	for i in (_escena["elenco"] as Array).size():
		var c := _actores[i]
		if c["anim"] == "":
			continue
		var ap: AnimationPlayer = c["ap"]
		var largo := ap.get_animation(c["anim"]).length
		ap.seek(clampf(_t_clip(i, _t), 0.0, largo - 0.001), true)
		(c["sk"] as Skeleton3D).force_update_all_bone_transforms()
		var cadera := _cadera(i)
		(c["marca"] as Node3D).global_position = Vector3(cadera.x, 0.02, cadera.z)
	_refrescar_info()

func _cadera(i: int) -> Vector3:
	var sk: Skeleton3D = _actores[i]["sk"]
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(PesAnimaciones.CADERA)).origin

## El recorrido de la cadera de cada uno por el piso, de lo que se ve en el juego.
func _dibujar_caminos() -> void:
	var ver := _ui_caminos == null or _ui_caminos.button_pressed
	for i in (_escena["elenco"] as Array).size():
		var c := _actores[i]
		var malla: ImmediateMesh = (c["camino"] as MeshInstance3D).mesh
		malla.clear_surfaces()
		if not ver or c["anim"] == "":
			continue
		var anim := (c["ap"] as AnimationPlayer).get_animation(c["anim"])
		var pista := anim.find_track("Node/Skeleton3D:" + PesAnimaciones.CADERA, Animation.TYPE_POSITION_3D)
		if pista < 0:
			# Clip en el lugar (sin pista de cadera): no hay recorrido que dibujar.
			continue
		var sk: Skeleton3D = c["sk"]
		malla.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var t := 0.0
		var largo: float = _escena["largo"]
		while t <= largo + 0.001:
			var p := sk.global_transform * anim.position_track_interpolate(pista, clampf(_t_clip(i, t), 0.0, anim.length))
			malla.surface_add_vertex(Vector3(p.x, 0.03, p.z))
			t += MUESTRAS_CAMINO
		malla.surface_end()

func _encuadrar() -> void:
	var centro := Vector3.ZERO
	var n := (_escena["elenco"] as Array).size()
	for i in n:
		centro += _cadera(i)
	_foco = Vector3(centro.x / n, 0.9, centro.z / n)
	var abierto := 0.0
	for i in n:
		abierto = maxf(abierto, Vector2(_cadera(i).x - _foco.x, _cadera(i).z - _foco.z).length())
	_distancia = clampf(abierto * 2.6, 7.0, 40.0)
	_mover_camara()

func _armar_podio() -> Node3D:
	var podio := Node3D.new()
	var tela := StandardMaterial3D.new()
	tela.albedo_color = Color(0.06, 0.08, 0.14)
	var esc := PesAnimaciones.ESCALA_ESCENAS
	for e: Array in Cin.ESCALONES:
		var alto: float = e[4]
		var caja := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3((float(e[3]) - float(e[2])) * esc, alto, (float(e[1]) - float(e[0])) * esc)
		caja.mesh = m
		caja.material_override = tela
		podio.add_child(caja)
		caja.position = _origen + PesAnimaciones.lugar_pes((float(e[0]) + float(e[1])) * 0.5, alto * 0.5, (float(e[2]) + float(e[3])) * 0.5)
	return podio

# ---------------------------------------------------------------------------
# Cuadro a cuadro
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _escena.is_empty():
		return
	if _reproduciendo:
		_t += delta * _velocidad
		if _t > float(_escena["largo"]):
			_t = 0.0
		_mostrar_tiempo()
		_actualizando = true
		_ui_tiempo.value = _t
		_actualizando = false

func _refrescar_info() -> void:
	if _ui_info == null or _elegido < 0:
		return
	var yo := _cadera(_elegido)
	var cerca := INF
	var quien := -1
	for i in (_escena["elenco"] as Array).size():
		if i == _elegido or _ajuste(i).get("oculto", false):
			continue
		var d := Vector2(yo.x - _cadera(i).x, yo.z - _cadera(i).z).length()
		if d < cerca:
			cerca = d
			quien = i
	var texto := "Clip: %s\nEn el clip: %.2f s" % [_escena["elenco"][_elegido]["actor"]["clip"], _t_clip(_elegido, _t)]
	if quien >= 0:
		texto += "\nMas cerca: %d, a %.2f m (cadera a cadera)" % [quien + 1, cerca]
	if _actores[_elegido]["anim"] == "":
		texto += "\n¡Este clip no esta en pateador.res!"
	if _escena.get("descartado", false):
		texto += "\nLa build lo descarto: %s.\nActivalo con \"Usar en el juego\" cuando se vea bien." % _escena["motivo"]
	_ui_info.text = texto
	_ui_t.text = "%.2f / %.2f s" % [_t, float(_escena["largo"])]

# ---------------------------------------------------------------------------
# Entrada
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _escena.is_empty():
		return
	if event is InputEventMouseButton:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_UP and b.pressed:
			_distancia = maxf(_distancia * 0.9, 2.0)
			_mover_camara()
		elif b.button_index == MOUSE_BUTTON_WHEEL_DOWN and b.pressed:
			_distancia = minf(_distancia * 1.1, 60.0)
			_mover_camara()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			get_viewport().gui_release_focus()
			if b.pressed:
				var i := _actor_bajo(b.position)
				if i >= 0:
					_elegir_actor(i)
					_arrastrando = true
					_arrastre_inicio = _en_el_piso(b.position)
					var aj := _ajuste(i)
					_arrastre_ajuste = Vector2(float(aj.get("x", 0.0)), float(aj.get("z", 0.0)))
					_recordar()
			else:
				_arrastrando = false
	elif event is InputEventMouseMotion:
		var m := event as InputEventMouseMotion
		if m.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_yaw -= m.relative.x * 0.006
			_pitch = clampf(_pitch - m.relative.y * 0.006, -1.5, -0.05)
			_mover_camara()
		elif m.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var b := _camara.global_basis
			_foco += (-b.x * m.relative.x + Vector3(b.z.x, 0, b.z.z).normalized() * -m.relative.y) * _distancia * 0.0015
			_mover_camara()
		elif _arrastrando and _elegido >= 0:
			var ahora := _en_el_piso(m.position)
			var d := ahora - _arrastre_inicio
			var aj := _ajuste(_elegido, true)
			aj["x"] = snappedf(_arrastre_ajuste.x + d.x, 0.01)
			aj["z"] = snappedf(_arrastre_ajuste.y + d.z, 0.01)
			_cambio()
	elif event is InputEventKey and event.pressed:
		_tecla(event as InputEventKey)

func _tecla(k: InputEventKey) -> void:
	var mucho := k.shift_pressed
	var poco := k.alt_pressed
	var paso := 0.25 if mucho else (0.01 if poco else 0.05)
	var grados := 15.0 if mucho else (1.0 if poco else 5.0)
	var b := _camara.global_basis
	var derecha := Vector3(b.x.x, 0, b.x.z).normalized()
	var adelante := Vector3(-b.z.x, 0, -b.z.z).normalized()
	if k.ctrl_pressed and k.keycode == KEY_S:
		_guardar()
	elif k.ctrl_pressed and k.keycode == KEY_Z:
		_deshacer_ultimo()
	elif k.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN] and _elegido >= 0:
		var d := Vector3.ZERO
		match k.keycode:
			KEY_LEFT: d = -derecha
			KEY_RIGHT: d = derecha
			KEY_UP: d = adelante
			KEY_DOWN: d = -adelante
		_recordar()
		var aj := _ajuste(_elegido, true)
		aj["x"] = snappedf(float(aj.get("x", 0.0)) + d.x * paso, 0.001)
		aj["z"] = snappedf(float(aj.get("z", 0.0)) + d.z * paso, 0.001)
		_cambio()
	elif k.keycode == KEY_Q:
		_sumar(_elegido, "giro", grados)
	elif k.keycode == KEY_E:
		_sumar(_elegido, "giro", -grados)
	elif k.keycode == KEY_Z:
		_sumar(_elegido, "desfase", -(0.25 if mucho else 0.05))
	elif k.keycode == KEY_X:
		_sumar(_elegido, "desfase", 0.25 if mucho else 0.05)
	elif k.keycode == KEY_H and _elegido > 0:
		_cambiar(_elegido, "oculto", not _ajuste(_elegido).get("oculto", false))
	elif k.keycode == KEY_TAB:
		_elegir_actor((_elegido + (-1 if mucho else 1) + (_escena["elenco"] as Array).size()) % (_escena["elenco"] as Array).size())
	elif k.keycode == KEY_SPACE:
		_alternar_play()
	elif k.keycode == KEY_HOME:
		_ir_a(0.0)
	elif k.keycode == KEY_COMMA:
		_reproduciendo = false
		_ir_a(maxf(_t - PASO_CUADRO, 0.0))
	elif k.keycode == KEY_PERIOD:
		_reproduciendo = false
		_ir_a(minf(_t + PASO_CUADRO, float(_escena["largo"])))
	else:
		return
	get_viewport().set_input_as_handled()

func _ir_a(t: float) -> void:
	_t = t
	_mostrar_tiempo()
	_refrescar_ui()

func _alternar_play() -> void:
	_reproduciendo = not _reproduciendo
	_refrescar_ui()

func _actor_bajo(pantalla: Vector2) -> int:
	var mejor := -1
	var menor := 70.0
	for i in (_escena["elenco"] as Array).size():
		for alto in [0.0, 0.5, 1.0]:
			var p := _cadera(i) + Vector3(0, alto - 0.4, 0)
			if _camara.is_position_behind(p):
				continue
			var d := _camara.unproject_position(p).distance_to(pantalla)
			if d < menor:
				menor = d
				mejor = i
	return mejor

func _en_el_piso(pantalla: Vector2) -> Vector3:
	var desde := _camara.project_ray_origin(pantalla)
	var dir := _camara.project_ray_normal(pantalla)
	if absf(dir.y) < 1e-4:
		return desde
	return desde + dir * (-desde.y / dir.y)

func _elegir_actor(i: int) -> void:
	_elegido = i
	_colocar_todos()
	_refrescar_ui()

func _mover_camara() -> void:
	var dir := Vector3(sin(_yaw) * cos(_pitch), -sin(_pitch), cos(_yaw) * cos(_pitch))
	_camara.global_position = _foco + dir * _distancia
	_camara.look_at(_foco)
	# El panel tapa la izquierda: el foco se ve en el centro de lo que queda libre.
	var tam := get_viewport().get_visible_rect().size
	var libre := 380.0 / maxf(tam.x, 1.0)
	_camara.h_offset = -libre * _distancia * tan(deg_to_rad(_camara.fov * 0.5)) * tam.x / maxf(tam.y, 1.0)

# ---------------------------------------------------------------------------
# Mundo y panel
# ---------------------------------------------------------------------------

func _armar_mundo() -> void:
	var entorno := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.66, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	entorno.environment = env
	add_child(entorno)
	var sol := DirectionalLight3D.new()
	sol.rotation_degrees = Vector3(-55, 35, 0)
	sol.shadow_enabled = true
	sol.light_energy = 1.2
	add_child(sol)
	var piso := MeshInstance3D.new()
	var plano := PlaneMesh.new()
	plano.size = Vector2(120, 120)
	piso.mesh = plano
	var pasto := StandardMaterial3D.new()
	pasto.albedo_color = Color(0.22, 0.45, 0.2)
	piso.material_override = pasto
	add_child(piso)
	# Cuadricula de un metro, mas marcada cada cinco.
	var grilla := MeshInstance3D.new()
	var lineas := ImmediateMesh.new()
	lineas.surface_begin(Mesh.PRIMITIVE_LINES)
	for k in range(-30, 31):
		var fuerte := k % 5 == 0
		var c := Color(1, 1, 1, 0.35 if fuerte else 0.12)
		lineas.surface_set_color(c)
		lineas.surface_add_vertex(Vector3(k, 0.01, -30))
		lineas.surface_add_vertex(Vector3(k, 0.01, 30))
		lineas.surface_add_vertex(Vector3(-30, 0.01, k))
		lineas.surface_add_vertex(Vector3(30, 0.01, k))
	lineas.surface_end()
	grilla.mesh = lineas
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grilla.material_override = m
	add_child(grilla)
	var arco := Label3D.new()
	arco.text = "hacia el arco (-z)"
	arco.font_size = 64
	arco.pixel_size = 0.01
	arco.rotation_degrees = Vector3(-90, 0, 0)
	arco.position = Vector3(0, 0.03, -8)
	arco.modulate = Color(1, 1, 1, 0.6)
	add_child(arco)
	_camara = Camera3D.new()
	_camara.fov = 45
	add_child(_camara)
	_mover_camara()

func _armar_ui() -> void:
	var capa := CanvasLayer.new()
	add_child(capa)
	var panel := PanelContainer.new()
	panel.position = Vector2(10, 10)
	panel.custom_minimum_size = Vector2(360, 0)
	capa.add_child(panel)
	var caja := VBoxContainer.new()
	caja.add_theme_constant_override("separation", 6)
	panel.add_child(caja)

	var titulo := Label.new()
	titulo.text = "Editor de festejos"
	titulo.add_theme_font_size_override("font_size", 20)
	caja.add_child(titulo)

	_ui_escena = OptionButton.new()
	_ui_escena.fit_to_longest_item = false
	for i in _menu.size():
		_ui_escena.add_item(_menu[i]["nombre"], i)
	_ui_escena.item_selected.connect(func(i: int): _elegir_escena(i))
	caja.add_child(_ui_escena)

	var fila := HBoxContainer.new()
	_ui_usar = CheckBox.new()
	_ui_usar.text = "Usar en el juego"
	_ui_usar.toggled.connect(func(si: bool):
		if _actualizando:
			return
		_recordar()
		var corte: String = _escena["corte"]
		if _escena.get("descartado", false):
			_ajuste_escena(corte, true)["activado"] = si
		else:
			_ajuste_escena(corte, true)["desactivado"] = not si
		_cambio())
	fila.add_child(_ui_usar)
	var lbl := Label.new()
	lbl.text = "  Adelantar escena"
	fila.add_child(lbl)
	_ui_desde = _spin(-5.0, 10.0, 0.05, "s")
	_ui_desde.value_changed.connect(func(v: float):
		if _actualizando:
			return
		_recordar()
		_ajuste_escena(_escena["corte"], true)["desde"] = v
		_cambio())
	fila.add_child(_ui_desde)
	caja.add_child(fila)

	_ui_lista = ItemList.new()
	_ui_lista.custom_minimum_size = Vector2(0, 150)
	_ui_lista.item_selected.connect(func(i: int): _elegir_actor(i))
	caja.add_child(_ui_lista)

	var grilla := GridContainer.new()
	grilla.columns = 4
	_ui_x = _campo(grilla, "X (m)", -10.0, 10.0, 0.01, "x")
	_ui_z = _campo(grilla, "Z (m)", -10.0, 10.0, 0.01, "z")
	_ui_giro = _campo(grilla, "Giro (°)", -180.0, 180.0, 1.0, "giro")
	_ui_desfase = _campo(grilla, "Desfase (s)", -10.0, 10.0, 0.05, "desfase")
	caja.add_child(grilla)
	_ui_oculto = CheckBox.new()
	_ui_oculto.text = "Oculto (no sale en el juego)"
	_ui_oculto.toggled.connect(func(si: bool):
		if not _actualizando:
			_cambiar(_elegido, "oculto", si))
	caja.add_child(_ui_oculto)

	var botones := HBoxContainer.new()
	var b1 := Button.new()
	b1.text = "Restablecer jugador"
	b1.pressed.connect(func():
		if _elegido < 0:
			return
		_recordar()
		var e: Dictionary = _escena["elenco"][_elegido]
		var de_escena := _ajuste_escena(e["corte"])
		if de_escena.has("actores"):
			(de_escena["actores"] as Dictionary).erase(e["clave"])
		_cambio())
	botones.add_child(b1)
	var b2 := Button.new()
	b2.text = "Restablecer escena"
	b2.pressed.connect(func():
		_recordar()
		for e: Dictionary in _escena["elenco"]:
			_ajustes.erase(e["corte"])
		_cambio())
	botones.add_child(b2)
	caja.add_child(botones)

	_ui_info = Label.new()
	_ui_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ui_info.custom_minimum_size = Vector2(340, 0)
	caja.add_child(_ui_info)

	var tiempo := HBoxContainer.new()
	_ui_play = Button.new()
	_ui_play.custom_minimum_size = Vector2(70, 0)
	_ui_play.pressed.connect(_alternar_play)
	tiempo.add_child(_ui_play)
	var vel := OptionButton.new()
	for v in [0.25, 0.5, 1.0]:
		vel.add_item("x%s" % v)
	vel.select(2)
	vel.item_selected.connect(func(i: int): _velocidad = [0.25, 0.5, 1.0][i])
	tiempo.add_child(vel)
	_ui_t = Label.new()
	tiempo.add_child(_ui_t)
	caja.add_child(tiempo)
	_ui_tiempo = HSlider.new()
	_ui_tiempo.step = 0.01
	_ui_tiempo.value_changed.connect(func(v: float):
		if _actualizando:
			return
		_reproduciendo = false
		_ir_a(v))
	caja.add_child(_ui_tiempo)

	_ui_caminos = CheckBox.new()
	_ui_caminos.text = "Ver recorridos"
	_ui_caminos.button_pressed = true
	_ui_caminos.toggled.connect(func(_si): _dibujar_caminos())
	caja.add_child(_ui_caminos)

	var guardar := HBoxContainer.new()
	var bg := Button.new()
	bg.text = "Guardar (Ctrl+S)"
	bg.pressed.connect(_guardar)
	guardar.add_child(bg)
	_ui_estado = Label.new()
	guardar.add_child(_ui_estado)
	caja.add_child(guardar)

	# La ayuda, aparte, arriba a la derecha.
	var panel_ayuda := PanelContainer.new()
	panel_ayuda.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel_ayuda.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel_ayuda.position = Vector2(-10, 10)
	capa.add_child(panel_ayuda)
	var ayuda := Label.new()
	ayuda.add_theme_font_size_override("font_size", 13)
	ayuda.modulate = Color(1, 1, 1, 0.8)
	ayuda.text = "Clic: elegir · arrastrar: mover por el piso\nBoton der.: girar camara · medio: correr · ruedita: acercar\nFlechas: mover 5 cm (Shift 25, Alt 1)\nQ / E: girar 5° (Shift 15, Alt 1)\nZ / X: atrasar / adelantar su clip 0,05 s (Shift 0,25)\nTab: siguiente · H: ocultar · Espacio: play\n,  .: un cuadro · Inicio: al principio\nCtrl+Z: deshacer · Ctrl+S: guardar"
	panel_ayuda.add_child(ayuda)

func _spin(desde: float, hasta: float, paso: float, sufijo: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = desde
	s.max_value = hasta
	s.step = paso
	s.suffix = sufijo
	s.custom_minimum_size = Vector2(95, 0)
	return s

func _campo(grilla: GridContainer, nombre: String, desde: float, hasta: float, paso: float, campo: String) -> SpinBox:
	var l := Label.new()
	l.text = nombre
	grilla.add_child(l)
	var s := _spin(desde, hasta, paso, "")
	s.value_changed.connect(func(v: float):
		if not _actualizando:
			_cambiar(_elegido, campo, v))
	grilla.add_child(s)
	return s

func _refrescar_ui() -> void:
	if _ui_lista == null:
		return
	_actualizando = true
	var tipo: String = _escena["tipo"]
	_ui_usar.disabled = tipo == "escena"
	if _escena.get("descartado", false):
		_ui_usar.button_pressed = _ajuste_escena(_escena["corte"]).get("activado", false)
	else:
		_ui_usar.button_pressed = not _ajuste_escena(_escena["corte"]).get("desactivado", false)
	_ui_desde.editable = tipo != "solo"
	_ui_desde.value = float(_ajuste_escena(_escena["corte"]).get("desde", 0.0))
	_ui_lista.clear()
	for i in (_escena["elenco"] as Array).size():
		var e: Dictionary = _escena["elenco"][i]
		var aj := _ajuste(i)
		var marca := "" if FestejosAjustes.es_neutro(aj) else "  *"
		_ui_lista.add_item("%d  %s%s%s" % [i + 1, e["actor"]["clip"], marca, "  (oculto)" if aj.get("oculto", false) else ""])
		_ui_lista.set_item_custom_fg_color(i, _actores[i]["color"])
	if _elegido >= 0:
		_ui_lista.select(_elegido)
		var aj := _ajuste(_elegido)
		_ui_x.value = float(aj.get("x", 0.0))
		_ui_z.value = float(aj.get("z", 0.0))
		_ui_giro.value = float(aj.get("giro", 0.0))
		_ui_desfase.value = float(aj.get("desfase", 0.0))
		_ui_oculto.button_pressed = aj.get("oculto", false)
		# El autor de un festejo (el primero) es el que pateo: no se puede sacar.
		_ui_oculto.disabled = _elegido == 0
	for s: SpinBox in [_ui_x, _ui_z, _ui_giro, _ui_desfase]:
		s.editable = tipo != "solo"
	_ui_tiempo.max_value = float(_escena["largo"])
	_ui_tiempo.value = _t
	_ui_play.text = "Pausa" if _reproduciendo else "Play"
	_ui_estado.text = "Cambios sin guardar" if _sin_guardar else "Guardado"
	_actualizando = false
	_refrescar_info()
