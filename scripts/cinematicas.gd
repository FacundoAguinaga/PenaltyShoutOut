extends Node

## Lo que se ve entre un tiro y el siguiente: la pelota entra, se corta a un plano
## cerca y festeja o se lamenta quien corresponda. Como la camara corta, en el festejo
## el pateador se puede recolocar sin ningun fundido: los goles se festejan en el corner.
## Al terminar el partido el ganador levanta la copa con su equipo.
##
## Las cinematicas se saltan con ESPACIO. Todo se acomoda otra vez en limpiar(), que se
## llama con la pantalla en negro.

const Copa := preload("res://scripts/copa.gd")
const ESPERA_SIN_PES := {"goal": 4.0, "save": 3.5, "miss": 3.5}
## Entrada corriendo, con que clip se queda festejando y a cuantos metros del banderin
## termina (los que patean el banderin llegan hasta el). Se suman los festejos completos
## de datos.json (dml_goal_celebrate_*), que traen la carrera y el gesto en un solo clip.
const FESTEJOS := [
	["dm_goal_Knee_slide01", "dm_goal_Knee_slide01_loop", 3.0],
	["dm_goal_Sliding01", "dm_goal_Sliding01_loop", 3.0],
	["dm_goal_Wide_sliding01", "dm_goal_Wide_sliding01_loop", 3.0],
	["dm_goal_Head_sliding01", "dm_goal_Head_sliding01_loop", 3.0],
	["dm_goal_archer", "dm_goal_archer_loop", 3.0],
	["dm_goal_recorder", "dm_goal_recorder_loop", 3.0],
	["dm_goal_ivoryCoastDance", "dm_goal_ivoryCoastDance_loop", 3.0],
	["dm_pfm_cornerF_kick", "dml_pk_goal_guts", 1.0],
	["dm_pfm_cornerF_lariat", "dml_pk_goal_drumming", 1.0],
	["dm_pfm_cornerF_kick", "dml_pk_goal_pointing", 1.0],
]
const DISTANCIA_BANDERIN := 3.0
## Un festejo completo se queda parado despues del gesto.
const QUEDARSE_CALMO := "pk_idle"
## Hasta cuando seguir al pateador de cerca, y cuanto se ve el grupo como minimo.
const MAXIMO_PLANO_CARRERA := 4.5
const MINIMO_PLANO_GRUPO := 2.5
const MAXIMO_FESTEJO := 8.0
## Lamentos del que erro: caminan volviendo hacia la camara.
const LAMENTOS_PATEADOR := ["dml_pk_miss_shoot_cool", "dml_pk_miss_shoot_excite_Lkick", "dml_pk_miss_shoot_facehand", "dml_pk_miss_shoot_hiphand", "dml_pk_miss_shoot_normal"]
## Las escenas de PES (animaciones_pes/escenas.json, de tools/pes_extraer_escenas.py)
## traen donde va cada jugador y hacia donde mira.
const ESCENA_RONDA := "pk_00_intro_circle00"
const ESCENA_FILAS := "pk_00_intro_teamMate00_5"
const ESCENA_REACCION_FALLO := "pk_03_afterKick_teamMate_H_fault_5_00"
## Al final, antes de la copa: el equipo que gano corre a abrazarse y el que perdio se
## queda abatido.
const ESCENA_ABRAZO := "end_pk_win_02"
const ESCENA_ABATIDOS := "end_pk_lose_02"
## En la escena de las filas tambien estan el primer pateador y los arqueros, lejos.
const ANCHO_FILAS := 5.0
## Las filas arrancan mas adelante, con todos ya enganchados de los hombros.
const ADELANTO_FILAS := 8.0
const DURACION_RONDA := 4.5
const DURACION_PLANO_EQUIPO := 2.4
const LUGAR_ABRAZO := Vector3(0.0, 0.0, 5.0)
const DESDE_ABRAZO := 9.2
const DURACION_ABRAZO := 4.3
const DURACION_ABATIDOS := 4.0
## La previa de una final se arma en la mitad de la cancha, como las escenas de PES.
const MITAD_CANCHA := Vector3(0.0, 0.0, 42.0)
const CLIP_SALE_PATEADOR := "dml_pk_ready02_firstkicker"
const DESDE_SALE_PATEADOR := 2.0
const DURACION_FILA := 4.0
const DURACION_CARAS := 4.5
const DURACION_SALIDA := 4.5
## La niebla del ambiente lava todo lo que esta hacia la cabecera lejana: en los planos
## que miran para ese lado se baja a esta fraccion.
const NIEBLA_DE_FRENTE := 0.2
## La previa del primer tiro: los ultimos segundos de cada clip.
const CLIP_PREVIA_PATEADOR := "dml_pk_ready03_kicker_in"
const CLIP_PREVIA_ARQUERO := "dml_pk_ready03_keeper_in"
const DESDE_PREVIA_PATEADOR := 8.0
const DESDE_PREVIA_ARQUERO := 6.2
## En kicker_in camina con la pelota hacia el punto y la apoya a los 8,4 s, mirando al
## arco; despues retrocede mirandola. Se lo ubica por ese momento, no por hacia donde
## se mueve.
const APOYA_PELOTA := 8.4
const DETRAS_DE_LA_PELOTA := 0.55
const DURACION_PREVIA := 3.5
## Los banderines del modelo del estadio.
const CORNER := Vector3(34.22, 0.0, -10.94)
## Corren hasta donde esta el pateador y festejan parados.
const LLEGADAS := ["dm_tu_run_3_0_idle_guts_banzai", "dm_tu_run_3_0_idle_guts_high", "dm_tu_run_3_0_idle_gutsR"]
const QUEDARSE := ["dm_tu_idle_0_0_idle_guts_banzai", "dm_tu_idle_0_0_idle_guts_high", "dm_tu_idle_0_0_idle_gutsR"]
## Cada companero: variante del kit, escala y, en el corner, donde termina respecto del
## pateador (x hacia adentro de la cancha, z hacia la cancha desde la linea de fondo).
const COMPANEROS := [
	["moreno", 1.03, Vector3(1.8, 0.0, 1.1)],
	["rubio", 0.97, Vector3(0.3, 0.0, 2.1)],
	["canela", 1.0, Vector3(2.6, 0.0, -0.1)],
	["", 1.02, Vector3.ZERO],
	["moreno", 0.98, Vector3.ZERO],
	["rubio", 1.01, Vector3.ZERO],
	["canela", 0.96, Vector3.ZERO],
]
## Los primeros tres son los que llegan al corner; el resto solo esta en la ceremonia.
const EN_EL_CORNER := 3
## La escena de PES: el capitan sostiene la copa los 13 s; todos estan agachados,
## saltan a los 4 s y a los 5 s ya la tiene sobre la cabeza.
const CLIP_CAPITAN := "dml_end_raise01_trophy08_cup_lg_chl"
const CLIP_SUB := "dml_end_raise01_trophy08_sub%02d"
const LUGAR_COPA := Vector3(0.0, 0.0, 6.0)
const FORMACION := [Vector3(-1.4, 0.0, -0.3), Vector3(1.4, 0.0, -0.3), Vector3(-2.6, 0.0, -0.9), Vector3(2.6, 0.0, -0.9),
	Vector3(-0.8, 0.0, -1.5), Vector3(0.9, 0.0, -1.6), Vector3(-1.9, 0.0, -2.1)]
const SALTO_COPA := 4.0
const LARGO_COPA := 12.8
const VER_GOL := 1.2
const VER_ATAJADA := 1.0
const VER_FALLO := 0.8
const DURACION_MINIMA_FESTEJO := 6.5
const TRAS_LLEGAR := 0.5
const DURACION_PLANO_CERCA := 2.0
const FOV_CERCA := 32.0
const ALTO_BARRA := 0.1
## Desde donde se mira a cada uno. Al pateador, desde su carrera: vuelve caminando hacia
## la camara y atras queda el arco (del otro lado hay niebla y esta a contraluz).
const PLANO_ARQUERO := Vector3(1.5, 0.1, 5.0)
const PLANO_PATEADOR := Vector3(1.6, 0.0, 5.0)

var _juego: GameManager
var _kicker: PlayerKicker
var _arquero: PlayerGoalkeeper
var _camara: Camera3D
var _companeros: Array[Dictionary] = []
## Los que actuan en las escenas de PES: se crean una vez y se reusan cambiando el kit.
var _extras: Array[Dictionary] = []
var _copa: Node3D
var _confeti: GPUParticles3D
var _cartel: Label
var _lado := 1.0
var _mirar_festejo := Vector3.ZERO
var _barras: Array[ColorRect] = []
var _aviso: Label
var _activa := false
var _saltar := false
var _usada := false
var _festejando := false
var _ultimo := ""
var _plano := Callable()
var _plano_anterior := Callable()
var _t_plano := 0.0
var _loop_festejo := ""

func _init(juego: GameManager, kicker: PlayerKicker, arquero: PlayerGoalkeeper, camara: Camera3D) -> void:
	name = "Cinematicas"
	_juego = juego
	_kicker = kicker
	_arquero = arquero
	_camara = camara

func _ready() -> void:
	_armar_barras()
	if _kicker._pes:
		for i in EN_EL_CORNER:
			_companeros.append(_crear_companero(COMPANEROS[i], "rojo"))

func _armar_barras() -> void:
	var capa := CanvasLayer.new()
	capa.layer = 45
	add_child(capa)
	for abajo in [false, true]:
		var barra := ColorRect.new()
		barra.color = Color.BLACK
		barra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		barra.anchor_right = 1.0
		barra.anchor_top = 1.0 - ALTO_BARRA if abajo else 0.0
		barra.anchor_bottom = 1.0 if abajo else ALTO_BARRA
		barra.visible = false
		capa.add_child(barra)
		_barras.append(barra)
	_aviso = Label.new()
	_aviso.text = "ESPACIO  saltar"
	_aviso.add_theme_font_size_override("font_size", 13)
	_aviso.modulate = Color(1.0, 1.0, 1.0, 0.55)
	_aviso.anchor_left = 1.0
	_aviso.anchor_right = 1.0
	_aviso.anchor_top = 1.0
	_aviso.anchor_bottom = 1.0
	_aviso.offset_left = -130.0
	_aviso.offset_top = -30.0
	_aviso.visible = false
	capa.add_child(_aviso)
	_cartel = EstiloUI.label("CAMPEONES", 72, EstiloUI.COLOR_ACENTO, EstiloUI.fuente(800, 8))
	EstiloUI.sombra(_cartel, 0.5, 4)
	_cartel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# Abajo: arriba taparia la copa.
	_cartel.anchor_top = 1.0 - ALTO_BARRA - 0.15
	_cartel.anchor_bottom = 1.0 - ALTO_BARRA - 0.15
	_cartel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cartel.visible = false
	capa.add_child(_cartel)

## Una copia del modelo del pateador, sin sus IK ni sus puntos de union.
func _crear_companero(datos: Array, equipo: String) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = "Companero"
	add_child(raiz)
	var modelo: Node3D = _kicker.get_node("player2").duplicate()
	modelo.scale *= float(datos[1])
	var sk: Skeleton3D = modelo.get_node("Node/Skeleton3D")
	for hijo in sk.get_children():
		if not hijo is MeshInstance3D:
			sk.remove_child(hijo)
			hijo.free()
	(sk.get_child(0) as MeshInstance3D).set_surface_override_material(0, load(_kit(equipo, datos[0])))
	raiz.add_child(modelo)
	var ap: AnimationPlayer = modelo.get_node("AnimationPlayer")
	PesAnimaciones.cargar_libreria(ap, "pateador.res")
	var piso := PesAnimaciones.cuidar_piso(raiz, sk)
	var c := {"raiz": raiz, "ap": ap, "sk": sk, "piso": piso, "fin": datos[2]}
	_mostrar_companero(c, false)
	return c

func _kit(equipo: String, variante: String) -> String:
	return "res://Player/kits/material_%s%s.tres" % [equipo, "_" + variante if variante != "" else ""]

## El extra numero i, con el kit de ese equipo, a la vista.
func _extra(i: int, equipo: String) -> Dictionary:
	while _extras.size() <= i:
		_extras.append(_crear_companero(COMPANEROS[_extras.size() % COMPANEROS.size()], equipo))
	var c: Dictionary = _extras[i]
	var mesh: MeshInstance3D = (c["sk"] as Skeleton3D).get_child(0)
	mesh.set_surface_override_material(0, load(_kit(equipo, COMPANEROS[i % COMPANEROS.size()][0])))
	_mostrar_companero(c, true)
	return c

func _ocultar_extras() -> void:
	for c in _extras:
		_mostrar_companero(c, false)

## Pone a los actores de una escena de PES que pasen el filtro, cada uno con su kit.
## Devuelve los extras usados, con el segundo en que arranca cada clip ("desde").
func _poner_escena(corte: String, origen: Vector3, filtro: Callable, equipo_de: Callable) -> Array:
	var lista := []
	for a: Dictionary in PesAnimaciones.escenas()[corte]:
		if not filtro.call(a):
			continue
		var c := _extra(lista.size(), equipo_de.call(a))
		c["desde"] = PesAnimaciones.colocar_actor(c["raiz"], c["ap"], a, origen)
		lista.append(c)
	return lista

func _mostrar_companero(c: Dictionary, si: bool) -> void:
	(c["raiz"] as Node3D).visible = si
	(c["piso"] as Node).set_process(si)
	if not si:
		(c["ap"] as AnimationPlayer).stop()

func _process(delta: float) -> void:
	if not _activa:
		return
	if Input.is_action_just_pressed("kick_charge"):
		_saltar = true
	if _plano.is_valid():
		# Las lambdas copian las variables locales: lo que avanza cada plano tiene que
		# salir del tiempo que lleva, no de sumar adentro.
		if _plano != _plano_anterior:
			_plano_anterior = _plano
			_t_plano = 0.0
		_t_plano += delta
		_plano.call(delta, _t_plano)

## Espera lo que dure la jugada y su cinematica.
func jugar(tipo: String) -> void:
	_ultimo = tipo
	if not _kicker._pes:
		await get_tree().create_timer(ESPERA_SIN_PES[tipo]).timeout
		return
	_activa = true
	_saltar = false
	_usada = true
	match tipo:
		"goal":
			await _esperar(VER_GOL)
			await _festejar()
		"save":
			await _esperar(VER_ATAJADA)
			await _plano_de(_arquero.skeleton, PLANO_ARQUERO, DURACION_PLANO_CERCA)
			await _lamento_pateador(DURACION_PLANO_CERCA)
			await _reaccion_filas()
		_:
			await _esperar(VER_FALLO)
			await _lamento_pateador(DURACION_PLANO_CERCA + 0.6)
			await _reaccion_filas()
	_activa = false

## Al terminar el partido: el ganador se abraza con su equipo, el perdedor queda abatido
## y el ganador levanta la copa. Si empatan no hay nada. ESPACIO salta de a una escena.
func jugar_fin() -> void:
	if not _kicker._pes or _juego.kicker_score == _juego.goalkeeper_score:
		return
	_activa = true
	var gano_pateador := _juego.kicker_score > _juego.goalkeeper_score
	if _juego.ball:
		_juego.ball.visible = false
	await _escena_de_equipo(gano_pateador, ESCENA_ABRAZO, DURACION_ABRAZO)
	await _escena_de_equipo(not gano_pateador, ESCENA_ABATIDOS, DURACION_ABATIDOS)
	_saltar = false
	await _juego.fundido(1.0)
	_armar_ceremonia(gano_pateador)
	await _juego.fundido(0.0)
	await _ceremonia()
	_activa = false
	_aviso.visible = false
	_cartel.visible = false

## La previa del primer tiro: los equipos abrazados en la mitad de la cancha, el primer
## pateador que sale de la fila, acomoda la pelota y el arquero que camina por la linea.
## Despues todos quedan listos para patear.
func jugar_previa() -> void:
	if not _kicker._pes:
		return
	_activa = true
	_saltar = false
	_usada = true
	await _filas_abrazadas()
	var ap := _kicker.animation_player
	var sk := _kicker.skeleton
	_kicker.en_cinematica = true
	_kicker.current_state = PlayerKicker.KickState.IDLE
	var pelota := _juego.ball.global_position if _juego.ball else Vector3.ZERO
	var detras := Vector3(pelota.x, 0.9, pelota.z + DETRAS_DE_LA_PELOTA)
	PesAnimaciones.colocar_mirando(_kicker, ap, sk, "pes/" + CLIP_PREVIA_PATEADOR, detras, Vector3.FORWARD, APOYA_PELOTA)
	ap.seek(DESDE_PREVIA_PATEADOR, true)
	await _plano_de(sk, PLANO_PATEADOR, DURACION_PREVIA)
	if not _saltar:
		_arquero.preparar_ceremonia()
		# Termina parado en su lugar, mirando a la cancha.
		var gap: AnimationPlayer = _arquero.animation_player
		var clip_arquero := "pes/" + CLIP_PREVIA_ARQUERO
		var fin_arquero := Vector3(0.0, 0.9, _arquero.global_position.z)
		PesAnimaciones.colocar_mirando(_arquero, gap, _arquero.skeleton, clip_arquero, fin_arquero, Vector3.BACK, gap.get_animation(clip_arquero).length)
		gap.seek(DESDE_PREVIA_ARQUERO, true)
		await _plano_de(_arquero.skeleton, PLANO_ARQUERO, DURACION_PREVIA)
	_activa = false
	await _juego.fundido(1.0)
	limpiar()
	_kicker.start_aiming()
	_arquero.reset_to_idle()
	await _juego.fundido(0.0)

## La previa en la mitad de la cancha: un equipo en ronda, los dos en fila abrazados y
## el primer pateador que sale. Todo con las posiciones de las escenas de PES.
func _filas_abrazadas() -> void:
	_kicker.visible = false
	var ambiente: Environment = _camara.get_world_3d().environment
	var niebla := ambiente.volumetric_fog_density if ambiente else 0.0
	if ambiente:
		ambiente.volumetric_fog_density = niebla * NIEBLA_DE_FRENTE
	if _juego.sound_manager and _juego.sound_manager.has_method("play_anticipation"):
		_juego.sound_manager.play_anticipation()
	_encuadre(true)

	# La ronda: once abrazados mirando al centro, y la camara girando alrededor.
	_poner_escena(ESCENA_RONDA, MITAD_CANCHA, func(_a): return true, func(_a): return "rojo")
	_camara.fov = 36.0
	_plano = func(_delta: float, t: float) -> void:
		var angulo := 0.5 + 0.2 * t
		_camara.global_position = MITAD_CANCHA + Vector3(sin(angulo) * 4.3, 2.4 - 0.12 * t, -cos(angulo) * 4.3)
		_camara.look_at(MITAD_CANCHA + Vector3(0.0, 1.0, 0.0))
	await _esperar(DURACION_RONDA)
	_ocultar_extras()

	# Las dos filas, una a cada lado del centro: de frente y en diagonal (atras queda la
	# tribuna del costado) y despues las caras, de cerca, pasando por la fila.
	if not _saltar:
		var filas := _poner_escena(ESCENA_FILAS, MITAD_CANCHA, func(a): return absf(float(a["pos"][0])) < ANCHO_FILAS,
			func(a): return "rojo" if float(a["pos"][2]) > 0.0 else "azul")
		for c in filas:
			(c["ap"] as AnimationPlayer).seek(float(c["desde"]) + ADELANTO_FILAS, true)
		_camara.fov = 32.0
		_plano = func(_delta: float, t: float) -> void:
			_camara.global_position = MITAD_CANCHA + Vector3(-11.0 + 0.4 * t, 1.6, -9.0 + 0.25 * t)
			_camara.look_at(MITAD_CANCHA + Vector3(0.0, 1.0, 0.0))
		await _esperar(DURACION_FILA)
	if not _saltar:
		_plano = func(_delta: float, t: float) -> void:
			var x := -6.8 + 3.0 * t
			_camara.global_position = MITAD_CANCHA + Vector3(x, 1.55, -2.0)
			_camara.look_at(MITAD_CANCHA + Vector3(x + 2.2, 1.45, 0.0))
		await _esperar(DURACION_CARAS)

	if ambiente:
		ambiente.volumetric_fog_density = niebla
	# Desde atras de la fila: el primer pateador sale hacia el arco.
	if not _saltar:
		_kicker.visible = true
		_kicker.en_cinematica = true
		_kicker.current_state = PlayerKicker.KickState.IDLE
		var sale := MITAD_CANCHA + Vector3(0.0, 0.0, -1.2)
		PesAnimaciones.colocar(_kicker, _kicker.animation_player, _kicker.skeleton, "pes/" + CLIP_SALE_PATEADOR, sale, Vector3.FORWARD)
		_kicker.animation_player.seek(DESDE_SALE_PATEADOR, true)
		_camara.fov = 34.0
		_plano = func(_delta: float, t: float) -> void:
			_camara.global_position = MITAD_CANCHA + Vector3(0.5, 1.6, 2.4 - 0.25 * t)
			_camara.look_at(_cadera(_kicker.skeleton).lerp(Vector3(0.0, 1.2, -11.0), 0.35))
		await _esperar(DURACION_SALIDA)

	_ocultar_extras()
	_kicker.visible = true

## Primer plano del pateador lamentandose, volviendo hacia la camara.
func _lamento_pateador(segundos: float) -> void:
	if _saltar:
		return
	_kicker.en_cinematica = true
	var punto := _cadera(_kicker.skeleton)
	punto.y = 0.0
	PesAnimaciones.colocar(_kicker, _kicker.animation_player, _kicker.skeleton, "pes/" + str(LAMENTOS_PATEADOR.pick_random()), punto, Vector3(0.15, 0.0, 1.0).normalized())
	await _plano_de(_kicker.skeleton, PLANO_PATEADOR, segundos)

## Corte a las filas de la mitad de la cancha despues de un tiro errado: los del
## pateador se lamentan y los del arquero festejan.
func _reaccion_filas() -> void:
	if _saltar:
		return
	_poner_escena(ESCENA_REACCION_FALLO, MITAD_CANCHA, func(_a): return true,
		func(a): return "rojo" if str(a["clip"]).contains("_miss_") else "azul")
	var ambiente: Environment = _camara.get_world_3d().environment
	var niebla := ambiente.volumetric_fog_density if ambiente else 0.0
	if ambiente:
		ambiente.volumetric_fog_density = niebla * NIEBLA_DE_FRENTE
	_encuadre(true)
	_camara.fov = 34.0
	_plano = func(_delta: float, t: float) -> void:
		_camara.global_position = MITAD_CANCHA + Vector3(-7.0 + 0.4 * t, 1.5, -8.5)
		_camara.look_at(MITAD_CANCHA + Vector3(0.0, 1.1, 0.0))
	await _esperar(DURACION_PLANO_EQUIPO)
	if ambiente:
		ambiente.volumetric_fog_density = niebla
	_ocultar_extras()

## Arma los companeros de un equipo: los que hagan falta y con su kit.
func _armar_equipo(equipo: String, cuantos: int) -> void:
	for c in _companeros:
		(c["raiz"] as Node).queue_free()
	_companeros.clear()
	for i in cuantos:
		var c := _crear_companero(COMPANEROS[i], equipo)
		_companeros.append(c)
		_mostrar_companero(c, true)

## Una escena de PES de un equipo, con su protagonista (el primer actor). En el abrazo el
## protagonista es el que pateo: PES lo pone donde este, asi que se lo deja terminar donde
## se juntan los demas.
func _escena_de_equipo(del_pateador: bool, corte: String, segundos: float) -> void:
	_saltar = false
	await _juego.fundido(1.0)
	limpiar()
	_activa = true
	var protagonista: Node3D = _kicker if del_pateador else _arquero
	var otro: Node3D = _arquero if del_pateador else _kicker
	protagonista.visible = true
	otro.visible = false
	if del_pateador:
		_kicker.en_cinematica = true
	else:
		_arquero.preparar_ceremonia()
	var ap: AnimationPlayer = protagonista.animation_player
	var sk: Skeleton3D = protagonista.skeleton
	var actores: Array = PesAnimaciones.escenas()[corte]
	var principal: Dictionary = actores[0]
	var equipo := "rojo" if del_pateador else "azul"
	var subs := _poner_escena(corte, Vector3.ZERO, func(a): return a != principal, func(_a): return equipo)
	var desde_principal := PesAnimaciones.colocar_actor(protagonista, ap, principal, Vector3.ZERO)
	# El modelo del arquero esta girado media vuelta respecto de su raiz.
	if protagonista == _arquero:
		protagonista.global_basis = Basis(Vector3.UP, PI) * protagonista.global_basis
	var centro := Vector3.ZERO
	if corte == ESCENA_ABRAZO:
		var fin_subs := Vector3.ZERO
		for c in subs:
			fin_subs += _cadera_al_final(c["ap"], c["sk"])
		fin_subs /= subs.size()
		var mover := fin_subs - _cadera_al_final(ap, sk)
		mover.y = 0.0
		protagonista.global_position += mover
		centro = fin_subs
	else:
		for c in subs:
			centro += (c["raiz"] as Node3D).global_position
		centro = (centro + protagonista.global_position) / (subs.size() + 1)
	var corrimiento := LUGAR_ABRAZO - centro
	corrimiento.y = 0.0
	protagonista.global_position += corrimiento
	ap.seek(DESDE_ABRAZO if corte == ESCENA_ABRAZO else desde_principal, true)
	for c in subs:
		(c["raiz"] as Node3D).global_position += corrimiento
		(c["ap"] as AnimationPlayer).seek(DESDE_ABRAZO if corte == ESCENA_ABRAZO else float(c["desde"]), true)
	await _juego.fundido(0.0)
	_encuadre(true)
	# Alta y lejos: en el abrazo llegan corriendo desde 20 m y pasarian por la camara.
	_camara.fov = 34.0
	var mirar := LUGAR_ABRAZO + Vector3(0.0, 0.9, 0.0)
	_camara.global_position = mirar + Vector3(sin(0.35) * 12.0, 1.6, cos(0.35) * 12.0)
	_camara.look_at(mirar)
	_plano = func(_delta: float, t: float) -> void:
		var angulo := 0.35 - 0.07 * t
		_camara.global_position = mirar + Vector3(sin(angulo) * 12.0, 1.6 - 0.15 * t, cos(angulo) * 12.0)
		_camara.look_at(mirar)
	await _esperar(segundos)

## Donde queda la cadera al terminar el clip que esta puesto.
func _cadera_al_final(ap: AnimationPlayer, sk: Skeleton3D) -> Vector3:
	ap.seek(ap.current_animation_length - 0.05, true)
	sk.force_update_all_bone_transforms()
	return _cadera(sk)

## Espera sin contar el tiempo en pausa. Corta antes si se salta.
func _esperar(segundos: float) -> void:
	var falta := segundos
	while falta > 0.0 and not _saltar:
		await get_tree().process_frame
		if not get_tree().paused:
			falta -= get_process_delta_time()

func _cadera(sk: Skeleton3D) -> Vector3:
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(PesAnimaciones.CADERA)).origin

func _encuadre(on: bool) -> void:
	for b in _barras:
		b.visible = on
	_aviso.visible = on

## Plano cerca de un personaje que lo sigue suave.
func _plano_de(sk: Skeleton3D, desde: Vector3, segundos: float) -> void:
	if _saltar:
		return
	_encuadre(true)
	_camara.fov = FOV_CERCA
	_camara.global_position = _cadera(sk) + desde
	_camara.look_at(_cadera(sk))
	_plano = func(delta: float, _t: float) -> void:
		var hacia := _cadera(sk)
		_camara.global_position = _camara.global_position.lerp(hacia + desde, 1.0 - exp(-4.0 * delta))
		_camara.look_at(hacia)
	await _esperar(segundos)

func _festejar() -> void:
	if _saltar:
		return
	_festejando = true
	var opciones: Array = FESTEJOS.duplicate()
	for n: String in PesAnimaciones.datos()["festejos_gol"]:
		opciones.append([n, QUEDARSE_CALMO, DISTANCIA_BANDERIN])
	var festejo: Array = opciones.pick_random()
	var entrada: String = festejo[0]
	_loop_festejo = "pes/" + str(festejo[1])
	var ap := _kicker.animation_player
	var sk := _kicker.skeleton
	_kicker.en_cinematica = true
	# Al corner del lado por donde entro la pelota. La camara queda en la cancha, con el
	# banderin y la tribuna de atras del arco de fondo.
	var bola := _juego.ball.global_position.x if _juego.ball else 0.0
	_lado = signf(bola) if absf(bola) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
	var corner := Vector3(CORNER.x * _lado, 0.0, CORNER.z)
	var hacia := Vector3(_lado * 0.85, 0.0, -0.53).normalized()
	var fin_carrera: Vector3 = corner - hacia * float(festejo[2])
	var llegada := PesAnimaciones.colocar(_kicker, ap, sk, "pes/" + entrada, fin_carrera, hacia, true)
	ap.animation_finished.connect(_al_terminar_entrada, CONNECT_ONE_SHOT)

	var costado_camara := Vector3(-_lado * 2.4, 0.15, 6.2)
	var llegadas := LLEGADAS.duplicate()
	llegadas.shuffle()
	var quedarse := QUEDARSE.duplicate()
	var centro_grupo := llegada + Vector3(-_lado * 1.2, 0.0, 1.0)
	_mirar_festejo = Vector3(-_lado * 0.35, 0.0, 1.0).normalized()
	for i in EN_EL_CORNER:
		var c: Dictionary = _companeros[i]
		_mostrar_companero(c, true)
		var offset: Vector3 = c["fin"]
		var fin := llegada + Vector3(-_lado * offset.x, 0.0, offset.z)
		var cap: AnimationPlayer = c["ap"]
		# Vienen por la cancha, a lo largo de la linea de fondo.
		PesAnimaciones.colocar(c["raiz"], cap, c["sk"], "pes/" + str(llegadas[i]), fin, Vector3(_lado * 0.97, 0.0, -0.1).normalized(), true)
		cap.animation_finished.connect(func(_n: StringName):
			PesAnimaciones.empalmar(c["raiz"], cap, c["sk"], "pes/" + str(quedarse[i]), 0.0, 0.5, _mirar_festejo), CONNECT_ONE_SHOT)

	_encuadre(true)
	_camara.fov = FOV_CERCA
	_camara.global_position = _cadera(sk) + costado_camara
	_camara.look_at(_cadera(sk))
	# Mira siempre a la cadera: algunos se deslizan a 9 m/s y una mirada suavizada los pierde.
	_plano = func(delta: float, _t: float) -> void:
		_camara.global_position = _camara.global_position.lerp(_cadera(sk) + costado_camara, 1.0 - exp(-4.0 * delta))
		_camara.look_at(_cadera(sk))
	var duracion_entrada: float = ap.get_animation("pes/" + entrada).length
	var plano_carrera := minf(duracion_entrada + TRAS_LLEGAR, MAXIMO_PLANO_CARRERA)
	await _esperar(plano_carrera)
	if _saltar:
		return

	# Plano del grupo girando despacio, siempre del lado de la cancha.
	_camara.fov = 30.0
	var centro := centro_grupo + Vector3(0.0, 0.8, 0.0)
	var angulo_inicial := atan2(-_lado * 0.75, 1.0)
	var sentido := _lado
	_plano = func(_delta: float, t: float) -> void:
		var angulo := angulo_inicial + sentido * 0.14 * t
		_camara.global_position = centro + Vector3(sin(angulo), 0.0, cos(angulo)) * 9.0 + Vector3(0.0, 0.5, 0.0)
		_camara.look_at(centro)
	# Los festejos largos siguen viendose en este plano hasta terminar.
	var hasta := clampf(duracion_entrada, DURACION_MINIMA_FESTEJO, MAXIMO_FESTEJO)
	await _esperar(maxf(hasta - plano_carrera, MINIMO_PLANO_GRUPO))

func _al_terminar_entrada(_nombre: StringName) -> void:
	PesAnimaciones.empalmar(_kicker, _kicker.animation_player, _kicker.skeleton, _loop_festejo, 0.0, 0.4, _mirar_festejo)

## Pone a los dos equipos para la ceremonia, con la pantalla en negro.
func _armar_ceremonia(gano_pateador: bool) -> void:
	limpiar()
	_activa = true
	if _juego.ball:
		_juego.ball.visible = false
	var capitan: Node3D = _kicker if gano_pateador else _arquero
	var perdedor: Node3D = _arquero if gano_pateador else _kicker
	perdedor.visible = false
	perdedor.set_process(false)
	var ap: AnimationPlayer = capitan.animation_player
	var sk: Skeleton3D = capitan.skeleton
	if gano_pateador:
		_kicker.en_cinematica = true
	else:
		_arquero.preparar_ceremonia()
	var frente := Vector3.BACK
	PesAnimaciones.colocar_mirando(capitan, ap, sk, "pes/" + CLIP_CAPITAN, LUGAR_COPA + Vector3(0.0, 0.9, 0.0), frente)
	_copa = Copa.new()
	add_child(_copa)
	_copa.process_priority = 100
	_copa.seguir(sk)

	capitan.visible = true
	_armar_equipo("rojo" if gano_pateador else "azul", COMPANEROS.size())
	for i in COMPANEROS.size():
		var c: Dictionary = _companeros[i]
		PesAnimaciones.colocar_mirando(c["raiz"], c["ap"], c["sk"], "pes/" + CLIP_SUB % (i + 1), LUGAR_COPA + FORMACION[i] + Vector3(0.0, 0.9, 0.0), frente)
	_armar_confeti()

func _armar_confeti() -> void:
	_confeti = GPUParticles3D.new()
	_confeti.amount = 5000
	_confeti.lifetime = 3.5
	_confeti.visibility_aabb = AABB(Vector3(-20.0, -16.0, -20.0), Vector3(40.0, 22.0, 40.0))
	_confeti.emitting = false
	var proceso := ParticleProcessMaterial.new()
	proceso.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proceso.emission_box_extents = Vector3(9.0, 0.5, 7.0)
	proceso.direction = Vector3.DOWN
	proceso.spread = 25.0
	proceso.initial_velocity_min = 2.0
	proceso.initial_velocity_max = 3.5
	proceso.gravity = Vector3(0.0, -2.0, 0.0)
	proceso.angular_velocity_min = -360.0
	proceso.angular_velocity_max = 360.0
	proceso.turbulence_enabled = true
	proceso.turbulence_noise_strength = 1.5
	var colores := Gradient.new()
	colores.offsets = PackedFloat32Array([0.0, 0.34, 0.35, 0.67, 0.68, 1.0])
	colores.colors = PackedColorArray([Color("f2c14e"), Color("f2c14e"), Color.WHITE, Color.WHITE, Color("d62828"), Color("d62828")])
	var rampa := GradientTexture1D.new()
	rampa.gradient = colores
	proceso.color_initial_ramp = rampa
	_confeti.process_material = proceso
	var papel := QuadMesh.new()
	papel.size = Vector2(0.055, 0.085)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	papel.material = material
	_confeti.draw_pass_1 = papel
	add_child(_confeti)
	_confeti.global_position = LUGAR_COPA + Vector3(0.0, 8.0, 0.0)

func _ceremonia() -> void:
	var cap: Skeleton3D = _copa._sk
	_encuadre(true)
	# Agachados, de frente y de lejos, acercandose: se espera el salto.
	_camara.fov = 28.0
	var mirar := LUGAR_COPA + Vector3(0.0, 0.8, -0.8)
	_plano = func(_delta: float, t: float) -> void:
		_camara.global_position = LUGAR_COPA + Vector3(0.4, 0.9, maxf(15.0 - 0.8 * t, 11.5))
		_camara.look_at(mirar)
	_camara.global_position = LUGAR_COPA + Vector3(0.4, 0.9, 15.0)
	_camara.look_at(mirar)
	await _esperar(SALTO_COPA)
	if _saltar:
		_confeti.emitting = true
		return

	# El salto: arranca el confeti, el cartel y el grito de la tribuna.
	_confeti.emitting = true
	_cartel.visible = true
	get_tree().call_group("crowd_clusters", "celebrate_goal", LARGO_COPA - SALTO_COPA + 4.0)
	if _juego.sound_manager and _juego.sound_manager.has_method("play_goal"):
		_juego.sound_manager.play_goal()
	# Abajo y cerca, siguiendo la copa.
	_camara.fov = 34.0
	var bajo := Vector3(1.8, -0.2, 7.0)
	_camara.global_position = _cadera(cap) + bajo
	_plano = func(delta: float, _t: float) -> void:
		# Entre la cara y la copa, para que entren los dos.
		_camara.global_position = _camara.global_position.lerp(_cadera(cap) + bajo, 1.0 - exp(-2.0 * delta))
		_camara.look_at(_copa.global_position.lerp(_cadera(cap), 0.45))
	await _esperar(4.2)
	if _saltar:
		return

	# Se aleja subiendo, con todo el equipo y el estadio.
	_camara.fov = 36.0
	var centro := LUGAR_COPA + Vector3(0.0, 1.1, -0.8)
	_plano = func(_delta: float, t: float) -> void:
		var angulo := 0.45 - 0.12 * t
		var alto := 1.2 + 0.55 * t
		var radio := 7.5 + 0.7 * t
		_camara.global_position = centro + Vector3(sin(angulo) * radio, alto, cos(angulo) * radio)
		_camara.look_at(centro)
	await _esperar(LARGO_COPA - SALTO_COPA - 4.2)

## Vuelve todo a como lo necesita el proximo tiro. Con la pantalla en negro.
func limpiar() -> void:
	if not _usada:
		return
	_activa = false
	_festejando = false
	_plano = Callable()
	_encuadre(false)
	var ap := _kicker.animation_player
	if ap.animation_finished.is_connected(_al_terminar_entrada):
		ap.animation_finished.disconnect(_al_terminar_entrada)
	_ocultar_extras()
	for c in _companeros:
		_mostrar_companero(c, false)
		var cap: AnimationPlayer = c["ap"]
		for con in cap.animation_finished.get_connections():
			cap.animation_finished.disconnect(con["callable"])
	_camara.fov = CinematicIntro.GAMEPLAY_FOV
	_camara.global_position = CinematicIntro.GAMEPLAY_POS
	_camara.look_at(CinematicIntro.GAMEPLAY_LOOK)
