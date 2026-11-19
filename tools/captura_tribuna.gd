extends Node3D

# Saca fotos de la tribuna desde varias camaras para revisar como se ve la
# hinchada sin tener que jugar. Uso:
#   godot --path . res://tools/captura_tribuna.tscn -- [carpeta_salida] [reaccion] [nivel]
# reaccion: normal | gol | lamento | tension
# Un cuarto argumento con el nombre de una animacion hace que todos la hagan.
# nivel: -1 automatico (por defecto) | 0 cerca | 1 media | 2 carteles

const TOMAS := [
	["juego", Vector3(0, 2.5, 14), Vector3(0, 1.2, 0), 23.0],
	["arco_cerca", Vector3(0, 2.2, 2), Vector3(-6, 4.0, -26), 40.0],
	["primer_plano", Vector3(-8, 3.0, -14), Vector3(-12, 3.2, -22), 35.0],
	["panoramica", Vector3(0, 22, 55), Vector3(0, 4, -10), 60.0],
	["lateral", Vector3(0, 6, 20), Vector3(-40, 6, 20), 55.0],
	["esquina", Vector3(8, 9, 12), Vector3(-45, 7, -30), 50.0],
	["esquina_norte", Vector3(-8, 14, 70), Vector3(45, 8, 118), 60.0],
	# Con campo de vision negativo es una vista desde arriba (sin perspectiva)
	# de ese ancho en metros, cortando el techo.
	["cenital", Vector3(0, 200, 20), Vector3(0, 0, 20), -170.0],
]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var carpeta: String = args[0] if args.size() > 0 else "user://capturas"
	var reaccion: String = args[1] if args.size() > 1 else "normal"
	DirAccess.make_dir_recursive_absolute(carpeta)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var env := WorldEnvironment.new()
	env.environment = load("res://resources/stadium_environment.tres")
	add_child(env)
	var estadio: Node3D = load("res://scenes/stadium.tscn").instantiate()
	add_child(estadio)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()

	await get_tree().create_timer(1.0).timeout
	var hinchada := estadio.get_node_or_null("Crowd")
	var nivel: int = int(args[2]) if args.size() > 2 else -1
	if hinchada:
		hinchada.forzar_nivel = nivel
		if args.size() > 3:
			hinchada.depurar_animacion = args[3]
		match reaccion:
			"gol": hinchada.celebrate_goal(true, 60.0)
			"lamento": hinchada.lament_miss(true, 60.0)
			"tension": hinchada.prepare_kick_tension()
	await get_tree().create_timer(1.5).timeout

	for t in TOMAS:
		cam.global_position = t[1]
		if t[3] > 0.0:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.near = 0.05
			cam.look_at(t[2])
			cam.fov = t[3]
		else:
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = -t[3]
			cam.near = t[1].y - 23.0
			cam.far = t[1].y + 5.0
			cam.look_at(t[2], Vector3.FORWARD)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s_%s%s.png" % [carpeta, t[0], reaccion, "" if nivel < 0 else "_nivel%d" % nivel])
		# Cuanto cuesta la hinchada: tiempo por cuadro y triangulos, con y sin.
		var con := await _medir()
		var linea := "[captura] %-12s %5.1f ms  %8d tris" % [t[0], con[0], con[1]]
		if hinchada:
			hinchada.visible = false
			var sin := await _medir()
			hinchada.visible = true
			linea += "   | sin hinchada %5.1f ms  %8d tris   | hinchada: %4.1f ms  %7d tris" % [
					sin[0], sin[1], con[0] - sin[0], con[1] - sin[1]]
		print(linea)
	get_tree().quit()

func _medir() -> Array:
	for i in 15:
		await RenderingServer.frame_post_draw
	var t0 := Time.get_ticks_usec()
	for i in 40:
		await RenderingServer.frame_post_draw
	return [(Time.get_ticks_usec() - t0) / 40000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]
