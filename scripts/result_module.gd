class_name ResultModule
extends RefCounted

## Como termina la jugada.
##   GOL:    el arquero se tiro a otra zona (animacion DIVE de la zona que eligio).
##   ATAJA:  acerto la zona y el tiro no es muy fuerte: la agarra (SAVE).
##   REBOTE: acerto la zona pero el tiro es fuerte: la tapa y rebota (DIVE).
enum Resultado { GOL, ATAJA, REBOTE }

## Se resuelve ANTES de arrancar la animacion, no despues del contacto. Si no,
## la animacion podria mentir: el azar daria vuelta el desenlace cuando el
## arquero ya esta reproduciendo una atajada.
##
## zona_elegida: la que eligio el arquero (con su error de percepcion).
## zona_real: por donde va la pelota de verdad.
## velocidad_max_atajar: hasta que velocidad (m/s) la puede agarrar; sale de
## GoalkeeperStats segun la dificultad.
static func decidir(zona_elegida: DiveAnimData.Zone, zona_real: DiveAnimData.Zone, velocidad: float, velocidad_max_atajar: float) -> Resultado:
	if zona_elegida != zona_real:
		return Resultado.GOL
	if velocidad <= velocidad_max_atajar:
		return Resultado.ATAJA
	return Resultado.REBOTE
