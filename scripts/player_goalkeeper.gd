extends Node3D
class_name PlayerGoalkeeper

enum GKState { IDLE, ANTICIPATING, DIVING, RESULT, RECOVERING, RESET }

@export var stats: GoalkeeperStats
@export var animation_player: AnimationPlayer
@export var animation_tree: AnimationTree
@export var skeleton: Skeleton3D
@export var left_hand_ik: TwoBoneIK3D
@export var right_hand_ik: TwoBoneIK3D
@export var ball: SoccerBall

@export_group("System Config")
@export var dificultad: float = 0.4
@export var libreria_animaciones: Array[DiveAnimData]
@export var goal_width: float = 7.32
@export var goal_height: float = 2.44

signal keeper_save(ball: SoccerBall)
signal keeper_deflect(ball: SoccerBall)

var state: GKState = GKState.IDLE
var reposition_module: RepositionModule
var _current_anim: DiveAnimData
var _base_position: Vector3

func _ready():
	_base_position = global_position
	
	if not animation_player:
		animation_player = _find_node_of_type(self, "AnimationPlayer") as AnimationPlayer
	if not animation_tree:
		animation_tree = _find_node_of_type(self, "AnimationTree") as AnimationTree
		
	if animation_tree:
		animation_tree.active = false

	if not skeleton:
		skeleton = _find_node_of_type(self, "Skeleton3D") as Skeleton3D

	# Inicializamos el RepositionModule con IK en la mano derecha por ahora (se podría mejorar para usar la correcta según lado)
	var main_ik = right_hand_ik if right_hand_ik else left_hand_ik
	reposition_module = RepositionModule.new(self, animation_player, main_ik)
	
	reset_to_idle()

func _process(delta: float) -> void:
	if state == GKState.DIVING:
		reposition_module.process_frame(delta)

func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null

func on_ball_kicked(shot: ShotData) -> void:
	var prediccion := PredictionModule.calcular_target_real(shot.origin, shot.initial_velocity)

	if not prediccion.es_gol_potencial:
		# Va afuera, nos quedamos quietos o simulamos reacción tardía/corta
		return 

	var error := ErrorModule.aplicar_error(prediccion.target, dificultad)
	var anim := DiveAnimData.AnimSelector.elegir_animacion(error.target_percibido, libreria_animaciones, goal_width, goal_height)
	
	if not anim:
		print("[Goalkeeper] No hay animación disponible en la librería.")
		return
		
	var delay := TimingModule.calcular_delay_inicio(anim, prediccion.tiempo_vuelo, error.delay_extra)

	state = GKState.ANTICIPATING
	await get_tree().create_timer(delay).timeout
	
	if state == GKState.ANTICIPATING:
		iniciar_dive(anim, error.target_percibido)

func iniciar_dive(anim: DiveAnimData, target_percibido: Vector2) -> void:
	state = GKState.DIVING
	_current_anim = anim
	
	# Restaurar pos base antes del dive por si acaso
	global_position = _base_position
	
	reposition_module.iniciar_offset(target_percibido, anim, _base_position)
	
	if animation_player.has_animation(anim.anim_name):
		animation_player.play(anim.anim_name)
	
	# Usamos un timer simple para saber cuándo evaluar el resultado, 
	# idealmente usaríamos Call Method Tracks en el AnimationPlayer
	await get_tree().create_timer(anim.contact_time).timeout
	
	if state == GKState.DIVING:
		_on_dive_terminado(anim)

func _on_dive_terminado(anim: DiveAnimData) -> void:
	var atajo := ResultModule.evaluar_resultado(anim)
	state = GKState.RESULT
	
	if atajo:
		keeper_save.emit(ball)
	else:
		# Podría ser deflect o nada, por ahora simplificamos
		pass

func reset_to_idle():
	state = GKState.IDLE
	global_position = _base_position
	if animation_player and animation_player.has_animation("Goalkeeperidle"):
		animation_player.play("Goalkeeperidle")
	if reposition_module:
		reposition_module._stop_ik()
