extends Node

# Mide en que cuadro la mano de cada animacion llega al punto de contacto.
# Recorre todas cuadro por cuadro (30 fps) y anota:
#   - contacto: el cuadro del contact_time del DiveAnimData
#   - ventana: cuadros en que la mano esta a menos de 15 cm de ese punto
#     (la pelota mide 22 cm: en esa ventana la toca)
#   - pico: cuadro en que la mano llega mas lejos hacia su objetivo

const FPS := 30.0
const RADIO := 0.15

var gk: Node3D
var ap: AnimationPlayer
var esq: Skeleton3D
var rutas: Array = []
var i := 0
var f := 0
var datos: DiveAnimData
var dist: Array = []
var avance: Array = []
var filas: Array = []


func _ready() -> void:
	var g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	gk = g.get_node("Goalkeeper")
	gk.set_process(false)
	gk.set_physics_process(false)
	ap = g.get_node("Goalkeeper/player/AnimationPlayer")
	esq = g.get_node("Goalkeeper/player/Node/Skeleton3D")
	for a in DirAccess.get_files_at("res://resources/animresources"):
		if a.ends_with(".tres"):
			rutas.append("res://resources/animresources/" + a)
	rutas.sort()


func _mano() -> Vector3:
	esq.force_update_all_bone_transforms()
	var b := esq.find_bone(datos.hand_bone)
	return esq.global_transform * esq.get_bone_global_pose(b).origin - gk.global_position


func _process(_d: float) -> void:
	if i >= rutas.size():
		_imprimir()
		get_tree().quit()
		return
	if f == 0:
		datos = load(rutas[i])
		ap.play(datos.anim_name)
		ap.pause()
		dist = []
		avance = []
	ap.seek(f / FPS, true)
	var m := _mano()
	dist.append(m.distance_to(datos.canonical_target))
	# cuanto avanzo la mano hacia el objetivo desde el primer cuadro
	avance.append(m.distance_to(Vector3.ZERO) if f == 0 else 0.0)
	if f == 0:
		avance[0] = 0.0
		set_meta("m0", m)
	else:
		var m0: Vector3 = get_meta("m0")
		var dir := (datos.canonical_target - m0).normalized()
		avance[f] = (m - m0).dot(dir)
	f += 1
	if f / FPS > ap.current_animation_length:
		var ventana := []
		for k in dist.size():
			if dist[k] < RADIO:
				ventana.append(k)
		var pico := 0
		for k in avance.size():
			if avance[k] > avance[pico]:
				pico = k
		filas.append([datos.anim_name.trim_prefix("blender/"), "SAVE" if datos.tipo == 0 else "DIVE",
			int(round(datos.contact_time * FPS)), datos.contact_time,
			"%d-%d" % [ventana[0], ventana[-1]] if ventana.size() > 0 else "-", pico])
		f = 0
		i += 1


func _imprimir() -> void:
	print("animacion          tipo      contacto       ventana (<15cm)   mano mas estirada")
	for r in filas:
		print("%-18s %-9s cuadro %d (%.2f s)   cuadros %-8s   cuadro %d" % r)
