extends GutTest
## The phone app's pieces that run without a phone: its helpers, its scene, and the settings that
## make Android open it.


func test_yours_go_right_and_the_ducks_left_in_the_phones_own_bubbles() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	app.tabs.add_message("user", "Good morning, Ducky.")
	app.tabs.add_message("assistant", "Good morning! Ready for coffee?")
	var rows: Array[Node] = app.tabs.messages_box.get_children()
	assert_eq((rows[0] as HBoxContainer).alignment, BoxContainer.ALIGNMENT_END, "yours on the right")
	assert_eq((rows[1] as HBoxContainer).alignment, BoxContainer.ALIGNMENT_BEGIN, "the duck's on the left")
	var yours: StyleBox = (rows[0].get_child(0) as PanelContainer).get_theme_stylebox("panel")
	assert_eq(yours.get_margin(SIDE_LEFT), 22.0, "the phone's theme sizes them, not the PC's")
	assert_eq((rows[0].get_child(0).get_child(0) as Label).get_theme_color("font_color"), Color.WHITE)


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
	for method: String in ["_on_duck_view_gui_input", "_on_tabs_line_sent", "_on_mic_toggled", "_on_found_item_selected", "_on_connect_pressed", "_on_code_submitted", "_on_listener_wav_ready", "_on_listener_mode_changed", "_on_player_finished", "_on_ping_clock_timeout", "_on_new_pressed", "_on_mute_toggled", "_on_past_pressed", "_on_conversation_chosen", "_on_pomodoro_pressed", "_on_lengths_changed", "_on_voice_applied", "_on_voice_tested", "_on_name_saved", "_on_memory_forgotten", "_on_hat_toggled"]:
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
	assert_eq(DuckTabs.history_line(found_one, ""), "2026-10-08 06:45   Good morning, Ducky.")
	assert_eq(DuckTabs.history_line(found_one, "2026-10-08_064512"), "2026-10-08 06:45   Good morning, Ducky.   (now)")


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
	var button: CheckBox = app.get_node("Layout/Chat/Margin/Column/Tabs/Duck/HatRow/Hat")
	button.button_pressed = true
	assert_true(app.duck.hat, "pressed, the duck wears it")
	app._show_hat(false)
	assert_false(app.duck.hat, "the PC took it off")
	assert_false(button.button_pressed, "and the box shows it")


func test_the_phone_duck_is_a_tomato_while_the_pc_timer_runs() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	assert_false(app.duck.tomato)
	app._on_frame({"tomato": true})
	assert_true(app.duck.tomato)
	app._on_frame({"pomodoro_state": {"title": "Focus, round 1 of 4", "left": 1500.0, "length": 1500.0, "running": true, "paused": false, "lengths": [25, 5, 15]}})
	assert_eq(app.tabs.time_label.text, "25:00", "the Pomodoro tab shows the PC's timer")
	assert_eq(app.tabs.start_button.text, "Pause")
	app._on_frame({"tomato": false})
	assert_false(app.duck.tomato)


func test_with_no_pc_pomodoro_only_keeps_time_on_the_phone() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	app.get_node("Pomodoro").settings_path = "user://test_phone_pomodoro.cfg"
	add_child_autofree(app)
	app.get_node("Pairing/Margin/Column/Alone/PomodoroOnly").pressed.emit()
	assert_eq(app.mode, RemoteApp.Mode.POMODORO)
	assert_false(app.pairing.visible)
	assert_true(app.find_pc_button.visible, "a way back to the PC")
	assert_eq(app.tabs.get_current_tab_control().name, &"Pomodoro")
	for i: int in app.tabs.get_tab_count():
		assert_eq(app.tabs.is_tab_disabled(i), app.tabs.get_tab_control(i).name != &"Pomodoro", "only the timer without a model")
	app.tabs.start_button.pressed.emit()
	assert_true(app.local_pomodoro.is_running(), "the tab works the phone's own timer")
	assert_true(app.duck.tomato)
	assert_eq(app.tabs.start_button.text, "Pause")
	app.tabs.stop_button.pressed.emit()
	assert_false(app.duck.tomato)
	app.find_pc_button.pressed.emit()
	assert_eq(app.mode, RemoteApp.Mode.PC)
	assert_true(app.pairing.visible)
	assert_false(app.tabs.is_tab_disabled(0), "every tab again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_phone_pomodoro.cfg"))


func test_with_no_pc_the_local_duck_has_every_tab_but_no_mic() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	app.get_node("Mind").root = "user://test_phone_mind"
	app.get_node("Pomodoro").settings_path = "user://test_phone_pomodoro.cfg"
	add_child_autofree(app)
	# The mode only: start() would fetch a model.
	app._go_alone(RemoteApp.Mode.LOCAL)
	assert_eq(app.mode, RemoteApp.Mode.LOCAL)
	for i: int in app.tabs.get_tab_count():
		assert_false(app.tabs.is_tab_disabled(i), "every tab: the duck runs here")
	assert_true(app.tabs.mic_button.disabled, "the PC writes speech down, so no mic here")
	assert_false(app.tabs.input.editable, "nothing to type to until a model is ready")
	assert_string_contains(app.tabs.stats.text, "Model: not loaded yet")
	assert_eq(app.tabs.pairing_label.text, "No PC: the duck runs on this phone.")
	app._on_tabs_line_sent("start a pomodoro")
	assert_true(app.local_pomodoro.is_running(), "the timer answers without a model")
	assert_true(app.duck.tomato)
	app._on_tabs_line_sent("stop the pomodoro")
	assert_false(app.local_pomodoro.is_running())
	app.tabs.name_field.text = "Pip"
	app.tabs.name_field.text_submitted.emit("Pip")
	assert_eq(app.mind.duck_name(), "Pip", "the Duck tab names the phone's own duck")
	app.find_pc_button.pressed.emit()
	assert_eq(app.mode, RemoteApp.Mode.PC)
	assert_true(app.local_brain.stopped, "the model lets go on the way back")
	assert_false(app.local_brain.is_ready())
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_phone_pomodoro.cfg"))
	_remove(ProjectSettings.globalize_path("user://test_phone_mind"))


func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_remove(folder.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func test_the_phones_model_stops_in_the_background_and_from_the_stats_tab() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	app.get_node("Mind").root = "user://test_phone_mind"
	# A model that cannot load, so nothing is downloaded when it wakes again.
	app.get_node("LocalBrain").model_path = "res://no_such_model.gguf"
	app.get_node("LocalBrain").metrics_path = ""
	add_child_autofree(app)
	app._go_alone(RemoteApp.Mode.LOCAL)
	# As though a model had loaded.
	app.local_brain.engine = "NobodyWho"
	app._on_local_brain_status_changed("Ready, thinking on this phone.")
	assert_eq(app.tabs.model_button.text, "Stop the model")
	app._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_true(app.local_brain.stopped, "in the background its memory goes")
	assert_false(app.local_brain.is_ready())
	app._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_false(app.local_brain.stopped, "and back in front it wakes again")
	await wait_until(func() -> bool: return not app.local_brain.is_starting(), 10.0)
	if ClassDB.class_exists(&"NobodyWhoChat"):
		assert_engine_error("Model not found", "the stand-in model is not there, as meant")
	app.local_brain.engine = "NobodyWho"
	app.tabs.model_button.pressed.emit()
	assert_true(app.local_brain.stopped, "Stop on the Stats tab")
	assert_eq(app.tabs.model_button.text, "Start the model")
	_remove(ProjectSettings.globalize_path("user://test_phone_mind"))


func test_with_no_pc_the_stats_tab_picks_the_model_and_runs_the_benchmark() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	app.get_node("Mind").root = "user://test_phone_mind"
	app.get_node("BenchMind").root = "user://test_phone_bench_mind"
	app.get_node("LocalBrain").metrics_path = "user://test_phone_metrics.jsonl"
	var bench: LocalBench = app.get_node("Bench")
	bench.settle_seconds = 0.0
	bench.model_folders = PackedStringArray([ProjectSettings.globalize_path("user://test_phone_models")])
	add_child_autofree(app)
	var ids: Array = RemoteApp.setup_items().map(func(item: Dictionary) -> String: return item["id"])
	assert_eq(ids[0], "auto", "Auto comes first")
	assert_eq(ids.size(), LocalBrain.SETUPS.size() + 1, "then every setup")
	assert_true(app.tabs.setup_list.visible, "the phone shows the picker")
	assert_true(app.tabs.bench_button.visible)
	assert_true(app.tabs.setup_list.disabled, "but it works the phone's own model, so not while looking for the PC")
	app._go_alone(RemoteApp.Mode.LOCAL)
	assert_false(app.tabs.setup_list.disabled)
	assert_false(app.tabs.bench_button.disabled)
	# Setups that need the Android plugins fail at once on a desktop, so nothing is downloaded.
	bench.setups = PackedStringArray(["litertlm-gemma4-e2b-gpu"])
	app.local_brain.model_path = "res://no_such_model.gguf"
	app.tabs.bench_button.pressed.emit()
	assert_true(bench.running)
	assert_eq(app.tabs.bench_button.text, "Stop the benchmark")
	assert_true(app.tabs.setup_list.disabled, "no picking while it runs")
	await wait_until(func() -> bool: return not bench.running, 10.0)
	await wait_until(func() -> bool: return not app.local_brain.is_starting(), 10.0)
	if ClassDB.class_exists(&"NobodyWhoChat"):
		assert_engine_error("Model not found", "the duck's own stand-in model starts again after it")
	assert_eq(app.tabs.bench_button.text, "Run the benchmark")
	assert_eq(app.local_brain.setup_id, "auto", "the duck's own setup again")
	assert_eq(app.local_brain.mind, app.mind, "and its own mind")
	assert_string_contains(app.tabs.stats.text, "Gemma 4 E2B, LiteRT-LM GPU", "the results are on the Stats tab")
	assert_string_contains(app.tabs.stats.text, "Failed: LiteRT-LM needs")
	app.local_brain.stop()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_phone_metrics.jsonl"))
	_remove(ProjectSettings.globalize_path("user://test_phone_mind"))
	_remove(ProjectSettings.globalize_path("user://test_phone_bench_mind"))


func test_the_pc_bubble_has_no_phone_model_picker() -> void:
	var state: SceneState = (load("res://scenes/pet.tscn") as PackedScene).get_state()
	for i: int in state.get_node_count():
		assert_false(str(state.get_node_path(i)).ends_with("Stats/Setup"), "pet.tscn leaves the picker as duck_tabs.tscn has it: hidden")
	var tabs: DuckTabs = (load("res://scenes/duck_tabs.tscn") as PackedScene).instantiate()
	add_child_autofree(tabs)
	assert_false(tabs.setup_list.visible)
	assert_false(tabs.bench_button.visible)


func test_a_paired_phones_model_button_works_the_pcs_model() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	app._on_frame({"status": "Stopped: the model is not loaded.", "ready": false, "stopped": true})
	assert_eq(app.tabs.model_button.text, "Start the model", "the PC's model is stopped")
	assert_false(app.tabs.model_button.disabled)
	app._on_frame({"status": "Ready, thinking on the GPU.", "ready": true, "stopped": false})
	assert_eq(app.tabs.model_button.text, "Stop the model")


func test_a_welcome_fills_every_tab_from_the_pc() -> void:
	var app: RemoteApp = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	add_child_autofree(app)
	assert_false(app.tabs.folder_button.visible, "the duck's folder is on the PC, not here")
	assert_true(app.tabs.mute_box.visible, "muting is this phone's own")
	app._on_frame({
		"welcome": "Ducky", "ready": false, "status": "Loading...", "speaks": false, "hat": true, "tomato": false,
		"recent": [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "Hello!"}],
		"memories": ["likes Godot"],
		"pomodoro_state": {"title": "Not running", "running": false, "lengths": [45, 5, 15]},
		"stats": "Ready, thinking on the GPU.",
		"voices": {"items": [{"id": "sys", "text": "Zira (US English)"}], "chosen": "sys", "note": "Speaking as: Zira"},
	})
	assert_eq(app.title.text, "Ducky")
	assert_eq(app.tabs.name_field.text, "Ducky")
	assert_eq(app.tabs.memory_list.item_count, 1)
	assert_true(app.tabs.hat_box.button_pressed)
	assert_eq(app.tabs.time_label.text, "45:00", "the PC's focus length")
	assert_eq(app.tabs.stats.text, "Ready, thinking on the GPU.")
	assert_eq(app.tabs.selected_voice(), "sys")
	assert_eq(app.tabs.current_voice.text, "Speaking as: Zira")
	assert_true(app.tabs.input.editable == false, "nothing to type into while the PC duck wakes")
	app._on_frame({"duck_name": "Quackers", "memories": []})
	assert_eq(app.title.text, "Quackers")
	assert_eq(app.tabs.memory_list.item_count, 0)
	app._on_frame({"voice_note": "Downloading natural voices: 120 of 352 MB"})
	assert_eq(app.tabs.current_voice.text, "Downloading natural voices: 120 of 352 MB")


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
