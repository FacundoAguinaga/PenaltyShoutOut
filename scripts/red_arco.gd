@tool
extends Node3D
class_name RedArco

## Red del arco simulada como tela (masa-resorte resuelto con XPBD).
##
## La red es una malla de particulas unidas por hilos. Los bordes que van
## atados al arco (palos, travesano, piso y barra trasera) quedan fijos; el
## resto cuelga con un poco de holgura y se mueve con gravedad.
##
## La pelota y la red se empujan entre si: la pelota hunde la red, y la red le
## devuelve la fuerza y la frena. Por eso la pelota no rebota como contra una
## pared sino que se "embolsa", pierde velocidad y cae, como en la tele.
##
## Detalles que importan:
## - Los hilos solo resisten estirarse, no comprimirse (como una soga). Eso
##   hace que la red cuelgue floja y forme pliegues naturales.
## - El choque pelota-red se hace contra los triangulos de la malla, no contra
##   las particulas, para que la pelota no se cuele entre dos nudos.
## - El choque es de un solo lado. Mientras la pelota esta lejos de la red se
##   decide si esta adentro del arco (entro por la boca) o afuera (paso por
##   arriba o por al lado del palo), y mientras la toca se la mantiene de ese
##   lado de la tela. Asi un tiro a 30 m/s no puede atravesar la red aunque
##   cruce el plano en un solo paso, y un tiro desviado que pega en la red
##   lateral por afuera la empuja hacia adentro.
## - Ademas de los hilos, cada nudo tiene "ataduras" invisibles a los puntos
##   fijos de su mismo panel (piso, palos, barra trasera) que no lo dejan
##   alejarse mas que el largo de hilo disponible. Es lo que pone un limite a
##   que tan honda se hace la bolsa aunque el tiro venga muy fuerte, y es
##   barato porque no depende de que los hilos converjan.
## - Se simula en varios subpasos por frame de fisica para que la pelota nunca
##   avance mas que su radio entre chequeos.
## - Cuando la red queda quieta y la pelota esta lejos, la simulacion se duerme
##   y no cuesta nada.
##
## Todo se calcula en coordenadas locales de este nodo: el origen es el centro
## de la linea de gol (al pie, entre los palos) y la red se extiende hacia -Z.

@export var pelota: RigidBody3D
@export var material: Material

@export_group("Forma")
## Ancho entre palos, en metros (por dentro).
@export var ancho: float = 7.33
## Alto hasta el travesano, en metros.
@export var alto: float = 2.445
## Cuanto se extiende la red hacia atras de la linea de gol, en metros.
@export var profundidad: float = 1.505
## Distancia entre nudos de la simulacion, en metros. Mas chico se ve mejor
## pero cuesta mas. El dibujo de los hilos es independiente de esto.
@export var separacion: float = 0.24
## Si la red esta atada a una barra arriba atras (arcos tipo caja).
@export var fijar_borde_trasero: bool = true

@export_group("Tela")
## Cuanto mas largos que la distancia entre nudos son los hilos. Con 0 la red
## queda tirante; con 0.03 a 0.06 cuelga como una red real.
@export_range(0.0, 0.2) var holgura: float = 0.04
## Masa total de la red, en kg. Mas pesada = frena mas a la pelota.
@export var masa_red: float = 6.0
## Elasticidad de los hilos (compliance de XPBD, en m/N). 0 = hilo que no
## estira nada. Valores mas altos dejan que la pelota hunda mas la red.
@export var elasticidad: float = 0.00001
## Cuanto mas que su largo puede estirarse la red en total antes de frenar en
## seco. Junto con la holgura define la profundidad maxima de la bolsa.
@export_range(0.0, 0.2) var estiramiento_maximo: float = 0.03
## Cuanto movimiento pierde la red por segundo (aire, roce de los hilos).
@export var amortiguacion: float = 3.0

@export_group("Pelota")
## Cuanto "agarra" la red a la pelota mientras la toca, por segundo. Es lo que
## hace que la pelota quede muerta en la red en vez de salir rebotando.
@export var agarre: float = 10.0
## Cuanto de la velocidad con que la pelota entra a la red le devuelve la red.
## 0 = la pelota queda muerta; las redes reales andan por 0.05 a 0.15.
@export_range(0.0, 1.0) var rebote: float = 0.1
## Maximo de subpasos por frame de fisica mientras la pelota esta cerca. Se
## usan los necesarios para que la pelota avance menos de un radio por
## subpaso: un tiro fuerte usa todos, una pelota que rueda usa pocos.
@export_range(2, 32) var subpasos: int = 8
## Subpasos por frame cuando la red se mueve sola (sin pelota cerca).
@export_range(1, 16) var subpasos_reposo: int = 2

const GRAVEDAD := Vector3(0.0, -9.8, 0.0)
const RADIO_PELOTA_DEFECTO := 0.11
## Con cuanta velocidad (m/s) tiene que estar apretando la pelota contra la red
## para que el agarre actue completo.
const VELOCIDAD_AGARRE_PLENO := 0.5
## La red se duerme despues de esta cantidad de frames sin moverse.
const FRAMES_PARA_DORMIR := 45
const ALTURA_TELA_EN_PISO := 0.07
## Cuanto puede corregir un contacto de una vez: evita que un pliegue la dispare.
const HUNDIDA_MAXIMA := 0.1
## Red de seguridad: la pelota de adentro no sale de la caja de la red mas esto.
const BOLSA_MAXIMA := 1.0

# --- Simulacion (indices de particula) ---
var _x := PackedVector3Array()   # posicion actual
var _xp := PackedVector3Array()  # posicion del subpaso anterior (Verlet)
var _w := PackedFloat32Array()   # inversa de la masa; 0 = nudo fijo
var _libres := PackedInt32Array()
var _hilos := PackedInt32Array() # pares de particulas unidas
var _largo := PackedFloat32Array()
var _atadura := PackedInt32Array()      # pares (nudo libre, punto fijo)
var _largo_atadura := PackedFloat32Array()
var _tri := PackedInt32Array()   # triangulos (de a tres), normal hacia adentro del arco
var _tris_de_particula: Array[PackedInt32Array] = []

# --- Dibujo (cada panel tiene sus propios vertices para tener sus UV) ---
var _vert_a_particula := PackedInt32Array()
var _uv := PackedVector2Array()
var _indices := PackedInt32Array()

var _malla: ArrayMesh
var _instancia: MeshInstance3D
var _caja_reposo: AABB
var _radio_pelota := RADIO_PELOTA_DEFECTO

var _activa := false
var _frames_quieta := 0
var _candidatos := PackedInt32Array()
var _hubo_contacto := false
## 1 si la pelota esta del lado de adentro de la red, -1 si esta afuera.
var _lado_pelota := 1.0

func _ready() -> void:
	_construir()
	_asentar(240)
	_crear_malla()
	_actualizar_malla()

	if Engine.is_editor_hint():
		set_physics_process(false)
		return

	if pelota:
		var forma := pelota.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if forma and forma.shape is SphereShape3D:
			_radio_pelota = (forma.shape as SphereShape3D).radius

# ---------------------------------------------------------------------------
# Construccion
# ---------------------------------------------------------------------------

func _construir() -> void:
	_x.clear(); _xp.clear(); _w.clear(); _hilos.clear(); _largo.clear(); _tri.clear()
	_atadura.clear(); _largo_atadura.clear()
	_vert_a_particula.clear(); _uv.clear(); _indices.clear()
	_tris_de_particula.clear()

	var mitad := ancho * 0.5
	var nu := maxi(2, roundi(ancho / separacion))
	var na := maxi(2, roundi(alto / separacion))
	var np := maxi(1, roundi(profundidad / separacion))

	var soldar := {}  # posicion en reposo redondeada -> indice de particula
	var hilos_vistos := {}

	# Fondo y techo como un solo panel doblado: arranca en el piso atras, sube
	# por el fondo y viene hacia adelante por el techo hasta el travesano. Asi
	# el hilo del dibujo sigue de corrido por el doblez.
	var filas := na + np + 1
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	for j in filas:
		for i in nu + 1:
			var x := -mitad + ancho * i / nu
			if j <= na:
				var y := alto * j / na
				pos.append(Vector3(x, y, -profundidad))
				uv.append(Vector2(x, y))
			else:
				var k := j - na
				var z := -profundidad + profundidad * k / np
				pos.append(Vector3(x, alto, z))
				uv.append(Vector2(x, alto + profundidad * k / np))
	_agregar_panel(pos, uv, nu + 1, filas, soldar, hilos_vistos)

	# Laterales: comparten con el panel principal la columna de atras y la
	# fila de arriba; esas particulas se sueldan por posicion.
	for lado in [-1.0, 1.0]:
		pos = PackedVector3Array()
		uv = PackedVector2Array()
		for j in na + 1:
			for k in np + 1:
				var y := alto * j / na
				var z := -profundidad + profundidad * k / np
				pos.append(Vector3(lado * mitad, y, z))
				uv.append(Vector2(z, y))
		_agregar_panel(pos, uv, np + 1, na + 1, soldar, hilos_vistos)

	var inv_masa := float(_x.size()) / maxf(masa_red, 0.01)
	_w.resize(_x.size())
	_libres.clear()
	for i in _x.size():
		_w[i] = 0.0 if _es_fija(_x[i]) else inv_masa
		if _w[i] > 0.0:
			_libres.append(i)
	_xp = _x.duplicate()

	_tris_de_particula.resize(_x.size())
	for i in _x.size():
		_tris_de_particula[i] = PackedInt32Array()
	for t in _tri.size() / 3:
		for k in 3:
			_tris_de_particula[_tri[t * 3 + k]].append(t)

	_construir_ataduras()
	_caja_reposo = AABB(Vector3(-mitad, 0.0, -profundidad), Vector3(ancho, alto, profundidad))

func _agregar_panel(pos: PackedVector3Array, uv: PackedVector2Array, columnas: int, filas: int,
		soldar: Dictionary, hilos_vistos: Dictionary) -> void:
	var base_vert := _vert_a_particula.size()
	for n in pos.size():
		var clave := Vector3i((pos[n] * 1000.0).round())
		var idx: int
		if soldar.has(clave):
			idx = soldar[clave]
		else:
			idx = _x.size()
			_x.append(pos[n])
			soldar[clave] = idx
		_vert_a_particula.append(idx)
		_uv.append(uv[n])

	# Hilos a lo largo de la cuadricula, sin repetir los de los bordes soldados.
	for j in filas:
		for i in columnas:
			var a := _vert_a_particula[base_vert + j * columnas + i]
			if i + 1 < columnas:
				_agregar_hilo(a, _vert_a_particula[base_vert + j * columnas + i + 1], hilos_vistos)
			if j + 1 < filas:
				_agregar_hilo(a, _vert_a_particula[base_vert + (j + 1) * columnas + i], hilos_vistos)

	# Triangulos: los de dibujo usan los vertices del panel, los de choque las
	# particulas. Se orientan para que la normal apunte hacia adentro del arco.
	var adentro := Vector3(0.0, alto * 0.5, -profundidad * 0.5)
	for j in filas - 1:
		for i in columnas - 1:
			var v00 := base_vert + j * columnas + i
			var v10 := v00 + 1
			var v01 := v00 + columnas
			var v11 := v01 + 1
			for t in [[v00, v10, v11], [v00, v11, v01]]:
				var pa := _x[_vert_a_particula[t[0]]]
				var pb := _x[_vert_a_particula[t[1]]]
				var pc := _x[_vert_a_particula[t[2]]]
				var normal := (pb - pa).cross(pc - pa)
				if normal.dot(adentro - (pa + pb + pc) / 3.0) < 0.0:
					t = [t[0], t[2], t[1]]
				for v in t:
					_indices.append(v)
					_tri.append(_vert_a_particula[v])

func _agregar_hilo(a: int, b: int, vistos: Dictionary) -> void:
	if _es_fija(_x[a]) and _es_fija(_x[b]):
		return
	var clave := mini(a, b) * 100000 + maxi(a, b)
	if vistos.has(clave):
		return
	vistos[clave] = true
	_hilos.append(a)
	_hilos.append(b)
	_largo.append(_x[a].distance_to(_x[b]) * (1.0 + holgura))

## Cada nudo libre se ata al punto fijo mas cercano de cada tipo (piso, marco,
## barra) que este en su mismo plano. Solo dentro del mismo plano la distancia
## en linea recta es igual al largo de hilo que hay entre los dos; si no, la
## atadura cruzaria por adentro del arco y tironearia la red.
func _construir_ataduras() -> void:
	var mitad := ancho * 0.5
	var planos := [
		func(p: Vector3) -> bool: return absf(p.z + profundidad) < 0.001,  # fondo
		func(p: Vector3) -> bool: return absf(p.y - alto) < 0.001,         # techo
		func(p: Vector3) -> bool: return absf(p.x + mitad) < 0.001,        # lateral izq
		func(p: Vector3) -> bool: return absf(p.x - mitad) < 0.001,        # lateral der
	]
	var factor := (1.0 + holgura) * (1.0 + estiramiento_maximo)
	for en_plano in planos:
		var fijas_por_tipo := {}
		var libres := PackedInt32Array()
		for i in _x.size():
			if not en_plano.call(_x[i]):
				continue
			if _w[i] == 0.0:
				var tipo := _tipo_de_fija(_x[i])
				if not fijas_por_tipo.has(tipo):
					fijas_por_tipo[tipo] = []
				fijas_por_tipo[tipo].append(i)
			else:
				libres.append(i)
		for i in libres:
			for tipo in fijas_por_tipo:
				var mejor := -1
				var mejor_d := INF
				for f in fijas_por_tipo[tipo]:
					var d := _x[i].distance_squared_to(_x[f])
					if d < mejor_d:
						mejor_d = d
						mejor = f
				_atadura.append(i)
				_atadura.append(mejor)
				_largo_atadura.append(sqrt(mejor_d) * factor)

func _tipo_de_fija(p: Vector3) -> int:
	if p.y < 0.001:
		return 0  # piso
	if absf(p.z) < 0.001:
		return 1  # palos y travesano
	return 2      # barra trasera

func _es_fija(p: Vector3) -> bool:
	const E := 0.001
	if absf(p.z) < E:  # palos y travesano
		return true
	if p.y < E:  # atada al piso
		return true
	if fijar_borde_trasero and absf(p.y - alto) < E and absf(p.z + profundidad) < E:
		return true
	return false

## Deja que la red cuelgue con su holgura antes de que empiece el juego.
func _asentar(pasos: int) -> void:
	var h := 1.0 / 240.0
	for s in pasos:
		_predecir(h)
		_resolver_hilos(h)
		_resolver_ataduras()
	_xp = _x.duplicate()

# ---------------------------------------------------------------------------
# Simulacion
# ---------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	var cerca := _pelota_cerca(dt)
	if cerca:
		_activa = true
		_frames_quieta = 0
	if not _activa:
		return

	var n := subpasos_reposo
	if cerca:
		var avance := pelota.linear_velocity.length() * dt
		n = clampi(ceili(avance / (_radio_pelota * 0.9)), subpasos_reposo, subpasos)
	var h := dt / n

	var inv_base := global_basis.inverse()
	var bpos := Vector3.ZERO
	var bvel := Vector3.ZERO
	var wb := 0.0
	if cerca:
		bpos = to_local(pelota.global_position)
		bvel = inv_base * pelota.linear_velocity
		wb = 0.0 if pelota.freeze else 1.0 / maxf(pelota.mass, 0.01)
		_buscar_candidatos(bpos, bvel, dt)
		# Delante de la boca se decide en cada frame: la pelota puede subir
		# por encima del travesano o abrirse del palo antes de llegar. Atras,
		# solo mientras no toca la red (si no, una pelota embolsada detras de
		# la linea del fondo pasaria a contar como "afuera").
		if bpos.z > 0.0 or _candidatos.is_empty():
			_lado_pelota = 1.0 if _en_el_arco(bpos) else -1.0

	var contacto_en_frame := false
	for s in n:
		_predecir(h)
		var bprev := bpos
		if wb > 0.0:
			bpos += bvel * h
		var bpredicha := bpos
		_resolver_hilos(h)
		_resolver_ataduras()
		if cerca:
			_hubo_contacto = false
			# Primero se empujan pelota y red entre si segun sus masas; despues
			# se corrige solo la pelota para garantizar que no quede adentro de
			# la red (es lo que impide que la atraviese).
			bpos = _resolver_contactos(bpos, bprev, wb, true)
			if wb > 0.0:
				bpos = _resolver_contactos(bpos, bprev, wb, false)
				if _lado_pelota > 0.0:
					var limitada := _limitar_a_la_bolsa(bpos)
					if limitada != bpos:
						_hubo_contacto = true
						bpos = limitada
				if _hubo_contacto:
					# Lo que la red corrio a la pelota se vuelve velocidad, pero
					# con tope: como mucho frena lo que iba hacia la red y le
					# devuelve un poco como rebote. Sin el tope, el retroceso de
					# la tela la escupiria como un trampolin.
					var correccion := bpos - bpredicha
					var largo_corr := correccion.length()
					if largo_corr > 1e-6:
						var normal := correccion / largo_corr
						var hacia_red := bvel.dot(normal)
						if hacia_red < 0.0:
							bvel += normal * minf(largo_corr / h, -hacia_red * (1.0 + rebote))
					# El agarre es roce: depende de cuanto aprieta la pelota
					# contra la red. Al impacto la frena fuerte; apoyada, la
					# deja resbalar hacia abajo por la tela.
					var apriete := clampf(largo_corr / (h * VELOCIDAD_AGARRE_PLENO), 0.0, 1.0)
					bvel *= exp(-agarre * h * apriete)
					contacto_en_frame = true

	if contacto_en_frame:
		# Se deja la pelota donde la ubico la red: el paso de fisica de Godot
		# la va a mover bvel*dt, asi que se la corre para atras eso mismo.
		var vel_global := global_basis * bvel
		pelota.global_position = to_global(bpos) - vel_global * dt
		pelota.linear_velocity = vel_global
		pelota.angular_velocity *= exp(-agarre * 0.5 * dt)

	_actualizar_malla()
	_quizas_dormir(cerca)

func _limitar_a_la_bolsa(p: Vector3) -> Vector3:
	var mitad := ancho * 0.5 + BOLSA_MAXIMA
	return Vector3(clampf(p.x, -mitad, mitad), minf(p.y, alto + BOLSA_MAXIMA), maxf(p.z, -profundidad - BOLSA_MAXIMA))

func _pelota_cerca(dt: float) -> bool:
	if pelota == null or not pelota.is_inside_tree():
		return false
	var p := to_local(pelota.global_position)
	var margen := _radio_pelota + pelota.linear_velocity.length() * dt + 0.8
	return _caja_reposo.grow(margen).has_point(p)

## Lo que la red encierra, mas lo que queda delante de la boca del arco.
func _en_el_arco(p: Vector3) -> bool:
	return absf(p.x) < ancho * 0.5 and p.y < alto and p.z > -profundidad

# Los bucles de abajo corren miles de veces por frame. Trabajan sobre copias
# locales de los arreglos (en GDScript acceder a una variable local es bastante
# mas rapido que a una del nodo) y las devuelven al final.

## Integra los nudos libres (Verlet) y los apoya en el pasto.
func _predecir(h: float) -> void:
	var freno := exp(-amortiguacion * h)
	var g := (global_basis.inverse() * GRAVEDAD) * h * h
	var x := _x
	var xp := _xp
	for i in _libres:
		var actual := x[i]
		var nueva := actual + (actual - xp[i]) * freno + g
		xp[i] = actual
		if nueva.y < 0.0:
			# Roce con el pasto: no se desliza.
			nueva.y = 0.0
			xp[i] = Vector3(nueva.x, actual.y, nueva.z)
		x[i] = nueva
	_x = x
	_xp = xp

## Hilos que solo tiran (no empujan), con XPBD para que la elasticidad no
## dependa de la cantidad de subpasos.
func _resolver_hilos(h: float) -> void:
	var alfa := elasticidad / (h * h)
	var x := _x
	var w := _w
	var hilos := _hilos
	var largos := _largo
	for k in largos.size():
		var i := hilos[k * 2]
		var j := hilos[k * 2 + 1]
		var d := x[j] - x[i]
		var largo := d.length()
		var estirado := largo - largos[k]
		if estirado <= 0.0:
			continue
		var wi := w[i]
		var wj := w[j]
		var f := estirado / ((wi + wj + alfa) * largo)
		x[i] += d * (f * wi)
		x[j] -= d * (f * wj)
	_x = x

## Si un nudo se alejo de su punto fijo mas de lo que da el hilo, se lo trae
## de vuelta y se le saca la velocidad en esa direccion. Sacarle la velocidad
## es lo que evita que la red "escupa" la pelota como un trampolin.
func _resolver_ataduras() -> void:
	var x := _x
	var xp := _xp
	var ataduras := _atadura
	var maximos := _largo_atadura
	for k in maximos.size():
		var i := ataduras[k * 2]
		var d := x[i] - x[ataduras[k * 2 + 1]]
		var maximo := maximos[k]
		if d.length_squared() <= maximo * maximo:
			continue
		var largo := d.length()
		var dir := d / largo
		var p := x[i] - dir * (largo - maximo)
		var v := p - xp[i]
		x[i] = p
		xp[i] = p - (v - dir * v.dot(dir))
	_x = x
	_xp = xp

## Arma la lista de triangulos que la pelota puede tocar en este frame.
func _buscar_candidatos(bpos: Vector3, bvel: Vector3, dt: float) -> void:
	var fin := bpos + bvel * dt
	var alcance := _radio_pelota + separacion * 1.5
	var alcance2 := alcance * alcance
	var vistos := {}
	_candidatos.clear()
	for i in _x.size():
		var q := Geometry3D.get_closest_point_to_segment(_x[i], bpos, fin)
		if q.distance_squared_to(_x[i]) > alcance2:
			continue
		for t in _tris_de_particula[i]:
			if not vistos.has(t):
				vistos[t] = true
				_candidatos.append(t)

func _resolver_contactos(bpos: Vector3, bprev: Vector3, wb: float, mover_red: bool) -> Vector3:
	var r := _radio_pelota
	var lado := _lado_pelota
	for t in _candidatos:
		var ia := _tri[t * 3]
		var ib := _tri[t * 3 + 1]
		var ic := _tri[t * 3 + 2]
		var a := _x[ia]
		var b := _x[ib]
		var c := _x[ic]
		# Tela acostada en el pasto: la pelota la pisa, no la empuja. Si contara,
		# la pelota quieta quedaria "del otro lado" y la tela la levantaria.
		if a.y < ALTURA_TELA_EN_PISO and b.y < ALTURA_TELA_EN_PISO and c.y < ALTURA_TELA_EN_PISO:
			continue
		var n := (b - a).cross(c - a)
		var largo_n := n.length()
		if largo_n < 1e-9:
			continue
		n /= largo_n

		var bc := _baricentricas(bpos, a, b, c)
		var q := a * bc.x + b * bc.y + c * bc.z
		var dif := bpos - q
		var dn := n.dot(dif) * lado
		var dir: Vector3
		var hundida: float
		if dn <= 0.0:
			# El centro quedo del lado equivocado de la tela. Cuenta si esta
			# encima del triangulo o a menos de un radio de su borde: asi se
			# atrapa tambien el caso de la punta de la bolsa, donde la pelota
			# pasa justo por un nudo y no cae adentro de ningun triangulo.
			if (dif - n * n.dot(dif)).length_squared() >= r * r:
				continue
			# Solo si recien cruzo. Si ya estaba de ese lado, es un pliegue de la
			# tela que quedo detras de la pelota, no un cruce.
			if n.dot(bprev - q) * lado <= 0.0:
				continue
			dir = n * lado
			hundida = r - dn
		else:
			var dist := dif.length()
			if dist >= r:
				continue
			dir = dif / dist
			hundida = r - dist

		var wa := _w[ia] if mover_red else 0.0
		var wbb := _w[ib] if mover_red else 0.0
		var wc := _w[ic] if mover_red else 0.0
		var denom := wb + bc.x * bc.x * wa + bc.y * bc.y * wbb + bc.z * bc.z * wc
		if denom <= 0.0:
			continue
		var l := minf(hundida, HUNDIDA_MAXIMA) / denom
		bpos += dir * (l * wb)
		if mover_red:
			_x[ia] -= dir * (l * bc.x * wa)
			_x[ib] -= dir * (l * bc.y * wbb)
			_x[ic] -= dir * (l * bc.z * wc)
		_hubo_contacto = true
	return bpos

## Coordenadas baricentricas del punto del triangulo abc mas cercano a p
## (Ericson, Real-Time Collision Detection 5.1.5).
static func _baricentricas(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return Vector3(1, 0, 0)
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return Vector3(0, 1, 0)
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		var v := d1 / (d1 - d3)
		return Vector3(1.0 - v, v, 0.0)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return Vector3(0, 0, 1)
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		var w := d2 / (d2 - d6)
		return Vector3(1.0 - w, 0.0, w)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return Vector3(0.0, 1.0 - w, w)
	var denom := 1.0 / (va + vb + vc)
	var v := vb * denom
	var w := vc * denom
	return Vector3(1.0 - v - w, v, w)

func _quizas_dormir(cerca: bool) -> void:
	var mov := 0.0
	for i in _x.size():
		mov = maxf(mov, _x[i].distance_squared_to(_xp[i]))
	if cerca or mov > 1e-8:
		_frames_quieta = 0
		return
	_frames_quieta += 1
	if _frames_quieta >= FRAMES_PARA_DORMIR:
		_activa = false
		_xp = _x.duplicate()

# ---------------------------------------------------------------------------
# Dibujo
# ---------------------------------------------------------------------------

func _crear_malla() -> void:
	if _instancia == null:
		_instancia = MeshInstance3D.new()
		_instancia.name = "MallaRed"
		_instancia.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_instancia)
	_malla = ArrayMesh.new()
	_instancia.mesh = _malla
	# La red se puede inflar fuera de su caja de reposo; sin esto Godot la
	# recortaria al salir de camara.
	_instancia.custom_aabb = _caja_reposo.grow(1.0)

func _actualizar_malla() -> void:
	var cant := _vert_a_particula.size()
	var verts := PackedVector3Array()
	verts.resize(cant)
	for v in cant:
		verts[v] = _x[_vert_a_particula[v]]

	var normales := PackedVector3Array()
	normales.resize(cant)
	for k in range(0, _indices.size(), 3):
		var a := _indices[k]
		var b := _indices[k + 1]
		var c := _indices[k + 2]
		var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normales[a] += n
		normales[b] += n
		normales[c] += n
	for v in cant:
		normales[v] = normales[v].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normales
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _indices
	_malla.clear_surfaces()
	_malla.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material:
		_malla.surface_set_material(0, material)
