class_name TimingModule
extends RefCounted

## Cuanto se puede acelerar una animacion para llegar a tiempo.
const VELOCIDAD_MAXIMA := 1.8

## Arma el plan para que la mano llegue justo cuando llega la pelota.
## tiempo_hasta_manos: segundos desde el disparo hasta que la pelota cruza el
## plano de las manos. delay_reaccion: lo minimo que tarda en reaccionar.
## Si la animacion entra en el tiempo disponible, se espera y se reproduce
## normal. Si no (un penal real llega en medio segundo), se saltea el
## principio de la animacion (el paso de preparacion) y se la acelera.
## Devuelve { delay, inicio, velocidad }: cuanto esperar, desde que segundo de
## la animacion arrancar y a que velocidad reproducirla hasta el contacto.
static func planificar(anim: DiveAnimData, tiempo_hasta_manos: float, delay_reaccion: float) -> Dictionary:
	var disponible := tiempo_hasta_manos - delay_reaccion
	if disponible >= anim.contact_time:
		return {"delay": tiempo_hasta_manos - anim.contact_time, "inicio": 0.0, "velocidad": 1.0}
	disponible = maxf(disponible, 0.05)
	var inicio := maxf(0.0, anim.contact_time - disponible * VELOCIDAD_MAXIMA)
	return {"delay": delay_reaccion, "inicio": inicio, "velocidad": (anim.contact_time - inicio) / disponible}
