extends GutTest
## The benchmark: every setup in turn, the models deleted before each, everything recorded under
## one run, and the duck's own setup and mind back afterwards. Setups that need the Android plugins
## fail at once off a phone, so nothing is downloaded here.

const ROOT: String = "user://test_local_bench"


func after_each() -> void:
	_remove(ProjectSettings.globalize_path(ROOT))


func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_remove(folder.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func test_each_setup_starts_clean_and_is_recorded_under_the_run() -> void:
	if Engine.has_singleton("LiteRtLm"):
		pass_test("on a phone these would download")
		return
	var models: String = ProjectSettings.globalize_path(ROOT).path_join("models")
	DirAccess.make_dir_recursive_absolute(models.path_join("owner/repo"))
	DirAccess.make_dir_recursive_absolute(models.path_join("compiled"))
	for file: String in ["owner/repo/old.gguf", "owner/repo/old.litertlm", "compiled/kernels.bin"]:
		FileAccess.open(models.path_join(file), FileAccess.WRITE).store_buffer(PackedByteArray([1, 2, 3]))
	var duck_mind: Mind = Mind.new()
	duck_mind.root = ROOT.path_join("duck")
	add_child_autofree(duck_mind)
	var bench_mind: Mind = Mind.new()
	bench_mind.root = ROOT.path_join("bench")
	add_child_autofree(bench_mind)
	var brain: LocalBrain = LocalBrain.new()
	brain.mind = duck_mind
	brain.setup_id = "auto"
	brain.metrics_path = ROOT.path_join("metrics.jsonl")
	add_child_autofree(brain)
	var bench: LocalBench = LocalBench.new()
	bench.brain = brain
	bench.mind = bench_mind
	bench.settle_seconds = 0.0
	bench.model_folders = PackedStringArray([models])
	bench.setups = PackedStringArray(["litertlm-gemma4-e2b-gpu", "gemini-nano"])
	add_child_autofree(bench)
	watch_signals(bench)
	var run: String = await bench.run()
	assert_signal_emitted(bench, "finished")
	assert_false(bench.running)
	assert_eq(brain.setup_id, "auto", "the duck's own setup again")
	assert_eq(brain.mind, duck_mind, "and its own mind")
	assert_eq(brain.run, "")
	assert_false(FileAccess.file_exists(models.path_join("owner/repo/old.gguf")), "the models went before the first setup")
	assert_false(DirAccess.dir_exists_absolute(models.path_join("compiled")), "and what LiteRT-LM compiled")
	var kinds: Array = []
	for entry: Dictionary in LlmMetrics.read(brain.metrics_path):
		assert_eq(entry["run"], run, "every line is under the run")
		kinds.append([entry["kind"], entry.get("setup", "")])
	assert_eq(kinds, [["bench", ""], ["cleared", "litertlm-gemma4-e2b-gpu"], ["cooled", "litertlm-gemma4-e2b-gpu"], ["failed", "litertlm-gemma4-e2b-gpu"], ["done", "litertlm-gemma4-e2b-gpu"], ["cleared", "gemini-nano"], ["cooled", "gemini-nano"], ["failed", "gemini-nano"], ["done", "gemini-nano"], ["end", ""]])
	assert_eq(LocalBench.unfinished(LlmMetrics.read(brain.metrics_path)), {}, "a run that ended is not taken up again")
	assert_eq(LlmMetrics.read(brain.metrics_path)[1]["mb"], 0, "three bytes freed is 0 MB")
	bench_mind.remember("likes pancakes")
	bench.setups = PackedStringArray(["gemini-nano"])
	await bench.run()
	assert_eq(bench_mind.memories(), PackedStringArray(), "each setup starts with a mind of its own, remembering nothing")


func test_it_waits_for_the_phone_to_cool() -> void:
	assert_true(LocalBench.cool_enough({}, 0, 36.0), "off a phone there is nothing to wait for")
	assert_true(LocalBench.cool_enough({"thermal": 0, "battery_c": 35.5}, 0, 36.0))
	assert_false(LocalBench.cool_enough({"thermal": 2, "battery_c": 35.5}, 0, 36.0), "throttling")
	assert_false(LocalBench.cool_enough({"thermal": 0, "battery_c": 37.6}, 0, 36.0), "a battery warmer than the limit")


func test_a_run_cut_short_is_taken_up_where_it_stopped() -> void:
	var entries: Array[Dictionary] = [
		{"kind": "bench", "run": "old", "setups": ["a"]},
		{"kind": "bench", "run": "r", "setups": ["a", "b", "c"], "battery_c": 37.1},
		{"kind": "cleared", "run": "r", "setup": "a"},
		{"kind": "done", "run": "r", "setup": "a"},
		{"kind": "cleared", "run": "r", "setup": "b"},
		{"kind": "answer", "run": "r", "setup": "b", "turn": 1},
	]
	assert_eq(LocalBench.unfinished(entries), {"run": "r", "setups": PackedStringArray(["b", "c"]), "total": 3, "battery_c": 37.1, "gpu_c": 0.0}, "b again from the start, then c")
	entries.append({"kind": "done", "run": "r", "setup": "b"})
	entries.append({"kind": "done", "run": "r", "setup": "c"})
	assert_eq(LocalBench.unfinished(entries), {}, "every setup done")
	entries.insert(entries.size() - 1, {"kind": "failed", "run": "r", "setup": "b", "why": "a missing folder"})
	assert_eq(LocalBench.unfinished(entries)["setups"], PackedStringArray(["b"]), "a setup that failed is tried again")
	entries.append({"kind": "cleared", "run": "r", "setup": "b"})
	entries.append({"kind": "done", "run": "r", "setup": "b"})
	assert_eq(LocalBench.unfinished(entries), {}, "until it is tried and does not fail")
	assert_eq(LocalBench.unfinished([] as Array[Dictionary]), {})
