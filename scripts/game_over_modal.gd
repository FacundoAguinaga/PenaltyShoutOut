extends CanvasLayer

@export var banner_label: Label
@export var result_title_label: Label
@export var kicker_score_label: Label
@export var goalkeeper_score_label: Label
@export var total_shots_label: Label
@export var accuracy_label: Label
@export var card_panel: PanelContainer

@export var btn_replay: Button
@export var btn_main_menu: Button

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if btn_replay:
		btn_replay.pressed.connect(_on_replay_pressed)
	if btn_main_menu:
		btn_main_menu.pressed.connect(_on_main_menu_pressed)

func setup_results(kicker_score: int, gk_score: int, total_shots: int):
	visible = true
	get_tree().paused = true

	if kicker_score_label:
		kicker_score_label.text = str(kicker_score)
	if goalkeeper_score_label:
		goalkeeper_score_label.text = str(gk_score)
	if total_shots_label:
		total_shots_label.text = "Tiros Totales: %d" % total_shots

	var accuracy = 0.0
	if total_shots > 0:
		accuracy = (float(kicker_score) / float(total_shots)) * 100.0

	if accuracy_label:
		accuracy_label.text = "Efectividad Tirador: %.1f%%" % accuracy

	if kicker_score > gk_score:
		if banner_label:
			banner_label.text = "¡VICTORIA DEL TIRADOR!"
			banner_label.modulate = Color(0.2, 0.9, 0.3) # Lime Green
		if result_title_label:
			result_title_label.text = "¡Gran actuación de disparo!"
	elif gk_score > kicker_score:
		if banner_label:
			banner_label.text = "¡VICTORIA DEL ARQUERO!"
			banner_label.modulate = Color(0.9, 0.3, 0.2) # Red/Orange
		if result_title_label:
			result_title_label.text = "¡El arquero dominó la tanda!"
	else:
		if banner_label:
			banner_label.text = "¡EMPATE!"
			banner_label.modulate = Color(0.9, 0.8, 0.2) # Gold
		if result_title_label:
			result_title_label.text = "Tanda de penaltis muy pareja."

	# Entrance Animation
	if card_panel:
		card_panel.scale = Vector2(0.7, 0.7)
		card_panel.modulate.a = 0.0
		var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card_panel, "scale", Vector2.ONE, 0.4)
		tween.tween_property(card_panel, "modulate:a", 1.0, 0.3)

func _on_replay_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
