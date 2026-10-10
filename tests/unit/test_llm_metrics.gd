extends GutTest
## The phone's model metrics: a JSON line per download, start and answer, and the Stats tab's
## summary of the last benchmark.

const PATH: String = "user://test_llm_metrics.jsonl"


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_each_entry_is_a_line_stamped_with_the_time() -> void:
	LlmMetrics.record({"kind": "load", "setup": "a", "seconds": 4.5}, PATH)
	LlmMetrics.record({"kind": "answer", "setup": "a", "turn": 1}, PATH)
	var entries: Array[Dictionary] = LlmMetrics.read(PATH)
	assert_eq(entries.size(), 2, "kept in order, one line each")
	assert_eq(entries[0]["kind"], "load")
	assert_eq(entries[0]["seconds"], 4.5)
	assert_almost_eq(float(entries[1]["at"]), Time.get_unix_time_from_system(), 5.0)
	LlmMetrics.record({"kind": "load"}, "")
	assert_eq(LlmMetrics.read(PATH).size(), 2, "no path, no record")
	assert_eq(LlmMetrics.read("user://no_such_metrics.jsonl"), [] as Array[Dictionary])


func test_the_summary_is_the_last_benchmark_setup_by_setup() -> void:
	var lines: Array[Dictionary] = [
		{"kind": "bench", "run": "old", "device": {"model": "Phone"}},
		{"kind": "load", "run": "old", "setup": "x", "label": "Old one", "seconds": 1.0},
		{"kind": "bench", "run": "new", "device": {"model": "samsung SM-S928U"}},
		{"kind": "cleared", "run": "new", "setup": "a", "label": "Gemma 4 E2B, LiteRT-LM GPU", "mb": 0},
		{"kind": "download", "run": "new", "setup": "a", "label": "Gemma 4 E2B, LiteRT-LM GPU", "mb": 2588, "seconds": 95.0, "mb_per_s": 27.2},
		{"kind": "load", "run": "new", "setup": "a", "label": "Gemma 4 E2B, LiteRT-LM GPU", "seconds": 7.9, "pss_mb": 2100},
		{"kind": "answer", "run": "new", "setup": "a", "turn": 1, "first_word_s": 1.2, "first_sentence_s": 2.0, "total_s": 4.0, "decode_tps": 20.0},
		{"kind": "answer", "run": "new", "setup": "a", "turn": 2, "first_word_s": 0.4, "total_s": 2.0, "decode_tps": 22.0},
		{"kind": "answer", "run": "new", "setup": "a", "turn": 3, "first_word_s": 0.6, "total_s": 3.0, "decode_tps": 24.0},
		{"kind": "failed", "run": "new", "setup": "b", "label": "Gemini Nano, Android AICore", "why": "606 FEATURE_NOT_FOUND"},
	]
	var text: String = LlmMetrics.summary(lines)
	assert_string_contains(text, "Benchmark new on samsung SM-S928U")
	assert_false(text.contains("Old one"), "only the last benchmark")
	assert_string_contains(text, "Gemma 4 E2B, LiteRT-LM GPU\nDownload", "a setup's name heads its lines")
	assert_string_contains(text, "Download 2588 MB in 1 min 35 s (27.2 MB/s)")
	assert_string_contains(text, "Warm-up 7.9 s")
	assert_string_contains(text, "First answer: first word 1.2 s, talking at 2.0 s, whole 4.0 s, 20.0 tokens/s")
	assert_string_contains(text, "Later answers (2): first word 0.50 s, whole 2.5 s, 23.0 tokens/s", "averaged")
	assert_string_contains(text, "Memory up to 2.1 GB")
	assert_string_contains(text, "Gemini Nano, Android AICore\nFailed: 606 FEATURE_NOT_FOUND")
	assert_eq(LlmMetrics.summary([{"kind": "answer", "run": ""}]), "", "nothing until a benchmark has run")
	var again: Array[Dictionary] = [
		{"kind": "bench", "run": "r"},
		{"kind": "cleared", "run": "r", "setup": "a", "label": "A"},
		{"kind": "load", "run": "r", "setup": "a", "seconds": 99.0},
		{"kind": "resumed", "run": "r"},
		{"kind": "cleared", "run": "r", "setup": "a", "label": "A"},
		{"kind": "load", "run": "r", "setup": "a", "seconds": 5.0},
	]
	text = LlmMetrics.summary(again)
	assert_string_contains(text, "Warm-up 5.0 s", "a setup tried again counts its last try")
	assert_false(text.contains("99"))


func test_times_read_as_seconds_or_minutes() -> void:
	assert_eq(LlmMetrics.seconds(0.4234), "0.42 s")
	assert_eq(LlmMetrics.seconds(8.06), "8.1 s")
	assert_eq(LlmMetrics.seconds(125.0), "2 min 05 s")


func test_off_the_phone_the_device_is_named_and_its_stats_are_empty() -> void:
	if Engine.has_singleton("DuckDevice"):
		pass_test("on a phone")
		return
	assert_eq(LlmMetrics.device_stats(), {})
	assert_true(LlmMetrics.device().has("model"))
