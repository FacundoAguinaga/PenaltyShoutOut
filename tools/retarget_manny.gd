extends Node

## Pasa las animaciones de Cascadeur (esqueleto Unreal "Manny") al esqueleto
## Mixamo del arquero (mixamorig1...).
##
## No se usa el BoneMap del importador porque renombraria los huesos del
## arquero y romperia las animaciones Mixamo que ya tiene la escena.
##
## Para cada hueso mapeado, en espacio de mundo:
##     D(t)  = rot_origen(t) * inversa(rot_origen_reposo)       (cuanto giro)
##     rot_destino(t) = D(t) * inversa(A) * rot_destino_reposo
## A es la rotacion que lleva la direccion del hueso en el reposo de Manny
## (A-pose) a la direccion del mismo hueso en el reposo de Mixamo (T-pose).
## Asi la direccion de cada hueso en el juego es la misma que en Cascadeur
## aunque los reposos sean distintos.
##
## La cadera lleva tambien la posicion (con el desplazamiento del root de
## Cascadeur sumado), escalada por la altura de cadera y corrida para que el
## cuadro 0 arranque en el lugar del arquero: no salta al empezar.
##
## Uso: godot --headless --path . res://tools/retarget_manny.tscn
## Lee Player/Animations/cascadeur_v2/*.fbx y escribe al lado un .res por
## animacion y la libreria arquero_cascadeur_v2.tres ("cascadeur").

const CARPETA := "res://Player/Animations/cascadeur_v2/"
const FPS := 30.0
const PISTA := "Node/Skeleton3D:"

## destino (mixamo, sin prefijo) <- origen (Manny)
const MAPA := {
	"Hips": "pelvis",
	"Spine": "spine_01", "Spine1": "spine_03", "Spine2": "spine_05",
	"Neck": "neck_01", "Head": "head",
	"LeftShoulder": "clavicle_l", "LeftArm": "upperarm_l", "LeftForeArm": "lowerarm_l", "LeftHand": "hand_l",
	"RightShoulder": "clavicle_r", "RightArm": "upperarm_r", "RightForeArm": "lowerarm_r", "RightHand": "hand_r",
	"LeftUpLeg": "thigh_l", "LeftLeg": "calf_l", "LeftFoot": "foot_l", "LeftToeBase": "ball_l",
	"RightUpLeg": "thigh_r", "RightLeg": "calf_r", "RightFoot": "foot_r", "RightToeBase": "ball_r",
}
## hueso -> hueso hijo que marca su direccion, en cada esqueleto
const DIR_DESTINO := {
	"Hips": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Spine2": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftArm", "LeftArm": "LeftForeArm", "LeftForeArm": "LeftHand", "LeftHand": "LeftHandMiddle1",
	"RightShoulder": "RightArm", "RightArm": "RightForeArm", "RightForeArm": "RightHand", "RightHand": "RightHandMiddle1",
	"LeftUpLeg": "LeftLeg", "LeftLeg": "LeftFoot", "LeftFoot": "LeftToeBase",
	"RightUpLeg": "RightLeg", "RightLeg": "RightFoot", "RightFoot": "RightToeBase",
}
const DIR_ORIGEN := {
	"pelvis": "spine_01", "spine_01": "spine_03", "spine_03": "spine_05", "spine_05": "neck_01", "neck_01": "head",
	"clavicle_l": "upperarm_l", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "hand_l": "middle_01_l",
	"clavicle_r": "upperarm_r", "upperarm_r": "lowerarm_r", "lowerarm_r": "hand_r", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "foot_l": "ball_l",
	"thigh_r": "calf_r", "calf_r": "foot_r", "foot_r": "ball_r",
}
const DEDOS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Pinky": "pinky"}

var dst: Skeleton3D
var dst_q: Quaternion          # rotacion del esqueleto destino en el mundo
var dst_xf: Transform3D
var dst_rest_mundo := {}       # nombre -> Quaternion (reposo global en el mundo)
var dst_rest_pos := {}         # nombre -> Vector3 (reposo global en el mundo)
var mapa := {}                 # nombre completo destino -> nombre origen


func _ready() -> void:
	var juego = load("res://scenes/game.tscn").instantiate()
	add_child(juego)
	var gk = juego.get_node("Goalkeeper")
	gk.set_process(false)
	gk.set_physics_process(false)
	dst = juego.get_node("Goalkeeper/player/Node/Skeleton3D")
	juego.get_node("Goalkeeper/player/AnimationPlayer").stop()
	dst.reset_bone_poses()
	dst_xf = dst.global_transform
	dst_q = dst_xf.basis.get_rotation_quaternion()
	# El "rest" del esqueleto de la escena es una pose cualquiera; la pose de
	# referencia de verdad (T-pose) es la del skin de la malla: la inversa de
	# cada bind pose es donde estaba ese hueso cuando se pego la malla.
	var malla: MeshInstance3D = dst.get_node("Ch36")
	var skin: Skin = malla.skin
	for b in skin.get_bind_count():
		var n := String(skin.get_bind_name(b))
		var g := malla.transform * skin.get_bind_pose(b).affine_inverse()
		dst_rest_mundo[n] = dst_q * g.basis.get_rotation_quaternion()
		dst_rest_pos[n] = dst_xf * g.origin
	for k in MAPA:
		mapa["mixamorig1" + k] = MAPA[k]
	for lado in [["Left", "_l"], ["Right", "_r"]]:
		for d in DEDOS:
			for j in [1, 2, 3]:
				mapa["mixamorig1%sHand%s%d" % [lado[0], d, j]] = "%s_0%d%s" % [DEDOS[d], j, lado[1]]

	var lib := AnimationLibrary.new()
	var archivos := Array(DirAccess.get_files_at(CARPETA)).filter(func(f): return f.ends_with(".fbx"))
	archivos.sort()
	for f in archivos:
		var nombre: String = f.get_basename()
		var anim := convertir(CARPETA + f)
		ResourceSaver.save(anim, CARPETA + nombre + ".res")
		lib.add_animation(nombre, load(CARPETA + nombre + ".res"))
	ResourceSaver.save(lib, CARPETA + "arquero_cascadeur_v2.tres")
	print("--- listo: %d animaciones ---" % archivos.size())
	get_tree().quit()


## Rotacion que lleva el vector a al vector b (la minima).
func _alinear(a: Vector3, b: Vector3) -> Quaternion:
	a = a.normalized()
	b = b.normalized()
	var eje := a.cross(b)
	var d := clampf(a.dot(b), -1.0, 1.0)
	if eje.length() < 1e-6:
		return Quaternion() if d > 0.0 else Quaternion(Vector3.UP, PI)
	return Quaternion(eje.normalized(), acos(d))


func _orden_padres_primero() -> Array:
	var orden := []
	var pila := Array(dst.get_parentless_bones())
	while pila.size() > 0:
		var i: int = pila.pop_front()
		orden.append(i)
		pila.append_array(Array(dst.get_bone_children(i)))
	return orden


func convertir(ruta: String) -> Animation:
	var escena: Node = load(ruta).instantiate()
	add_child(escena)
	var src: Skeleton3D = escena.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = escena.find_children("*", "AnimationPlayer", true, false)[0]
	var an_src := ap.get_animation(ap.get_animation_list()[0])
	var src_xf := src.global_transform
	var src_q := src_xf.basis.get_rotation_quaternion()

	# reposo del origen en el mundo
	src.reset_bone_poses()
	var src_rest_q := {}
	var src_rest_p := {}
	for i in src.get_bone_count():
		var g := src.get_bone_global_rest(i)
		src_rest_q[src.get_bone_name(i)] = src_q * g.basis.get_rotation_quaternion()
		src_rest_p[src.get_bone_name(i)] = src_xf * g.origin

	# G: gira el mundo del origen para que mire para el mismo lado que el
	# arquero (se mide con el eje izquierda-derecha de las caderas)
	var izq_src: Vector3 = src_rest_p["thigh_l"] - src_rest_p["thigh_r"]
	var izq_dst: Vector3 = dst_rest_pos["mixamorig1LeftUpLeg"] - dst_rest_pos["mixamorig1RightUpLeg"]
	izq_src.y = 0.0
	izq_dst.y = 0.0
	var G := _alinear(izq_src, izq_dst)
	for n in src_rest_q:
		src_rest_q[n] = G * src_rest_q[n]
		src_rest_p[n] = G * src_rest_p[n]

	# A por hueso: lleva la direccion del reposo de Manny a la de Mixamo
	var A := {}
	for n_dst in mapa:
		var corto: String = n_dst.trim_prefix("mixamorig1")
		var n_src: String = mapa[n_dst]
		if DIR_DESTINO.has(corto) and DIR_ORIGEN.has(n_src):
			var d_src: Vector3 = src_rest_p[DIR_ORIGEN[n_src]] - src_rest_p[n_src]
			var d_dst: Vector3 = dst_rest_pos["mixamorig1" + DIR_DESTINO[corto]] - dst_rest_pos[n_dst]
			A[n_dst] = _alinear(d_src, d_dst)
	# los que no tienen direccion propia (dedos, cabeza, punta del pie) usan
	# la del hueso padre; los dedos se alinean falange por falange
	for n_dst in mapa:
		if A.has(n_dst):
			continue
		var corto: String = n_dst.trim_prefix("mixamorig1")
		var n_src: String = mapa[n_dst]
		var hijo_dst := corto.left(corto.length() - 1) + str(int(corto.right(1)) + 1)
		var hijo_src := n_src.replace("_0%s" % corto.right(1), "_0%d" % (int(corto.right(1)) + 1))
		if corto.contains("Hand") and dst_rest_pos.has("mixamorig1" + hijo_dst) and src_rest_p.has(hijo_src):
			A[n_dst] = _alinear(src_rest_p[hijo_src] - src_rest_p[n_src],
				dst_rest_pos["mixamorig1" + hijo_dst] - dst_rest_pos[n_dst])
	var orden := _orden_padres_primero()
	for n_dst in mapa:
		if not A.has(n_dst):
			var p := dst.get_bone_parent(dst.find_bone(n_dst))
			while p >= 0 and not A.has(dst.get_bone_name(p)):
				p = dst.get_bone_parent(p)
			A[n_dst] = A[dst.get_bone_name(p)] if p >= 0 else Quaternion()

	# escala por altura de cadera (los dos parados en el reposo)
	var piso_dst: float = dst_xf.origin.y
	var escala: float = (dst_rest_pos["mixamorig1Hips"].y - piso_dst) / src_rest_p["pelvis"].y

	var n_cuadros := int(round(an_src.length * FPS)) + 1
	var out := Animation.new()
	out.length = (n_cuadros - 1) / FPS
	out.step = 1.0 / FPS
	var pistas_rot := {}
	for i in dst.get_bone_count():
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, PISTA + dst.get_bone_name(i))
		pistas_rot[i] = t
	var pista_pos := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(pista_pos, PISTA + "mixamorig1Hips")

	ap.play(an_src.resource_name if ap.has_animation(an_src.resource_name) else ap.get_animation_list()[0])
	var p0 := Vector3.ZERO
	for c in n_cuadros:
		var t := c / FPS
		ap.seek(t, true)
		src.force_update_all_bone_transforms()
		var src_mundo := {}
		for n_src in mapa.values():
			var i := src.find_bone(n_src)
			src_mundo[n_src] = G * src_q * src.get_bone_global_pose(i).basis.get_rotation_quaternion()
		var pelvis: Vector3 = G * (src_xf * src.get_bone_global_pose(src.find_bone("pelvis")).origin)
		if c == 0:
			p0 = Vector3(pelvis.x, 0.0, pelvis.z)
		# rotaciones globales del destino (en espacio del esqueleto destino)
		var glob := {}
		for i in orden:
			var n := dst.get_bone_name(i)
			var padre := dst.get_bone_parent(i)
			var g_sk: Quaternion
			if mapa.has(n):
				var n_src: String = mapa[n]
				var D: Quaternion = src_mundo[n_src] * src_rest_q[n_src].inverse()
				var mundo: Quaternion = D * A[n].inverse() * dst_rest_mundo[n]
				g_sk = dst_q.inverse() * mundo
			else:
				# sin pareja en Manny: se queda como en la T-pose, relativo al padre
				var ref: Quaternion = dst_q.inverse() * dst_rest_mundo[n]
				var ref_padre: Quaternion = (dst_q.inverse() * dst_rest_mundo[dst.get_bone_name(padre)]) if padre >= 0 else Quaternion()
				g_sk = (glob[padre] if padre >= 0 else Quaternion()) * (ref_padre.inverse() * ref)
			glob[i] = g_sk.normalized()
			var local: Quaternion = (glob[padre].inverse() * g_sk) if padre >= 0 else g_sk
			out.rotation_track_insert_key(pistas_rot[i], t, local.normalized())
		# cadera: posicion del origen escalada, arrancando en el lugar del arquero
		var hr: Vector3 = dst_rest_pos["mixamorig1Hips"]
		var mundo_pos := Vector3(hr.x, piso_dst, hr.z) + (pelvis - p0) * escala
		out.position_track_insert_key(pista_pos, t, dst_xf.affine_inverse() * mundo_pos)
	escena.queue_free()
	print("%-28s %d cuadros  escala %.3f  giro %.0f grados" % [ruta.get_file(), n_cuadros, escala, rad_to_deg(G.get_angle())])
	return out
