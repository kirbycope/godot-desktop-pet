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
	for method: String in ["_on_mic_toggled", "_on_squeak_finished", "_on_listener_heard", "_on_brain_replied", "_on_input_text_submitted", "_on_chat_stream_delta", "_on_chat_stream_finished", "_on_brain_sentence", "_on_voice_finished", "_on_test_pressed", "_on_apply_pressed", "_on_send_pressed", "_on_screen_reader_read_finished"]:
		assert_has(methods, method)


func test_bubble_has_chat_stats_and_settings_tabs() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var tabs: TabContainer = pet.get_node("Bubble/Panel/Margin/Tabs")
	var titles: PackedStringArray = PackedStringArray()
	for i: int in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	assert_eq(titles, PackedStringArray(["Chat", "Stats", "Settings", "Duck"]))
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


func test_a_quick_click_is_a_click_and_a_pull_is_a_drag() -> void:
	assert_true(Pet.is_click(Vector2(100, 100), Vector2(100, 100), 4.0), "press and release in one frame")
	assert_true(Pet.is_click(Vector2(100, 100), Vector2(103, 102), 4.0))
	assert_false(Pet.is_click(Vector2(100, 100), Vector2(110, 100), 4.0))


func test_the_scene_has_no_physics_picking_to_lose_a_click() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	assert_eq(pet.find_children("*", "Area2D", true, false).size(), 0)
	pet.free()


func test_hit_outline_turns_with_the_duck() -> void:
	var floor: PackedVector2Array = Pet.hit_outline(Vector2(144, 144), Vector2(124, 108), Vector2(0, 16), 0.0)
	assert_almost_eq(floor[0], Vector2(10, 34), Vector2(0.01, 0.01), "top left on the floor")
	assert_almost_eq(floor[2], Vector2(134, 142), Vector2(0.01, 0.01), "bottom right sits on the window's bottom")
	var wall: PackedVector2Array = Pet.hit_outline(Vector2(144, 144), Vector2(124, 108), Vector2(0, 16), 90.0)
	var right_most: float = -INF
	for point: Vector2 in wall:
		right_most = maxf(right_most, point.x)
	assert_almost_eq(right_most, 142.0, 0.01, "on the right wall it hugs the right side")


func test_a_click_squeaks_one_of_four_sounds() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var randomizer: AudioStreamRandomizer = (pet.get_node("Squeak") as AudioStreamPlayer).stream as AudioStreamRandomizer
	assert_not_null(randomizer)
	assert_eq(randomizer.streams_count, 4)
	for i: int in 4:
		assert_not_null(randomizer.get_stream(i), "squeak %d" % (i + 1))
	pet.free()


func test_the_mic_button_toggles_with_an_icon() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var mic: Button = pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Mic")
	assert_true(mic.toggle_mode)
	assert_not_null(mic.icon)
	pet.free()


func test_the_hint_says_what_the_mic_is_doing() -> void:
	assert_eq(Pet.placeholder_for(Listener.Mode.WAITING, true), "Listening... talk, then pause")
	assert_eq(Pet.placeholder_for(Listener.Mode.HEARING, true), "Hearing you...")
	assert_eq(Pet.placeholder_for(Listener.Mode.OFF, true), "Talk to me, then Enter")
	assert_eq(Pet.placeholder_for(Listener.Mode.OFF, false), "Still waking up...")


func test_the_box_opens_only_once_the_duck_is_awake() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	assert_true((pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Input") as LineEdit).editable, "nothing in the scene shuts it for good")
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	assert_string_contains(source, "bubble_input.editable = brain.is_ready()")
	assert_string_contains(source, "mic_button.disabled = not brain.is_ready()")
	pet.free()


func test_the_duck_looks_at_you_only_while_the_bubble_is_open() -> void:
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	assert_string_contains(source, "duck.looking_at_viewer = true")
	assert_string_contains(source, "duck.looking_at_viewer = false")


func test_the_status_line_says_what_the_mic_is_doing() -> void:
	assert_eq(Pet.status_for(Listener.Mode.WAITING, false, false), "Listening...")
	assert_eq(Pet.status_for(Listener.Mode.HEARING, false, false), "Hearing you...")
	assert_eq(Pet.status_for(Listener.Mode.PAUSED, true, false), "Thinking...")
	assert_eq(Pet.status_for(Listener.Mode.PAUSED, false, true), "Talking...")


func test_listening_comes_back_even_if_the_voice_never_says_it_finished() -> void:
	assert_gt(Pet.speaking_seconds("A short answer."), 2.0)
	assert_gt(Pet.speaking_seconds("x".repeat(140)), 11.0, "ten seconds of words, with a margin")
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	assert_false('if state == State.CHAT and duck.animation == &"talk":\n\t\t_done_talking()' in source, "resuming does not hang on the animation")


func test_the_mic_has_a_red_dot_and_the_chat_a_status_line() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var dot: Panel = pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Mic/Dot")
	assert_false(dot.visible, "hidden until the mic is on")
	var red: Color = (dot.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color
	assert_gt(red.r, 0.8)
	assert_lt(red.g, 0.3)
	assert_false((pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Status") as Control).visible)
	assert_not_null(pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Level") as ProgressBar)
	pet.free()


func test_tooltips_are_dark_text_on_light() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var theme: Theme = (pet.get_node("Bubble/Panel") as Control).theme
	assert_lt(theme.get_color(&"font_color", &"TooltipLabel").get_luminance(), 0.3)
	assert_gt((theme.get_stylebox(&"panel", &"TooltipPanel") as StyleBoxFlat).bg_color.get_luminance(), 0.8)
	pet.free()


func test_it_is_happy_to_talk_about_more_than_code() -> void:
	var brain: Brain = load("res://scripts/brain.gd").new()
	assert_string_contains(brain.role, "chat happily about whatever they bring up")
	assert_string_contains(brain.sight_rules, "otherwise ignore it and just talk")
	brain.free()



func test_it_sleeps_until_its_brain_is_ready() -> void:
	assert_eq(Pet.settle_state(Pet.State.WALK, false), Pet.State.SLEEP)
	assert_eq(Pet.settle_state(Pet.State.IDLE, false), Pet.State.SLEEP, "landing from a drag goes back to sleep")
	assert_eq(Pet.settle_state(Pet.State.CHAT, false), Pet.State.CHAT, "a click still opens the bubble")
	assert_eq(Pet.settle_state(Pet.State.DRAG, false), Pet.State.DRAG, "a sleeping duck can still be picked up")
	assert_eq(Pet.settle_state(Pet.State.WALK, true), Pet.State.WALK)


func test_the_warm_up_line_says_what_it_is_doing_and_how_long() -> void:
	assert_eq(Pet.waking_text("Loading qwen2.5-coder-7b...", 23), "Waking up, 23 s: Loading qwen2.5-coder-7b")
	assert_eq(Pet.waking_text("I need Foundry Local to think.\nWindows: winget install", 4), "Waking up, 4 s: I need Foundry Local to think")


func test_the_wake_clock_ticks_in_the_scene() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var clock: Timer = pet.get_node("WakeClock")
	assert_true(clock.autostart)
	assert_eq(clock.wait_time, 1.0)
	pet.free()



func test_a_long_status_never_widens_the_bubble() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var bubble: Window = pet.get_node("Bubble")
	var status: Control = pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Status")
	status.visible = true
	(pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Label") as Label).text = Pet.waking_text("Fetching mistral-nemo-12b-instruct (first run only)...", 120)
	var panel: Control = pet.get_node("Bubble/Panel")
	assert_lte(panel.get_combined_minimum_size().x, float(bubble.size.x), "fits the 340 px bubble, clipped with an ellipsis")
	pet.free()



func test_the_status_takes_the_boxs_place_rather_than_a_row_of_its_own() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var chat: Node = pet.get_node("Bubble/Panel/Margin/Tabs/Chat")
	assert_eq(chat.get_children().map(func(n: Node) -> String: return n.name), ["Text", "Entry"], "nothing between the answer and the entry row")
	assert_eq(pet.get_node("Bubble/Panel/Margin/Tabs/Chat/Entry/Status").get_index(), 0, "the status sits where the box is")
	assert_string_contains((load("res://scripts/pet.gd") as GDScript).source_code, "bubble_input.visible = not status.visible")
	pet.free()


func test_a_long_answer_scrolls_along_as_it_is_spoken() -> void:
	assert_almost_eq(Pet.scroll_seconds("x".repeat(140)), 9.0, 0.01, "about as long as ten seconds of speech, less the top")
	assert_eq(Pet.scroll_seconds("Hi!"), 0.5, "a short answer does not crawl")
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	assert_string_contains(source, "bubble_text.scroll_to_line(0)", "each answer starts from its top")
	assert_string_contains(source, "_scroll_along(_spoken)", "and scrolls once the voice starts")


const SCREEN: Rect2 = Rect2(0, 0, 1000, 600)
const DUCK: Vector2 = Vector2(144, 144)


func test_the_throw_takes_the_mouses_last_speed() -> void:
	var trail: Array = [[1000, Vector2(100, 400)], [1050, Vector2(150, 380)], [1100, Vector2(300, 300)]]
	assert_eq(Pet.throw_velocity(trail, 4500.0), Vector2(2000, -1000), "200 px right and 100 up in a tenth of a second")
	assert_eq(Pet.throw_velocity([[1000, Vector2.ZERO]], 4500.0), Vector2.ZERO, "a drop, not a throw")
	assert_almost_eq(Pet.throw_velocity([[0, Vector2.ZERO], [10, Vector2(1000, 0)]], 4500.0).length(), 4500.0, 0.1, "capped")


func test_a_thrown_duck_bounces_off_the_walls_and_ceiling() -> void:
	var wall: Dictionary = Pet.fly(Vector2(850, 200), Vector2(3000, 0), SCREEN, DUCK, 0.016, 2600.0, 0.55, 4.0)
	assert_eq(wall["position"].x, 856.0, "stopped at the right edge")
	assert_lt(wall["velocity"].x, 0.0, "and heading back left")
	assert_gt(wall["impact"], 2000.0)
	var ceiling: Dictionary = Pet.fly(Vector2(400, 5), Vector2(0, -2000), SCREEN, DUCK, 0.016, 2600.0, 0.55, 4.0)
	assert_eq(ceiling["position"].y, 0.0)
	assert_gt(ceiling["velocity"].y, 0.0, "back down")


func test_it_bounces_lower_each_time_and_comes_to_rest() -> void:
	var at: Vector2 = Vector2(400, 0)
	var speed: Vector2 = Vector2(600, 0)
	var bounces: int = 0
	var rested: bool = false
	for frame: int in 60 * 10:
		var step: Dictionary = Pet.fly(at, speed, SCREEN, DUCK, 1.0 / 60.0, 2600.0, 0.55, 4.0)
		if step["impact"] > 250.0:
			bounces += 1
		at = step["position"]
		speed = step["velocity"]
		if step["resting"]:
			rested = true
			break
	assert_true(rested, "settles within ten seconds")
	assert_gt(bounces, 1, "bounces more than once on the way")
	assert_eq(at.y, 456.0, "on the bottom")


func test_stats_show_how_quick_the_last_answer_was() -> void:
	assert_eq(Pet.timing_text({}, 400), "", "nothing until an answer has come")
	assert_eq(Pet.timing_text({"first_token": 390, "first_sentence": 977, "reply": 1863, "finish_reason": "stop", "debugging": true}, 410), "screen 410 ms, first word 390 ms, first sentence 977 ms, whole 1.9 s (stop, debugging)")
	assert_string_ends_with(Pet.stats_text("Ready", "", "", "none", "", "", "whole 1.9 s"), "Last answer: whole 1.9 s")


func test_a_screen_read_ahead_is_used_only_while_fresh() -> void:
	assert_true(Pet.is_fresh(1000, 3500, 3000))
	assert_false(Pet.is_fresh(1000, 4500, 3000), "too old: read it again")
	assert_false(Pet.is_fresh(-1, 10, 3000), "nothing read ahead")
	var state: SceneState = (load("res://scenes/pet.tscn") as PackedScene).get_state()
	var methods: PackedStringArray = PackedStringArray()
	for i: int in state.get_connection_count():
		methods.append(state.get_connection_method(i))
	assert_has(methods, "_on_input_text_changed", "typing starts the read")
