extends Node

# Mide las animaciones de Cascadeur ya pasadas al arquero: para cada una busca
# el cuadro de contacto (el cuadro en que la mano -nudillos- llega al punto de
# referencia medido en Cascadeur, o el de maximo alcance si no hay
# referencia) y revisa que los pies no atraviesen el piso.
#
# Referencias (cuadro, mano, X cm, Y cm) medidas por el autor en Cascadeur.
# Las 17/18/19 (dives al palo) no tienen referencia del autor: su punto es el
# primer cuadro en que los nudillos llegan a x >= 3,30 m (pelota pegada al palo).

const REF := {
	"Dive_derecha_11": [38, "l", 231, 79], "Dive_derecha_13": [38, "l", 226, 16],
	"Dive_izquierda_11": [38, "r", -231, 79], "Dive_izquierda_13": [38, "r", -226, 16],
	"Dive_medio": [31, "l", 7, 108], "Dive_medio_arriba": [36, "l", -3, 252],
	"Dive_medio_derecha_1": [41, "r", 55, 156], "Dive_medio_derecha_12": [40, "l", 248, 18],
	"Dive_medio_derecha_2": [39, "r", 54, 97], "Dive_medio_derecha_3": [38, "l", 68, 52],
	"Dive_medio_derecha_9": [34, "r", 30, 201],
	"Dive_medio_izquierda_1": [41, "l", -55, 156], "Dive_medio_izquierda_12": [40, "r", -248, 18],
	"Dive_medio_izquierda_2": [39, "l", -54, 97], "Dive_medio_izquierda_3": [38, "r", -68, 52],
	"Dive_medio_izquierda_9": [34, "l", -30, 201],
	"Dive_derecha_17": [32, "l", 346, 203], "Dive_derecha_18": [32, "l", 337, 122], "Dive_derecha_19": [32, "l", 342, 45],
	"Dive_izquierda_17": [32, "r", -346, 203], "Dive_izquierda_18": [32, "r", -337, 122], "Dive_izquierda_19": [32, "r", -342, 45],
	"Save_derecha_11": [43, "l", 248, 25], "Save_derecha_12": [40, "l", 248, 25], "Save_derecha_13": [33, "l", 212, 31],
	"Save_izquierda_11": [43, "r", -248, 25], "Save_izquierda_12": [40, "r", -248, 25], "Save_izquierda_13": [33, "r", -212, 31],
	"Save_medio_4": [32, "l", -17, 20], "Save_medio_arriba": [34, "l", 5, 246],
	"Save_medio_derecha_1": [41, "r", 63, 146], "Save_medio_derecha_9": [34, "r", 42, 204],
	"Save_medio_izquierda_1": [41, "l", -63, 146], "Save_medio_izquierda_9": [34, "l", -42, 204],
}
const FPS := 30.0

func _ready() -> void:
	var j = load("res://scenes/game.tscn").instantiate()
	add_child(j)
	var gk: Node3D = j.get_node("Goalkeeper")
	gk.set_process(false)
	gk.set_physics_process(false)
	var ap: AnimationPlayer = j.get_node("Goalkeeper/player/AnimationPlayer")
	var sk: Skeleton3D = j.get_node("Goalkeeper/player/Node/Skeleton3D")
	var base := gk.global_position
	var nombres := REF.keys()
	nombres.sort()
	print("RES animacion                 ref   medido  mano   X     Y     Z   | ref X  Y  | dif cm | pie min cm")
	for n in nombres:
		var r: Array = REF[n]
		var hueso := "mixamorig1LeftHandMiddle1" if r[1] == "l" else "mixamorig1RightHandMiddle1"
		ap.play("cascadeur/" + n)
		ap.pause()
		var cuadros := int(round(ap.current_animation_length * FPS)) + 1
		var mejor := -1
		var mejor_d := INF
		var mejor_p := Vector3.ZERO
		var pie_min := INF
		for c in cuadros:
			ap.seek(c / FPS, true)
			sk.force_update_all_bone_transforms()
			var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(hueso)).origin - base
			var d := Vector2(p.x - r[2] / 100.0, p.y - r[3] / 100.0).length()
			# solo cerca del cuadro de referencia: despues de atajar la mano
			# puede volver a pasar por el mismo lugar al caer
			if absi(c - r[0]) <= 8 and d < mejor_d:
				mejor_d = d
				mejor = c
				mejor_p = p
			for pie in ["mixamorig1LeftToeBase", "mixamorig1RightToeBase", "mixamorig1LeftFoot", "mixamorig1RightFoot"]:
				pie_min = minf(pie_min, (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(pie)).origin).y)
		print("RES %-26s %3d   %3d    %s   %5.2f %5.2f %5.2f | %5.2f %4.2f | %4.0f   | %4.1f" % [
			n, r[0], mejor, r[1], mejor_p.x, mejor_p.y, mejor_p.z, r[2] / 100.0, r[3] / 100.0, mejor_d * 100.0, pie_min * 100.0])
	get_tree().quit()
