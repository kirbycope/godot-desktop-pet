extends GutTest

const AREA: Rect2 = Rect2(0, 0, 1000, 600)
const SIZE: Vector2 = Vector2(128, 128)


func test_walks_along_the_bottom_and_stays_on_it() -> void:
	var moved: Array = Pet.walk(Pet.Edge.BOTTOM, 1, Vector2(100, 300), AREA, SIZE, 10.0)
	assert_eq(moved[0], Vector2(110, 472), "snapped to the bottom, moved right")
	assert_false(moved[1], "no corner yet")


func test_stops_at_the_right_hand_corner() -> void:
	var moved: Array = Pet.walk(Pet.Edge.BOTTOM, 1, Vector2(868, 472), AREA, SIZE, 10.0)
	assert_eq(moved[0], Vector2(872, 472))
	assert_true(moved[1])


func test_climbs_the_sides_and_hangs_from_the_top() -> void:
	var up: Array = Pet.walk(Pet.Edge.RIGHT, -1, Vector2(872, 472), AREA, SIZE, 10.0)
	assert_eq(up[0], Vector2(872, 462), "climbing the right side moves up")
	var across: Array = Pet.walk(Pet.Edge.TOP, -1, Vector2(500, 50), AREA, SIZE, 10.0)
	assert_eq(across[0], Vector2(490, 0), "hanging from the top snaps to it")


func test_goes_round_every_corner_onto_the_next_edge() -> void:
	assert_eq(Pet.around_corner(Pet.Edge.BOTTOM, 1), [Pet.Edge.RIGHT, -1])
	assert_eq(Pet.around_corner(Pet.Edge.BOTTOM, -1), [Pet.Edge.LEFT, -1])
	assert_eq(Pet.around_corner(Pet.Edge.RIGHT, -1), [Pet.Edge.TOP, -1])
	assert_eq(Pet.around_corner(Pet.Edge.TOP, -1), [Pet.Edge.LEFT, 1])
	assert_eq(Pet.around_corner(Pet.Edge.LEFT, 1), [Pet.Edge.BOTTOM, 1])


func test_a_full_lap_returns_to_the_bottom() -> void:
	var edge: Pet.Edge = Pet.Edge.BOTTOM
	var direction: int = 1
	var at: Vector2 = Vector2(500, 472)
	var corners: int = 0
	for step: int in 1000:
		var moved: Array = Pet.walk(edge, direction, at, AREA, SIZE, 20.0)
		at = moved[0]
		if moved[1]:
			corners += 1
			var turned: Array = Pet.around_corner(edge, direction)
			edge = turned[0]
			direction = turned[1]
			if corners == 4:
				break
	assert_eq(corners, 4)
	assert_eq(edge, Pet.Edge.BOTTOM)
	assert_eq(at, Vector2(0, 472), "came round to the bottom left corner")


func test_each_edge_has_its_animation() -> void:
	for edge: Pet.Edge in [Pet.Edge.BOTTOM, Pet.Edge.RIGHT, Pet.Edge.TOP, Pet.Edge.LEFT]:
		assert_has(Duck.ANIMATIONS, Pet.animation_for(edge))
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	var played: RegEx = RegEx.create_from_string("play\\(&\"(\\w+)\"\\)")
	for found: RegExMatch in played.search_all(source):
		assert_has(Duck.ANIMATIONS, StringName(found.get_string(1)), "the duck can play %s" % found.get_string(1))


func test_the_duck_stands_on_every_edge_with_its_base_against_it() -> void:
	assert_eq(Pet.roll_for(Pet.Edge.BOTTOM), 0.0)
	assert_eq(Pet.roll_for(Pet.Edge.RIGHT), 90.0, "rolled anticlockwise, its base points right")
	assert_eq(Pet.roll_for(Pet.Edge.TOP), 180.0)
	assert_eq(Pet.roll_for(Pet.Edge.LEFT), -90.0)


func test_the_duck_faces_where_it_is_going() -> void:
	assert_eq(Pet.facing_for(Pet.Edge.BOTTOM, 1), 1, "walking right faces right")
	assert_eq(Pet.facing_for(Pet.Edge.BOTTOM, -1), -1)
	assert_eq(Pet.facing_for(Pet.Edge.RIGHT, -1), 1, "on the right wall its right points up")
	assert_eq(Pet.facing_for(Pet.Edge.TOP, 1), -1, "upside down its right points left")
	assert_eq(Pet.facing_for(Pet.Edge.LEFT, 1), 1, "on the left wall its right points down")


func test_scene_wires_its_signals_in_the_scene() -> void:
	var state: SceneState = (load("res://scenes/pet.tscn") as PackedScene).get_state()
	var methods: PackedStringArray = PackedStringArray()
	for i: int in state.get_connection_count():
		methods.append(state.get_connection_method(i))
	for method: String in ["_on_area_input_event", "_on_brain_replied", "_on_input_text_submitted", "_on_chat_request_completed", "_on_voice_finished", "_on_test_pressed", "_on_apply_pressed", "_on_send_pressed", "_on_screen_reader_read_finished"]:
		assert_has(methods, method)


func test_bubble_has_chat_stats_and_settings_tabs() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var tabs: TabContainer = pet.get_node("Bubble/Panel/Margin/Tabs")
	var titles: PackedStringArray = PackedStringArray()
	for i: int in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	assert_eq(titles, PackedStringArray(["Chat", "Stats", "Settings"]))
	assert_not_null(pet.get_node("Bubble/Panel/Margin/Tabs/Settings/Voices") as OptionButton)
	pet.free()


func test_there_are_many_greetings() -> void:
	var pet: Pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	assert_gt(pet.greetings.size(), 5)
	for greeting: String in pet.greetings:
		assert_false(greeting.strip_edges().is_empty())
	pet.free()


func test_stats_show_what_the_bubble_used_to() -> void:
	var text: String = Pet.stats_text("Ready, thinking on the GPU.", "NPU: none\nGPU: RTX 4080 Laptop GPU, 369 TOPS", "qwen2.5-1.5b-instruct-trtrtx-gpu", "Microsoft Zira")
	assert_eq(text, "Ready, thinking on the GPU.\nNPU: none\nGPU: RTX 4080 Laptop GPU, 369 TOPS\nModel: qwen2.5-1.5b-instruct-trtrtx-gpu\nVoice: Microsoft Zira")
	assert_eq(Pet.stats_text("Waking up...", "", "", "none"), "Waking up...\nVoice: none", "nothing invented before the brain is up")
	assert_string_ends_with(Pet.stats_text("Ready", "", "", "none", "1234 characters read last time"), "Screen: 1234 characters read last time")


func test_input_box_stands_out_from_the_bubble() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var input: LineEdit = pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Input")
	var style: StyleBoxFlat = input.get_theme_stylebox(&"normal") as StyleBoxFlat
	assert_not_null(style, "the bubble theme styles the box")
	assert_gt(style.border_width_bottom, 0, "it has a visible border")
	assert_not_null(pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Send") as Button, "and a Send button beside it")
	pet.free()


func test_bubble_starts_hidden_in_the_scene() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	assert_false((pet.get_node("Bubble") as Window).visible)
	pet.free()


func test_bubble_is_on_top_but_not_transient() -> void:
	# Windows refuses: "Windows with the 'on top' can't become transient."
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var bubble: Window = pet.get_node("Bubble")
	assert_true(bubble.always_on_top)
	assert_false(bubble.transient)
	pet.free()
