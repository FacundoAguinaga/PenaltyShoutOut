extends CanvasLayer

## Modo debug de animaciones: que clip tiene cada personaje y por que lo eligio.
##   F3  mostrar u ocultar el panel
##   F4  copiar el historial del partido, para pegarlo donde haga falta
## El historial se junta siempre, aunque el panel este oculto.

const MAXIMO_HISTORIAL := 400
const ANCHO := 372.0
## Lo que entra en una linea del panel con la letra chica.
const COLUMNAS := 54
## Cuantos cambios de clip recientes se ven: el resto queda en el historial copiado.
const RECIENTES := 4
const LIBRERIA_FOTO := "pes_foto/"

var _kicker: PlayerKicker
var _arquero: PlayerGoalkeeper
var _juego: GameManager
var _panel: ColorRect
var _texto: Label
var _historial: PackedStringArray = []
var _clip_kicker := ""
var _clip_arquero := ""
var _aviso := 0.0

func _init(kicker: PlayerKicker, arquero: PlayerGoalkeeper, juego: GameManager) -> void:
	name = "DepurarAnimaciones"
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_kicker = kicker
	_arquero = arquero
	_juego = juego

func _ready() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.0, 0.0, 0.0, 0.72)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -ANCHO - 8.0
	_panel.offset_right = -8.0
	_panel.offset_top = 64.0
	_panel.visible = false
	add_child(_panel)

	_texto = Label.new()
	var fuente := SystemFont.new()
	fuente.font_names = PackedStringArray(["monospace"])
	_texto.add_theme_font_override("font", fuente)
	_texto.add_theme_font_size_override("font_size", 11)
	_texto.position = Vector2(8.0, 6.0)
	_panel.add_child(_texto)

	_juego.penalty_started.connect(func(): _anotar("=== Tiro %d ===" % _juego.current_shot))
	_juego.kick_released.connect(func(potencia: float, destino: Vector3): _anotar(
		"Soltó: potencia %.0f, destino (%.2f, %.2f)%s" % [potencia, destino.x, destino.y, " PICADA" if _kicker.es_picada() else ""]))
	_juego.shot_complete.connect(func(resultado: String): _anotar("Resultado: %s" % resultado))
	_kicker.ball_launch_requested.connect(func(v: Vector3): _anotar("Patada: %.1f m/s, %s" % [v.length(), _resumen_remate()]))

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F3:
			_panel.visible = not _panel.visible
		KEY_F4:
			DisplayServer.clipboard_set("\n".join(_historial))
			_aviso = 2.0

func _process(delta: float) -> void:
	_aviso = maxf(_aviso - delta, 0.0)
	_clip_kicker = _seguir_clip("Pateador", _kicker.animation_player, _clip_kicker)
	_clip_arquero = _seguir_clip("Arquero ", _arquero.animation_player, _clip_arquero)
	if _panel.visible:
		_texto.text = _armar_texto()
		_panel.size.y = _texto.get_minimum_size().y + 12.0

## Anota cada cambio de clip. La foto de PesAnimaciones.transicion dura un instante.
func _seguir_clip(quien: String, ap: AnimationPlayer, anterior: String) -> String:
	var clip := String(ap.current_animation)
	if clip == anterior or clip == "" or clip.begins_with(LIBRERIA_FOTO):
		return anterior
	_anotar("%s -> %s (desde %.2f s)" % [quien, clip.trim_prefix("pes/"), ap.current_animation_position])
	return clip

func _anotar(linea: String) -> void:
	_historial.append("[%7.2f] %s" % [Time.get_ticks_msec() / 1000.0, linea])
	if _historial.size() > MAXIMO_HISTORIAL:
		_historial.remove_at(0)

func _estado_clip(ap: AnimationPlayer) -> String:
	if String(ap.current_animation) == "":
		return "(sin clip)"
	return "%s\n  %.2f / %.2f s  x%.2f" % [String(ap.current_animation).trim_prefix("pes/").left(COLUMNAS), ap.current_animation_position, ap.current_animation_length, ap.speed_scale]

func _resumen_remate() -> String:
	var r: Dictionary = _kicker._remate
	if r.is_empty():
		return "(sin elegir)"
	return "%s | estilo %s, %s, %s, pie %s%s" % [str(r["anim"]).trim_prefix("remate_"), r["estilo"] if r["estilo"] != "" else "base", r["potencia"], r["metodo"], r["dir"], ", vaselina" if r["lob"] else ""]

func _armar_texto() -> String:
	var k := _kicker
	var a := _arquero
	var lineas := PackedStringArray([
		"F3 ocultar  F4 copiar historial%s" % ("  [COPIADO]" if _aviso > 0.0 else ""),
		"",
		"PATEADOR  %s  tiro %d" % [PlayerKicker.KickState.keys()[k.current_state], _juego.current_shot],
		_estado_clip(k.animation_player),
		"Carrera %s  potencia %.0f  picada %s  reaccion %s" % [k._estilo if k._estilo != "" else "base", k.final_power if k.current_state >= PlayerKicker.KickState.RUN_UP else k.power, "SI" if k.es_picada() else "no", k._reaccion if k._reaccion != "" else "-"],
		"Remate %s" % (str(k._remate["anim"]).trim_prefix("remate_").left(COLUMNAS - 7) if not k._remate.is_empty() else "-"),
		"",
		"ARQUERO  %s  %s" % [PlayerGoalkeeper.GKState.keys()[a.state], ResultModule.Resultado.keys()[a._resultado]],
		_estado_clip(a.animation_player),
	])
	if a._current_anim and a.state != PlayerGoalkeeper.GKState.IDLE:
		lineas.append("Estirada %s" % a._current_anim.anim_name.trim_prefix("pes/").left(COLUMNAS - 9))
		lineas.append("  %s %s  toca %.2f s  punto (%.2f, %.2f)" % [DiveAnimData.Zone.keys()[a._current_anim.zone], DiveAnimData.Tipo.keys()[a._current_anim.tipo], a._current_anim.contact_time, a._current_anim.canonical_target.x, a._current_anim.canonical_target.y])
		lineas.append("  objetivo (%.2f, %.2f)%s" % [a._objetivo.x, a._objetivo.y, "  SE JUGO" if a._ya_jugado else ""])
	var sigue: String = str(a._cola_reaccion[0]["anim"]).trim_prefix("pes/") if not a._cola_reaccion.is_empty() else "-"
	lineas.append("Sigue %s" % sigue.left(COLUMNAS - 6))
	lineas.append("")
	for linea in _historial.slice(maxi(_historial.size() - RECIENTES, 0)):
		lineas.append(linea.substr(10).left(COLUMNAS))
	return "\n".join(lineas)
