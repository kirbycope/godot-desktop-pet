extends SceneTree
## Prints an imported model's node tree, size, materials and animations: tools/inspect_model.gd <res path>
func _init() -> void:
	var path: String = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "res://assets/duck/rubber_duck.fbx"
	var root: Node = (load(path) as PackedScene).instantiate()
	_walk(root, 0)
	var aabb: AABB = AABB()
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb() if mesh.is_inside_tree() else mesh.transform * mesh.get_aabb()
		aabb = box if aabb.size == Vector3.ZERO else aabb.merge(box)
	print("AABB: ", aabb)
	for player: AnimationPlayer in root.find_children("*", "AnimationPlayer", true, false):
		print("animations: ", player.get_animation_list())
	root.free()
	quit()

func _walk(node: Node, depth: int) -> void:
	var extra: String = ""
	if node is Node3D:
		extra = " pos=%s rot=%s scale=%s" % [node.position, node.rotation_degrees, node.scale]
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		extra += " surfaces=%d aabb=%s" % [mesh.get_surface_count(), mesh.get_aabb()]
		for i: int in mesh.get_surface_count():
			var mat: Material = node.get_active_material(i)
			extra += "\n%s  surface %d: %s %s" % ["  ".repeat(depth), i, mat.resource_name if mat else "none", (mat as StandardMaterial3D).albedo_color if mat is StandardMaterial3D else ""]
	print("  ".repeat(depth), node.name, " (", node.get_class(), ")", extra)
	for child: Node in node.get_children():
		_walk(child, depth + 1)
