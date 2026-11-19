@tool
class_name HinchadaEquipacion
extends Resource

## Una camiseta de hincha. Cada equipo puede tener varias (titular, suplente,
## retro...) y cada hincha con camiseta elige una al azar segun su peso.

enum Patron {
	LISO,              ## Todo del color primario.
	RAYAS_VERTICALES,  ## Bastones primario / secundario.
	AROS,              ## Franjas horizontales primario / secundario.
	BANDA,             ## Banda cruzada del secundario.
	MITADES,           ## Mitad primario, mitad secundario.
	FRANJA_PECHO,      ## Una franja horizontal del secundario en el pecho.
	MANGAS,            ## Cuerpo primario, mangas del secundario.
}

@export var nombre: String = "Titular"
@export var color_primario: Color = Color(0.85, 0.15, 0.15)
@export var color_secundario: Color = Color.WHITE
@export var patron: Patron = Patron.LISO
@export var color_pantalon: Color = Color(0.1, 0.1, 0.12)
## Que tan comun es entre los hinchas del equipo.
@export var peso: float = 1.0

static func crear(p_nombre: String, primario: Color, secundario: Color, p_patron: Patron,
		pantalon: Color, p_peso: float) -> HinchadaEquipacion:
	var e := HinchadaEquipacion.new()
	e.nombre = p_nombre
	e.color_primario = primario
	e.color_secundario = secundario
	e.patron = p_patron
	e.color_pantalon = pantalon
	e.peso = p_peso
	return e
