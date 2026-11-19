@tool
class_name HinchadaNpc
extends Resource

## Un tipo de espectador ya horneado (lo genera tools/hinchada_hornear.gd).
## Cada NPC trae sus dos mallas (cerca y media), su textura de
## animaciones (VAT) y su textura de color.

@export var nombre: String = ""
## Que tan seguido aparece en la tribuna respecto a los demas NPC.
## El horneado conserva este valor si ya lo habias cambiado.
@export var peso: float = 1.0
@export var malla_cerca: Mesh
@export var malla_media: Mesh
## Posiciones de cada vertice en cada cuadro de cada animacion.
@export var vat: Texture2D
## Hacia donde mira la superficie en cada cuadro (para la luz).
@export var vat_normales: Texture2D
@export var albedo: Texture2D
## Brillo promedio de la textura en remera (x), pantalon (y) y pelo (w).
## El shader lo usa para poder teñir esas partes de cualquier color.
@export var lum_media: Vector4 = Vector4(0.3, 0.3, 0.3, 0.3)
