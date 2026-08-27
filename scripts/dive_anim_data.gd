class_name DiveAnimData
extends Resource

enum Zone {
	TOP_LEFT, TOP_CENTER, TOP_RIGHT,
	MID_LEFT, MID_CENTER, MID_RIGHT,
	BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT
}

@export var anim_name: String
@export var zone: Zone
@export var contact_time: float
@export var hand_bone: String = "mixamorig1RightHand"
@export var canonical_target: Vector3
@export var max_offset_permitido: float = 1.0

# El AnimSelector estará dentro de una clase estática interna o en el mismo archivo para simplificar
class AnimSelector:
	static func clasificar_zona(target: Vector2, goal_width: float, goal_height: float) -> Zone:
		var horizontal: int
		var x_tercio := goal_width / 3.0
		if target.x < -x_tercio / 2.0:
			horizontal = 0 # LEFT
		elif target.x > x_tercio / 2.0:
			horizontal = 2 # RIGHT
		else:
			horizontal = 1 # CENTER
			
		var vertical: int
		var y_tercio := goal_height / 3.0
		if target.y < y_tercio:
			vertical = 2 # BOTTOM
		elif target.y > y_tercio * 2.0:
			vertical = 0 # TOP
		else:
			vertical = 1 # MID

		var matrix = [
			[Zone.TOP_LEFT, Zone.TOP_CENTER, Zone.TOP_RIGHT],
			[Zone.MID_LEFT, Zone.MID_CENTER, Zone.MID_RIGHT],
			[Zone.BOTTOM_LEFT, Zone.BOTTOM_CENTER, Zone.BOTTOM_RIGHT],
		]
		return matrix[vertical][horizontal]

	static func elegir_animacion(target_percibido: Vector2, libreria: Array[DiveAnimData], goal_width: float, goal_height: float) -> DiveAnimData:
		var zona := clasificar_zona(target_percibido, goal_width, goal_height)
		var candidatas := libreria.filter(func(a): return a.zone == zona)
		
		# Fallback: si no hay animación exacta para esa zona, devolvemos la primera (deberíamos tener al menos 1 por zona idealmente)
		var elegida: DiveAnimData
		if candidatas.size() > 0:
			elegida = candidatas[0]
		else:
			# Busca la más cercana o simplemente la primera de la librería si no hay
			if libreria.size() > 0:
				elegida = libreria[0]
			else:
				return null
				
		var offset := target_percibido - Vector2(elegida.canonical_target.x, elegida.canonical_target.y)
		elegida.set_meta("offset_actual", offset)
		elegida.set_meta("alcanzable", offset.length() <= elegida.max_offset_permitido)
		
		return elegida
