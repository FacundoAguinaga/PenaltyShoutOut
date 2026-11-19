extends Node3D

## La copa de la ceremonia, armada por codigo (una copa generica, sin licencias):
## un perfil que gira alrededor del eje vertical, mas dos asas. Cada cuadro se pone
## entre las manos de quien la levanta.

const SEGMENTOS := 32
## Radio y altura del perfil, de abajo hacia arriba y por adentro al final.
const PERFIL := [
	Vector2(0.0, 0.0), Vector2(0.095, 0.0), Vector2(0.095, 0.025), Vector2(0.055, 0.05),
	Vector2(0.03, 0.09), Vector2(0.024, 0.17), Vector2(0.034, 0.21), Vector2(0.075, 0.25),
	Vector2(0.115, 0.32), Vector2(0.135, 0.42), Vector2(0.14, 0.52), Vector2(0.155, 0.56),
	Vector2(0.14, 0.565), Vector2(0.125, 0.5), Vector2(0.09, 0.36), Vector2(0.0, 0.3),
]
## A que altura de la copa van las manos.
const ALTURA_MANOS := 0.33

var _sk: Skeleton3D
## La copa de la ceremonia de PES se sostiene de las asas, con las manos a casi un metro.
var escala := 1.0

func _init() -> void:
	name = "Copa"
	var oro := StandardMaterial3D.new()
	oro.albedo_color = Color(0.95, 0.72, 0.28)
	# Medio metalico: como metal puro se ve oscura, no tiene mucho que reflejar.
	oro.metallic = 0.55
	oro.roughness = 0.3
	oro.emission_enabled = true
	oro.emission = Color(0.5, 0.33, 0.08)
	var cuerpo := MeshInstance3D.new()
	cuerpo.mesh = _girar_perfil()
	cuerpo.material_override = oro
	add_child(cuerpo)
	for lado in [-1.0, 1.0]:
		var asa := MeshInstance3D.new()
		var toro := TorusMesh.new()
		toro.inner_radius = 0.05
		toro.outer_radius = 0.072
		asa.mesh = toro
		asa.material_override = oro
		asa.position = Vector3(lado * 0.155, 0.43, 0.0)
		asa.rotation.x = PI / 2.0
		asa.scale = Vector3(0.9, 1.0, 1.4)
		add_child(asa)
	visible = false

func _girar_perfil() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in PERFIL.size() - 1:
		for s in SEGMENTOS:
			var a0 := TAU * s / SEGMENTOS
			var a1 := TAU * (s + 1) / SEGMENTOS
			var p0: Vector2 = PERFIL[i]
			var p1: Vector2 = PERFIL[i + 1]
			var v00 := Vector3(cos(a0) * p0.x, p0.y, sin(a0) * p0.x)
			var v01 := Vector3(cos(a1) * p0.x, p0.y, sin(a1) * p0.x)
			var v10 := Vector3(cos(a0) * p1.x, p1.y, sin(a0) * p1.x)
			var v11 := Vector3(cos(a1) * p1.x, p1.y, sin(a1) * p1.x)
			for v in [v00, v10, v01, v01, v10, v11]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()

func seguir(sk: Skeleton3D) -> void:
	_sk = sk
	visible = true

func soltar() -> void:
	_sk = null
	visible = false

func _pos(hueso: String) -> Vector3:
	return _sk.global_transform * _sk.get_bone_global_pose(_sk.find_bone(hueso)).origin

## Corre despues de las animaciones, para no ir un cuadro atrasada de las manos.
func _process(_delta: float) -> void:
	if _sk == null:
		return
	var izq := _pos("mixamorig1LeftHandMiddle1")
	var der := _pos("mixamorig1RightHandMiddle1")
	var costado := (der - izq).normalized()
	var adelante := costado.cross(Vector3.UP).normalized()
	var arriba := adelante.cross(costado).normalized()
	global_transform = Transform3D(Basis(costado, arriba, adelante).scaled(Vector3.ONE * escala), (izq + der) * 0.5 - arriba * ALTURA_MANOS * escala)
