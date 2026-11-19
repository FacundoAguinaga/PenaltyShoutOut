extends SceneTree

## Guarda el estadio optimizado en pedazos que entran en git.
##
## stadium_optimizado.scn (lo arma tools/optimizar_estadio.gd) pesa 390 MB, y comprimido
## 132 MB: no entra en GitHub, que no acepta archivos de mas de 100 MB, y por eso esta en
## .gitignore. Sin el, un clon del repositorio no tiene ni estadio ni cancha (el pasto se
## ve negro). Esta herramienta guarda cada malla y cada material en su propio archivo
## comprimido en DESTINO, y la escena que los junta en ESCENA. Asi cada archivo pesa unos
## pocos MB y stadium.tscn usa ESCENA.
##
## Uso (tarda unos segundos):
##   godot --headless --path . -s res://tools/partir_estadio.gd
##
## Si se vuelve a correr optimizar_estadio.gd, hay que correr esta despues.

const ENTRADA := "res://assets/models/stadium_optimizado.scn"
const DESTINO := "res://assets/models/estadio/"
const ESCENA := DESTINO + "estadio.scn"
## Ningun archivo puede pasar los 100 MB de GitHub; se avisa bastante antes.
const MAXIMO_MB := 50.0

func _initialize() -> void:
	var raiz: Node3D = (load(ENTRADA) as PackedScene).instantiate()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINO))
	_borrar_viejos()
	var materiales := {}
	var mallas := 0
	for mi: MeshInstance3D in raiz.find_children("*", "MeshInstance3D", true, false):
		var malla: Mesh = mi.mesh
		if malla == null:
			continue
		for s in malla.get_surface_count():
			var mat := malla.surface_get_material(s)
			if mat != null and not materiales.has(mat) and _incrustado(mat):
				materiales[mat] = DESTINO + "material_%02d.res" % materiales.size()
				_guardar(mat, materiales[mat])
		_guardar(malla, DESTINO + "%s.res" % mi.name)
		mallas += 1
	var escena := PackedScene.new()
	var err := escena.pack(raiz)
	if err == OK:
		err = ResourceSaver.save(escena, ESCENA, ResourceSaver.FLAG_COMPRESS)
	raiz.free()
	print("estadio: %d mallas y %d materiales en %s, escena %s (%s)" % [mallas, materiales.size(), DESTINO, ESCENA, error_string(err)])
	_revisar_tamanos()
	quit(0 if err == OK else 1)

## Guarda un recurso comprimido y lo deja apuntando a su archivo, para que la escena (y
## las mallas, en el caso de los materiales) lo referencien en vez de copiarlo adentro.
func _guardar(r: Resource, ruta: String) -> void:
	var err := ResourceSaver.save(r, ruta, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_error("no se pudo guardar %s: %s" % [ruta, error_string(err)])
	r.take_over_path(ruta)

## Un recurso que no tiene archivo propio: va adentro del que lo usa.
func _incrustado(r: Resource) -> bool:
	return r.resource_path == "" or r.resource_path.contains("::")

func _borrar_viejos() -> void:
	var dir := DirAccess.open(DESTINO)
	for f in dir.get_files():
		if f.ends_with(".res") or f.ends_with(".scn"):
			dir.remove(f)

func _revisar_tamanos() -> void:
	var dir := DirAccess.open(DESTINO)
	var total := 0
	var mayor := 0
	for f in dir.get_files():
		var largo := FileAccess.get_file_as_bytes(DESTINO + f).size()
		total += largo
		mayor = maxi(mayor, largo)
	print("total %.1f MB, el mas grande %.1f MB" % [total / 1e6, mayor / 1e6])
	if mayor / 1e6 > MAXIMO_MB:
		push_error("hay un archivo de mas de %d MB: no conviene subirlo a git" % MAXIMO_MB)
