extends GutTest
## The duck's tabs, the same scene in the PC's bubble and the phone app: the chat's bubbles and its
## past conversations, the voice list, and the Duck tab.

var tabs: DuckTabs


func before_each() -> void:
	tabs = (load("res://scenes/duck_tabs.tscn") as PackedScene).instantiate()
	add_child_autofree(tabs)
	watch_signals(tabs)


func _bubbles() -> Array:
	var said: Array = []
	for row: Node in tabs.messages_box.get_children():
		if row.is_queued_for_deletion():
			continue
		if row is Label:
			said.append(["note", (row as Label).text])
		else:
			var bubble: PanelContainer = row.get_child(0)
			said.append([str(bubble.theme_type_variation), (bubble.get_child(0) as Label).text])
	return said


func test_the_tabs_are_chat_pomodoro_stats_settings_and_duck() -> void:
	var titles: PackedStringArray = PackedStringArray()
	for i: int in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(i))
	assert_eq(titles, PackedStringArray(["Chat", "Pomodoro", "Stats", "Settings", "Duck"]))


func test_your_line_then_the_answer_growing_in_its_own_bubble() -> void:
	tabs.begin_answer("why is this null?", "Looking at your screen...")
	assert_eq(_bubbles(), [["YourBubble", "why is this null?"], ["DuckBubble", "Looking at your screen..."]])
	tabs.set_answer("...")
	tabs.add_sentence("Let's see.")
	tabs.add_sentence("Line 4 reads x before it is set.")
	assert_eq(_bubbles()[1], ["DuckBubble", "Let's see. Line 4 reads x before it is set."], "the sentences join the one bubble")
	tabs.add_note("Remembered: you use Godot")
	assert_eq(_bubbles()[2], ["note", "Remembered: you use Godot"])
	tabs.say("Quack!")
	assert_eq(_bubbles()[3], ["DuckBubble", "Quack!"], "a greeting is a bubble of its own")


func test_a_conversation_shows_its_lines_and_past_ones_can_be_picked() -> void:
	tabs.show_conversation([{"role": "user", "content": "hi"}, {"role": "assistant", "content": "Hello!"}, {"role": "system", "content": "never shown"}])
	await get_tree().process_frame
	assert_eq(_bubbles(), [["YourBubble", "hi"], ["DuckBubble", "Hello!"]])
	tabs.past_button.button_pressed = true
	assert_signal_emitted(tabs, "past_pressed")
	tabs.show_past([{"id": "a", "when": "2026-10-09 09:00", "title": "Good morning"}, {"id": "b", "when": "2026-10-08 20:00", "title": "A bug"}], "a")
	assert_true(tabs.past_list.visible)
	assert_false(tabs.conversation.visible, "the list stands in for the conversation")
	assert_eq(tabs.past_list.get_item_text(0), "2026-10-09 09:00   Good morning   (now)")
	tabs.past_list.item_selected.emit(1)
	assert_signal_emitted_with_parameters(tabs, "conversation_chosen", ["b"])
	assert_false(tabs.past_list.visible, "and goes again once one is picked")


func test_sending_clears_the_box_and_only_when_it_may() -> void:
	tabs.send_button.disabled = false
	tabs.input.text = "  hello  "
	tabs.send_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "line_sent", ["hello"])
	assert_eq(tabs.input.text, "")
	tabs.send_button.disabled = true
	tabs.input.text = "again"
	tabs.input.text_submitted.emit("again")
	assert_signal_emit_count(tabs, "line_sent", 1, "not while it is thinking")


func test_the_voice_list_has_a_download_entry_until_the_natural_voices_are_in() -> void:
	var available: Array = [{"id": "sys", "name": "Zira", "language": "en_US"}, {"id": "kokoro:3", "name": "Heart", "kokoro": true}]
	var items: Array[Dictionary] = DuckTabs.voice_items(available, false, false, "Download natural voices (352 MB)")
	assert_eq(items.map(func(i: Dictionary) -> String: return str(i.get("id", "--"))), ["sys", "--", DuckTabs.DOWNLOAD_KOKORO, "kokoro:3"])
	assert_true(items[3]["disabled"], "greyed out until downloaded")
	tabs.show_voices(items, "sys", "Speaking as: Zira")
	assert_eq(tabs.selected_voice(), "sys")
	assert_false(tabs.apply_button.disabled)
	tabs.voices.select(2)
	tabs.voices.item_selected.emit(2)
	assert_signal_emitted_with_parameters(tabs, "voice_selected", [DuckTabs.DOWNLOAD_KOKORO])
	assert_true(tabs.apply_button.disabled, "the download entry is not a voice")
	tabs.show_voice_note("Downloading natural voices: 120 of 352 MB", true)
	assert_eq(tabs.voices.get_item_text(2), "Downloading natural voices: 120 of 352 MB")
	var ready: Array[Dictionary] = DuckTabs.voice_items(available, true, false, "")
	assert_false(ready.any(func(i: Dictionary) -> bool: return i.get("id", "") == DuckTabs.DOWNLOAD_KOKORO))
	assert_false(ready[-1]["disabled"])


func test_the_duck_tab_says_its_name_hat_and_memories_and_passes_on_changes() -> void:
	tabs.show_duck("Ducky", PackedStringArray(["likes Godot", "has a cat"]))
	tabs.show_hat(true)
	assert_eq(tabs.name_field.text, "Ducky")
	assert_eq(tabs.memory_list.item_count, 2)
	assert_true(tabs.hat_box.button_pressed)
	assert_signal_not_emitted(tabs, "hat_toggled", "showing it is not changing it")
	tabs.name_field.text = "Quackers"
	tabs.name_field.text_submitted.emit("Quackers")
	assert_signal_emitted_with_parameters(tabs, "name_saved", ["Quackers"])
	tabs.memory_list.select(1)
	tabs.get_node("Duck/Buttons/Forget").pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "memory_forgotten", [1])


func test_the_stats_tab_stops_and_starts_the_model() -> void:
	assert_true(tabs.model_button.disabled, "nothing to stop before a model runs")
	tabs.show_model(true, false)
	assert_eq(tabs.model_button.text, "Stop the model")
	assert_false(tabs.model_button.disabled)
	tabs.model_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "model_toggled", [false])
	tabs.show_model(false, true)
	assert_eq(tabs.model_button.text, "Start the model")
	tabs.model_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "model_toggled", [true])
	tabs.show_model(false, false)
	assert_true(tabs.model_button.disabled, "grey while one is loading")


func test_the_stats_tab_picks_a_setup_and_runs_the_benchmark() -> void:
	tabs.show_setups([{"id": "auto", "label": "Auto"}, {"id": "litertlm-gemma4-e2b-gpu", "label": "Gemma 4 E2B, LiteRT-LM GPU"}], "litertlm-gemma4-e2b-gpu")
	assert_eq(tabs.setup_list.item_count, 2)
	assert_eq(tabs.setup_list.selected, 1, "the setup in use is the one picked")
	tabs.setup_list.item_selected.emit(0)
	assert_signal_emitted_with_parameters(tabs, "setup_chosen", ["auto"])
	tabs.show_bench(false)
	tabs.bench_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "bench_toggled", [true])
	tabs.show_bench(true)
	assert_eq(tabs.bench_button.text, "Stop the benchmark")
	assert_true(tabs.setup_list.disabled, "no picking while it runs")
	tabs.bench_button.pressed.emit()
	assert_signal_emitted_with_parameters(tabs, "bench_toggled", [false])


func test_a_bubble_is_as_wide_as_its_text_up_to_the_room() -> void:
	assert_eq(DuckTabs.bubble_width(120.4, 600.0), 123.0)
	assert_eq(DuckTabs.bubble_width(900.0, 600.0), 600.0)
