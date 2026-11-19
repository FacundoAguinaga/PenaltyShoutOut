@tool
class_name HinchadaBanco
extends Resource

## Todo lo horneado de la hinchada: la lista de animaciones (compartida por
## todos los NPC), los NPC y el atlas de impostores (las "fotos" que se usan
## para los espectadores lejanos). Lo genera tools/hinchada_hornear.gd.

@export var fps: float = 15.0
@export var anim_nombres: PackedStringArray
## Fila del VAT donde arranca cada animacion y cuantos cuadros dura.
@export var anim_inicio: PackedInt32Array
@export var anim_cuadros: PackedInt32Array
@export var npcs: Array[HinchadaNpc] = []

@export_group("Impostores")
@export var imp_albedo: Texture2D
@export var imp_mascara: Texture2D
@export var imp_coords: Texture2D
## Cuantas fotos se guardaron de cada animacion.
@export var imp_cuadros: int = 12
## Cuantos NPC hay por fila en la textura.
@export var imp_npc_por_fila: int = 4
## Tamaño en metros de cada foto (ancho, alto).
@export var imp_celda: Vector2 = Vector2(1.40625, 2.38)

func id_anim(nombre: String) -> int:
	var i := anim_nombres.find(nombre)
	if i < 0:
		push_warning("HinchadaBanco: no existe la animacion '%s'" % nombre)
		return 0
	return i
