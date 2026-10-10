extends GutTest
## The phone's own brain, for when there is no PC: its sentences, what it says aloud, the prompt
## Gemini Nano gets, and, with DUCK_LLM_TESTS=1 and NobodyWho fetched, a real answer from a small model.

const MIND_ROOT: String = "user://test_local_brain"


func after_all() -> void:
	_remove(ProjectSettings.globalize_path(MIND_ROOT))


func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_remove(folder.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func test_whole_sentences_go_out_as_they_end() -> void:
	var found: Array = LocalBrain.whole_sentences("Hi there! How are", 0)
	assert_eq(found[0], PackedStringArray(["Hi there!"]))
	assert_eq(found[1], 9)
	found = LocalBrain.whole_sentences("Hi there! How are you? I'm a duck.", 9)
	assert_eq(found[0], PackedStringArray(["How are you?"]), "the last one waits for what follows it")
	assert_eq(LocalBrain.whole_sentences("It says \"quack.\" Then", 0)[0], PackedStringArray(["It says \"quack.\""]), "a closing quote stays with its sentence")


func test_what_is_said_has_no_tags_emoji_or_markdown() -> void:
	assert_eq(LocalBrain.spoken("My favorite color is the rainbow! 🎨"), "My favorite color is the rainbow!")
	assert_eq(LocalBrain.spoken("**Quack!** [remember: likes ducks] Hi."), "Quack! Hi.")
	assert_eq(LocalBrain.spoken("Ducks 🦆🦆 rule"), "Ducks rule")


func test_gemini_nano_gets_one_prompt_ending_where_the_duck_answers() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "hi"}, {"role": "assistant", "content": "Hello!"}]
	var prompt: String = LocalBrain.nano_prompt("You are a duck.", history, "how are you?")
	assert_eq(prompt, "You are a duck.\n\nUser: hi\nDuck: Hello!\nUser: how are you?\nDuck:")


func test_the_download_is_watched_by_the_file_it_writes() -> void:
	assert_eq(LocalBrain.model_label("Qwen_Qwen3.5-2B-GGUF"), "Qwen 3.5 2B")
	assert_eq(LocalBrain.model_label("Google_Gemma4-E4B-GGUF"), "Gemma 4 E4B")
	var folder: String = ProjectSettings.globalize_path(MIND_ROOT).path_join("models/NobodyWho/Qwen_Qwen3.5-2B-GGUF")
	DirAccess.make_dir_recursive_absolute(folder)
	assert_eq(LocalBrain.partial_download(ProjectSettings.globalize_path(MIND_ROOT).path_join("models")), {}, "nothing downloading")
	var part: FileAccess = FileAccess.open(folder.path_join("Qwen_Qwen3.5-2B-Q4_K_M.gguf.abc123.part"), FileAccess.WRITE)
	part.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
	part.close()
	assert_eq(LocalBrain.partial_download(ProjectSettings.globalize_path(MIND_ROOT).path_join("models")), {"model": "Qwen 3.5 2B", "bytes": 5})
	var models: String = ProjectSettings.globalize_path(MIND_ROOT).path_join("models")
	assert_eq(LocalBrain.newest_model_file(models), "", "a part file is not a model yet")
	DirAccess.rename_absolute(folder.path_join("Qwen_Qwen3.5-2B-Q4_K_M.gguf.abc123.part"), folder.path_join("Qwen_Qwen3.5-2B-Q4_K_M.gguf"))
	var found: String = LocalBrain.newest_model_file(models)
	assert_eq(found, folder.path_join("Qwen_Qwen3.5-2B-Q4_K_M.gguf"), "once downloaded it is the duck's model from then on")
	assert_eq(LocalBrain.model_label(found.get_base_dir().get_file()), "Qwen 3.5 2B", "and the Stats tab names it")


func test_only_the_model_in_use_is_kept() -> void:
	var models: String = ProjectSettings.globalize_path(MIND_ROOT).path_join("prune/models")
	var files: Dictionary = {
		"NobodyWho/Qwen_Qwen3.5-2B-GGUF/Qwen_Qwen3.5-2B-Q4_K_M.gguf": 3,
		"NobodyWho/Qwen_Qwen3.5-4B-GGUF/Qwen_Qwen3.5-4B-Q4_K_M.gguf": 5,
		"NobodyWho/Google_Gemma4-E2B-GGUF/gemma.gguf.x1y2.part": 2,
		"NobodyWho/Qwen_Qwen3.5-4B-GGUF/notes.txt": 1,
	}
	for relative: String in files:
		DirAccess.make_dir_recursive_absolute(models.path_join(relative).get_base_dir())
		var file: FileAccess = FileAccess.open(models.path_join(relative), FileAccess.WRITE)
		file.store_buffer(PackedByteArray([0, 0, 0, 0, 0]).slice(0, files[relative]))
		file.close()
	var keep: String = models.path_join("NobodyWho/Qwen_Qwen3.5-4B-GGUF/Qwen_Qwen3.5-4B-Q4_K_M.gguf")
	assert_eq(LocalBrain.prune_models(models, keep), 5, "the old 2B and the unfinished download")
	assert_true(FileAccess.file_exists(keep), "the model in use stays")
	assert_true(FileAccess.file_exists(models.path_join("NobodyWho/Qwen_Qwen3.5-4B-GGUF/notes.txt")), "and anything that is not a model")
	assert_false(DirAccess.dir_exists_absolute(models.path_join("NobodyWho/Qwen_Qwen3.5-2B-GGUF")), "an emptied folder goes")
	assert_false(DirAccess.dir_exists_absolute(models.path_join("NobodyWho/Google_Gemma4-E2B-GGUF")))


func test_a_model_named_by_path_is_found_in_the_cache_and_named() -> void:
	var path: String = "hf://NobodyWho/Google_Gemma4-E2B-GGUF/gemma-4-E2B-it-Q4_K_M.gguf"
	assert_eq(LocalBrain.cached_path("/cache/models", path), "/cache/models/NobodyWho/Google_Gemma4-E2B-GGUF/gemma-4-E2B-it-Q4_K_M.gguf", "kept only it when the others go")
	assert_eq(LocalBrain.cached_path("/cache/models", "res://model.gguf"), "res://model.gguf")
	assert_eq(LocalBrain.model_label(path.get_base_dir().get_file()), "Gemma 4 E2B")
	var scene: SceneState = (load("res://scenes/remote.tscn") as PackedScene).get_state()
	var found: String = ""
	for i: int in scene.get_node_count():
		if scene.get_node_name(i) == &"LocalBrain":
			for p: int in scene.get_node_property_count(i):
				if scene.get_node_property_name(i, p) == &"model_path":
					found = scene.get_node_property_value(i, p)
	assert_eq(found, path, "the phone app asks for Gemma 4 E2B, Gemini Nano 4's open sibling")


func test_every_setup_names_an_engine_a_chip_and_a_model() -> void:
	var ids: Array[String] = []
	for setup: Dictionary in LocalBrain.SETUPS:
		assert_false(setup["id"] in ids, "ids are unique: %s" % setup["id"])
		ids.append(setup["id"])
		assert_has(["NobodyWho", "LiteRT-LM", "Gemini Nano"], setup["engine"])
		if setup["engine"] == "LiteRT-LM":
			assert_has(["CPU", "GPU"], setup["backend"])
			assert_true(str(setup["model"]).ends_with(".litertlm"), setup["id"])
		elif setup["engine"] == "NobodyWho":
			assert_true(str(setup["model"]).begins_with("hf://NobodyWho/") and str(setup["model"]).ends_with(".gguf"), setup["id"])
	assert_eq(LocalBrain.setup_for("litertlm-gemma4-e2b-gpu")["backend"], "GPU")
	assert_eq(LocalBrain.setup_for("auto"), {})
	var brain: LocalBrain = LocalBrain.new()
	assert_eq(brain.auto_setups, PackedStringArray(["litertlm-gemma4-e2b-gpu", "litertlm-gemma4-e2b-cpu"]), "Auto: Gemma 4 E2B on the GPU, then the same file on the CPU (BENCHMARKS.md)")
	assert_eq(LocalBrain.setup_for(brain.auto_setups[0])["model"], LocalBrain.setup_for(brain.auto_setups[1])["model"], "so falling back downloads nothing more")
	brain.free()
	assert_eq(LocalBrain.hf_url("hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm"), "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")
	assert_eq(LocalBrain.litert_path("/cache/litertlm", "hf://litert-community/repo/model.litertlm"), "/cache/litertlm/litert-community/repo/model.litertlm")


func test_an_answer_is_timed_from_the_line_to_its_first_word_sentence_and_end() -> void:
	var found: Dictionary = LocalBrain.answer_metrics(10.0, 10.5, 11.25, 13.0, 2, 26, 120, {})
	assert_eq(found, {"turn": 2, "total_s": 3.0, "chars": 120, "pieces": 26, "first_word_s": 0.5, "decode_tps": 10.0, "first_sentence_s": 1.25})
	found = LocalBrain.answer_metrics(0.0, 0.2, 0.0, 1.0, 1, 3, 10, {"decode_tps": 31.25, "native_ttft_s": 0.18})
	assert_eq(found["decode_tps"], 31.25, "LiteRT-LM's own count wins")
	assert_eq(found["native_ttft_s"], 0.18)
	assert_false(found.has("first_sentence_s"), "no sentence ended before the answer did")
	assert_false(LocalBrain.answer_metrics(0.0, 0.0, 0.0, 1.0, 1, 0, 0, {}).has("first_word_s"), "nothing came")


func test_clearing_deletes_every_model_and_what_was_compiled() -> void:
	var root: String = ProjectSettings.globalize_path(MIND_ROOT).path_join("clear")
	var files: Array[String] = ["nobodywho/NobodyWho/repo/model.gguf", "litertlm/litert-community/repo/model.litertlm", "litertlm/litert-community/repo/model.litertlm.part", "litertlm/compiled/kernel.bin", "litertlm/readme.txt"]
	for relative: String in files:
		DirAccess.make_dir_recursive_absolute(root.path_join(relative).get_base_dir())
		FileAccess.open(root.path_join(relative), FileAccess.WRITE).store_buffer(PackedByteArray([0, 0]))
	assert_eq(LocalBrain.clear_models(PackedStringArray([root.path_join("nobodywho"), root.path_join("litertlm")])), 8)
	assert_false(DirAccess.dir_exists_absolute(root.path_join("nobodywho")))
	assert_false(DirAccess.dir_exists_absolute(root.path_join("litertlm/compiled")))
	assert_false(DirAccess.dir_exists_absolute(root.path_join("litertlm/litert-community")))
	assert_true(FileAccess.file_exists(root.path_join("litertlm/readme.txt")), "anything that is not a model stays")


func test_a_setup_off_its_phone_fails_and_is_recorded() -> void:
	if Engine.has_singleton("LiteRtLm"):
		pass_test("on a phone it would download")
		return
	var brain: LocalBrain = LocalBrain.new()
	brain.setup_id = "litertlm-gemma4-e2b-cpu"
	brain.metrics_path = MIND_ROOT + "/metrics.jsonl"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MIND_ROOT))
	add_child_autofree(brain)
	brain.start()
	assert_false(brain.is_starting())
	assert_string_contains(brain.status, "LiteRT-LM needs the GeminiNano Android plugin")
	var entries: Array[Dictionary] = LlmMetrics.read(brain.metrics_path)
	assert_eq(entries.size(), 1)
	assert_eq(entries[0]["kind"], "failed")
	assert_eq(entries[0]["label"], "Gemma 4 E2B, LiteRT-LM CPU")
	assert_eq(entries[0]["backend"], "CPU")
	brain.setup_id = "gemini-nano"
	brain.start()
	if not Engine.has_singleton("GeminiNano"):
		assert_string_contains(brain.status, "needs the GeminiNano Android plugin", "a setup has nothing to fall back on")


func test_with_no_model_engine_it_says_so_rather_than_failing() -> void:
	var brain: LocalBrain = LocalBrain.new()
	add_child_autofree(brain)
	assert_false(brain.is_ready())
	assert_false(brain.ask("hi"), "nothing to ask yet")
	if not ClassDB.class_exists(&"NobodyWhoChat") and not Engine.has_singleton("GeminiNano"):
		brain.start()
		assert_string_contains(brain.status, "No model can run on this phone")


func test_a_small_model_answers_in_sentences_with_the_ducks_mind() -> void:
	if OS.get_environment("DUCK_LLM_TESTS") != "1" or not ClassDB.class_exists(&"NobodyWhoChat"):
		pass_test("set DUCK_LLM_TESTS=1, with NobodyWho fetched, to load a real model")
		return
	var mind: Mind = Mind.new()
	mind.root = MIND_ROOT
	add_child_autofree(mind)
	var brain: LocalBrain = LocalBrain.new()
	brain.mind = mind
	brain.model_path = "hf://NobodyWho/Qwen_Qwen3-0.6B-GGUF/Qwen_Qwen3-0.6B-Q4_K_M.gguf"
	add_child_autofree(brain)
	watch_signals(brain)
	brain.start()
	await wait_until(brain.is_ready, 300.0)
	assert_true(brain.is_ready(), brain.status)
	assert_eq(brain.engine, "NobodyWho")
	assert_true(brain.ask("Hi duck! What's your favourite colour?"))
	await wait_for_signal(brain.replied, 120.0)
	assert_signal_emitted(brain, "replied")
	var reply: String = get_signal_parameters(brain, "replied")[0]
	assert_false(reply.is_empty())
	assert_signal_emitted(brain, "sentence", "it streams sentence by sentence")
	assert_eq(mind.recent(2).map(func(m: Dictionary) -> String: return m["role"]), ["user", "assistant"], "the exchange is in the duck's own conversation")
	gut.p("The duck said: " + reply)
