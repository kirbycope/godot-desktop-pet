extends SceneTree
## Renders a model from the front (+Z), right (+X), back and left, side by side, to see which way it
## faces: godot --path . -s tools/model_shot.gd -- <res path> <out png>

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://assets/duck/rubber_duck.fbx"
	var out: String = args[1] if args.size() > 1 else "res://screenshots/model_shot.png"
	var shots: Array[Image] = []
	for angle: float in [0.0, 90.0, 180.0, 270.0]:
		var viewport: SubViewport = SubViewport.new()
		viewport.size = Vector2i(256, 256)
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var model: Node3D = (load(path) as PackedScene).instantiate()
		viewport.add_child(model)
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, 30, 0)
		viewport.add_child(light)
		var camera: Camera3D = Camera3D.new()
		camera.fov = 30.0
		var direction: Vector3 = Vector3(sin(deg_to_rad(angle)), 0.25, cos(deg_to_rad(angle))).normalized()
		camera.position = Vector3(0, 0.11, 0) + direction * 0.7
		viewport.add_child(camera)
		camera.look_at(Vector3(0, 0.11, 0))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		shots.append(viewport.get_texture().get_image())
	var strip: Image = Image.create_empty(256 * 4, 256, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.35, 0.42, 0.55))
	for i: int in shots.size():
		shots[i].convert(Image.FORMAT_RGBA8)
		strip.blend_rect(shots[i], Rect2i(0, 0, 256, 256), Vector2i(256 * i, 0))
	strip.save_png(out)
	print("saved ", ProjectSettings.globalize_path(out), " (front +Z, right +X, back, left)")
	quit()
