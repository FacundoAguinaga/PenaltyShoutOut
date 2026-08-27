extends CanvasLayer

@export var pause_panel: Control
@export var options_panel: Control

@export_group("Main Pause Buttons")
@export var btn_resume: Button
@export var btn_restart: Button
@export var btn_options: Button
@export var btn_main_menu: Button
@export var btn_quit: Button

@export_group("Options Controls")
@export var slider_master: HSlider
@export var slider_music: HSlider
@export var slider_sfx: HSlider
@export var check_fullscreen: CheckBox
@export var option_difficulty: OptionButton
@export var option_shots: OptionButton
@export var btn_close_options: Button

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if options_panel:
		options_panel.visible = false

	_connect_signals()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	var new_pause_state = not get_tree().paused
	get_tree().paused = new_pause_state
	visible = new_pause_state

	if new_pause_state:
		if pause_panel:
			pause_panel.visible = true
		if options_panel:
			options_panel.visible = false
		if btn_resume:
			btn_resume.grab_focus()

func resume():
	get_tree().paused = false
	visible = false

func _connect_signals():
	if btn_resume:
		btn_resume.pressed.connect(resume)
	if btn_restart:
		btn_restart.pressed.connect(_on_restart_pressed)
	if btn_options:
		btn_options.pressed.connect(_on_options_pressed)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_main_menu_pressed)
	if btn_quit:
		btn_quit.pressed.connect(_on_quit_pressed)
	if btn_close_options:
		btn_close_options.pressed.connect(_on_close_options_pressed)

	_setup_options_signals()

func _setup_options_signals():
	var settings = get_node_or_null("/root/SettingsManager")

	if slider_master:
		if settings: slider_master.value = settings.master_volume
		slider_master.value_changed.connect(func(val):
			if settings:
				settings.master_volume = val
				settings.save_settings()
		)

	if slider_music:
		if settings: slider_music.value = settings.music_volume
		slider_music.value_changed.connect(func(val):
			if settings:
				settings.music_volume = val
				settings.save_settings()
		)

	if slider_sfx:
		if settings: slider_sfx.value = settings.sfx_volume
		slider_sfx.value_changed.connect(func(val):
			if settings:
				settings.sfx_volume = val
				settings.save_settings()
		)

	if check_fullscreen:
		if settings: check_fullscreen.button_pressed = settings.fullscreen
		check_fullscreen.toggled.connect(func(toggled):
			if settings:
				settings.fullscreen = toggled
				settings.save_settings()
		)

	if option_difficulty:
		option_difficulty.clear()
		option_difficulty.add_item("Fácil", 0)
		option_difficulty.add_item("Medio", 1)
		option_difficulty.add_item("Difícil", 2)
		if settings: option_difficulty.selected = settings.difficulty
		option_difficulty.item_selected.connect(func(idx):
			if settings:
				settings.difficulty = idx
				settings.save_settings()
		)

	if option_shots:
		option_shots.clear()
		option_shots.add_item("5 Tiros", 0)
		option_shots.add_item("10 Tiros", 1)
		option_shots.add_item("20 Tiros", 2)
		option_shots.add_item("40 Tiros", 3)
		
		var shots_map = [5, 10, 20, 40]
		if settings:
			var curr_idx = shots_map.find(settings.shots_per_round)
			option_shots.selected = curr_idx if curr_idx != -1 else 0
			
		option_shots.item_selected.connect(func(idx):
			if settings and idx >= 0 and idx < shots_map.size():
				settings.shots_per_round = shots_map[idx]
				settings.save_settings()
		)

func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_options_pressed():
	if pause_panel: pause_panel.visible = false
	if options_panel: options_panel.visible = true

func _on_close_options_pressed():
	if options_panel: options_panel.visible = false
	if pause_panel: pause_panel.visible = true

func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_quit_pressed():
	get_tree().quit()
