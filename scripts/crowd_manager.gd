@tool
class_name CrowdManager
extends MultiMeshInstance3D

## CrowdManager - la hinchada del estadio.
##
## Cada nodo hijo CrowdSection es una tribuna. Para cada una se arman grupos
## de espectadores con tres niveles de detalle que Godot cambia solo segun
## la distancia a la camara:
##   cerca / media -> el personaje 3D (unos 2600 y 1500 triangulos)
##   lejos         -> un cartel con una "foto" del personaje (impostor)
## Cada espectador tiene su tipo de NPC, su ropa, su piel y su personalidad.
## Los assets salen de tools/hinchada_hornear.gd. Ver docs/hinchada.md.

const RUTA_BANCO := "res://resources/hinchada/banco.tres"
const SHADER_3D := preload("res://resources/shaders/hinchada_3d.gdshader")
const SHADER_IMPOSTOR := preload("res://resources/shaders/hinchada_impostor.gdshader")

## NPC horneados. Vacio = usa resources/hinchada/banco.tres.
@export var banco: HinchadaBanco
@export_file("*.json") var positions_json_path: String = "res://assets/models/people/crowd_positions.json"

@export_group("Team Colors")
@export var home_team_color: Color = Color(0.85, 0.15, 0.15, 1.0):
	set(val):
		home_team_color = val
		_pedir_refresco()

@export var away_team_color: Color = Color(0.15, 0.35, 0.90, 1.0):
	set(val):
		away_team_color = val
		_pedir_refresco()

## Ya no se usa: el publico neutral viste ropa comun (ver ROPA_COMUN).
@export var neutral_color: Color = Color(0.85, 0.85, 0.85, 1.0)

@export_group("Equipaciones")
## Camisetas de los hinchas locales (hasta 8). Vacio = se inventan tres a
## partir de home_team_color (titular, alternativa y retro).
@export var equipaciones_local: Array[HinchadaEquipacion] = []:
	set(val):
		equipaciones_local = val
		_pedir_refresco()
## Camisetas de los hinchas visitantes (hasta 8).
@export var equipaciones_visitante: Array[HinchadaEquipacion] = []:
	set(val):
		equipaciones_visitante = val
		_pedir_refresco()
## De los hinchas de un equipo, cuantos van con la camiseta. El resto va de
## ropa comun.
@export_range(0.0, 1.0, 0.01) var proporcion_camiseta: float = 0.72:
	set(val):
		proporcion_camiseta = val
		_pedir_refresco()

@export_group("Sections")
## Si hay nodos hijos CrowdSection, mandan ellos: cada sección genera
## su grilla (filas x asientos) con sus propios parámetros. Sin secciones se
## usa el crowd_positions.json viejo.
@export var use_sections: bool = true
## Seed del patrón (quien se sienta donde, ropa, personalidades).
@export var generation_seed: int = 12345:
	set(val):
		generation_seed = val
		_pedir_refresco()
## Hacia donde miran los que estan de pie.
@export var centro_cancha: Vector3 = Vector3(0.0, 0.0, 20.0)

@export_group("Variedad")
## Asientos que quedan vacios ademas de la densidad de cada seccion.
@export_range(0.0, 0.6, 0.01) var asientos_vacios: float = 0.05:
	set(val):
		asientos_vacios = val
		_pedir_refresco()
## Cuanto cambia la altura de una persona a otra (0.08 = +-8%).
@export_range(0.0, 0.2, 0.01) var variacion_altura: float = 0.08
## Cuanto cambia el ancho (contextura).
@export_range(0.0, 0.25, 0.01) var variacion_ancho: float = 0.12
## Corrimiento de los sentados respecto del punto de la grilla, en el espacio
## de la seccion (x al costado, y arriba, z hacia atras). Sirve para que
## queden justo sobre las butacas del estadio.
@export var sentado_desplazamiento: Vector3 = Vector3(0.0, 0.0, 0.0):
	set(val):
		sentado_desplazamiento = val
		_pedir_refresco()
## Tamaño de las zonas donde se junta gente parecida (barras que saltan,
## plateas tranquilas) en las secciones de estilo AUTO. En metros.
@export var tamano_zonas: float = 14.0

@export_group("Rendimiento")
## Altura en pantalla (en pixeles, para 1080p) desde la que un espectador usa
## cada nivel de detalle. Mas chico = mejor calidad y mas costo.
@export var px_cerca: float = 330.0
## Por debajo de esto se dibuja como cartel (impostor).
@export var px_media: float = 170.0
## false = nunca usa carteles (para comparar o sacar fotos de cerca).
@export var usar_impostores: bool = true:
	set(val):
		usar_impostores = val
		_pedir_refresco()

## Para depurar: -1 normal; 0 cerca, 1 media, 2 carteles -> toda la hinchada
## usa ese nivel sin importar la distancia.
@export_range(-1, 2) var forzar_nivel: int = -1:
	set(val):
		forzar_nivel = val
		if is_inside_tree():
			_actualizar_lod(true)

## Para depurar o mirar una animacion: si se escribe su nombre (idle, aplauso,
## festejo, victoria, enojo, triste, sentado...), toda la hinchada la hace.
@export var depurar_animacion: String = "":
	set(val):
		depurar_animacion = val
		_aplicar_tabla()

@export_group("Editor Tools")
@export var regenerate_crowd: bool = false:
	set(val):
		if val:
			regenerate_crowd = false
			_populate_multimesh()

## Ropa comun: [color, peso]. Mas grises y oscuros que colores, como en una
## tribuna real.
const ROPA_COMUN := [
	[Color(0.90, 0.90, 0.88), 9.0], [Color(0.08, 0.08, 0.09), 9.0], [Color(0.35, 0.36, 0.38), 6.0],
	[Color(0.62, 0.63, 0.65), 5.0], [Color(0.10, 0.14, 0.28), 6.0], [Color(0.55, 0.47, 0.36), 3.0],
	[Color(0.25, 0.30, 0.20), 2.5], [Color(0.42, 0.10, 0.13), 2.5], [Color(0.45, 0.62, 0.78), 3.0],
	[Color(0.75, 0.60, 0.15), 1.5], [Color(0.30, 0.20, 0.14), 2.0], [Color(0.12, 0.33, 0.24), 2.0],
	[Color(0.72, 0.35, 0.18), 1.2], [Color(0.48, 0.30, 0.50), 1.0],
]
## Pantalones de la ropa comun: jean, negro, gris, beige, azul, jean claro.
const PANTALON_COMUN := [
	Color(0.16, 0.24, 0.42), Color(0.06, 0.06, 0.07), Color(0.30, 0.31, 0.33),
	Color(0.58, 0.50, 0.38), Color(0.09, 0.11, 0.20), Color(0.38, 0.50, 0.66),
]
## Multiplicadores sobre la textura de piel (5 tonos).
const TONOS_PIEL := [
	Color(1.0, 1.0, 1.0), Color(1.08, 0.98, 0.92), Color(0.86, 0.74, 0.64),
	Color(0.62, 0.48, 0.40), Color(0.42, 0.31, 0.26),
]
const PESO_PIEL := [30.0, 18.0, 28.0, 16.0, 8.0]
## Colores de pelo 0 a 5. El 6 es gorra y el 7 pelado (ver el shader).
const TONOS_PELO := [
	Color(0.05, 0.04, 0.04), Color(0.14, 0.09, 0.06), Color(0.28, 0.18, 0.10),
	Color(0.55, 0.42, 0.22), Color(0.48, 0.48, 0.50), Color(0.32, 0.12, 0.06),
]
const PESO_PELO := [34.0, 26.0, 14.0, 5.0, 7.0, 2.0, 7.0, 5.0]

const KIT_VISITANTE := 8
const KIT_COMUN := 16
const ALTO_PERSONA := 1.8

var _instance_count: int = 0
var _return_timer: float = 0.0
var _is_reacting: bool = false
var _dirty: bool = false
var _tiempo: float = 0.0
var _evento: int = 0
var _equipo_evento: int = 0
var _materiales: Array[ShaderMaterial] = []
var _mat_npc: Array[ShaderMaterial] = []
var _mat_impostor: ShaderMaterial
var _quad: QuadMesh
## Un arreglo por nivel de detalle (0 cerca, 1 media, 2 impostor).
var _niveles: Array = [[], [], []]
var _factor_lod: float = -1.0
var _kits_primario: Array[Color] = []
var _kits_peso: Array[float] = []
var _ruido: FastNoiseLite

## Lo llaman los CrowdSection hijos al moverse o cambiar un parámetro.
## Solo marca dirty: se repuebla una vez por frame (ver _process).
func request_crowd_refresh() -> void:
	if Engine.is_editor_hint():
		_dirty = true

func _pedir_refresco() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		_dirty = true

func _ready() -> void:
	multimesh = null
	material_override = null
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_populate_multimesh()
	if not Engine.is_editor_hint():
		_connect_game_signals()

# ------------------------------------------------------------ materiales

func _cargar_banco() -> bool:
	if banco == null and ResourceLoader.exists(RUTA_BANCO):
		banco = load(RUTA_BANCO)
	if banco == null or banco.npcs.is_empty():
		push_warning("CrowdManager: falta hornear la hinchada (godot --path . res://tools/hinchada_hornear.tscn).")
		return false
	return true

func _armar_materiales() -> void:
	_materiales.clear()
	_mat_npc.clear()
	for npc in banco.npcs:
		var m := ShaderMaterial.new()
		m.shader = SHADER_3D
		m.set_shader_parameter("vat", npc.vat)
		m.set_shader_parameter("vat_normales", npc.vat_normales)
		m.set_shader_parameter("albedo", npc.albedo)
		m.set_shader_parameter("lum_media", npc.lum_media)
		_mat_npc.append(m)
		_materiales.append(m)
	_mat_impostor = ShaderMaterial.new()
	_mat_impostor.shader = SHADER_IMPOSTOR
	_mat_impostor.set_shader_parameter("atlas_albedo", banco.imp_albedo)
	_mat_impostor.set_shader_parameter("atlas_mascara", banco.imp_mascara)
	_mat_impostor.set_shader_parameter("atlas_coords", banco.imp_coords)
	_mat_impostor.set_shader_parameter("celda_mundo", banco.imp_celda)
	_mat_impostor.set_shader_parameter("cuadros_por_anim", banco.imp_cuadros)
	_mat_impostor.set_shader_parameter("total_anims", banco.anim_nombres.size())
	_mat_impostor.set_shader_parameter("npcs_por_fila", banco.imp_npc_por_fila)
	_mat_impostor.set_shader_parameter("bloques", Vector2i(mini(banco.npcs.size(), banco.imp_npc_por_fila),
			int(ceil(float(banco.npcs.size()) / float(banco.imp_npc_por_fila)))))
	_materiales.append(_mat_impostor)

	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
		_quad.center_offset = Vector3(0.0, 0.5, 0.0)
		_quad.custom_aabb = AABB(Vector3(-1.0, -0.1, -1.0), Vector3(2.0, 2.8, 2.0))

	# Equipaciones: 0-7 local, 8-15 visitante, 16+ ropa comun.
	var secundario := PackedVector3Array()
	var pantalon := PackedVector3Array()
	var patron := PackedInt32Array()
	secundario.resize(32)
	pantalon.resize(32)
	patron.resize(32)
	_kits_primario.resize(32)
	_kits_peso.resize(32)
	_kits_peso.fill(0.0)
	var listas := [_kits_de(equipaciones_local, home_team_color), _kits_de(equipaciones_visitante, away_team_color)]
	for eq in 2:
		for i in mini(listas[eq].size(), 8):
			var k: HinchadaEquipacion = listas[eq][i]
			var n := eq * KIT_VISITANTE + i
			_kits_primario[n] = k.color_primario
			_kits_peso[n] = maxf(k.peso, 0.0)
			secundario[n] = _lineal(k.color_secundario)
			pantalon[n] = _lineal(k.color_pantalon)
			patron[n] = k.patron
	for i in 16:
		var n := KIT_COMUN + i
		pantalon[n] = _lineal(PANTALON_COMUN[i % PANTALON_COMUN.size()])
		secundario[n] = _lineal(Color(0.9, 0.9, 0.88) if i % 2 == 0 else Color(0.1, 0.1, 0.12))
		# Algunas remeras comunes son rayadas.
		patron[n] = HinchadaEquipacion.Patron.AROS if i == 12 or i == 13 else (
				HinchadaEquipacion.Patron.RAYAS_VERTICALES if i == 14 else HinchadaEquipacion.Patron.LISO)

	var piel := PackedVector3Array()
	var pelo := PackedVector3Array()
	piel.resize(8)
	pelo.resize(8)
	for i in TONOS_PIEL.size():
		piel[i] = Vector3(TONOS_PIEL[i].r, TONOS_PIEL[i].g, TONOS_PIEL[i].b)
	for i in TONOS_PELO.size():
		pelo[i] = _lineal(TONOS_PELO[i])

	var inicio := banco.anim_inicio.duplicate()
	var cuadros := banco.anim_cuadros.duplicate()
	inicio.resize(16)
	cuadros.resize(16)
	for i in range(banco.anim_cuadros.size(), 16):
		cuadros[i] = 1
	_aplicar_tabla()
	for m in _materiales:
		m.set_shader_parameter("fps_anim", banco.fps)
		m.set_shader_parameter("anim_inicio", inicio)
		m.set_shader_parameter("anim_cuadros", cuadros)
		m.set_shader_parameter("kit_secundario", secundario)
		m.set_shader_parameter("kit_pantalon", pantalon)
		m.set_shader_parameter("kit_patron", patron)
		m.set_shader_parameter("tonos_piel", piel)
		m.set_shader_parameter("tonos_pelo", pelo)
		m.set_shader_parameter("tiempo", _tiempo)
		m.set_shader_parameter("evento", _evento)
		m.set_shader_parameter("evento_previo", _evento)
		m.set_shader_parameter("equipo_evento", _equipo_evento)

func _aplicar_tabla() -> void:
	if banco == null or _materiales.is_empty():
		return
	var tabla := HinchadaConductas.armar_tabla(banco)
	if depurar_animacion != "" and banco.anim_nombres.has(depurar_animacion):
		tabla.fill(banco.id_anim(depurar_animacion))
	for m in _materiales:
		m.set_shader_parameter("tabla", tabla)

func _kits_de(lista: Array[HinchadaEquipacion], color: Color) -> Array[HinchadaEquipacion]:
	var limpia: Array[HinchadaEquipacion] = []
	for k in lista:
		if k != null:
			limpia.append(k)
	if not limpia.is_empty():
		return limpia
	var P := HinchadaEquipacion.Patron
	var claro := Color(0.93, 0.93, 0.91)
	var oscuro := color.darkened(0.75)
	var contraste := claro if color.get_luminance() < 0.6 else oscuro
	return [
		HinchadaEquipacion.crear("Titular", color, contraste, P.LISO, oscuro, 6.0),
		HinchadaEquipacion.crear("Alternativa", contraste, color, P.MANGAS, color.darkened(0.35), 2.0),
		HinchadaEquipacion.crear("Retro", color, contraste, P.FRANJA_PECHO, contraste.darkened(0.1), 1.5),
	]

func _lineal(c: Color) -> Vector3:
	var l := c.srgb_to_linear()
	return Vector3(l.r, l.g, l.b)

# ------------------------------------------------------------ poblar

func _populate_multimesh() -> void:
	multimesh = null
	_clear_section_mmis()
	_niveles = [[], [], []]
	_factor_lod = -1.0
	_instance_count = 0
	if not _cargar_banco():
		return
	_armar_materiales()

	_ruido = FastNoiseLite.new()
	_ruido.seed = generation_seed
	_ruido.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ruido.frequency = 1.0 / maxf(tamano_zonas, 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed
	var section_counts: Dictionary = {}
	var sections: Array[CrowdSection] = _get_sections()
	var a_local := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY

	if use_sections and not sections.is_empty():
		var idx := 0
		for s in sections:
			var xf: Transform3D = s.global_transform.orthonormalized()
			var entries: Array = []
			var frente := -xf.basis.z
			for e in s.generate_entries(rng):
				if rng.randf() < asientos_vacios:
					continue
				entries.append({
					"pos": e["pos"],
					"frente": e.get("frente", Vector3.FORWARD),
					"team": _resolve_team(s.team, rng),
					"sit_prob": s.sitting_ratio,
					"stand": int(e["row"]) < s.standing_rows,
				})
			var n := _build_section_mmi(idx, s.section_name, entries, xf, frente, s.estilo, a_local, rng)
			section_counts[s.section_name] = int(section_counts.get(s.section_name, 0)) + n
			_instance_count += n
			idx += 1
	elif FileAccess.file_exists(positions_json_path):
		# Sin secciones: JSON plano con la logica vieja por Z.
		var datos = JSON.parse_string(FileAccess.get_file_as_string(positions_json_path))
		if datos is Array:
			var entries: Array = []
			for p_arr in datos:
				var pos := Vector3(p_arr[0], p_arr[1], p_arr[2])
				var team := 2
				if pos.z > 30.0:
					team = 1 if rng.randf() < 0.8 else 2
				elif pos.z < -10.0:
					team = 0 if rng.randf() < 0.85 else 2
				else:
					team = _resolve_team(CrowdSection.Team.MIXTO, rng)
				entries.append({"pos": pos, "team": team, "sit_prob": 0.65, "stand": pos.y <= 6.0})
			_instance_count = _build_section_mmi(0, "json", entries, Transform3D.IDENTITY, Vector3.ZERO,
					CrowdSection.Estilo.AUTO, a_local, rng)
			section_counts["json"] = _instance_count
	else:
		push_warning("CrowdManager: no hay secciones ni " + positions_json_path)

	if _instance_count == 0:
		push_warning("CrowdManager: 0 espectadores generados (¿secciones vacías?).")
		return
	_actualizar_lod(true)

	print("[CrowdManager] " + ("Editor: " if Engine.is_editor_hint() else "Runtime: ") + "Hinchada cargada (%d espectadores, %d tipos de NPC, %d secciones)." % [
			_instance_count, banco.npcs.size(), _niveles[2].size() if usar_impostores else section_counts.size()])
	var parts: PackedStringArray = []
	for k in section_counts.keys():
		parts.append(str(k) + ": " + str(section_counts[k]))
	print("[CrowdManager] Por sección -> " + ", ".join(parts))

## Arma los MultiMesh de una seccion: uno de impostores con todos, y por cada
## tipo de NPC uno por nivel de detalle 3D. `xf` lleva las posiciones de las
## entradas al mundo; `frente` es hacia donde mira la tribuna (cero = hacia
## el centro de la cancha). Devuelve cuantos espectadores quedaron.
func _build_section_mmi(idx: int, label: String, entries: Array, xf: Transform3D, frente: Vector3,
		estilo: int, a_local: Transform3D, rng: RandomNumberGenerator) -> int:
	if entries.is_empty():
		return 0
	var n_npc := banco.npcs.size()
	var peso_npc: Array[float] = []
	for npc in banco.npcs:
		peso_npc.append(maxf(npc.peso, 0.0))

	var todos := PackedFloat32Array()
	var por_npc: Array[PackedFloat32Array] = []
	for i in n_npc:
		por_npc.append(PackedFloat32Array())
	var bmin := Vector3(INF, INF, INF)
	var bmax := Vector3(-INF, -INF, -INF)
	var P := HinchadaConductas.Personalidad
	frente.y = 0.0
	var hay_frente := frente.length_squared() > 0.0001
	if hay_frente:
		frente = frente.normalized()

	for e: Dictionary in entries:
		var team: int = e["team"]
		var pos_mundo: Vector3 = xf * (e["pos"] as Vector3)

		# Personalidad segun el estilo de la tribuna (o la zona, si es AUTO).
		var mezcla: Array = HinchadaConductas.MEZCLA_GENERAL
		match estilo:
			CrowdSection.Estilo.PLATEA: mezcla = HinchadaConductas.MEZCLA_PLATEA
			CrowdSection.Estilo.POPULAR: mezcla = HinchadaConductas.MEZCLA_POPULAR
			CrowdSection.Estilo.AUTO:
				var zona := _ruido.get_noise_2d(pos_mundo.x + pos_mundo.y * 0.7, pos_mundo.z)
				if zona > 0.38 and team != 2:
					mezcla = HinchadaConductas.MEZCLA_POPULAR
				elif zona < -0.35:
					mezcla = HinchadaConductas.MEZCLA_PLATEA
		var pers := _elegir(mezcla, rng)
		if team == 2 and pers == P.FANATICO:
			pers = P.APLAUDIDOR

		var sentado := not bool(e["stand"]) and rng.randf() < float(e["sit_prob"])
		if pers == P.FANATICO or (pers == P.EUFORICO and rng.randf() < 0.5):
			sentado = false
		elif pers == P.CHARLATAN or pers == P.TRANQUILO:
			sentado = not bool(e["stand"]) and rng.randf() < maxf(float(e["sit_prob"]), 0.85)

		# Ropa
		var kit := 0
		var primario := Color.WHITE
		if team < 2 and rng.randf() < proporcion_camiseta:
			kit = _elegir(_kits_peso.slice(team * KIT_VISITANTE, team * KIT_VISITANTE + 8), rng) + team * KIT_VISITANTE
			primario = _kits_primario[kit]
		else:
			kit = KIT_COMUN + rng.randi_range(0, 15)
			primario = _elegir_color(ROPA_COMUN, rng)
		var brillo := rng.randf_range(0.82, 1.06)
		var prim := Color(primario.r * brillo, primario.g * brillo, primario.b * brillo).srgb_to_linear()

		var piel := _elegir(PESO_PIEL, rng)
		var pelo := _elegir(PESO_PELO, rng)
		var npc := _elegir(peso_npc, rng)

		# Orientacion: los sentados miran derecho segun la tribuna; los de pie
		# giran un poco hacia el centro de la cancha.
		var a_cancha := centro_cancha - pos_mundo
		a_cancha.y = 0.0
		a_cancha = a_cancha.normalized() if a_cancha.length_squared() > 0.01 else Vector3.FORWARD
		var mira := a_cancha
		if hay_frente:
			# En las secciones curvas cada asiento mira hacia su lado.
			var f := frente
			if e.has("frente"):
				f = xf.basis * (e["frente"] as Vector3)
				f.y = 0.0
				f = f.normalized()
			mira = f if sentado else f.slerp(a_cancha, 0.45).normalized()
		var basis := Basis.looking_at(mira, Vector3.UP, true)
		basis = basis.rotated(Vector3.UP, rng.randf_range(-0.07, 0.07) if sentado else rng.randf_range(-0.22, 0.22))
		var alto := 1.0 + rng.randf_range(-variacion_altura, variacion_altura)
		var ancho := alto * (1.0 + rng.randf_range(-variacion_ancho * 0.6, variacion_ancho))
		basis = basis.scaled_local(Vector3(ancho, alto, ancho))
		if sentado:
			pos_mundo = xf * ((e["pos"] as Vector3) + sentado_desplazamiento)
		var t := a_local * Transform3D(basis, pos_mundo)
		bmin = bmin.min(t.origin)
		bmax = bmax.max(t.origin)

		var fila := PackedFloat32Array([
			t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
			t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y,
			t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z,
			prim.r, prim.g, prim.b, 1.0,
			rng.randf(), float(pers + (8 if sentado else 0) + 16 * team), float(kit), float(piel + 8 * pelo + 64 * npc),
		])
		todos.append_array(fila)
		por_npc[npc].append_array(fila)

	var caja := AABB(bmin + Vector3(-1.5, -0.5, -1.5), (bmax - bmin) + Vector3(3.0, 3.2, 3.0))
	var nombre := "MM_%d_%s" % [idx, label.replace(" ", "_")]
	if usar_impostores:
		_niveles[2].append(_crear_mmi(nombre + "_lejos", _quad, _mat_impostor, todos, caja))
	for i in n_npc:
		if por_npc[i].is_empty():
			continue
		var npc: HinchadaNpc = banco.npcs[i]
		_niveles[0].append(_crear_mmi("%s_%s_cerca" % [nombre, npc.nombre], npc.malla_cerca, _mat_npc[i], por_npc[i], caja))
		_niveles[1].append(_crear_mmi("%s_%s_media" % [nombre, npc.nombre], npc.malla_media, _mat_npc[i], por_npc[i], caja))
	return todos.size() / 20

func _crear_mmi(nombre: String, malla: Mesh, mat: Material, buffer: PackedFloat32Array, caja: AABB) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = malla
	mm.instance_count = buffer.size() / 20
	mm.buffer = buffer
	var mmi := MultiMeshInstance3D.new()
	mmi.name = nombre
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# El shader mueve los vertices: sin caja propia Godot recorta mal.
	mmi.custom_aabb = caja
	mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mmi, false, Node.INTERNAL_MODE_BACK)
	return mmi

func _elegir(pesos: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for p in pesos:
		total += float(p)
	if total <= 0.0:
		return 0
	var r := rng.randf() * total
	for i in pesos.size():
		r -= float(pesos[i])
		if r <= 0.0:
			return i
	return pesos.size() - 1

func _elegir_color(lista: Array, rng: RandomNumberGenerator) -> Color:
	var pesos: Array = []
	for par in lista:
		pesos.append(par[1])
	return lista[_elegir(pesos, rng)][0]

func _clear_section_mmis() -> void:
	for c in get_children(true):
		if c is MultiMeshInstance3D and (c.name as String).begins_with("MM_"):
			remove_child(c)
			c.queue_free()

## Secciones hijas habilitadas, en orden de árbol (el orden define el
## orden del RNG, o sea el patrón).
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
		var r := rng.randf()
		if r < 0.45:
			return 0
		elif r < 0.75:
			return 1
		return 2
	return st

# ------------------------------------------------------------ niveles de detalle

## Godot cambia de nivel por distancia. Aca se traduce "cuantos pixeles de
## alto ocupa una persona" a metros, segun el zoom de la camara actual: con el
## teleobjetivo del penal la tribuna se ve grande aunque este lejos.
func _actualizar_lod(forzar: bool = false) -> void:
	var tan_medio := tan(deg_to_rad(70.0) * 0.5)
	var alto_px := 1080.0
	if is_inside_tree() and not Engine.is_editor_hint():
		var cam := get_viewport().get_camera_3d()
		if cam and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
			tan_medio = tan(deg_to_rad(cam.fov) * 0.5)
	var factor := ALTO_PERSONA * 0.5 * alto_px / tan_medio
	if not forzar and absf(factor - _factor_lod) < _factor_lod * 0.03:
		return
	_factor_lod = factor
	var d0 := factor / maxf(px_cerca, 1.0)
	var d1 := maxf(factor / maxf(px_media, 1.0), d0 + 1.0)
	var rangos := [[0.0, d0], [d0, d1 if usar_impostores else 0.0], [d1, 0.0]]
	for nivel in 3:
		for mmi: MultiMeshInstance3D in _niveles[nivel]:
			mmi.visible = forzar_nivel < 0 or forzar_nivel == nivel
			mmi.visibility_range_begin = rangos[nivel][0] if forzar_nivel < 0 else 0.0
			mmi.visibility_range_end = rangos[nivel][1] if forzar_nivel < 0 else 0.0

# ------------------------------------------------------------ juego

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
	if Engine.is_editor_hint() and _dirty:
		# Refresh diferido: los CrowdSection marcan dirty al moverse o
		# cambiar parámetros, y acá se repuebla 1 vez por frame como mucho.
		_dirty = false
		_populate_multimesh()
	if _materiales.is_empty():
		return
	_tiempo += delta
	for m in _materiales:
		m.set_shader_parameter("tiempo", _tiempo)
	if Engine.is_editor_hint():
		return
	_actualizar_lod()
	if _is_reacting and _return_timer > 0.0:
		_return_timer -= delta
		if _return_timer <= 0.0:
			_return_to_normal()

# Las reacciones no tocan a los espectadores: se le avisa al shader que paso
# y cada uno decide ahi que hacer segun su equipo y su personalidad, con un
# retardo propio (no reaccionan todos en el mismo cuadro).
const EVENTO_NORMAL := 0
const EVENTO_TENSION := 1
const EVENTO_GOL := 2
const EVENTO_FALLO := 3

func _set_evento(ev: int, equipo: int) -> void:
	if ev == _evento and equipo == _equipo_evento:
		return
	for m in _materiales:
		m.set_shader_parameter("evento_previo", _evento)
		m.set_shader_parameter("equipo_evento_previo", _equipo_evento)
		m.set_shader_parameter("evento", ev)
		m.set_shader_parameter("equipo_evento", equipo)
		m.set_shader_parameter("evento_inicio", _tiempo)
	_evento = ev
	_equipo_evento = equipo

## Celebración de Gol eufórica
func celebrate_goal(is_home_goal: bool = true, duration: float = 6.0) -> void:
	_is_reacting = true
	_return_timer = duration
	_set_evento(EVENTO_GOL, 0 if is_home_goal else 1)

## Reacción a penal atajado o desviado
func lament_miss(is_home_kicker: bool = true, duration: float = 4.5) -> void:
	_is_reacting = true
	_return_timer = duration
	_set_evento(EVENTO_FALLO, 0 if is_home_kicker else 1)

## Tensión antes de patear el penal
func prepare_kick_tension() -> void:
	_is_reacting = false
	_set_evento(EVENTO_TENSION, 0)

## Volver al estado normal de cánticos e hinchada de tribuna
func _return_to_normal() -> void:
	_is_reacting = false
	_set_evento(EVENTO_NORMAL, 0)
