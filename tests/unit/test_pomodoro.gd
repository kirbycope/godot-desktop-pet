extends GutTest
## The Pomodoro timer: what a line asks of it, its rounds, its tab, and the tomato it makes of the duck.

const SETTINGS: String = "user://test_pomodoro.cfg"

var tab: Pomodoro


## The timer out of pet.tscn, on its own in the tree, keeping its lengths in a scratch file, at the
## usual 25, 5 and 15 minutes.
func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	tab = pet.get_node("Pomodoro")
	pet.remove_child(tab)
	tab.owner = null
	pet.free()
	tab.settings_path = SETTINGS
	add_child_autofree(tab)


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func test_asking_for_one_starts_it_and_can_say_how_long() -> void:
	assert_eq(Pomodoro.request_in("Start a pomodoro"), {"action": "start", "minutes": 0})
	assert_eq(Pomodoro.request_in("Can you start a 50 minute pomodoro please?"), {"action": "start", "minutes": 50})
	assert_eq(Pomodoro.request_in("Let's do a pomodoro of twenty-five minutes."), {"action": "start", "minutes": 25})
	assert_eq(Pomodoro.request_in("I'd like a pomodoro"), {"action": "start", "minutes": 0})
	assert_eq(Pomodoro.request_in("set a tomato timer for 10 mins").get("minutes"), 10)
	assert_eq(Pomodoro.request_in("Start a pomadoro.").get("action"), "start", "as speech-to-text spells it")


func test_it_can_be_stopped_paused_resumed_skipped_and_asked_about() -> void:
	assert_eq(Pomodoro.request_in("Stop the pomodoro").get("action"), "stop")
	assert_eq(Pomodoro.request_in("cancel my pomodoro").get("action"), "stop")
	assert_eq(Pomodoro.request_in("Pause the pomodoro").get("action"), "pause")
	assert_eq(Pomodoro.request_in("Resume the pomodoro").get("action"), "resume")
	assert_eq(Pomodoro.request_in("skip this pomodoro").get("action"), "skip")
	assert_eq(Pomodoro.request_in("How long is left on the pomodoro?").get("action"), "status")
	assert_eq(Pomodoro.request_in("When does the pomodoro end?").get("action"), "status", "asking when it ends does not end it")


func test_talking_about_one_is_left_to_the_model() -> void:
	assert_eq(Pomodoro.request_in("What is the pomodoro technique?"), {})
	assert_eq(Pomodoro.request_in("What do you think of pomodoros?"), {})
	assert_eq(Pomodoro.request_in("I had a tomato for lunch"), {})
	assert_eq(Pomodoro.request_in("start the build"), {}, "no timer named")


func test_four_focus_rounds_then_a_long_break() -> void:
	var seen: Array[Pomodoro.Phase] = []
	var phase: Pomodoro.Phase = Pomodoro.Phase.FOCUS
	var done: int = 0
	for i: int in 8:
		if phase == Pomodoro.Phase.FOCUS:
			done += 1
		phase = Pomodoro.next_phase(phase, done, 4)
		seen.append(phase)
	assert_eq(seen, [
		Pomodoro.Phase.SHORT_BREAK, Pomodoro.Phase.FOCUS, Pomodoro.Phase.SHORT_BREAK, Pomodoro.Phase.FOCUS,
		Pomodoro.Phase.SHORT_BREAK, Pomodoro.Phase.FOCUS, Pomodoro.Phase.LONG_BREAK, Pomodoro.Phase.FOCUS,
	] as Array[Pomodoro.Phase])
	assert_eq(Pomodoro.next_phase(Pomodoro.Phase.OFF, 0, 4), Pomodoro.Phase.OFF)


func test_times_read_as_a_clock_and_are_said_in_words() -> void:
	assert_eq(Pomodoro.clock(25 * 60), "25:00")
	assert_eq(Pomodoro.clock(61), "01:01")
	assert_eq(Pomodoro.spoken_time(12 * 60 + 20), "12 minutes")
	assert_eq(Pomodoro.spoken_time(60), "1 minute")
	assert_eq(Pomodoro.spoken_time(40), "40 seconds")
	assert_eq(Pomodoro.title_for(Pomodoro.Phase.FOCUS, 5, 4), "Focus, round 2 of 4")
	assert_eq(Pomodoro.title_for(Pomodoro.Phase.OFF, 0, 4), "Not running")


func test_the_tab_runs_round_by_round_and_stops() -> void:
	watch_signals(tab)
	assert_eq(tab.carry_out({"action": "start", "minutes": 0}), "Tomato time! 25 minutes of focus. I'll tell you when it's time for a break.")
	assert_eq(tab.phase, Pomodoro.Phase.FOCUS)
	assert_almost_eq(tab.phase_timer.wait_time, 1500.0, 0.01)
	assert_signal_emitted_with_parameters(tab, "phase_changed", [Pomodoro.Phase.FOCUS])
	tab.skip()
	assert_eq(tab.phase, Pomodoro.Phase.SHORT_BREAK)
	assert_almost_eq(tab.phase_timer.wait_time, 300.0, 0.01)
	assert_signal_emitted_with_parameters(tab, "time_up", [Pomodoro.Phase.SHORT_BREAK])
	for i: int in 6:
		tab.skip()
	assert_eq(tab.phase, Pomodoro.Phase.LONG_BREAK, "after the fourth round")
	assert_almost_eq(tab.phase_timer.wait_time, 900.0, 0.01)
	assert_eq(tab.carry_out({"action": "stop"}), "Pomodoro stopped. Back to being a plain old duck.")
	assert_eq(tab.phase, Pomodoro.Phase.OFF)
	assert_signal_emitted_with_parameters(tab, "phase_changed", [Pomodoro.Phase.OFF])
	assert_eq(tab.carry_out({"action": "stop"}), "There's no pomodoro running.")


func test_a_length_asked_for_and_pausing() -> void:
	tab.carry_out({"action": "start", "minutes": 50})
	assert_almost_eq(tab.phase_timer.wait_time, 3000.0, 0.01, "this round only")
	assert_string_starts_with(tab.carry_out({"action": "pause"}), "Paused, with 50 minutes left")
	assert_true(tab.is_paused())
	assert_string_ends_with(tab.carry_out({"action": "status"}), ", paused.")
	assert_string_starts_with(tab.carry_out({"action": "resume"}), "And we're off again")
	assert_false(tab.is_paused())
	tab.skip()
	tab.skip()
	assert_almost_eq(tab.phase_timer.wait_time, 1500.0, 0.01, "the next round is the usual length")


func test_the_lengths_are_kept() -> void:
	Pomodoro.save_lengths(SETTINGS, [50, 10, 30])
	assert_eq(Pomodoro.load_lengths(SETTINGS, [25, 5, 15]), [50, 10, 30] as Array[int])
	assert_eq(Pomodoro.load_lengths("user://no_such_settings.cfg", [25, 5, 15]), [25, 5, 15] as Array[int])


func test_lengths_are_kept_in_range_and_saved() -> void:
	watch_signals(tab)
	tab.set_lengths([50, 0, 500] as Array[int])
	assert_eq(tab.lengths, [50, 1, 90] as Array[int], "at least a minute, at most an hour and a half for the long break")
	assert_eq(Pomodoro.load_lengths(SETTINGS, Pomodoro.DEFAULT_LENGTHS), [50, 1, 90] as Array[int])
	assert_signal_emitted(tab, "changed")
	tab.act("start")
	assert_almost_eq(tab.phase_timer.wait_time, 3000.0, 0.01)
	tab.act("pause")
	assert_true(tab.state()["paused"])
	tab.act("resume")
	assert_false(tab.state()["paused"])
	tab.act("stop")
	assert_false(tab.state()["running"])


func test_after_sleeping_it_catches_up_by_the_clock() -> void:
	watch_signals(tab)
	tab.start()
	var began: float = Time.get_unix_time_from_system()
	tab.catch_up(began + 600.0)
	assert_eq(tab.phase, Pomodoro.Phase.FOCUS, "ten minutes in, still focusing")
	assert_almost_eq(tab.phase_timer.time_left, 900.0, 2.0, "with fifteen to go")
	assert_signal_not_emitted(tab, "time_up")
	tab.catch_up(began + 1500.0 + 300.0 + 60.0)
	assert_eq(tab.phase, Pomodoro.Phase.FOCUS, "a focus, its break, and a minute into the next focus")
	assert_eq(tab.finished, 1)
	assert_almost_eq(tab.phase_timer.time_left, 1440.0, 2.0)
	assert_signal_emit_count(tab, "time_up", 1, "only the phase under way is announced")
	tab.pause()
	tab.catch_up(began + 99999.0)
	assert_eq(tab.finished, 1, "a paused timer waits")


func test_the_state_is_what_the_tab_shows() -> void:
	var state: Dictionary = tab.state()
	assert_eq(state["title"], "Not running")
	assert_almost_eq(float(state["length"]), 1500.0, 0.01, "not running, the next focus's length")
	tab.start()
	state = tab.state()
	assert_true(state["running"])
	assert_eq(state["title"], "Focus, round 1 of 4")
	assert_almost_eq(float(state["left"]), 1500.0, 1.0)
	assert_eq(JSON.parse_string(JSON.stringify(state))["lengths"], [25.0, 5.0, 15.0], "it goes to the phone as JSON")


func test_the_tab_counts_down_and_its_buttons_ask_for_the_next_thing() -> void:
	var tabs: DuckTabs = (load("res://scenes/duck_tabs.tscn") as PackedScene).instantiate()
	add_child_autofree(tabs)
	watch_signals(tabs)
	assert_eq(tabs.time_label.text, "25:00", "not running: the focus length")
	assert_true(tabs.stop_button.disabled)
	tabs.show_pomodoro({"phase": Pomodoro.Phase.FOCUS, "title": "Focus, round 2 of 4", "left": 600.0, "length": 1500.0, "running": true, "paused": false, "lengths": [25, 5, 15]})
	assert_eq(tabs.phase_label.text, "Focus, round 2 of 4")
	assert_eq(tabs.time_label.text, "10:00")
	assert_almost_eq(tabs.bar.value, 0.6, 0.01)
	assert_eq(tabs.start_button.text, "Pause")
	assert_false(tabs.tick.is_stopped(), "it ticks while running")
	tabs._pomodoro_at -= 61000
	tabs._on_tick_timeout()
	assert_eq(tabs.time_label.text, "08:59", "counting down between updates")
	tabs.start_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "pomodoro_pressed", ["pause"])
	tabs.show_pomodoro({"title": "Short break", "left": 120.0, "length": 300.0, "running": true, "paused": true, "lengths": [25, 5, 15]})
	assert_eq(tabs.phase_label.text, "Short break (paused)")
	assert_eq(tabs.start_button.text, "Resume")
	assert_true(tabs.tick.is_stopped(), "not while paused")
	tabs.start_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "pomodoro_pressed", ["resume"])
	tabs.focus_box.value = 45
	assert_signal_emitted_with_parameters(tabs, "lengths_changed", [[45, 5, 15]])


func test_the_tab_sits_after_chat_and_is_wired() -> void:
	var wired: PackedStringArray = PackedStringArray()
	for scene: String in ["res://scenes/pet.tscn", "res://scenes/duck_tabs.tscn"]:
		var state: SceneState = (load(scene) as PackedScene).get_state()
		for i: int in state.get_connection_count():
			wired.append("%s.%s" % [state.get_connection_signal(i), state.get_connection_method(i)])
	for connection: String in ["phase_changed._on_pomodoro_phase_changed", "time_up._on_pomodoro_time_up", "changed._on_pomodoro_changed", "timeout._on_phase_timer_timeout", "pomodoro_pressed.act", "lengths_changed.set_lengths", "timeout._on_tick_timeout", "pressed._on_start_pressed", "pressed._on_skip_pressed", "pressed._on_stop_pressed", "value_changed._on_length_changed"]:
		assert_has(wired, connection)


func test_the_duck_turns_tomato_and_back() -> void:
	var duck: Duck = load("res://scenes/duck.tscn").instantiate()
	add_child_autofree(duck)
	var leaves: Node3D = duck.get_node("Pivot/Body/Yaw/Leaves")
	var hat: Node3D = duck.get_node("Pivot/Body/Yaw/Hat")
	assert_false(leaves.visible, "a plain duck to start")
	duck.hat = true
	duck.tomato = true
	assert_true(leaves.visible)
	assert_false(hat.visible, "the leaves take the hat's place")
	assert_eq(duck.model_mesh.get_surface_override_material(0), duck.tomato_skin)
	assert_eq(duck.model_mesh.get_surface_override_material(1), duck.tomato_beak)
	assert_null(duck.model_mesh.get_surface_override_material(3), "the eyes stay as they are")
	duck.tomato = false
	assert_false(leaves.visible)
	assert_true(hat.visible, "and the hat comes back")
	assert_null(duck.model_mesh.get_surface_override_material(0))


func test_the_leaves_take_the_mouse_but_not_as_high_as_the_hat() -> void:
	assert_eq(Pet.reach_for(false, false, 60.0, 26.0), 0.0)
	assert_eq(Pet.reach_for(true, false, 60.0, 26.0), 60.0)
	assert_eq(Pet.reach_for(true, true, 60.0, 26.0), 26.0)
	assert_eq(Pet.reach_for(false, true, 60.0, 26.0), 26.0)
