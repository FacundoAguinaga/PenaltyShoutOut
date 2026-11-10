extends Node

## Mantiene la malla sobre el piso con la pose final de cada cuadro. Los clips ya
## vienen apoyados (tools/pes_construir.gd), pero un fundido entre dos poses validas
## puede hundir un pie unos centimetros. Corre despues del AnimationPlayer.

const ESCALA := 0.01

var _sk: Skeleton3D
var _alto_base: float
var _huesos: PackedInt32Array = []
var _nubes: Array[PackedVector3Array] = []

func _init(esqueleto: Skeleton3D, nube: Dictionary) -> void:
	name = "PesPiso"
	process_priority = 100
	_sk = esqueleto
	_alto_base = _sk.global_position.y
	for hueso: String in nube:
		var puntos := PackedVector3Array()
		for p: Array in nube[hueso]:
			puntos.append(Vector3(p[0], p[1], p[2]))
		_huesos.append(_sk.find_bone(hueso))
		_nubes.append(puntos)

func _process(_delta: float) -> void:
	var min_y := INF
	for i in _huesos.size():
		var g := _sk.get_bone_global_pose(_huesos[i])
		var fila := Vector3(g.basis.x.y, g.basis.y.y, g.basis.z.y)
		for punto in _nubes[i]:
			min_y = minf(min_y, fila.dot(punto) + g.origin.y)
	_sk.global_position.y = _alto_base + maxf(0.0, -(min_y * ESCALA + _alto_base))
