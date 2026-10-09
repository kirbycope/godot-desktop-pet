extends GutTest
## The phone app's pieces that run without a phone: its helpers, its scene, and the settings that
## make Android open it.


func test_a_bubble_is_as_wide_as_its_text_up_to_the_room() -> void:
	assert_eq(RemoteApp.bubble_width(80.4, 500.0), 83.0, "a short one shrinks to fit")
	assert_eq(RemoteApp.bubble_width(900.0, 500.0), 500.0, "a long one wraps at the room")


func test_yours_go_right_and_the_ducks_left() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	app._add_message("user", "Good morning, Ducky.")
	app._add_message("assistant", "Good morning! Ready for coffee?")
	var rows: Array[Node] = app.messages_box.get_children()
	assert_eq((rows[0] as HBoxContainer).alignment, BoxContainer.ALIGNMENT_END, "yours on the right")
	assert_eq((rows[1] as HBoxContainer).alignment, BoxContainer.ALIGNMENT_BEGIN, "the duck's on the left")
	assert_eq((rows[0].get_child(0) as PanelContainer).get_theme_stylebox("panel"), app.your_bubble)
	assert_eq((rows[1].get_child(0) as PanelContainer).get_theme_stylebox("panel"), app.duck_bubble)


func test_audio_plays_in_order_and_waits_for_a_gap() -> void:
	var one: AudioStreamWAV = AudioStreamWAV.new()
	var three: AudioStreamWAV = AudioStreamWAV.new()
	var queue: Dictionary = {1: one, 3: three}
	assert_eq(RemoteApp.next_audio(queue, 1), one)
	assert_null(RemoteApp.next_audio(queue, 2), "sentence 2 has not come yet: wait rather than skip to 3")


func test_the_scene_wires_its_signals() -> void:
	var state: SceneState = (load("res://scenes/remote.tscn") as PackedScene).get_state()
	var methods: PackedStringArray = PackedStringArray()
	for i: int in state.get_connection_count():
		methods.append(state.get_connection_method(i))
	for method: String in ["_on_duck_view_gui_input", "_on_input_text_submitted", "_on_mic_toggled", "_on_send_pressed", "_on_found_item_selected", "_on_connect_pressed", "_on_code_submitted", "_on_listener_wav_ready", "_on_listener_mode_changed", "_on_player_finished", "_on_ping_clock_timeout", "_on_new_pressed", "_on_mute_toggled", "_on_past_pressed", "_on_history_item_selected", "_on_history_close_pressed"]:
		assert_has(methods, method)


func test_the_phone_listens_but_hands_its_sentences_to_the_pc() -> void:
	var app: Node = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	var listener: Listener = app.get_node("Listener")
	assert_true(listener.hand_off)
	assert_eq((app.get_node("Listener/Mic") as AudioStreamPlayer).bus, &"Mic")
	assert_not_null(app.get_node("Layout/DuckView/Viewport/Duck"), "the same duck as on the PC")
	app.free()


func test_android_opens_the_phone_app_in_an_ordinary_portrait_window() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_eq(config.load("res://project.godot"), OK)
	assert_eq(config.get_value("application", "run/main_scene"), "res://scenes/pet.tscn", "the PC still gets the pet")
	assert_eq(config.get_value("application", "run/main_scene.android"), "res://scenes/remote.tscn")
	assert_eq(config.get_value("display", "window/size/transparent.android"), false)
	assert_eq(config.get_value("display", "window/size/borderless.android"), false)
	assert_eq(config.get_value("display", "window/handheld/orientation.android"), 1, "portrait")
	assert_eq(config.get_value("rendering", "textures/vram_compression/import_etc2_astc"), true, "Android needs ETC2/ASTC")


func test_the_android_preset_asks_for_the_network_and_the_mic() -> void:
	var presets: ConfigFile = ConfigFile.new()
	assert_eq(presets.load("res://export_presets.cfg"), OK)
	assert_eq(presets.get_value("preset.0", "platform"), "Android")
	assert_eq(presets.get_value("preset.0.options", "permissions/internet"), true)
	assert_eq(presets.get_value("preset.0.options", "permissions/record_audio"), true)
	assert_eq(presets.get_value("preset.0.options", "architectures/arm64-v8a"), true, "phones")
	assert_eq(presets.get_value("preset.0.options", "architectures/x86_64"), true, "the emulator")


func test_the_mic_waits_for_the_last_sentence_to_be_heard() -> void:
	assert_true(RemoteApp.owes_audio(1, 3), "three sentences written, none heard: the text being done is not enough")
	assert_true(RemoteApp.owes_audio(3, 3))
	assert_false(RemoteApp.owes_audio(4, 3), "all three heard")
	assert_null(RemoteApp.next_audio({1: false}, 1), "one the PC could not say is skipped, not played")


func test_a_past_conversation_shows_when_and_what_and_which_is_now() -> void:
	var found_one: Dictionary = {"id": "2026-10-08_064512", "when": "2026-10-08 06:45", "title": "Good morning, Ducky."}
	assert_eq(RemoteApp.history_line(found_one, ""), "2026-10-08 06:45   Good morning, Ducky.")
	assert_eq(RemoteApp.history_line(found_one, "2026-10-08_064512"), "2026-10-08 06:45   Good morning, Ducky.   (now)")


func test_the_bath_is_calm_until_it_is_stirred() -> void:
	var app: Node = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	var bubbles: CPUParticles3D = app.get_node("Layout/DuckView/Viewport/Bubbles")
	assert_false(bubbles.emitting, "no bubbles until something disturbs the water")
	assert_true(bubbles.one_shot, "a burst, not a stream")
	app.free()


func test_a_harder_jolt_stirs_more_and_it_settles() -> void:
	assert_eq(RemoteApp.stir_for(2.6, 2.5), 0.3 + 0.1 / 6.0, "just past the threshold: a little")
	assert_eq(RemoteApp.stir_for(20.0, 2.5), 1.0, "a hard shake: fully")
	assert_almost_eq(RemoteApp.settled_stir(1.0, 0.8, 0.8), 0.5, 0.0001, "half gone after the half-life")


func test_the_hat_button_puts_the_hat_on_and_follows_the_pc() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	var button: Button = app.get_node("Layout/Chat/Margin/Column/Header/Hat")
	assert_true(button.toggle_mode)
	button.button_pressed = true
	assert_true(app.duck.hat, "pressed, the duck wears it")
	app._show_hat(false)
	assert_false(app.duck.hat, "the PC took it off")
	assert_false(button.button_pressed, "and the button shows it")


func test_the_phone_duck_is_a_tomato_while_the_pc_timer_runs() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	var button: Button = app.get_node("Layout/Chat/Margin/Column/Header/Timer")
	assert_true(button.toggle_mode)
	assert_false(app.duck.tomato)
	app._on_frame({"tomato": true})
	assert_true(app.duck.tomato)
	assert_true(button.button_pressed, "the Timer button shows it running")
	app._on_frame({"tomato": false})
	assert_false(app.duck.tomato)
	assert_false(button.button_pressed)
	button.button_pressed = true
	assert_false(button.button_pressed, "with no PC to ask, it comes back up")
	assert_false(app.duck.tomato, "and the duck waits for the PC to say the timer runs")


func test_a_thrown_duck_bounces_off_the_sides_and_splashes_down() -> void:
	var bounds: Rect2 = Rect2(-0.3, 0.0, 0.6, 0.4)
	var off_the_side: Dictionary = RemoteApp.toss(Vector2(0.29, 0.2), Vector2(3.0, 0.0), bounds, 0.05, 5.0)
	assert_almost_eq(off_the_side["position"].x, 0.3, 0.0001, "kept in view")
	assert_lt(off_the_side["velocity"].x, 0.0, "and on its way back")
	assert_eq(off_the_side["bump"], 3.0, "a bump as hard as it hit, for the squeak")
	var flop: Dictionary = RemoteApp.toss(Vector2(0.0, 0.05), Vector2(0.0, -3.0), bounds, 0.05, 5.0)
	assert_eq(flop["position"].y, 0.0, "in the water, not under it")
	assert_gt(flop["splash"], 3.0, "a splash as hard as it came down")
	assert_gt(flop["velocity"].y, 0.0, "bobbing up again after a belly flop")
	assert_false(flop["resting"])


func test_a_dropped_duck_settles_in_the_water() -> void:
	var p: Vector2 = Vector2(0.1, 0.3)
	var v: Vector2 = Vector2.ZERO
	var splashes: int = 0
	var resting: bool = false
	for i: int in 600:
		var step: Dictionary = RemoteApp.toss(p, v, Rect2(-0.3, 0.0, 0.6, 0.4), 1.0 / 60.0, 5.0)
		p = step["position"]
		v = step["velocity"]
		splashes += 1 if step["splash"] > 0.0 else 0
		if step["resting"]:
			resting = true
			break
	assert_true(resting, "it comes to rest")
	assert_eq(p.y, 0.0, "afloat")
	assert_gt(splashes, 0)


func test_pushing_the_duck_down_squeezes_it() -> void:
	assert_true(RemoteApp.is_squash(0.0, Vector2(0.0, -0.4)), "swiped down into the water")
	assert_false(RemoteApp.is_squash(0.2, Vector2.ZERO), "lifted out and let go: a drop")
	assert_false(RemoteApp.is_squash(0.01, Vector2(3.0, 0.5)), "flung along the water: a throw")
