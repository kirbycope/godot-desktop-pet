extends SceneTree
## The PC duck's models side by side: every Foundry Local build of the chat models the duck can
## choose (resources/model_preferences.tres), each through the duck's own brain from a clean start,
## as the phone's benchmark (LocalBench) does on a phone. Before each build every cached build of
## those models is deleted and Foundry's server stopped, and the GPU is left to cool to within
## COOL_RISE_C of where it began; then the build is downloaded, started and asked the phone
## benchmark's four lines, with the GPU let cool again before the first. Everything goes to
## DUCK_BENCH_OUT in LlmMetrics' format, with the GPU's temperature, load and memory and Foundry's
## own memory on each line, so tools/llm_report.py makes the table. A run cut short is taken up
## where it stopped, as the phone's is.
##
##   godot --headless --path . -s res://tools/pc_bench.gd
##
## DUCK_BENCH_BUILDS: comma-separated build names (variantName in `foundry model list --variants`)
## to try instead of every one. Speech models are left alone; the chat model the duck uses is
## downloaded again when it next starts.

const OUT: String = "user://pc_llm_metrics.jsonl"
const FOLDER: String = "user://pc_bench"
const FOUNDRY_PATHS: PackedStringArray = ["foundry", "/opt/homebrew/bin/foundry", "/usr/local/bin/foundry"]
const SETTLE_SECONDS: float = 10.0
## Cool: the GPU within this of its temperature when the run began, and this busy at most.
const COOL_RISE_C: float = 3.0
const COOL_UTIL: int = 10
const COOL_TIMEOUT: float = 600.0
const START_TIMEOUT: float = 900.0
const ANSWER_TIMEOUT: float = 300.0
## Foundry's execution providers, as the table names them.
const PROVIDERS: Dictionary = {
	"NvTensorRTRTXExecutionProvider": "TensorRT-RTX",
	"CUDAExecutionProvider": "CUDA",
	"WebGpuExecutionProvider": "WebGPU",
	"CPUExecutionProvider": "CPU",
}

var _foundry: String = ""
var _out: String = OUT
var _run_name: String = ""
var _start_gpu_c: float = 0.0
var _pet: Node = null
var _brain: Brain = null
## The answer under way: when it was asked, its first piece, how many pieces, and whether it is in.
var _asked_at: int = 0
var _first_piece_at: int = 0
var _pieces: int = 0
var _reply: String = ""
var _replied: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_out = OS.get_environment("DUCK_BENCH_OUT") if not OS.get_environment("DUCK_BENCH_OUT").is_empty() else OUT
	for path: String in FOUNDRY_PATHS:
		if OS.execute(path, ["--version"]) == 0:
			_foundry = path
			break
	if _foundry.is_empty():
		push_error("pc_bench: Foundry Local is not installed")
		quit(1)
		return
	var builds: Array[Dictionary] = chat_builds(_catalog(), (load("res://resources/model_preferences.tres") as ModelPreferences).chat_for(OS.get_name()))
	var only: String = OS.get_environment("DUCK_BENCH_BUILDS")
	if not only.is_empty():
		var wanted: PackedStringArray = only.split(",", false)
		builds = builds.filter(func(b: Dictionary) -> bool: return b["variantName"] in wanted)
	var by_name: Dictionary = {}
	for build: Dictionary in builds:
		by_name[build["variantName"]] = build
	var left: Dictionary = LocalBench.unfinished(LlmMetrics.read(_out))
	var names: PackedStringArray = left.get("setups", PackedStringArray(builds.map(func(b: Dictionary) -> String: return b["variantName"])))
	var total: int = left.get("total", names.size())
	_start_gpu_c = float(left.get("gpu_c", float(gpu_stats().get("gpu_c", 0.0))))
	if left.is_empty():
		_run_name = Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
		_record({"kind": "bench", "device": {"model": OS.get_model_name(), "soc": OS.get_processor_name(), "gpu": gpu_name(), "os": "%s %s" % [OS.get_name(), OS.get_version()], "foundry": _foundry_version()}, "setups": names, "prompts": LocalBench.PROMPTS})
	else:
		_run_name = left["run"]
		_record({"kind": "resumed", "setups": names})
	print("pc_bench: run %s, %d builds, writing %s" % [_run_name, names.size(), ProjectSettings.globalize_path(_out)])
	for i: int in names.size():
		if by_name.has(names[i]):
			await _try(by_name[names[i]], "%d of %d" % [total - names.size() + i + 1, total])
	_record({"kind": "end"})
	await _let_go()
	print("pc_bench: done")
	quit()


func _try(build: Dictionary, count: String) -> void:
	var name: String = build["variantName"]
	var setup: Dictionary = {"setup": name, "label": label_for(build), "engine": "Foundry Local", "backend": PROVIDERS.get(build.get("executionProvider", ""), build.get("executionProvider", ""))}
	print("pc_bench: %s %s" % [count, setup["label"]])
	await _let_go()
	var freed: int = _clear()
	_record({"kind": "cleared", "mb": freed}, setup)
	await create_timer(SETTLE_SECONDS).timeout
	await _cool_down(setup, "before starting")
	var began: int = Time.get_ticks_msec()
	var output: Array = []
	if OS.execute(_foundry, ["model", "download", name], output, true) != 0:
		_record({"kind": "failed", "why": "download: " + "".join(output).strip_edges().right(200)}, setup)
		_record({"kind": "done"}, setup)
		return
	var took: float = (Time.get_ticks_msec() - began) / 1000.0
	var mb: int = int(build.get("fileSizeMb", 0))
	_record({"kind": "download", "mb": mb, "seconds": snappedf(took, 0.01), "mb_per_s": snappedf(mb / maxf(took, 0.001), 0.1)}, setup)
	# The download started Foundry's server on a port of its own; the duck starts it on its own.
	OS.execute(_foundry, ["server", "stop"])
	# The duck's own pet, brain and prompts, on this build, in a mind of its own.
	_pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var mind: Mind = _pet.get_node("Mind")
	# A mind of its own for each build, so what one remembered cannot change the next one's prompt.
	mind.root = FOLDER.path_join(name)
	LocalBrain.remove_tree(ProjectSettings.globalize_path(mind.root))
	_brain = _pet.get_node("Brain")
	_brain.model_alias = name
	_brain.keep_loaded_from_editor = false
	began = Time.get_ticks_msec()
	root.add_child(_pet)
	while not _brain.is_ready() and Time.get_ticks_msec() - began < START_TIMEOUT * 1000 and not _gave_up(_brain.status):
		await create_timer(0.5).timeout
	if not _brain.is_ready():
		_record({"kind": "failed", "why": _brain.status}, setup)
		_record({"kind": "done"}, setup)
		return
	_record({"kind": "load", "seconds": snappedf((Time.get_ticks_msec() - began) / 1000.0, 0.01)}, setup)
	_brain.chat_stream.delta.connect(_on_delta)
	_brain.replied.connect(_on_replied)
	await _cool_down(setup, "before asking")
	var turn: int = 0
	for line: String in LocalBench.PROMPTS:
		turn += 1
		_pieces = 0
		_first_piece_at = 0
		_replied = false
		_asked_at = Time.get_ticks_msec()
		_brain.ask(line, "")
		while not _replied and Time.get_ticks_msec() - _asked_at < ANSWER_TIMEOUT * 1000:
			await create_timer(0.1).timeout
		if not _replied:
			_record({"kind": "failed", "why": "no answer in %d s" % ANSWER_TIMEOUT}, setup)
			break
		var timed: Dictionary = _brain.timings
		var answer: Dictionary = LocalBrain.answer_metrics(0.0, (_first_piece_at - _asked_at) / 1000.0 if _first_piece_at > 0 else 0.0, float(timed.get("first_sentence", 0)) / 1000.0, float(timed.get("reply", 0)) / 1000.0, turn, _pieces, _reply.length(), {})
		answer["kind"] = "answer"
		answer["garbled"] = LlmMetrics.garbled(_reply)
		answer["text"] = _reply
		answer["finish_reason"] = str(timed.get("finish_reason", ""))
		_record(answer, setup)
		print("pc_bench:   %d. %.1f s, %s" % [turn, answer["total_s"], _reply.left(80)])
	_record({"kind": "done"}, setup)


func _on_delta(_piece: String) -> void:
	if _first_piece_at == 0:
		_first_piece_at = Time.get_ticks_msec()
	_pieces += 1


func _on_replied(text: String) -> void:
	_reply = text
	_replied = true


## Frees the duck and its brain, which stops Foundry's server, and stops it again in case.
func _let_go() -> void:
	if _pet != null:
		_pet.queue_free()
		_pet = null
		_brain = null
		await process_frame
		await process_frame
	OS.execute(_foundry, ["server", "stop"])
	await create_timer(2.0).timeout


## Deletes every cached build of the duck's chat models, so the next starts as on a fresh machine.
## Returns the megabytes freed. Stops the server `foundry model list` starts.
func _clear() -> int:
	var freed: int = 0
	var catalog: Array = _catalog()
	var chat: Array[Dictionary] = chat_builds(catalog, (load("res://resources/model_preferences.tres") as ModelPreferences).chat_for(OS.get_name()))
	for build: Dictionary in chat:
		if build.get("cached", false):
			if OS.execute(_foundry, ["cache", "remove", build["variantId"], "--force"]) == 0:
				freed += int(build.get("fileSizeMb", 0))
	OS.execute(_foundry, ["server", "stop"])
	return freed


func _catalog() -> Array:
	var output: Array = []
	OS.execute(_foundry, ["model", "list", "--variants", "-o", "json"], output)
	return ModelPreferences.parse_catalog("".join(output), "variants")


func _cool_down(setup: Dictionary, stage: String) -> void:
	var began: int = Time.get_ticks_msec()
	var stats: Dictionary = gpu_stats()
	while not cool_enough(stats, _start_gpu_c + COOL_RISE_C, COOL_UTIL) and Time.get_ticks_msec() - began < COOL_TIMEOUT * 1000:
		await create_timer(5.0).timeout
		stats = gpu_stats()
	_record({"kind": "cooled", "stage": stage, "seconds": snappedf((Time.get_ticks_msec() - began) / 1000.0, 0.1)}, setup)


func _record(entry: Dictionary, setup: Dictionary = {}) -> void:
	var line: Dictionary = {"run": _run_name}
	line.merge(gpu_stats())
	line["foundry_mb"] = foundry_mb()
	# "free": physical memory free; "available" counts the page file as well on Windows.
	line["avail_mb"] = int(OS.get_memory_info().get("free", 0)) / 1048576
	line.merge(setup, true)
	line.merge(entry, true)
	LlmMetrics.record(line, _out)


func _foundry_version() -> String:
	var output: Array = []
	OS.execute(_foundry, ["--version"], output)
	return "".join(output).strip_edges()


func _gave_up(status: String) -> bool:
	return status.begins_with("Foundry Local failed") or status.contains("took over") or status.begins_with("No chat model") or status.begins_with("I need Foundry")


## The chat builds in `catalog` (`foundry model list --variants`) of the aliases `entries` names.
static func chat_builds(catalog: Array, entries: PackedStringArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for build: Variant in catalog:
		if build is Dictionary and String(build.get("type", "")) in ModelPreferences.CHAT_TYPES:
			for entry: String in entries:
				if String(build.get("alias", "")).matchn(entry):
					found.append(build)
					break
	return found


## "Qwen 2.5 Coder 7B, Foundry CUDA GPU" from a build's alias, provider and device.
static func label_for(build: Dictionary) -> String:
	var words: PackedStringArray = PackedStringArray()
	for part: String in String(build.get("alias", "")).split("-"):
		if part.begins_with("qwen"):
			words.append("Qwen " + part.trim_prefix("qwen"))
		elif part.ends_with("b") and part.trim_suffix("b").is_valid_float():
			words.append(part.to_upper())
		else:
			words.append(part.capitalize())
	var provider: String = PROVIDERS.get(build.get("executionProvider", ""), String(build.get("executionProvider", "")))
	var device: String = String(build.get("device", "")).to_upper()
	return "%s, Foundry %s" % [" ".join(words), provider if provider == device else "%s %s" % [provider, device]]


## The GPU's temperature, load and memory in use from nvidia-smi; {} without one.
static func gpu_stats() -> Dictionary:
	var output: Array = []
	if OS.execute("nvidia-smi", ["--query-gpu=temperature.gpu,utilization.gpu,memory.used", "--format=csv,noheader,nounits"], output) != 0:
		return {}
	var parts: PackedStringArray = "".join(output).strip_edges().get_slice("\n", 0).split(",")
	if parts.size() < 3:
		return {}
	return {"gpu_c": parts[0].strip_edges().to_float(), "gpu_util": parts[1].strip_edges().to_int(), "gpu_mem_mb": parts[2].strip_edges().to_int()}


static func gpu_name() -> String:
	var output: Array = []
	if OS.execute("nvidia-smi", ["--query-gpu=name", "--format=csv,noheader"], output) != 0:
		return ""
	return "".join(output).strip_edges()


## The memory Foundry's service holds, where the models run, in MB.
static func foundry_mb() -> int:
	var output: Array = []
	if OS.get_name() == "Windows":
		OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process foundrylocald -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum"], output)
	else:
		OS.execute("/bin/sh", ["-c", "ps -A -o rss=,comm= | awk '/foundry/ {s+=$1} END {print s*1024}'"], output)
	return int("".join(output).strip_edges().to_int() / 1048576)


## Whether the GPU is back to `max_c` or cooler and no busier than `max_util` percent. No GPU to
## read counts as cool.
static func cool_enough(stats: Dictionary, max_c: float, max_util: int) -> bool:
	return float(stats.get("gpu_c", 0.0)) <= max_c and int(stats.get("gpu_util", 0)) <= max_util
