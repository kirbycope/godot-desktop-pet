extends GutTest
## Model choice, run against the catalog `foundry model list -o json` printed on an RTX 4080 Laptop
## PC in October 2026 (tests/fixtures), so the names and sizes are real.

const GB: float = 1024.0

var prefs: ModelPreferences
var models: Array
var variants: Array


func before_each() -> void:
	prefs = load("res://resources/model_preferences.tres")
	models = ModelPreferences.parse_catalog(FileAccess.get_file_as_string("res://tests/fixtures/catalog_models.json"), "models")
	variants = ModelPreferences.parse_catalog(FileAccess.get_file_as_string("res://tests/fixtures/catalog_variants.json"), "variants")


func budgets(gpu_gb: float, system_gb: float) -> Dictionary:
	return {"gpu": gpu_gb * GB * prefs.memory_share, "npu": system_gb * GB * prefs.memory_share, "cpu": system_gb * GB * prefs.memory_share}


func test_the_catalog_fixture_parses() -> void:
	assert_eq(models.size(), 49)
	assert_eq(variants.size(), 148)
	assert_eq(ModelPreferences.parse_catalog("not json", "models"), [])


func test_this_pc_gets_the_7b_and_parakeet() -> void:
	var chosen: Dictionary = Brain.choose(prefs, models, variants, budgets(12.0, 32.0), "en", "")
	assert_eq(chosen["chat"], "qwen2.5-7b", "12 GB card: 14b (9 GB) does not fit in 70% beside speech")
	assert_eq(chosen["speech"], "parakeet-tdt-0.6b-v2")
	assert_string_contains(chosen["why"], "qwen2.5-7b, 5.5 GB on the GPU")


func test_a_bigger_card_gets_a_bigger_model() -> void:
	assert_eq(Brain.choose(prefs, models, variants, budgets(24.0, 64.0), "en", "")["chat"], "qwen2.5-14b")


func test_a_mac_starts_at_the_7b_where_the_14b_would_fit() -> void:
	# A 24 GB Mac: its unified memory fits the 14B, but reading the prompt is what keeps it quiet.
	assert_eq(Brain.choose(prefs, models, variants, budgets(24.0, 24.0), "en", "", "macOS")["chat"], "qwen2.5-7b")
	assert_eq(Brain.choose(prefs, models, variants, budgets(24.0, 24.0), "en", "", "Windows")["chat"], "qwen2.5-14b", "elsewhere the list is unchanged")
	assert_eq(Brain.choose(prefs, models, variants, budgets(4.0, 4.0), "en", "", "macOS")["chat"], "qwen2.5-1.5b", "a small Mac still falls through to what fits")


func test_an_empty_mac_list_uses_the_main_one() -> void:
	prefs = prefs.duplicate()
	prefs.mac_chat = PackedStringArray()
	assert_eq(prefs.chat_for("macOS"), prefs.chat)


func test_a_small_machine_gets_a_small_model() -> void:
	assert_eq(Brain.choose(prefs, models, variants, budgets(4.0, 8.0), "en", "")["chat"], "qwen2.5-1.5b", "phi-4-mini (3.6 GB) does not fit")


func test_the_coder_is_never_taken_over_a_general_model() -> void:
	var chosen: String = Brain.choose(prefs, models, variants, budgets(12.0, 32.0), "en", "")["chat"]
	assert_false(chosen.contains("coder"), "small talk with the coder repeats itself")


func test_an_npu_build_is_judged_against_system_memory() -> void:
	var npu_models: Array = [
		{"alias": "qwen2.5-coder-7b", "type": "Chat", "device": "Npu", "fileSizeMb": 4800},
		{"alias": "qwen2.5-coder-1.5b", "type": "Chat", "device": "Npu", "fileSizeMb": 1300},
		{"alias": "parakeet-tdt-0.6b-v2", "type": "Speech", "device": "Cpu", "fileSizeMb": 692},
	]
	assert_eq(Brain.choose(prefs, npu_models, [], budgets(0.0, 16.0), "en", "")["chat"], "qwen2.5-coder-7b", "16 GB laptop, only coder builds for its NPU: the fallback")
	assert_eq(Brain.choose(prefs, npu_models, [], budgets(0.0, 8.0), "en", "")["chat"], "qwen2.5-coder-1.5b", "8 GB laptop")


func test_other_languages_get_a_multilingual_whisper_on_the_cpu() -> void:
	var chosen: Dictionary = Brain.choose(prefs, models, variants, budgets(12.0, 32.0), "de", "")
	assert_eq(chosen["speech"], "openai-whisper-small-generic-cpu", "the CUDA Whisper builds garble, so the CPU build by name")


func test_model_alias_overrides_the_choice() -> void:
	var chosen: Dictionary = Brain.choose(prefs, models, variants, budgets(12.0, 32.0), "en", "phi-4-mini")
	assert_eq(chosen["chat"], "phi-4-mini")
	assert_string_contains(chosen["why"], "set by model_alias")


func test_nothing_fits_says_so() -> void:
	var chosen: Dictionary = Brain.choose(prefs, models, variants, budgets(0.2, 0.4), "en", "")
	assert_eq(chosen["chat"], "")
	assert_string_contains(chosen["why"], "none fits")


func test_reasoning_models_are_never_picked() -> void:
	for gb: float in [4.0, 8.0, 12.0, 24.0, 48.0]:
		var chat: String = Brain.choose(prefs, models, variants, budgets(gb, gb * 2.0), "en", "")["chat"]
		assert_false("reasoning" in chat or chat.begins_with("deepseek-r1"), "%s at %d GB" % [chat, gb])


func test_a_family_takes_its_largest_member_that_fits() -> void:
	var budget: Dictionary = {"gpu": 2000.0, "npu": 0.0, "cpu": 0.0}
	assert_eq(ModelPreferences.pick(["qwen2.5-coder-*"], models, variants, ModelPreferences.CHAT_TYPES, budget, 1.2)["name"], "qwen2.5-coder-1.5b")


func test_the_brain_uses_the_preferences_resource() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var brain: Brain = pet.get_node("Brain")
	assert_not_null(brain.preferences)
	assert_eq(brain.model_alias, "", "chosen per machine unless overridden")
	pet.free()


func test_the_catalog_reads_past_the_line_a_starting_server_prints() -> void:
	# What `foundry model list -o json` prints on macOS when it has to start the server first.
	var printed: String = "foundrylocald 0.10.3 starting (log-level=info)\n{\"models\":[{\"alias\":\"qwen2.5-7b\",\"type\":\"Chat\"}]}"
	assert_eq(ModelPreferences.parse_catalog(printed, "models").size(), 1)
	assert_eq(ModelPreferences.parse_catalog("no catalog here", "models"), [])
