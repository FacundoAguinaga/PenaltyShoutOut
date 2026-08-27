class_name ErrorModule
extends RefCounted

static func generar_error_espacial(dificultad: float, radio_maximo: float) -> Vector2:
	var angulo := randf() * TAU
	# Usamos dos randf() para aproximar a una distribución normal centrada
	var magnitud := ((randf() + randf()) / 2.0) * radio_maximo * dificultad
	return Vector2(cos(angulo), sin(angulo)) * magnitud

static func generar_error_timing(dificultad: float) -> float:
	# Hasta 0.3 segundos de retraso adicional, escalado por dificultad
	return randf() * 0.3 * dificultad

static func aplicar_error(target_real: Vector2, dificultad: float) -> Dictionary:
	var error_pos := generar_error_espacial(dificultad, 2.0)
	var error_tiempo := generar_error_timing(dificultad)
	return {
		"target_percibido": target_real + error_pos,
		"delay_extra": error_tiempo
	}
