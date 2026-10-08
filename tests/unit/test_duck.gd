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
	assert_almost_eq(Duck.pose(&"land", 1.0)[2], Vector3.ONE, Vector3(0.01, 0.01, 0.01), "settled a second later")


func test_every_pose_keeps_the_ducks_volume() -> void:
	for anim: StringName in Duck.ANIMATIONS:
		for t: float in [0.0, 0.05, 0.13, 0.31, 0.6, 1.7]:
			var size: Vector3 = Duck.pose(anim, t)[2]
			assert_almost_eq(size.x * size.y * size.z, 1.0, 0.001, "%s at %.2f s" % [anim, t])


func test_the_waddle_squashes_on_each_step_and_stretches_between() -> void:
	assert_lt(Duck.pose(&"walk", 0.0)[2].y, 1.0, "foot down")
	assert_gt(Duck.pose(&"walk", PI / 20.0)[2].y, 1.0, "top of the step")


func test_a_hop_crouches_leaps_stretched_and_lands_squashed() -> void:
	assert_lt(Duck.hop_at(0.14)[1], -0.1, "gathers itself first")
	var takeoff: Array = Duck.hop_at(0.16)
	assert_gt(takeoff[1], 0.1, "stretched as it leaves the ground")
	assert_gt(Duck.hop_at(0.32)[0], 0.04, "high in the air")
	assert_lt(Duck.hop_at(0.51)[1], -0.15, "squashed as it lands")
	assert_almost_eq(Duck.hop_at(0.89)[1], 0.0, 0.03, "settled before the next hop")


func test_falling_stretches_and_dangling_stretches() -> void:
	assert_gt(Duck.pose(&"fall", 0.5)[2].y, 1.15)
	assert_gt(Duck.pose(&"hang", 0.0)[2].y, 1.05)


func test_a_squeeze_flattens_then_springs_back_past_round() -> void:
	assert_lt(Duck.pose(&"squeeze", 0.0)[2].y, 0.75, "squeezed hard")
	var overshoot: float = -INF
	for i: int in 20:
		overshoot = maxf(overshoot, Duck.pose(&"squeeze", i * 0.01)[2].y)
	assert_gt(overshoot, 1.05, "springs back taller than round")
	assert_almost_eq(Duck.pose(&"squeeze", 1.0)[2].y, 1.0, 0.01)


func test_squash_keeps_volume_and_never_flattens_to_nothing() -> void:
	assert_eq(Duck.squash(0.0), Vector3.ONE)
	assert_almost_eq(Duck.squash(-5.0).y, 0.2, 0.0001)


func test_a_click_squeezes_the_duck() -> void:
	assert_string_contains((load("res://scripts/pet.gd") as GDScript).source_code, 'duck.play(&"squeeze")')


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
	assert_eq(duck.target_yaw(), 210.0)


func test_it_turns_to_face_you_while_talking_and_back_after() -> void:
	var duck: Duck = (load("res://scenes/duck.tscn") as PackedScene).instantiate()
	add_child_autofree(duck)
	duck.facing = 1
	duck.looking_at_viewer = true
	assert_eq(duck.target_yaw(), Duck.VIEWER_YAW)
	for i: int in 60:
		duck._process(1.0 / 60.0)
	assert_almost_eq(duck.yaw.rotation_degrees.y, -90.0, 1.0, "facing the camera within a second")
	duck.looking_at_viewer = false
	for i: int in 60:
		duck._process(1.0 / 60.0)
	assert_almost_eq(duck.yaw.rotation_degrees.y, -30.0, 1.0, "back to walking right, three-quarters on")


func test_it_eases_round_rather_than_snapping() -> void:
	var duck: Duck = (load("res://scenes/duck.tscn") as PackedScene).instantiate()
	add_child_autofree(duck)
	duck.looking_at_viewer = true
	duck._process(1.0 / 60.0)
	var after_one_frame: float = duck.yaw.rotation_degrees.y
	assert_gt(after_one_frame, -90.0, "not there in one frame")
	assert_lt(after_one_frame, -30.0, "but on its way")


func test_perking_up_stretches_then_settles_and_keeps_volume() -> void:
	assert_eq(Duck.perk(0.0), 0.0, "starts round")
	assert_gt(Duck.perk(0.1), 0.05, "stands tall")
	assert_lt(Duck.perk(0.3), 0.0, "dips past round")
	assert_almost_eq(Duck.perk(1.0), 0.0, 0.01, "settled")
	var size: Vector3 = Duck.squash(0.1) * Duck.squash(Duck.perk(0.1))
	assert_almost_eq(size.x * size.y * size.z, 1.0, 0.001)



func test_sleeping_breathes_and_waking_stretches_then_settles() -> void:
	var low: float = INF
	var high: float = -INF
	for i: int in 40:
		var y: float = Duck.pose(&"sleep", i * 0.1)[2].y
		low = minf(low, y)
		high = maxf(high, y)
	assert_lt(low, 0.95, "breathes out, settled low")
	assert_gt(high - low, 0.04, "breathes deeply")
	assert_almost_eq(Duck.pose(&"wake", 0.0)[2].y, 1.0, 0.01, "starts from where sleep left off, near round")
	assert_gt(Duck.pose(&"wake", 0.45)[2].y, 1.2, "a big stretch")
	assert_almost_eq(Duck.pose(&"wake", 1.5)[2].y, 1.0, 0.02, "settled")


func test_the_zs_rise_and_fade_one_after_another() -> void:
	var start: Array = Duck.z_at(0.0, 0)
	var later: Array = Duck.z_at(1.0, 0)
	assert_gt(later[0].y, start[0].y, "rising")
	assert_almost_eq(start[1], 0.0, 0.01, "fades in from nothing")
	assert_gt(Duck.z_at(0.0, 1)[1], 0.5, "the next is already showing")


func test_the_duck_scene_has_three_zs_hidden_until_it_sleeps() -> void:
	var duck: Duck = (load("res://scenes/duck.tscn") as PackedScene).instantiate()
	add_child_autofree(duck)
	for z: Label3D in duck.zzz:
		assert_false(z.visible)
	duck.play(&"sleep")
	duck._process(0.1)
	for z: Label3D in duck.zzz:
		assert_true(z.visible)
