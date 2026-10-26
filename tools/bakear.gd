extends Node

# Calcula el canonical_target de cada DiveAnimData: reproduce la animacion,
# la frena en su contact_time y lee donde quedo la mano del contacto.
# Hace lo mismo que scripts/bake_animations.gd pero sin abrir el editor.

const Z := ["TOP_LEFT", "TOP_CENTER", "TOP_RIGHT", "MID_LEFT", "MID_CENTER", "MID_RIGHT", "BOTTOM_LEFT", "BOTTOM_CENTER", "BOTTOM_RIGHT"]
const T := ["SAVE", "DIVE"]

var gk: Node3D
var ap: AnimationPlayer
var esq: Skeleton3D
var rutas: Array = []
var i := 0
var base: Vector3
var faltan := 0


func _ready() -> void:
	var g = load("res://scenes/game.tscn").instantiate()
	add_child(g)
	gk = g.get_node("Goalkeeper")
	gk.set_process(false)
	ap = g.get_node("Goalkeeper/player/AnimationPlayer")
	esq = g.get_node("Goalkeeper/player/Node/Skeleton3D")
	base = gk.global_position
	for f in DirAccess.get_files_at("res://resources/animresources"):
		if f.ends_with(".tres"):
			rutas.append("res://resources/animresources/" + f)
	rutas.sort()


func _process(_d: float) -> void:
	if i >= rutas.size():
		print("--- bakeo terminado. animaciones inexistentes: %d ---" % faltan)
		get_tree().quit()
		return
	var d := load(rutas[i]) as DiveAnimData
	if not ap.has_animation(d.anim_name):
		print("%-26s NO EXISTE la animacion '%s'" % [rutas[i].get_file(), d.anim_name])
		faltan += 1
		i += 1
		return
	# se frena en el contact_time y se lee en el mismo cuadro: si se deja
	# correr un cuadro, la mano ya se movio (en una caida, varios cm)
	ap.play(d.anim_name)
	ap.seek(d.contact_time, true)
	ap.pause()
	esq.force_update_all_bone_transforms()
	var b := esq.find_bone(d.hand_bone)
	d.canonical_target = esq.global_transform * esq.get_bone_global_pose(b).origin - base
	ResourceSaver.save(d, rutas[i])
	print("%-8s %-14s %-34s t=%.2f  mano=(%5.2f, %4.2f, %4.2f)" % [T[d.tipo], Z[d.zone], d.anim_name, d.contact_time, d.canonical_target.x, d.canonical_target.y, d.canonical_target.z])
	i += 1
