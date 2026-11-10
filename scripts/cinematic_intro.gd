extends Node3D
class_name CinematicIntro

## CinematicIntro - Control de cámaras y secuencia cinemática de apertura
## Muestra tomas panorámicas, de red y de tensión antes de ceder el control
## a la cámara de juego. Puede saltarse en cualquier momento con ESPACIO o Clic.

signal intro_finished

@export var camera: Camera3D
@export var sound_manager: Node

var is_intro_active: bool = true
var current_shot_idx: int = 0

# Coordenadas calibradas para PenaltyShoutOut (Arco en Z=-11m, Pelota en Z=-2m, Cámara de juego en Z=2m)
var shots: Array[Dictionary] = [
	{
		# Toma 1: Panorámica aérea general del estadio y luces
		"pos": Vector3(0.0, 18.0, 22.0),
		"look": Vector3(0.0, 1.5, -4.0),
		"duration": 3.0,
		"fov": 65.0
	},
	{
		# Toma 2: A ras de piso desde el interior de la red hacia el punto de penal
		"pos": Vector3(0.0, 0.9, -12.8),
		"look": Vector3(0.0, 0.2, -2.0),
		"duration": 2.5,
		"fov": 55.0
	},
	{
		# Toma 3: Enfoque al arquero en la línea de gol con tribunas de fondo
		"pos": Vector3(2.0, 1.4, -7.5),
		"look": Vector3(0.0, 1.3, -11.0),
		"duration": 2.2,
		"fov": 45.0
	},
	{
		# Toma 4: Primer plano de tensión en la pelota
		"pos": Vector3(0.7, 0.35, -1.2),
		"look": Vector3(0.0, 0.11, -2.0),
		"duration": 2.0,
		"fov": 40.0
	}
]

# Posición de cámara de juego en PenaltyShoutOut
# Lejos y con poco FOV, como en FIFA: el arco se ve grande y el pateador no lo tapa.
const GAMEPLAY_POS = Vector3(0.0, 2.5, 14.0)
const GAMEPLAY_LOOK = Vector3(0.0, 1.1, -11.0)
const GAMEPLAY_FOV = 23.0

var current_tween: Tween

func _ready() -> void:
	if not camera:
		camera = get_viewport().get_camera_3d()
	start_intro()

func _unhandled_input(event: InputEvent) -> void:
	if is_intro_active:
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
			finish_intro()

func start_intro() -> void:
	is_intro_active = true
	current_shot_idx = 0
	_play_shot(0)

func _play_shot(idx: int) -> void:
	if not is_intro_active:
		return
		
	if idx >= shots.size():
		finish_intro()
		return
		
	current_shot_idx = idx
	var shot = shots[idx]
	
	if current_tween:
		current_tween.kill()
		
	if camera:
		camera.fov = shot.fov
		camera.global_position = shot.pos
		camera.look_at(shot.look, Vector3.UP)
		
		current_tween = create_tween()
		var drift_pos = shot.pos + Vector3(0.2, -0.1, -0.4)
		current_tween.tween_property(camera, "global_position", drift_pos, shot.duration)
		current_tween.tween_callback(func(): _play_shot(idx + 1))

func finish_intro() -> void:
	if not is_intro_active:
		return
	is_intro_active = false
	
	if current_tween:
		current_tween.kill()
		
	# Silbato del árbitro
	if sound_manager and sound_manager.has_method("play_whistle"):
		sound_manager.play_whistle()
		
	if not camera:
		intro_finished.emit()
		return
		
	# Transición suave de cámara hacia la perspectiva de juego
	var blend_tween = create_tween().set_parallel(true)
	blend_tween.tween_property(camera, "global_position", GAMEPLAY_POS, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	blend_tween.tween_property(camera, "fov", GAMEPLAY_FOV, 1.2)
	
	var target_rot_quat = Transform3D.IDENTITY.looking_at(GAMEPLAY_LOOK - GAMEPLAY_POS, Vector3.UP).basis.get_rotation_quaternion()
	blend_tween.tween_property(camera, "quaternion", target_rot_quat, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	blend_tween.finished.connect(func():
		camera.look_at(GAMEPLAY_LOOK, Vector3.UP)
		intro_finished.emit()
	)
