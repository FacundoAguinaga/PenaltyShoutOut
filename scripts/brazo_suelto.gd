class_name BrazoSuelto
extends SkeletonModifier3D

## Deja colgando un brazo con la pose de otro clip, encima de lo que haga la animacion.
## En las filas de PES todos abrazan a los dos lados (sus filas son mas largas que lo que
## muestra la camara): en las puntas, el brazo de afuera abrazaria al aire.

var _poses := {}

## `lado` es "Left" o "Right"; la pose sale del primer cuadro de `anim`.
func preparar(sk: Skeleton3D, anim: Animation, lado: String) -> void:
	for h: String in ["Arm", "ForeArm", "Hand"]:
		var nombre := "mixamorig1" + lado + h
		var pista := anim.find_track("Node/Skeleton3D:" + nombre, Animation.TYPE_ROTATION_3D)
		if pista >= 0:
			_poses[sk.find_bone(nombre)] = anim.rotation_track_interpolate(pista, 0.0)

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	for b: int in _poses:
		sk.set_bone_pose_rotation(b, _poses[b])
