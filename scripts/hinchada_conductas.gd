@tool
class_name HinchadaConductas
extends RefCounted

## Como actua cada tipo de espectador en cada momento del partido.
##
## Cada espectador tiene una PERSONALIDAD fija. Segun lo que pasa en la cancha
## queda en un ESTADO, y para ese estado tiene 4 opciones de animacion: cada
## pocos segundos elige una al azar (por eso no se mueven todos igual). Hay una
## lista para cuando esta PARADO y otra para cuando esta SENTADO; si la lista
## de sentado trae una animacion de pie, el espectador se levanta.
##
## Para cambiar como actua alguien alcanza con editar la tabla de abajo.
## Animaciones disponibles: las de ANIMS en tools/hinchada_hornear.gd.
## Agregar "+salta" a una animacion la combina con saltitos en el lugar.

enum Personalidad { TRANQUILO, HINCHA, FANATICO, CHARLATAN, SUFRIDOR, APLAUDIDOR, AMARGO, EUFORICO }

enum Estado {
	NORMAL,         ## Mirando el partido.
	TENSION,        ## Antes de que pateen el penal.
	FESTEJO,        ## Gol de su equipo.
	FESTEJO_LEVE,   ## Fallo el rival / atajo su arquero.
	LAMENTO,        ## Gol del rival o fallo propio.
	NEUTRAL,        ## Paso algo y es publico neutral: aplaude.
}

const N_PERSONALIDADES := 8
const N_ESTADOS := 6
const SALTA := 64

## [personalidad][estado] = [[4 opciones parado], [4 opciones sentado]]
const TABLA := {
	Personalidad.TRANQUILO: {
		Estado.NORMAL: [["idle", "idle", "idle", "aplauso"], ["sentado", "sentado", "sentado", "charla_izq"]],
		Estado.TENSION: [["idle", "idle", "idle", "idle"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.FESTEJO: [["aplauso", "festejo", "aplauso", "victoria"], ["sentado_festejo", "sentado_aplauso", "sentado_festejo", "aplauso"]],
		Estado.FESTEJO_LEVE: [["aplauso", "aplauso", "idle", "aplauso"], ["sentado_aplauso", "sentado_aplauso", "sentado", "sentado_aplauso"]],
		Estado.LAMENTO: [["triste", "triste", "idle", "enojo"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.NEUTRAL: [["aplauso", "idle", "aplauso", "idle"], ["sentado_aplauso", "sentado", "sentado_aplauso", "sentado"]],
	},
	Personalidad.HINCHA: {
		Estado.NORMAL: [["idle", "aplauso", "idle", "idle"], ["sentado", "sentado", "sentado_aplauso", "charla_der"]],
		Estado.TENSION: [["idle", "idle", "idle", "triste"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.FESTEJO: [["festejo+salta", "victoria", "festejo", "victoria+salta"], ["festejo", "victoria", "sentado_festejo", "festejo+salta"]],
		Estado.FESTEJO_LEVE: [["aplauso", "festejo", "aplauso", "victoria"], ["sentado_aplauso", "sentado_festejo", "sentado_aplauso", "aplauso"]],
		Estado.LAMENTO: [["enojo", "triste", "enojo", "triste"], ["sentado", "enojo", "sentado", "sentado"]],
		Estado.NEUTRAL: [["aplauso", "aplauso", "idle", "aplauso"], ["sentado_aplauso", "sentado_aplauso", "sentado", "sentado"]],
	},
	Personalidad.FANATICO: {
		Estado.NORMAL: [["aplauso+salta", "idle+salta", "aplauso+salta", "festejo"], ["aplauso+salta", "aplauso", "idle+salta", "aplauso+salta"]],
		Estado.TENSION: [["idle", "aplauso", "idle", "idle+salta"], ["idle", "aplauso", "idle", "idle"]],
		Estado.FESTEJO: [["festejo+salta", "victoria+salta", "festejo+salta", "victoria+salta"], ["festejo+salta", "victoria+salta", "festejo+salta", "victoria+salta"]],
		Estado.FESTEJO_LEVE: [["festejo+salta", "aplauso+salta", "victoria", "festejo"], ["festejo+salta", "aplauso+salta", "victoria", "festejo"]],
		Estado.LAMENTO: [["enojo", "enojo", "triste", "enojo"], ["enojo", "enojo", "triste", "enojo"]],
		Estado.NEUTRAL: [["aplauso", "aplauso+salta", "aplauso", "idle"], ["aplauso", "aplauso+salta", "aplauso", "idle"]],
	},
	Personalidad.CHARLATAN: {
		Estado.NORMAL: [["idle", "idle", "aplauso", "idle"], ["charla_izq", "charla_der", "charla_izq", "sentado"]],
		Estado.TENSION: [["idle", "idle", "idle", "idle"], ["charla_izq", "sentado", "sentado", "charla_der"]],
		Estado.FESTEJO: [["festejo", "victoria", "aplauso", "festejo+salta"], ["sentado_festejo", "festejo", "sentado_aplauso", "victoria"]],
		Estado.FESTEJO_LEVE: [["aplauso", "idle", "aplauso", "festejo"], ["sentado_aplauso", "charla_der", "sentado_aplauso", "charla_izq"]],
		Estado.LAMENTO: [["triste", "enojo", "idle", "triste"], ["charla_izq", "sentado", "charla_der", "sentado"]],
		Estado.NEUTRAL: [["aplauso", "idle", "idle", "aplauso"], ["sentado_aplauso", "charla_izq", "charla_der", "sentado"]],
	},
	Personalidad.SUFRIDOR: {
		Estado.NORMAL: [["idle", "triste", "idle", "idle"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.TENSION: [["triste", "triste", "idle", "triste"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.FESTEJO: [["victoria+salta", "festejo+salta", "victoria", "victoria+salta"], ["victoria", "festejo+salta", "victoria+salta", "sentado_festejo"]],
		Estado.FESTEJO_LEVE: [["victoria", "aplauso", "festejo", "aplauso"], ["sentado_festejo", "sentado_aplauso", "sentado_festejo", "sentado_aplauso"]],
		Estado.LAMENTO: [["enojo", "enojo", "enojo", "triste"], ["enojo", "sentado", "enojo", "triste"]],
		Estado.NEUTRAL: [["aplauso", "idle", "aplauso", "idle"], ["sentado_aplauso", "sentado", "sentado", "sentado"]],
	},
	Personalidad.APLAUDIDOR: {
		Estado.NORMAL: [["aplauso", "aplauso", "idle", "aplauso"], ["sentado_aplauso", "sentado_aplauso", "sentado", "sentado_aplauso"]],
		Estado.TENSION: [["aplauso", "idle", "aplauso", "idle"], ["sentado_aplauso", "sentado", "sentado", "sentado_aplauso"]],
		Estado.FESTEJO: [["aplauso", "festejo", "aplauso+salta", "victoria"], ["sentado_festejo", "aplauso", "sentado_aplauso", "festejo"]],
		Estado.FESTEJO_LEVE: [["aplauso", "aplauso", "aplauso", "festejo"], ["sentado_aplauso", "sentado_aplauso", "sentado_aplauso", "sentado_festejo"]],
		Estado.LAMENTO: [["idle", "triste", "aplauso", "idle"], ["sentado", "sentado", "sentado_aplauso", "sentado"]],
		Estado.NEUTRAL: [["aplauso", "aplauso", "aplauso", "idle"], ["sentado_aplauso", "sentado_aplauso", "sentado_aplauso", "sentado"]],
	},
	Personalidad.AMARGO: {
		Estado.NORMAL: [["idle", "triste", "idle", "idle"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.TENSION: [["idle", "idle", "triste", "idle"], ["sentado", "sentado", "sentado", "sentado"]],
		Estado.FESTEJO: [["aplauso", "idle", "aplauso", "idle"], ["sentado_aplauso", "sentado", "sentado", "sentado_aplauso"]],
		Estado.FESTEJO_LEVE: [["idle", "aplauso", "idle", "idle"], ["sentado", "sentado_aplauso", "sentado", "sentado"]],
		Estado.LAMENTO: [["enojo", "enojo", "enojo", "enojo"], ["enojo", "sentado", "enojo", "sentado"]],
		Estado.NEUTRAL: [["idle", "idle", "aplauso", "idle"], ["sentado", "sentado", "sentado", "sentado"]],
	},
	Personalidad.EUFORICO: {
		Estado.NORMAL: [["aplauso", "festejo", "idle+salta", "aplauso+salta"], ["sentado_aplauso", "sentado_festejo", "sentado", "aplauso+salta"]],
		Estado.TENSION: [["aplauso", "idle+salta", "aplauso", "festejo"], ["sentado_aplauso", "sentado", "sentado_aplauso", "sentado_festejo"]],
		Estado.FESTEJO: [["victoria+salta", "festejo+salta", "victoria+salta", "festejo+salta"], ["victoria+salta", "festejo+salta", "victoria+salta", "festejo+salta"]],
		Estado.FESTEJO_LEVE: [["festejo+salta", "victoria", "festejo", "aplauso+salta"], ["festejo", "sentado_festejo", "victoria", "aplauso+salta"]],
		Estado.LAMENTO: [["enojo", "triste", "enojo", "enojo"], ["enojo", "triste", "enojo", "sentado"]],
		Estado.NEUTRAL: [["aplauso+salta", "aplauso", "festejo", "aplauso"], ["sentado_aplauso", "aplauso", "sentado_festejo", "sentado_aplauso"]],
	},
}

## Mezcla de personalidades segun el estilo de la tribuna.
## Orden: TRANQUILO, HINCHA, FANATICO, CHARLATAN, SUFRIDOR, APLAUDIDOR, AMARGO, EUFORICO
const MEZCLA_PLATEA := [30.0, 22.0, 1.0, 16.0, 8.0, 12.0, 8.0, 3.0]
const MEZCLA_GENERAL := [14.0, 34.0, 8.0, 9.0, 10.0, 11.0, 5.0, 9.0]
const MEZCLA_POPULAR := [2.0, 22.0, 48.0, 2.0, 6.0, 6.0, 2.0, 12.0]

## Arma el arreglo que lee el shader: una entrada por
## (personalidad, estado, postura, opcion).
static func armar_tabla(banco: HinchadaBanco) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(N_PERSONALIDADES * N_ESTADOS * 2 * 4)
	for p in N_PERSONALIDADES:
		for e in N_ESTADOS:
			var fila: Array = TABLA[p][e]
			for postura in 2:
				for op in 4:
					var txt: String = fila[postura][op]
					var salta := txt.ends_with("+salta")
					var id := banco.id_anim(txt.trim_suffix("+salta"))
					out[((p * N_ESTADOS + e) * 2 + postura) * 4 + op] = id + (SALTA if salta else 0)
	return out
