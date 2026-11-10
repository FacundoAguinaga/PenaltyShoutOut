extends Node

## Juega tiros de verdad y anota cuadro a cuadro donde estan los cuerpos, con los
## fundidos y empalmes incluidos (pes_auditar solo mira cada clip por separado).
## Por tiro: distancia real del dedo a la pelota al golpear, lo mas bajo de la malla
## y el mayor salto de la cadera entre dos cuadros, con el clip y el momento.
##   godot --headless --path . res://tools/pes_trazar.tscn
## TIROS=n cuantos tiros (por defecto 9); PICADA=1 los pica; DETALLE=1 ademas escribe
## cada cuadro en animaciones_pes/traza.csv. Cada tiro sigue hasta el arranque del
## proximo, para ver el acomodo: "salto visible" no cuenta lo que tapa el fundido a negro.

const PesCuerpo := preload("res://tools/pes_cuerpo.gd")
const CADERA := "mixamorig1Hips"
const DEDO := "mixamorig1RightToeBase"
const OBJETIVOS := [Vector2(-2.6, 2.05), Vector2(0.2, 2.15), Vector2(2.6, 2.05), Vector2(-2.5, 1.25), Vector2(-0.1, 1.2), Vector2(2.5, 1.25), Vector2(-2.4, 0.35), Vector2(0.15, 0.35), Vector2(2.4, 0.35)]
const DURACION := 11.0
const TIRON := 0.04

var _total := int(OS.get_environment("TIROS")) if OS.get_environment("TIROS") != "" else OBJETIVOS.size()
var _detalle := OS.get_environment("DETALLE") != ""
var _picada := OS.get_environment("PICADA") != ""
var _csv: FileAccess
var _i := 0
var _juego: Node
var _t := 0.0
var _pateado := false
var _kicker: Node3D
var _arquero: Node3D
var _pelota: RigidBody3D
var _c_k: PesCuerpo
var _c_a: PesCuerpo
var _datos := {}
var _peores := {"dedo": [], "malla_k": [], "malla_a": [], "vel_k": [], "vel_a": []}

func _ready() -> void:
	if _detalle:
		_csv = FileAccess.open(PesAnimaciones.DIR + "traza.csv", FileAccess.WRITE)
		_csv.store_line("tiro,t,quien,clip,t_clip,x,y,z,malla_y,salto,negro")
	_nuevo()

func _nuevo() -> void:
	if _juego:
		_juego.queue_free()
	_juego = load("res://scenes/game.tscn").instantiate()
	add_child(_juego)
	_t = 0.0
	_pateado = false
	_kicker = _juego.get_node("Kicker")
	_arquero = _juego.get_node("Goalkeeper")
	_pelota = _juego.get_node("Ball")
	_c_k = PesCuerpo.new(_kicker.skeleton)
	_c_a = PesCuerpo.new(_arquero.skeleton)
	_datos = {"dedo": -1.0, "k": _vacio(), "a": _vacio(), "cruce": Vector2.INF, "t_cruce": 0.0, "t_golpe": 0.0}
	_kicker.ball_launch_requested.connect(_al_golpear, CONNECT_DEFERRED)
	_kicker.ball_launch_requested.connect(func(_v):
		_datos["dedo"] = _dist_dedo()
		_datos["t_golpe"] = _t
		_datos["remate"] = str(_kicker._remate["anim"]).trim_prefix("remate_"))

func _vacio() -> Dictionary:
	return {"prev": Vector3.INF, "min_y": INF, "min_info": "", "salto": 0.0, "salto_info": "", "parado": 0, "parado_max": 0, "parado_clip": ""}

func _dist_dedo() -> float:
	var sk: Skeleton3D = _kicker.skeleton
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(DEDO)).origin).distance_to(_pelota.global_position)

func _al_golpear(_v: Vector3) -> void:
	_datos["pelota_vel"] = _pelota.linear_velocity

func _anotar(clave: String, quien: Node3D, cuerpo: PesCuerpo, delta: float) -> void:
	var d: Dictionary = _datos[clave]
	var sk: Skeleton3D = quien.skeleton
	var ap: AnimationPlayer = quien.animation_player
	var clip := String(ap.current_animation)
	var t_clip := ap.current_animation_position if clip != "" else 0.0
	var cadera := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(CADERA)).origin
	var bajo := cuerpo.lo_mas_bajo_ahora()
	var salto := 0.0
	if d["prev"] != Vector3.INF:
		salto = (d["prev"] as Vector3).distance_to(cadera)
	if bajo["y"] < d["min_y"]:
		d["min_y"] = bajo["y"]
		d["min_info"] = "%s %s t=%.2f" % [bajo["hueso"], clip, t_clip]
	# Quieto: la cadera no se mueve ni medio milimetro y no hay clip andando.
	if ap.is_playing():
		d["parado"] = 0
	else:
		d["parado"] += 1
		if d["parado"] > d["parado_max"]:
			d["parado_max"] = d["parado"]
			d["parado_clip"] = "t=%.2f" % _t
	var negro: float = _juego._negro.color.a if _juego._negro else 0.0
	# Lo que tapa el negro no se ve, y en un tiron de la maquina avanza todo junto.
	# Al arrancar el festejo se lo recoloca, pero en un corte de camara.
	var corte: bool = quien == _kicker and _kicker.en_cinematica != d.get("en_cine", false)
	d["en_cine"] = quien == _kicker and _kicker.en_cinematica
	if negro > 0.99 or delta > TIRON or corte:
		salto = 0.0
	if salto > d["salto"]:
		d["salto"] = salto
		d["salto_info"] = "%s t=%.2f" % [clip, t_clip]
	d["prev"] = cadera
	if _csv:
		_csv.store_line("%d,%.3f,%s,%s,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.2f" % [_i, _t, clave, clip, t_clip, cadera.x, cadera.y, cadera.z, bajo["y"], salto, negro])

func _process(delta: float) -> void:
	_t += delta
	if not _pateado and _t > 0.5:
		_arquero.dificultad = 0.0
		_kicker.power = 80.0
		var o: Vector2 = OBJETIVOS[_i % OBJETIVOS.size()]
		_kicker.aim_target_3d = Vector3(o.x, o.y, 0.0)
		_kicker._release_kick(_picada)
		_pateado = true
	if _datos["cruce"] == Vector2.INF and _pelota.global_position.z <= PredictionModule.Z_GOAL:
		_datos["cruce"] = Vector2(_pelota.global_position.x, _pelota.global_position.y)
		_datos["t_cruce"] = _t
	if _t > 0.5:
		_anotar("k", _kicker, _c_k, delta)
		_anotar("a", _arquero, _c_a, delta)
	if _t < DURACION:
		return
	var k: Dictionary = _datos["k"]
	var a: Dictionary = _datos["a"]
	print("tiro %d %s %s | dedo-pelota %.2f m | %s | cruza en %s tras %.2f s | marcador %d-%d" % [_i, OBJETIVOS[_i % OBJETIVOS.size()], _datos.get("remate", ""), _datos["dedo"], ResultModule.Resultado.keys()[_arquero._resultado], _datos["cruce"], _datos["t_cruce"] - _datos["t_golpe"], _juego.kicker_score, _juego.goalkeeper_score])
	print("   pateador malla %+.3f (%s)  salto visible %.2f m (%s)  sin animar %d cuadros" % [k["min_y"], k["min_info"], k["salto"], k["salto_info"], k["parado_max"]])
	print("   arquero  malla %+.3f (%s)  salto visible %.2f m (%s)  sin animar %d cuadros" % [a["min_y"], a["min_info"], a["salto"], a["salto_info"], a["parado_max"]])
	_i += 1
	if _i >= _total:
		if _csv:
			_csv.close()
		get_tree().quit()
		return
	_nuevo()
