extends Node

## SoundManager - Sistema de Sonido Avanzado
## - Soporte para Música aleatoria y salteo de pista con fade inicial y final suave
## - Parámetros de Reverb configurables por variable (efecto estadio / ambiente)
## - Crossfade de ambiente de hinchada continuo entre inicio y final (evita cortes)
## - Reacciones de público: festejos (cánticos/goles), quejas/abucheos, suspenso
## - Efectos de arbitraje: silbato corto y silbato largo de final de partido
## - Efectos físicos: patada, atajada, rebote en poste, pelota detenida

# ==================== PARÁMETROS CONFIGURABLES DE MÚSICA Y REVERB ====================
## Duración del fade out al cambiar o saltear canciones (en segundos)
@export var music_fade_out_duration: float = 0.45

## Duración del fade in al arrancar una nueva canción (en segundos)
@export var music_fade_in_duration: float = 0.55

## Volumen base de la música en dB
@export var music_volume_db: float = -4.0

## Activar efecto Reverb en la música
@export var music_reverb_enabled: bool = true:
	set(val):
		music_reverb_enabled = val
		_apply_music_reverb_params()

## Mezcla de reverb (0.0 = sonido seco puro, 1.0 = sólo reverb). 0.15 a 0.25 da sensación estadio agradable
@export_range(0.0, 1.0, 0.01) var music_reverb_wet: float = 0.18:
	set(val):
		music_reverb_wet = val
		_apply_music_reverb_params()

## Tamaño de la sala de reverb (0.0 a 1.0)
@export_range(0.0, 1.0, 0.01) var music_reverb_room_size: float = 0.55:
	set(val):
		music_reverb_room_size = val
		_apply_music_reverb_params()

## Amortiguación de agudos en reverb (0.0 a 1.0)
@export_range(0.0, 1.0, 0.01) var music_reverb_damping: float = 0.45:
	set(val):
		music_reverb_damping = val
		_apply_music_reverb_params()

# ==================== ESTADO INTERNO ====================
var _ambient_a: AudioStreamPlayer
var _ambient_b: AudioStreamPlayer
var _ambient_stream: AudioStream
var _ambient_duration: float = 0.0
## Volumen base del ambiente de la hinchada en dB (-80 a 6)
@export var ambient_volume_db: float = -4.0:
	set(val):
		ambient_volume_db = val
		_ambient_base_vol = val
		if _ambient_a and _ambient_a.playing:
			_ambient_a.volume_db = val
		if _ambient_b and _ambient_b.playing:
			_ambient_b.volume_db = val

var _ambient_base_vol: float = -4.0
var _ambient_timer: float = 0.0
var _crossfade_duration: float = 2.5
var _active_is_a: bool = true

# Reproductor de música y control de fades
var _music_player: AudioStreamPlayer
var _music_tween: Tween
var _music_tracks: Array[Dictionary] = []
var _current_track_idx: int = -1
var _is_transitioning: bool = false
var _reverb_effect: AudioEffectReverb

# Efectos SFX
var sfx_whistle: AudioStreamPlayer
var sfx_whistle_long: AudioStreamPlayer
var sfx_kick: AudioStreamPlayer
var sfx_goal: AudioStreamPlayer
var sfx_save: AudioStreamPlayer
var sfx_post: AudioStreamPlayer
var sfx_miss: AudioStreamPlayer
var sfx_crowd_chant: AudioStreamPlayer
var sfx_crowd_boo: AudioStreamPlayer
var sfx_crowd_anticipation: AudioStreamPlayer

# Sonidos de PES (tools/pes_extraer_sonidos.py), si estan extraidos. Como las animaciones,
# no van a git: sin ellos quedan los de audio/.
const PES_SONIDOS := "res://animaciones_pes/sonidos/"
## Volumen de cada grupo de sonidos de PES, para quedar a la altura de los de audio/ (se
## midio el volumen medio de cada uno con ffmpeg: rondan los mismos -15 a -20 dB). El gol
## va arriba; el "uh", la atajada y el abucheo, sin tapar la pelota ni al arquero.
const PES_VOLUMEN := {"gol": 6.0, "uh": 0.0, "atajada": -1.0, "abucheo": -3.0, "silbato": 1.0, "expectativa": 2.0, "golpe": 3.0, "pique": -4.0}
## Los golpes de la pelota (SE_Movement): de cada uno PES tiene 5 fuerzas (_01 a _05).
const PES_GOLPES := {
	"patada": "BALLHIT_INSTEP", "red": "BALLHIT_GOALNET", "palo": "BALLHIT_GOALPOST",
	"travesano": "BALLHIT_GOALBAR", "pique": "BALLHIT_BOUND", "agarra": "GK_CATCH", "rechazo": "GK_PUNCH",
}
## Cuantos sonidos de PES pueden sonar a la vez (la tribuna suena en capas).
const PES_VOCES := 6
## Un abucheo despues de un tiro errado, no siempre.
const PROB_ABUCHEO := 0.4
var _pes := {}
## Por golpe, las fuerzas que hay: {"red": {3: [streams], 4: [...]}, ...}
var _golpes := {}
var _pes_voces: Array[AudioStreamPlayer] = []
## La voz de la expectativa, para apagarla cuando llega el desenlace.
var _voz_expectativa: AudioStreamPlayer

signal song_changed(title: String, artist: String)
signal crowd_celebration_triggered(duration: float)

func _ready() -> void:
	_setup_audio_buses()
	_cargar_pes()
	_setup_ambient_players()
	_setup_music_player()
	_setup_sfx_players()
	scan_music_directory()
	start_stadium_ambience()

func _setup_audio_buses() -> void:
	# Asegurar que exista el bus Music
	var music_bus_idx = AudioServer.get_bus_index("Music")
	if music_bus_idx < 0:
		AudioServer.add_bus()
		music_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(music_bus_idx, "Music")
		AudioServer.set_bus_send(music_bus_idx, "Master")

	# Asegurar que exista el bus SFX
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	if sfx_bus_idx < 0:
		AudioServer.add_bus()
		sfx_bus_idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(sfx_bus_idx, "SFX")
		AudioServer.set_bus_send(sfx_bus_idx, "Master")

	# Agregar y configurar efecto de Reverb en el bus Music
	_reverb_effect = AudioEffectReverb.new()
	AudioServer.add_bus_effect(music_bus_idx, _reverb_effect)
	_apply_music_reverb_params()

func _apply_music_reverb_params() -> void:
	if _reverb_effect:
		var music_bus_idx = AudioServer.get_bus_index("Music")
		if music_bus_idx >= 0:
			AudioServer.set_bus_effect_enabled(music_bus_idx, 0, music_reverb_enabled)
		_reverb_effect.room_size = music_reverb_room_size
		_reverb_effect.damping = music_reverb_damping
		_reverb_effect.wet = music_reverb_wet
		_reverb_effect.dry = 1.0 - (music_reverb_wet * 0.4)
		_reverb_effect.spread = 0.8

func _find_audio_stream(base_name: String) -> AudioStream:
	var path_no_ext = base_name.get_basename() if "." in base_name else base_name
	for ext in [".mp3", ".wav", ".ogg"]:
		var full_path = path_no_ext + ext
		if ResourceLoader.exists(full_path):
			return load(full_path)
	return null

func _setup_ambient_players() -> void:
	_ambient_a = AudioStreamPlayer.new()
	_ambient_b = AudioStreamPlayer.new()
	_ambient_a.bus = "SFX"
	_ambient_b.bus = "SFX"
	add_child(_ambient_a)
	add_child(_ambient_b)
	
	_ambient_stream = _pes["ambiente"][0] if _pes.has("ambiente") else _find_audio_stream("res://audio/crowd_ambient")
	if _ambient_stream:
		_ambient_duration = _ambient_stream.get_length()
		_ambient_a.stream = _ambient_stream
		_ambient_b.stream = _ambient_stream
		print("[SoundManager] Sonido de hinchada cargado: ", _ambient_stream.resource_path, " (%.1fs)" % _ambient_duration)
	else:
		push_warning("[SoundManager] No se encontró audio/crowd_ambient (.mp3, .wav o .ogg)")

func _setup_music_player() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = music_volume_db
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)

func _setup_sfx_players() -> void:
	sfx_whistle = _create_sfx("res://audio/whistle", 0.0)
	sfx_whistle_long = _create_sfx("res://audio/whistle_long", 1.0)
	sfx_kick = _create_sfx("res://audio/kick", 3.0)
	sfx_goal = _create_sfx("res://audio/goal_cheer", 5.0)
	sfx_save = _create_sfx("res://audio/save", 2.5)
	sfx_post = _create_sfx("res://audio/post_hit", 4.0)
	sfx_miss = _create_sfx("res://audio/miss_groan", 2.5)
	sfx_crowd_chant = _create_sfx("res://audio/crowd_chant", 1.5)
	sfx_crowd_boo = _create_sfx("res://audio/crowd_boo", 2.0)
	sfx_crowd_anticipation = _create_sfx("res://audio/crowd_anticipation", 1.0)

func _create_sfx(path: String, vol_db: float) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.bus = "SFX"
	player.volume_db = vol_db
	add_child(player)
	var stream = _find_audio_stream(path)
	if stream:
		player.stream = stream
	return player

# ---------------------------------------------------------------- GESTIÓN DINÁMICA DE MÚSICA
func scan_music_directory() -> void:
	_music_tracks.clear()
	var dir_path := "res://audio/music/"
	var dir := DirAccess.open(dir_path)
	if not dir:
		push_warning("[SoundManager] No se pudo abrir el directorio: " + dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and not file_name.ends_with(".import") and not file_name.ends_with(".uid"):
			var ext := file_name.get_extension().to_lower()
			if ext in ["mp3", "wav", "ogg"]:
				var base_name := file_name.get_basename()
				var full_path := dir_path + file_name
				var title := base_name
				var artist := ""

				# Si el archivo tiene formato 'Artista - Título'
				if " - " in base_name:
					var parts = base_name.split(" - ", true, 1)
					artist = parts[0].strip_edges()
					title = parts[1].strip_edges()

				_music_tracks.append({
					"title": title,
					"artist": artist,
					"path": full_path
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	print("[SoundManager] Canciones cargadas desde audio/music/: ", _music_tracks.size())

## Saltear a la siguiente canción al azar o específica con fade out y fade in
func skip_track() -> void:
	play_random_music(true)

func play_random_music(with_fade: bool = true) -> void:
	if _music_tracks.is_empty():
		return
	var next_idx := randi() % _music_tracks.size()
	if _music_tracks.size() > 1 and next_idx == _current_track_idx:
		next_idx = (next_idx + 1) % _music_tracks.size()
	play_track(next_idx, with_fade)

func play_track(idx: int, with_fade: bool = true) -> void:
	if idx < 0 or idx >= _music_tracks.size():
		return
	
	if _music_tween:
		_music_tween.kill()

	var track = _music_tracks[idx]
	_current_track_idx = idx

	if not ResourceLoader.exists(track["path"]):
		return

	var stream = load(track["path"])
	if not stream:
		return

	if with_fade and _music_player.playing:
		# Fade out muy pequeño de la canción actual antes de entrar la nueva
		_is_transitioning = true
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, music_fade_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.tween_callback(func():
			_iniciar_stream_con_fade_in(stream, track)
		)
	else:
		_iniciar_stream_con_fade_in(stream, track)

func _iniciar_stream_con_fade_in(stream: AudioStream, track: Dictionary) -> void:
	_music_player.stream = stream
	_music_player.volume_db = -80.0
	_music_player.play()
	song_changed.emit(track["title"], track["artist"])

	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", music_volume_db, music_fade_in_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_tween.tween_callback(func():
		_is_transitioning = false
	)

func get_current_track_info() -> Dictionary:
	if _current_track_idx >= 0 and _current_track_idx < _music_tracks.size():
		return _music_tracks[_current_track_idx]
	return {"title": "Sin música", "artist": ""}

func stop_music(fade_out_time: float = 0.8) -> void:
	if _music_tween:
		_music_tween.kill()
	if fade_out_time > 0.0 and _music_player.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, fade_out_time).set_trans(Tween.TRANS_SINE)
		_music_tween.tween_callback(func(): _music_player.stop())
	else:
		_music_player.stop()

func _on_music_finished() -> void:
	if not _is_transitioning:
		play_random_music(true)

# ---------------------------------------------------------------- CROSSFADE HINCHADA
func start_stadium_ambience() -> void:
	if not _ambient_stream or _ambient_duration <= 0.0:
		push_warning("[SoundManager] start_stadium_ambience llamado pero no hay stream de hinchada cargado.")
		return
	_active_is_a = true
	_ambient_a.volume_db = _ambient_base_vol
	_ambient_b.volume_db = -80.0
	_ambient_a.play()
	_ambient_b.stop()
	_ambient_timer = 0.0
	print("[SoundManager] Ambiente de hinchada sonando: %s (vol: %.1f dB)" % [_ambient_stream.resource_path, _ambient_base_vol])

func _process(delta: float) -> void:
	if _ambient_stream and _ambient_duration > 0.0 and (_ambient_a.playing or _ambient_b.playing):
		_ambient_timer += delta
		var trigger_time = maxf(0.5, _ambient_duration - _crossfade_duration)
		if _ambient_timer >= trigger_time:
			_do_ambient_crossfade()

func _do_ambient_crossfade() -> void:
	_ambient_timer = 0.0
	var fade_out_player = _ambient_a if _active_is_a else _ambient_b
	var fade_in_player = _ambient_b if _active_is_a else _ambient_a
	_active_is_a = not _active_is_a

	fade_in_player.volume_db = -80.0
	fade_in_player.play()

	var t = create_tween().set_parallel(true)
	t.tween_property(fade_in_player, "volume_db", _ambient_base_vol, _crossfade_duration)
	t.tween_property(fade_out_player, "volume_db", -80.0, _crossfade_duration)
	t.chain().tween_callback(func(): fade_out_player.stop())

func stop_stadium_ambience() -> void:
	_ambient_a.stop()
	_ambient_b.stop()

# ---------------------------------------------------------------- SONIDOS DE PES
## Arma los grupos de sonidos de PES a partir de sonidos.json (lo que mide el extractor).
## Se eligen por lo que son, no por su lugar en el banco:
## - ambiente: el CZ_Base parejo y mas fuerte (58 s).
## - gol: un arranque de los cortos compartidos (2-3 s) mas un cuerpo que se va apagando
##   (los rugidos de 20-30 s de Goal y el "yeah" de 9-11 s de Goal_YEAH).
## - uh: la ola de "ohh" de Goal_OHH (7-9 s, pareja), para el tiro errado.
## - atajada: los "uuh" fuertes de Surprise. abucheo: Anger.
## - expectativa: el murmullo que crece antes del tiro (Special_CK, el de antes de un
##   corner, que sube de -34 a -24 dB en 14 s, y los de Special_Pass, que crecen y se
##   sostienen). Otros Special son copias de estos.
## - silbatos de un arbitro (A-F) por partido: el corto (un pitazo de menos de 0,35 s), el
##   del penal (un pitazo de 0,7-1,6 s) y el del final (el de mas pitazos).
func _cargar_pes() -> void:
	var json := PES_SONIDOS + "sonidos.json"
	if not FileAccess.file_exists(json):
		return
	var indice: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(json))
	var de := func(banco: String, filtro: Callable) -> Array:
		return (indice.get(banco, []) as Array).filter(filtro)
	var grupos := {
		"ambiente": [(de.call("SE_Cheers_CZ_Base", func(x): return x["duracion"] > 30.0) as Array).reduce(func(a, b): return a if a["volumen_db"] > b["volumen_db"] else b)],
		"gol_arranque": de.call("SE_Cheers_CM_Goal", func(x): return x["duracion"] < 3.0),
		"gol_cuerpo": de.call("SE_Cheers_CM_Goal", func(x): return x["duracion"] > 20.0) + de.call("SE_Cheers_CM_Goal_YEAH", func(x): return x["duracion"] > 9.0 and x["duracion"] < 12.0),
		"uh": de.call("SE_Cheers_CM_Goal_OHH", func(x): return x["duracion"] > 7.0 and x["duracion"] < 9.0),
		"atajada": de.call("SE_Cheers_CM_Surprise", func(x): return x["volumen_db"] > -20.0),
		"abucheo": de.call("SE_Cheers_CM_Anger", func(x): return true),
		"expectativa": de.call("SE_Cheers_CM_Special_CK", func(x): return true) + de.call("SE_Cheers_CM_Special_Pass", func(x): return true) + de.call("SE_Cheers_CM_Special_Pass_A", func(x): return true),
	}
	var arbitro: Array = indice.get("SE_Referee_" + "ABCDEF"[randi() % 6], [])
	if not arbitro.is_empty():
		grupos["silbato_corto"] = arbitro.filter(func(x): return x["pitazos"] == 1 and x["sonando"] < 0.35)
		grupos["silbato"] = arbitro.filter(func(x): return x["pitazos"] == 1 and x["sonando"] >= 0.7 and x["sonando"] <= 1.6)
		var final: Dictionary = arbitro.reduce(func(a, b): return b if [b["pitazos"], b["sonando"]] > [a["pitazos"], a["sonando"]] else a)
		grupos["silbato_final"] = [final]
	for grupo: String in grupos:
		var streams: Array[AudioStream] = []
		for x in grupos[grupo]:
			if x == null:
				continue
			var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(PES_SONIDOS + str(x["archivo"])))
			if stream:
				streams.append(stream)
		if not streams.is_empty():
			_pes[grupo] = streams
	for x: Dictionary in indice.get("SE_Movement", []):
		var cue := str(x["cue"]).trim_prefix("SE_PL_")
		var nivel := int(cue.get_slice("_", cue.get_slice_count("_") - 1))
		var base := cue.left(cue.rfind("_"))
		for tipo: String in PES_GOLPES:
			if PES_GOLPES[tipo] == base:
				var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(PES_SONIDOS + str(x["archivo"])))
				if stream:
					var niveles: Dictionary = _golpes.get_or_add(tipo, {})
					(niveles.get_or_add(nivel, []) as Array).append(stream)
	for i in PES_VOCES:
		var voz := AudioStreamPlayer.new()
		voz.bus = "SFX"
		add_child(voz)
		_pes_voces.append(voz)
	print("[SoundManager] Sonidos de PES: ", _pes.keys(), " golpes: ", _golpes.keys())

## Suena uno al azar del grupo, en una voz libre (o en la que hace mas que suena).
## El desenlace de un tiro apaga la expectativa que venia sonando.
func _pes_sonar(grupo: String, volumen_db: float) -> bool:
	if not _pes.has(grupo):
		return false
	if grupo in ["gol_cuerpo", "uh", "atajada"]:
		_apagar_expectativa()
	var voz := _pes_voces[0]
	for v in _pes_voces:
		if not v.playing:
			voz = v
			break
		if v.get_playback_position() > voz.get_playback_position():
			voz = v
	voz.stream = (_pes[grupo] as Array).pick_random()
	voz.volume_db = volumen_db
	voz.play()
	if grupo == "expectativa":
		_voz_expectativa = voz
	return true

## Un golpe de la pelota con la fuerza de PES mas cercana (fuerza 0 a 1 -> _01 a _05).
func _golpe_pes(tipo: String, fuerza: float, volumen_db: float) -> bool:
	if not _golpes.has(tipo):
		return false
	var niveles: Dictionary = _golpes[tipo]
	var buscado := 1 + roundi(clampf(fuerza, 0.0, 1.0) * 4.0)
	var mejor: int = niveles.keys()[0]
	for n: int in niveles:
		if absi(n - buscado) < absi(mejor - buscado):
			mejor = n
	var voz := _pes_voces[0]
	for v in _pes_voces:
		if not v.playing:
			voz = v
			break
	voz.stream = (niveles[mejor] as Array).pick_random()
	voz.volume_db = volumen_db
	voz.play()
	return true

func _apagar_expectativa() -> void:
	if not _voz_expectativa or not _voz_expectativa.playing:
		return
	var voz := _voz_expectativa
	_voz_expectativa = null
	var t := create_tween()
	t.tween_property(voz, "volume_db", -40.0, 0.6)
	t.tween_callback(voz.stop)

# ---------------------------------------------------------------- EVENTOS SFX
func play_whistle() -> void:
	if not _pes_sonar("silbato", PES_VOLUMEN["silbato"]):
		_play(sfx_whistle)

func play_whistle_long() -> void:
	if not _pes_sonar("silbato_final", PES_VOLUMEN["silbato"]):
		_play(sfx_whistle_long)

## velocidad: la de la pelota al salir (un penal va de unos 12 a 35 m/s).
func play_kick(velocidad := 25.0) -> void:
	if not _golpe_pes("patada", (velocidad - 12.0) / 20.0, PES_VOLUMEN["golpe"]):
		_play(sfx_kick)

## Un golpe de la pelota (SoccerBall.impacto): palo, travesano, red o pique.
func play_impacto(tipo: String, fuerza: float) -> void:
	if not _golpe_pes(tipo, fuerza, PES_VOLUMEN["pique" if tipo == "pique" else "golpe"]) and tipo in ["palo", "travesano"]:
		_play(sfx_post)

func play_goal() -> void:
	if _pes_sonar("gol_cuerpo", PES_VOLUMEN["gol"]):
		_pes_sonar("gol_arranque", PES_VOLUMEN["gol"])
	else:
		_play(sfx_goal)
		if sfx_crowd_chant:
			_play(sfx_crowd_chant)
	crowd_celebration_triggered.emit(5.0)

## agarra: si la retiene (si no, la rechaza).
func play_save(agarra := true) -> void:
	if not _golpe_pes("agarra" if agarra else "rechazo", 0.8, PES_VOLUMEN["golpe"]):
		_play(sfx_save)
	if not _pes_sonar("atajada", PES_VOLUMEN["atajada"]) and sfx_crowd_boo:
		_play(sfx_crowd_boo)

func play_post() -> void:
	_play(sfx_post)
	if not _pes_sonar("uh", PES_VOLUMEN["uh"]) and sfx_crowd_boo:
		_play(sfx_crowd_boo)

func play_miss() -> void:
	if _pes_sonar("uh", PES_VOLUMEN["uh"]):
		if randf() < PROB_ABUCHEO:
			_pes_sonar("abucheo", PES_VOLUMEN["abucheo"])
	else:
		_play(sfx_miss)
		if sfx_crowd_boo:
			_play(sfx_crowd_boo)

func play_anticipation() -> void:
	if not _pes_sonar("expectativa", PES_VOLUMEN["expectativa"]):
		_play(sfx_crowd_anticipation)

func _play(player: AudioStreamPlayer) -> void:
	if player and player.stream:
		player.stop()
		player.play()
