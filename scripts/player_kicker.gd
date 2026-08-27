extends Node3D
class_name PlayerKicker

enum KickState {
	IDLE,
	AIMING,
	CHARGING,
	RUN_UP,
	KICK_CONTACT,
	FOLLOW_THROUGH
}

@export var animation_player: AnimationPlayer
@export var skeleton: Skeleton3D
@export var ball: SoccerBall

@export_group("IK Setup (Godot 4.7 TwoBoneIK3D)")
@export var plant_foot_ik: TwoBoneIK3D
@export var kick_foot_ik: TwoBoneIK3D
@export var plant_foot_target: Marker3D
@export var kick_foot_target: Marker3D

@export_group("Bone Names")
@export var plant_leg_bone: String = "mixamorig1LeftUpLeg"
@export var plant_knee_bone: String = "mixamorig1LeftLeg"
@export var plant_foot_bone: String = "mixamorig1LeftFoot"
@export var kick_leg_bone: String = "mixamorig1RightUpLeg"
@export var kick_knee_bone: String = "mixamorig1RightLeg"
@export var kick_foot_bone: String = "mixamorig1RightFoot"

@export_group("Kick Parameters")
@export var power_speed: float = 2.5
@export var max_power: float = 100.0
@export var optimal_power_min: float = 75.0
@export var optimal_power_max: float = 90.0
@export var ball_contact_animation_progress: float = 0.55
@export var run_up_duration: float = 1.2
@export var max_aim_goal_height: float = 2.8
@export var min_aim_goal_height: float = 0.0
@export var aim_horizontal_range: float = 4.2
@export var goal_z_position: float = -12.0

@export_group("Aim Feel (FIFA-style)")
@export var aim_smooth_speed: float = 6.0
@export var aim_center_pull: float = 4.0
@export var aim_edge_instability: float = 0.15
@export var aim_edge_threshold: float = 0.7

var current_state: KickState = KickState.IDLE
var _smooth_aim: Vector2 = Vector2.ZERO
var aim_target_3d: Vector3 = Vector3.ZERO
var power: float = 0.0
var power_filling: bool = true
var final_power: float = 0.0
var final_target: Vector3 = Vector3.ZERO
var run_up_timer: float = 0.0
var is_run_up_complete: bool = false
var is_kick_complete: bool = false
var plant_foot_world_pos: Vector3
var _last_shot_data: ShotData

signal kick_connecting(power: float, kick_target: Vector3)
signal ball_launch_requested(velocity: Vector3)
signal shot_taken(shot_data: ShotData)

func _ready():
	_find_skeleton_and_anim_player()
	_setup_ik()

func _find_skeleton_and_anim_player():
	if not skeleton:
		skeleton = _find_node_of_type(self, "Skeleton3D") as Skeleton3D
	if not animation_player:
		animation_player = _find_node_of_type(self, "AnimationPlayer") as AnimationPlayer

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func _process(delta: float):
	match current_state:
		KickState.AIMING:
			_process_aiming(delta)
		KickState.CHARGING:
			_process_charging(delta)
		KickState.RUN_UP:
			_process_run_up(delta)
		KickState.KICK_CONTACT:
			if animation_player and not animation_player.is_playing():
				notify_follow_through()

func start_aiming():
	current_state = KickState.AIMING
	_smooth_aim = Vector2.ZERO
	power = 0.0
	power_filling = true
	_last_shot_data = null
	play_idle()

func _process_aiming(delta: float):
	var input := Input.get_vector("move_left", "move_right", "move_down", "move_up")

	# Smooth aim follows input with momentum
	_smooth_aim = _smooth_aim.lerp(input, aim_smooth_speed * delta)

	# Centering force: pull back to center when stick released
	if input.length() < 0.15:
		_smooth_aim = _smooth_aim.lerp(Vector2.ZERO, aim_center_pull * delta)

	# Edge instability: harder to hold at extremes
	if _smooth_aim.length() > aim_edge_threshold:
		var edge := _smooth_aim.length()
		var wobble := randf_range(-aim_edge_instability, aim_edge_instability) * (edge - aim_edge_threshold) * 2.0
		_smooth_aim += _smooth_aim.orthogonal() * wobble

	_smooth_aim = _smooth_aim.limit_length(1.0)
	aim_target_3d = _aim_to_goal_position(_smooth_aim)

	if Input.is_action_just_pressed("kick_charge"):
		start_charging()

func _process_charging(delta: float):
	var input := Input.get_vector("move_left", "move_right", "move_down", "move_up")

	# Same smooth aim, but more instability at high power
	_smooth_aim = _smooth_aim.lerp(input, aim_smooth_speed * delta)

	if input.length() < 0.15:
		_smooth_aim = _smooth_aim.lerp(Vector2.ZERO, aim_center_pull * delta)

	var power_ratio := power / max_power
	if _smooth_aim.length() > aim_edge_threshold:
		var edge := _smooth_aim.length()
		var extra_wobble := 1.0 + power_ratio * 2.0
		var wobble := randf_range(-aim_edge_instability, aim_edge_instability) * (edge - aim_edge_threshold) * extra_wobble
		_smooth_aim += _smooth_aim.orthogonal() * wobble

	_smooth_aim = _smooth_aim.limit_length(1.0)
	aim_target_3d = _aim_to_goal_position(_smooth_aim)

	if power_filling:
		power += power_speed * max_power * delta
		if power >= max_power:
			power = max_power
			power_filling = false
	else:
		power -= power_speed * max_power * delta
		if power <= 0.0:
			power = 0.0
			power_filling = true

	if Input.is_action_just_released("kick_charge"):
		_release_kick()

func _release_kick():
	final_power = power
	final_target = aim_target_3d

	if final_power > 95.0:
		var overshoot = (final_power - 95.0) / 5.0
		final_target += Vector3(
			randf_range(-1.0, 1.0) * overshoot * 4.0,
			randf_range(-0.5, 1.0) * overshoot * 2.0,
			0.0
		)

	current_state = KickState.RUN_UP
	run_up_timer = 0.0
	is_run_up_complete = false
	is_kick_complete = false

	kick_connecting.emit(final_power, final_target)
	play_run_up()

func _process_run_up(delta: float):
	run_up_timer += delta
	if run_up_timer >= run_up_duration * 0.7 and not is_kick_complete:
		is_kick_complete = true
		play_kick()
		_enable_kick_ik()

	_check_animation_contact()

	if run_up_timer >= run_up_duration and not is_run_up_complete:
		is_run_up_complete = true
		_on_run_up_complete()

func _check_animation_contact():
	if is_kick_complete and current_state != KickState.KICK_CONTACT and current_state != KickState.FOLLOW_THROUGH:
		if animation_player and animation_player.is_playing():
			var progress = animation_player.current_animation_position / animation_player.current_animation_length
			if progress >= ball_contact_animation_progress:
				notify_animation_contact()

func _on_run_up_complete():
	pass

func notify_animation_contact():
	if current_state != KickState.KICK_CONTACT:
		current_state = KickState.KICK_CONTACT
		_update_kick_foot_ik_target()

		var ball_pos = _get_ball_world_position()
		var power_ratio = final_power / max_power
		var velocity = _calculate_ball_velocity()

		_last_shot_data = ShotData.new(ball_pos, velocity, power_ratio, 0.0)
		shot_taken.emit(_last_shot_data)
		ball_launch_requested.emit(velocity)

func notify_follow_through():
	current_state = KickState.FOLLOW_THROUGH
	disable_all_ik()

func _aim_to_goal_position(analog_input: Vector2) -> Vector3:
	var x = analog_input.x * aim_horizontal_range
	var y = clamp(remap(analog_input.y, -1.0, 1.0, min_aim_goal_height, max_aim_goal_height), 0.0, max_aim_goal_height)
	return Vector3(x, y, 0.0)

func _setup_ik():
	if not skeleton:
		push_warning("PlayerKicker: Skeleton3D not found. IK disabled.")
		return
	if plant_foot_ik:
		if plant_foot_ik.setting_count < 1:
			plant_foot_ik.setting_count = 1
		plant_foot_ik.set_root_bone_name(0, plant_leg_bone)
		plant_foot_ik.set_middle_bone_name(0, plant_knee_bone)
		plant_foot_ik.set_end_bone_name(0, plant_foot_bone)
		plant_foot_ik.influence = 1.0
		plant_foot_ik.active = false
		if plant_foot_target:
			plant_foot_ik.set_target_node(0, plant_foot_ik.get_path_to(plant_foot_target))

	if kick_foot_ik:
		if kick_foot_ik.setting_count < 1:
			kick_foot_ik.setting_count = 1
		kick_foot_ik.set_root_bone_name(0, kick_leg_bone)
		kick_foot_ik.set_middle_bone_name(0, kick_knee_bone)
		kick_foot_ik.set_end_bone_name(0, kick_foot_bone)
		kick_foot_ik.influence = 1.0
		kick_foot_ik.active = false
		if kick_foot_target:
			kick_foot_ik.set_target_node(0, kick_foot_ik.get_path_to(kick_foot_target))

func _enable_kick_ik():
	if not skeleton:
		return
	var bone_idx = skeleton.find_bone(plant_foot_bone)
	if bone_idx >= 0:
		plant_foot_world_pos = skeleton.to_global(skeleton.get_bone_global_pose(bone_idx).origin)
	if plant_foot_ik and plant_foot_target:
		plant_foot_target.global_position = plant_foot_world_pos
		plant_foot_ik.active = true
	if kick_foot_ik and kick_foot_target:
		kick_foot_ik.active = true

func _update_kick_foot_ik_target():
	if not kick_foot_target:
		return
	var ball_pos = _get_ball_world_position()
	kick_foot_target.global_position = ball_pos

func _calculate_ball_velocity() -> Vector3:
	var power_ratio = final_power / max_power
	var ball_pos = _get_ball_world_position()
	var target_world = Vector3(final_target.x, final_target.y, goal_z_position)
	var direction = (target_world - ball_pos).normalized()
	var speed = 15.0 + power_ratio * 25.0
	var distance = ball_pos.distance_to(target_world)
	var flight_time = distance / speed
	var gravity = 9.8
	var height_diff = target_world.y - ball_pos.y
	var vy_needed = (height_diff + 0.5 * gravity * flight_time * flight_time) / flight_time
	var velocity = direction * speed
	velocity.y = vy_needed * power_ratio + 2.0 * (1.0 - power_ratio)
	return velocity

func disable_all_ik():
	if plant_foot_ik:
		plant_foot_ik.active = false
	if kick_foot_ik:
		kick_foot_ik.active = false

func _get_ball_world_position() -> Vector3:
	if not ball:
		var root = owner if owner else get_tree().root
		ball = _find_node_of_type(root, "SoccerBall") as SoccerBall
	if ball:
		return ball.global_position
	return global_position + Vector3(0, 0, -2.0)

func play_idle():
	if animation_player and animation_player.has_animation("Offensiveidle"):
		animation_player.play("Offensiveidle")

func play_run_up():
	if animation_player and animation_player.has_animation("Jogforward"):
		animation_player.play("Jogforward")

func play_kick():
	if not animation_player:
		return
	var kick_anim: String = ""
	if animation_player.has_animation("Soccerpenaltykick"):
		kick_anim = "Soccerpenaltykick"
	elif final_target.x < -0.5 and animation_player.has_animation("Kicksoccerball"):
		kick_anim = "Kicksoccerball"
	elif final_target.x > 0.5 and animation_player.has_animation("Kicksoccerball(2)"):
		kick_anim = "Kicksoccerball(2)"
	elif animation_player.has_animation("Kicksoccerball"):
		kick_anim = "Kicksoccerball"

	if kick_anim != "":
		animation_player.play(kick_anim)
	else:
		notify_animation_contact()

func start_charging():
	current_state = KickState.CHARGING
	power = 0.0
	power_filling = true

func get_current_aim() -> Vector3:
	return aim_target_3d

func get_power() -> float:
	return power

func get_power_percent() -> float:
	return power / max_power

func get_final_power() -> float:
	return final_power

func get_final_target() -> Vector3:
	return final_target

func is_optimal_power() -> bool:
	return final_power >= optimal_power_min and final_power <= optimal_power_max
