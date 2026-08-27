extends Area3D
class_name GoalZone

@export var goal_width: float = 7.32
@export var goal_height: float = 2.44
@export var goal_depth: float = 2.0

var is_goal_side: bool = true

signal goal_detected
signal ball_hit_post(post_position: Vector3)
signal ball_hit_crossbar(crossbar_position: Vector3)

func _ready():
	body_entered.connect(_on_body_entered)
	_resize_collision()

func _resize_collision():
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape and collision_shape.shape is BoxShape3D:
		collision_shape.shape.size = Vector3(goal_width, goal_height, goal_depth)

func _on_body_entered(body: Node):
	if body is SoccerBall:
		goal_detected.emit()
