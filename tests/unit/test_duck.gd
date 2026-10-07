extends GutTest


func test_every_animation_poses_from_the_base() -> void:
	for anim: StringName in Duck.ANIMATIONS:
		var pose: Array = Duck.pose(anim, 0.37)
		assert_eq(pose.size(), 3, String(anim))
		assert_true((pose[0] as Vector3).distance_to(Duck.BASE) < 0.1, "%s stays near the base point" % anim)


func test_unknown_animation_stands_still() -> void:
	assert_eq(Duck.pose(&"nonsense", 1.0), [Duck.BASE, Vector3.ZERO, Vector3.ONE])


func test_landing_squashes_then_recovers() -> void:
	var squashed: Vector3 = Duck.pose(&"land", 0.0)[2]
	assert_lt(squashed.y, 1.0)
	assert_gt(squashed.x, 1.0)
	assert_eq(Duck.pose(&"land", 1.0)[2], Vector3.ONE)


func test_facing_turns_toward_the_camera_either_way() -> void:
	assert_eq(Duck.yaw_for(1, 30.0), -30.0, "the model faces +X; turning -30 brings its face round to the camera")
	assert_eq(Duck.yaw_for(-1, 30.0), 210.0)


func test_duck_scene_uses_the_supplied_model() -> void:
	var duck: Duck = (load("res://scenes/duck.tscn") as PackedScene).instantiate()
	add_child_autofree(duck)
	assert_not_null(duck.get_node("Pivot/Body/Yaw/Model"))
	assert_gt(duck.find_children("*", "MeshInstance3D", true, false).size(), 0)
	duck.roll = 90.0
	assert_almost_eq(duck.pivot.rotation_degrees.z, 90.0, 0.01)
	duck.facing = -1
	assert_almost_eq(duck.yaw.rotation_degrees.y, 210.0, 0.01)
