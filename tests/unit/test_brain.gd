extends GutTest


func test_device_comes_from_the_variant_suffix() -> void:
	assert_eq(Brain.device_of("qwen2.5-1.5b-instruct-trtrtx-gpu:2"), "GPU")
	assert_eq(Brain.device_of("qwen2.5-1.5b-instruct-qnn-npu"), "NPU")
	assert_eq(Brain.device_of("Phi-4-mini-instruct-generic-cpu:4"), "CPU")
	assert_eq(Brain.device_of("something-unexpected"), "CPU")


func test_picks_the_loaded_model_by_its_parent_alias() -> void:
	# The shape CLI 0.10.3 returns from /v1/models.
	var models: Array = [
		{"id": "phi-4-mini-instruct-cuda-gpu", "parent": "phi-4-mini"},
		{"id": "qwen2.5-1.5b-instruct-trtrtx-gpu", "parent": "qwen2.5-1.5b"},
	]
	assert_eq(Brain.pick_model(models, "qwen2.5-1.5b"), "qwen2.5-1.5b-instruct-trtrtx-gpu")
	assert_eq(Brain.pick_model(models, "qwen3-4b"), "")
	assert_eq(Brain.pick_model([], "qwen2.5-1.5b"), "")


func test_parses_a_real_chat_completion() -> void:
	var body: String = '{"model":"qwen2.5-1.5b-instruct-trtrtx-gpu","choices":[{"delta":{"role":"assistant","content":"I am Bolt."},"message":{"role":"assistant","content":" I am Bolt. ","tool_calls":[]},"index":0,"finish_reason":"stop"}],"object":"chat.completion"}'
	assert_eq(Brain.parse_reply(body), "I am Bolt.")


func test_bad_responses_parse_to_nothing() -> void:
	assert_eq(Brain.parse_reply(""), "")
	assert_eq(Brain.parse_reply("{}"), "")
	assert_eq(Brain.parse_reply('{"choices": []}'), "")
	assert_eq(Brain.parse_reply("not json"), "")


func test_history_keeps_the_system_prompt_and_the_latest_messages() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}]
	for i: int in 20:
		history.append({"role": "user", "content": str(i)})
	var kept: Array[Dictionary] = Brain.trimmed(history, 4)
	assert_eq(kept.size(), 5)
	assert_eq(kept[0]["role"], "system")
	assert_eq(kept[1]["content"], "16")
	assert_eq(kept[4]["content"], "19")


func test_short_history_is_left_alone() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "hi"}]
	assert_eq(Brain.trimmed(history, 4), history)


func test_screen_text_goes_with_the_latest_line_only() -> void:
	var history: Array[Dictionary] = [
		{"role": "system", "content": "s"},
		{"role": "user", "content": "first"},
		{"role": "assistant", "content": "a"},
		{"role": "user", "content": "why is this null?"},
	]
	var sent: Array[Dictionary] = Brain.with_screen(history, "var x = null\nprint(x.name)")
	assert_string_contains(sent[3]["content"], "print(x.name)")
	assert_string_contains(sent[3]["content"], "The user says: why is this null?")
	assert_eq(sent[1]["content"], "first", "older lines are not given the screen")
	assert_eq(history[3]["content"], "why is this null?", "the kept history is not changed")


func test_an_unreadable_screen_is_said_plainly() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "what do you see?"}]
	assert_string_starts_with(Brain.with_screen(history, "  ")[0]["content"], "No text could be read")


func test_the_model_is_told_it_only_sees_ocr_text() -> void:
	var brain: Brain = Brain.new()
	assert_string_contains(brain.sight_rules, "OCR")
	assert_string_contains(brain.sight_rules, "never describe anything that is not in that text")
	brain.free()


func test_chat_body_is_openai_shaped() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "hi"}]
	var body: Dictionary = Brain.chat_body("m", history, 99)
	assert_eq(body["model"], "m")
	assert_eq(body["messages"], history)
	assert_eq(body["max_tokens"], 99)
	assert_true(body.has("presence_penalty"), "chat discourages repeating itself")
	assert_false(Brain.chat_body("m", history, 99, true).has("frequency_penalty"), "code repeats its marks, so no penalties")


func test_a_model_counts_as_loaded_by_alias_or_build() -> void:
	# What `foundry model list --loaded -o json` printed with the duck's two models loaded.
	var loaded: Array = ModelPreferences.parse_catalog('{"models":[{"alias":"parakeet-tdt-0.6b-v2","id":"parakeet-tdt-0.6b-v2-cuda-gpu:1","type":"Speech"},{"alias":"qwen2.5-coder-7b","id":"qwen2.5-coder-7b-instruct-trtrtx-gpu:2","type":"Chat"}]}', "models")
	assert_true(Brain.is_loaded(loaded, "qwen2.5-coder-7b"))
	assert_true(Brain.is_loaded(loaded, "qwen2.5-coder-7b-instruct-trtrtx-gpu"), "a build id, without its version")
	assert_false(Brain.is_loaded(loaded, "phi-4-mini"))
	assert_false(Brain.is_loaded([], "qwen2.5-coder-7b"))


func test_loading_does_not_wait_on_the_load_command() -> void:
	# `foundry model load` can keep running after the model is up (CLI 0.10.3); the brain watches
	# the loaded list instead and gives up after a while.
	var source: String = (load("res://scripts/brain.gd") as GDScript).source_code
	assert_string_contains(source, '["model", "list", "--loaded", "-o", "json"]')
	assert_false('OS.execute(_foundry, ["model", "load"' in source)
	assert_gt(Brain.LOAD_TIMEOUT_SECONDS, 60)


func test_the_prompt_carries_the_last_three_exchanges() -> void:
	var brain: Brain = load("res://scripts/brain.gd").new()
	assert_eq(brain.max_history, 6, "three of yours, three of the duck's")
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}]
	for i: int in 10:
		history.append({"role": "user" if i % 2 == 0 else "assistant", "content": str(i)})
	var kept: Array[Dictionary] = Brain.trimmed(history, brain.max_history)
	assert_eq(kept.map(func(m: Dictionary) -> String: return m["content"]), ["s", "4", "5", "6", "7", "8", "9"])
	brain.free()


func test_what_the_duck_says_on_its_own_joins_the_conversation() -> void:
	var source: String = (load("res://scripts/pet.gd") as GDScript).source_code
	assert_string_contains(source, "brain.note_said(_greeting)")
	var brain_source: String = (load("res://scripts/brain.gd") as GDScript).source_code
	assert_string_contains(brain_source, "messages.append_array(mind.recent(max_history))", "picks up where it left off")


func test_greetings_open_a_conversation_not_a_debugging_session() -> void:
	var pet: Pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	for greeting: String in pet.greetings:
		for word: String in ["debug", "broken", "code", "wrong"]:
			assert_false(word in greeting.to_lower(), "%s in %s" % [word, greeting])
	pet.free()
	var brain: Brain = load("res://scripts/brain.gd").new()
	assert_string_contains(brain.role, "Do not steer the talk towards code")
	brain.free()


func test_web_results_go_ahead_of_the_users_line() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "search for x"}]
	var sent: Array[Dictionary] = Brain.with_web(history, "Web search results: x")
	assert_string_starts_with(sent[-1]["content"], "Web search results: x")
	assert_string_ends_with(sent[-1]["content"], "search for x")
	assert_eq(history[-1]["content"], "search for x", "the kept history is untouched")
	assert_eq(Brain.with_web(history, ""), history, "nothing searched, nothing added")


func test_earlier_replies_are_the_ducks_latest() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "a"}, {"role": "assistant", "content": "one"}, {"role": "user", "content": "b"}, {"role": "assistant", "content": "two"}, {"role": "user", "content": "c"}]
	assert_eq(Brain.earlier_replies(history, 1), PackedStringArray(["two"]))
	assert_eq(Brain.earlier_replies(history, 5), PackedStringArray(["one", "two"]))


func test_the_fallback_is_not_the_one_just_said() -> void:
	assert_eq(Brain.fresh_fallback(PackedStringArray()), Brain.FALLBACKS[0])
	assert_eq(Brain.fresh_fallback(PackedStringArray([Brain.FALLBACKS[0]])), Brain.FALLBACKS[1])


func test_facts_are_pulled_from_search_results_as_lines() -> void:
	var results: Array[Dictionary] = [{"title": "Duck facts", "url": "https://example.org", "snippet": "Ducklings can swim within hours."}]
	var sent: Array[Dictionary] = Brain.facts_prompt(results)
	assert_string_contains(sent[-1]["content"], "Duck facts: Ducklings can swim within hours.")
	assert_eq(Brain.parse_facts("Here you go:\n- Ducklings can swim within hours of hatching.\n- Short.\n* A group of ducks on water is called a raft.\n- Three\n- Four is the fourth fact here.\n- Five is the fifth fact here."), PackedStringArray(["Ducklings can swim within hours of hatching.", "A group of ducks on water is called a raft.", "Four is the fourth fact here."]))
	assert_eq(Brain.parse_facts("NONE"), PackedStringArray())
	assert_eq(Brain.parse_facts("Ducks are mostly aquatic birds.\n2. Drakes are male ducks, hens female."), PackedStringArray(["Ducks are mostly aquatic birds.", "Drakes are male ducks, hens female."]), "no bullets, or numbers")


func test_debugging_gets_the_rubber_duck_reminder_and_small_talk_does_not() -> void:
	assert_true(Brain.is_debugging("why does this crash?", "", ""))
	assert_true(Brain.is_debugging("my average is wrong, it should be 90", "", ""))
	assert_true(Brain.is_debugging("what's going on here?", "", "Uncaught (in promise) TypeError: res.json is not a function"), "pointing at an error on screen")
	assert_true(Brain.is_debugging("After the wave I set get_tree().paused = true", "", ""), "code in the line")
	assert_true(Brain.is_debugging("The enemies spawn fine, they just don't move.", "I'm stuck, my enemies stop moving", ""), "still the same bug")
	assert_false(Brain.is_debugging("what's your favourite colour?", "hi", "func _ready() -> void:"), "an editor on screen is not a bug")
	assert_false(Brain.is_debugging("what's this?", "", "Weather: sunny"))
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "x"}]
	assert_string_ends_with(Brain.with_screen(history, "", Brain.DEBUG_REMINDER)[-1]["content"], Brain.DEBUG_REMINDER)


func test_the_earlier_line_is_the_users_message_before_the_last() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "first"}, {"role": "assistant", "content": "a"}, {"role": "user", "content": "second"}]
	assert_eq(Brain.earlier_user_line(history), "first")
	assert_eq(Brain.earlier_user_line(history.slice(0, 2)), "")
