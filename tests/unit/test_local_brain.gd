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
