class_name PesAnimaciones
extends RefCounted

## Animaciones de PES 2021 armadas por tools/pes_construir.gd. Viven en
## animaciones_pes/, que no esta en git: si la carpeta no existe, los personajes
## siguen usando sus animaciones de siempre.

const DIR := "res://animaciones_pes/"
const LIBRERIA := "pes"
const LIBRERIA_FOTO := "pes_foto"
const CADERA := "mixamorig1Hips"
const PesPiso := preload("res://scripts/pes_piso.gd")

static var _datos: Dictionary = {}
static var _escenas: Dictionary = {}
## Las escenas de PES vienen con las medidas de sus jugadores; los nuestros son mas chicos
## (la cadera queda al 91 %), asi que las distancias entre ellos se achican igual.
const ESCALA_ESCENAS := 0.91

static func disponible() -> bool:
	return ResourceLoader.exists(DIR + "arquero.res") and ResourceLoader.exists(DIR + "pateador.res") \
		and FileAccess.file_exists(DIR + "datos.json")

static func datos() -> Dictionary:
	if _datos.is_empty():
		_datos = JSON.parse_string(FileAccess.get_file_as_string(DIR + "datos.json"))
	return _datos

## Escenas de PES (tools/pes_extraer_escenas.py): por corte, el clip, el lugar y el giro
## de cada actor.
static func escenas() -> Dictionary:
	if _escenas.is_empty() and FileAccess.file_exists(DIR + "escenas.json"):
		_escenas = JSON.parse_string(FileAccess.get_file_as_string(DIR + "escenas.json"))
	return _escenas

## Pone a un actor de una escena de PES. En PES x va a lo largo de la cancha (hacia el
## arco es -x) y z a lo ancho; aca el arco esta hacia -z. La conversion se eligio
## midiendo hacia donde apuntan los pies: con esta, en la ronda de 11 todos miran al
## centro, las filas miran al arco y cada mano cae sobre el hombro del vecino.
## `origen` es donde queda el (0, 0, 0) de la escena. Devuelve el segundo del clip en
## el que arranca.
static func colocar_actor(raiz: Node3D, ap: AnimationPlayer, actor: Dictionary, origen: Vector3) -> float:
	var p: Array = actor["pos"]
	var lugar := Vector3(float(p[2]) * ESCALA_ESCENAS, float(p[1]), float(p[0]) * ESCALA_ESCENAS)
	# Un giro de exactamente 0 en PES es "sin giro" y equivale a media vuelta: con eso, en el
	# abrazo final los cinco que llegan corriendo terminan juntos (con 0 corren en paralelo).
	var giro := float(actor["giro"]) if float(actor["giro"]) != 0.0 else 180.0
	raiz.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-giro - 90.0)), origen + lugar)
	var anim := "pes/" + str(actor["clip"])
	var largo := ap.get_animation(anim).length
	# El dato que acompana a cada actor es en que momento arranca, en sesentavos de segundo.
	var desde := fmod(float(actor["extra"]) / 60.0, largo) if float(actor["extra"]) < 1.0e6 else 0.0
	ap.speed_scale = 1.0
	ap.play(anim, 0.0)
	ap.seek(desde, true)
	return desde

static func cargar_libreria(ap: AnimationPlayer, archivo: String) -> void:
	if not ap.has_animation_library(LIBRERIA):
		ap.add_animation_library(LIBRERIA, load(DIR + archivo))

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
