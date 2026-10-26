extends SceneTree

## Pasa animaciones exportadas desde Blender al esqueleto del arquero.
##
## Problema: Blender reorienta los ejes de cada hueso al importar el FBX y
## exporta en metros (el juego esta en cm), asi que las rotaciones no se pueden
## copiar tal cual.
##
## Solucion: CALIBRAR con un par conocido (la misma animacion en el juego y
## exportada desde Blender). Para la misma pose fisica vale, en cada hueso:
##     rot_juego = R * rot_blender * C_hueso
## donde R alinea los dos espacios y C_hueso es la conversion fija entre los
## ejes de ese hueso en Blender y en el juego. C no depende de la pose: si la
## calibracion es correcta, sale igual en todos los cuadros (eso se verifica).
## Una vez calibrado, sirve para cualquier animacion exportada del mismo rig.
##
## Uso:
##   MODO=calibrar  FBX=res://...ida_y_vuelta.fbx ORIG=Goalkeeperdivingsave
##   MODO=convertir FBX=res://...nueva.fbx OUT=res://...nueva.res

const FPS := 30.0
const CALIB := "res://tools/calibracion_blender.json"


func _buscar(n: Node, tipo: String) -> Node:
	if n.is_class(tipo):
		return n
	for c in n.get_children():
		var r = _buscar(c, tipo)
		if r:
			return r
	return null


func _mapa_pistas(an: Animation) -> Dictionary:
	var m := {}
	for i in an.get_track_count():
		var hueso := String(an.track_get_path(i)).get_slice(":", 1)
		if not m.has(hueso):
			m[hueso] = {}
		match an.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				m[hueso]["rot"] = i
			Animation.TYPE_POSITION_3D:
				m[hueso]["pos"] = i
	return m


func _orden(esq: Skeleton3D) -> Array:
	var orden := []
	var pend := []
	for b in esq.get_bone_count():
		if esq.get_bone_parent(b) < 0:
			pend.append(b)
	while not pend.is_empty():
		var b = pend.pop_front()
		orden.append(b)
		for h in esq.get_bone_children(b):
			pend.append(h)
	return orden


func _globales(esq: Skeleton3D, an: Animation, mapa: Dictionary, orden: Array, t: float) -> Array:
	var G := []
	G.resize(esq.get_bone_count())
	for b in orden:
		var rest := esq.get_bone_rest(b)
		var rot := rest.basis.get_rotation_quaternion()
		var pos := rest.origin
		var p: Dictionary = mapa.get(esq.get_bone_name(b), {})
		if p.has("rot"):
			rot = an.rotation_track_interpolate(p["rot"], t)
		if p.has("pos"):
			pos = an.position_track_interpolate(p["pos"], t)
		var local := Transform3D(Basis(rot.normalized()), pos)
		var padre := esq.get_bone_parent(b)
		G[b] = local if padre < 0 else (G[padre] as Transform3D) * local
	return G


func _q(G: Array, b: int) -> Quaternion:
	return (G[b] as Transform3D).basis.get_rotation_quaternion()


func _p(G: Array, b: int) -> Vector3:
	return (G[b] as Transform3D).origin


## Base del cuerpo armada con POSICIONES (manos, cadera, cabeza): no depende de
## como esten orientados los ejes de cada hueso.
func _base_cuerpo(G: Array, li: int, ri: int, hi: int, he: int) -> Basis:
	var x := (_p(G, ri) - _p(G, li)).normalized()
	var y := _p(G, he) - _p(G, hi)
	y = (y - x * x.dot(y)).normalized()
	return Basis(x, y, x.cross(y))


func _q2a(q: Quaternion) -> Array:
	return [q.x, q.y, q.z, q.w]


func _a2q(a: Array) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3])


func _initialize() -> void:
	var modo := OS.get_environment("MODO")
	var g = load("res://scenes/game.tscn").instantiate()
	root.add_child(g)
	var esq_t: Skeleton3D = g.get_node("Goalkeeper/player/Node/Skeleton3D")
	var ap_t: AnimationPlayer = g.get_node("Goalkeeper/player/AnimationPlayer")
	var ord_t := _orden(esq_t)

	var f = load(OS.get_environment("FBX")).instantiate()
	root.add_child(f)
	var esq_s: Skeleton3D = _buscar(f, "Skeleton3D")
	var ap_s: AnimationPlayer = _buscar(f, "AnimationPlayer")
	var an_s: Animation = ap_s.get_animation(ap_s.get_animation_list()[0])
	var ord_s := _orden(esq_s)
	var map_s := _mapa_pistas(an_s)

	var par := {}
	for bt in esq_t.get_bone_count():
		var bs := esq_s.find_bone(esq_t.get_bone_name(bt).replace("mixamorig1", "mixamorig1_"))
		if bs >= 0:
			par[bt] = bs
	var hips_t := esq_t.find_bone("mixamorig1Hips")
	var hips_s := esq_s.find_bone("mixamorig1_Hips")

	if modo == "calibrar":
		_calibrar(esq_t, ap_t, ord_t, esq_s, an_s, ord_s, map_s, par, hips_t, hips_s)
	else:
		_convertir(esq_t, ord_t, esq_s, an_s, ord_s, map_s, par, hips_s)
	quit()


func _calibrar(esq_t, ap_t, ord_t, esq_s, an_s, ord_s, map_s, par, hips_t, hips_s) -> void:
	var an_o: Animation = ap_t.get_animation(OS.get_environment("ORIG"))
	var map_o := _mapa_pistas(an_o)
	var Gs0 := _globales(esq_s, an_s, map_s, ord_s, 0.0)
	var Gt0 := _globales(esq_t, an_o, map_o, ord_t, 0.0)
	var Bs := _base_cuerpo(Gs0, esq_s.find_bone("mixamorig1_LeftHand"), esq_s.find_bone("mixamorig1_RightHand"), hips_s, esq_s.find_bone("mixamorig1_Head"))
	var Bt := _base_cuerpo(Gt0, esq_t.find_bone("mixamorig1LeftHand"), esq_t.find_bone("mixamorig1RightHand"), hips_t, esq_t.find_bone("mixamorig1Head"))
	var R := (Bt * Bs.inverse()).get_rotation_quaternion()

	# escala por largo de huesos: no depende de la postura
	var suma := 0.0
	var cant := 0
	for bt in par:
		var lt: float = esq_t.get_bone_rest(bt).origin.length()
		var ls: float = esq_s.get_bone_rest(par[bt]).origin.length()
		if esq_t.get_bone_parent(bt) >= 0 and ls > 1e-6 and lt > 1e-6:
			suma += lt / ls
			cant += 1
	var k := suma / cant
	var off := _p(Gt0, hips_t) - R * (_p(Gs0, hips_s) * k)

	# C por hueso en el cuadro 0, y control de que sea constante en todos
	var C := {}
	for bt in par:
		C[bt] = ((R * _q(Gs0, par[bt])).inverse() * _q(Gt0, bt)).normalized()
	var peor := 0.0
	var peor_hueso := ""
	var n := int(round(min(an_s.length, an_o.length) * FPS))
	for c in range(1, n + 1, 3):
		var t := c / FPS
		var Gs := _globales(esq_s, an_s, map_s, ord_s, t)
		var Gt := _globales(esq_t, an_o, map_o, ord_t, t)
		for bt in par:
			var Ct := ((R * _q(Gs, par[bt])).inverse() * _q(Gt, bt)).normalized()
			var ang := rad_to_deg(Ct.angle_to(C[bt]))
			if ang > peor:
				peor = ang
				peor_hueso = "%s (t=%.2f)" % [esq_t.get_bone_name(bt), t]
	print("escala Blender->juego: %.3f" % k)
	print("CONSISTENCIA de C: desvio maximo %.4f grados en %s" % [peor, peor_hueso])

	var datos := {"R": _q2a(R), "k": k, "off": [off.x, off.y, off.z], "C": {}}
	for bt in C:
		datos["C"][esq_t.get_bone_name(bt)] = _q2a(C[bt])
	var fa := FileAccess.open(CALIB, FileAccess.WRITE)
	fa.store_string(JSON.stringify(datos, "  "))
	fa.close()
	print("calibracion guardada en ", CALIB)


func _convertir(esq_t, ord_t, esq_s, an_s, ord_s, map_s, par, hips_s) -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CALIB))
	var R := _a2q(d["R"])
	var k: float = d["k"]
	var off := Vector3(d["off"][0], d["off"][1], d["off"][2])

	var sal := Animation.new()
	sal.length = an_s.length
	var pos_i := sal.add_track(Animation.TYPE_POSITION_3D)
	sal.track_set_path(pos_i, NodePath("Node/Skeleton3D:mixamorig1Hips"))
	var pista := {}
	for bt in ord_t:
		if not par.has(bt) or not d["C"].has(esq_t.get_bone_name(bt)):
			continue
		var i := sal.add_track(Animation.TYPE_ROTATION_3D)
		sal.track_set_path(i, NodePath("Node/Skeleton3D:" + esq_t.get_bone_name(bt)))
		pista[bt] = i

	var previa := {}
	var n := int(round(an_s.length * FPS))
	for c in n + 1:
		var t: float = min(c / FPS, an_s.length)
		var Gs := _globales(esq_s, an_s, map_s, ord_s, t)
		var Grot := {}
		for bt in pista:
			Grot[bt] = (R * _q(Gs, par[bt]) * _a2q(d["C"][esq_t.get_bone_name(bt)])).normalized()
		for bt in ord_t:
			if not pista.has(bt):
				continue
			var padre: int = esq_t.get_bone_parent(bt)
			var q: Quaternion = Grot[bt]
			if padre >= 0 and Grot.has(padre):
				q = (Grot[padre] as Quaternion).inverse() * q
			q = q.normalized()
			if previa.has(bt) and (previa[bt] as Quaternion).dot(q) < 0.0:
				q = -q  # continuidad: evitar saltos de signo entre cuadros
			previa[bt] = q
			sal.rotation_track_insert_key(pista[bt], t, q)
		sal.position_track_insert_key(pos_i, t, off + R * (_p(Gs, hips_s) * k))

	var err := ResourceSaver.save(sal, OS.get_environment("OUT"))
	print("convertida: %s (%d cuadros, %.2fs) %s" % [OS.get_environment("OUT"), n + 1, sal.length, "OK" if err == OK else "ERROR"])
