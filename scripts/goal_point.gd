class_name GoalPoint
extends RefCounted

var x: float
var y: float

func _init(_x: float = 0.0, _y: float = 0.0):
	x = _x
	y = _y

func _to_string() -> String:
	return "(x=%.2f, y=%.2f)" % [x, y]
