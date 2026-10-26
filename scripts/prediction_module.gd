class_name PredictionModule
extends RefCounted

const GRAVITY := 9.8
const GOAL_WIDTH := 7.32
const GOAL_HEIGHT := 2.44
## Linea de gol: donde estan los palos. Antes era -12 (un metro detras) y un
## tiro cruzado que entraba pegado al palo se seguia abriendo despues de la
## linea: en -12 ya daba "afuera" y el arquero ni se movia.
const Z_GOAL := -11.0
## Una pelota que pasa rozando el palo por adentro tambien puede entrar, y una
## que va al palo puede rebotar para adentro: el arquero se tira a las dos.
const RADIO_PELOTA := 0.11
const RADIO_PALO := 0.125

static func calcular_target_real(pos_inicial: Vector3, vel_inicial: Vector3) -> Dictionary:
	# Tiempo hasta que la pelota cruce el plano del arco
	var t := 0.0
	if abs(vel_inicial.z) > 0.001:
		t = (Z_GOAL - pos_inicial.z) / vel_inicial.z
		
	var x := pos_inicial.x + vel_inicial.x * t
	var y := pos_inicial.y + vel_inicial.y * t - 0.5 * GRAVITY * t * t
	
	# Si da negativo, la pelota pica antes del arco y llega a ras del piso.
	var target := Vector2(x, maxf(y, 0.11))
	var entra_en_el_arco := esta_dentro_del_marco(target)
	
	return {
		"target": target,
		"tiempo_vuelo": t,
		"es_gol_potencial": entra_en_el_arco
	}

## Donde pasa la pelota (x, y) cuando llega a la profundidad z, y en cuanto
## tiempo. Sirve para el plano de las manos del arquero, que esta adelante del
## arco.
static func punto_en_z(pos_inicial: Vector3, vel_inicial: Vector3, z: float) -> Dictionary:
	var t := 0.0
	if abs(vel_inicial.z) > 0.001:
		t = (z - pos_inicial.z) / vel_inicial.z
	var x := pos_inicial.x + vel_inicial.x * t
	var y := pos_inicial.y + vel_inicial.y * t - 0.5 * GRAVITY * t * t
	return {"punto": Vector2(x, y), "tiempo": t}

static func esta_dentro_del_marco(target: Vector2) -> bool:
	var half_width = GOAL_WIDTH / 2.0 + RADIO_PELOTA + RADIO_PALO
	if target.x < -half_width or target.x > half_width:
		return false
	if target.y < 0.0 or target.y > GOAL_HEIGHT + RADIO_PELOTA:
		return false
	return true
