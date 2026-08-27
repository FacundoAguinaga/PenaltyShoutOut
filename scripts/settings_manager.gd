extends Node

const SAVE_PATH = "user://settings.cfg"

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 0.8
var fullscreen: bool = false
var difficulty: int = 1 # 0: Fácil, 1: Medio, 2: Difícil
var shots_per_round: int = 5 # 5, 10, 20, 40
var show_controls_help: bool = true

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func save_settings():
	var config = ConfigFile.new()
	config.set_value("audio", "master", master_volume)
	config.set_value("audio", "music", music_volume)
	config.set_value("audio", "sfx", sfx_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("game", "difficulty", difficulty)
	config.set_value("game", "shots_per_round", shots_per_round)
	config.set_value("game", "show_controls_help", show_controls_help)
	config.save(SAVE_PATH)
	apply_settings()

func load_settings():
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err == OK:
		master_volume = config.get_value("audio", "master", 1.0)
		music_volume = config.get_value("audio", "music", 0.8)
		sfx_volume = config.get_value("audio", "sfx", 0.8)
		fullscreen = config.get_value("video", "fullscreen", false)
		difficulty = config.get_value("game", "difficulty", 1)
		shots_per_round = config.get_value("game", "shots_per_round", 5)
		show_controls_help = config.get_value("game", "show_controls_help", true)
	apply_settings()

func apply_settings():
	# Video Mode
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# Audio Bus volumes if present
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("Music", music_volume)
	_set_bus_volume("SFX", sfx_volume)

func _set_bus_volume(bus_name: String, volume_linear: float):
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db = linear_to_db(clamp(volume_linear, 0.0001, 1.0))
		AudioServer.set_bus_volume_db(bus_idx, db)
		AudioServer.set_bus_mute(bus_idx, volume_linear <= 0.001)

func get_difficulty_resource_path() -> String:
	match difficulty:
		0:
			return "res://resources/goalkeeper_stats_facil.tres"
		1:
			return "res://resources/goalkeeper_stats_medio.tres"
		2:
			return "res://resources/goalkeeper_stats_dificil.tres"
		_:
			return "res://resources/goalkeeper_stats_medio.tres"

func get_difficulty_name() -> String:
	match difficulty:
		0:
			return "Fácil"
		1:
			return "Medio"
		2:
			return "Difícil"
		_:
			return "Medio"
