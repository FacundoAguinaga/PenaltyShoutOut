class_name DiveAnimData
extends Resource

enum Zone {
	TOP_LEFT, TOP_CENTER, TOP_RIGHT,
	MID_LEFT, MID_CENTER, MID_RIGHT,
	BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT
}

## SAVE: el arquero agarra la pelota. DIVE: se tira; segun la jugada la pelota
## le rebota en las manos (tiro fuerte) o entra (se tiro a otra zona).
## Los valores (0 y 1) son los mismos que tenian ATAJADA y FALLO.
enum Tipo { SAVE, DIVE }

@export var anim_name: String
@export var zone: Zone
@export var tipo: Tipo = Tipo.SAVE
## Segundo de la animacion en que la mano llega a la pelota.
@export var contact_time: float
@export var hand_bone: String = "mixamorig1RightHand"
## Segundo en que el arquero despega (la cadera arranca rapido): lo de antes
## es preparacion. Lo mide el bakeo. El arquero trata de despegar recien
## cuando le patean.
@export var despegue: float = 0.0
## Donde esta la mano en el contact_time, relativo al arquero. Lo calcula el
## bakeo (tools/bakear.tscn), no se escribe a mano.
@export var canonical_target: Vector3
## Como sigue la animacion segun termine la jugada ("ataja", "rebote", "gol"):
## {anim, t_salto, t_inicio}. Solo lo tienen las de PES.
var empalmes: Dictionary = {}

# El AnimSelector estará dentro de una clase estática interna o en el mismo archivo para simplificar
class AnimSelector:
	const PESO_LATERAL := 0.85
	const MARGEN_VARIEDAD := 0.06
	const PENALIDAD_PASARSE := 2.0

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

	## solo_zona en false busca en todo el arco: cuando el arquero acerto, importa
	## la que toca mas cerca de la pelota aunque quede justo del otro lado del
	## limite entre dos zonas.
	## Elige la animacion de un tipo para una zona: entre las de esa zona, la
	## que toca mas cerca del punto (x, y) por donde pasa la pelota. Si la
	## zona no tiene ninguna de ese tipo, la mas cercana de cualquier zona
	## (y lo avisa, porque el arquero va a tener que correrse mucho).
	static func elegir(libreria: Array[DiveAnimData], zona: Zone, tipo: DiveAnimData.Tipo, punto: Vector2, solo_zona: bool = true) -> DiveAnimData:
		if solo_zona:
			var mejor_zona := _mas_cercana(libreria.filter(func(a): return a != null and a.zone == zona and a.tipo == tipo), punto)
			if mejor_zona:
				return mejor_zona
		var mejor: DiveAnimData
		mejor = _mas_cercana(libreria.filter(func(a): return a != null and a.tipo == tipo), punto)
		if mejor:
			print("[AnimSelector] Zona %s sin %s: uso %s (la mas cercana)" % [Zone.keys()[zona], Tipo.keys()[tipo], mejor.anim_name])
		return mejor

	## Importa mas acertar la altura: lo que falte de costado se corrige moviendo
	## al arquero, pero la altura no se corrige. Entre las que quedan casi igual
	## de bien se elige al azar, para que dos tiros parecidos no se vean iguales.
	static func _mas_cercana(candidatas: Array, punto: Vector2) -> DiveAnimData:
		var mejor_d := INF
		var puntajes := []
		for a in candidatas:
			var dx: float = (punto.x - a.canonical_target.x) * PESO_LATERAL
			# Un clip que se pasa de largo obliga a correr al arquero para atras
			# mientras se tira, y se ve como que amaga para el otro lado.
			if absf(a.canonical_target.x) > absf(punto.x) and signf(a.canonical_target.x) == signf(punto.x):
				dx *= PENALIDAD_PASARSE
			var dy: float = punto.y - a.canonical_target.y
			var d := sqrt(dx * dx + dy * dy)
			puntajes.append(d)
			mejor_d = minf(mejor_d, d)
		var parecidas: Array = []
		for i in candidatas.size():
			if puntajes[i] <= mejor_d + MARGEN_VARIEDAD:
				parecidas.append(candidatas[i])
		return parecidas.pick_random() if not parecidas.is_empty() else null
