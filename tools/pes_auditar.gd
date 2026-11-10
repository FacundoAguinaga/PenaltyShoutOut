extends SceneTree

## Mide donde queda de verdad cada animacion de PES, en el personaje del juego y
## con la raiz puesta como la pone el juego. No cambia nada.
##
## Por cada clip: lo mas bajo de la malla (negativo: atraviesa el piso), saltos de
## la cadera, en los remates donde queda el pie respecto de la pelota y en los
## empalmes cuanto salta el cuerpo. Escribe animaciones_pes/auditoria.json.
##   godot --headless --path . -s res://tools/pes_auditar.gd

const PesCuerpo := preload("res://tools/pes_cuerpo.gd")
const FPS := 30.0
const CADERA := "mixamorig1Hips"
const DEDO := "mixamorig1RightToeBase"
const PIE_APOYO := "mixamorig1LeftFoot"

var _hecho := false
var _juego: Node

func _initialize() -> void:
	_juego = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(_juego)

func _process(_d: float) -> bool:
	if _hecho:
		return true
	_hecho = true
	_auditar()
	quit()
	return false

func _pos(sk: Skeleton3D, hueso: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(hueso)).origin

func _pose(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	if ap.current_animation != anim:
		ap.play(anim)
		ap.pause()
	ap.seek(t, true)
	sk.force_update_all_bone_transforms()

## Recorre un tramo del clip: lo mas bajo de la malla y el mayor salto de la cadera.
func _recorrer(c: PesCuerpo, a: Animation, desde: float, hasta: float) -> Dictionary:
	var r := {"min_y": INF, "min_hueso": "", "min_t": 0.0, "salto": 0.0}
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var prev := Vector3.INF
	var f := roundi(desde * FPS)
	while f / FPS <= hasta + 0.001:
		var b := c.lo_mas_bajo(a, f / FPS)
		if b["y"] < r["min_y"]:
			r["min_y"] = b["y"]; r["min_hueso"] = b["hueso"]; r["min_t"] = f / FPS
		var p := a.position_track_interpolate(pista, f / FPS) * PesCuerpo.ESCALA
		if prev != Vector3.INF:
			r["salto"] = maxf(r["salto"], p.distance_to(prev))
		prev = p
		f += 1
	return r

func _auditar() -> void:
	var arquero: Node3D = _juego.get_node("Goalkeeper")
	var pateador: Node3D = _juego.get_node("Kicker")
	arquero.set_process(false); arquero.set_physics_process(false)
	pateador.set_process(false); pateador.set_physics_process(false)
	_juego.set_process(false); _juego.set_physics_process(false)
	pateador.global_transform = Transform3D.IDENTITY
	var datos := PesAnimaciones.datos()
	var cuerpo_a := PesCuerpo.new(arquero.skeleton)
	var cuerpo_p := PesCuerpo.new(pateador.skeleton)
	var salida := {
		"esperas": _esperas(arquero, cuerpo_a, datos["esperas_arquero"]) + _esperas(pateador, cuerpo_p, datos["esperas_pateador"]),
		"remates": _remates(pateador, cuerpo_p, datos["remates"]),
		"atajadas": _atajadas(arquero, cuerpo_a, datos["atajadas"]),
	}
	var f := FileAccess.open(PesAnimaciones.DIR + "auditoria.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(salida, " "))
	f.close()

func _esperas(quien: Node3D, c: PesCuerpo, nombres: Array) -> Array:
	var d := []
	for n: String in nombres:
		var a: Animation = quien.animation_player.get_animation("pes/" + n)
		var r := _recorrer(c, a, 0.0, a.length)
		r["anim"] = n
		d.append(r)
		print("espera %-30s malla min %+.3f (%s)" % [n, r["min_y"], r["min_hueso"]])
	return d

func _percentiles(v: Array, nombre: String) -> void:
	v.sort()
	if v.is_empty():
		return
	print("%-36s min %+.3f  p10 %+.3f  mediana %+.3f  p90 %+.3f  max %+.3f" % [nombre, v[0], v[v.size() / 10], v[v.size() / 2], v[v.size() * 9 / 10], v[-1]])

## El juego apoya la raiz en el piso y deja la pelota toe_to_ball delante del dedo.
func _remates(pateador: Node3D, c: PesCuerpo, remates: Array) -> Array:
	var ap: AnimationPlayer = pateador.animation_player
	var sk: Skeleton3D = pateador.skeleton
	var pelota: Vector3 = pateador.ball.global_position
	var salida := []
	for r: Dictionary in remates:
		var anim := "pes/" + str(r["anim"])
		var a := ap.get_animation(anim)
		var t: float = r["t"]
		var raiz: Vector3 = pelota - PesAnimaciones.v3(r["dedo"]) - Vector3(r["dir_pie"][0], 0.0, r["dir_pie"][2]).normalized() * pateador.toe_to_ball
		raiz.y = 0.0
		pateador.global_position = raiz
		_pose(ap, sk, anim, t)
		var dedo := _pos(sk, DEDO)
		var apoyo := _pos(sk, PIE_APOYO)
		var cerca := {"d": INF, "dt": 0.0}
		for f in range(roundi(t * FPS) - 4, roundi(t * FPS) + 5):
			_pose(ap, sk, anim, f / FPS)
			var d := _pos(sk, DEDO).distance_to(pelota)
			if d < cerca["d"]:
				cerca = {"d": d, "dt": f / FPS - t}
		_pose(ap, sk, anim, r["inicio"])
		var cadera := _pos(sk, CADERA)
		salida.append({
			"anim": r["anim"], "estilo": r["estilo"], "t": t,
			"dedo_y": dedo.y, "dedo_a_pelota": dedo.distance_to(pelota),
			"dedo_cerca": cerca["d"], "dedo_cerca_dt": cerca["dt"],
			"apoyo_x": apoyo.x - pelota.x, "apoyo_z": apoyo.z - pelota.z, "apoyo_y": apoyo.y,
			"cadera_inicio": [cadera.x, cadera.y, cadera.z],
			"carrera": _recorrer(c, a, r["inicio"], t),
			"despues": _recorrer(c, a, t, a.length),
		})
	pateador.global_position = Vector3.ZERO
	print("\n--- %d remates ---" % salida.size())
	_percentiles(salida.map(func(s): return s["dedo_a_pelota"]), "dedo-pelota en el golpe (m)")
	_percentiles(salida.map(func(s): return s["dedo_cerca"]), "dedo-pelota lo mas cerca (m)")
	_percentiles(salida.map(func(s): return s["dedo_cerca_dt"]), "ese momento - golpe (s)")
	_percentiles(salida.map(func(s): return s["dedo_y"]), "dedo y en el golpe")
	_percentiles(salida.map(func(s): return s["apoyo_x"]), "pie de apoyo x respecto pelota")
	_percentiles(salida.map(func(s): return s["apoyo_z"]), "pie de apoyo z respecto pelota")
	_percentiles(salida.map(func(s): return s["apoyo_y"]), "pie de apoyo y")
	_percentiles(salida.map(func(s): return s["carrera"]["min_y"]), "malla min en la carrera")
	_percentiles(salida.map(func(s): return s["despues"]["min_y"]), "malla min despues del golpe")
	# Todos los remates de un estilo deberian arrancar del mismo lugar.
	var por_estilo := {}
	for s: Dictionary in salida:
		if not por_estilo.has(s["estilo"]):
			por_estilo[s["estilo"]] = []
		por_estilo[s["estilo"]].append(PesAnimaciones.v3(s["cadera_inicio"]))
	for e: String in por_estilo:
		var lista: Array = por_estilo[e]
		var peor := 0.0
		for p: Vector3 in lista:
			peor = maxf(peor, Vector2(p.x - lista[0].x, p.z - lista[0].z).length())
		print("estilo %-12s arranca en %s, dispersion %.2f m" % [e, (lista[0] as Vector3).snapped(Vector3.ONE * 0.01), peor])
	return salida

func _atajadas(arquero: Node3D, c: PesCuerpo, atajadas: Array) -> Array:
	var ap: AnimationPlayer = arquero.animation_player
	var sk: Skeleton3D = arquero.skeleton
	var salida := []
	for e: Dictionary in atajadas:
		if e["espejo"]:
			continue
		var anim: String = e["anim"]
		var a := ap.get_animation(anim)
		var item := {"anim": anim, "t": e["t"], "rec": _recorrer(c, a, 0.0, a.length), "sig": {}}
		for clave: String in e["sig"]:
			var sig: Dictionary = e["sig"][clave]
			_pose(ap, sk, anim, sig["t_salto"])
			var c1 := _pos(sk, CADERA)
			var otro := "pes/" + str(sig["anim"])
			_pose(ap, sk, otro, sig["t_inicio"])
			var c2 := _pos(sk, CADERA)
			var ao := ap.get_animation(otro)
			item["sig"][clave] = {"anim": sig["anim"], "err": sig["err"], "dy_cadera": c2.y - c1.y, "rec": _recorrer(c, ao, sig["t_inicio"], ao.length)}
		salida.append(item)
	print("\n--- %d atajadas ---" % salida.size())
	_percentiles(salida.map(func(s): return s["rec"]["min_y"]), "malla min en la atajada")
	var dy := []
	var err := []
	var min_sig := []
	for s in salida:
		for k: String in s["sig"]:
			dy.append(s["sig"][k]["dy_cadera"])
			err.append(s["sig"][k]["err"])
			min_sig.append(s["sig"][k]["rec"]["min_y"])
	_percentiles(dy, "dy cadera al empalmar (m)")
	_percentiles(err, "err de pose al empalmar")
	_percentiles(min_sig, "malla min en la reaccion")
	var peores := salida.duplicate()
	peores.sort_custom(func(a, b): return a["rec"]["min_y"] < b["rec"]["min_y"])
	for s in peores.slice(0, 5):
		print("  %-44s min %+.3f %s t=%.2f (contacto %.2f)" % [s["anim"], s["rec"]["min_y"], s["rec"]["min_hueso"], s["rec"]["min_t"], s["t"]])
	return salida
