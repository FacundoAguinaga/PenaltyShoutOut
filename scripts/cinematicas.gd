extends Node

## Lo que se ve entre un tiro y el siguiente: la pelota entra, se corta a un plano
## cerca y festeja o se lamenta quien corresponda. Como la camara corta, en el festejo
## el pateador se puede recolocar sin ningun fundido: los goles se festejan en el corner.
## Al terminar el partido el ganador levanta la copa con su equipo.
##
## Las cinematicas se saltan con ESPACIO. Todo se acomoda otra vez en limpiar(), que se
## llama con la pantalla en negro.

const Copa := preload("res://scripts/copa.gd")
const Repeticion := preload("res://scripts/repeticion.gd")
## Lo que se sigue grabando despues de que entra la pelota, para la repeticion.
const GRABAR_TRAS_GOL := 0.9
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
## La ronda: todos se separan a los 9 s del clip, asi que se la ve antes.
const DESDE_RONDA := 3.8
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
## Cuantos goles se festejan con un festejo grupal de PES (datos.json, festejos_grupales):
## el autor y sus companeros, cada uno con su clip, coordinados entre si. En los demas el
## autor festeja solo, como en una tanda de verdad (el equipo queda en la mitad de la
## cancha). Antes llegaban tres companeros con clips sueltos puestos a mano, que no estaban
## coordinados con el del autor.
const PROB_GRUPAL := 0.75
## Hasta cuanto afuera de las lineas puede pasar alguien del grupo.
const MARGEN_LINEAS := 1.5
## La variante del kit de cada companero. Todos del mismo alto: con otra escala tambien
## corren otra distancia y no llegan a abrazarse.
const COMPANEROS := ["moreno", "rubio", "canela", "", "moreno", "rubio", "canela"]
## La ceremonia de PES (end_trophy_01): el capitan con la copa adelante y el equipo en
## un podio de dos escalones (los actores estan a 0,3 y 0,6 m). El capitan la sostiene de
## las asas y la levanta mas alto hacia los 8,5 s del clip.
const ESCENA_COPA := "end_trophy_01_pl"
const ESCENA_CAPITAN := "end_trophy_01_cupeur"
const LUGAR_COPA := Vector3(0.0, 0.0, 6.0)
const DESDE_COPA := 3.2
const SALTO_COPA := 5.3
const LARGO_COPA := 13.5
const ESCALA_COPA := 1.7
## Los escalones del podio en coordenadas de PES: x desde, x hasta, z desde, z hasta, alto.
const ESCALONES := [[-3.2, 2.4, 17.45, 19.9, 0.3], [-3.0, 1.6, 16.3, 17.45, 0.6]]
## Los oficiales del penal, donde los pone PES (pk_03_afterKick_GK00): el arbitro junto al
## area y el asistente en la linea de fondo. Con escala 1: son lugares de la cancha.
const ESCENA_OFICIALES := "pk_03_afterKick_GK00"
const CLIP_OFICIAL := "dml_pk_ready03_judge"
const KIT_OFICIAL := "amarillo"
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
var _oficiales: Array[Dictionary] = []
var _podio: Node3D
var _repeticion: Node
var _letrero_repeticion: Label
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
	_repeticion = Repeticion.new(_kicker, _arquero, _juego.ball)
	add_child(_repeticion)
	if _kicker._pes:
		_crear_oficiales()

## El arbitro y el asistente, siempre en la cancha (menos en las escenas del final).
func _crear_oficiales() -> void:
	if not _kicker.animation_player.has_animation("pes/" + CLIP_OFICIAL):
		return
	var escena: Array = PesAnimaciones.escenas().get(ESCENA_OFICIALES, [])
	for a: Dictionary in escena:
		if a["clip"] != CLIP_OFICIAL or absf(float(a["pos"][0])) < 30.0:
			continue
		var c := _crear_companero("", KIT_OFICIAL)
		var ap: AnimationPlayer = c["ap"]
		c["actor"] = a
		_oficiales.append(c)
		ap.animation_finished.connect(func(_n: StringName): ap.play("pes/" + CLIP_OFICIAL, 0.3))
	_mostrar_oficiales(true)

func _mostrar_oficiales(si: bool) -> void:
	for c in _oficiales:
		_mostrar_companero(c, si)
		if si:
			PesAnimaciones.colocar_actor(c["raiz"], c["ap"], c["actor"], MITAD_CANCHA, 1.0)
			(c["ap"] as AnimationPlayer).seek(randf_range(0.0, 10.0), true)

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
	# A la derecha: a la izquierda esta el marcador.
	_letrero_repeticion = EstiloUI.label("REPETICIÓN", 20, EstiloUI.COLOR_ACENTO, EstiloUI.fuente(800, 6))
	_letrero_repeticion.anchor_left = 1.0
	_letrero_repeticion.anchor_right = 1.0
	_letrero_repeticion.anchor_top = ALTO_BARRA + 0.03
	_letrero_repeticion.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_letrero_repeticion.offset_right = -40.0
	_letrero_repeticion.visible = false
	capa.add_child(_letrero_repeticion)

## Una copia del modelo del pateador, sin sus IK ni sus puntos de union.
func _crear_companero(variante: String, equipo: String) -> Dictionary:
	var raiz := Node3D.new()
	raiz.name = "Companero"
	add_child(raiz)
	var modelo: Node3D = _kicker.get_node("player2").duplicate()
	var sk: Skeleton3D = modelo.get_node("Node/Skeleton3D")
	for hijo in sk.get_children():
		if not hijo is MeshInstance3D:
			sk.remove_child(hijo)
			hijo.free()
	(sk.get_child(0) as MeshInstance3D).set_surface_override_material(0, load(_kit(equipo, variante)))
	raiz.add_child(modelo)
	var ap: AnimationPlayer = modelo.get_node("AnimationPlayer")
	PesAnimaciones.cargar_libreria(ap, "pateador.res")
	var piso := PesAnimaciones.cuidar_piso(raiz, sk)
	var c := {"raiz": raiz, "ap": ap, "sk": sk, "piso": piso}
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
	mesh.set_surface_override_material(0, load(_kit(equipo, COMPANEROS[i % COMPANEROS.size()])))
	_mostrar_companero(c, true)
	return c

func _ocultar_extras() -> void:
	for c in _extras:
		_mostrar_companero(c, false)

## Pone a los actores de una escena de PES que pasen el filtro, cada uno con su kit, todos
## en el mismo segundo de sus clips (estan sincronizados). Devuelve los extras usados.
func _poner_escena(corte: String, origen: Vector3, filtro: Callable, equipo_de: Callable, desde := 0.0, escala := PesAnimaciones.ESCALA_ESCENAS) -> Array:
	var lista := []
	for a: Dictionary in PesAnimaciones.escenas()[corte]:
		if not filtro.call(a):
			continue
		var c := _extra(lista.size(), equipo_de.call(a))
		PesAnimaciones.colocar_actor(c["raiz"], c["ap"], a, origen, escala, desde)
		c["actor"] = a
		lista.append(c)
	return lista

func _mostrar_companero(c: Dictionary, si: bool) -> void:
	(c["raiz"] as Node3D).visible = si
	if c.has("brazo"):
		(c["brazo"] as Node).queue_free()
		c.erase("brazo")
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
			_repeticion.cortar_en(GRABAR_TRAS_GOL)
			await _esperar(VER_GOL)
			await _festejar()
			await _repetir()
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
	_mostrar_oficiales(false)
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
	if _juego.sound_manager and _juego.sound_manager.has_method("play_whistle"):
		_juego.sound_manager.play_whistle()

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
	_poner_escena(ESCENA_RONDA, MITAD_CANCHA, func(_a): return true, func(_a): return "rojo", DESDE_RONDA)
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
		var sobran := _puntas_sobrantes(ESCENA_FILAS)
		var filas := _poner_escena(ESCENA_FILAS, MITAD_CANCHA, func(a): return absf(float(a["pos"][0])) < ANCHO_FILAS and not a in sobran,
			func(a): return "rojo" if float(a["pos"][2]) > 0.0 else "azul", ADELANTO_FILAS)
		_soltar_puntas(filas)
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

## En las filas de PES, cada fila tiene en una punta otra vez el clip del medio (`wait`,
## con los dos brazos sobre los hombros), que de un lado abraza al aire: se la saca.
## Medido: sin ellas, ninguna mano levantada queda a mas de 0,4 m de un companero.
func _puntas_sobrantes(corte: String) -> Array:
	var sobran := []
	for lado in [-1.0, 1.0]:
		var fila: Array = PesAnimaciones.escenas()[corte].filter(func(a): return absf(float(a["pos"][0])) < ANCHO_FILAS and signf(float(a["pos"][2])) == lado)
		fila.sort_custom(func(a, b): return float(a["pos"][2]) < float(b["pos"][2]))
		for punta: Dictionary in [fila[0], fila[-1]]:
			if fila.filter(func(a): return a["clip"] == punta["clip"]).size() > 1:
				sobran.append(punta)
	return sobran

## En las puntas de cada fila, el brazo de afuera cuelga (con la pose de pk_idle): el clip
## de PES lo pasaria por el hombro de un companero que no esta.
func _soltar_puntas(filas: Array) -> void:
	for lado in [-1.0, 1.0]:
		var fila := filas.filter(func(c): return signf(float(c["actor"]["pos"][2])) == lado)
		fila.sort_custom(func(a, b): return float(a["actor"]["pos"][2]) < float(b["actor"]["pos"][2]))
		if fila.size() < 2:
			continue
		for k in [0, fila.size() - 1]:
			var c: Dictionary = fila[k]
			var vecino: Dictionary = fila[1 if k == 0 else fila.size() - 2]
			var sk: Skeleton3D = c["sk"]
			var hacia: Vector3 = (vecino["raiz"] as Node3D).global_position
			var izq := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig1LeftArm")).origin
			var der := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig1RightArm")).origin
			var brazo := BrazoSuelto.new()
			brazo.preparar(sk, (c["ap"] as AnimationPlayer).get_animation("pes/" + QUEDARSE_CALMO), "Left" if izq.distance_to(hacia) > der.distance_to(hacia) else "Right")
			sk.add_child(brazo)
			c["brazo"] = brazo

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
		func(a): return _juego.equipo_pateador if str(a["clip"]).contains("_miss_") else _juego.equipo_arquero)
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
	var equipo := _juego.equipo_pateador if del_pateador else _juego.equipo_arquero
	# En el abrazo llegan corriendo desde 20 m: los lugares van sin achicar.
	var escala := PesAnimaciones.ESCALA_CON_CARRERA if corte == ESCENA_ABRAZO else PesAnimaciones.ESCALA_ESCENAS
	var subs := _poner_escena(corte, Vector3.ZERO, func(a): return a != principal, func(_a): return equipo, 0.0, escala)
	PesAnimaciones.colocar_actor(protagonista, ap, principal, Vector3.ZERO, escala)
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
	var desde := DESDE_ABRAZO if corte == ESCENA_ABRAZO else 0.0
	PesAnimaciones.seek_actor(ap, principal, desde)
	for c in subs:
		(c["raiz"] as Node3D).global_position += corrimiento
		PesAnimaciones.seek_actor(c["ap"], c["actor"], desde)
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
	# Al corner del lado por donde entro la pelota. La camara queda en la cancha, con el
	# banderin y la tribuna de atras del arco de fondo.
	var bola := _juego.ball.global_position.x if _juego.ball else 0.0
	_lado = signf(bola) if absf(bola) > 0.3 else (1.0 if randf() < 0.5 else -1.0)
	var corner := Vector3(CORNER.x * _lado, 0.0, CORNER.z)
	var hacia := Vector3(_lado * 0.85, 0.0, -0.53).normalized()
	var grupales: Array = PesAnimaciones.datos().get("festejos_grupales", [])
	if not grupales.is_empty() and randf() < PROB_GRUPAL:
		await _festejo_grupal(grupales.pick_random(), corner, hacia)
		return
	var opciones: Array = FESTEJOS.filter(func(f: Array): return not FestejosAjustes.desactivado(f[0]))
	for n: String in PesAnimaciones.datos()["festejos_gol"]:
		opciones.append([n, QUEDARSE_CALMO, DISTANCIA_BANDERIN])
	if opciones.is_empty():
		opciones = FESTEJOS.duplicate()
	var festejo: Array = opciones.pick_random()
	var entrada: String = festejo[0]
	_loop_festejo = "pes/" + str(festejo[1])
	var ap := _kicker.animation_player
	var sk := _kicker.skeleton
	_kicker.en_cinematica = true
	var fin_carrera: Vector3 = corner - hacia * float(festejo[2])
	var llegada := PesAnimaciones.colocar(_kicker, ap, sk, "pes/" + entrada, fin_carrera, hacia, true)
	ap.animation_finished.connect(_al_terminar_entrada, CONNECT_ONE_SHOT)

	var costado_camara := Vector3(-_lado * 2.4, 0.15, 6.2)
	_mirar_festejo = Vector3(-_lado * 0.35, 0.0, 1.0).normalized()

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

	# Plano del autor girando despacio, siempre del lado de la cancha.
	_camara.fov = 30.0
	var centro := llegada + Vector3(0.0, 0.8, 0.0)
	var angulo_inicial := atan2(-_lado * 0.75, 1.0)
	var sentido := _lado
	_plano = func(_delta: float, t: float) -> void:
		var angulo := angulo_inicial + sentido * 0.14 * t
		_camara.global_position = centro + Vector3(sin(angulo), 0.0, cos(angulo)) * 9.0 + Vector3(0.0, 0.5, 0.0)
		_camara.look_at(centro)
	# Los festejos largos siguen viendose en este plano hasta terminar.
	var hasta := clampf(duracion_entrada, DURACION_MINIMA_FESTEJO, MAXIMO_FESTEJO)
	await _esperar(maxf(hasta - plano_carrera, MINIMO_PLANO_GRUPO))

## Un festejo grupal de PES: el pateador hace el clip del autor y cada companero el suyo,
## todos desde el mismo segundo. El grupo entero se gira y se mueve junto, sin separarlo,
## para que el autor termine cerca del banderin y los demas queden del lado de la cancha.
func _festejo_grupal(festejo: Dictionary, corner: Vector3, hacia: Vector3) -> void:
	var actores: Array = festejo["actores"]
	var caminos: Array = festejo["caminos"]
	var x := _lugar_del_grupo(caminos, corner, hacia)
	var ap := _kicker.animation_player
	var sk := _kicker.skeleton
	_kicker.en_cinematica = true
	PesAnimaciones.colocar_actor(_kicker, ap, actores[0], Vector3.ZERO, PesAnimaciones.ESCALA_CON_CARRERA)
	_kicker.global_transform = x * _kicker.global_transform
	var centro_grupo := Vector3.ZERO
	var esqueletos: Array[Skeleton3D] = [sk]
	for i in actores.size():
		if i > 0:
			var c := _extra(i - 1, _juego.equipo_pateador)
			esqueletos.append(c["sk"])
			PesAnimaciones.colocar_actor(c["raiz"], c["ap"], actores[i], Vector3.ZERO, PesAnimaciones.ESCALA_CON_CARRERA)
			(c["raiz"] as Node3D).global_transform = x * (c["raiz"] as Node3D).global_transform
		var fin: Array = caminos[i][-1]
		centro_grupo += x * Vector3(float(fin[0]), 0.0, float(fin[1]))
	centro_grupo /= actores.size()
	var abierto := 0.0
	for camino: Array in caminos:
		var fin := x * Vector3(float(camino[-1][0]), 0.0, float(camino[-1][1]))
		abierto = maxf(abierto, fin.distance_to(centro_grupo))

	var costado_camara := Vector3(-_lado * 2.4, 0.15, 6.2)
	_encuadre(true)
	_camara.fov = FOV_CERCA
	_camara.global_position = _cadera(sk) + costado_camara
	_camara.look_at(_cadera(sk))
	_plano = func(delta: float, _t: float) -> void:
		_camara.global_position = _camara.global_position.lerp(_cadera(sk) + costado_camara, 1.0 - exp(-4.0 * delta))
		_camara.look_at(_cadera(sk))
	var largo: float = festejo["largo"]
	var plano_carrera := minf(largo * 0.5, MAXIMO_PLANO_CARRERA)
	await _esperar(plano_carrera)
	if _saltar:
		return

	# El grupo girando despacio, desde la cancha y mas lejos si estan abiertos. Mira al
	# centro del grupo mientras se mueve (en los largos llegan de lejos) y termina en el
	# lugar donde se juntan.
	_camara.fov = 30.0
	var radio := 9.0 + abierto * 1.5
	var angulo_inicial := atan2(-_lado * 0.75, 1.0)
	var sentido := _lado
	var centro := [_centro_de(esqueletos)]
	_plano = func(delta: float, t: float) -> void:
		centro[0] = (centro[0] as Vector3).lerp(_centro_de(esqueletos), 1.0 - exp(-2.0 * delta))
		var mira: Vector3 = centro[0] + Vector3(0.0, 0.8, 0.0)
		var angulo := angulo_inicial + sentido * 0.14 * t
		_camara.global_position = mira + Vector3(sin(angulo), 0.0, cos(angulo)) * radio + Vector3(0.0, 0.5, 0.0)
		_camara.look_at(mira)
	var hasta := clampf(largo, DURACION_MINIMA_FESTEJO, MAXIMO_FESTEJO)
	await _esperar(maxf(hasta - plano_carrera, MINIMO_PLANO_GRUPO))

func _centro_de(esqueletos: Array[Skeleton3D]) -> Vector3:
	var suma := Vector3.ZERO
	for e in esqueletos:
		suma += _cadera(e)
	suma /= esqueletos.size()
	suma.y = 0.0
	return suma

## Donde poner el grupo (la escena medida en el origen): el autor termina a
## DISTANCIA_BANDERIN del banderin y los companeros, del lado de la cancha. Si terminan
## todos encima del autor, se lo gira para que llegue corriendo desde la cancha. Despues
## se prueban giros cercanos hasta que nadie se vaya de las lineas.
func _lugar_del_grupo(caminos: Array, corner: Vector3, hacia: Vector3) -> Transform3D:
	var autor: Array = caminos[0]
	var fin := Vector3(float(autor[-1][0]), 0.0, float(autor[-1][1]))
	var inicio := Vector3(float(autor[0][0]), 0.0, float(autor[0][1]))
	var resto := Vector3.ZERO
	for i in range(1, caminos.size()):
		resto += Vector3(float(caminos[i][-1][0]), 0.0, float(caminos[i][-1][1]))
	resto /= caminos.size() - 1
	var juntos := resto.distance_to(fin) < 1.0
	var propio := (inicio - fin) if juntos else (resto - fin)
	var deseado := -hacia if juntos else Vector3(-_lado * 0.6, 0.0, 1.0)
	var giro := propio.signed_angle_to(deseado, Vector3.UP) if propio.length() > 0.2 else 0.0
	var destino := corner - hacia * DISTANCIA_BANDERIN
	var mejor := Transform3D.IDENTITY
	var menor := INF
	for grados in [0.0, 15.0, -15.0, 30.0, -30.0, 45.0, -45.0, 60.0, -60.0, 90.0, -90.0]:
		var b := Basis(Vector3.UP, giro + deg_to_rad(grados))
		var t := Transform3D(b, destino - b * fin)
		var afuera := absf(grados) * 0.002
		for camino: Array in caminos:
			for p: Array in camino:
				var q := t * Vector3(float(p[0]), 0.0, float(p[1]))
				afuera += maxf(0.0, absf(q.x) - CORNER.x - MARGEN_LINEAS) + maxf(0.0, CORNER.z - MARGEN_LINEAS - q.z)
		if afuera < menor:
			menor = afuera
			mejor = t
	return mejor

func _al_terminar_entrada(_nombre: StringName) -> void:
	PesAnimaciones.empalmar(_kicker, _kicker.animation_player, _kicker.skeleton, _loop_festejo, 0.0, 0.4, _mirar_festejo)

## Pone a los dos equipos para la ceremonia de PES, con la pantalla en negro: el podio,
## el equipo en sus lugares y el capitan adelante con la copa. Todo se gira para que el
## capitan mire a +z, desde donde lo toman las camaras de _ceremonia().
func _armar_ceremonia(gano_pateador: bool) -> void:
	limpiar()
	_activa = true
	_mostrar_oficiales(false)
	if _juego.ball:
		_juego.ball.visible = false
	var capitan: Node3D = _kicker if gano_pateador else _arquero
	var perdedor: Node3D = _arquero if gano_pateador else _kicker
	perdedor.visible = false
	perdedor.set_process(false)
	capitan.visible = true
	var ap: AnimationPlayer = capitan.animation_player
	var sk: Skeleton3D = capitan.skeleton
	if gano_pateador:
		_kicker.en_cinematica = true
	else:
		_arquero.preparar_ceremonia()
	var escenas := PesAnimaciones.escenas()
	var actor_capitan: Dictionary = escenas[ESCENA_CAPITAN][0]
	# El (0, 0, 0) de la escena queda de modo que el capitan caiga en LUGAR_COPA.
	var p: Array = actor_capitan["pos"]
	var origen := LUGAR_COPA - PesAnimaciones.lugar_pes(float(p[0]), 0.0, float(p[2]))
	PesAnimaciones.colocar_actor(capitan, ap, actor_capitan, origen)
	if capitan == _arquero:
		capitan.global_basis = Basis(Vector3.UP, PI) * capitan.global_basis
	var equipo := "rojo" if gano_pateador else "azul"
	var subs := _poner_escena(ESCENA_COPA, origen, func(a): return str(a["clip"]).begins_with("dml_end_trophy01"), func(_a): return equipo)
	_podio = _armar_podio(origen)
	add_child(_podio)

	# Todos al mismo momento del clip y girados alrededor del capitan para que mire a +z.
	PesAnimaciones.seek_actor(ap, actor_capitan, DESDE_COPA)
	for c in subs:
		PesAnimaciones.seek_actor(c["ap"], c["actor"], DESDE_COPA)
	sk.force_update_all_bone_transforms()
	var frente := PesAnimaciones._frente(sk, ap.get_animation(ap.current_animation), DESDE_COPA)
	var giro := Basis(Vector3.UP, -atan2(frente.x, frente.z))
	var nodos: Array = [capitan, _podio]
	for c in subs:
		nodos.append(c["raiz"])
	for nodo: Node3D in nodos:
		nodo.global_transform = Transform3D(giro * nodo.global_basis, LUGAR_COPA + giro * (nodo.global_position - LUGAR_COPA))

	_copa = Copa.new()
	_copa.escala = ESCALA_COPA
	add_child(_copa)
	_copa.process_priority = 100
	_copa.seguir(sk)
	_armar_confeti()

## Dos cajas por escalon: la tela del podio y un borde dorado arriba.
func _armar_podio(origen: Vector3) -> Node3D:
	var podio := Node3D.new()
	podio.name = "Podio"
	var tela := StandardMaterial3D.new()
	tela.albedo_color = Color(0.06, 0.08, 0.14)
	tela.roughness = 0.85
	var borde := StandardMaterial3D.new()
	borde.albedo_color = Color(0.85, 0.66, 0.3)
	borde.metallic = 0.6
	borde.roughness = 0.35
	var esc := PesAnimaciones.ESCALA_ESCENAS
	for e: Array in ESCALONES:
		var alto: float = e[4]
		var centro := origen + PesAnimaciones.lugar_pes((float(e[0]) + float(e[1])) * 0.5, alto * 0.5, (float(e[2]) + float(e[3])) * 0.5)
		var tam := Vector3((float(e[3]) - float(e[2])) * esc, alto, (float(e[1]) - float(e[0])) * esc)
		for capa: Array in [[tam, tela, 0.0], [Vector3(tam.x + 0.04, 0.03, tam.z + 0.04), borde, alto * 0.5 - 0.015]]:
			var caja := MeshInstance3D.new()
			var m := BoxMesh.new()
			m.size = capa[0]
			caja.mesh = m
			caja.material_override = capa[1]
			podio.add_child(caja)
			caja.position = centro + Vector3(0.0, capa[2], 0.0)
	return podio

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

## La repeticion del gol en camara lenta: primero de costado, desde atras de la pelota,
## y despues desde el arco, siguiendo la pelota hasta la red.
func _repetir() -> void:
	var largo: float = _repeticion.duracion()
	if _saltar or largo <= 0.0:
		return
	_ocultar_extras()
	_mostrar_oficiales(false)
	_repeticion.empezar()
	_letrero_repeticion.visible = true
	_encuadre(true)
	var pelota: Node3D = _juego.ball
	var patada: float = _repeticion.t_patada()
	_plano = func(_delta: float, t: float) -> void:
		var grabado: float = _repeticion.tiempo_grabado(t)
		_repeticion.mostrar(grabado)
		if grabado < patada + 0.15:
			# De costado y bajo, con el pateador llegando a la pelota.
			_camara.fov = 30.0
			_camara.global_position = Vector3(-4.2, 0.7, 2.2)
			_camara.look_at(pelota.global_position.lerp(_cadera(_kicker.skeleton), 0.4) + Vector3(0.0, 0.2, 0.0))
		else:
			# Desde el costado del arco, siguiendo la pelota.
			_camara.fov = 34.0
			_camara.global_position = Vector3(5.5, 1.0, -7.0)
			_camara.look_at(pelota.global_position)
	await _esperar(largo)
	_plano = Callable()
	_letrero_repeticion.visible = false
	_repeticion.terminar()

## Vuelve todo a como lo necesita el proximo tiro. Con la pantalla en negro.
func limpiar() -> void:
	if not _usada:
		return
	_activa = false
	_festejando = false
	_plano = Callable()
	_encuadre(false)
	_mostrar_oficiales(true)
	if _repeticion:
		_repeticion.volver_a_grabar()
	var ap := _kicker.animation_player
	if ap.animation_finished.is_connected(_al_terminar_entrada):
		ap.animation_finished.disconnect(_al_terminar_entrada)
	_ocultar_extras()
	_camara.fov = CinematicIntro.GAMEPLAY_FOV
	_camara.global_position = CinematicIntro.GAMEPLAY_POS
	_camara.look_at(CinematicIntro.GAMEPLAY_LOOK)
