extends Node

## Hornea los espectadores de la tribuna. Convierte cada personaje (FBX de
## Mixamo o compatible) en lo que usa el juego:
##   - 2 mallas livianas (cerca y media)
##   - una textura con todas las animaciones (VAT)
##   - las "fotos" para los espectadores lejanos (impostores)
## y deja todo en resources/hinchada/ (banco.tres es el indice).
##
## Uso (necesita ventana, no anda con --headless):
##   godot --path . res://tools/hinchada_hornear.tscn
##   godot --path . res://tools/hinchada_hornear.tscn -- carpeta_para_vistas_previas
##
## PARA AGREGAR UN NPC: copiar su FBX (personaje de Mixamo "con skin", en T)
## a assets/models/people/npc/, abrir Godot una vez para que lo importe y
## volver a correr esto. Las animaciones son las de ANIMS y sirven para
## cualquier personaje con esqueleto de Mixamo. Ver docs/hinchada.md.

const DIR_NPC := "res://assets/models/people/npc/"
const DIR_ANIM := "res://assets/models/people/3d/"
const DIR_SALIDA := "res://resources/hinchada/"
## Personajes que ya estaban en el proyecto: [archivo, nombre].
const NPC_BASE := [["res://assets/models/people/3d/Cheering.fbx", "ch42"]]

const FPS := 15.0
## Cuadros que se funden para que el final de un recorte empalme con su inicio.
const MEZCLA_BUCLE := 5
## [nombre, archivo, desde, hasta] en segundos. hasta < 0 = el clip entero.
## El orden no importa para el juego (se busca por nombre), pero si agregas
## animaciones hay que usarlas en scripts/hinchada_conductas.gd. Maximo 16.
const ANIMS := [
	["idle", "Breathing Idle.fbx", 0.0, 4.0],
	["aplauso", "Clapping.fbx", 0.0, -1.0],
	["festejo", "Cheering.fbx", 0.0, -1.0],
	["victoria", "Victory.fbx", 0.0, 4.5],
	["enojo", "Angry.fbx", 1.0, 5.5],
	["triste", "Sad Idle.fbx", 0.0, -1.0],
	["sentado", "Sitting.fbx", 0.0, 4.0],
	["sentado_aplauso", "Sitting Clap.fbx", 0.0, -1.0],
	["charla_izq", "Sitting Talking head to left.fbx", 4.0, 9.0],
	["charla_der", "Sitting Talking head to right.fbx", 4.0, 9.0],
	["sentado_festejo", "sitting Victory.fbx", 0.0, 5.0],
]
## Triangulos que se buscan para cada nivel de detalle.
const TRIS_OBJETIVO := [2600, 1500]
const LADO_ALBEDO := 1024

## Cada foto de impostor: tamaño en pixeles y en metros (misma proporcion).
const CELDA_PX := Vector2i(104, 176)
const CELDA_MUNDO := Vector2(1.40625, 2.38)
## Fotos por animacion. Mas = movimiento mas suave de lejos y textura mas grande.
const CUADROS_IMP := 12
## Cuantos NPC entran por fila en la textura de impostores.
const NPC_POR_FILA := 4

enum Region { CABEZA, CUERPO, REMERA, PANTALON, OTRO }
## [nombre, parte de los triangulos que se lleva cada region]
const REGIONES := [["cabeza", 0.28], ["brazos y piernas", 0.25], ["remera", 0.24], ["pantalon", 0.12], ["calzado", 0.11]]

enum Parte { OTRO, REMERA, PANTALON, PIEL, PELO, AUTO = 98, OMITIR = 99 }

const PALABRAS := [
	[Parte.OMITIR, ["eyelash", "pesta", "hair", "pelo", "beard", "barba", "brow"]],
	[Parte.REMERA, ["shirt", "top", "jersey", "camis", "remera", "torso", "jacket", "hoodie", "sweater", "coat", "vest"]],
	[Parte.PANTALON, ["short", "pant", "trouser", "jean", "bottom", "skirt", "legging"]],
	[Parte.OTRO, ["shoe", "sneaker", "boot", "zapat", "sandal", "sock", "hat", "cap", "gorra", "glass"]],
	[Parte.PIEL, ["body", "skin", "head", "face", "piel", "cuerpo"]],
]

var _vistas: String = ""
var _clips: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_vistas = args[0]
		DirAccess.make_dir_recursive_absolute(_vistas)
	DirAccess.make_dir_recursive_absolute(DIR_SALIDA)
	await get_tree().process_frame

	var viejo: HinchadaBanco = load(DIR_SALIDA + "banco.tres") if ResourceLoader.exists(DIR_SALIDA + "banco.tres") else null
	var banco := HinchadaBanco.new()
	banco.fps = FPS
	banco.imp_cuadros = CUADROS_IMP
	banco.imp_celda = CELDA_MUNDO
	banco.imp_npc_por_fila = NPC_POR_FILA

	var fuentes: Array = NPC_BASE.duplicate()
	var d := DirAccess.open(DIR_NPC)
	if d:
		for f in d.get_files():
			var ext := f.get_extension().to_lower()
			if ext in ["fbx", "glb", "gltf"]:
				fuentes.append([DIR_NPC + f, f.get_basename().to_snake_case().validate_filename()])

	var bloques: Array = []
	for fu in fuentes:
		print("\n=== NPC %s (%s)" % [fu[1], fu[0]])
		var r: Dictionary = await _hornear_npc(fu[0], fu[1], banco)
		if r.is_empty():
			continue
		var npc: HinchadaNpc = r["npc"]
		if viejo:
			for v in viejo.npcs:
				if v.nombre == npc.nombre:
					npc.peso = v.peso
		banco.npcs.append(npc)
		bloques.append(r["fotos"])

	if banco.npcs.is_empty():
		push_error("No se pudo hornear ningun NPC.")
		get_tree().quit(1)
		return

	_guardar_atlas(banco, bloques)
	var err := ResourceSaver.save(banco, DIR_SALIDA + "banco.tres")
	print("\nBanco guardado (%s): %d NPC, %d animaciones." % [error_string(err), banco.npcs.size(), banco.anim_nombres.size()])
	get_tree().quit()

# ---------------------------------------------------------------- un NPC

func _hornear_npc(ruta: String, nombre: String, banco: HinchadaBanco) -> Dictionary:
	var escena: PackedScene = load(ruta)
	if escena == null:
		push_error("No se pudo cargar %s (¿lo importo Godot?)" % ruta)
		return {}
	var raiz: Node3D = escena.instantiate()
	raiz.visible = false
	add_child(raiz)
	var esq := _buscar_esqueleto(raiz)
	if esq == null:
		push_error("%s no tiene esqueleto." % ruta)
		raiz.queue_free()
		return {}
	var a_raiz: Transform3D = raiz.global_transform.affine_inverse() * esq.global_transform
	var manual := _leer_partes_manuales(ruta)

	# --- 1. Juntar todas las mallas en una sola lista de vertices
	var v_malla := PackedVector3Array()   # posicion en espacio de la malla
	var n_malla := PackedVector3Array()
	var v_uv := PackedVector2Array()
	var v_parte := PackedInt32Array()
	var v_tex := PackedInt32Array()
	var v_hueso := PackedInt32Array()     # hueso que mas pesa en el vertice
	var ropa_aparte := {Parte.REMERA: false, Parte.PANTALON: false}
	var inf_ranura := PackedInt32Array()  # 8 por vertice
	var inf_peso := PackedFloat32Array()
	var indices := PackedInt32Array()
	var ranura_hueso := PackedInt32Array()
	var ranura_bind: Array[Transform3D] = []
	var texturas: Array[Image] = []
	var tex_clave: Dictionary = {}

	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var parte_malla := _clasificar(mi.name, manual)
		if parte_malla == Parte.OMITIR:
			print("  - %s: se omite" % mi.name)
			continue
		var base_ranura := ranura_hueso.size()
		var skin := mi.skin
		if skin:
			for i in skin.get_bind_count():
				var b := skin.get_bind_bone(i)
				if b < 0:
					b = esq.find_bone(skin.get_bind_name(i))
				ranura_hueso.append(maxi(b, 0))
				ranura_bind.append(skin.get_bind_pose(i))
		else:
			for b in esq.get_bone_count():
				ranura_hueso.append(b)
				ranura_bind.append(esq.get_bone_global_rest(b).affine_inverse())
		for s in mi.mesh.get_surface_count():
			var parte := parte_malla
			var mat := mi.get_active_material(s)
			if parte == Parte.AUTO and mat:
				parte = _clasificar(mat.resource_name, manual)
			var arr := mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_INDEX] == null:
				print("  - %s: sin huesos o sin indices, se omite" % mi.name)
				continue
			var hs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var por := hs.size() / vs.size()
			var base := v_malla.size()
			var it := _indice_textura(mat, texturas, tex_clave)
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			for i in vs.size():
				v_malla.append(vs[i])
				n_malla.append(ns[i] if i < ns.size() else Vector3.UP)
				v_uv.append(uvs[i] if i < uvs.size() else Vector2.ZERO)
				v_tex.append(it)
				var mejor := 0
				var mejor_w := -1.0
				for j in 8:
					var w := ws[i * por + j] if j < por else 0.0
					var r := base_ranura + hs[i * por + j] if j < por else 0
					inf_ranura.append(r)
					inf_peso.append(w)
					if w > mejor_w:
						mejor_w = w
						mejor = r
				var p := parte
				if p == Parte.AUTO:
					p = _parte_por_hueso(esq.get_bone_name(ranura_hueso[mejor]))
				elif ropa_aparte.has(p):
					ropa_aparte[p] = true
				v_parte.append(p)
				v_hueso.append(ranura_hueso[mejor])
			for i: int in arr[Mesh.ARRAY_INDEX]:
				indices.append(base + i)
			print("  - %s: %d vertices, parte %s" % [mi.name, vs.size(), _nombre_parte(parte)])

	var total := v_malla.size()
	if total == 0:
		push_error("%s no tiene mallas con huesos." % ruta)
		raiz.queue_free()
		return {}

	# --- 2. Pose de descanso (en T) en espacio del personaje
	esq.reset_bone_poses()
	var mats := _matrices(esq, a_raiz, ranura_hueso, ranura_bind)
	var rest := PackedVector3Array()
	var rest_n := PackedVector3Array()
	rest.resize(total)
	rest_n.resize(total)
	for i in total:
		var p := Vector3.ZERO
		var n := Vector3.ZERO
		for j in 8:
			var w := inf_peso[i * 8 + j]
			if w > 0.0:
				var m: Transform3D = mats[inf_ranura[i * 8 + j]]
				p += (m * v_malla[i]) * w
				n += (m.basis * n_malla[i]) * w
		rest[i] = p
		rest_n[i] = n.normalized() if n.length_squared() > 0.0 else Vector3.UP

	var v_pelo := _medir_pelo(esq, a_raiz, rest, v_parte, inf_ranura, inf_peso, ranura_hueso)

	# --- 3. Textura de color (una sola por NPC)
	var rejilla := int(ceil(sqrt(float(texturas.size()))))
	var lado_celda := LADO_ALBEDO / rejilla
	var atlas := Image.create(LADO_ALBEDO, LADO_ALBEDO, false, Image.FORMAT_RGBA8)
	for t in texturas.size():
		var img := texturas[t]
		img.resize(lado_celda, lado_celda, Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(img, Rect2i(0, 0, lado_celda, lado_celda), Vector2i((t % rejilla) * lado_celda, (t / rejilla) * lado_celda))
	var suma := [0.0, 0.0, 0.0, 0.0, 0.0]
	var cuenta := [0, 0, 0, 0, 0]
	for i in total:
		var uv := v_uv[i]
		uv = Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0)) if (uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0) else uv
		var t := v_tex[i]
		uv = (uv + Vector2(t % rejilla, t / rejilla)) / float(rejilla)
		v_uv[i] = uv
		var c := atlas.get_pixel(clampi(int(uv.x * LADO_ALBEDO), 0, LADO_ALBEDO - 1), clampi(int(uv.y * LADO_ALBEDO), 0, LADO_ALBEDO - 1)).srgb_to_linear()
		suma[v_parte[i]] += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		cuenta[v_parte[i]] += 1
	var lum := Vector4(0.3, 0.3, 0.3, 0.3)
	if cuenta[Parte.REMERA] > 0: lum.x = suma[Parte.REMERA] / cuenta[Parte.REMERA]
	if cuenta[Parte.PANTALON] > 0: lum.y = suma[Parte.PANTALON] / cuenta[Parte.PANTALON]
	if cuenta[Parte.PELO] > 0: lum.w = suma[Parte.PELO] / cuenta[Parte.PELO]
	# Pelo pintado: alfa 1 = normal, alfa 0 = pelo.
	atlas.convert(Image.FORMAT_RGB8)
	atlas.convert(Image.FORMAT_RGBA8)
	var suma_pelo := 0.0
	var n_pelo := 0
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var b := indices[t + 1]
		var c := indices[t + 2]
		if v_pelo[a] + v_pelo[b] + v_pelo[c] <= 0.001:
			continue
		_pintar_alfa(atlas, v_uv[a] * LADO_ALBEDO, v_uv[b] * LADO_ALBEDO, v_uv[c] * LADO_ALBEDO, v_pelo[a], v_pelo[b], v_pelo[c])
		for k: int in [a, b, c]:
			if v_pelo[k] > 0.5:
				var col := atlas.get_pixelv(Vector2i(v_uv[k] * (LADO_ALBEDO - 1))).srgb_to_linear()
				suma_pelo += col.r * 0.299 + col.g * 0.587 + col.b * 0.114
				n_pelo += 1
	if n_pelo > 0:
		lum.w = suma_pelo / n_pelo
	atlas.generate_mipmaps()
	var tex_albedo := ImageTexture.create_from_image(atlas)

	# --- 4. Simplificar: tres niveles de detalle sobre los mismos vertices
	# Primero se saca la piel que queda tapada por la ropa (no se ve y gasta
	# triangulos). Despues cada region se simplifica por separado con su
	# propio presupuesto, para que la cabeza no desaparezca en los niveles
	# bajos (es lo que mas se nota de lejos).
	var zona := PackedInt32Array() # por hueso: 1 cabeza/cuello, 2 tronco, 3 cadera
	for b in esq.get_bone_count():
		var nb := esq.get_bone_name(b).to_lower()
		if nb.contains("head") or nb.contains("neck"):
			zona.append(1)
		elif nb.contains("spine") or nb.contains("shoulder"):
			zona.append(2)
		elif nb.ends_with("hips"):
			zona.append(3)
		else:
			zona.append(0)
	var y_cuello := INF
	for b in esq.get_bone_count():
		if esq.get_bone_name(b).to_lower().contains("neck"):
			y_cuello = (a_raiz * esq.get_bone_global_rest(b)).origin.y
	var regiones: Array[PackedInt32Array] = []
	for r in REGIONES:
		regiones.append(PackedInt32Array())
	var tapados := 0
	for t in range(0, indices.size(), 3):
		var tri: Array[int] = [indices[t], indices[t + 1], indices[t + 2]]
		var p := v_parte[tri[0]]
		var region := Region.OTRO
		if p == Parte.REMERA:
			region = Region.REMERA
		elif p == Parte.PANTALON:
			region = Region.PANTALON
		elif p == Parte.PIEL or p == Parte.PELO:
			var n_cabeza := 0
			var n_tronco := 0
			var n_cadera := 0
			var bajo_cuello := true
			for k in tri:
				var z := zona[v_hueso[k]]
				n_cabeza += int(z == 1)
				n_tronco += int(z == 2)
				n_cadera += int(z == 3)
				if rest[k].y > y_cuello - 0.03:
					bajo_cuello = false
			if p == Parte.PIEL and bajo_cuello and ((ropa_aparte[Parte.REMERA] and n_tronco == 3)
					or (ropa_aparte[Parte.PANTALON] and ropa_aparte[Parte.REMERA] and n_cadera + n_tronco == 3)):
				tapados += 1
				continue
			region = Region.CABEZA if n_cabeza >= 2 else Region.CUERPO
		regiones[region].append_array(tri)
	print("  piel tapada por la ropa: %d triangulos menos" % tapados)

	var reparto_total := 0.0
	for r in REGIONES.size():
		if not regiones[r].is_empty():
			reparto_total += REGIONES[r][1]
	var niveles: Array[PackedInt32Array] = []
	for objetivo: int in TRIS_OBJETIVO:
		var nivel := PackedInt32Array()
		for r in REGIONES.size():
			if regiones[r].is_empty():
				continue
			var tris := int(round(objetivo * REGIONES[r][1] / reparto_total))
			nivel.append_array(_simplificar(regiones[r], tris, rest, rest_n, v_uv))
		niveles.append(nivel)

	# Solo se hornean los vertices que usa algun nivel.
	var columna := PackedInt32Array()
	columna.resize(total)
	columna.fill(-1)
	var usados := PackedInt32Array()
	for nv in niveles:
		for i in nv:
			if columna[i] < 0:
				columna[i] = usados.size()
				usados.append(i)
	var columnas := usados.size()
	print("  vertices originales %d -> horneados %d. Triangulos: cerca %d, media %d" % [
			total, columnas, niveles[0].size() / 3, niveles[1].size() / 3])

	var mallas: Array[ArrayMesh] = []
	for nv in niveles:
		mallas.append(_armar_malla(nv, rest, rest_n, v_uv, v_parte, columna))

	# --- 5. Hornear las animaciones (VAT)
	var filas := 0
	var plan: Array = []
	for a in ANIMS:
		var clip := _clip(a[1])
		if clip.is_empty():
			raiz.queue_free()
			return {}
		var anim: Animation = clip["anim"]
		var entero: bool = a[3] < 0.0
		var desde: float = 0.0 if entero else float(a[2])
		var hasta: float = anim.length if entero else minf(float(a[3]), anim.length)
		var n := maxi(int(round((hasta - desde) * FPS)), 2)
		plan.append({"nombre": a[0], "clip": clip, "desde": desde, "hasta": hasta, "n": n, "entero": entero, "inicio": filas})
		filas += n
	if banco.anim_nombres.is_empty():
		for pl in plan:
			banco.anim_nombres.append(pl["nombre"])
			banco.anim_inicio.append(pl["inicio"])
			banco.anim_cuadros.append(pl["n"])

	var datos := PackedFloat32Array()
	datos.resize(columnas * filas * 3)
	# Normales por cuadro (para que la luz siga al cuerpo): una textura aparte.
	var datos_n := PackedByteArray()
	datos_n.resize(columnas * filas * 3)
	var u_nor := PackedVector3Array()
	var u_pos := PackedVector3Array()
	var u_ini := PackedInt32Array()
	var u_ranura := PackedInt32Array()
	var u_peso := PackedFloat32Array()
	for i in usados:
		u_pos.append(v_malla[i])
		u_nor.append(n_malla[i])
		u_ini.append(u_ranura.size())
		for j in 8:
			if inf_peso[i * 8 + j] > 0.0:
				u_ranura.append(inf_ranura[i * 8 + j])
				u_peso.append(inf_peso[i * 8 + j])
	u_ini.append(u_ranura.size())

	var cadera := _hueso_cadera(esq)
	var alto_cadera := esq.get_bone_global_rest(cadera).origin.y
	var t0 := Time.get_ticks_msec()
	for pl in plan:
		var anim: Animation = pl["clip"]["anim"]
		var escala: float = alto_cadera / maxf(pl["clip"]["alto_cadera"], 0.01)
		var n: int = pl["n"]
		var crudos: int = n if pl["entero"] else n + MEZCLA_BUCLE
		var tiempos := PackedFloat32Array()
		for i in crudos:
			if pl["entero"]:
				tiempos.append(float(i) / float(n) * anim.length)
			else:
				tiempos.append(minf(pl["desde"] + float(i) / FPS, anim.length))
		# La cadera se centra para que todas las animaciones queden en el
		# mismo lugar (algunas de Mixamo vienen corridas 30 cm).
		var centro := Vector3.ZERO
		var pista_cadera := _pista_posicion(anim, esq, cadera)
		if pista_cadera >= 0:
			for t in tiempos:
				centro += anim.position_track_interpolate(pista_cadera, t) * escala
			centro /= float(tiempos.size())
			centro.y = 0.0
		var poses: Array[PackedVector3Array] = []
		var normales: Array[PackedVector3Array] = []
		for t in tiempos:
			_posar(esq, anim, t, cadera, escala, centro)
			var ms := _matrices(esq, a_raiz, ranura_hueso, ranura_bind)
			var fila := PackedVector3Array()
			var fila_n := PackedVector3Array()
			fila.resize(columnas)
			fila_n.resize(columnas)
			for c in columnas:
				var p := Vector3.ZERO
				var nn := Vector3.ZERO
				var v := u_pos[c]
				var vn := u_nor[c]
				for k in range(u_ini[c], u_ini[c + 1]):
					var m: Transform3D = ms[u_ranura[k]]
					p += (m * v) * u_peso[k]
					nn += (m.basis * vn) * u_peso[k]
				fila[c] = p
				fila_n[c] = nn
			poses.append(fila)
			normales.append(fila_n)
		for i in n:
			var fila := poses[i]
			var fila_n := normales[i]
			if not pl["entero"] and i < MEZCLA_BUCLE:
				var w := float(i) / float(MEZCLA_BUCLE)
				var otra := poses[n + i]
				var otra_n := normales[n + i]
				var mez := PackedVector3Array()
				var mez_n := PackedVector3Array()
				mez.resize(columnas)
				mez_n.resize(columnas)
				for c in columnas:
					mez[c] = otra[c].lerp(fila[c], w)
					mez_n[c] = otra_n[c].lerp(fila_n[c], w)
				fila = mez
				fila_n = mez_n
			var o: int = (int(pl["inicio"]) + i) * columnas * 3
			for c in columnas:
				datos[o + c * 3] = fila[c].x
				datos[o + c * 3 + 1] = fila[c].y
				datos[o + c * 3 + 2] = fila[c].z
				var nn := fila_n[c].normalized() * 127.0 + Vector3(128.0, 128.0, 128.0)
				datos_n[o + c * 3] = int(nn.x)
				datos_n[o + c * 3 + 1] = int(nn.y)
				datos_n[o + c * 3 + 2] = int(nn.z)
		print("  anim %-16s %3d cuadros" % [pl["nombre"], n])
	print("  VAT %d x %d en %.1f s" % [columnas, filas, (Time.get_ticks_msec() - t0) / 1000.0])
	esq.reset_bone_poses()
	raiz.queue_free()

	var img_vat := Image.create_from_data(columnas, filas, false, Image.FORMAT_RGBF, datos.to_byte_array())
	img_vat.convert(Image.FORMAT_RGBH)
	var tex_vat := ImageTexture.create_from_image(img_vat)
	var tex_vat_n := ImageTexture.create_from_image(Image.create_from_data(columnas, filas, false, Image.FORMAT_RGB8, datos_n))

	# --- 6. Guardar
	var npc := HinchadaNpc.new()
	npc.nombre = nombre
	npc.lum_media = lum
	var base_ruta := DIR_SALIDA + nombre
	var nombres := ["cerca", "media"]
	for i in 2:
		ResourceSaver.save(mallas[i], "%s_%s.res" % [base_ruta, nombres[i]], ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(tex_vat, base_ruta + "_vat.res", ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(tex_vat_n, base_ruta + "_vat_normales.res", ResourceSaver.FLAG_COMPRESS)
	ResourceSaver.save(tex_albedo, base_ruta + "_albedo.res", ResourceSaver.FLAG_COMPRESS)
	npc.malla_cerca = load(base_ruta + "_cerca.res")
	npc.malla_media = load(base_ruta + "_media.res")
	npc.vat = load(base_ruta + "_vat.res")
	npc.vat_normales = load(base_ruta + "_vat_normales.res")
	npc.albedo = load(base_ruta + "_albedo.res")

	# --- 7. Fotos para los impostores
	var fotos: Array[Image] = await _sacar_fotos(npc, banco)
	if _vistas != "":
		fotos[0].save_png("%s/%s_fotos.png" % [_vistas, nombre])
		atlas.save_png("%s/%s_albedo.png" % [_vistas, nombre])
	return {"npc": npc, "fotos": fotos}

# ---------------------------------------------------------------- mallas

## Reduce una region a (mas o menos) `tris` triangulos. Devuelve indices sobre
## los mismos vertices originales.
func _simplificar(idx: PackedInt32Array, tris: int, rest: PackedVector3Array, rest_n: PackedVector3Array,
		uv: PackedVector2Array) -> PackedInt32Array:
	if idx.size() / 3 <= tris:
		return idx
	var mapa: Dictionary = {}
	var vuelta := PackedInt32Array()
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var local := PackedInt32Array()
	for i in idx:
		if not mapa.has(i):
			mapa[i] = vs.size()
			vuelta.append(i)
			vs.append(rest[i])
			ns.append(rest_n[i])
			uvs.append(uv[i])
		local.append(mapa[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = local
	var st := SurfaceTool.new()
	st.create_from_arrays(arr)
	var red := st.generate_lod(1.0, maxi(tris, 4) * 3)
	if red.size() < 3:
		return idx
	var out := PackedInt32Array()
	out.resize(red.size())
	for i in red.size():
		out[i] = vuelta[red[i]]
	return out

func _pintar_alfa(img: Image, p0: Vector2, p1: Vector2, p2: Vector2, a0: float, a1: float, a2: float) -> void:
	var den := (p1 - p0).cross(p2 - p0)
	if absf(den) < 0.000001:
		return
	var x0 := maxi(int(floor(minf(p0.x, minf(p1.x, p2.x)))) - 1, 0)
	var x1 := mini(int(ceil(maxf(p0.x, maxf(p1.x, p2.x)))) + 1, img.get_width() - 1)
	var y0 := maxi(int(floor(minf(p0.y, minf(p1.y, p2.y)))) - 1, 0)
	var y1 := mini(int(ceil(maxf(p0.y, maxf(p1.y, p2.y)))) + 1, img.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0 := (p1 - p).cross(p2 - p) / den
			var w1 := (p2 - p).cross(p0 - p) / den
			var w2 := 1.0 - w0 - w1
			if w0 < -0.15 or w1 < -0.15 or w2 < -0.15:
				continue
			var c := img.get_pixel(x, y)
			c.a = 1.0 - clampf(w0 * a0 + w1 * a1 + w2 * a2, 0.0, 1.0)
			img.set_pixel(x, y, c)

func _armar_malla(nivel: PackedInt32Array, rest: PackedVector3Array, rest_n: PackedVector3Array,
		uv: PackedVector2Array, parte: PackedInt32Array, columna: PackedInt32Array) -> ArrayMesh:
	var mapa: Dictionary = {}
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in nivel:
		if not mapa.has(i):
			mapa[i] = vs.size()
			vs.append(rest[i])
			ns.append(rest_n[i])
			uvs.append(uv[i])
			# UV2.x = columna del VAT, UV2.y = parte del cuerpo
			uv2.append(Vector2(columna[i], parte[i]))
		idx.append(mapa[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Caja amplia: el shader mueve los vertices (brazos arriba, saltos).
	m.custom_aabb = AABB(Vector3(-0.9, -0.1, -0.8), Vector3(1.8, 2.7, 1.6))
	return m

## El pelo de Mixamo son cientos de planos transparentes que no sobreviven a la
## simplificacion. En su lugar se marca como pelo la parte de arriba y de atras
## de la cabeza: devuelve, por vertice, cuanto pelo tiene (0 a 1). Despues se
## pinta en el canal alfa de la textura, asi el borde del pelo sale prolijo
## aunque la malla tenga pocos triangulos.
func _medir_pelo(esq: Skeleton3D, a_raiz: Transform3D, rest: PackedVector3Array, parte: PackedInt32Array,
		inf_ranura: PackedInt32Array, inf_peso: PackedFloat32Array, ranura_hueso: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(rest.size())
	var cabeza := -1
	var tope := -1
	for b in esq.get_bone_count():
		var n := esq.get_bone_name(b).to_lower()
		if n.ends_with("headtop_end"):
			tope = b
		elif n.ends_with("head"):
			cabeza = b
	if cabeza < 0:
		return out
	var de_cabeza := PackedInt32Array()
	var y_max := -INF
	var z_min := INF
	var z_max := -INF
	for i in rest.size():
		if parte[i] != Parte.PIEL:
			continue
		var w_cabeza := 0.0
		for j in 8:
			var h := ranura_hueso[inf_ranura[i * 8 + j]]
			if h == cabeza or h == tope:
				w_cabeza += inf_peso[i * 8 + j]
		if w_cabeza > 0.5:
			de_cabeza.append(i)
			y_max = maxf(y_max, rest[i].y)
			z_min = minf(z_min, rest[i].z)
			z_max = maxf(z_max, rest[i].z)
	if de_cabeza.is_empty():
		return out
	var y_base: float = (a_raiz * esq.get_bone_global_rest(cabeza)).origin.y
	var alto := maxf(y_max - y_base, 0.05)
	var fondo := maxf(z_max - z_min, 0.05)
	for i in de_cabeza:
		var h := (rest[i].y - y_base) / alto            # 0 = base del craneo, 1 = coronilla
		var adelante := (rest[i].z - z_min) / fondo     # 0 = nuca, 1 = nariz
		# Linea del pelo: alta en la frente, baja hacia la nuca.
		var linea := clampf(lerpf(0.30, 0.86, smoothstep(0.25, 0.80, adelante)), 0.30, 0.86)
		out[i] = smoothstep(linea - 0.035, linea + 0.035, h)
	return out

# ---------------------------------------------------------------- animacion

func _clip(archivo: String) -> Dictionary:
	if _clips.has(archivo):
		return _clips[archivo]
	var esc: PackedScene = load(DIR_ANIM + archivo)
	if esc == null:
		push_error("Falta la animacion %s" % (DIR_ANIM + archivo))
		return {}
	var n := esc.instantiate()
	var ap: AnimationPlayer = n.find_child("*", true, false) if false else _buscar_tipo(n, "AnimationPlayer")
	var esq := _buscar_esqueleto(n)
	var elegido := ""
	for nom in ap.get_animation_list():
		if nom == "mixamo_com" or elegido == "" or (elegido == "Take 001"):
			if nom != "RESET":
				elegido = nom
		if nom == "mixamo_com":
			break
	var out := {
		"anim": ap.get_animation(elegido),
		"alto_cadera": esq.get_bone_global_rest(_hueso_cadera(esq)).origin.y,
	}
	n.free()
	_clips[archivo] = out
	return out

func _posar(esq: Skeleton3D, anim: Animation, t: float, cadera: int, escala: float, centro: Vector3) -> void:
	esq.reset_bone_poses()
	for p in anim.get_track_count():
		var tipo := anim.track_get_type(p)
		if tipo != Animation.TYPE_ROTATION_3D and tipo != Animation.TYPE_POSITION_3D:
			continue
		var ruta := anim.track_get_path(p)
		if ruta.get_subname_count() == 0:
			continue
		var b := esq.find_bone(ruta.get_subname(0))
		if b < 0:
			continue
		if tipo == Animation.TYPE_ROTATION_3D:
			esq.set_bone_pose_rotation(b, anim.rotation_track_interpolate(p, t))
		elif b == cadera:
			# Solo la cadera se traslada; el resto de los huesos conserva las
			# medidas del NPC (asi una animacion sirve para cualquier cuerpo).
			esq.set_bone_pose_position(b, anim.position_track_interpolate(p, t) * escala - centro)

func _pista_posicion(anim: Animation, esq: Skeleton3D, hueso: int) -> int:
	for p in anim.get_track_count():
		if anim.track_get_type(p) == Animation.TYPE_POSITION_3D:
			var ruta := anim.track_get_path(p)
			if ruta.get_subname_count() > 0 and esq.find_bone(ruta.get_subname(0)) == hueso:
				return p
	return -1

func _matrices(esq: Skeleton3D, a_raiz: Transform3D, ranura_hueso: PackedInt32Array, ranura_bind: Array[Transform3D]) -> Array:
	var globales: Array[Transform3D] = []
	for b in esq.get_bone_count():
		globales.append(a_raiz * esq.get_bone_global_pose(b))
	var out: Array = []
	out.resize(ranura_hueso.size())
	for r in ranura_hueso.size():
		out[r] = globales[ranura_hueso[r]] * ranura_bind[r]
	return out

func _hueso_cadera(esq: Skeleton3D) -> int:
	for b in esq.get_bone_count():
		if esq.get_bone_name(b).to_lower().ends_with("hips"):
			return b
	for b in esq.get_bone_count():
		if esq.get_bone_parent(b) < 0:
			return b
	return 0

# ---------------------------------------------------------------- partes

func _clasificar(nombre: String, manual: Dictionary) -> int:
	if manual.has(nombre):
		match String(manual[nombre]).to_lower():
			"remera": return Parte.REMERA
			"pantalon": return Parte.PANTALON
			"piel": return Parte.PIEL
			"pelo": return Parte.PELO
			"otro": return Parte.OTRO
			"omitir": return Parte.OMITIR
			_: return Parte.AUTO
	var n := nombre.to_lower()
	for regla in PALABRAS:
		for palabra: String in regla[1]:
			if n.contains(palabra):
				return regla[0]
	return Parte.AUTO

func _parte_por_hueso(hueso: String) -> int:
	var h := hueso.to_lower()
	if h.contains("forearm") or h.contains("hand") or h.contains("head") or h.contains("neck"):
		return Parte.PIEL
	if h.contains("spine") or h.contains("shoulder") or h.contains("arm"):
		return Parte.REMERA
	if h.contains("upleg") or h.contains("hips"):
		return Parte.PANTALON
	if h.contains("foot") or h.contains("toe"):
		return Parte.OTRO
	return Parte.PIEL

func _nombre_parte(p: int) -> String:
	match p:
		Parte.REMERA: return "remera"
		Parte.PANTALON: return "pantalon"
		Parte.PIEL: return "piel"
		Parte.PELO: return "pelo"
		Parte.OTRO: return "otro"
	return "segun el hueso"

## Opcional: un archivo <personaje>.json al lado del FBX con
## {"partes": {"NombreDeMalla": "remera" | "pantalon" | "piel" | "otro" | "omitir"}}
func _leer_partes_manuales(ruta: String) -> Dictionary:
	var rj := ruta.get_basename() + ".json"
	if not FileAccess.file_exists(rj):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(rj))
	if d is Dictionary and d.has("partes"):
		return d["partes"]
	return {}

func _indice_textura(mat: Material, texturas: Array[Image], claves: Dictionary) -> int:
	var clave: Variant = "blanco"
	var img: Image = null
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.albedo_texture:
			clave = bm.albedo_texture
		else:
			clave = bm.albedo_color
	if claves.has(clave):
		return claves[clave]
	if clave is Texture2D:
		img = (clave as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	else:
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(clave if clave is Color else Color.WHITE)
	claves[clave] = texturas.size()
	texturas.append(img)
	return texturas.size() - 1

func _buscar_esqueleto(n: Node) -> Skeleton3D:
	return _buscar_tipo(n, "Skeleton3D") as Skeleton3D

func _buscar_tipo(n: Node, tipo: String) -> Node:
	if n.is_class(tipo):
		return n
	for c in n.get_children():
		var r := _buscar_tipo(c, tipo)
		if r:
			return r
	return null

# ---------------------------------------------------------------- impostores

## Dibuja al NPC en una grilla (una fila por animacion, una columna por cuadro)
## y devuelve tres imagenes: color, mascara de partes y coordenadas.
func _sacar_fotos(npc: HinchadaNpc, banco: HinchadaBanco) -> Array[Image]:
	var n_anims := banco.anim_nombres.size()
	var vp := SubViewport.new()
	vp.size = Vector2i(CUADROS_IMP * CELDA_PX.x, n_anims * CELDA_PX.y)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = n_anims * CELDA_MUNDO.y
	cam.near = 0.1
	cam.far = 40.0
	cam.position = Vector3(0, 0, 15)
	vp.add_child(cam)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://resources/shaders/hinchada_horneado.gdshader")
	mat.set_shader_parameter("vat", npc.vat)
	mat.set_shader_parameter("albedo", npc.albedo)
	mat.set_shader_parameter("lum_media", npc.lum_media)
	mat.set_shader_parameter("anim_inicio", _rellenar(banco.anim_inicio))
	mat.set_shader_parameter("anim_cuadros", _rellenar(banco.anim_cuadros))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = npc.malla_cerca
	mm.instance_count = n_anims * CUADROS_IMP
	for a in n_anims:
		for k in CUADROS_IMP:
			var i := a * CUADROS_IMP + k
			var x := (float(k) + 0.5 - CUADROS_IMP * 0.5) * CELDA_MUNDO.x
			var y := (n_anims * 0.5 - float(a) - 1.0) * CELDA_MUNDO.y + 0.05
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, 0)))
			var cuadro := float(k) * float(banco.anim_cuadros[a]) / float(CUADROS_IMP)
			mm.set_instance_custom_data(i, Color(float(a), cuadro, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-100, -100, -5), Vector3(200, 200, 10))
	vp.add_child(mmi)

	var out: Array[Image] = []
	for modo in 3:
		mat.set_shader_parameter("modo", modo)
		for i in 4:
			await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if modo > 0:
			img.srgb_to_linear() # son datos, no colores
		out.append(img)
	vp.queue_free()
	return out

func _guardar_atlas(banco: HinchadaBanco, bloques: Array) -> void:
	var ancho_bloque := CUADROS_IMP * CELDA_PX.x
	var alto_bloque := banco.anim_nombres.size() * CELDA_PX.y
	var columnas := mini(bloques.size(), NPC_POR_FILA)
	var filas := int(ceil(float(bloques.size()) / float(NPC_POR_FILA)))
	var nombres := ["imp_albedo", "imp_mascara", "imp_coords"]
	var imgs: Array[Image] = []
	for t in 3:
		var img := Image.create(ancho_bloque * columnas, alto_bloque * filas, false, Image.FORMAT_RGBA8)
		for b in bloques.size():
			img.blit_rect(bloques[b][t], Rect2i(0, 0, ancho_bloque, alto_bloque),
					Vector2i((b % NPC_POR_FILA) * ancho_bloque, (b / NPC_POR_FILA) * alto_bloque))
		imgs.append(img)
	# Las dos de datos usan el recorte (alfa) de la de color, y a las tres se
	# les estira el color hacia afuera del borde para que al achicarlas no
	# aparezca un halo negro alrededor de cada persona.
	var alfa := imgs[0].get_data()
	for t in 3:
		var img := imgs[t]
		if t > 0:
			var datos := img.get_data()
			for i in range(3, datos.size(), 4):
				datos[i] = alfa[i]
			img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, datos)
		img.fix_alpha_edges()
		if t > 0:
			# Son datos suaves: con la mitad de resolucion alcanza.
			img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
		img.generate_mipmaps()
		if _vistas != "":
			img.save_png("%s/%s.png" % [_vistas, nombres[t]])
		ResourceSaver.save(ImageTexture.create_from_image(img), DIR_SALIDA + nombres[t] + ".res", ResourceSaver.FLAG_COMPRESS)
	banco.imp_albedo = load(DIR_SALIDA + "imp_albedo.res")
	banco.imp_mascara = load(DIR_SALIDA + "imp_mascara.res")
	banco.imp_coords = load(DIR_SALIDA + "imp_coords.res")

func _rellenar(a: PackedInt32Array) -> PackedInt32Array:
	var out := a.duplicate()
	out.resize(16)
	return out
