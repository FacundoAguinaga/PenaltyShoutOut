extends SceneTree

## Reconstruye el modelo del estadio para que Godot lo pueda dibujar barato.
##
## El stadium.glb viene de Sketchfab partido en 186 mallas de ~47k triangulos,
## cortadas por limite de vertices y no por zona: cada pedazo ocupa el estadio
## entero. Con eso Godot no puede descartar lo que queda fuera de camara ni
## bajar el detalle con la distancia (el LOD se elige por el tamano en pantalla
## de la caja de la malla, y una caja de 200 m siempre esta "cerca").
##
## Esta herramienta junta todos los triangulos por material y los vuelve a
## cortar en una grilla de BLOQUE metros en el plano XZ. Cada bloque es una
## malla con una superficie por material y con LODs generados. El resultado
## se guarda en SALIDA y stadium.tscn lo usa en vez del glb.
##
## Uso (tarda un par de minutos):
##   godot --headless --path . -s res://tools/optimizar_estadio.gd
##
## Si cambia stadium.glb hay que volver a correrla.

const ENTRADA := "res://assets/models/stadium.glb"
const SALIDA := "res://assets/models/stadium_optimizado.scn"
## Lado de cada bloque de la grilla, en metros.
const BLOQUE := 30.0
## Un material con menos triangulos que esto dentro de un bloque no merece su
## propio draw call: se lo junta con los vecinos en un bloque GRUESO veces mas
## grande.
const MIN_TRIS_POR_SUPERFICIE := 4000
const GRUESO := 3
## Opcional, apagado: que lo que este por encima de ALTURA_TECHO proyecte
## sombra con una copia simplificada que no se ve (FRACCION_SOMBRA de sus
## triangulos). Probado: con el techo solo casi no cambia nada, y con todo el
## estadio al 5% cuesta ~2 ms y la simplificacion deja manchas en las
## tribunas. 0 = sin sombra.
const ALTURA_TECHO := 23.0
const FRACCION_SOMBRA := 0.0
## Nodos del glb que en stadium.tscn estan ocultos y no hay que copiar.
const EXCLUIR := ["StadiumCrowd"]
## La red fija que trae el modelo en el arco del penal: ahi se dibuja la de
## scripts/red_arco.gd, y juntas se ven dos redes. Esta caja (en coordenadas del
## modelo) solo deja afuera la de ese arco: la del otro lado se queda.
const RED_FIJA_MATERIALES := ["auto_37", "auto_38"]
const RED_FIJA_CAJA := AABB(Vector3(-5.0, -1.0, -2.0), Vector3(10.0, 5.0, 6.0))

var _raiz: Node3D
var _listo := false

func _initialize() -> void:
	_raiz = load(ENTRADA).instantiate()
	get_root().add_child(_raiz)

func _process(_delta: float) -> bool:
	# Se espera un frame para que las transformaciones globales esten listas.
	if _listo:
		return true
	_listo = true
	_procesar()
	quit()
	return false

func _procesar() -> void:
	var t0 := Time.get_ticks_msec()
	# bloques[Vector2i] = {material: [pedazos]}
	var bloques := {}
	# sombras[Vector2i] = [PackedVector3Array] con los triangulos del techo
	var sombras := {}
	var tris_entrada := 0

	for mi: MeshInstance3D in _raiz.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not mi.is_visible_in_tree() or _excluido(mi):
			continue
		var xf: Transform3D = _raiz.global_transform.affine_inverse() * mi.global_transform
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(s)
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			tris_entrada += _repartir(arrays, xf, mat, bloques, sombras)

	bloques = _agrupar_chicos(bloques)
	print("Entrada: %d triangulos. Armando %d bloques..." % [tris_entrada, bloques.size()])

	var salida := Node3D.new()
	salida.name = "EstadioOptimizado"
	var tris_salida := 0
	var superficies := 0
	for clave: Vector3i in bloques:
		var por_material: Dictionary = bloques[clave]
		var im := ImporterMesh.new()
		for mat in por_material:
			var arr := _juntar(por_material[mat])
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mat)
			tris_salida += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			superficies += 1
		im.generate_lods(60.0, 25.0, [])
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "Bloque_%s%d_%d" % ["G" if clave.z == 1 else "", clave.x, clave.y]
		mesh_inst.mesh = im.get_mesh()
		# El estadio no proyecta sombras: los focos estan arriba de las
		# tribunas, asi que su sombra cae sobre la misma tribuna y casi no se
		# nota, pero cada foco con sombra tendria que volver a dibujarlo
		# entero. Recibir sombras (las de los jugadores en el pasto) sigue
		# funcionando.
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		salida.add_child(mesh_inst)
		mesh_inst.owner = salida

	var tris_sombra := 0
	for clave: Vector2i in sombras:
		var sombra := _malla_de_sombra(sombras[clave])
		if sombra == null:
			continue
		tris_sombra += sombra.surface_get_array_index_len(0) / 3
		var inst := MeshInstance3D.new()
		inst.name = "SombraTecho_%d_%d" % [clave.x, clave.y]
		inst.mesh = sombra
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		salida.add_child(inst)
		inst.owner = salida
	if FRACCION_SOMBRA > 0.0:
		print("Sombra del techo: %d triangulos en %d bloques" % [tris_sombra, sombras.size()])

	var escena := PackedScene.new()
	var err := escena.pack(salida)
	if err == OK:
		err = ResourceSaver.save(escena, SALIDA)
	print("Salida: %d bloques, %d superficies, %d triangulos (en LOD 0). Guardado en %s (%s). %.1f s" % [
		bloques.size(), superficies, tris_salida, SALIDA, error_string(err), (Time.get_ticks_msec() - t0) / 1000.0])

func _excluido(n: Node) -> bool:
	while n and n != _raiz:
		if String(n.name) in EXCLUIR:
			return true
		n = n.get_parent()
	return false

## Pasa a bloques gruesos los materiales que en su bloque fino tienen pocos
## triangulos. Devuelve {Vector3i(x, z, grueso 0/1): {material: [pedazos]}}.
func _agrupar_chicos(finos: Dictionary) -> Dictionary:
	var salida := {}
	for clave: Vector2i in finos:
		for mat in finos[clave]:
			var pedazos: Array = finos[clave][mat]
			var tris := 0
			for p: Dictionary in pedazos:
				tris += (p["i"] as PackedInt32Array).size() / 3
			var destino := Vector3i(clave.x, clave.y, 0)
			if tris < MIN_TRIS_POR_SUPERFICIE:
				destino = Vector3i(floori(clave.x / float(GRUESO)), floori(clave.y / float(GRUESO)), 1)
			if not salida.has(destino):
				salida[destino] = {}
			if not salida[destino].has(mat):
				salida[destino][mat] = []
			salida[destino][mat].append_array(pedazos)
	return salida

## Reparte los triangulos de una superficie entre los bloques de la grilla,
## pasando los vertices a coordenadas del estadio. Cada bloque recibe un
## pedazo (con sus propios vertices) que despues se junta con los demas
## pedazos del mismo material. Devuelve cuantos triangulos habia.
##
## Todo se arma en arreglos locales: un PackedArray guardado en un diccionario
## se copia entero cada vez que se escribe un elemento.
func _repartir(arrays: Array, xf: Transform3D, mat: Material, bloques: Dictionary, sombras: Dictionary) -> int:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var t: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx = PackedInt32Array(range(v.size()))
	var nb := xf.basis.inverse().transposed()
	var tb := xf.basis

	var vw := PackedVector3Array()
	vw.resize(v.size())
	for k in v.size():
		vw[k] = xf * v[k]

	# Triangulos de cada bloque (Array es por referencia: append no copia).
	var por_bloque := {}
	for k in range(0, idx.size(), 3):
		var centro := (vw[idx[k]] + vw[idx[k + 1]] + vw[idx[k + 2]]) / 3.0
		if mat and mat.resource_name in RED_FIJA_MATERIALES and RED_FIJA_CAJA.has_point(centro):
			continue
		var clave := Vector2i(floori(centro.x / BLOQUE), floori(centro.z / BLOQUE))
		if not por_bloque.has(clave):
			por_bloque[clave] = []
		por_bloque[clave].append(k)
		if FRACCION_SOMBRA > 0.0 and centro.y >= ALTURA_TECHO:
			if not sombras.has(clave):
				sombras[clave] = []
			var tri := PackedVector3Array([vw[idx[k]], vw[idx[k + 1]], vw[idx[k + 2]]])
			sombras[clave].append(tri)

	var remap := PackedInt32Array()
	remap.resize(v.size())
	for clave: Vector2i in por_bloque:
		remap.fill(-1)
		var pv := PackedVector3Array()
		var pn := PackedVector3Array()
		var pt := PackedFloat32Array()
		var puv := PackedVector2Array()
		var puv2 := PackedVector2Array()
		var pc := PackedColorArray()
		var pi := PackedInt32Array()
		for k: int in por_bloque[clave]:
			for j in 3:
				var vi := idx[k + j]
				var ni := remap[vi]
				if ni < 0:
					ni = pv.size()
					remap[vi] = ni
					pv.append(vw[vi])
					pn.append((nb * n[vi]).normalized() if not n.is_empty() else Vector3.UP)
					if not t.is_empty():
						var tv := (tb * Vector3(t[vi * 4], t[vi * 4 + 1], t[vi * 4 + 2])).normalized()
						pt.append(tv.x); pt.append(tv.y); pt.append(tv.z); pt.append(t[vi * 4 + 3])
					if not uv.is_empty(): puv.append(uv[vi])
					if not uv2.is_empty(): puv2.append(uv2[vi])
					if not c.is_empty(): pc.append(c[vi])
				pi.append(ni)
		var pedazo := {"v": pv, "n": pn, "i": pi}
		if not pt.is_empty(): pedazo["t"] = pt
		if not puv.is_empty(): pedazo["uv"] = puv
		if not puv2.is_empty(): pedazo["uv2"] = puv2
		if not pc.is_empty(): pedazo["c"] = pc
		if not bloques.has(clave):
			bloques[clave] = {}
		if not bloques[clave].has(mat):
			bloques[clave][mat] = []
		bloques[clave][mat].append(pedazo)
	return idx.size() / 3

## Arma la malla que solo proyecta la sombra del techo de un bloque: suelda
## los vertices repetidos (sin eso no se puede simplificar) y se queda con el
## nivel de detalle mas cercano a FRACCION_SOMBRA de los triangulos.
func _malla_de_sombra(tris: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var i := PackedInt32Array()
	var soldar := {}
	for tri: PackedVector3Array in tris:
		for p in tri:
			var clave := Vector3i((p * 100.0).round())
			if not soldar.has(clave):
				soldar[clave] = v.size()
				v.append(p)
			i.append(soldar[clave])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = i
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr)
	im.generate_lods(180.0, 180.0, [])
	var objetivo := int(i.size() * FRACCION_SOMBRA)
	var mejor := i
	for lod in im.get_surface_lod_count(0):
		var li := im.get_surface_lod_indices(0, lod)
		if absi(li.size() - objetivo) < absi(mejor.size() - objetivo):
			mejor = li
	if mejor.size() < 3:
		return null
	arr[Mesh.ARRAY_INDEX] = mejor
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

## Junta los pedazos de un mismo material y bloque en un solo juego de arrays.
func _juntar(pedazos: Array) -> Array:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var t := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	var todos_t := true
	var todos_uv := true
	var todos_uv2 := true
	var todos_c := true
	for p: Dictionary in pedazos:
		todos_t = todos_t and p.has("t")
		todos_uv = todos_uv and p.has("uv")
		todos_uv2 = todos_uv2 and p.has("uv2")
		todos_c = todos_c and p.has("c")
	for p: Dictionary in pedazos:
		var base := v.size()
		var pi: PackedInt32Array = p["i"]
		for k in pi.size():
			pi[k] += base
		i.append_array(pi)
		v.append_array(p["v"])
		n.append_array(p["n"])
		if todos_t: t.append_array(p["t"])
		if todos_uv: uv.append_array(p["uv"])
		if todos_uv2: uv2.append_array(p["uv2"])
		if todos_c: c.append_array(p["c"])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	if todos_t: arr[Mesh.ARRAY_TANGENT] = t
	if todos_uv: arr[Mesh.ARRAY_TEX_UV] = uv
	if todos_uv2: arr[Mesh.ARRAY_TEX_UV2] = uv2
	if todos_c: arr[Mesh.ARRAY_COLOR] = c
	arr[Mesh.ARRAY_INDEX] = i
	return arr
