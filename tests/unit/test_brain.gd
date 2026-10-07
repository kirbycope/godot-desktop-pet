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
	assert_string_ends_with(sent[3]["content"], "The user says: why is this null?")
	assert_eq(sent[1]["content"], "first", "older lines are not given the screen")
	assert_eq(history[3]["content"], "why is this null?", "the kept history is not changed")


func test_an_unreadable_screen_is_said_plainly() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "what do you see?"}]
	assert_string_starts_with(Brain.with_screen(history, "  ")[0]["content"], "No text could be read")


func test_the_model_is_told_it_only_sees_ocr_text() -> void:
	var brain: Brain = Brain.new()
	assert_string_contains(brain.sight_rules, "OCR")
	assert_string_contains(brain.sight_rules, "Never describe anything that is not in that text")
	brain.free()


func test_chat_body_is_openai_shaped() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "hi"}]
	var body: Dictionary = Brain.chat_body("m", history, 99)
	assert_eq(body["model"], "m")
	assert_eq(body["messages"], history)
	assert_eq(body["max_tokens"], 99)
