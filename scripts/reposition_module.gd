class_name RepositionModule
extends RefCounted

var offset_objetivo: Vector3
var offset_actual: Vector3 = Vector3.ZERO
var offset_objetivo_completo: Vector3

var _arquero_root: Node3D
var _anim_player: AnimationPlayer
var _anim: DiveAnimData
var _pos_base_arquero: Vector3
var _skeleton_ik: TwoBoneIK3D
var _is_diving: bool = false
var _ik_started: bool = false

func _init(arquero_root: Node3D, anim_player: AnimationPlayer, skeleton_ik: TwoBoneIK3D):
	_arquero_root = arquero_root
	_anim_player = anim_player
	_skeleton_ik = skeleton_ik
	
func iniciar_offset(target_percibido: Vector2, anim: DiveAnimData, base_pos: Vector3) -> void:
	_anim = anim
	_pos_base_arquero = base_pos
	_is_diving = true
	_ik_started = false
	
	var target_3d := Vector3(target_percibido.x, target_percibido.y, anim.canonical_target.z)
	offset_objetivo_completo = target_3d - anim.canonical_target
	# Solo movemos horizontal con el root, la altura la corrige el IK
	offset_objetivo = offset_objetivo_completo
	offset_objetivo.y = 0

func process_frame(delta: float) -> void:
	if not _is_diving or not _anim:
		return
		
	var anim_length: float = _anim_player.current_animation_length
	var current_pos: float = _anim_player.current_animation_position
	
	if _anim.contact_time > 0:
		var progreso: float = current_pos / _anim.contact_time
		offset_actual = offset_objetivo * clampf(progreso, 0.0, 1.0)
		_arquero_root.global_position = _pos_base_arquero + offset_actual
		
		# Activar IK si estamos cerca del momento de contacto (ej: 0.15s antes)
		var time_to_contact = _anim.contact_time - current_pos
		if time_to_contact > 0.0 and time_to_contact < 0.15 and not _ik_started:
			_start_ik()
		# Apagar IK después del contacto
		elif time_to_contact < -0.1 and _ik_started:
			_stop_ik()

func _start_ik() -> void:
	if not _skeleton_ik or not _skeleton_ik.get_node(_skeleton_ik.target_node):
		return
	_ik_started = true
	var altura_fina := offset_objetivo_completo.y
	var hand_target_local := _anim.canonical_target + Vector3(0, altura_fina, 0)
	var hand_target_world := _pos_base_arquero + hand_target_local # Aproximación rápida
	
	var target_node = _skeleton_ik.get_node(_skeleton_ik.target_node) as Node3D
	if target_node:
		target_node.global_position = hand_target_world
		_skeleton_ik.influence = 0.0
		_skeleton_ik.active = true
		
		var tween = _arquero_root.create_tween()
		tween.tween_property(_skeleton_ik, "influence", 1.0, 0.15)

func _stop_ik() -> void:
	if _skeleton_ik:
		_skeleton_ik.active = false
	_ik_started = false
	_is_diving = false
