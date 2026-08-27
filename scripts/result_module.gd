class_name ResultModule
extends RefCounted

static func evaluar_resultado(anim: DiveAnimData) -> bool:
	if not anim.has_meta("alcanzable"):
		return false
		
	if not anim.get_meta("alcanzable"):
		return false

	var offset: Vector2 = anim.get_meta("offset_actual")
	var margen_extra := randf() * 0.15
	return offset.length() <= (anim.max_offset_permitido - margen_extra)
