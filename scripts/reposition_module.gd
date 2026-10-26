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
var _corregir_con_ik: bool = true
var _inicio: float = 0.0

func _init(arquero_root: Node3D, anim_player: AnimationPlayer, skeleton_ik: TwoBoneIK3D):
	_arquero_root = arquero_root
	_anim_player = anim_player
	_skeleton_ik = skeleton_ik
	
## corregir_con_ik en false cuando es gol: el arquero igual se tira hacia el
## lado que eligio, pero no se le estira la mano hasta la pelota (si no, un gol
## se veria como atajada).
## inicio: segundo de la animacion desde el que se arranca (ver TimingModule).
func iniciar_offset(target_percibido: Vector2, anim: DiveAnimData, base_pos: Vector3, corregir_con_ik: bool = true, inicio: float = 0.0) -> void:
	_anim = anim
	_corregir_con_ik = corregir_con_ik
	_inicio = inicio
	_pos_base_arquero = base_pos
	_is_diving = true
	_ik_started = false
	
	var target_3d := Vector3(target_percibido.x, target_percibido.y, anim.canonical_target.z)
	offset_objetivo_completo = target_3d - anim.canonical_target
	# Solo movemos horizontal con el root, la altura la corrige el IK
	offset_objetivo = offset_objetivo_completo
	offset_objetivo.y = 0
	if not corregir_con_ik:
		offset_objetivo = Vector3(_offset_fallo(target_percibido.x, anim.canonical_target.x), 0, 0)

## Cuando es gol el arquero NO se corre hacia la pelota (si no, la tocaria).
## Se lo corre lo minimo para que la pelota pase lejos del tramo entre su
## cuerpo y su mano.
const MARGEN_FALLO := 0.6

func _offset_fallo(pelota_x: float, mano_x: float) -> float:
	var desde := minf(0.0, mano_x) - MARGEN_FALLO
	var hasta := maxf(0.0, mano_x) + MARGEN_FALLO
	if pelota_x <= desde or pelota_x >= hasta:
		return 0.0
	var a_la_izq := pelota_x - hasta  # negativo: corre el arquero hacia -x
	var a_la_der := pelota_x - desde  # positivo: corre el arquero hacia +x
	return a_la_izq if absf(a_la_izq) < absf(a_la_der) else a_la_der

## Segundos de animacion antes del contacto en los que se corre al arquero.
const VENTANA_CORRIMIENTO := 0.45

func process_frame(delta: float) -> void:
	if not _is_diving or not _anim:
		return
		
	var anim_length: float = _anim_player.current_animation_length
	var current_pos: float = _anim_player.current_animation_position
	
	if _anim.contact_time > _inicio:
		# El arquero se corre solo durante la estirada (no mientras espera
		# parado, que se veria como patinar) y con arranque y frenada suaves.
		var desde := maxf(_inicio, _anim.contact_time - VENTANA_CORRIMIENTO)
		var progreso: float = (current_pos - desde) / (_anim.contact_time - desde)
		offset_actual = offset_objetivo * smoothstep(0.0, 1.0, progreso)
		_arquero_root.global_position = _pos_base_arquero + offset_actual
		
		# Activar IK si estamos cerca del momento de contacto (ej: 0.15s antes)
		var time_to_contact = _anim.contact_time - current_pos
		if _corregir_con_ik and time_to_contact > 0.0 and time_to_contact < 0.15 and not _ik_started:
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
