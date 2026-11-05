@tool
class_name CrowdManager
extends MultiMeshInstance3D

## CrowdManager - Sistema de Hinchada 3D Masiva en GPU
## Diseñado con @tool para que los 4.769 espectadores se visualicen
## y se puedan posicionar directamente en el editor 3D de Godot y en juego.

@export_group("Assets")
@export var spectator_mesh: Mesh
@export var vat_material: Material
@export_file("*.json") var positions_json_path: String = "res://assets/models/people/crowd_positions.json"

## LOD liviano para tribunas lejanas (~4.5x menos tris). Si falta el
## archivo se usa la malla HIGH en todos lados (más lindo, más caro).
const LOW_GLB_PATH := "res://assets/models/people/crowd_spectator_mesh_low.glb"
const LOW_VAT_PATH := "res://assets/models/people/crowd_vat_low.exr"
const LOW_META_PATH := "res://assets/models/people/crowd_anim_meta_low.json"
const HIGH_META_PATH := "res://assets/models/people/crowd_anim_meta.json"
var spectator_mesh_low: Mesh
var vat_material_low: ShaderMaterial

@export_group("Team Colors")
@export var home_team_color: Color = Color(0.85, 0.15, 0.15, 1.0):
	set(val):
		home_team_color = val
		_update_material_colors()

@export var away_team_color: Color = Color(0.15, 0.35, 0.90, 1.0):
	set(val):
		away_team_color = val
		_update_material_colors()

@export var neutral_color: Color = Color(0.85, 0.85, 0.85, 1.0):
	set(val):
		neutral_color = val
		_update_material_colors()

@export_group("Sections")
## Si hay nodos hijos CrowdSection, mandan ellos: cada sección genera
## su grilla (filas x asientos) con sus propios parámetros. Así se le
## dice al sistema qué parte es tribuna: moviendo/rotando nodos y
## tocando filas, spacings, escalón y densidad. Sin secciones se usa
## el crowd_positions.json viejo (fallback).
@export var use_sections: bool = true

## Seed del patrón (jitter, densidad, anims). Cambiala para otro patrón.
@export var generation_seed: int = 12345

@export_group("Rendimiento")
## Qué tan rápido baja el detalle de los espectadores con la distancia (LOD).
## Godot calcula el LOD con la caja de toda la tribuna y no la de una persona,
## así que con 1.0 dibuja todo en detalle máximo. Con 0.1 la hinchada cuesta
## ~3 ms en vez de ~10 (GTX 1650, 1080p) y desde el penal no se nota.
@export_range(0.01, 1.0) var lod_bias_hinchada: float = 0.1

@export_group("Editor Tools")
@export var regenerate_crowd: bool = false:
	set(val):
		if val:
			regenerate_crowd = false
			_populate_multimesh()

var _instance_count: int = 0
var _return_timer: float = 0.0
var _is_reacting: bool = false
var _dirty: bool = false
## Por CrowdSection: {mmi: MultiMeshInstance3D -> {mm: MultiMesh}}.
## Un MultiMesh por sección = un draw call por tribuna + culling por
## caja (la cámara solo paga lo que ve) + LOD por tribuna.
var _section_data: Dictionary = {}

## Lo llaman los CrowdSection hijos al moverse o cambiar un parámetro.
## Solo marca dirty: se repuebla una vez por frame (ver _process).
func request_crowd_refresh() -> void:
	if Engine.is_editor_hint():
		_dirty = true

# IDs de animación definidos en crowd_anim_meta.json
const ANIM_IDLE: float = 0.0
const ANIM_CHEER: float = 1.0
const ANIM_VICTORY: float = 2.0
const ANIM_ANGRY: float = 3.0
const ANIM_CLAP: float = 4.0
const ANIM_SITTING: float = 5.0
const ANIM_SITTING_CLAP: float = 6.0

func _ready() -> void:
	# Cargar siempre los assets y poblar el MultiMesh para que se vea en el Editor y en Juego
	_setup_mesh_and_material()
	_populate_multimesh()
	_update_material_colors()
	_update_vat_size_from_meta()
	# El VAT mueve los vertices por shader: sin AABB custom Godot
	# cullea mal y se ven destellos / desapariciones por frustum.
	# Cubre toda la tribuna (posiciones x[-45,30] y[1.5,19] z[-60,66] + 2m de alto).
	custom_aabb = AABB(Vector3(-55, -1, -75), Vector3(110, 32, 160))
	# La shadow mesh no tiene UV2 (y no debe generarse): si el crowd
	# proyecta sombras, la pasada de sombras colapsa a puntos.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if not Engine.is_editor_hint():
		_connect_game_signals()

func _setup_mesh_and_material() -> void:
	# Siempre preferir el GLB rebakeado: el .tscn puede traer una copia
	# vieja embebida. Si el GLB carga, pisa al embebido.
	var glb = load("res://assets/models/people/crowd_spectator_mesh.glb")
	if glb:
		var inst = glb.instantiate()
		var m_inst = _find_mesh_instance(inst)
		if m_inst and m_inst.mesh:
			spectator_mesh = m_inst.mesh
		inst.queue_free()

	var glb_low = load(LOW_GLB_PATH)
	if glb_low:
		var inst_low = glb_low.instantiate()
		var m_low = _find_mesh_instance(inst_low)
		if m_low and m_low.mesh:
			spectator_mesh_low = m_low.mesh
		inst_low.queue_free()
	if spectator_mesh_low == null:
		spectator_mesh_low = spectator_mesh # fallback: todo en HIGH
	spectator_mesh = _con_lods(spectator_mesh)
	spectator_mesh_low = _con_lods(spectator_mesh_low)

	if not vat_material:
		vat_material = load("res://resources/materials/crowd_vat_material.tres")

	# Material LOW = clon del HIGH pero con su VAT y su ancho.
	# OJO: ShaderMaterial.duplicate() comparte el shader, no los params.
	if vat_material:
		material_override = vat_material
		vat_material_low = vat_material.duplicate() as ShaderMaterial
		var vat_low_tex = load(LOW_VAT_PATH)
		if vat_low_tex:
			vat_material_low.set_shader_parameter("vat_texture", vat_low_tex)

## Le agrega niveles de detalle (LOD) a la malla del espectador para que las
## tribunas lejanas dibujen muchos menos triangulos (la baja pasa de 492 a 161,
## 79 y 31). La hinchada esta limitada por vertices, no por pixeles, asi que
## esto es lo que mas la abarata. Godot elige el nivel por tribuna segun la
## distancia.
##
## Es seguro con el VAT: los LOD son solo indices nuevos sobre los mismos
## vertices, y cada vertice sigue leyendo su fila del VAT por su UV2. Lo que
## rompe el VAT es generar LODs al importar el GLB (ahi Godot puede partir o
## soldar vertices), por eso se hace aca y no en el .import.
static var _cache_lods: Dictionary = {}
func _con_lods(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	if _cache_lods.has(mesh):
		return _cache_lods[mesh]
	if _cache_lods.values().has(mesh):
		return mesh # ya tiene LODs
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(mesh.surface_get_primitive_type(s), mesh.surface_get_arrays(s), [], {},
				mesh.surface_get_material(s), mesh.surface_get_name(s))
	im.generate_lods(25.0, 60.0, [])
	var con_lods: ArrayMesh = im.get_mesh()
	_cache_lods[mesh] = con_lods
	return con_lods

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found = _find_mesh_instance(c)
		if found:
			return found
	return null

## Cada entrada: {pos: Vector3 global, team: int, sit_prob: float, stand: bool}
func _populate_multimesh() -> void:
	_setup_mesh_and_material()
	if spectator_mesh == null:
		push_warning("CrowdManager: sin spectator_mesh, no se puede poblar.")
		return

	# El padre no dibuja nada: cada sección tiene su propio MultiMesh
	# hijo (un draw call por tribuna). Así hay culling por tribuna y
	# LOD por tribuna en vez de un solo bloque gigante siempre visible.
	multimesh = null
	_clear_section_mmis()
	_section_data.clear()

	var rng = RandomNumberGenerator.new()
	rng.seed = generation_seed
	var section_counts: Dictionary = {}
	var sections: Array[CrowdSection] = _get_sections()
	_instance_count = 0

	if use_sections and not sections.is_empty():
		# Modo generativo: cada sección aporta su grilla a SU MultiMesh.
		var idx := 0
		for s in sections:
			var entries: Array = []
			var xf: Transform3D = s.global_transform
			for e in s.generate_entries(rng):
				var pos: Vector3 = xf * (e["pos"] as Vector3)
				var row: int = int(e["row"])
				entries.append({
					"pos": pos,
					"team": _resolve_team(s.team, rng),
					"sit_prob": s.sitting_ratio,
					"stand": row < s.standing_rows,
				})
			var use_low: bool = (s.detail == CrowdSection.Detail.BAJA)
			_build_section_mmi(idx, s.section_name, entries, use_low, rng)
			section_counts[s.section_name] = int(section_counts.get(s.section_name, 0)) + entries.size()
			_instance_count += entries.size()
			idx += 1
	else:
		# Fallback: JSON plano con la lógica vieja por Z (deprecated).
		if not FileAccess.file_exists(positions_json_path):
			push_warning("CrowdManager: no se encontro el archivo de posiciones " + positions_json_path)
		else:
			var file = FileAccess.open(positions_json_path, FileAccess.READ)
			var json = JSON.new()
			if json.parse(file.get_as_text()) != OK:
				push_warning("CrowdManager: error parseando JSON de posiciones")
			else:
				var entries: Array = []
				var positions: Array = json.data
				for p_arr in positions:
					var pos = Vector3(p_arr[0], p_arr[1], p_arr[2])
					var team: int = 0
					if pos.z > 30.0:
						team = 1 if rng.randf() < 0.8 else 2 # Visitante
					elif pos.z < -10.0:
						team = 0 if rng.randf() < 0.85 else 2 # Local
					else:
						var r = rng.randf()
						if r < 0.45: team = 0
						elif r < 0.75: team = 1
						else: team = 2
					entries.append({
						"pos": pos,
						"team": team,
						"sit_prob": 0.65,
						"stand": pos.y <= 6.0,
					})
				_build_section_mmi(0, "json_fallback", entries, false, rng)
				section_counts["json_fallback"] = entries.size()
				_instance_count = entries.size()

	if _instance_count == 0:
		push_warning("CrowdManager: 0 espectadores generados (¿secciones vacías?).")
		return

	print("[CrowdManager] " + ("Editor: " if Engine.is_editor_hint() else "Runtime: ") + "Hinchada cargada (" + str(_instance_count) + " espectadores en " + str(_section_data.size()) + " MultiMesh).")
	if not section_counts.is_empty():
		var parts: PackedStringArray = []
		for k in section_counts.keys():
			parts.append(str(k) + ": " + str(section_counts[k]))
		print("[CrowdManager] Por sección -> " + ", ".join(parts))

## Crea el MultiMeshInstance3D hijo para una sección (o fallback).
func _build_section_mmi(idx: int, label: String, entries: Array, use_low: bool, rng: RandomNumberGenerator) -> void:

	var mesh: Mesh = spectator_mesh_low if (use_low and spectator_mesh_low) else spectator_mesh
	var mat: Material = vat_material_low if (use_low and vat_material_low) else vat_material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = entries.size()

	var bmin := Vector3(INF, INF, INF)
	var bmax := Vector3(-INF, -INF, -INF)

	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var pos: Vector3 = e["pos"]
		var team: int = int(e["team"])

		# Mirar hacia el centro de la cancha
		var pitch_center = Vector3(0.0, pos.y, 20.0)
		var look_dir = (pitch_center - pos).normalized()
		look_dir.y = 0.0
		if look_dir.is_zero_approx():
			look_dir = Vector3.FORWARD
		else:
			look_dir = look_dir.normalized()

		# El modelo mira hacia +Z (la nariz es el punto de mayor Z):
		# use_model_front=true para que el FRENTE apunte a la cancha.
		# Sin esto quedan todos de espaldas.
		var basis = Basis.looking_at(look_dir, Vector3.UP, true)
		var scale_var = rng.randf_range(0.94, 1.06)
		var yaw_jitter = rng.randf_range(-0.14, 0.14)
		basis = basis.rotated(Vector3.UP, yaw_jitter)
		basis = basis.scaled(Vector3(scale_var, scale_var, scale_var))

		mm.set_instance_transform(i, Transform3D(basis, pos))

		# Animación inicial
		var init_anim = ANIM_IDLE
		if not bool(e["stand"]) and rng.randf() < float(e["sit_prob"]):
			init_anim = ANIM_SITTING if rng.randf() < 0.6 else ANIM_SITTING_CLAP
		else:
			init_anim = ANIM_IDLE if rng.randf() < 0.7 else ANIM_CLAP

		var time_offset = rng.randf_range(0.0, 10.0)
		var speed_factor = rng.randf_range(0.92, 1.08)

		mm.set_instance_custom_data(i, Color(time_offset, init_anim, speed_factor, float(team)))

		var shade = rng.randf_range(0.75, 1.0)
		mm.set_instance_color(i, Color(shade, shade, shade, 1.0))

		bmin = bmin.min(pos)
		bmax = bmax.max(pos)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_%d_%s" % [idx, label.replace(" ", "_")]
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.lod_bias = lod_bias_hinchada
	if entries.is_empty():
		mmi.custom_aabb = AABB(Vector3.ZERO, Vector3.ONE)
	else:
		# Caja propia = culling real: la cámara solo paga esta tribuna
		# si la ve. Margen para cuerpos (~1.9m) y saltos.
		var pad_min := bmin + Vector3(-1.5, -0.5, -1.5)
		var pad_max := bmax + Vector3(1.5, 2.5, 1.5)
		mmi.custom_aabb = AABB(pad_min, pad_max - pad_min)
	add_child(mmi)
	_section_data[mmi] = {"mm": mm}

func _clear_section_mmis() -> void:
	for c in get_children():
		if c is MultiMeshInstance3D and (c.name as String).begins_with("MM_"):
			remove_child(c)
			c.queue_free()

## Secciones hijas habilitadas, en orden de árbol (el orden define el
## orden del RNG, o sea el patrón). owned=false para que funcione
## también con nodos creados por código (sin owner de escena).
func _get_sections() -> Array[CrowdSection]:
	var out: Array[CrowdSection] = []
	if not use_sections:
		return out
	for child in find_children("*", "CrowdSection", true, false):
		if child is CrowdSection and (child as CrowdSection).enabled:
			out.append(child as CrowdSection)
	return out

func _resolve_team(st: int, rng: RandomNumberGenerator) -> int:
	if st == CrowdSection.Team.MIXTO:
		var r = rng.randf()
		if r < 0.45:
			return 0
		elif r < 0.75:
			return 1
		return 2
	return st

func _update_material_colors() -> void:
	for mat in _all_vat_materials():
		mat.set_shader_parameter("home_team_color", home_team_color)
		mat.set_shader_parameter("away_team_color", away_team_color)
		mat.set_shader_parameter("neutral_color", neutral_color)

func _all_vat_materials() -> Array:
	var out: Array = []
	var hi = material_override as ShaderMaterial
	if hi:
		out.append(hi)
	if vat_material_low and vat_material_low != hi:
		out.append(vat_material_low)
	return out

func _update_vat_size_from_meta() -> void:
	# El shader necesita vat_width == ancho del EXR == num_vertices del bake.
	# Si el rebake cambia el conteo (distinta version de Blender/decimate),
	# el .tres quedaria desfasado y el v_id decodificaria mal (triangulos).
	_apply_meta_to_material(material_override as ShaderMaterial, HIGH_META_PATH)
	_apply_meta_to_material(vat_material_low, LOW_META_PATH)

func _apply_meta_to_material(mat: ShaderMaterial, meta_path: String) -> void:
	if mat == null or not FileAccess.file_exists(meta_path):
		return
	var f := FileAccess.open(meta_path, FileAccess.READ)
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		push_warning("CrowdManager: no se pudo leer " + meta_path)
		return
	var d: Dictionary = j.data
	if d.has("num_vertices") and d.has("total_frames"):
		mat.set_shader_parameter("vat_width", int(d["num_vertices"]))
		mat.set_shader_parameter("total_frames", int(d["total_frames"]))

func _connect_game_signals() -> void:
	var sm = get_node_or_null("/root/SoundManager")
	if sm and sm.has_signal("crowd_celebration_triggered"):
		sm.crowd_celebration_triggered.connect(func(duration): celebrate_goal(true, duration))
		
	# El GameManager es la raiz de game.tscn (se llama "Game"), asi que se lo
	# busca subiendo por el arbol y no por nombre.
	var gm: Node = get_parent()
	while gm and not (gm is GameManager):
		gm = gm.get_parent()
	if gm:
		if gm.has_signal("goal_scored"):
			gm.goal_scored.connect(func(_kicker): celebrate_goal(true, 6.0))
		if gm.has_signal("ball_saved"):
			gm.ball_saved.connect(func(): lament_miss(true, 4.5))
		if gm.has_signal("ball_missed"):
			gm.ball_missed.connect(func(): lament_miss(true, 4.5))
		if gm.has_signal("penalty_started"):
			gm.penalty_started.connect(prepare_kick_tension)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		# Refresh diferido: los CrowdSection marcan dirty al moverse o
		# cambiar parámetros, y acá se repuebla 1 vez por frame como mucho.
		if _dirty:
			_dirty = false
			_populate_multimesh()
		return

	if _is_reacting and _return_timer > 0.0:
		_return_timer -= delta
		if _return_timer <= 0.0:
			_return_to_normal()

# Las reacciones no tocan las instancias: el shader elige la animacion de
# cada espectador segun la reaccion actual, su equipo y un numero al azar
# propio (ver crowd_vat.gdshader). Antes se reescribian las ~25.000 instancias
# desde GDScript y el juego se trababa 10-20 ms justo en el gol.
const REACCION_NORMAL := 0
const REACCION_GOL := 1
const REACCION_LAMENTO := 2
const REACCION_TENSION := 3

func _set_reaccion(reaccion: int, equipo: int) -> void:
	for mat in _all_vat_materials():
		mat.set_shader_parameter("reaccion", reaccion)
		mat.set_shader_parameter("equipo_reaccion", equipo)

## Celebración de Gol eufórica
func celebrate_goal(is_home_goal: bool = true, duration: float = 6.0) -> void:
	_is_reacting = true
	_return_timer = duration
	_set_reaccion(REACCION_GOL, 0 if is_home_goal else 1)

## Reacción a penal atajado o desviado
func lament_miss(is_home_kicker: bool = true, duration: float = 4.5) -> void:
	_is_reacting = true
	_return_timer = duration
	_set_reaccion(REACCION_LAMENTO, 0 if is_home_kicker else 1)

## Tensión antes de patear el penal
func prepare_kick_tension() -> void:
	_set_reaccion(REACCION_TENSION, 0)

## Volver al estado normal de cánticos e hinchada de tribuna
func _return_to_normal() -> void:
	_is_reacting = false
	_set_reaccion(REACCION_NORMAL, 0)
