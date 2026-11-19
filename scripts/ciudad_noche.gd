extends Node3D

## La ciudad del mapa es un modelo diurno: de noche se veia apagada. Este
## script le agrega emision a las texturas de las fachadas para que las
## ventanas y las calles se lean como una ciudad iluminada, sin tener que
## colocar cientos de luces. Solo se usa en la toma de ciudad de la intro;
## despues la ciudad se oculta.

@export_range(0.0, 1.5) var energia_emision: float = 0.5

var _cache_materiales: Dictionary = {}


func _ready() -> void:
	_iluminar(self)


func _iluminar(nodo: Node) -> void:
	if nodo is MeshInstance3D and (nodo as MeshInstance3D).mesh:
		var malla := nodo as MeshInstance3D
		for superficie in malla.mesh.get_surface_count():
			var material := malla.get_active_material(superficie)
			if not material is StandardMaterial3D:
				continue
			var base := material as StandardMaterial3D
			if base.albedo_texture == null:
				continue
			var clave := base.get_instance_id()
			if not _cache_materiales.has(clave):
				var emisivo := base.duplicate() as StandardMaterial3D
				emisivo.emission_enabled = true
				emisivo.emission_texture = base.albedo_texture
				emisivo.emission_energy_multiplier = energia_emision
				emisivo.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
				_cache_materiales[clave] = emisivo
			malla.set_surface_override_material(superficie, _cache_materiales[clave])
	for hijo in nodo.get_children():
		_iluminar(hijo)
