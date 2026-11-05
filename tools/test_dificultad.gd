extends SceneTree
# DIF=0|1|2  N=cantidad de tiros
var dif := int(OS.get_environment("DIF"))
var n := int(OS.get_environment("N")) if OS.get_environment("N") != "" else 30
var i := 0
var game: Node
var t := 0.0
var res := ""
var atajadas := 0
var goles := 0
var otros := 0
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	rng.seed = 1234
	_nuevo()

func _nuevo() -> void:
	if game: game.queue_free()
	game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	t = 0.0; res = ""
	var path: String = ["facil","medio","dificil"][dif]
	game.goalkeeper.stats = load("res://resources/goalkeeper_stats_%s.tres" % path)
	game.goal_scored.connect(func(_n): res = "gol")
	game.ball_saved.connect(func(): res = "ataja")
	game.ball_missed.connect(func(): res = "afuera")

func _physics_process(delta: float) -> bool:
	t += delta
	if t < 0.5: return false
	var ball = game.ball
	if t - delta < 0.5 or (t >= 0.5 and not game.get_meta("k", false)):
		game.set_meta("k", true)
		game.current_state = game.PenaltyState.BALL_FLYING
		game._shot_resolved = false
		# zona variada dentro del arco
		var x := rng.randf_range(-3.2, 3.2)
		var y := rng.randf_range(0.3, 2.1)
		var vz := -rng.randf_range(18.0, 30.0)
		var d := Vector3(0, 0.11, -0.5)
		var tv := (-12.0 - d.z) / vz
		ball.kick(Vector3(x / tv, (y - d.y + 0.5 * 9.8 * tv * tv) / tv, vz))
		return false
	if res != "" or t > 5.0:
		match res:
			"gol": goles += 1
			"ataja": atajadas += 1
			_: otros += 1
		i += 1
		if i >= n:
			print("RESULT dif=%d n=%d atajadas=%d goles=%d otros=%d  save%%=%.0f" % [dif, n, atajadas, goles, otros, 100.0 * atajadas / n])
			quit()
			return true
		_nuevo()
	return false
