@tool
class_name CrowdSection
extends Node3D

## CrowdSection: una tribuna paramétrica. VOS le decís qué parte es tribuna.
##
## El nodo marca la PRIMERA FILA (la más baja y cercana a la cancha):
## - Eje local X = a lo ancho (los asientos de la fila).
## - Eje local +Z = hacia atrás/subiendo (las filas siguientes).
## - Eje local Y = arriba.
## Rotá el nodo para orientar la grada. La posición del nodo es el centro
## de la primera fila. La escala del nodo se IGNORA a propósito: todo se
## maneja con seat_spacing / row_spacing / row_height (así mover y escalar
## nunca pelean entre sí).
##
## Controles:
## - Distancia entre espectadores: seat_spacing (lateral) y row_spacing
##   (profundidad entre filas).
## - Altura: posición Y del nodo + row_height por fila.
## - Escalonado o plano: row_height > 0 = escalonado, row_height = 0 = plano.
## - Patrón: density (cuántos asientos existen), jitter (desorden),
##   y la seed global del manager (generation_seed).
## - De pie o sentados: standing_rows (primeras N filas siempre de pie)
##   + sitting_ratio para el resto.
##
## Todo cambio (mover, rotar o tocar un parámetro) repuebla la hinchada
## en el editor automáticamente. El color de la caja = color del equipo.

enum Team { LOCAL = 0, VISITANTE = 1, NEUTRAL = 2, MIXTO = 3 }

## Ya no se usa: el nivel de detalle ahora se elige solo segun la distancia
## a la camara (ver CrowdManager, grupo Rendimiento). Queda para no romper
## las escenas guardadas.
enum Detail { ALTA = 0, BAJA = 1 }

## Como se comporta la gente de esta tribuna (que mezcla de personalidades).
## AUTO = general, con zonas de barra y de platea que arma el manager solo.
## PLATEA = tranquilos y sentados. POPULAR = fanaticos de pie que saltan.
enum Estilo { AUTO = 0, PLATEA = 1, GENERAL = 2, POPULAR = 3 }

@export var section_name: String = "Tribuna":
	set(val):
		section_name = val
		_update_viz_name()

@export var team: Team = Team.MIXTO:
	set(val):
		team = val
		_after_change()

@export var estilo: Estilo = Estilo.AUTO:
	set(val):
		estilo = val
		_after_change()

## Obsoleto (ver arriba).
@export var detail: Detail = Detail.BAJA

@export_group("Grilla")
## Cantidad de filas (hacia atrás/subiendo, eje local +Z).
@export var rows: int = 40:
	set(val):
		rows = maxi(val, 1)
		_after_change()

## Asientos por fila (a lo ancho, eje local X).
@export var seats_per_row: int = 100:
	set(val):
		seats_per_row = maxi(val, 1)
		_after_change()

## Distancia lateral entre espectadores (m).
@export var seat_spacing: float = 0.76:
	set(val):
		seat_spacing = maxf(val, 0.2)
		_after_change()

## Profundidad entre una fila y la siguiente (m).
@export var row_spacing: float = 1.15:
	set(val):
		row_spacing = maxf(val, 0.2)
		_after_change()

## Escalón: cuánto sube cada fila (m). 0 = tribuna plana.
@export var row_height: float = 0.4:
	set(val):
		row_height = maxf(val, 0.0)
		_after_change()

## 0..1: probabilidad de que cada asiento exista. Menos de 1 rompe el
## patrón perfecto de grilla (pasillos, huecos, bandejas).
@export_range(0.05, 1.0, 0.05) var density: float = 0.6:
	set(val):
		density = clampf(val, 0.05, 1.0)
		_after_change()

## Desplazamiento aleatorio por espectador (m). 0 = formación militar.
@export var jitter: float = 0.08:
	set(val):
		jitter = maxf(val, 0.0)
		_after_change()

@export_group("Curva")
## Dobla la seccion en arco, para las esquinas del estadio. 0 = recta.
## Positivo = el arco abraza la cancha (lo normal en una esquina): 90 es un
## cuarto de vuelta. Negativo = curva hacia afuera.
## El ancho de la primera fila sigue siendo seats_per_row x seat_spacing; las
## filas de atras son mas largas (o mas cortas si es negativo) y llevan mas
## gente. El nodo queda en el medio de la primera fila, igual que siempre.
@export_range(-180.0, 180.0, 1.0) var curva_grados: float = 0.0:
	set(val):
		curva_grados = clampf(val, -180.0, 180.0)
		_after_change()

@export_group("Comportamiento")
## Primeras N filas siempre de pie (ej: la popular abajo).
@export var standing_rows: int = 0:
	set(val):
		standing_rows = maxi(val, 0)
		_after_change()

## Del resto de filas: probabilidad de anim sentada.
## 0.0 = todos de pie, 1.0 = platea sentada.
@export_range(0.0, 1.0, 0.05) var sitting_ratio: float = 0.65:
	set(val):
		sitting_ratio = clampf(val, 0.0, 1.0)
		_after_change()

@export var enabled: bool = true:
	set(val):
		enabled = val
		_after_change()

@export var debug_visible: bool = true:
	set(val):
		debug_visible = val
		_refresh_viz()

var _viz: MeshInstance3D
var _viz_mat: StandardMaterial3D
var _viz_caja: BoxMesh

func _ready() -> void:
	_build_viz()
	_refresh_viz()
	if Engine.is_editor_hint():
		set_notify_transform(true)

func _notification(what: int) -> void:
	# Mover o rotar el nodo en el viewport repuebla solo (con debounce
	# de 1 frame en el manager, para no regenerar 60 veces por arrastre).
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint():
		_request_repopulate()

func _after_change() -> void:
	_refresh_viz()
	_request_repopulate()

func _request_repopulate() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var m := get_parent()
	if m != null and m.has_method("request_crowd_refresh"):
		m.request_crowd_refresh()

func es_curva() -> bool:
	return absf(curva_grados) >= 1.0

## Radio de la primera fila cuando la seccion es curva.
func radio_curva() -> float:
	return float(seats_per_row) * seat_spacing / deg_to_rad(absf(curva_grados))

## Punto de la curva: fila `r` (puede tener decimales) y `t` de -0.5 a 0.5 a lo
## ancho. Devuelve [posicion local, hacia donde mira].
func punto_curva(r: float, t: float) -> Array:
	var r0 := radio_curva()
	var ang := deg_to_rad(absf(curva_grados)) * t
	if curva_grados > 0.0:
		# El centro del arco esta adelante (hacia la cancha).
		var radio := r0 + r * row_spacing
		return [Vector3(sin(ang) * radio, r * row_height, cos(ang) * radio - r0),
				Vector3(-sin(ang), 0.0, -cos(ang))]
	# El centro esta atras: las filas se van cerrando.
	var radio := maxf(r0 - r * row_spacing, 0.0)
	return [Vector3(sin(ang) * radio, r * row_height, r0 - cos(ang) * radio),
			Vector3(sin(ang), 0.0, -cos(ang))]

## Genera los asientos LOCALES (origen = centro de primera fila).
## Devuelve Array de {pos: Vector3, row: int} y, en las secciones curvas,
## tambien {frente: Vector3} (hacia donde mira ese asiento). Llamado por el
## manager con su RNG global para que el patrón sea determinista dada la seed.
func generate_entries(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not enabled or rows < 1 or seats_per_row < 1:
		return out
	var curva := es_curva()
	for r in range(rows):
		var asientos := seats_per_row
		if curva:
			var radio := radio_curva() + float(r) * row_spacing * signf(curva_grados)
			if radio < seat_spacing:
				break
			asientos = maxi(int(round(deg_to_rad(absf(curva_grados)) * radio / seat_spacing)), 1)
		for c in range(asientos):
			if rng.randf() > density:
				continue
			var e := {"row": r}
			var pos: Vector3
			if curva:
				var pc := punto_curva(float(r), (float(c) + 0.5) / float(asientos) - 0.5)
				pos = pc[0]
				e["frente"] = pc[1]
			else:
				pos = Vector3((float(c) - float(seats_per_row - 1) * 0.5) * seat_spacing,
						float(r) * row_height, float(r) * row_spacing)
			if jitter > 0.0:
				pos.x += rng.randf_range(-jitter, jitter)
				pos.z += rng.randf_range(-jitter, jitter)
				pos.y += rng.randf_range(-jitter * 0.5, jitter * 0.5)
			e["pos"] = pos
			out.append(e)
	return out

func _build_viz() -> void:
	if _viz and is_instance_valid(_viz):
		return
	_viz = MeshInstance3D.new()
	_viz.name = "SectionViz"
	_viz_caja = BoxMesh.new()
	_viz.mesh = _viz_caja
	_viz_mat = StandardMaterial3D.new()
	_viz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_viz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_viz_mat.no_depth_test = false
	_viz_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_viz_caja.surface_set_material(0, _viz_mat)
	_viz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_viz, false, Node.INTERNAL_MODE_FRONT)
	_update_viz_name()

func _update_viz_name() -> void:
	if _viz and is_instance_valid(_viz):
		_viz.name = "SectionViz"

func _refresh_viz() -> void:
	if not is_inside_tree():
		return
	_build_viz()
	# La caja encierra la grilla generada + ~1.9m de cuerpo por encima.
	var w := float(seats_per_row) * seat_spacing
	var d := float(maxi(rows - 1, 0)) * row_spacing
	var h := float(maxi(rows - 1, 0)) * row_height + 1.9
	if es_curva():
		_viz.mesh = _malla_curva()
		_viz.position = Vector3.ZERO
	else:
		_viz_caja.size = Vector3(maxf(w, 0.5), maxf(h, 0.5), maxf(d, 0.5))
		_viz.mesh = _viz_caja
		_viz.position = Vector3(0.0, (h - 1.9) * 0.5 + 0.95, d * 0.5)
	var col := _team_color()
	_viz_mat.albedo_color = Color(col.r, col.g, col.b, 0.13)
	_viz_mat.emission_enabled = true
	_viz_mat.emission = col
	_viz_mat.emission_energy_multiplier = 0.35
	# La caja solo existe en el editor: en juego se oculta (el manager
	# la lee en runtime igual).
	_viz.visible = debug_visible and Engine.is_editor_hint()

## Guia de editor para las secciones curvas: el piso de la tribuna (abanico
## inclinado) y otro igual a la altura de las cabezas.
func _malla_curva() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pasos := maxi(int(absf(curva_grados) / 6.0), 2)
	var ultima := float(maxi(rows - 1, 0))
	for alto: float in [0.05, 1.9]:
		for i in pasos:
			var t0 := float(i) / float(pasos) - 0.5
			var t1 := float(i + 1) / float(pasos) - 0.5
			var a: Vector3 = punto_curva(0.0, t0)[0] + Vector3.UP * alto
			var b: Vector3 = punto_curva(0.0, t1)[0] + Vector3.UP * alto
			var c: Vector3 = punto_curva(ultima, t0)[0] + Vector3.UP * alto
			var d: Vector3 = punto_curva(ultima, t1)[0] + Vector3.UP * alto
			for v: Vector3 in [a, b, c, b, d, c]:
				st.add_vertex(v)
	var m := st.commit()
	m.surface_set_material(0, _viz_mat)
	return m

func _team_color() -> Color:
	match team:
		Team.LOCAL:
			return Color(0.85, 0.15, 0.15)
		Team.VISITANTE:
			return Color(0.15, 0.35, 0.90)
		Team.NEUTRAL:
			return Color(0.85, 0.85, 0.85)
		_:
			return Color(0.95, 0.80, 0.20)
