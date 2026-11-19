extends SceneTree

## Convierte los clips de animaciones_pes/fbx/ a librerias para el juego.
##
## Los FBX de PES usan el mismo rig que los personajes (mismos ejes por hueso),
## asi que las rotaciones se copian tal cual. Cambian tres cosas:
##   - el nombre de las pistas (mixamorig1_Hips -> Node/Skeleton3D:mixamorig1Hips)
##   - la cadera: viene en metros, con el origen en los pies y mirando a +Z, y
##     hay que pasarla al espacio del esqueleto de cada personaje
##   - los huesos sin pista (Godot saca las constantes) se completan con su
##     valor fijo, para que no hereden la pose de la animacion anterior
##
## PES guarda casi todo para un solo lado y lo espeja al jugar, asi que cada
## clip del arquero se guarda tambien espejado (nombre terminado en __M).
##
## Genera animaciones_pes/arquero.res, pateador.res y datos.json.
##   godot --headless --path . -s res://tools/pes_construir.gd

const PesCuerpo := preload("res://tools/pes_cuerpo.gd")
const DIR := "res://animaciones_pes/"
const FPS := 30.0
const CADERA := "mixamorig1Hips"
const SUFIJO_ESPEJO := "__M"
const CLIPS_EN_LOOP := ["pk_idle", "pk_kamae", "pk_enclose", "_loop"]
## El pateador arranca la carrera a esta distancia de la pelota como maximo: la
## camara esta 6 m detras de la pelota, y las carreras de PES empiezan a 5-9 m.
const DISTANCIA_CARRERA := 4.5
## Y tampoco tarda mas que esto (segundos de clip): hay carreras muy lentas al principio.
const DURACION_MAXIMA_CARRERA := 1.7
## Las que llegan corriendo fuerte desde lejos no se usan.
const CARRERAS_DESCARTADAS := ["pk_runup_neymar", "pk_runup_ronaldinho"]
## Angulo de llegada de cada estilo, en grados desde la linea recta al arco.
## Negativo: desde la izquierda de la pelota, como le pega un diestro.
const ANGULO_CARRERA := {"": -8.0, "2": -5.0, "cristiano": -14.0, "dummy_8": -10.0, "lewandowski": -20.0, "pogba": -12.0}
## Las esperas del arquero que se mueven mas de esto de costado parecen un amague.
const ESPERA_LATERAL_MAXIMA := 0.1
const GIRO_MAXIMO := 28.0
const RADIO_MINIMO := 3.3
## Cuadros de fundido al unir una carrera con su remate.
const FUNDIDO := 3
const RADIO_PELOTA := 0.11
const AVANCE_MAXIMO_REACCION := 1.35
## Algunos remates siguen corriendo hasta 8 m: hasta donde puede llegar la cadera
## despues del golpe, y en cuanto tiempo se mira (la reaccion llega cuando se
## resuelve el tiro, hasta un segundo y medio despues).
const AVANCE_MAXIMO_REMATE := 3.0
const TIEMPO_AVANCE_REMATE := 1.6
## La malla queda por lo menos a esta altura del piso (metros), y la correccion se
## reparte en esta cantidad de cuadros antes y despues de hacer falta.
const MARGEN_PISO := 0.005
const VENTANA_PISO := 5
## Al elegir un empalme: cuanto pesan la diferencia de altura de la cadera (m) y de
## su velocidad (m/s) frente a la de la pose (m).
const PESO_ALTURA_EMPALME := 1.0
const PESO_VELOCIDAD_EMPALME := 0.08
## Costo por segundo de seguir con el remate antes de reaccionar: si no, se elige un
## empalme parecido pero tardio y el pateador sigue corriendo metros despues del golpe.
const COSTO_ESPERA_REACCION := 0.2
## Festejos de las cinematicas (scripts/cinematicas.gd). Los de gol tienen entrada y _loop.
const FESTEJOS_PATEADOR := ["dm_goal_Knee_slide01", "dm_goal_Sliding01", "dm_goal_Wide_sliding01", "dm_goal_Head_sliding01", "dm_goal_archer", "dm_goal_recorder", "dm_goal_ivoryCoastDance",
	"dm_goal_Knee_slide01_loop", "dm_goal_Sliding01_loop", "dm_goal_Wide_sliding01_loop", "dm_goal_Head_sliding01_loop", "dm_goal_archer_loop", "dm_goal_recorder_loop", "dm_goal_ivoryCoastDance_loop",
	"dm_tu_run_3_0_idle_guts_banzai", "dm_tu_run_3_0_idle_guts_high", "dm_tu_run_3_0_idle_gutsR",
	"dm_tu_idle_0_0_idle_guts_banzai", "dm_tu_idle_0_0_idle_guts_high", "dm_tu_idle_0_0_idle_gutsR",
	"dm_pfm_cornerF_kick", "dm_pfm_cornerF_lariat"]
const FESTEJOS_ARQUERO := ["dm_oop_gk_idle_0_0_idle_cheer_03", "dm_oop_gk_idle_0_0_idle_walkCheer", "dm_oop_gk_idle_0_0_idle_walkCheer_04"]
## Las escenas de dt12 (tools/pes_extraer_ceremonias.py) que usa cada uno. El arquero
## tambien puede ser el capitan, asi que necesita los clips principales.
const ESCENAS_ARQUERO := ["dml_end_raise01_trophy08_cup_lg_chl", "dml_pk_win_hugSet_run_pounce02", "dml_pk_lose_aghast", "dml_pk_ready03_keeper_in", "dml_pk_goal_gk_goddamn_cool",
	"dml_pk_ready01_firstkeeper", "dml_pk_ready02_firstkeeper", "dml_end_trophy01_cup_eur"]
const ESCENAS_PATEADOR := ["dml_end_raise01_trophy08_", "dml_pk_win_hugSet_run_pounce02", "dml_pk_lose_aghast", "dml_pk_miss_shoot_", "dml_pk_goal_guts", "dml_pk_goal_drumming", "dml_pk_goal_pointing", "dml_pk_wait_miss_set01_", "dml_pk_ready03_kicker_in", "dml_pk_ready03_judge", "dml_pk_ready02_wait", "dml_pk_ready01_firstkicker", "dml_pk_ready02_firstkicker", "dml_pk_wait_success_set01_", "dml_pk_wait_success_pair", "dml_ent_circleJPN01_", "dml_end_trophy01_"]
## Festejos completos de un jugador (arrancan corriendo y terminan en el gesto) que sirven
## solos: no se van demasiado lejos, no duran demasiado y no se tiran al piso ni flotan.
const FESTEJO_RECORRIDO := Vector2(3.0, 18.0)
const FESTEJO_DURACION := Vector2(3.0, 9.0)
const FESTEJO_ALTURA := Vector2(0.4, 1.7)
## Festejos grupales (tools/pes_extraer_ceremonias.py): cuanto dura el del autor, entre que
## alturas de cadera se aceptan (hay quien se sube a upa) y a cuanto de algun companero
## tiene que llegar CADA uno, cadera con cadera (un abrazo o chocar los cinco): en PES
## hay festejos en que alguno le hace el gesto a otro que esta a 2 m, y en el juego se ve
## como abrazar al aire.
const GRUPAL_DURACION := Vector2(4.0, 14.0)
const GRUPAL_ALTURA := Vector2(0.25, 2.3)
const GRUPAL_CONTACTO := 0.6
## Y a cuanto del autor terminan los demas, en promedio, como mucho, y a cuanto del mas
## cercano termina cada uno: si alguno queda aparte, abraza o le habla a alguien lejos.
const GRUPAL_SEPARACION := 6.0
const GRUPAL_VECINO := 2.0
const GRUPAL_PASO := 0.25
## Las vaselinas (kick_*_lob) son suaves: el pie va mas lento que en un remate.
const VELOCIDAD_MINIMA_REMATE := 12.0
const VELOCIDAD_MINIMA_LOB := 7.0
## Una vaselina con el dedo mas alto que esto en el golpe pasa por arriba de la pelota.
const ALTURA_MAXIMA_DEDO_LOB := 0.16
## Despues de levantarse, el lamento sale de aca segun la pose (los kneeR son
## arrodillado, los hop de pie), y no se acepta si la cadera tendria que saltar mas
## que DIFERENCIA_MAXIMA_LAMENTO.
const LAMENTOS_ARQUERO := ["dml_pk_goal_gk_goddamn_cool", "gdml_pk_goal_gk_connect01_rise_hop_01_045", "gdml_pk_goal_gk_connect01_rise_hop_02_045",
	"gdml_pk_goal_gk_connect01_rise_kneeR_01_045", "gdml_pk_goal_gk_connect01_rise_kneeR_02_000"]
const DIFERENCIA_MAXIMA_LAMENTO := 0.2
## Una reaccion cuya cadera baja mas que esto respecto de como arranco se vuelve a
## tirar al piso (varias "cancel" y "resign" arrancan con una estirada entera).
const CAIDA_MAXIMA_REACCION := 0.3
const HUESOS_POSE := ["mixamorig1Spine2", "mixamorig1Head", "mixamorig1LeftHand", "mixamorig1RightHand",
	"mixamorig1LeftFoot", "mixamorig1RightFoot", "mixamorig1LeftLeg", "mixamorig1RightLeg"]

var _hecho := false
var _juego: Node
## Por clip (sin espejar): cuanto se subio la cadera en cada cuadro.
var _levantes := {}
var _crudas := {}

## escenas.json tal cual, sin los ajustes del editor de festejos: el juego los aplica
## encima de lo que se mide aca (si se midiera con ellos, se aplicarian dos veces).
func _escenas_crudas() -> Dictionary:
	if _crudas.is_empty():
		_crudas = JSON.parse_string(FileAccess.get_file_as_string(DIR + "escenas.json"))
	return _crudas

func _initialize() -> void:
	_juego = load("res://scenes/game.tscn").instantiate()
	get_root().add_child(_juego)

func _process(_d: float) -> bool:
	if _hecho:
		return true
	_hecho = true
	_construir()
	quit()
	return false

func _construir() -> void:
	var t0 := Time.get_ticks_msec()
	var arquero: Node3D = _juego.get_node("Goalkeeper")
	var pateador: Node3D = _juego.get_node("Kicker")
	arquero.set_process(false); arquero.set_physics_process(false)
	pateador.set_process(false); pateador.set_physics_process(false)
	_juego.set_process(false); _juego.set_physics_process(false)
	# Si ya hay una version de las librerias, el juego ya llego a parar al pateador
	# girado hacia su carrera, y todo lo medido quedaria girado con el.
	pateador.global_transform = Transform3D.IDENTITY
	arquero.reset_to_idle()
	var sk_a: Skeleton3D = arquero.skeleton
	var sk_p: Skeleton3D = pateador.skeleton
	var ap_a: AnimationPlayer = arquero.animation_player
	var ap_p: AnimationPlayer = pateador.animation_player

	# Del espacio del clip (pies en el origen, mirando a +Z) al del esqueleto.
	# Los dos personajes miran en sentidos opuestos: el arquero tiene su raiz
	# rotada 180 grados y por eso el giro sale de la misma cuenta.
	var giro := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var x_a := sk_a.global_transform.affine_inverse() * arquero.global_transform * giro
	var x_p := sk_p.global_transform.affine_inverse() * pateador.global_transform * giro
	print("clip->arquero ", x_a.basis.get_scale(), " ", x_a.origin, " | clip->pateador ", x_p.basis.get_scale(), " ", x_p.origin)

	var lib_a := AnimationLibrary.new()
	var lib_p := AnimationLibrary.new()
	var huesos: Array[String] = []
	for b in sk_a.get_bone_count():
		huesos.append(sk_a.get_bone_name(b))

	_comprobar_espejo()

	for grupo in ["atajadas", "arquero_extra"]:
		for f in _fbx(grupo):
			_agregar(lib_a, f, huesos, x_a, true, false)
	for grupo in ["pateador", "remates"]:
		for f in _fbx(grupo):
			_agregar(lib_p, f, huesos, x_p, false, false)
	for n: String in FESTEJOS_PATEADOR:
		_agregar(lib_p, DIR + "fbx/festejos/" + n + ".fbx", huesos, x_p, false, false)
	var festejos_gol := []
	# Los clips de festejos grupales esperan a sus companeros: no van solos.
	var grupales: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "festejos_grupales.json"))
	var de_grupo := {}
	for corte: String in grupales.values():
		for a: Dictionary in _escenas_crudas()[corte]:
			de_grupo[a["clip"]] = true
	for f in _fbx("ceremonia"):
		var nombre := f.get_file().get_basename()
		if nombre.ends_with("_ball"):
			continue
		var es_festejo := nombre.begins_with("dml_goal_celebrate")
		if es_festejo or ESCENAS_PATEADOR.any(func(p: String): return nombre.begins_with(p)):
			_agregar(lib_p, f, huesos, x_p, false, false)
		if es_festejo and not de_grupo.has(nombre):
			if _festejo_sirve(lib_p.get_animation(nombre)):
				festejos_gol.append(nombre)
			else:
				lib_p.remove_animation(nombre)
		if nombre in ESCENAS_ARQUERO:
			_agregar(lib_a, f, huesos, x_a, true, false)
	print("festejos de gol: ", festejos_gol.size())
	for n: String in FESTEJOS_ARQUERO:
		_agregar(lib_a, DIR + "fbx/festejos/" + n + ".fbx", huesos, x_a, true, false)
	_preparar_fk(sk_a)
	var combinados := _combinar_remates(lib_p, sk_p)
	var cuerpo_a := PesCuerpo.new(sk_a)
	_apoyar_en_piso(lib_a, cuerpo_a)
	_apoyar_en_piso(lib_p, PesCuerpo.new(sk_p))

	print("armadas: arquero %d, pateador %d (%.0f s)" % [lib_a.get_animation_list().size(), lib_p.get_animation_list().size(), (Time.get_ticks_msec() - t0) / 1000.0])
	# El juego ya pudo haber cargado una version anterior de las librerias.
	for ap: AnimationPlayer in [ap_a, ap_p]:
		if ap.has_animation_library("pes"):
			ap.remove_animation_library("pes")
	ap_a.add_animation_library("pes", lib_a)
	ap_p.add_animation_library("pes", lib_p)
	var remates := _medir_remates(pateador, ap_p, sk_p, combinados)
	_empalmar_remates(remates, lib_p)
	var atajadas := _medir_atajadas(arquero, ap_a, sk_a)
	_empalmar_atajadas(atajadas, lib_a)
	var datos := {
		"atajadas": atajadas,
		"remates": remates,
		"esperas_arquero": _esperas(lib_a, "gkmovemid_pk", false),
		"esperas_pateador": _esperas(lib_p, "pk_kamae"),
		"nube_malla": cuerpo_a.nubes(),
		"festejos_gol": festejos_gol,
	}
	var medidos := _medir_grupales(pateador, ap_p, sk_p, grupales.values())
	datos["festejos_grupales"] = medidos["sirven"]
	datos["festejos_grupales_descartados"] = medidos["descartados"]
	# De los festejos grupales quedan en pateador.res solo los clips de los que sirven. Los
	# de los descartados van aparte (GRUPALES_EXTRA): el editor de festejos los muestra y
	# el juego los carga solo si alguno se activo a mano.
	var usados := {}
	for g: Dictionary in datos["festejos_grupales"]:
		for a: Dictionary in g["actores"]:
			usados[a["clip"]] = true
	var lib_extra := AnimationLibrary.new()
	for n: String in de_grupo:
		if not usados.has(n) and lib_p.has_animation(n):
			lib_extra.add_animation(n, lib_p.get_animation(n))
			lib_p.remove_animation(n)
	# Las carreras y golpes sueltos ya estan adentro de los clips unidos.
	for n: String in lib_p.get_animation_list():
		if n.begins_with("kick_") or n.begins_with("pk_runup"):
			lib_p.remove_animation(n)
	# Se comprimen recien aca: para medir y unir se usan los cuadros exactos.
	_comprimir_con_control(lib_a)
	_comprimir_con_control(lib_p)
	_comprimir_con_control(lib_extra)
	ResourceSaver.save(lib_a, DIR + "arquero.res")
	ResourceSaver.save(lib_p, DIR + "pateador.res")
	ResourceSaver.save(lib_extra, DIR + PesAnimaciones.GRUPALES_EXTRA)
	var f := FileAccess.open(DIR + "datos.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(datos, " "))
	f.close()
	print("listo en %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0))

## Por cada festejo grupal, el camino de la cadera de cada actor (x, z cada GRUPAL_PASO s),
## con la escena puesta en el origen como la pone el juego. Con eso el juego mueve al grupo
## entero, sin separarlo, hasta el corner. El autor va primero. Devuelve los que sirven y,
## aparte, los que no pasan los controles con el motivo, para arreglarlos en el editor de
## festejos. Solo se pierden los que no tienen todos sus clips.
func _medir_grupales(pateador: Node3D, ap: AnimationPlayer, sk: Skeleton3D, cortes: Array) -> Dictionary:
	var salida := []
	var descartados := []
	var cuenta := {"faltan": 0, "duracion": 0, "altura": 0, "solos": 0, "separados": 0}
	for corte: String in cortes:
		var actores: Array = _escenas_crudas()[corte].duplicate(true)
		actores.sort_custom(func(a, b): return not str(a["clip"]).contains("_sub") and str(b["clip"]).contains("_sub"))
		if actores.any(func(a): return not ap.has_animation("pes/" + str(a["clip"]))):
			cuenta["faltan"] += 1
			continue
		var largo := ap.get_animation("pes/" + str(actores[0]["clip"])).length
		var medido := _caminos(pateador, ap, sk, actores, largo)
		var caminos: Array = medido["caminos"]
		# Cada uno tiene que llegar a tocar a alguno en algun momento.
		var lejos := 0.0
		for i in caminos.size():
			var encuentro := INF
			for j in caminos.size():
				if j == i:
					continue
				for k in mini(caminos[i].size(), caminos[j].size()):
					encuentro = minf(encuentro, Vector2(caminos[i][k][0] - caminos[j][k][0], caminos[i][k][1] - caminos[j][k][1]).length())
			lejos = maxf(lejos, encuentro)
		var motivo := ""
		var detalle := ""
		if largo < GRUPAL_DURACION.x or largo > GRUPAL_DURACION.y:
			motivo = "duracion"
			detalle = "dura %.1f s" % largo
		elif not medido["alturas_ok"]:
			motivo = "altura"
			detalle = "alguno se tira al piso o se sube a otro"
		elif lejos > GRUPAL_CONTACTO:
			motivo = "solos"
			detalle = "alguno no llega a tocar a nadie (queda a %.1f m)" % lejos
		elif medido["separacion"] > GRUPAL_SEPARACION or medido["aparte"] > GRUPAL_VECINO:
			motivo = "separados"
			detalle = "alguno termina lejos (a %.1f m del mas cercano)" % medido["aparte"]
		var g := {"corte": corte, "largo": largo, "actores": actores, "caminos": caminos}
		if motivo == "":
			salida.append(g)
		else:
			cuenta[motivo] += 1
			g["motivo"] = detalle
			descartados.append(g)
	ap.stop()
	pateador.global_transform = Transform3D.IDENTITY
	print("festejos grupales: %d (descartados %s)" % [salida.size(), cuenta])
	return {"sirven": salida, "descartados": descartados}

## El camino de la cadera de cada actor, si alguno se tira al piso o vuela y que tan
## lejos del autor terminan los demas, en promedio.
func _caminos(pateador: Node3D, ap: AnimationPlayer, sk: Skeleton3D, actores: Array, largo: float) -> Dictionary:
	var caminos := []
	var alturas_ok := true
	for a: Dictionary in actores:
		var camino := []
		var t := 0.0
		var hasta := minf(largo, ap.get_animation("pes/" + str(a["clip"])).length)
		PesAnimaciones.colocar_actor(pateador, ap, a, Vector3.ZERO, PesAnimaciones.ESCALA_CON_CARRERA)
		while t <= hasta + 0.001:
			ap.seek(minf(t, hasta - 0.02), true)
			sk.force_update_all_bone_transforms()
			var p := _pos(sk, CADERA)
			alturas_ok = alturas_ok and p.y >= GRUPAL_ALTURA.x and p.y <= GRUPAL_ALTURA.y
			camino.append([snappedf(p.x, 0.01), snappedf(p.z, 0.01)])
			t += GRUPAL_PASO
		caminos.append(camino)
	var separacion := 0.0
	for i in range(1, caminos.size()):
		separacion += Vector2(caminos[i][-1][0] - caminos[0][-1][0], caminos[i][-1][1] - caminos[0][-1][1]).length()
	var aparte := 0.0
	for i in caminos.size():
		var vecino := INF
		for j in caminos.size():
			if j != i:
				vecino = minf(vecino, Vector2(caminos[i][-1][0] - caminos[j][-1][0], caminos[i][-1][1] - caminos[j][-1][1]).length())
		aparte = maxf(aparte, vecino)
	return {"caminos": caminos, "alturas_ok": alturas_ok, "separacion": separacion / maxf(caminos.size() - 1, 1), "aparte": aparte}

## Sube la cadera en los cuadros donde la malla atravesaria el piso. Va antes de
## medir contactos y empalmes, que dependen de la altura final. El clip espejado
## usa la misma correccion que el original.
func _apoyar_en_piso(lib: AnimationLibrary, cuerpo: PesCuerpo) -> void:
	var nombres: Array = lib.get_animation_list()
	var maximo := 0.0
	var corregidos := 0
	for n: String in nombres:
		if n.ends_with(SUFIJO_ESPEJO):
			continue
		var subir := cuerpo.levante(lib.get_animation(n), FPS, MARGEN_PISO, VENTANA_PISO)
		_levantes[n] = subir
		var cambio := _aplicar_levante(lib.get_animation(n), subir)
		if lib.has_animation(n + SUFIJO_ESPEJO):
			_aplicar_levante(lib.get_animation(n + SUFIJO_ESPEJO), subir)
		maximo = maxf(maximo, cambio)
		corregidos += 1 if cambio > 0.0 else 0
	print("piso: %d clips corregidos, hasta %.2f m" % [corregidos, maximo])

func _aplicar_levante(a: Animation, subir: PackedFloat32Array) -> float:
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var maximo := 0.0
	for k in a.track_get_key_count(pista):
		var f := clampi(roundi(a.track_get_key_time(pista, k) * FPS), 0, subir.size() - 1)
		a.track_set_key_value(pista, k, (a.track_get_key_value(pista, k) as Vector3) + Vector3(0.0, subir[f] / PesCuerpo.ESCALA, 0.0))
		maximo = maxf(maximo, subir[f])
	return maximo

func _festejo_sirve(a: Animation) -> bool:
	if a.length < FESTEJO_DURACION.x or a.length > FESTEJO_DURACION.y:
		return false
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var inicio := a.position_track_interpolate(pista, 0.0)
	var lejos := 0.0
	var t := 0.0
	while t <= a.length:
		var p := a.position_track_interpolate(pista, t) * 0.01
		if p.y < FESTEJO_ALTURA.x or p.y > FESTEJO_ALTURA.y:
			return false
		lejos = maxf(lejos, Vector2(p.x - inicio.x * 0.01, p.z - inicio.z * 0.01).length())
		t += 0.1
	return lejos >= FESTEJO_RECORRIDO.x and lejos <= FESTEJO_RECORRIDO.y

func _fbx(grupo: String) -> Array[String]:
	var out: Array[String] = []
	for a in DirAccess.get_files_at(DIR + "fbx/" + grupo):
		if a.ends_with(".fbx"):
			out.append(DIR + "fbx/" + grupo + "/" + a)
	out.sort()
	return out

## Animation.compress() a veces mete saltos de metros en los bordes de sus paginas.
## Se comprime cada clip por separado y solo se acepta si sigue igual al original.
func _comprimir_con_control(lib: AnimationLibrary) -> void:
	var rechazados := 0
	for n: String in lib.get_animation_list():
		var original := lib.get_animation(n)
		var copia: Animation = original.duplicate(true)
		copia.compress()
		if _coinciden(original, copia):
			lib.remove_animation(n)
			lib.add_animation(n, copia)
		else:
			rechazados += 1
	print("compresion: %d de %d clips quedan sin comprimir por diferir del original" % [rechazados, lib.get_animation_list().size()])

func _coinciden(a: Animation, b: Animation) -> bool:
	for t in a.get_track_count():
		var ruta := a.track_get_path(t)
		var tipo := a.track_get_type(t)
		var tb := b.find_track(ruta, tipo)
		if tb < 0:
			return false
		var x := 0.0
		while x <= a.length:
			if tipo == Animation.TYPE_POSITION_3D:
				if a.position_track_interpolate(t, x).distance_to(b.position_track_interpolate(tb, x)) > 3.0:
					return false
			elif tipo == Animation.TYPE_ROTATION_3D:
				if absf(a.rotation_track_interpolate(t, x).dot(b.rotation_track_interpolate(tb, x))) < 0.999:
					return false
			x += 1.0 / 60.0
	return true

func _agregar(lib: AnimationLibrary, ruta: String, huesos: Array[String], x: Transform3D, espejo: bool, comprimir := true) -> void:
	var escena: Node = load(ruta).instantiate()
	var ap: AnimationPlayer = escena.find_children("*", "AnimationPlayer", true, false)[0]
	var esq: Skeleton3D = escena.find_children("*", "Skeleton3D", true, false)[0]
	var fuente: Animation = ap.get_animation(ap.get_animation_list()[0])
	var nombre := ruta.get_file().get_basename()
	lib.add_animation(nombre, _convertir(fuente, esq, huesos, x, false, nombre, comprimir))
	if espejo:
		lib.add_animation(nombre + SUFIJO_ESPEJO, _convertir(fuente, esq, huesos, x, true, nombre, comprimir))
	escena.free()

static func _clip(hueso: String) -> String:
	return hueso.replace("mixamorig1", "mixamorig1_")

static func _pareja(hueso: String) -> String:
	if hueso.contains("Left"):
		return hueso.replace("Left", "Right")
	return hueso.replace("Right", "Left")

## Reflejar una rotacion local respecto del plano YZ. Vale para todos los huesos
## porque el rig tiene los ejes del lado derecho reflejados respecto de los del
## izquierdo (_comprobar_espejo lo verifica).
static func _reflejar(q: Quaternion) -> Quaternion:
	return Quaternion(q.x, -q.y, -q.z, q.w)

func _convertir(a: Animation, e: Skeleton3D, huesos: Array[String], x: Transform3D, espejo: bool, nombre: String, comprimir: bool) -> Animation:
	var pistas_rot := {}
	var pista_pos := -1
	for t in a.get_track_count():
		var hueso := str(a.track_get_path(t)).get_slice(":", 1)
		match a.track_get_type(t):
			Animation.TYPE_ROTATION_3D: pistas_rot[hueso] = t
			Animation.TYPE_POSITION_3D:
				if hueso == _clip(CADERA):
					pista_pos = t

	var d := Animation.new()
	var cuadros := roundi(a.length * FPS)
	d.length = cuadros / FPS
	d.step = 1.0 / FPS
	for parte in CLIPS_EN_LOOP:
		if nombre.contains(parte):
			d.loop_mode = Animation.LOOP_LINEAR
	var rot_x := Quaternion(x.basis.orthonormalized())
	var ruta := "Node/Skeleton3D:"

	if pista_pos >= 0:
		var t := d.add_track(Animation.TYPE_POSITION_3D)
		d.track_set_path(t, ruta + CADERA)
		for c in cuadros + 1:
			var p := a.position_track_interpolate(pista_pos, c / FPS)
			if espejo:
				p.x = -p.x
			d.position_track_insert_key(t, c / FPS, x * p)

	for hueso in huesos:
		var origen := _clip(_pareja(hueso) if espejo else hueso)
		var t := d.add_track(Animation.TYPE_ROTATION_3D)
		d.track_set_path(t, ruta + hueso)
		var pista: int = pistas_rot.get(origen, -1)
		var keys := cuadros + 1 if pista >= 0 else 1
		for c in keys:
			var q: Quaternion
			if pista >= 0:
				q = a.rotation_track_interpolate(pista, c / FPS)
			else:
				var i := e.find_bone(origen)
				q = e.get_bone_rest(i).basis.get_rotation_quaternion() if i >= 0 else Quaternion.IDENTITY
			if espejo:
				q = _reflejar(q)
			if hueso == CADERA:
				q = rot_x * q
			d.rotation_track_insert_key(t, c / FPS, q)
	if comprimir:
		d.compress()
	return d

## Comprueba con un clip real que el espejo da exactamente la pose reflejada:
## posicion de cada hueso con _reflejar vs. la del hueso pareja con x invertida.
func _comprobar_espejo() -> void:
	var escena: Node = load(_fbx("atajadas")[10]).instantiate()
	var ap: AnimationPlayer = escena.find_children("*", "AnimationPlayer", true, false)[0]
	var e: Skeleton3D = escena.find_children("*", "Skeleton3D", true, false)[0]
	var a: Animation = ap.get_animation(ap.get_animation_list()[0])
	var rots := {}
	for t in a.get_track_count():
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			rots[str(a.track_get_path(t)).get_slice(":", 1)] = t
	var peor := 0.0
	var peor_hueso := ""
	var tm := a.length * 0.5
	var normal := {}
	var refl := {}
	for b in e.get_bone_count():
		var n := e.get_bone_name(b)
		var tr := rots.get(n, -1) as int
		var q: Quaternion = a.rotation_track_interpolate(tr, tm) if tr >= 0 else e.get_bone_rest(b).basis.get_rotation_quaternion()
		var par := _pareja(n)
		var trp := rots.get(par, -1) as int
		var ib := e.find_bone(par)
		var qp: Quaternion = a.rotation_track_interpolate(trp, tm) if trp >= 0 else e.get_bone_rest(ib).basis.get_rotation_quaternion()
		var padre := e.get_bone_parent(b)
		var o := e.get_bone_rest(b).origin
		var pn: Transform3D = normal[padre] if padre >= 0 else Transform3D()
		var pr: Transform3D = refl[padre] if padre >= 0 else Transform3D()
		normal[b] = pn * Transform3D(Basis(q), o)
		refl[b] = pr * Transform3D(Basis(_reflejar(qp)), o)
	for b in e.get_bone_count():
		var par := e.find_bone(_pareja(e.get_bone_name(b)))
		var p: Vector3 = (refl[b] as Transform3D).origin
		var q: Vector3 = (normal[par] as Transform3D).origin
		var err := p.distance_to(Vector3(-q.x, q.y, q.z))
		if err > peor:
			peor = err
			peor_hueso = e.get_bone_name(b)
	print("espejo: error maximo %.2f cm (%s)" % [peor * 100.0, peor_hueso])
	escena.free()

const HUESOS_PES := {
	"sk_hand_l": "LeftHandMiddle1", "sk_hand_r": "RightHandMiddle1",
	"sk_forearm_l": "LeftForeArm", "sk_forearm_r": "RightForeArm",
	"sk_upperarm_l": "LeftArm", "sk_upperarm_r": "RightArm",
	"sk_leg_l": "LeftLeg", "sk_leg_r": "RightLeg",
	"sk_foot_l": "LeftFoot", "sk_foot_r": "RightFoot",
	"sk_thigh_l": "LeftUpLeg", "sk_thigh_r": "RightUpLeg",
	"sk_head": "Head", "sk_chest": "Spine2", "sk_belly": "Spine", "sk_neck": "Neck",
}

func _pos(sk: Skeleton3D, hueso: String) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(hueso)).origin

func _pose(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	if ap.current_animation != anim:
		ap.play(anim)
		ap.pause()
	ap.seek(t, true)
	sk.force_update_all_bone_transforms()

## Para cada atajada: cuando y donde es el contacto, medido en el personaje.
func _medir_atajadas(arquero: Node3D, ap: AnimationPlayer, sk: Skeleton3D) -> Array:
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "atajadas.json"))
	var base := arquero.global_position
	var salida := []
	var dist_mano := PackedFloat32Array()
	for nombre: String in info:
		var c: Dictionary = info[nombre]
		for espejo in [false, true]:
			var anim := "pes/" + nombre + (SUFIJO_ESPEJO if espejo else "")
			if not ap.has_animation(anim):
				continue
			var p: Array = c["contacto_m"]
			# El punto de contacto de PES sube junto con el cuerpo.
			var subir: PackedFloat32Array = _levantes[nombre]
			var alto: float = float(p[1]) + subir[clampi(int(c["hit_frame"]), 0, subir.size() - 1)]
			var punto := Vector3(-p[0] if espejo else p[0], alto, p[2])
			var hueso_pes: String = c["hueso"]
			var parte: String = HUESOS_PES.get(hueso_pes, "RightHandMiddle1" if p[0] < 0.0 else "LeftHandMiddle1")
			if espejo:
				parte = _pareja(parte)
			var hueso := "mixamorig1" + parte
			var t := int(c["hit_frame"]) / FPS
			_pose(ap, sk, anim, t)
			# El punto de PES es para el cuerpo de su jugador, con otras proporciones.
			# Si toca con el brazo, se usa la mano real del personaje y la pelota
			# apoyada en ella (un radio de pelota en la direccion del punto).
			if parte.contains("Arm") or parte.contains("Hand"):
				var izq := _pos(sk, "mixamorig1LeftHandMiddle1") - base
				var der := _pos(sk, "mixamorig1RightHandMiddle1") - base
				var mano := izq if izq.distance_to(punto) < der.distance_to(punto) else der
				hueso = "mixamorig1LeftHandMiddle1" if mano == izq else "mixamorig1RightHandMiddle1"
				if mano.distance_to(punto) > RADIO_PELOTA:
					punto = mano + (punto - mano).normalized() * RADIO_PELOTA
			var d := (_pos(sk, hueso) - base).distance_to(punto)
			dist_mano.append(d)
			salida.append({
				"anim": anim,
				"base": nombre,
				"espejo": espejo,
				"familia": nombre.get_slice("_", 0),
				"t": t,
				"hueso": hueso,
				"despegue": _medir_despegue(ap, sk, anim, t),
				"punto": [punto.x, punto.y, punto.z],
			})
	dist_mano.sort()
	print("atajadas medidas: %d | hueso-punto: mediana %.2f m, p90 %.2f m" % [salida.size(), dist_mano[dist_mano.size() / 2], dist_mano[dist_mano.size() * 9 / 10]])
	return salida

## Igual que tools/bakear.gd: primer momento en que la cadera arranca rapido.
func _medir_despegue(ap: AnimationPlayer, sk: Skeleton3D, anim: String, contacto: float) -> float:
	var prev := Vector3.ZERO
	var paso := 1.0 / FPS
	var t := 0.0
	while t < contacto:
		_pose(ap, sk, anim, t)
		var p := _pos(sk, CADERA)
		var v := (p - prev) / paso
		if t > 0.0 and (Vector2(v.x, v.z).length() > 0.75 or v.y > 1.0):
			return maxf(0.0, t - paso)
		prev = p
		t += paso
	return maxf(0.0, contacto - 0.35)

# --- Pose para comparar clips ------------------------------------------------

var _padres := {}
var _origenes := {}
var _pistas := {}

func _preparar_fk(sk: Skeleton3D) -> void:
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b)
		_padres[n] = sk.get_bone_name(sk.get_bone_parent(b)) if sk.get_bone_parent(b) >= 0 else ""
		_origenes[n] = sk.get_bone_rest(b).origin

func _pistas_de(a: Animation) -> Dictionary:
	if _pistas.has(a):
		return _pistas[a]
	var d := {}
	for t in a.get_track_count():
		var n := str(a.track_get_path(t)).get_slice(":", 1)
		if a.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			d[n] = t
		elif a.track_get_type(t) == Animation.TYPE_POSITION_3D:
			d["_pos"] = t
	_pistas[a] = d
	return d

static func _yaw(q: Quaternion) -> float:
	var r := q * Vector3.RIGHT
	if Vector2(r.x, r.z).length() > 0.5:
		return atan2(-r.z, r.x)
	var f := q * Vector3.BACK
	return atan2(f.x, f.z)

## Pose de un cuadro relativa a la cadera y sin el giro horizontal: dos clips se
## pueden empalmar si esto da parecido, mire para donde mire cada uno.
func _pose_clip(a: Animation, t: float) -> Dictionary:
	var p := _pistas_de(a)
	var globales := {}
	var pose := {}
	var cadera_q := a.rotation_track_interpolate(p[CADERA], t)
	var sin_giro := Quaternion(Vector3.UP, -_yaw(cadera_q))
	for hueso: String in _padres:
		var q: Quaternion = a.rotation_track_interpolate(p[hueso], t) if p.has(hueso) else Quaternion.IDENTITY
		var padre: String = _padres[hueso]
		var local := Transform3D(Basis(q), _origenes[hueso])
		globales[hueso] = local if padre == "" else (globales[padre] as Transform3D) * local
	var origen: Vector3 = (globales[CADERA] as Transform3D).origin
	# La cadera del clip reemplaza al origen de reposo.
	for hueso in HUESOS_POSE:
		pose[hueso] = sin_giro * ((globales[hueso] as Transform3D).origin - origen) * 0.01
	# Para los empalmes: _pose_clip no ve ni la altura ni el movimiento de la cadera.
	var cadera := a.position_track_interpolate(p["_pos"], t)
	var siguiente := minf(t + 1.0 / FPS, a.length)
	var luego := a.position_track_interpolate(p["_pos"], siguiente)
	pose["_alto"] = cadera.y * 0.01
	pose["_vel"] = sin_giro * (luego - cadera) * 0.01 * FPS if siguiente > t else Vector3.ZERO
	return pose

static func _dif_pose(a: Dictionary, b: Dictionary) -> float:
	var s := 0.0
	for k in HUESOS_POSE:
		s += (a[k] as Vector3).distance_squared_to(b[k])
	return sqrt(s / HUESOS_POSE.size())

## Costo de saltar entre dos cuadros: ademas de la pose, cuanto cambian la altura y
## la velocidad de la cadera. Dos clips con la misma pose pero un metro de altura de
## diferencia se ven flotar durante el fundido.
static func _dif_empalme(a: Dictionary, b: Dictionary) -> float:
	var alto: float = absf(a["_alto"] - b["_alto"]) * PESO_ALTURA_EMPALME
	var vel: float = (a["_vel"] as Vector3).distance_to(b["_vel"]) * PESO_VELOCIDAD_EMPALME
	return _dif_pose(a, b) + alto + vel

## Busca como seguir: el cuadro de `a` entre desde y hasta (segundos) y el cuadro
## inicial de algun candidato que menos saltan.
func _mejor_empalme(a: Animation, desde: float, hasta: float, candidatos: Dictionary, costo_espera := 0.0) -> Dictionary:
	var mejor := {"err": INF}
	var t := desde
	while t <= hasta + 0.001:
		var p := _pose_clip(a, t)
		for n: String in candidatos:
			var poses: Array = candidatos[n]
			for i in poses.size():
				var e := _dif_empalme(p, poses[i]) + (t - desde) * costo_espera
				if e < mejor["err"]:
					mejor = {"err": e, "t_salto": t, "anim": n, "t_inicio": i / FPS}
		t += 2.0 / FPS
	return mejor

func _poses_iniciales(lib: AnimationLibrary, nombres: Array, cuadros := 10) -> Dictionary:
	var d := {}
	for n: String in nombres:
		var a := lib.get_animation(n)
		var poses := []
		for c in mini(cuadros, roundi(a.length * FPS)):
			poses.append(_pose_clip(a, c / FPS))
		d[n] = poses
	return d

# --- Remates --------------------------------------------------------------------

## Datos de un remate: cuadro del golpe y hacia donde va el pie.
func _analizar_remate(a: Animation, sk: Skeleton3D) -> Dictionary:
	var p := _pistas_de(a)
	var mejor := {"v": 0.0, "f": 0, "dir": Vector3.ZERO}
	var dedo := "mixamorig1RightToeBase"
	var cadena: Array[String] = []
	var h := dedo
	while h != "":
		cadena.push_front(h)
		h = _padres[h]
	var prev := Vector3.ZERO
	var alturas := PackedFloat32Array()
	for f in roundi(a.length * FPS) + 1:
		var tf := Transform3D()
		for b in cadena:
			var o: Vector3 = a.position_track_interpolate(p["_pos"], f / FPS) if b == CADERA else _origenes[b]
			var q: Quaternion = a.rotation_track_interpolate(p[b], f / FPS) if p.has(b) else Quaternion.IDENTITY
			tf = tf * Transform3D(Basis(q), o)
		var pos := tf.origin * 0.01
		alturas.append(pos.y)
		if f > 0:
			var v := (pos - prev) * FPS
			if v.length() > mejor["v"] and pos.y < 2.25 + 0.45 and f < 25:
				mejor = {"v": v.length(), "f": f, "dir": v}
		prev = pos
	mejor["alturas"] = alturas
	return mejor

## Une cada carrera con los remates que mejor la continuan: un clip por estilo de
## carrera, direccion, potencia y forma de golpear. PES hace lo mismo al jugar: los ultimos
## cuadros de pk_runup coinciden con el arranque de un kick_*.
func _combinar_remates(lib: AnimationLibrary, sk: Skeleton3D) -> Array:
	var remates := {}
	for n: String in lib.get_animation_list():
		if not n.begins_with("kick_"):
			continue
		var r := RegEx.create_from_string("kick_(long|mid|short)_(\\d)_0_(\\w+?)_y(\\d)_(000|045|f045|f022)(?:_(\\w+))?$").search(n)
		if r == null:
			continue
		var lob := n.ends_with("_lob")
		if r.get_string(1) == "short" and not lob:
			continue
		var info := _analizar_remate(lib.get_animation(n), sk)
		# y0 es la pelota en el piso; y2, y4... son voleas.
		if r.get_string(4) != "0" or info["v"] < (VELOCIDAD_MINIMA_LOB if lob else VELOCIDAD_MINIMA_REMATE) or info["f"] < 8 or info["f"] > 14:
			continue
		# El pico de velocidad no es el toque: puede llegar ya arriba de la pelota. El
		# golpe es donde el pie esta mas abajo.
		if lob:
			var alturas: PackedFloat32Array = info["alturas"]
			while info["f"] > 8 and alturas[info["f"] - 1] < alturas[info["f"]]:
				info["f"] -= 1
			while info["f"] < 14 and alturas[info["f"] + 1] < alturas[info["f"]]:
				info["f"] += 1
		remates[n] = {"potencia": r.get_string(1), "metodo": r.get_string(3), "altura": int(r.get_string(4)), "dir": r.get_string(5), "golpe": info["f"], "vel": info["dir"], "lob": lob}
	print("remates utiles: ", remates.size())
	var salida := []
	for n: String in lib.get_animation_list().duplicate():
		if not n.begins_with("pk_runup") or n in CARRERAS_DESCARTADAS:
			continue
		var carrera := lib.get_animation(n)
		var ult := roundi(carrera.length * FPS)
		var poses_fin := {}
		for f in range(ult - 10, ult + 1):
			poses_fin[f] = _pose_clip(carrera, f / FPS)
		var por_grupo := {}
		for k: String in remates:
			var info: Dictionary = remates[k]
			var kick := lib.get_animation(k)
			var mejor := {"err": INF}
			for f: int in poses_fin:
				for kf in range(0, int(info["golpe"]) - 1):
					var e := _dif_pose(poses_fin[f], _pose_clip(kick, kf / FPS))
					if e < mejor["err"]:
						mejor = {"err": e, "fin": f, "kf": kf, "kick": k}
			# De las picadas quedan todas: que nunca sea la misma es lo que las esconde.
			var grupo: String = k if info["lob"] else "%s|%s|%s" % [info["potencia"], info["dir"], info["metodo"]]
			if not por_grupo.has(grupo) or mejor["err"] < por_grupo[grupo]["err"]:
				por_grupo[grupo] = mejor
		var estilo: String = n.trim_prefix("pk_runup").trim_prefix("_")
		var errores := []
		for grupo: String in por_grupo:
			var m: Dictionary = por_grupo[grupo]
			var k: String = m["kick"]
			var info: Dictionary = remates[k]
			var nombre := "remate_%s_%s" % [estilo if estilo != "" else "base", k.trim_prefix("kick_")]
			var unida := _unir(carrera, lib.get_animation(k), m["fin"], m["kf"])
			lib.add_animation(nombre, unida)
			errores.append(m["err"])
			salida.append({"anim": nombre, "estilo": estilo, "potencia": info["potencia"],
				"dir": info["dir"], "t": (int(m["fin"]) + int(info["golpe"]) - int(m["kf"])) / FPS, "metodo": info["metodo"], "lob": info["lob"]})
		errores.sort()
		print("%-22s %2d remates, error de union %.3f .. %.3f m" % [n, errores.size(), errores[0], errores[-1]])
	return salida

## Carrera hasta el cuadro fin + remate desde kf, alineando la cadera y el giro
## horizontal del remate con los de la carrera, y con un fundido corto.
func _unir(carrera: Animation, kick: Animation, fin: int, kf: int) -> Animation:
	var pc := _pistas_de(carrera)
	var pk := _pistas_de(kick)
	var hc := carrera.position_track_interpolate(pc["_pos"], fin / FPS)
	var hk := kick.position_track_interpolate(pk["_pos"], kf / FPS)
	var giro := Quaternion(Vector3.UP, _yaw(carrera.rotation_track_interpolate(pc[CADERA], fin / FPS)) - _yaw(kick.rotation_track_interpolate(pk[CADERA], kf / FPS)))
	var fundido := mini(FUNDIDO, kf)
	var cuadros_kick := roundi(kick.length * FPS)
	var d := Animation.new()
	d.step = 1.0 / FPS
	d.length = (fin + cuadros_kick - kf) / FPS

	var t_pos := d.add_track(Animation.TYPE_POSITION_3D)
	d.track_set_path(t_pos, carrera.track_get_path(pc["_pos"]))
	for f in fin + cuadros_kick - kf + 1:
		var p: Vector3
		var en_kick := func(c: int) -> Vector3:
			var v := kick.position_track_interpolate(pk["_pos"], c / FPS) - hk
			return (giro * Vector3(v.x, v.y, v.z)) + hc
		if f <= fin - fundido:
			p = carrera.position_track_interpolate(pc["_pos"], f / FPS)
		elif f <= fin:
			var w := (f - (fin - fundido)) / float(maxi(fundido, 1))
			p = carrera.position_track_interpolate(pc["_pos"], f / FPS).lerp(en_kick.call(kf - fin + f), w)
		else:
			p = en_kick.call(kf + f - fin)
		d.position_track_insert_key(t_pos, f / FPS, p)

	for hueso: String in pc:
		if hueso == "_pos":
			continue
		var t := d.add_track(Animation.TYPE_ROTATION_3D)
		d.track_set_path(t, carrera.track_get_path(pc[hueso]))
		var es_cadera := hueso == CADERA
		for f in fin + cuadros_kick - kf + 1:
			var q: Quaternion
			if f <= fin - fundido:
				q = carrera.rotation_track_interpolate(pc[hueso], f / FPS)
			else:
				var ck := kf + f - fin
				var qk := kick.rotation_track_interpolate(pk[hueso], ck / FPS)
				if es_cadera:
					qk = giro * qk
				if f <= fin:
					var w := (f - (fin - fundido)) / float(maxi(fundido, 1))
					q = carrera.rotation_track_interpolate(pc[hueso], f / FPS).slerp(qk, w)
				else:
					q = qk
			d.rotation_track_insert_key(t, f / FPS, q)
	return d

## Mide cada remate unido en el personaje. Ademas gira el clip entero alrededor
## del punto de golpe: asi todos los remates de un estilo arrancan del mismo lugar
## (el pateador espera ahi sin saber a donde va a patear) y siempre desde la
## izquierda de la pelota, como un diestro. Cada estilo tiene su angulo.
func _medir_remates(pateador: Node3D, ap: AnimationPlayer, sk: Skeleton3D, remates: Array) -> Array:
	var raiz := pateador.global_position
	# Se descartan los que quedarian torcidos respecto del tiro (hay que girarlos
	# demasiado) o con una carrera demasiado corta. El radio de cada estilo es el
	# menor de los que quedan.
	var radios := {}
	var utiles := []
	for r: Dictionary in remates:
		var t: float = r["t"]
		var a := "pes/" + str(r["anim"])
		_pose(ap, sk, a, t)
		var dedo := _pos(sk, "mixamorig1RightToeBase")
		_pose(ap, sk, a, maxf(t - DURACION_MAXIMA_CARRERA, 0.0))
		var c := _pos(sk, CADERA)
		var radio := minf(Vector2(c.x - dedo.x, c.z - dedo.z).length(), DISTANCIA_CARRERA)
		_pose(ap, sk, a, _buscar_inicio(ap, sk, a, t, dedo, radio))
		c = _pos(sk, CADERA)
		var giro := float(ANGULO_CARRERA.get(r["estilo"], -8.0)) - rad_to_deg(atan2(c.x - dedo.x, c.z - dedo.z))
		_pose(ap, sk, a, minf(t + TIEMPO_AVANCE_REMATE, ap.get_animation(a).length))
		var despues := _pos(sk, CADERA)
		var avance := Vector2(despues.x - dedo.x, despues.z - dedo.z).length()
		var dedo_alto: bool = r["lob"] and dedo.y > ALTURA_MAXIMA_DEDO_LOB
		if radio < RADIO_MINIMO or absf(wrapf(giro, -180.0, 180.0)) > GIRO_MAXIMO or avance > AVANCE_MAXIMO_REMATE or dedo_alto:
			# Sacar el clip que el reproductor tiene puesto lo hace caerse.
			ap.stop()
			ap.get_animation_library("pes").remove_animation(r["anim"])
			continue
		utiles.append(r)
		radios[r["estilo"]] = minf(radios.get(r["estilo"], DISTANCIA_CARRERA), radio)
	ap.stop()
	remates = utiles
	print("radio de carrera por estilo: ", radios)

	for r: Dictionary in remates:
		var anim := "pes/" + str(r["anim"])
		var a := ap.get_animation(anim)
		var t: float = r["t"]
		_pose(ap, sk, anim, t)
		var dedo := _pos(sk, "mixamorig1RightToeBase")
		var radio: float = radios[r["estilo"]]
		var inicio := _buscar_inicio(ap, sk, anim, t, dedo, radio)
		_pose(ap, sk, anim, inicio)
		var c := _pos(sk, CADERA)
		var angulo_actual := atan2(c.x - dedo.x, c.z - dedo.z)
		var angulo_estilo := deg_to_rad(float(ANGULO_CARRERA.get(r["estilo"], -8.0)))
		_girar_clip(a, angulo_estilo - angulo_actual, sk.global_transform.affine_inverse() * dedo)
		# Volver a soltar la cache del reproductor: el clip cambio.
		ap.stop()
		_pose(ap, sk, anim, t)
		var dedo_final := _pos(sk, "mixamorig1RightToeBase") - raiz
		_pose(ap, sk, anim, t - 1.0 / FPS)
		var dir := (dedo_final - (_pos(sk, "mixamorig1RightToeBase") - raiz)).normalized()
		_pose(ap, sk, anim, inicio)
		var cadera_inicio := _pos(sk, CADERA) - raiz
		r["dedo"] = [dedo_final.x, dedo_final.y, dedo_final.z]
		r["dir_pie"] = [dir.x, dir.y, dir.z]
		r["inicio"] = inicio
		r["cadera_inicio"] = [cadera_inicio.x, cadera_inicio.y, cadera_inicio.z]
		r["giro_grados"] = rad_to_deg(angulo_estilo - angulo_actual)
	return remates

func _buscar_inicio(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float, dedo: Vector3, radio: float) -> float:
	var f := roundi(t * FPS)
	var inicio := t
	while f >= 0:
		_pose(ap, sk, anim, f / FPS)
		var c := _pos(sk, CADERA)
		if Vector2(c.x - dedo.x, c.z - dedo.z).length() > radio:
			break
		inicio = f / FPS
		f -= 1
	return inicio

## Gira un clip sin comprimir alrededor del eje vertical que pasa por pivote
## (en espacio del esqueleto).
func _girar_clip(a: Animation, angulo: float, pivote: Vector3) -> void:
	var q := Quaternion(Vector3.UP, angulo)
	var pista := _pistas_de(a)
	var tp: int = pista["_pos"]
	for k in a.track_get_key_count(tp):
		var p: Vector3 = a.track_get_key_value(tp, k)
		var rel := p - pivote
		rel = q * Vector3(rel.x, 0.0, rel.z) + Vector3(0.0, rel.y, 0.0)
		a.track_set_key_value(tp, k, pivote + rel)
	var tr: int = pista[CADERA]
	for k in a.track_get_key_count(tr):
		a.track_set_key_value(tr, k, q * (a.track_get_key_value(tr, k) as Quaternion))

func _empalmar_remates(remates: Array, lib: AnimationLibrary) -> void:
	var goles := []
	var fallos := []
	for n: String in lib.get_animation_list():
		if n.begins_with("gdml_pk_goal_shoot"):
			goles.append(n)
		elif n.begins_with("gdml_pk_miss_shoot"):
			fallos.append(n)
	# Muchas reacciones siguen corriendo 2-4 m hacia el arco antes de frenar: en
	# un penal el jugador llegaria hasta el arquero.
	goles = goles.filter(func(n: String): return _avance_maximo(lib.get_animation(n)) <= AVANCE_MAXIMO_REACCION)
	fallos = fallos.filter(func(n: String): return _avance_maximo(lib.get_animation(n)) <= AVANCE_MAXIMO_REACCION)
	print("reacciones del pateador: goles %s, fallos %s" % [goles, fallos])
	var pg := _poses_iniciales(lib, goles, 14)
	var pf := _poses_iniciales(lib, fallos, 14)
	var errores := []
	for r: Dictionary in remates:
		var a := lib.get_animation(r["anim"])
		var desde: float = r["t"] + 0.35
		var hasta := a.length
		r["sig"] = {"gol": _mejor_empalme(a, desde, hasta, pg, COSTO_ESPERA_REACCION), "fallo": _mejor_empalme(a, desde, hasta, pf, COSTO_ESPERA_REACCION)}
		errores.append(r["sig"]["gol"]["err"])
		errores.append(r["sig"]["fallo"]["err"])
	errores.sort()
	print("empalme remate->reaccion: mediana %.3f m, peor %.3f m" % [errores[errores.size() / 2], errores[-1]])

func _clip_continuo(a: Animation) -> bool:
	var pista := _pistas_de(a)["_pos"] as int
	var prev := a.position_track_interpolate(pista, 0.0)
	var t := 1.0 / FPS
	while t <= a.length:
		var p := a.position_track_interpolate(pista, t)
		if p.distance_to(prev) * 0.01 > 0.3:
			return false
		prev = p
		t += 1.0 / FPS
	return true

func _avance_maximo(a: Animation) -> float:
	var pista := _pistas_de(a)["_pos"] as int
	var inicio := a.position_track_interpolate(pista, 0.0)
	var maximo := 0.0
	var t := 0.0
	while t <= a.length:
		maximo = maxf(maximo, (a.position_track_interpolate(pista, t).z - inicio.z) * 0.01)
		t += 0.1
	return maximo

# --- Atajadas -------------------------------------------------------------------

## Como sigue cada atajada segun termine la jugada. Se calcula para el clip
## original; el espejado usa el mismo candidato espejado.
func _empalmar_atajadas(atajadas: Array, lib: AnimationLibrary) -> void:
	var grupos := {"ataja": [], "rebote": [], "gol": []}
	for n: String in lib.get_animation_list():
		if n.ends_with(SUFIJO_ESPEJO):
			pass
		if n.begins_with("gdml_pk_miss_gk_connect01_catch") or n.begins_with("gdml_pk_win_gk_connect01_catch") or n.begins_with("gkrise_sideways_catch") or n.begins_with("dm_oop_gk_pk_riseup_catch"):
			grupos["ataja"].append(n)
		elif n.begins_with("gdml_pk_miss_gk_connect01_rise") or n.begins_with("dm_oop_gk_pk_riseup_0"):
			grupos["rebote"].append(n)
		elif n.begins_with("gdml_pk_goal_gk_connect01_rise"):
			grupos["gol"].append(n)
		# AfterSideRun se desliza 3 m de costado: saca al arquero del arco por el palo.
		if n.begins_with("gkrise_faceup") or n.begins_with("gkrise_sideways_0") or (n.begins_with("gksavingCancel") and not n.contains("AfterSideRun")):
			grupos["rebote"].append(n)
			grupos["gol"].append(n)
	var poses := {}
	for g: String in grupos:
		# Algunos clips traen la cadera saltando adentro (PES los corta con otro).
		grupos[g] = grupos[g].filter(func(n: String): return _clip_continuo(lib.get_animation(n)) and not _se_cae(lib.get_animation(n)))
		poses[g] = _poses_iniciales(lib, grupos[g], 8)
		print("candidatos ", g, ": ", grupos[g].size())
	var con_espejos := []
	for n: String in LAMENTOS_ARQUERO:
		con_espejos.append(n)
		con_espejos.append(n + SUFIJO_ESPEJO)
	var poses_lamento := _poses_iniciales(lib, con_espejos, 14)
	var por_base := {}
	var errores := []
	for e: Dictionary in atajadas:
		if e["espejo"]:
			continue
		var a := lib.get_animation(e["base"])
		var desde: float = minf(float(e["t"]) + 0.3, a.length)
		var sig := {}
		for g: String in grupos:
			sig[g] = _mejor_empalme(a, desde, a.length, poses[g])
			errores.append(sig[g]["err"])
		sig["gol"]["cola"] = _lamento_tras(lib, sig["gol"]["anim"], poses_lamento)
		por_base[e["base"]] = sig
	for e: Dictionary in atajadas:
		var sig: Dictionary = por_base[e["base"]]
		if not e["espejo"]:
			e["sig"] = sig
			continue
		var espejado := {}
		for g: String in sig:
			var m: Dictionary = (sig[g] as Dictionary).duplicate()
			var nombre: String = m["anim"]
			m["anim"] = _otro_lado(nombre)
			if m.has("cola") and not (m["cola"] as Dictionary).is_empty():
				var cola: Dictionary = (m["cola"] as Dictionary).duplicate()
				cola["anim"] = _otro_lado(cola["anim"])
				m["cola"] = cola
			espejado[g] = m
		e["sig"] = espejado
	errores.sort()
	print("empalme atajada->reaccion: mediana %.3f m, p90 %.3f m, peor %.3f m" % [errores[errores.size() / 2], errores[errores.size() * 9 / 10], errores[-1]])

static func _otro_lado(nombre: String) -> String:
	return nombre.trim_suffix(SUFIJO_ESPEJO) if nombre.ends_with(SUFIJO_ESPEJO) else nombre + SUFIJO_ESPEJO

func _se_cae(a: Animation) -> bool:
	var pista := _pistas_de(a)["_pos"] as int
	var inicio := a.position_track_interpolate(pista, 0.0).y
	var t := 0.0
	while t <= a.length:
		if (inicio - a.position_track_interpolate(pista, t).y) * 0.01 > CAIDA_MAXIMA_REACCION:
			return true
		t += 1.0 / FPS
	return false

## Con que lamento seguir cuando termina de levantarse: el que mejor continua la
## pose en la que quedo. {} si ya se lamenta en ese clip o si ninguno le queda bien.
func _lamento_tras(lib: AnimationLibrary, anim: String, poses: Dictionary) -> Dictionary:
	if anim.begins_with("gdml_pk_goal"):
		return {}
	var a := lib.get_animation(anim)
	var m := _mejor_empalme(a, a.length, a.length, poses)
	var cuadro := roundi(float(m["t_inicio"]) * FPS)
	var diferencia: float = absf(_pose_clip(a, a.length)["_alto"] - (poses[m["anim"]][cuadro] as Dictionary)["_alto"])
	if diferencia > DIFERENCIA_MAXIMA_LAMENTO:
		return {}
	return {"anim": m["anim"], "t_inicio": m["t_inicio"]}

## Clips que se pueden repetir en loop sin que se note: el ultimo cuadro y el
## primero casi coinciden, tambien en la posicion de la cadera.
func _esperas(lib: AnimationLibrary, prefijo: String, solo_loop := true) -> Array:
	var salida := []
	for n: String in lib.get_animation_list():
		if not n.begins_with(prefijo) or n.ends_with(SUFIJO_ESPEJO):
			continue
		var a := lib.get_animation(n)
		var p := _pistas_de(a)
		var e := _dif_pose(_pose_clip(a, 0.0), _pose_clip(a, a.length))
		var salto: float = a.position_track_interpolate(p["_pos"], 0.0).distance_to(a.position_track_interpolate(p["_pos"], a.length)) * 0.01
		print("espera %-30s %.2f s  pose %.3f m  cadera %.3f m" % [n, a.length, e, salto])
		var lateral := 0.0
		var t := 0.0
		while t <= a.length:
			lateral = maxf(lateral, absf(a.position_track_interpolate(p["_pos"], t).x - a.position_track_interpolate(p["_pos"], 0.0).x) * 0.01)
			t += 0.05
		if lateral > ESPERA_LATERAL_MAXIMA:
			continue
		if not solo_loop or (e < 0.12 and salto < 0.25):
			salida.append(n)
	return salida
