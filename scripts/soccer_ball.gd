extends RigidBody3D
class_name SoccerBall

@export var min_speed_threshold: float = 0.5
@export var max_lifetime: float = 15.0
@export var bounce_factor: float = 0.6
@export var air_resistance: float = 0.998
@export var spin_decay: float = 0.95
@export var goal_line_z: float = -12.0

signal shot_taken(shot_data: ShotData)
signal crossed_goal_line(ball_world_pos: Vector3)
signal ball_stopped

var is_in_play: bool = false
var has_been_kicked: bool = false
var lifetime_timer: float = 0.0
var spawn_position: Vector3 = Vector3.ZERO
var _prev_z: float = 0.0
var _crossed_emitted: bool = false
var _last_shot_data: ShotData

func _ready():
	spawn_position = global_position
	_prev_z = global_position.z
	freeze = true
	collision_layer = 1

func _physics_process(delta: float):
	if not is_in_play:
		return

	lifetime_timer += delta

	if freeze:
		reset_to(spawn_position)
		return

	_apply_air_resistance()

	_check_goal_line_crossing()

	if linear_velocity.length() < min_speed_threshold and has_been_kicked:
		linear_velocity = Vector3.ZERO
		is_in_play = false
		ball_stopped.emit()

	if lifetime_timer > max_lifetime:
		is_in_play = false
		ball_stopped.emit()

func _check_goal_line_crossing():
	if _crossed_emitted:
		return
	var curr_z = global_position.z
	var crossed = (_prev_z > goal_line_z and curr_z <= goal_line_z) or \
				  (_prev_z < goal_line_z and curr_z >= goal_line_z)
	_prev_z = curr_z
	if crossed:
		_crossed_emitted = true
		crossed_goal_line.emit(global_position)

func kick(velocity: Vector3):
	freeze = false
	is_in_play = true
	has_been_kicked = true
	lifetime_timer = 0.0
	_crossed_emitted = false
	_prev_z = global_position.z

	linear_velocity = velocity

	var lateral_spin = velocity.x * 0.05
	var vertical_spin = velocity.y * 0.02
	angular_velocity = Vector3(vertical_spin, lateral_spin, 0.0)

	_last_shot_data = ShotData.new(global_position, velocity, 1.0, 0.0)
	shot_taken.emit(_last_shot_data)

func reset_to(pos: Vector3):
	freeze = true
	is_in_play = false
	has_been_kicked = false
	lifetime_timer = 0.0
	_crossed_emitted = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_position = pos
	_prev_z = pos.z

func _apply_air_resistance():
	linear_velocity *= air_resistance
	angular_velocity *= spin_decay

func get_speed() -> float:
	return linear_velocity.length()

func get_velocity() -> Vector3:
	return linear_velocity
