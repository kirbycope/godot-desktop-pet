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
## On a Mac the duck's chat runs on llama.cpp (llama-server, on Metal) rather than Foundry, so there
## each GGUF model in Brain.llama_models is tried too, downloaded by llama-server itself into the
## Hugging Face cache, which is cleared between setups like Foundry's. A Mac has no GPU sensor this
## can read, so its lines carry the CPU speed limit macOS reports instead (100 is unthrottled).
##
##   godot --headless --path . -s res://tools/pc_bench.gd
##
## DUCK_BENCH_BUILDS: comma-separated build names (variantName in `foundry model list --variants`)
## to try instead of every one. Speech models are left alone. Once every build is done, the cache is
## put back as the duck needs it: the last build tried goes, and the chat model the duck chooses on
## this machine is downloaded, so its next start does not download it. (On a Mac, llama-server
## downloads its GGUF itself as the duck next starts.)

const OUT: String = "user://pc_llm_metrics.jsonl"
const FOLDER: String = "user://pc_bench"
const FOUNDRY_PATHS: PackedStringArray = ["foundry", "/opt/homebrew/bin/foundry", "/usr/local/bin/foundry"]
## The duck's own ports for Foundry Local and llama-server (Brain.port, Brain.llama_port).
const FOUNDRY_PORT: int = 39839
const LLAMA_PORT: int = 39841
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
	if OS.get_name() == "macOS" and not _llama_path().is_empty():
		builds.append_array(llama_builds(_llama_models()))
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
	_put_back()
	print("pc_bench: done")
	quit()


func _try(build: Dictionary, count: String) -> void:
	var name: String = build["variantName"]
	var gguf: String = build.get("gguf", "")
	var setup: Dictionary = {"setup": name, "label": label_for(build), "engine": build.get("engine", "Foundry Local"), "backend": PROVIDERS.get(build.get("executionProvider", ""), build.get("executionProvider", ""))}
	print("pc_bench: %s %s" % [count, setup["label"]])
	await _let_go()
	var freed: int = _clear()
	_record({"kind": "cleared", "mb": freed}, setup)
	await create_timer(SETTLE_SECONDS).timeout
	await _cool_down(setup, "before starting")
	var began: int = Time.get_ticks_msec()
	if gguf.is_empty():
		_serve()
		var output: Array = []
		if OS.execute(_foundry, ["model", "download", name], output, true) != 0:
			_record({"kind": "failed", "why": "download: " + "".join(output).strip_edges().right(200)}, setup)
			_record({"kind": "done"}, setup)
			return
		var took: float = (Time.get_ticks_msec() - began) / 1000.0
		var mb: int = int(build.get("fileSizeMb", 0))
		_record({"kind": "download", "mb": mb, "seconds": snappedf(took, 0.01), "mb_per_s": snappedf(mb / maxf(took, 0.001), 0.1)}, setup)
		# The duck starts the server itself, as on any start.
		OS.execute(_foundry, ["server", "stop"])
	# The duck's own pet, brain and prompts, on this build, in a mind of its own.
	_pet = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var mind: Mind = _pet.get_node("Mind")
	# A mind of its own for each build, so what one remembered cannot change the next one's prompt.
	mind.root = FOLDER.path_join(name)
	LocalBrain.remove_tree(ProjectSettings.globalize_path(mind.root))
	_brain = _pet.get_node("Brain")
	# A Foundry build is named outright; a GGUF by its Foundry alias, which the brain sends to
	# llama-server on a Mac.
	_brain.model_alias = name if gguf.is_empty() else String(build["alias"])
	_brain.keep_loaded_from_editor = false
	if gguf.is_empty():
		began = Time.get_ticks_msec()
	root.add_child(_pet)
	# llama-server downloads the model before it starts loading it, which the brain reports as
	# "Loading": the download is timed to there.
	var loading_at: int = 0 if not gguf.is_empty() else began
	while not _brain.is_ready() and Time.get_ticks_msec() - began < START_TIMEOUT * 1000 and not _gave_up(_brain.status):
		if loading_at == 0 and _brain.status.begins_with("Loading"):
			loading_at = Time.get_ticks_msec()
		await create_timer(0.5).timeout
	if loading_at == 0:
		loading_at = Time.get_ticks_msec()
	if not gguf.is_empty():
		var took_gguf: float = (loading_at - began) / 1000.0
		var size: int = folder_mb(hf_folder(gguf).path_join("blobs"))
		_record({"kind": "download", "mb": size, "seconds": snappedf(took_gguf, 0.01), "mb_per_s": snappedf(size / maxf(took_gguf, 0.001), 0.1)}, setup)
	if not _brain.is_ready():
		_record({"kind": "failed", "why": _brain.status}, setup)
		_record({"kind": "done"}, setup)
		return
	_record({"kind": "load", "seconds": snappedf((Time.get_ticks_msec() - loading_at) / 1000.0, 0.01)}, setup)
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
	var stop_llama: PackedStringArray = KeptModel.stop_llama_command(LLAMA_PORT)
	OS.execute(stop_llama[0], stop_llama.slice(1))
	await create_timer(2.0).timeout


## Deletes every cached build of the duck's chat models, and on a Mac every GGUF llama-server
## downloaded for them, so the next starts as on a fresh machine. Returns the megabytes freed.
func _clear() -> int:
	var freed: int = 0
	if OS.get_name() == "macOS":
		for gguf: String in _llama_models().values():
			freed += LocalBrain.remove_tree(hf_folder(gguf)) / 1000000
	var catalog: Array = _catalog()
	var chat: Array[Dictionary] = chat_builds(catalog, (load("res://resources/model_preferences.tres") as ModelPreferences).chat_for(OS.get_name()))
	for build: Dictionary in chat:
		if build.get("cached", false):
			if OS.execute(_foundry, ["cache", "remove", build["variantId"], "--force"]) == 0:
				freed += int(build.get("fileSizeMb", 0))
	OS.execute(_foundry, ["server", "stop"])
	return freed


## Clears the builds tried and downloads the chat model the duck chooses here, as Brain does.
func _put_back() -> void:
	_clear()
	_serve()
	var prefs: ModelPreferences = load("res://resources/model_preferences.tres")
	var output: Array = []
	OS.execute(_foundry, ["model", "list", "-o", "json"], output)
	var models: Array = ModelPreferences.parse_catalog("".join(output), "models")
	var chosen: String = Brain.choose(prefs, models, _catalog(), Hardware.memory_budgets(prefs.memory_share), OS.get_locale_language(), "", OS.get_name())["chat"]
	if not chosen.is_empty():
		print("pc_bench: downloading %s again, the duck's own chat model" % chosen)
		OS.execute(_foundry, ["model", "download", chosen])
	OS.execute(_foundry, ["server", "stop"])


func _catalog() -> Array:
	_serve()
	var output: Array = []
	OS.execute(_foundry, ["model", "list", "--variants", "-o", "json"], output)
	return ModelPreferences.parse_catalog("".join(output), "variants")


## Starts Foundry's server on the duck's port the way the duck does. A foundry command that starts
## it itself leaves it holding the command's output open on macOS, and the command never returns.
func _serve() -> void:
	var command: PackedStringArray = Brain.server_start_command(_foundry, FOUNDRY_PORT, OS.get_name())
	OS.execute(command[0], command.slice(1))


## The GGUF build of each Foundry alias the Mac duck runs on llama-server (Brain.llama_models).
func _llama_models() -> Dictionary:
	var brain: Brain = Brain.new()
	var models: Dictionary = brain.llama_models.duplicate()
	brain.free()
	return models


func _llama_path() -> String:
	for path: String in Brain.LLAMA_PATHS:
		if FileAccess.file_exists(path):
			return path
	return ""


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
	if OS.get_name() == "macOS":
		line["llama_mb"] = process_mb("llama-server")
		line["cpu_speed_limit"] = cpu_speed_limit()
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
	return status.begins_with("Foundry Local failed") or status.contains("took over") or status.begins_with("No chat model") or status.begins_with("I need Foundry") or status.begins_with("llama-server stopped")


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


## A setup for each of `models` ({Foundry alias: "owner/repo:quant"}) on llama-server, named by
## alias, as the Mac duck runs them.
static func llama_builds(models: Dictionary) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for alias: String in models:
		found.append({"variantName": "llama-" + alias, "alias": alias, "gguf": models[alias], "engine": "llama.cpp", "executionProvider": "Metal", "device": "Gpu"})
	return found


## Where llama-server keeps the GGUF "owner/repo:quant": the Hugging Face cache's models--owner--repo.
static func hf_folder(gguf: String) -> String:
	var home: String = OS.get_environment("HF_HOME")
	var hub: String = home.path_join("hub") if not home.is_empty() else OS.get_environment("HOME").path_join(".cache/huggingface/hub")
	return hub.path_join("models--" + gguf.get_slice(":", 0).replace("/", "--"))


## The megabytes of the files under `folder`.
static func folder_mb(folder: String) -> int:
	var bytes: int = 0
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	for sub: String in DirAccess.get_directories_at(folder):
		bytes += folder_mb(folder.path_join(sub)) * 1000000
	for file: String in DirAccess.get_files_at(folder):
		var handle: FileAccess = FileAccess.open(folder.path_join(file), FileAccess.READ)
		bytes += handle.get_length() if handle != null else 0
	return bytes / 1000000


## "Qwen 2.5 Coder 7B, Foundry CUDA GPU" from a build's alias, provider and device; "Qwen 2.5 7B,
## llama.cpp Metal" for one on llama-server.
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
	if build.has("gguf"):
		return "%s, llama.cpp %s" % [" ".join(words), provider]
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
	return process_mb("foundrylocald")


## The memory every process named `name` holds, in MB.
static func process_mb(name: String) -> int:
	var output: Array = []
	if OS.get_name() == "Windows":
		OS.execute("powershell", ["-NoProfile", "-Command", "(Get-Process %s -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum" % name], output)
		return int("".join(output).strip_edges().to_int() / 1048576)
	OS.execute("/bin/ps", ["-A", "-o", "rss=,comm="], output)
	var kb: int = 0
	for line: String in "".join(output).split("
", false):
		var parts: PackedStringArray = line.strip_edges().split(" ", false, 1)
		if parts.size() == 2 and parts[1].get_file() == name:
			kb += parts[0].to_int()
	return kb / 1024


## The CPU speed limit macOS reports (`pmset -g therm`), 100 when nothing has throttled it.
static func cpu_speed_limit() -> int:
	var output: Array = []
	OS.execute("/usr/bin/pmset", ["-g", "therm"], output)
	var found: RegExMatch = RegEx.create_from_string(r"CPU_Speed_Limit\s*=\s*(\d+)").search("".join(output))
	return found.get_string(1).to_int() if found != null else 100


## Whether the GPU is back to `max_c` or cooler and no busier than `max_util` percent. No GPU to
## read counts as cool.
static func cool_enough(stats: Dictionary, max_c: float, max_util: int) -> bool:
	return float(stats.get("gpu_c", 0.0)) <= max_c and int(stats.get("gpu_util", 0)) <= max_util
