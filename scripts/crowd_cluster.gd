class_name CrowdCluster
extends Node3D

## Altura del salto normal de la hinchada (en metros)
@export var base_jump_height: float = 0.075

## Altura del salto al festejar gol (en metros)
@export var goal_jump_height: float = 0.22

## Frecuencia de salto normal (saltos por segundo / Hz)
@export var base_frequency: float = 2.1

## Frecuencia de salto en gol (más rápido y eufórico)
@export var goal_frequency: float = 3.2

var _base_y: float = 0.0
var _time_accum: float = 0.0
var _phase_offset: float = 0.0
var _celebration_timer: float = 0.0
var _celebration_duration: float = 5.0
var _celebration_weight: float = 0.0
var _is_initialized: bool = false

func _ready() -> void:
	add_to_group("crowd_clusters")
	# Guardar la altura base a la que fue colocado sobre el escalón
	_base_y = position.y
	
	# Desfase orgánico según la posición para que hagan oleadas naturales
	var pos = global_position if is_inside_tree() else position
	var seed_val = int(abs(pos.x * 73.0 + pos.y * 31.0 + pos.z * 53.0))
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val != 0 else 42
	_phase_offset = (pos.x * 0.35 + pos.z * 0.2) + rng.randf_range(-0.35, 0.35)
	_time_accum = rng.randf_range(0.0, 1.0)
	
	# Conexión automática con SoundManager
	if is_inside_tree():
		var sm = get_node_or_null("/root/SoundManager")
		if sm and sm.has_signal("crowd_celebration_triggered"):
			sm.crowd_celebration_triggered.connect(celebrate_goal)
			
	_is_initialized = true

func _process(delta: float) -> void:
	if not _is_initialized:
		return
	
	# Decaimiento suave del festejo de gol
	if _celebration_timer > 0.0:
		_celebration_timer -= delta
		_celebration_weight = clampf(_celebration_timer / _celebration_duration, 0.0, 1.0)
	else:
		_celebration_weight = 0.0
	
	# Mezclar frecuencia y altura entre cántico normal y festejo de gol
	var cur_freq = lerpf(base_frequency, goal_frequency, _celebration_weight)
	var cur_height = lerpf(base_jump_height, goal_jump_height, _celebration_weight)
	
	_time_accum += delta * cur_freq
	var cycle_t = fmod(_time_accum + _phase_offset, 1.0)
	if cycle_t < 0.0:
		cycle_t += 1.0
	
	# Curva de salto humana:
	# 0.0 a 0.72: vuelo en el aire (curva senoidal)
	# 0.72 a 1.0: pies en el escalón preparando el siguiente salto
	var jump_offset = 0.0
	if cycle_t < 0.72:
		jump_offset = sin(cycle_t / 0.72 * PI) * cur_height
	
	position.y = _base_y + jump_offset

## Activa la celebración de gol durante 'duration' segundos
func celebrate_goal(duration: float = 5.0) -> void:
	_celebration_duration = maxf(1.0, duration)
	_celebration_timer = _celebration_duration
	_celebration_weight = 1.0
