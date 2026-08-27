class_name TimingModule
extends RefCounted

static func calcular_delay_inicio(anim: DiveAnimData, tiempo_vuelo: float, delay_extra_error: float) -> float:
	var duracion_hasta_contacto := anim.contact_time
	var delay := tiempo_vuelo - duracion_hasta_contacto + delay_extra_error
	return max(0.0, delay)
