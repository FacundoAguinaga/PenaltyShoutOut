@tool
extends EditorScript

# Script de utilidad para pre-calcular el "canonical_target" de cada animación de atajada.
# Para correrlo, abre este script en el editor y haz click en File -> Run (o Ctrl+Shift+X).

func _run() -> void:
	print("--- Iniciando Bakeo de Animaciones ---")
	
	# Ajusta estas rutas a donde tengas las cosas en tu proyecto
	var scene_path := "res://scenes/goalkeeper_bake_scene.tscn" # Necesitas una escena temporal o usar la actual
	
	# NOTA: Para que esto funcione necesitas abrir una escena donde esté tu arquero instanciado
	var root = get_scene()
	if not root:
		print("ERROR: Debes tener abierta una escena con el arquero para correr el script.")
		return
		
	var anim_player = _find_node_by_type(root, AnimationPlayer) as AnimationPlayer
	var skeleton = _find_node_by_type(root, Skeleton3D) as Skeleton3D
	var keeper_root = _find_node_by_type(root, CharacterBody3D) as Node3D
	if not keeper_root:
		keeper_root = skeleton.get_parent() as Node3D
		
	if not anim_player or not skeleton:
		print("ERROR: No se encontró AnimationPlayer o Skeleton3D en la escena.")
		return

	# Busca todos los recursos DiveAnimData en la carpeta especificada
	var dir_path := "res://resources/animresources"
	var dir = DirAccess.open(dir_path)
	if not dir:
		print("ERROR: No se encontró la carpeta ", dir_path, ". Créala y pon tus recursos ahí.")
		return
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var anim_data := ResourceLoader.load(dir_path + "/" + file_name) as DiveAnimData
			if anim_data and anim_player.has_animation(anim_data.anim_name):
				_bake_anim(anim_data, anim_player, skeleton, keeper_root)
		file_name = dir.get_next()

	print("--- Finalizado Bakeo de Animaciones ---")

func _bake_anim(anim_data: DiveAnimData, player: AnimationPlayer, skeleton: Skeleton3D, root: Node3D):
	player.play(anim_data.anim_name)
	player.seek(anim_data.contact_time, true)

	var bone_idx := skeleton.find_bone(anim_data.hand_bone)
	if bone_idx == -1:
		print("WARN: Hueso no encontrado en ", anim_data.anim_name)
		return
		
	var bone_global_pose := skeleton.get_bone_global_pose(bone_idx)
	var world_pos := skeleton.global_transform * bone_global_pose.origin

	anim_data.canonical_target = root.global_transform.affine_inverse() * world_pos

	ResourceSaver.save(anim_data, anim_data.resource_path)
	print("Bakeado: ", anim_data.anim_name, " -> target en ", anim_data.canonical_target)

func _find_node_by_type(node: Node, type):
	if is_instance_of(node, type):
		return node
	for child in node.get_children():
		var found = _find_node_by_type(child, type)
		if found:
			return found
	return null
