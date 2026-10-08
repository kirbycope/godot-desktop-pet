extends SceneTree
## Renders the duck facing the viewer into assets/icons/duck_icon.png, the app's icon on the phone and
## the window's on the PC. Needs a window, so not --headless.
##
##   godot --path . -s res://tools/make_icon.gd

const SIZE: int = 192
const OUT: String = "res://assets/icons/duck_icon.png"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var duck: Duck = load("res://scenes/duck.tscn").instantiate()
	viewport.add_child(duck)
	duck.looking_at_viewer = true
	# The scene stands the duck on the bottom edge, for walking along it; an icon wants it centred,
	# with a little room around.
	var camera: Camera3D = duck.get_node("Camera")
	camera.size *= 1.2
	camera.position.y -= camera.size * 0.14
	duck.play(&"idle")
	# Let it turn to face the viewer and settle.
	for i: int in 90:
		await process_frame
	var image: Image = viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("saved ", ProjectSettings.globalize_path(OUT), " ", image.get_size())
	quit()
