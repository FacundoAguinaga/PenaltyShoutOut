extends SceneTree

## Tira pelotas contra la red y mide como reacciona:
##   godot --headless --path . -s res://tools/test_red.gd
## RED="holgura,elasticidad,estiramiento_maximo,rebote,agarre" prueba otros valores
## (por defecto, los de game.tscn: holgura 0,15, elasticidad 0,0002, estiramiento 0,12).
## bolsa: cuanto pasa la pelota del fondo de la red en reposo (m).
## sale: velocidad maxima con que vuelve hacia la cancha despues de tocar la red.
## mueve: cuantos nudos se movieron mas de 5 cm (si la red ondula o solo se hunde un punto).
## escapa: la pelota termino del otro lado de la tela.

const TIROS := [
	# nombre, desde, hacia (en la linea), velocidad
	["centro fuerte", Vector3(0, 0.11, 11), Vector3(0.3, 1.2, 0), 32.0],
	["centro suave", Vector3(0, 0.11, 11), Vector3(0.0, 1.0, 0), 16.0],
	["angulo sup der fuerte", Vector3(0, 0.11, 11), Vector3(3.2, 2.2, 0), 33.0],
	["angulo inf izq", Vector3(0, 0.11, 11), Vector3(-3.3, 0.25, 0), 28.0],
	["rasante centro", Vector3(0, 0.11, 11), Vector3(0.5, 0.11, 0), 25.0],
	["cruzado al lateral", Vector3(2.0, 0.11, 11), Vector3(-3.5, 0.8, 0), 30.0],
	["picada", Vector3(0, 0.11, 11), Vector3(0.0, 1.6, 0), -1.0],
	["lateral por afuera", Vector3(9.0, 0.11, 11), Vector3(3.75, 0.9, -1.0), 26.0],
	["esquina fondo 36 m/s", Vector3(-1.0, 0.11, 11), Vector3(3.4, 2.25, 0), 36.0],
	["palo bajo 34 m/s", Vector3(0, 0.11, 11), Vector3(3.45, 0.2, 0), 34.0],
	["cae en el techo", Vector3(0.4, 5.0, -0.8), Vector3(0.3, -2.0, -0.5), 0.0],
	["cae en el lateral", Vector3(4.6, 1.5, -0.7), Vector3(-6.0, 2.0, 0.0), 0.0],
]

var red: Node3D
var pelota: RigidBody3D
var idx := 0
var t := 0.0
var datos := {}
var reposo := PackedVector3Array()

func _init() -> void:
	var raiz := Node3D.new()
	root.add_child(raiz)
	var piso := StaticBody3D.new()
	var forma_piso := CollisionShape3D.new()
	forma_piso.shape = WorldBoundaryShape3D.new()
	piso.add_child(forma_piso)
	raiz.add_child(piso)
	pelota = RigidBody3D.new()
	pelota.name = "Pelota"
	var forma := CollisionShape3D.new()
	forma.name = "CollisionShape3D"
	var esfera := SphereShape3D.new()
	esfera.radius = 0.11
	forma.shape = esfera
	pelota.add_child(forma)
	pelota.mass = 0.43
	pelota.continuous_cd = true
	pelota.physics_material_override = PhysicsMaterial.new()
	pelota.physics_material_override.bounce = 0.5
	raiz.add_child(pelota)
	red = load("res://scripts/red_arco.gd").new()
	red.pelota = pelota
	# Los de game.tscn.
	red.holgura = 0.15
	red.elasticidad = 0.0002
	red.estiramiento_maximo = 0.12
	var otros := OS.get_environment("RED")
	if otros != "":
		var v := otros.split(",")
		for i in v.size():
			if v[i] != "":
				red.set(["holgura", "elasticidad", "estiramiento_maximo", "rebote", "agarre", "masa_red", "amortiguacion"][i], float(v[i]))
	raiz.add_child(red)
	physics_frame.connect(_paso)

func _empezar() -> void:
	reposo = red._x.duplicate()
	print("red: holgura %.3f elasticidad %s estiramiento %.3f rebote %.2f agarre %.1f masa %.1f, %d nudos, %d hilos" % [red.holgura, red.elasticidad, red.estiramiento_maximo, red.rebote, red.agarre, red.masa_red, red._x.size(), red._largo.size()])
	_tirar()

func _tirar() -> void:
	var tiro: Array = TIROS[idx]
	var desde: Vector3 = tiro[1]
	var hacia: Vector3 = tiro[2]
	var vel: float = tiro[3]
	pelota.global_position = desde
	pelota.angular_velocity = Vector3.ZERO
	var v: Vector3
	if vel == 0.0:
		v = hacia
	elif vel < 0.0:
		var tt := -vel * 1.3 if vel < -1.5 else 1.3
		var d := hacia - desde
		v = Vector3(d.x / tt, (d.y + 0.5 * 9.8 * tt * tt) / tt, d.z / tt)
	else:
		var d := hacia - desde
		var tt := d.length() / vel
		v = Vector3(d.x / tt, (d.y + 0.5 * 9.8 * tt * tt) / tt, d.z / tt)
	pelota.linear_velocity = v
	t = 0.0
	datos = {"z_min": 0.0, "toco": false, "sale": 0.0, "mueve": 0, "despl": 0.0, "escapa": false, "afuera": false}

func _paso() -> void:
	if reposo.is_empty():
		if red._x.is_empty():
			return
		_empezar()
		return
	t += 1.0 / 60.0
	var p := pelota.global_position
	var x: PackedVector3Array = red._x
	var movidos := 0
	var despl := 0.0
	for i in x.size():
		var d := x[i].distance_to(reposo[i])
		despl = maxf(despl, d)
		if d > 0.05:
			movidos += 1
	if despl > 0.05:
		datos["toco"] = true
	datos["mueve"] = maxi(datos["mueve"], movidos)
	datos["despl"] = maxf(datos["despl"], despl)
	datos["z_min"] = minf(datos["z_min"], p.z)
	if datos["toco"]:
		datos["sale"] = maxf(datos["sale"], pelota.linear_velocity.z)
	var tiro: Array = TIROS[idx]
	if OS.get_environment("TRAZA") != "" and str(tiro[0]).begins_with(OS.get_environment("TRAZA")) and t < 3.0:
		print("  t %.3f p (%.2f, %.2f, %.2f) v (%.1f, %.1f, %.1f) lado %d cand %d" % [t, p.x, p.y, p.z, pelota.linear_velocity.x, pelota.linear_velocity.y, pelota.linear_velocity.z, red._lado_pelota, red._candidatos.size()])
	var entra: bool = absf((tiro[2] as Vector3).x) < 3.6 and (tiro[2] as Vector3).y < 2.4 and tiro[3] != 0.0
	# Atraveso: entro y termino afuera de la caja de la red, o vino de afuera y quedo adentro.
	var adentro := absf(p.x) < 3.665 + 0.05 and p.y < 2.445 + 0.05 and p.z < 0.0 and p.z > -1.505 - 1.2
	if t > 2.5:
		var bolsa: float = -1.505 - datos["z_min"]
		if entra:
			datos["escapa"] = p.z < -1.505 - 1.0 or absf(p.x) > 3.665 + 0.4 or p.y > 2.445 + 0.5
		else:
			datos["escapa"] = adentro and p.z < -0.3
		print("%-22s bolsa %+.2f m  despl red %.2f m  mueve %3d nudos  sale %4.1f m/s  final (%.2f, %.2f, %.2f)%s" % [tiro[0], bolsa, datos["despl"], datos["mueve"], datos["sale"], p.x, p.y, p.z, "  << ATRAVESO" if datos["escapa"] else ""])
		idx += 1
		if idx >= TIROS.size():
			quit()
			return
		# La red vuelve a quedar quieta para el tiro siguiente.
		red._x = reposo.duplicate()
		red._xp = reposo.duplicate()
		_tirar()
