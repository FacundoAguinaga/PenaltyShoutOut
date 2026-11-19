class_name PesAnimaciones
extends RefCounted

## Animaciones de PES 2021 armadas por tools/pes_construir.gd. Viven en
## animaciones_pes/, que no esta en git: si la carpeta no existe, los personajes
## siguen usando sus animaciones de siempre.

const DIR := "res://animaciones_pes/"
const LIBRERIA := "pes"
const LIBRERIA_FOTO := "pes_foto"
## Los clips de los festejos grupales que la build descarta (tools/pes_construir.gd). Se
## cargan solo si el editor de festejos activo alguno, o en el editor.
const GRUPALES_EXTRA := "grupales_extra.res"
const CADERA := "mixamorig1Hips"
const PesPiso := preload("res://scripts/pes_piso.gd")

static var _datos: Dictionary = {}
static var _escenas: Dictionary = {}
## Las escenas de PES vienen con las medidas de sus jugadores; los nuestros son mas chicos
## (la cadera queda al 91 %), asi que en las escenas quietas (la ronda, las filas) las
## distancias entre ellos se achican igual y las manos llegan a los hombros.
const ESCALA_ESCENAS := 0.91
## Pero el retarget achica solo la altura de la cadera, no lo que se desplaza: un clip que
## en PES corre 23,7 m aca corre 23,7 m. En las escenas en que corren, los lugares van sin
## achicar; si no, dos que arrancan a 15 m se encuentran 1,4 m corridos.
const ESCALA_CON_CARRERA := 1.0

static func disponible() -> bool:
	return ResourceLoader.exists(DIR + "arquero.res") and ResourceLoader.exists(DIR + "pateador.res") \
		and FileAccess.file_exists(DIR + "datos.json")

static func datos() -> Dictionary:
	if _datos.is_empty():
		_datos = JSON.parse_string(FileAccess.get_file_as_string(DIR + "datos.json"))
		# Los retoques a mano del editor de festejos (FestejosAjustes).
		# Los descartados por la build entran si se activaron a mano.
		var grupales: Array = _datos.get("festejos_grupales", [])
		for g: Dictionary in _datos.get("festejos_grupales_descartados", []):
			if FestejosAjustes.activado(str(g["corte"])):
				grupales.append(g)
		_datos["festejos_grupales"] = FestejosAjustes.aplicar_a_grupales(grupales)
		_datos["festejos_gol"] = (_datos.get("festejos_gol", []) as Array).filter(func(n: String): return not FestejosAjustes.desactivado(n))
	return _datos

## Vuelve a leer todo (despues de guardar ajustes en el editor de festejos).
static func recargar() -> void:
	_datos = {}
	_escenas = {}
	FestejosAjustes._cargado = false

## Escenas de PES (tools/pes_extraer_escenas.py): por corte, el clip, el lugar y el giro
## de cada actor.
static func escenas() -> Dictionary:
	if _escenas.is_empty() and FileAccess.file_exists(DIR + "escenas.json"):
		_escenas = JSON.parse_string(FileAccess.get_file_as_string(DIR + "escenas.json"))
		FestejosAjustes.aplicar_a_escenas(_escenas)
	return _escenas

## Un lugar de una escena de PES, aca. En PES x va a lo largo de la cancha (hacia el arco
## es -x) y z a lo ancho; aca el arco esta hacia -z. Tiene que ser una rotacion y no un
## espejo: los clips no se espejan, y con x y z solo intercambiados (como estuvo antes)
## cada uno quedaba del otro lado de su companero y el que abrazaba lo hacia al aire.
static func lugar_pes(x: float, y: float, z: float, escala := ESCALA_ESCENAS) -> Vector3:
	return Vector3(-z * escala, y, x * escala)

## Pone a un actor de una escena de PES. La conversion se eligio midiendo con los datos de
## PES solos: el camino de cada clip girado `giro` y puesto en su lugar. Asi, en los 131
## festejos grupales el 88 % de los jugadores llega a tocar a alguien (mediana 0,25 m); con
## cualquier otra lectura del giro, a lo sumo el 67 %. El giro 0 es 0: en el abrazo final
## (todos en 0) terminan juntos.
## `origen` es donde queda el (0, 0, 0) de la escena. Arranca el clip en `desde`: los clips
## de una escena estan sincronizados en su propio tiempo (en la ronda de 11 todos se
## separan entre los 9 y los 11 s del clip), asi que todos van desde el mismo segundo.
## `escala` achica las distancias; para lugares de la cancha (el arbitro, el arco) va 1.
## Si el actor trae un ajuste del editor de festejos (FestejosAjustes), se lo corre, se lo
## gira y se adelanta o atrasa su clip.
static func colocar_actor(raiz: Node3D, ap: AnimationPlayer, actor: Dictionary, origen: Vector3, escala := ESCALA_ESCENAS, desde := 0.0) -> void:
	raiz.global_transform = lugar_actor(actor, origen, escala)
	ap.speed_scale = 1.0
	ap.play("pes/" + str(actor["clip"]), 0.0)
	seek_actor(ap, actor, desde)

## Donde va la raiz de un actor de una escena, con su ajuste.
static func lugar_actor(actor: Dictionary, origen: Vector3, escala := ESCALA_ESCENAS) -> Transform3D:
	var p: Array = actor["pos"]
	var aj: Dictionary = actor.get("ajuste", {})
	var lugar := lugar_pes(float(p[0]), float(p[1]), float(p[2]), escala)
	lugar += Vector3(float(aj.get("x", 0.0)), 0.0, float(aj.get("z", 0.0)))
	var giro := float(actor["giro"]) + 90.0 + float(aj.get("giro", 0.0))
	return Transform3D(Basis(Vector3.UP, deg_to_rad(giro)), origen + lugar)

## Lleva el clip de un actor al segundo `t` de la escena, con su desfase. Con desfase
## negativo, al principio espera quieto en el primer cuadro.
static func seek_actor(ap: AnimationPlayer, actor: Dictionary, t: float) -> void:
	var en_clip := t + float((actor.get("ajuste", {}) as Dictionary).get("desfase", 0.0))
	ap.seek(maxf(en_clip, 0.0), true)
	if en_clip < -0.01 and ap.is_inside_tree():
		ap.speed_scale = 0.0
		var clip := ap.current_animation
		ap.get_tree().create_timer(-en_clip, false).timeout.connect(func():
			if is_instance_valid(ap) and ap.current_animation == clip:
				ap.speed_scale = 1.0)

## `con_descartados` suma siempre los clips de GRUPALES_EXTRA (para el editor); si no, se
## suman solo cuando hay algun festejo descartado activado.
static func cargar_libreria(ap: AnimationPlayer, archivo: String, con_descartados := false) -> void:
	if ap.has_animation_library(LIBRERIA):
		return
	var lib: AnimationLibrary = load(DIR + archivo)
	if archivo == "pateador.res" and (con_descartados or _hay_descartados_activados()):
		sumar_descartados(lib)
	ap.add_animation_library(LIBRERIA, lib)

static func _hay_descartados_activados() -> bool:
	return (datos().get("festejos_grupales_descartados", []) as Array).any(
		func(g: Dictionary): return FestejosAjustes.activado(str(g["corte"])))

## Agrega a la libreria (la misma para todos los personajes) los clips de GRUPALES_EXTRA.
static func sumar_descartados(lib: AnimationLibrary) -> void:
	if not ResourceLoader.exists(DIR + GRUPALES_EXTRA):
		return
	var extra: AnimationLibrary = load(DIR + GRUPALES_EXTRA)
	for n: StringName in extra.get_animation_list():
		if not lib.has_animation(n):
			lib.add_animation(n, extra.get_animation(n))

## Agrega al personaje el control que mantiene su malla sobre el piso.
static func cuidar_piso(personaje: Node3D, sk: Skeleton3D) -> Node:
	var piso := PesPiso.new(sk, datos()["nube_malla"])
	personaje.add_child(piso)
	return piso

static func v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

## Donde esta la cadera de un clip en el momento t, relativa a la raiz.
static func cadera_en(ap: AnimationPlayer, sk: Skeleton3D, raiz: Node3D, anim: String, t: float) -> Vector3:
	var a := ap.get_animation(anim)
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	return sk.global_transform * a.position_track_interpolate(pista, t) - raiz.global_position

static func _yaw(q: Quaternion) -> float:
	var r := q * Vector3.RIGHT
	if Vector2(r.x, r.z).length() > 0.5:
		return atan2(-r.z, r.x)
	var f := q * Vector3.BACK
	return atan2(f.x, f.z)

## Pasa a otro clip sin que el cuerpo salte, con la raiz en su lugar nuevo.
##
## Fundir dos clips directamente no sirve: cada uno guarda la cadera respecto de
## su propio origen, asi que si la raiz cambia, el fundido arrastra el cuerpo
## metros (y si ademas gira, lo lleva en arco). En cambio se saca una foto de la
## pose actual, se mueve la raiz de golpe reexpresando la foto para que el cuerpo
## no se mueva ni un milimetro, y se funde desde la foto al clip nuevo.
static func transicion(raiz: Node3D, ap: AnimationPlayer, sk: Skeleton3D, raiz_nueva: Transform3D, anim: String, t_inicio: float, fundido: float) -> void:
	var cadera_hueso := sk.find_bone(CADERA)
	var cadera_mundo := sk.global_transform * sk.get_bone_global_pose(cadera_hueso)
	var foto := _animacion_foto(ap, sk)
	for t in foto.get_track_count():
		var hueso := str(foto.track_get_path(t)).get_slice(":", 1)
		if foto.track_get_type(t) == Animation.TYPE_ROTATION_3D and hueso != CADERA:
			foto.track_set_key_value(t, 0, sk.get_bone_pose_rotation(sk.find_bone(hueso)))

	raiz.global_transform = raiz_nueva
	var cadera_nueva := sk.global_transform.affine_inverse() * cadera_mundo
	foto.track_set_key_value(foto.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D), 0, cadera_nueva.origin)
	foto.track_set_key_value(foto.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_ROTATION_3D), 0, cadera_nueva.basis.orthonormalized().get_rotation_quaternion())

	ap.speed_scale = 1.0
	ap.play(LIBRERIA_FOTO + "/foto", 0.0)
	ap.seek(0.0, true)
	ap.play_section(anim, t_inicio, -1.0, fundido)

static func _animacion_foto(ap: AnimationPlayer, sk: Skeleton3D) -> Animation:
	if ap.has_animation(LIBRERIA_FOTO + "/foto"):
		return ap.get_animation(LIBRERIA_FOTO + "/foto")
	var a := Animation.new()
	a.length = 10.0
	var p := a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(p, "Node/Skeleton3D:" + CADERA)
	a.position_track_insert_key(p, 0.0, Vector3.ZERO)
	for b in sk.get_bone_count():
		var t := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(t, "Node/Skeleton3D:" + sk.get_bone_name(b))
		a.rotation_track_insert_key(t, 0.0, Quaternion.IDENTITY)
	var lib := AnimationLibrary.new()
	lib.add_animation("foto", a)
	ap.add_animation_library(LIBRERIA_FOTO, lib)
	return a

## Pone un clip desde el principio, sin fundido (para despues de un corte de camara):
## gira la raiz para que el clip se desplace hacia `direccion` y la deja de modo que
## la cadera arranque en `punto`, o termine ahi si en_el_final. Devuelve donde
## termina la cadera, a la altura del piso.
static func colocar(raiz: Node3D, ap: AnimationPlayer, sk: Skeleton3D, anim: String, punto: Vector3, direccion: Vector3, en_el_final := false) -> Vector3:
	var a := ap.get_animation(anim)
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var relativo := raiz.global_transform.affine_inverse() * sk.global_transform
	var inicio := relativo * a.position_track_interpolate(pista, 0.0)
	var fin := relativo * a.position_track_interpolate(pista, a.length)
	var recorrido := fin - inicio
	var giro := Basis(Vector3.UP, atan2(direccion.x, direccion.z) - atan2(recorrido.x, recorrido.z))
	var origen := punto - giro * (fin if en_el_final else inicio)
	origen.y = 0.0
	raiz.global_transform = Transform3D(giro, origen)
	ap.speed_scale = 1.0
	ap.play(anim, 0.0)
	ap.seek(0.0, true)
	var llegada := origen + giro * fin
	llegada.y = 0.0
	return llegada

## Para donde mira el cuerpo en un clip, con la raiz actual.
static func _frente(sk: Skeleton3D, a: Animation, t: float) -> Vector3:
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_ROTATION_3D)
	var q := sk.global_basis.orthonormalized().get_rotation_quaternion() * a.rotation_track_interpolate(pista, t)
	return (q * Vector3.RIGHT).cross(Vector3.UP).normalized()

## Como colocar, pero mirando en vez de desplazandose: en el segundo `t` del clip la
## cadera queda en `punto` y el cuerpo mira hacia `mirar`. Arranca el clip desde el
## principio (el que llama elige desde donde verlo).
static func colocar_mirando(raiz: Node3D, ap: AnimationPlayer, sk: Skeleton3D, anim: String, punto: Vector3, mirar: Vector3, t := 0.0) -> void:
	var a := ap.get_animation(anim)
	var pista := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var inicio := raiz.global_transform.affine_inverse() * sk.global_transform * a.position_track_interpolate(pista, t)
	var frente := raiz.global_basis.orthonormalized().inverse() * _frente(sk, a, t)
	var giro := Basis(Vector3.UP, atan2(mirar.x, mirar.z) - atan2(frente.x, frente.z))
	var origen := punto - giro * inicio
	origen.y = 0.0
	raiz.global_transform = Transform3D(giro, origen)
	ap.speed_scale = 1.0
	ap.play(anim, 0.0)
	ap.seek(0.0, true)

## Transicion para seguir con un clip desde donde esta el cuerpo: la raiz nueva
## deja la cadera del clip donde esta la actual y mirando para el mismo lado, o
## hacia `mirar` si se pasa una direccion.
static func empalmar(raiz: Node3D, ap: AnimationPlayer, sk: Skeleton3D, anim: String, t_inicio: float, fundido: float, mirar := Vector3.ZERO) -> void:
	var a := ap.get_animation(anim)
	var pista_pos := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_POSITION_3D)
	var pista_rot := a.find_track("Node/Skeleton3D:" + CADERA, Animation.TYPE_ROTATION_3D)
	var base_sk := sk.global_basis.orthonormalized().get_rotation_quaternion()

	var cadera := sk.get_bone_global_pose(sk.find_bone(CADERA))
	var ahora_pos := sk.global_transform * cadera.origin
	var ahora_yaw := _yaw(base_sk * cadera.basis.get_rotation_quaternion())

	var luego_pos := sk.global_transform * a.position_track_interpolate(pista_pos, t_inicio)
	var luego_yaw := _yaw(base_sk * a.rotation_track_interpolate(pista_rot, t_inicio))

	var giro := Basis(Vector3.UP, wrapf(ahora_yaw - luego_yaw, -PI, PI))
	if mirar != Vector3.ZERO:
		var frente := _frente(sk, a, t_inicio)
		giro = Basis(Vector3.UP, atan2(mirar.x, mirar.z) - atan2(frente.x, frente.z))
	var desde := raiz.global_transform
	var hasta := Transform3D(giro * desde.basis, desde.origin)
	var pos_girada := desde.origin + giro * (luego_pos - desde.origin)
	hasta.origin.x += ahora_pos.x - pos_girada.x
	hasta.origin.z += ahora_pos.z - pos_girada.z
	transicion(raiz, ap, sk, hasta, anim, t_inicio, fundido)
