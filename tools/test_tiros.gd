extends Node

# Prueba de integracion: patea a las 9 zonas y anota que animacion elige el
# arquero, como termina la jugada (ATAJA / REBOTE / GOL), que tan cerca pasa la
# pelota de sus manos y donde termina. Usa el flujo normal del juego, sin error
# de percepcion (el arquero siempre elige la zona correcta).
#
# VEL=18 tiro suave, VEL=32 tiro fuerte (el limite para agarrarla depende de
# la dificultad: GoalkeeperStats.velocidad_max_atajar).
# FORZAR=fallo fuerza GOL: el arquero se tira (DIVE) pero la pelota pasa lejos.
# PATEADOR=1 patea con el pateador (carrera y patada, como en el juego): el
# arquero arranca al soltar el tiro. POT=potencia 0-100 (velocidad 15 + POT/4).
# POSTE=1 patea pegado a los palos (arriba, media y abajo) en vez de a las 9 zonas.
# FULL=1 apunta afuera de los palos (como tirar "full" a un costado con el
# pateador; con PATEADOR=1 el tiro cruzado igual entra pegado al palo).
# "palo": cuanto le sobra al cuerpo del arquero hasta el palo (negativo = lo atraviesa).

const TIROS_FULL := [
	["full der baja", Vector2(4.2, 0.4)],
	["full der media", Vector2(4.2, 1.2)],
	["full der alta", Vector2(4.2, 2.0)],
	["full izq media", Vector2(-4.2, 1.2)],
	["casi palo media", Vector2(3.7, 1.2)],
]
const TIROS_POSTE := [
	["palo arriba izq", Vector2(-3.3, 2.1)],
	["palo media izq", Vector2(-3.3, 1.25)],
	["palo abajo izq", Vector2(-3.3, 0.4)],
	["palo arriba der", Vector2(3.3, 2.1)],
	["palo media der", Vector2(3.3, 1.25)],
	["palo abajo der", Vector2(3.3, 0.4)],
]
const TIROS_ZONAS := [
	["arriba izquierda", Vector2(-2.6, 2.05)],
	["arriba centro", Vector2(0.2, 2.15)],
	["arriba derecha", Vector2(2.6, 2.05)],
	["media izquierda", Vector2(-2.5, 1.25)],
	["media centro", Vector2(-0.1, 1.2)],
	["media derecha", Vector2(2.5, 1.25)],
	["abajo izquierda", Vector2(-2.4, 0.35)],
	["abajo centro", Vector2(0.15, 0.35)],
	["abajo derecha", Vector2(2.4, 0.35)],
]
var TIROS: Array = TIROS_POSTE if OS.get_environment("POSTE") != "" else (TIROS_FULL if OS.get_environment("FULL") != "" else TIROS_ZONAS)
var VEL_Z := -float(OS.get_environment("VEL")) if OS.get_environment("VEL") != "" else -25.0

var idx := int(OS.get_environment("TIRO")) if OS.get_environment("TIRO") != "" else 0
var traza := OS.get_environment("TIRO") != ""
var juego: Node
var t := 0.0
var pateado := false
var anim_vista := ""
var dist_min := INF
var salvada := false
var palo_min := INF


func _ready() -> void:
	_nuevo()


func _nuevo() -> void:
	if juego:
		juego.queue_free()
	juego = load("res://scenes/game.tscn").instantiate()
	add_child(juego)
	t = 0.0
	pateado = false
	anim_vista = ""
	dist_min = INF
	salvada = false
	palo_min = INF


## Velocidad inicial para que la pelota cruce z=-12 en el punto pedido.
func _velocidad(desde: Vector3, objetivo: Vector2) -> Vector3:
	var tv := (-12.0 - desde.z) / VEL_Z
	return Vector3((objetivo.x - desde.x) / tv, (objetivo.y - desde.y + 0.5 * 9.8 * tv * tv) / tv, VEL_Z)


func _physics_process(delta: float) -> void:
	t += delta
	var gk = juego.get_node("Goalkeeper")
	var pelota: RigidBody3D = juego.get_node("Ball")
	if not pateado and t > 0.5:
		gk.dificultad = 0.0
		if OS.get_environment("FORZAR") == "fallo":
			gk.forzar_resultado = ResultModule.Resultado.GOL
		gk.keeper_save.connect(func(_b): salvada = true)
		if OS.get_environment("PATEADOR") != "":
			var k = juego.get_node("Kicker")
			k.power = float(OS.get_environment("POT")) if OS.get_environment("POT") != "" else 80.0
			k.aim_target_3d = Vector3(TIROS[idx][1].x, TIROS[idx][1].y, 0.0)
			k._release_kick()
		else:
			pelota.kick(_velocidad(pelota.global_position, TIROS[idx][1]))
		pateado = true
	if not pateado:
		return
	var ap: AnimationPlayer = juego.get_node("Goalkeeper/player/AnimationPlayer")
	if String(ap.current_animation).begins_with("cascadeur/"):
		anim_vista = ap.current_animation
	# distancia de la pelota a la mano mas cercana, solo cerca del arquero
	if pelota.global_position.z < -7.0 and not salvada:
		var esq: Skeleton3D = juego.get_node("Goalkeeper/player/Node/Skeleton3D")
		for h in ["mixamorig1RightHandMiddle1", "mixamorig1LeftHandMiddle1"]:
			var p := esq.global_transform * esq.get_bone_global_pose(esq.find_bone(h)).origin
			dist_min = minf(dist_min, p.distance_to(pelota.global_position))
	# cuanto le sobra al cuerpo del arquero hasta los palos (negativo: lo atraviesa)
	var esq_p: Skeleton3D = juego.get_node("Goalkeeper/player/Node/Skeleton3D")
	for h in gk.HUESOS_CUERPO:
		var q := esq_p.global_transform * esq_p.get_bone_global_pose(esq_p.find_bone(h)).origin
		if q.y > 2.6:
			continue
		for palo in gk.palos:
			palo_min = minf(palo_min, Vector2(q.x, q.z).distance_to(palo) - gk.radio_palo - gk.HUESOS_CUERPO[h])
	if traza and Engine.get_physics_frames() % 3 == 0:
		var esq2: Skeleton3D = juego.get_node("Goalkeeper/player/Node/Skeleton3D")
		var m := esq2.global_transform * esq2.get_bone_global_pose(esq2.find_bone("mixamorig1RightHand")).origin
		print("  t=%.2f pelota %s vel %s mano_der %s salvada %s" % [t, pelota.global_position.snapped(Vector3.ONE * 0.01), pelota.linear_velocity.snapped(Vector3.ONE * 0.1), m.snapped(Vector3.ONE * 0.01), salvada])
	if t > (3.6 if OS.get_environment("PATEADOR") != "" else 2.6):
		var p := pelota.global_position
		var donde := "en las manos" if pelota.freeze else ("adentro del arco" if p.z < -11.0 and absf(p.x) < 3.66 and p.y < 2.44 else "afuera / despejada")
		print("%-17s %-34s %-7s mano-pelota %.2f m  palo %+.2f m  pelota (%5.1f, %4.1f, %6.1f) %s" % [
			TIROS[idx][0], anim_vista, ResultModule.Resultado.keys()[gk._resultado], dist_min, palo_min,
			p.x, p.y, p.z, donde])
		idx += 1
		if idx >= TIROS.size() or traza:
			get_tree().quit()
			return
		_nuevo()
