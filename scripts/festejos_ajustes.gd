class_name FestejosAjustes
extends RefCounted

## Ajustes a mano de los festejos y las escenas de PES, encima de lo que trae la extraccion.
##
## Al pasar las escenas de PES al juego algunos lugares quedan corridos (el retarget cambia
## las medidas del cuerpo y no todos los .fdc traen la formacion exacta): en un festejo en
## grupo uno abraza al aire o se mete adentro de otro. Esto se corrige con el editor
## (tools/editor_festejos.tscn), que guarda en AJUSTES:
##
##   { "<corte>": {
##       "desactivado": false,   # el festejo no sale en el juego (grupales y de uno solo)
##       "activado": false,      # un festejo grupal que la build descarto sale igual
##       "desde": 0.0,           # segundos que se adelanta toda la escena
##       "actores": { "<clip>#<n>": {"x": 0.0, "z": 0.0, "giro": 0.0, "desfase": 0.0, "oculto": false} }
##   } }
##
## x y z son metros en el espacio de la escena tal como la pone el juego (el arco hacia -z),
## giro en grados (positivo = a la izquierda, visto de arriba) y desfase en segundos: positivo
## adelanta el clip de ese actor, negativo lo hace esperar quieto en el primer cuadro. <n> es
## cuantos actores con ese mismo clip hay antes en el corte (en las filas se repiten clips).
## Los festejos de un solo jugador usan como corte el nombre de su clip.
##
## PesAnimaciones aplica todo al cargar escenas.json y datos.json: los actores llevan su
## ajuste en "ajuste" y colocar_actor() lo usa. Los ocultos se sacan de las listas.

const AJUSTES := "res://resources/festejos_ajustes.json"
## Paso de los caminos de los festejos grupales (GRUPAL_PASO en tools/pes_construir.gd).
const PASO_CAMINOS := 0.25

static var _cache: Dictionary = {}
static var _cargado := false

static func todos() -> Dictionary:
	if not _cargado:
		_cargado = true
		_cache = {}
		if FileAccess.file_exists(AJUSTES):
			var leido = JSON.parse_string(FileAccess.get_file_as_string(AJUSTES))
			if leido is Dictionary:
				_cache = leido
	return _cache

static func guardar(ajustes: Dictionary) -> Error:
	_limpiar(ajustes)
	var f := FileAccess.open(AJUSTES, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(ajustes, "\t", true))
	f.close()
	_cache = ajustes
	_cargado = true
	return OK

## Saca lo que quedo en cero, para que el archivo muestre solo lo que se toco.
static func _limpiar(ajustes: Dictionary) -> void:
	for corte: String in ajustes.keys():
		var e: Dictionary = ajustes[corte]
		var actores: Dictionary = e.get("actores", {})
		for clave: String in actores.keys():
			if es_neutro(actores[clave]):
				actores.erase(clave)
		if actores.is_empty():
			e.erase("actores")
		if not e.get("desactivado", false):
			e.erase("desactivado")
		if not e.get("activado", false):
			e.erase("activado")
		if absf(float(e.get("desde", 0.0))) < 0.001:
			e.erase("desde")
		if e.is_empty():
			ajustes.erase(corte)

static func es_neutro(a: Dictionary) -> bool:
	return absf(float(a.get("x", 0.0))) < 0.001 and absf(float(a.get("z", 0.0))) < 0.001 \
		and absf(float(a.get("giro", 0.0))) < 0.01 and absf(float(a.get("desfase", 0.0))) < 0.001 \
		and not a.get("oculto", false)

static func desactivado(corte: String) -> bool:
	return (todos().get(corte, {}) as Dictionary).get("desactivado", false)

static func activado(corte: String) -> bool:
	return (todos().get(corte, {}) as Dictionary).get("activado", false)

static func desde(corte: String) -> float:
	return float((todos().get(corte, {}) as Dictionary).get("desde", 0.0))

## Las claves de los actores de un corte, en el orden de la lista.
static func claves(actores: Array) -> Array:
	var vistos := {}
	var salida := []
	for a: Dictionary in actores:
		var clip := str(a["clip"])
		var n: int = vistos.get(clip, 0)
		vistos[clip] = n + 1
		salida.append("%s#%d" % [clip, n])
	return salida

## El ajuste de un actor, sumandole lo que se adelanta toda la escena.
static func de_actor(corte: String, clave: String) -> Dictionary:
	var e: Dictionary = todos().get(corte, {})
	var a: Dictionary = (e.get("actores", {}) as Dictionary).get(clave, {}).duplicate()
	a["desfase"] = float(a.get("desfase", 0.0)) + float(e.get("desde", 0.0))
	return a

## Escenas de escenas.json: a cada actor le pone su clave y su ajuste, y saca los ocultos.
static func aplicar_a_escenas(escenas: Dictionary) -> void:
	for corte: String in escenas:
		var actores: Array = escenas[corte]
		_marcar(corte, actores)
		escenas[corte] = actores.filter(func(a: Dictionary): return not (a["ajuste"] as Dictionary).get("oculto", false))

static func _marcar(corte: String, actores: Array) -> void:
	var lista := claves(actores)
	for i in actores.size():
		var a: Dictionary = actores[i]
		a["clave"] = lista[i]
		a["ajuste"] = de_actor(corte, lista[i])

## Festejos grupales de datos.json: saca los desactivados y los actores ocultos (el autor,
## el primero, no se puede ocultar) y corre los caminos de la cadera con el ajuste, que es
## lo que usa el juego para llevar al grupo al corner.
static func aplicar_a_grupales(grupales: Array) -> Array:
	var salida := []
	for g: Dictionary in grupales:
		var corte := str(g["corte"])
		if desactivado(corte):
			continue
		var actores: Array = g["actores"]
		var caminos: Array = g["caminos"]
		_marcar(corte, actores)
		var nuevos_actores := []
		var nuevos_caminos := []
		for i in actores.size():
			var a: Dictionary = actores[i]
			var aj: Dictionary = a["ajuste"]
			if i > 0 and aj.get("oculto", false):
				continue
			nuevos_actores.append(a)
			nuevos_caminos.append(_correr_camino(caminos[i], a, aj))
		g["actores"] = nuevos_actores
		g["caminos"] = nuevos_caminos
		g["largo"] = maxf(float(g["largo"]) - desde(corte), 1.0)
		salida.append(g)
	return salida

## Los caminos se midieron con el actor puesto en su lugar de PES (escala 1): se giran
## alrededor de ese lugar, se corren y se desplazan en el tiempo segun el desfase.
static func _correr_camino(camino: Array, actor: Dictionary, aj: Dictionary) -> Array:
	var p: Array = actor["pos"]
	var lugar := PesAnimaciones.lugar_pes(float(p[0]), 0.0, float(p[2]), PesAnimaciones.ESCALA_CON_CARRERA)
	var giro := Basis(Vector3.UP, deg_to_rad(float(aj.get("giro", 0.0))))
	var mover := Vector3(float(aj.get("x", 0.0)), 0.0, float(aj.get("z", 0.0)))
	var salto := roundi(float(aj.get("desfase", 0.0)) / PASO_CAMINOS)
	var salida := []
	for k in camino.size():
		var q: Array = camino[clampi(k + salto, 0, camino.size() - 1)]
		var v := lugar + mover + giro * (Vector3(float(q[0]), 0.0, float(q[1])) - lugar)
		salida.append([snappedf(v.x, 0.01), snappedf(v.z, 0.01)])
	return salida
