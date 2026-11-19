extends Node

## Graba lo que pasa en la cancha (las poses del pateador y del arquero, y la pelota) y
## despues lo reproduce en camara lenta, sin volver a simular nada: la repeticion es
## exactamente lo que se vio. Graba siempre los ultimos segundos; al haber gol se corta
## la grabacion y se reproduce desde un poco antes de la patada.

## Cuantos segundos se guardan como maximo.
const MEMORIA := 7.0
## Desde cuanto antes de la patada se muestra.
const ANTES_DE_LA_PATADA := 0.75
const CAMARA_LENTA := 0.45

var _cuadros: Array[Dictionary] = []
var _grabando := true
var _t := 0.0
var _t_patada := -1.0
var _personajes: Array[Dictionary] = []
var _pelota: Node3D
var _reproduciendo := false

func _init(kicker: PlayerKicker, arquero: PlayerGoalkeeper, pelota: Node3D) -> void:
	name = "Repeticion"
	# Despues de las animaciones y del control del piso: se graba la pose final.
	process_priority = 200
	for p: Node3D in [kicker, arquero]:
		_personajes.append({"nodo": p, "sk": p.skeleton, "ap": p.animation_player})
	_pelota = pelota
	kicker.ball_launch_requested.connect(func(_v: Vector3): _t_patada = _t)

func _process(delta: float) -> void:
	if _reproduciendo or not _grabando:
		return
	_t += delta
	var cuadro := {"t": _t, "pelota": _pelota.global_transform, "gente": []}
	for p in _personajes:
		var sk: Skeleton3D = p["sk"]
		var rot := PackedFloat32Array()
		var pos := PackedVector3Array()
		for b in sk.get_bone_count():
			var q := sk.get_bone_pose_rotation(b)
			rot.append_array([q.x, q.y, q.z, q.w])
			pos.append(sk.get_bone_pose_position(b))
		(cuadro["gente"] as Array).append({"raiz": (p["nodo"] as Node3D).global_transform, "sk": sk.global_transform, "rot": rot, "pos": pos})
	_cuadros.append(cuadro)
	while not _cuadros.is_empty() and _t - float(_cuadros[0]["t"]) > MEMORIA:
		_cuadros.pop_front()

## Deja de grabar dentro de `segundos` (lo que se quiere ver despues del gol).
func cortar_en(segundos: float) -> void:
	await get_tree().create_timer(segundos).timeout
	_grabando = false

func volver_a_grabar() -> void:
	_cuadros.clear()
	_grabando = true
	_t_patada = -1.0

## Cuantos segundos dura la repeticion (ya en camara lenta). 0 si no hay nada.
func duracion() -> float:
	if _cuadros.is_empty() or _t_patada < 0.0:
		return 0.0
	return (float(_cuadros[-1]["t"]) - _desde()) / CAMARA_LENTA

func _desde() -> float:
	return maxf(_t_patada - ANTES_DE_LA_PATADA, float(_cuadros[0]["t"]))

## Momento de la grabacion que corresponde a `t` segundos de repeticion.
func tiempo_grabado(t: float) -> float:
	return _desde() + t * CAMARA_LENTA

func t_patada() -> float:
	return _t_patada

## Prepara a los personajes para que los mueva la repeticion.
func empezar() -> void:
	_reproduciendo = true
	for p in _personajes:
		(p["ap"] as AnimationPlayer).active = false
		(p["nodo"] as Node).set_physics_process(false)
		(p["nodo"] as Node3D).visible = true
	if _pelota is RigidBody3D:
		(_pelota as RigidBody3D).freeze = true
	_pelota.visible = true

func terminar() -> void:
	_reproduciendo = false
	for p in _personajes:
		(p["ap"] as AnimationPlayer).active = true
		(p["nodo"] as Node).set_physics_process(true)
	volver_a_grabar()

## Pone todo como estaba en el momento grabado `t`, interpolando entre dos cuadros.
func mostrar(t: float) -> void:
	var i := 0
	while i < _cuadros.size() - 2 and float(_cuadros[i + 1]["t"]) < t:
		i += 1
	var a: Dictionary = _cuadros[i]
	var b: Dictionary = _cuadros[mini(i + 1, _cuadros.size() - 1)]
	var largo := float(b["t"]) - float(a["t"])
	var f := clampf((t - float(a["t"])) / largo, 0.0, 1.0) if largo > 0.0 else 0.0
	_pelota.global_transform = (a["pelota"] as Transform3D).interpolate_with(b["pelota"], f)
	for k in _personajes.size():
		var p: Dictionary = _personajes[k]
		var ga: Dictionary = a["gente"][k]
		var gb: Dictionary = b["gente"][k]
		(p["nodo"] as Node3D).global_transform = (ga["raiz"] as Transform3D).interpolate_with(gb["raiz"], f)
		var sk: Skeleton3D = p["sk"]
		sk.global_transform = (ga["sk"] as Transform3D).interpolate_with(gb["sk"], f)
		var ra: PackedFloat32Array = ga["rot"]
		var rb: PackedFloat32Array = gb["rot"]
		var pa: PackedVector3Array = ga["pos"]
		var pb: PackedVector3Array = gb["pos"]
		for h in sk.get_bone_count():
			var qa := Quaternion(ra[h * 4], ra[h * 4 + 1], ra[h * 4 + 2], ra[h * 4 + 3])
			var qb := Quaternion(rb[h * 4], rb[h * 4 + 1], rb[h * 4 + 2], rb[h * 4 + 3])
			sk.set_bone_pose_rotation(h, qa.slerp(qb, f))
			sk.set_bone_pose_position(h, pa[h].lerp(pb[h], f))
