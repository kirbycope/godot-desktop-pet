extends GutTest

## llama-server's /v1/models (version 0.6.0, build 11429) serving qwen2.5-14b with --alias, its
## Ollama-style "models" list left out.
const LLAMA_MODELS: String = '{"object":"list","data":[{"id":"qwen2.5-14b","aliases":["qwen2.5-14b"],"tags":[],"object":"model","architecture":{"input_modalities":["text"],"output_modalities":["text"]},"created":1791431385,"owned_by":"llamacpp","meta":{"vocab_type":2,"n_vocab":152064,"n_ctx":6144,"n_ctx_train":32768,"n_embd":5120,"n_params":14770033664,"size":8982142976,"ftype":"Q4_K - Medium"}}]}'


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


func test_only_a_run_from_the_editor_keeps_the_model_loaded() -> void:
	assert_true(Brain.keeps_model(true, true))
	assert_false(Brain.keeps_model(true, false), "run on its own, it frees the memory")
	assert_false(Brain.keeps_model(false, true), "unless told not to")


func test_a_tag_is_never_shown_or_spoken_even_half_written() -> void:
	assert_eq(Brain.speakable("Hello! [remember: user likes ducks] Bye."), "Hello! Bye.")
	assert_eq(Brain.speakable("Hello! [remem"), "Hello! ", "held back until it closes")
	assert_eq(Brain.speakable("Look at names[0] here."), "Look at names[0] here.", "a closed bracket is just text")


func test_a_sentence_is_kept_unless_it_repeats_or_echoes_instructions() -> void:
	var said: PackedStringArray = ["I love the sea, it looks enormous for a bath."]
	assert_eq(Brain.keep_sentence("Pancakes are great.", said, PackedStringArray()), "Pancakes are great.")
	assert_eq(Brain.keep_sentence("I love the sea, it looks enormous for a bath.", said, PackedStringArray()), "", "a repeat")
	assert_eq(Brain.keep_sentence("Are you a beach person?", said, PackedStringArray(["Are you a beach person?"])), "", "a question asked lately")
	assert_eq(Brain.keep_sentence("1.", said, PackedStringArray()), "", "no words")
	assert_eq(Brain.keep_sentence("If they teach you a way of doing something to use again, end it with a skill tag.", said, PackedStringArray()), "", "its instructions")


func test_debugging_gets_a_slim_prompt_without_the_personality() -> void:
	var brain: Brain = Brain.new()
	var slim: String = brain.system_prompt(true)
	assert_false("Things you know for sure" in slim)
	assert_string_contains(slim, "rubber duck for debugging")
	assert_string_contains(slim, brain.sight_rules)
	brain.free()


func test_hints_and_the_reminder_wrap_the_users_line() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "why?"}]
	var content: String = Brain.with_screen(history, "code", Brain.DEBUG_REMINDER, PackedStringArray(["`$Sprit` appears only here"]))[-1]["content"]
	assert_string_contains(content, "Things to check, from a quick look done in code")
	assert_string_contains(content, "- `$Sprit` appears only here")
	assert_lt(content.find("Things to check"), content.find("The user says: why?"), "their line comes after, last but for the reminder")
	assert_string_ends_with(content, Brain.DEBUG_REMINDER)
	assert_eq(Brain.user_lines(history), "why?")


func test_the_server_starts_without_handing_its_daemon_our_stdout() -> void:
	var windows: PackedStringArray = Brain.server_start_command("foundry", 39839, "Windows")
	assert_eq(windows, PackedStringArray(["foundry", "server", "start", "--port", "39839", "--idle-timeout", "0"]))
	var mac: PackedStringArray = Brain.server_start_command("/opt/homebrew/bin/foundry", 39839, "macOS")
	assert_eq(mac, PackedStringArray(["/bin/sh", "-c", "exec '/opt/homebrew/bin/foundry' server start --port 39839 --idle-timeout 0 </dev/null >/dev/null 2>&1"]))
	assert_string_contains(Brain.server_start_command("/a b/it's/foundry", 1, "macOS")[2], "'/a b/it'\\''s/foundry'", "a quote in the path is escaped")


func test_starting_the_server_returns_while_its_daemon_runs_on() -> void:
	# A stand-in for `foundry server start` on macOS: it leaves a child running that holds stdout.
	if OS.get_name() == "Windows":
		pass_test("Windows starts the server directly")
		return
	var fake: String = ProjectSettings.globalize_path("user://fake_foundry.sh")
	var file: FileAccess = FileAccess.open(fake, FileAccess.WRITE)
	file.store_string("#!/bin/sh\nsleep 20 &\nexit 0\n")
	file.close()
	FileAccess.set_unix_permissions(fake, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER | FileAccess.UNIX_EXECUTE_OWNER)
	var command: PackedStringArray = Brain.server_start_command(fake, 39839, OS.get_name())
	var started: int = Time.get_ticks_msec()
	assert_eq(OS.execute(command[0], command.slice(1)), 0)
	assert_lt(Time.get_ticks_msec() - started, 5000, "OS.execute did not wait for the daemon")


func test_only_a_mac_runs_chat_on_llama_cpp() -> void:
	var models: Dictionary = {"qwen2.5-14b": "bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M"}
	assert_eq(Brain.llama_model(models, "qwen2.5-14b", "macOS"), "bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M")
	assert_eq(Brain.llama_model(models, "qwen2.5-14b", "Windows"), "", "Foundry has the NPU, CUDA and TensorRT builds there")
	assert_eq(Brain.llama_model(models, "qwen3-4b", "macOS"), "", "a model with no GGUF mapped stays on Foundry")


func test_every_chat_model_the_duck_prefers_has_a_gguf_for_the_mac() -> void:
	var brain: Brain = load("res://scripts/brain.gd").new()
	var prefs: ModelPreferences = load("res://resources/model_preferences.tres")
	for alias: String in prefs.chat + prefs.mac_chat:
		if not "*" in alias:
			assert_true(brain.llama_models.has(alias), "%s has a GGUF build in Brain.llama_models" % alias)
	brain.free()


func test_llama_server_runs_in_the_background_on_the_foundry_alias() -> void:
	var command: PackedStringArray = Brain.llama_command("/opt/homebrew/bin/llama-server", "bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M", "qwen2.5-14b", 39841, 16384, "/Users/me/Library/Application Support/Godot/app_userdata/Desktop Pet/llama-server.log")
	assert_eq(command.size(), 3, "Godot drops arguments after sh -c's script")
	assert_eq(command[0], "/bin/sh")
	assert_eq(command[2], "exec '/opt/homebrew/bin/llama-server' -hf 'bartowski/Qwen2.5-14B-Instruct-GGUF:Q4_K_M' --alias 'qwen2.5-14b' --host 127.0.0.1 --port 39841 -c 16384 -np 3 -ngl 99 --jinja </dev/null >'/Users/me/Library/Application Support/Godot/app_userdata/Desktop Pet/llama-server.log' 2>&1")
	assert_eq(Brain.shell_quoted("it's"), "'it'\\''s'")


func test_llama_server_lists_its_model_under_the_alias() -> void:
	# What llama-server's /v1/models printed serving qwen2.5-14b with --alias.
	var data: Variant = Brain.parse_json(LLAMA_MODELS)
	assert_eq(Brain.pick_model(data["data"], "qwen2.5-14b"), "qwen2.5-14b")


func test_a_short_line_said_word_for_word_before_is_dropped() -> void:
	var said: PackedStringArray = ["cool! I love that. Ducks see ultraviolet."]
	assert_eq(Brain.keep_sentence("I love that.", said, PackedStringArray()), "", "too few words to compare, but the same words")
	assert_eq(Brain.keep_sentence("Cool!", said, PackedStringArray()), "")
	assert_eq(Brain.keep_sentence("I love pancakes.", said, PackedStringArray()), "I love pancakes.")
	assert_eq(Brain.plain_words("Hi!  I love it, really."), "hi i love it really")


func test_the_history_grows_then_is_cut_back_so_its_opening_stays_put() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}]
	for i: int in 12:
		history.append({"role": "user" if i % 2 == 0 else "assistant", "content": str(i)})
	assert_eq(Brain.settled(history, 6), history, "twelve is twice six: left alone")
	history.append({"role": "user", "content": "12"})
	var cut: Array[Dictionary] = Brain.settled(history, 6)
	assert_eq(cut.map(func(m: Dictionary) -> String: return m["content"]), ["s", "8", "9", "10", "11", "12"], "cut back, starting with theirs")


func test_a_sentence_leaning_on_a_dropped_one_goes_with_it() -> void:
	assert_true(Brain.leans_on_the_last("That means raindrops look magical to them."))
	assert_true(Brain.leans_on_the_last("So it never got a value."))
	assert_false(Brain.leans_on_the_last("Rain is lovely."))
	assert_false(Brain.leans_on_the_last("Thatcher was a prime minister."), "a whole word only")


func test_an_answer_never_starts_on_but() -> void:
	assert_eq(Brain.without_leading_conjunction("But did you know that ducks have webbed feet?"), "Did you know that ducks have webbed feet?")
	assert_eq(Brain.without_leading_conjunction("And, honestly, I love ponds."), "Honestly, I love ponds.")
	assert_eq(Brain.without_leading_conjunction("Butter is lovely."), "Butter is lovely.", "a whole word only")
	assert_eq(Brain.without_leading_conjunction("Ponds are great."), "Ponds are great.")


func test_good_morning_after_a_bug_is_not_more_debugging() -> void:
	assert_false(Brain.is_debugging("good morning!", "why does this crash?", ""), "a greeting ends the thread")
	assert_false(Brain.is_debugging("Thanks, that fixed it", "why does this crash?", ""), "so does a thank-you")
	assert_true(Brain.is_debugging("hi, why does this crash?", "", ""), "a greeting with a bug in it is still a bug")
	assert_true(Brain.is_debugging("they spawn fine but don't move", "my enemies are stuck", ""), "the thread goes on")
	assert_eq(Brain.DEBUG_THREAD_MS, 300000, "for five minutes")
