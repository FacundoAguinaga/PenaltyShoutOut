class_name ShotData
extends RefCounted

var origin: Vector3
var initial_velocity: Vector3
var spin: float = 0.0
var power: float = 1.0

func _init(_origin: Vector3 = Vector3.ZERO, _velocity: Vector3 = Vector3.ZERO, _power: float = 1.0, _spin: float = 0.0):
	origin = _origin
	initial_velocity = _velocity
	power = _power
	spin = _spin
