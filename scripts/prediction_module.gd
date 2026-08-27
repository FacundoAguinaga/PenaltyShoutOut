class_name PredictionModule
extends RefCounted

const GRAVITY := 9.8
const GOAL_WIDTH := 7.32
const GOAL_HEIGHT := 2.44
const Z_GOAL := -12.0

static func calcular_target_real(pos_inicial: Vector3, vel_inicial: Vector3) -> Dictionary:
	# Tiempo hasta que la pelota cruce el plano del arco
	var t := 0.0
	if abs(vel_inicial.z) > 0.001:
		t = (Z_GOAL - pos_inicial.z) / vel_inicial.z
		
	var x := pos_inicial.x + vel_inicial.x * t
	var y := pos_inicial.y + vel_inicial.y * t - 0.5 * GRAVITY * t * t
	
	var target := Vector2(x, y)
	var entra_en_el_arco := esta_dentro_del_marco(target)
	
	return {
		"target": target,
		"tiempo_vuelo": t,
		"es_gol_potencial": entra_en_el_arco
	}

static func esta_dentro_del_marco(target: Vector2) -> bool:
	var half_width = GOAL_WIDTH / 2.0
	if target.x < -half_width or target.x > half_width:
		return false
	if target.y < 0.0 or target.y > GOAL_HEIGHT:
		return false
	return true
