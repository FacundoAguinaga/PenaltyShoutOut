@tool
extends Node3D

## Cesped de la cancha: piso con POM + hojas cerca de la camara + lineas.
##
## Corre tambien en el editor (@tool): al abrir stadium.tscn o game.tscn se ve
## el pasto en el viewport, con las hojas siguiendo a la camara del editor, y
## todos los parametros se tunean desde el inspector de este nodo.
##
## El estadio viene de stadium_optimizado.scn, un archivo gigante que se
## regenera con tools/optimizar_estadio.gd y que junta los triangulos por
## material. Editar ese .scn a mano no sirve porque se pisa al regenerarlo.
## Por eso aca, al arrancar:
##   1. Se buscan las superficies del cesped ("auto_1") y se les pone el
##      material del piso (paralaje).
##   2. A las lineas ("auto_30") se les pone su material (levantadas 4 mm,
##      sin z-fighting) y con sus triangulos se hornea una mascara para que
##      las hojas que caen sobre la cal salgan blancas.
##   3. Se crea un parche de capas de hojas (grass_shells) que sigue a la
##      camara, con LOD por distancia.
##
## Los materiales se DUPLICAN: los .tres de assets/materials no se tocan y lo
## que manda son las variables exportadas de este nodo. En el editor, antes de
## guardar la escena se sacan los overrides para no meterlos en el .tscn.
##
## Ver docs/pasto_volumetrico.md.

const GRASS_MATERIAL: ShaderMaterial = preload("res://assets/materials/grass_volumetric_material.tres")
const SHELL_MATERIAL: ShaderMaterial = preload("res://assets/materials/grass_shells_material.tres")
const LINE_SHADER: Shader = preload("res://assets/materials/grass_lineas.gdshader")
const FIELD_SHADER: Shader = preload("res://assets/materials/grass_horneado.gdshader")

## Variables exportadas que se pasan tal cual a los shaders (mismo nombre que
## el uniform). Cada material recibe solo las que declara.
const SHADER_PARAMS: Array[String] = [
	"grass_base", "grass_dark", "grass_tip", "wear_color", "line_color",
	"macro_strength", "detail_strength", "wear_strength",
	"stripe_width", "stripe_view", "stripe_fixed", "stripe_softness",
	"goal_line_z", "pitch_length",
	"wind_strength", "wind_speed", "grass_height",
	"blade_density", "clump_scale", "height_strength", "normal_strength",
	"ao_strength", "lean_normal", "fade_start", "fade_end", "debug_mode",
	"shell_density", "blade_width", "lean_amount", "blade_tint",
	"shell_radius", "shell_fade_dist", "layer_px", "min_layers",
]

@export var enabled := true:
	set(v):
		enabled = v
		_reiniciar()

@export_group("Color del pasto")
@export var grass_base := Color(0.25, 0.42, 0.14):
	set(v): grass_base = v; _cambio()
## Color de la raiz de las hojas (zona sombreada).
@export var grass_dark := Color(0.11, 0.25, 0.06):
	set(v): grass_dark = v; _cambio()
## Color de la punta de las hojas.
@export var grass_tip := Color(0.41, 0.55, 0.22):
	set(v): grass_tip = v; _cambio()
## Manchas grandes de color (riego, resiembra).
@export_range(0.0, 0.5, 0.01) var macro_strength := 0.10:
	set(v): macro_strength = v; _cambio()
## Grano fino del piso.
@export_range(0.0, 0.5, 0.01) var detail_strength := 0.12:
	set(v): detail_strength = v; _cambio()
@export var line_color := Color(0.86, 0.88, 0.86):
	set(v): line_color = v; _cambio()

@export_group("Desgaste")
## Pasto gastado en punto de penal y boca del arco (0 = nada).
@export_range(0.0, 1.0, 0.01) var wear_strength := 0.55:
	set(v): wear_strength = v; _cambio()
@export var wear_color := Color(0.47, 0.44, 0.27):
	set(v): wear_color = v; _cambio()

@export_group("Franjas de corte")
## Ancho de cada franja, en metros.
@export_range(1.0, 15.0, 0.1) var stripe_width := 5.5:
	set(v): stripe_width = v; _cambio()
## Contraste que depende de la camara (se invierte al girar 180 grados).
@export_range(0.0, 0.6, 0.01) var stripe_view := 0.24:
	set(v): stripe_view = v; _cambio()
## Contraste fijo (se ve tambien desde arriba).
@export_range(0.0, 0.3, 0.01) var stripe_fixed := 0.07:
	set(v): stripe_fixed = v; _cambio()
## Ancho del borde suave entre franjas, en metros.
@export_range(0.0, 1.0, 0.01) var stripe_softness := 0.18:
	set(v): stripe_softness = v; _cambio()
## Z de la linea de meta: desde ahi arrancan las franjas y el desgaste.
@export var goal_line_z := -11.0:
	set(v): goal_line_z = v; _cambio()
## Distancia entre lineas de meta.
@export var pitch_length := 105.0:
	set(v): pitch_length = v; _cambio()

@export_group("Viento")
@export_range(0.0, 3.0, 0.01) var wind_strength := 0.5:
	set(v): wind_strength = v; _cambio()
@export_range(0.0, 5.0, 0.01) var wind_speed := 1.4:
	set(v): wind_speed = v; _cambio()

@export_group("Piso (paralaje)")
## Alto del pasto en metros (piso y hojas).
@export_range(0.005, 0.15, 0.001, "suffix:m") var grass_height := 0.05:
	set(v): grass_height = v; _cambio()
## Matas por metro en el relieve del piso.
@export_range(10.0, 150.0, 1.0) var blade_density := 50.0:
	set(v): blade_density = v; _cambio()
@export_range(0.5, 20.0, 0.1) var clump_scale := 5.0:
	set(v): clump_scale = v; _cambio()
@export_range(0.0, 1.0, 0.01) var height_strength := 0.8:
	set(v): height_strength = v; _cambio()
@export_range(0.0, 3.0, 0.01) var normal_strength := 1.0:
	set(v): normal_strength = v; _cambio()
@export_range(0.0, 1.0, 0.01) var ao_strength := 0.3:
	set(v): ao_strength = v; _cambio()
## Cuanto inclina la franja a la normal (brillo distinto con los focos).
@export_range(0.0, 1.0, 0.01) var lean_normal := 0.22:
	set(v): lean_normal = v; _cambio()
## Distancia donde el relieve del piso empieza a apagarse.
@export_range(0.0, 200.0, 0.5, "suffix:m") var fade_start := 25.0:
	set(v): fade_start = v; _cambio()
## Distancia donde ya no hay relieve.
@export_range(0.0, 300.0, 0.5, "suffix:m") var fade_end := 60.0:
	set(v): fade_end = v; _cambio()

@export_group("Hojas")
@export var shells_enabled := true:
	set(v): shells_enabled = v; _cambio()
## Hojas por metro. Mas alto = mas finas, pero se apagan antes al alejarse.
@export_range(20.0, 250.0, 1.0) var shell_density := 70.0:
	set(v): shell_density = v; _cambio()
## Grosor de la hoja en la raiz (fraccion de celda).
@export_range(0.05, 0.5, 0.01) var blade_width := 0.30:
	set(v): blade_width = v; _cambio()
## Cuanto se vuelca la hoja hacia el peinado de la franja.
@export_range(0.0, 1.5, 0.01) var lean_amount := 0.55:
	set(v): lean_amount = v; _cambio()
## Variacion de tono entre hojas (lo que las hace legibles de lejos).
@export_range(0.0, 0.6, 0.01) var blade_tint := 0.22:
	set(v): blade_tint = v; _cambio()

@export_group("Hojas: capas y LOD")
## Capas maximas (las que se usan de cerca). Mas = hojas mas suaves de
## costado; el costo sube casi lineal.
@export_range(2, 48) var shell_layers := 16:
	set(v): shell_layers = v; _cambio(true)
## Radio del parche de hojas alrededor de la camara.
@export_range(2.0, 60.0, 0.5, "suffix:m") var shell_radius := 20.0:
	set(v): shell_radius = v; _cambio(true)
## Distancia a la camara donde las hojas desaparecen (se funden con el piso
## desde el 60% de esta distancia).
@export_range(1.0, 120.0, 0.5, "suffix:m") var shell_fade_dist := 35.0:
	set(v): shell_fade_dist = v; _cambio()
## Pixeles de alto de hoja por capa. Mas alto = menos capas lejos, mas barato.
@export_range(0.5, 8.0, 0.1, "suffix:px") var layer_px := 1.6:
	set(v): layer_px = v; _cambio()
## Capas minimas por baldosa, aunque este lejos.
@export_range(1, 16) var min_layers := 3:
	set(v): min_layers = v; _cambio()
## Tamano de las baldosas del LOD. Mas chico = LOD mas fino, mas vertices.
@export_range(0.5, 10.0, 0.1, "suffix:m") var shell_tile_size := 2.5:
	set(v): shell_tile_size = v; _cambio(true)

@export_group("Debug")
## Piso: 1 altura, 2 normales, 3 mascara de detalle, 4 desgaste.
@export_enum("Normal", "Altura", "Normales", "Detalle", "Desgaste") var debug_mode := 0:
	set(v): debug_mode = v; _cambio()
## Pinta las hojas de rojo para ver hasta donde llegan.
@export var debug_shells := false:
	set(v): debug_shells = v; _cambio()

@export_group("Avanzado")
## Materiales del modelo que son cancha (comparacion exacta, sin mayusculas).
## "Trawa_03_1" es el cesped perimetral y no se toca.
@export var target_materials: Array[String] = ["auto_1"]:
	set(v): target_materials = v; _reiniciar()
## Materiales del modelo que son lineas de cal.
@export var line_materials: Array[String] = ["auto_30"]:
	set(v): line_materials = v; _reiniciar()
## Resolucion de la mascara de lineas (metros por pixel).
@export_range(0.01, 0.2, 0.005, "suffix:m") var line_mask_resolution := 0.04:
	set(v): line_mask_resolution = v; _reiniciar()
## Resolucion de los campos de color horneados para las hojas.
@export_range(0.02, 0.3, 0.005, "suffix:m") var field_resolution := 0.06:
	set(v): field_resolution = v; _reiniciar()

var _piso_mat: ShaderMaterial
var _hojas_mat: ShaderMaterial
var _lineas_mat: ShaderMaterial
var _campos_mat: ShaderMaterial
var _campos_vp: SubViewport
var _shells: MeshInstance3D
var _grass_surfaces: Array = []   # [MeshInstance3D, surface, override original]
var _line_surfaces: Array = []
var _pitch_rect := Rect2()
var _base_y := 0.0
var _activo := false
var _params_pendientes := false
var _malla_pendiente := false

func _ready() -> void:
	_reiniciar()

func _enter_tree() -> void:
	# En el editor, al cambiar de pestana la escena sale y vuelve a entrar al
	# arbol sin volver a llamar a _ready.
	if is_node_ready() and not _activo:
		_reiniciar.call_deferred()

func _exit_tree() -> void:
	_desactivar()

func _notification(what: int) -> void:
	# En el editor los overrides se sacan antes de guardar y se vuelven a poner
	# despues: si no, la escena guardaria los materiales duplicados (con las
	# texturas horneadas adentro).
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_quitar_overrides()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_poner_overrides()

func _cambio(malla := false) -> void:
	_params_pendientes = true
	if malla:
		_malla_pendiente = true

func _reiniciar() -> void:
	if not is_inside_tree():
		return
	_desactivar()
	if enabled:
		_activar()

func _activar() -> void:
	_buscar_superficies()
	if _grass_surfaces.is_empty():
		return
	_piso_mat = GRASS_MATERIAL.duplicate()
	_lineas_mat = ShaderMaterial.new()
	_lineas_mat.shader = LINE_SHADER
	_hojas_mat = SHELL_MATERIAL.duplicate()

	_pitch_rect = _surfaces_rect(_grass_surfaces)
	_base_y = _surfaces_top(_grass_surfaces)
	_hojas_mat.set_shader_parameter("pitch_rect", Vector4(
		_pitch_rect.position.x, _pitch_rect.position.y, _pitch_rect.end.x, _pitch_rect.end.y))

	if not _line_surfaces.is_empty():
		var t0 := Time.get_ticks_msec()
		var line_rect := _surfaces_rect(_line_surfaces).grow(0.5)
		var mask := _bake_line_mask(_line_surfaces, line_rect)
		_hojas_mat.set_shader_parameter("line_mask", mask)
		_hojas_mat.set_shader_parameter("line_rect", Vector4(
			line_rect.position.x, line_rect.position.y, line_rect.size.x, line_rect.size.y))
		_hojas_mat.set_shader_parameter("use_line_mask", 1.0)
		print("[Cesped] Mascara de lineas ", mask.get_size(), " en ", Time.get_ticks_msec() - t0, " ms")

	# Campos de color horneados en la GPU: las hojas leen una textura en vez
	# de calcular ~10 ruidos por capa.
	_crear_campos(_pitch_rect)
	_hojas_mat.set_shader_parameter("grass_field", _campos_vp.get_texture())
	_hojas_mat.set_shader_parameter("field_rect", Vector4(
		_pitch_rect.position.x, _pitch_rect.position.y, _pitch_rect.size.x, _pitch_rect.size.y))
	_hojas_mat.set_shader_parameter("use_field", 1.0)

	_shells = MeshInstance3D.new()
	_shells.name = "CespedHojas"
	_shells.material_override = _hojas_mat
	_shells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shells.visible = false
	# Sin owner: el editor no lo guarda en la escena.
	add_child(_shells, false, Node.INTERNAL_MODE_BACK)
	_shells.global_position = Vector3(0.0, _base_y, 0.0)

	_activo = true
	_construir_malla()
	_aplicar_parametros()
	_poner_overrides()
	print("[Cesped] Superficies de pasto: ", _grass_surfaces.size(), ", lineas: ", _line_surfaces.size())

func _desactivar() -> void:
	_quitar_overrides()
	if _shells:
		_shells.queue_free()
		_shells = null
	if _campos_vp:
		_campos_vp.queue_free()
		_campos_vp = null
	_grass_surfaces.clear()
	_line_surfaces.clear()
	_activo = false

func _buscar_superficies() -> void:
	_grass_surfaces.clear()
	_line_surfaces.clear()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or mesh_instance == _shells:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			# El override que ya tenia la superficie se guarda para devolverlo
			# al sacar el pasto. Si es uno nuestro (quedo de antes), no cuenta.
			var original := mesh_instance.get_surface_override_material(surface)
			if _es_nuestro(original):
				original = null
			var source := original if original != null else mesh_instance.mesh.surface_get_material(surface)
			if _matches(source, target_materials):
				_grass_surfaces.append([mesh_instance, surface, original])
			elif _matches(source, line_materials):
				_line_surfaces.append([mesh_instance, surface, original])

func _poner_overrides() -> void:
	if not _activo:
		return
	for entry in _grass_surfaces:
		if is_instance_valid(entry[0]):
			(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], _piso_mat)
	for entry in _line_surfaces:
		if is_instance_valid(entry[0]):
			(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], _lineas_mat)

func _quitar_overrides() -> void:
	for entry in _grass_surfaces + _line_surfaces:
		if is_instance_valid(entry[0]):
			(entry[0] as MeshInstance3D).set_surface_override_material(entry[1], entry[2])

func _es_nuestro(material: Material) -> bool:
	if not material is ShaderMaterial:
		return false
	var shader := (material as ShaderMaterial).shader
	return shader in [GRASS_MATERIAL.shader, LINE_SHADER]

## Pasa las variables exportadas a los cuatro materiales.
func _aplicar_parametros() -> void:
	if not _activo:
		return
	for mat in [_piso_mat, _hojas_mat, _lineas_mat, _campos_mat]:
		if mat == null:
			continue
		var available := {}
		for u in mat.shader.get_shader_uniform_list():
			available[u["name"]] = true
		for param in SHADER_PARAMS:
			if available.has(param):
				mat.set_shader_parameter(param, get(param))
	_hojas_mat.set_shader_parameter("debug_shells", 1 if debug_shells else 0)
	_hojas_mat.set_shader_parameter("tile_half_diag", shell_tile_size * 0.7072)
	# Los campos horneados dependen del desgaste y de las lineas de meta:
	# se vuelven a hornear (es un solo dibujo).
	if _campos_vp:
		_campos_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_params_pendientes = false

func _process(_delta: float) -> void:
	if not _activo:
		return
	if _malla_pendiente:
		_construir_malla()
	if _params_pendientes:
		_aplicar_parametros()
	if _shells == null:
		return
	var camera := _camara()
	if camera == null or not shells_enabled:
		_shells.visible = false
		return
	var cam_pos := camera.global_position
	var viewport_size := camera.get_viewport().get_visible_rect().size

	# Punto del piso mas cercano que se ve: el rayo del borde inferior de la
	# pantalla. Si ahi una hoja mide menos de ~1 pixel, no hay nada que ver.
	var bottom_ray := camera.project_ray_normal(Vector2(viewport_size.x * 0.5, viewport_size.y))
	var near_dist := 1.0e9
	if bottom_ray.y < -0.001:
		near_dist = (cam_pos.y - _base_y) / -bottom_ray.y
	var pixel_angle: float = deg_to_rad(camera.fov) / maxf(viewport_size.y, 1.0)
	var near_footprint: float = near_dist * pixel_angle
	var cell := 1.0 / maxf(shell_density, 1.0)
	var show: bool = near_footprint < cell * 1.1 and near_dist < shell_fade_dist and cam_pos.y > _base_y - 0.5
	_shells.visible = show
	if not show:
		return

	# El parche se centra adelante de la camara, sobre el piso.
	var forward := -camera.global_transform.basis.z
	var flat := Vector2(forward.x, forward.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector2.ZERO
	var center := Vector2(cam_pos.x, cam_pos.z) + flat * shell_radius * 0.55
	center.x = clampf(center.x, _pitch_rect.position.x, _pitch_rect.end.x)
	center.y = clampf(center.y, _pitch_rect.position.y, _pitch_rect.end.y)
	# Saltos de 0.5 m: el patron esta en coordenadas de mundo, asi que mover
	# el parche no cambia nada salvo el borde.
	center = center.snapped(Vector2(0.5, 0.5))
	_shells.global_position = Vector3(center.x, _base_y, center.y)

## En el juego, la camara activa. En el editor, la del viewport 3D (el
## singleton se pide por nombre para que el script compile en el juego
## exportado, donde EditorInterface no existe).
func _camara() -> Camera3D:
	if Engine.is_editor_hint():
		var ei = Engine.get_singleton("EditorInterface")
		if ei == null:
			return null
		var vp = ei.get_editor_viewport_3d(0)
		return vp.get_camera_3d() if vp else null
	return get_viewport().get_camera_3d()

## Dibuja grass_fields() sobre la cancha en un SubViewport que se renderiza
## una vez (y otra cada vez que cambian los parametros).
func _crear_campos(rect: Rect2) -> void:
	_campos_vp = SubViewport.new()
	_campos_vp.name = "CespedCampos"
	_campos_vp.size = Vector2i(ceili(rect.size.x / field_resolution), ceili(rect.size.y / field_resolution))
	_campos_vp.disable_3d = true
	_campos_vp.transparent_bg = true   # el canal alfa guarda el desgaste
	_campos_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_campos_mat = ShaderMaterial.new()
	_campos_mat.shader = FIELD_SHADER
	_campos_mat.set_shader_parameter("field_rect", Vector4(
		rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	var quad := ColorRect.new()
	quad.size = Vector2(_campos_vp.size)
	quad.material = _campos_mat
	_campos_vp.add_child(quad)
	add_child(_campos_vp, false, Node.INTERNAL_MODE_BACK)

func _construir_malla() -> void:
	_malla_pendiente = false
	if _shells:
		_shells.mesh = _build_shell_mesh(shell_layers, shell_radius)

## N capas de (2r x 2r), cada una partida en baldosas de ~shell_tile_size.
## Por vertice:
##   VERTEX.y = fraccion de altura de la capa (el shader la pasa a metros),
##   UV       = centro de la baldosa (local), para el LOD por distancia,
##   UV2      = (indice de capa, total de capas).
## El vertex shader colapsa las capas que no hacen falta a la distancia de
## cada baldosa: lejos quedan pocas capas, cerca todas.
func _build_shell_mesh(layers: int, radius: float) -> ArrayMesh:
	var tiles := maxi(1, ceili(radius * 2.0 / shell_tile_size))
	var step := radius * 2.0 / float(tiles)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()
	# De arriba hacia abajo: las puntas se dibujan primero y el early-z
	# descarta lo que tapan en las capas de abajo.
	for i in range(layers - 1, -1, -1):
		var h := (float(i) + 0.5) / float(layers)
		for tz in tiles:
			for tx in tiles:
				var x0 := -radius + step * tx
				var z0 := -radius + step * tz
				var c := Vector2(x0 + step * 0.5, z0 + step * 0.5)
				var base := verts.size()
				verts.append(Vector3(x0, h, z0))
				verts.append(Vector3(x0 + step, h, z0))
				verts.append(Vector3(x0 + step, h, z0 + step))
				verts.append(Vector3(x0, h, z0 + step))
				for k in 4:
					normals.append(Vector3.UP)
					uvs.append(c)
					uv2s.append(Vector2(i, layers))
				indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# El shader sube los vertices; el AABB tiene que cubrir hasta y=1 igual.
	mesh.custom_aabb = AABB(Vector3(-radius, 0.0, -radius), Vector3(radius * 2.0, 1.0, radius * 2.0))
	return mesh

## Rasteriza los triangulos de las lineas (vistos desde arriba) en una
## textura de un canal: 1 = cal, 0 = pasto.
func _bake_line_mask(surfaces: Array, rect: Rect2) -> ImageTexture:
	var res := line_mask_resolution
	var w := int(ceil(rect.size.x / res))
	var h := int(ceil(rect.size.y / res))
	var img := Image.create_empty(w, h, false, Image.FORMAT_L8)
	for entry in surfaces:
		var mi: MeshInstance3D = entry[0]
		var arrays := mi.mesh.surface_get_arrays(entry[1])
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var xf := mi.global_transform
		var pts := PackedVector2Array()
		pts.resize(verts.size())
		for i in verts.size():
			var wp := xf * verts[i]
			pts[i] = (Vector2(wp.x, wp.z) - rect.position) / res
		var count := idx.size() if not idx.is_empty() else verts.size()
		for t in range(0, count - 2, 3):
			var a := pts[idx[t] if not idx.is_empty() else t]
			var b := pts[idx[t + 1] if not idx.is_empty() else t + 1]
			var c := pts[idx[t + 2] if not idx.is_empty() else t + 2]
			_fill_triangle(img, a, b, c)
	return ImageTexture.create_from_image(img)

func _fill_triangle(img: Image, a: Vector2, b: Vector2, c: Vector2) -> void:
	var area := (b - a).cross(c - a)
	if absf(area) < 1.0e-6:
		return
	var x0 := maxi(int(floor(minf(a.x, minf(b.x, c.x)))), 0)
	var y0 := maxi(int(floor(minf(a.y, minf(b.y, c.y)))), 0)
	var x1 := mini(int(ceil(maxf(a.x, maxf(b.x, c.x)))), img.get_width() - 1)
	var y1 := mini(int(ceil(maxf(a.y, maxf(b.y, c.y)))), img.get_height() - 1)
	var white := Color(1, 1, 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0 := (b - a).cross(p - a) / area
			var w1 := (c - b).cross(p - b) / area
			var w2 := (a - c).cross(p - c) / area
			if w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0:
				img.set_pixel(x, y, white)

func _surfaces_rect(surfaces: Array) -> Rect2:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for entry in surfaces:
		var mi: MeshInstance3D = entry[0]
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(entry[1])[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		for v in verts:
			var wp := xf * v
			mn = mn.min(Vector2(wp.x, wp.z))
			mx = mx.max(Vector2(wp.x, wp.z))
	return Rect2(mn, mx - mn)

func _surfaces_top(surfaces: Array) -> float:
	var top := -INF
	for entry in surfaces:
		var mi: MeshInstance3D = entry[0]
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(entry[1])[Mesh.ARRAY_VERTEX]
		var xf := mi.global_transform
		for v in verts:
			top = maxf(top, (xf * v).y)
	return top

func _matches(material: Material, names: Array[String]) -> bool:
	if material == null or names.is_empty():
		return false
	var material_name := str(material.resource_name).to_lower()
	for name in names:
		if not name.is_empty() and material_name == name.to_lower():
			return true
	if material is BaseMaterial3D:
		var albedo: Texture2D = (material as BaseMaterial3D).albedo_texture
		if albedo != null:
			var texture_name: String = albedo.resource_path.get_file().to_lower()
			for name in names:
				if name.is_empty():
					continue
				var prefix := "stadium_" + name.to_lower() + "_"
				if texture_name.begins_with(prefix) and texture_name.contains("basecolor"):
					return true
	return false
