class_name LlmMetrics
extends RefCounted
## How the phone's own models do, kept to compare engines and models after the fact: every download,
## start and answer is one JSON line in a file (user://llm_metrics.jsonl on the phone), with the
## phone's memory and temperature at that moment. The Stats tab shows a summary of the last
## benchmark; the whole file comes off the phone with
## `adb exec-out run-as com.kirbycope.duck cat files/llm_metrics.jsonl`.
##
## Each line has "at" (Unix seconds), "kind" and "setup" (LocalBrain.SETUPS' id, or "auto"):
##   bench     a benchmark began: "run", "device" and the "setups" it tries
##   cleared   the models were deleted before a setup: "mb" freed
##   cooled    the benchmark waited "seconds" for the phone to cool, "stage" before starting or asking
##   done      the benchmark has tried this setup; "resumed" and "end" mark a run taken up again
##             and finished
##   download  "mb", "seconds", "mb_per_s"
##   load      the model started: "seconds" from download to ready (the warm-up), "init_s" as the
##             engine counts it, where it says
##   answer    "turn" (1 is the first after a start), "first_word_s", "first_sentence_s" (when the
##             duck starts talking), "total_s", "chars", "pieces" (tokens, or chunks for LiteRT-LM
##             and Gemini Nano), and LiteRT-LM's own "native_ttft_s", "prefill_tps", "decode_tps",
##             "prefill_tokens" and "decode_tokens"
##   failed    "why"
## Every line also carries "pss_mb", "avail_mb", "battery_c" and "thermal" where the phone says.

const PATH: String = "user://llm_metrics.jsonl"


## Adds `entry` to the file at `path`, stamped with the time and the phone's state. Nothing for "".
static func record(entry: Dictionary, path: String = PATH) -> void:
	if path.is_empty():
		return
	var line: Dictionary = {"at": snappedf(Time.get_unix_time_from_system(), 0.001)}
	line.merge(device_stats())
	line.merge(entry, true)
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		push_warning("Metrics: could not open %s" % path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(line))


## Every line in the file, oldest first.
static func read(path: String = PATH) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return found
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			found.append(parsed)
	return found


## The phone's memory and temperature now, from the DuckDevice Android plugin; {} elsewhere.
static func device_stats() -> Dictionary:
	if not Engine.has_singleton("DuckDevice"):
		return {}
	var parsed: Variant = JSON.parse_string(str(Engine.get_singleton("DuckDevice").call("stats")))
	return parsed if parsed is Dictionary else {}


## The phone's name, chip and Android version; on a desktop, the OS and processor.
static func device() -> Dictionary:
	if Engine.has_singleton("DuckDevice"):
		var parsed: Variant = JSON.parse_string(str(Engine.get_singleton("DuckDevice").call("device")))
		if parsed is Dictionary:
			return parsed
	return {"model": OS.get_model_name(), "soc": OS.get_processor_name(), "os": OS.get_name()}


## The last benchmark in `entries`, a few lines per setup it tried, for the Stats tab. "" for none.
static func summary(entries: Array[Dictionary]) -> String:
	var run: String = ""
	for entry: Dictionary in entries:
		if entry.get("kind") == "bench":
			run = str(entry.get("run", ""))
	if run.is_empty():
		return ""
	var order: Array[String] = []
	var by_setup: Dictionary = {}
	var device_name: String = ""
	for entry: Dictionary in entries:
		if str(entry.get("run", "")) != run:
			continue
		if entry.get("kind") == "bench":
			device_name = str((entry.get("device", {}) as Dictionary).get("model", ""))
			continue
		if not entry.has("setup"):
			continue
		var setup: String = str(entry["setup"])
		if not by_setup.has(setup):
			order.append(setup)
		# Tried again after the run was cut short: only the last try counts.
		if not by_setup.has(setup) or entry.get("kind") == "cleared":
			by_setup[setup] = []
		by_setup[setup].append(entry)
	var lines: PackedStringArray = PackedStringArray(["Benchmark %s%s" % [run, (" on " + device_name) if not device_name.is_empty() else ""]])
	for setup: String in order:
		lines.append(setup_summary(by_setup[setup]))
	return "\n\n".join(lines)


## One setup's lines: what it is, its download and warm-up, its first answer and the later ones.
static func setup_summary(entries: Array) -> String:
	var label: String = ""
	var parts: PackedStringArray = PackedStringArray()
	var later: Array[Dictionary] = []
	var peak: int = 0
	for entry: Dictionary in entries:
		label = str(entry.get("label", label))
		# The "cleared" line still carries the setup before's memory.
		if entry.get("kind") != "cleared":
			peak = maxi(peak, int(entry.get("pss_mb", 0)))
		match entry.get("kind"):
			"download":
				parts.append("Download %d MB in %s (%.1f MB/s)" % [int(entry.get("mb", 0)), seconds(entry.get("seconds", 0.0)), float(entry.get("mb_per_s", 0.0))])
			"load":
				parts.append("Warm-up %s" % seconds(entry.get("seconds", 0.0)))
			"answer":
				if int(entry.get("turn", 0)) == 1:
					parts.append("First answer: " + answer_line([entry]))
				else:
					later.append(entry)
			"failed":
				parts.append("Failed: %s" % entry.get("why", ""))
	if not later.is_empty():
		parts.append("Later answers (%d): %s" % [later.size(), answer_line(later)])
	if peak > 0:
		parts.append("Memory up to %.1f GB" % (peak / 1000.0))
	return "%s\n%s" % [label, "\n".join(parts)]


## The average first word, first sentence, whole answer and speed of `answers`.
static func answer_line(answers: Array[Dictionary]) -> String:
	var keys: Array[String] = ["first_word_s", "first_sentence_s", "total_s", "decode_tps"]
	var mean: Dictionary = {}
	for key: String in keys:
		var total: float = 0.0
		var count: int = 0
		for answer: Dictionary in answers:
			if answer.has(key):
				total += float(answer[key])
				count += 1
		if count > 0:
			mean[key] = total / count
	var said: PackedStringArray = PackedStringArray()
	if mean.has("first_word_s"):
		said.append("first word %s" % seconds(mean["first_word_s"]))
	if mean.has("first_sentence_s"):
		said.append("talking at %s" % seconds(mean["first_sentence_s"]))
	if mean.has("total_s"):
		said.append("whole %s" % seconds(mean["total_s"]))
	if mean.has("decode_tps"):
		said.append("%.1f tokens/s" % mean["decode_tps"])
	return ", ".join(said)


## A time as it reads best: "0.42 s", "8.1 s", "2 min 05 s".
static func seconds(value: Variant) -> String:
	var s: float = float(value)
	if s < 1.0:
		return "%.2f s" % s
	if s < 60.0:
		return "%.1f s" % s
	return "%d min %02d s" % [int(s) / 60, int(s) % 60]
