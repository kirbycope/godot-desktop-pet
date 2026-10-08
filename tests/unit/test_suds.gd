extends GutTest
## The bubble bath's foam: where the suds go.


func test_the_pile_hugs_the_duck_without_going_inside_it() -> void:
	var placed: Array[Transform3D] = Suds.layout(7, -0.13, Vector2(0.125, 0.15), 0.07, 200, 0, Vector2i(1, 1), Rect2(-1, -2.8, 2, 2.9), Vector2(0.004, 0.017))
	assert_eq(placed.size(), 200)
	for at: Transform3D in placed:
		var p: Vector3 = at.origin
		var reach: float = Vector2(p.x / 0.125, p.z / 0.15).length()
		assert_gte(reach, 1.0, "outside the duck's footprint")
		assert_lte(Vector2(p.x, p.z).length(), 0.15 + 0.07 + 0.02, "and close to it")
		assert_almost_eq(p.y, -0.13, 0.03, "at the water")


func test_clumps_float_in_the_bath_and_the_same_seed_gives_the_same_bath() -> void:
	var a: Array[Transform3D] = Suds.layout(7, -0.13, Vector2(0.125, 0.15), 0.07, 0, 5, Vector2i(10, 20), Rect2(-1, -2.8, 2, 2.9), Vector2(0.004, 0.017))
	var b: Array[Transform3D] = Suds.layout(7, -0.13, Vector2(0.125, 0.15), 0.07, 0, 5, Vector2i(10, 20), Rect2(-1, -2.8, 2, 2.9), Vector2(0.004, 0.017))
	assert_between(a.size(), 50, 100)
	assert_eq(a, b, "placed once from the seed, so the bath looks the same each time")


func test_the_phone_scene_has_its_suds() -> void:
	var app: Node = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	var suds: Suds = app.get_node("Layout/DuckView/Viewport/Suds")
	assert_not_null(suds.sud_mesh)
	assert_not_null(suds.material_override)
	app.free()
