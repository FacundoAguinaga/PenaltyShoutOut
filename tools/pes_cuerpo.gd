extends RefCounted

## Calcula la pose de un clip a mano (sin AnimationPlayer) y donde queda la malla
## del personaje, no solo sus huesos: un cuerpo acostado se apoya en la espalda,
## 10-15 cm debajo del hueso.

const ESCALA := 0.01
const DIRECCIONES := [
	Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK,
	Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(1, -1, -1),
	Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, 1), Vector3(-1, -1, -1),
]

var sk: Skeleton3D
var _alto_sk: float
var _orden: Array[int] = []
var _nombres: PackedStringArray = []
var _padre: PackedInt32Array = []
var _origen: PackedVector3Array = []
## Por hueso (indice en _orden): los puntos extremos de su parte de la malla.
var _nube: Array[PackedVector3Array] = []
var _pistas := {}

func _init(esqueleto: Skeleton3D) -> void:
	sk = esqueleto
	_alto_sk = sk.global_transform.origin.y
	var puntos := _leer_malla()
	# Solo los huesos con malla y sus ancestros, de padres a hijos.
	var usados := {}
	for b: int in puntos:
		var h := b
		while h >= 0 and not usados.has(h):
			usados[h] = true
			h = sk.get_bone_parent(h)
	var indice := {}
	for b in sk.get_bone_count():
		if usados.has(b):
			indice[b] = _orden.size()
			_orden.append(b)
			_nombres.append(sk.get_bone_name(b))
			_padre.append(indice.get(sk.get_bone_parent(b), -1))
			_origen.append(sk.get_bone_rest(b).origin)
			_nube.append(_extremos(puntos.get(b, PackedVector3Array())))

## Vertices de la malla en el espacio del hueso que mas los mueve.
func _leer_malla() -> Dictionary:
	var salida := {}
	for nodo in sk.find_children("*", "MeshInstance3D", false, false):
		var mi: MeshInstance3D = nodo
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var k: int = bs.size() / vs.size()
			for i in vs.size():
				if ws[i * k] < 0.5:
					continue
				var bind := bs[i * k]
				var b := mi.skin.get_bind_bone(bind)
				if b < 0:
					b = sk.find_bone(mi.skin.get_bind_name(bind))
				if not salida.has(b):
					salida[b] = PackedVector3Array()
				var lista: PackedVector3Array = salida[b]
				lista.append(mi.skin.get_bind_pose(bind) * vs[i])
				salida[b] = lista
	return salida

func _extremos(puntos: PackedVector3Array) -> PackedVector3Array:
	var salida := PackedVector3Array()
	if puntos.is_empty():
		return salida
	for d: Vector3 in DIRECCIONES:
		var mejor := puntos[0]
		var mejor_v := -INF
		for p in puntos:
			var v := d.dot(p)
			if v > mejor_v:
				mejor_v = v
				mejor = p
		if not salida.has(mejor):
			salida.append(mejor)
	return salida

## Los puntos extremos por hueso, para guardar en datos.json (ver scripts/pes_piso.gd).
func nubes() -> Dictionary:
	var d := {}
	for i in _orden.size():
		if _nube[i].is_empty():
			continue
		var puntos := []
		for p in _nube[i]:
			puntos.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01)])
		d[_nombres[i]] = puntos
	return d

func _pistas_de(a: Animation) -> Dictionary:
	if _pistas.has(a):
		return _pistas[a]
	var rot := PackedInt32Array()
	var pos := PackedInt32Array()
	for n in _nombres:
		rot.append(a.find_track("Node/Skeleton3D:" + n, Animation.TYPE_ROTATION_3D))
		pos.append(a.find_track("Node/Skeleton3D:" + n, Animation.TYPE_POSITION_3D))
	var d := {"rot": rot, "pos": pos}
	_pistas[a] = d
	return d

## Altura del punto mas bajo de la malla en el momento t, en metros sobre el piso.
## {y, hueso}
func lo_mas_bajo(a: Animation, t: float) -> Dictionary:
	var p := _pistas_de(a)
	var rot: PackedInt32Array = p["rot"]
	var pos: PackedInt32Array = p["pos"]
	var globales: Array[Transform3D] = []
	globales.resize(_orden.size())
	var min_y := INF
	var hueso := -1
	for i in _orden.size():
		var o := a.position_track_interpolate(pos[i], t) if pos[i] >= 0 else _origen[i]
		var q := a.rotation_track_interpolate(rot[i], t) if rot[i] >= 0 else Quaternion(sk.get_bone_rest(_orden[i]).basis.orthonormalized())
		var local := Transform3D(Basis(q), o)
		var g := globales[_padre[i]] * local if _padre[i] >= 0 else local
		globales[i] = g
		var fila := Vector3(g.basis.x.y, g.basis.y.y, g.basis.z.y)
		for punto in _nube[i]:
			var y := fila.dot(punto) + g.origin.y
			if y < min_y:
				min_y = y
				hueso = i
	return {"y": min_y * ESCALA + _alto_sk, "hueso": _nombres[hueso].trim_prefix("mixamorig1")}

## Cuanto subir la cadera en cada cuadro para que la malla no atraviese el piso.
## Se ensancha y se suaviza para que el cuerpo suba de a poco antes de apoyarse y
## no salte; un cuerpo en el aire no se toca porque no le falta nada.
func levante(a: Animation, fps: float, margen: float, ventana: int) -> PackedFloat32Array:
	var n := roundi(a.length * fps) + 1
	var falta := PackedFloat32Array()
	falta.resize(n)
	for f in n:
		falta[f] = maxf(0.0, margen - float(lo_mas_bajo(a, f / fps)["y"]))
	var ancho := PackedFloat32Array()
	ancho.resize(n)
	for f in n:
		var m := 0.0
		for g in range(maxi(f - ventana, 0), mini(f + ventana + 1, n)):
			m = maxf(m, falta[g])
		ancho[f] = m
	var suave := PackedFloat32Array()
	suave.resize(n)
	for f in n:
		var s := 0.0
		for g in range(f - ventana, f + ventana + 1):
			s += ancho[clampi(g, 0, n - 1)]
		suave[f] = s / (2 * ventana + 1)
	return suave

## Lo mismo pero con la pose que tiene ahora el esqueleto (fundidos incluidos).
func lo_mas_bajo_ahora() -> Dictionary:
	var min_y := INF
	var hueso := -1
	for i in _orden.size():
		var g := sk.get_bone_global_pose(_orden[i])
		var fila := Vector3(g.basis.x.y, g.basis.y.y, g.basis.z.y)
		for punto in _nube[i]:
			var y := fila.dot(punto) + g.origin.y
			if y < min_y:
				min_y = y
				hueso = i
	return {"y": min_y * ESCALA + sk.global_transform.origin.y, "hueso": _nombres[hueso].trim_prefix("mixamorig1")}
