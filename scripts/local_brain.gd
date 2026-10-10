class_name LocalBrain
extends Node
## The duck's brain on a phone with no PC: a model running on the phone itself. Which one is
## `setup_id`: one of SETUPS (an engine, a model and the chip it runs on), or "auto", which is Gemini
## Nano through Android's AICore when the GeminiNano plugin is there and the phone has it, then each
## of `auto_setups` in turn (Gemma 4 E2B on LiteRT-LM, the GPU and then the CPU), and last
## `model_path` through NobodyWho (llama.cpp). Its name, personality and memories are the phone's
## own Mind. Answers come sentence by sentence, as from the PC's Brain, for the phone to show
## and say in its own voice.
##
## Every download, start and answer is timed and written to `metrics_path` (see LlmMetrics), so
## engines and models can be compared after the fact; LocalBench runs them all in turn.
##
## NobodyWho is a GDExtension fetched into addons/nobodywho, so it is reached through ClassDB rather
## than by its class names, and Gemini Nano and LiteRT-LM are Android plugins (android_plugin/), so
## they are reached as singletons: a checkout or a desktop without them still loads and runs.

signal status_changed(text: String)
## One sentence of the answer, cleaned for saying aloud, as soon as it is written.
signal sentence(text: String)
## The whole answer, after the last sentence.
signal replied(text: String)

## The ways the duck can think on a phone. "engine" is NobodyWho, LiteRT-LM or Gemini Nano;
## "backend" the chip it runs on (NobodyWho chooses for itself, using the GPU through Vulkan where
## it can); "model" an hf://owner/repository/file path. The -gpu LiteRT-LM files are smaller builds
## made for the GPU alone; on a Galaxy S24 Ultra (Snapdragon 8 Gen 3) they write nonsense, so they
## are here to be benchmarked on other phones, not picked. Gemini Nano is whatever AICore has.
const SETUPS: Array[Dictionary] = [
	{"id": "nobodywho-gemma4-e2b", "label": "Gemma 4 E2B, NobodyWho", "engine": "NobodyWho", "backend": "auto", "model": "hf://NobodyWho/Google_Gemma4-E2B-GGUF/gemma-4-E2B-it-Q4_K_M.gguf"},
	{"id": "nobodywho-gemma4-e4b", "label": "Gemma 4 E4B, NobodyWho", "engine": "NobodyWho", "backend": "auto", "model": "hf://NobodyWho/Google_Gemma4-E4B-GGUF/gemma-4-E4B-it-Q4_K_M.gguf"},
	{"id": "nobodywho-qwen3.5-2b", "label": "Qwen 3.5 2B, NobodyWho", "engine": "NobodyWho", "backend": "auto", "model": "hf://NobodyWho/Qwen_Qwen3.5-2B-GGUF/Qwen_Qwen3.5-2B-Q4_K_M-vendor-sampling.gguf"},
	{"id": "nobodywho-qwen3.5-4b", "label": "Qwen 3.5 4B, NobodyWho", "engine": "NobodyWho", "backend": "auto", "model": "hf://NobodyWho/Qwen_Qwen3.5-4B-GGUF/Qwen_Qwen3.5-4B-Q4_K_M-vendor-sampling.gguf"},
	{"id": "litertlm-gemma4-e2b-cpu", "label": "Gemma 4 E2B, LiteRT-LM CPU", "engine": "LiteRT-LM", "backend": "CPU", "model": "hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm"},
	{"id": "litertlm-gemma4-e2b-gpu", "label": "Gemma 4 E2B, LiteRT-LM GPU", "engine": "LiteRT-LM", "backend": "GPU", "model": "hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it.litertlm"},
	{"id": "litertlm-gemma4-e2b-gpu-file", "label": "Gemma 4 E2B (GPU file), LiteRT-LM GPU", "engine": "LiteRT-LM", "backend": "GPU", "model": "hf://litert-community/gemma-4-E2B-it-litert-lm/gemma-4-E2B-it-gpu.litertlm"},
	{"id": "litertlm-gemma4-e4b-cpu", "label": "Gemma 4 E4B, LiteRT-LM CPU", "engine": "LiteRT-LM", "backend": "CPU", "model": "hf://litert-community/gemma-4-E4B-it-litert-lm/gemma-4-E4B-it.litertlm"},
	{"id": "litertlm-gemma4-e4b-gpu", "label": "Gemma 4 E4B, LiteRT-LM GPU", "engine": "LiteRT-LM", "backend": "GPU", "model": "hf://litert-community/gemma-4-E4B-it-litert-lm/gemma-4-E4B-it.litertlm"},
	{"id": "litertlm-gemma4-e4b-gpu-file", "label": "Gemma 4 E4B (GPU file), LiteRT-LM GPU", "engine": "LiteRT-LM", "backend": "GPU", "model": "hf://litert-community/gemma-4-E4B-it-litert-lm/gemma-4-E4B-it-gpu.litertlm"},
	{"id": "gemini-nano", "label": "Gemini Nano, Android AICore", "engine": "Gemini Nano", "backend": "NPU", "model": ""},
]

## "auto", or the id of one of SETUPS. A setup is tried as it is, with no other to fall back on.
@export var setup_id: String = "auto"
## What "auto" tries after Gemini Nano, in order, where the LiteRtLm plugin is there; each that will
## not start gives way to the next, and the last to NobodyWho. Measured on a Galaxy S24 Ultra
## (BENCHMARKS.md), Gemma 4 E2B on LiteRT-LM's GPU answers in about 2 s at 28 tokens a second,
## twenty times what NobodyWho manages with the same model; both use the same file, so falling back
## to the CPU downloads nothing more. (The smaller -gpu files are faster still, but write nonsense
## on that phone.)
@export var auto_setups: PackedStringArray = PackedStringArray(["litertlm-gemma4-e2b-gpu", "litertlm-gemma4-e2b-cpu"])
## The NobodyWho model for "auto": an hf:// path to a .gguf, or "auto" to pick the largest that fits
## the memory free now (from 0.6B to 27B parameters, see NobodyWho's model_selection.rs). One named by
## path that will not load gives way to "auto". The phone app names Gemma 4 E2B, the open model
## Gemini Nano 4 is built on, since its phone's AICore may not offer Gemini Nano itself.
@export var model_path: String = "auto"
@export var context_tokens: int = 4096
## The last messages kept in mind for Gemini Nano, which takes one prompt rather than a chat.
@export var max_history: int = 6
@export var mind: Mind
## Where every download, start and answer is recorded (LlmMetrics). "" records nothing.
@export var metrics_path: String = ""
## Who the duck is here. Its name, personality and memories come from `mind`.
@export_multiline var role: String = "You are a friendly little rubber duck who lives on the user's phone and keeps them company. Chat happily about whatever they bring up and follow the conversation. When they bring you a coding problem, be a great rubber duck: ask one sharp question at a time. Your answers are read aloud, so keep each turn to two or three short sentences, with no lists, markdown or emoji."

## Which engine answers: "Gemini Nano", "LiteRT-LM" or "NobodyWho", "" until one is ready.
var engine: String = ""
var model_name: String = ""
var status: String = "Not started."
## Set once the model has been stopped, from the Stats tab or as the app goes to the background.
var stopped: bool = false
## The benchmark these metrics belong to, "" in everyday use.
var run: String = ""
var _starting: bool = false
## Counts starts, so a model that finishes loading after stop() is dropped rather than kept.
var _session: int = 0
var _nano: Object = null
var _litert: Object = null
var _chat: Variant = null
var _http: HTTPRequest = null
## The LiteRT-LM setup being started or running, and where "auto" has got to in `auto_setups` (-1
## when it is not working through them).
var _litert_setup: Dictionary = {}
var _auto_index: int = -1
var _busy: bool = false
var _request: int = 0
## The answer being written, how much of it has gone out as sentences, and the line it answers.
var _raw: String = ""
var _sent_upto: int = 0
var _asked: String = ""
var _history: Array[Dictionary] = []
## The clock (seconds) for the metrics: when this start began, when its download finished (0 for
## none yet), and whether there was one; when the answer was asked for, and its first piece and
## sentence came; answers since the model started, and pieces in this one.
var _began_at: float = 0.0
var _downloaded_at: float = 0.0
var _download_seen: bool = false
var _asked_at: float = 0.0
var _first_piece_at: float = 0.0
var _first_sentence_at: float = 0.0
var _turn: int = 0
var _pieces: int = 0


func is_ready() -> bool:
	return not engine.is_empty()


func is_busy() -> bool:
	return _busy


func is_starting() -> bool:
	return _starting


## The setup `id` names, {} for "auto" or one not in SETUPS.
static func setup_for(id: String) -> Dictionary:
	for setup: Dictionary in SETUPS:
		if setup["id"] == id:
			return setup
	return {}


## Starts the model `setup_id` names. Says how it goes through `status_changed`.
func start() -> void:
	if is_ready() or _starting:
		return
	_starting = true
	stopped = false
	_session += 1
	_began_at = _now()
	_downloaded_at = 0.0
	_download_seen = false
	_auto_index = -1
	var setup: Dictionary = setup_for(setup_id)
	match str(setup.get("engine", "auto")):
		"NobodyWho":
			_start_nobodywho("", setup["model"])
		"LiteRT-LM":
			_start_litert(setup)
		_:
			if Engine.has_singleton("GeminiNano"):
				_start_nano()
			elif setup.is_empty():
				_start_auto("", 0)
			else:
				_fail("Gemini Nano needs the GeminiNano Android plugin, which is not in this build.")


## Sends the user's line; the answer comes through `sentence` and `replied`. False while busy or
## not ready.
func ask(line: String) -> bool:
	if not is_ready() or _busy or line.strip_edges().is_empty():
		return false
	if mind != null:
		mind.heed(line)
		mind.record("user", line)
	_busy = true
	_raw = ""
	_sent_upto = 0
	_asked = line
	_request += 1
	_turn += 1
	_pieces = 0
	_asked_at = _now()
	_first_piece_at = 0.0
	_first_sentence_at = 0.0
	match engine:
		"Gemini Nano":
			_nano.call("ask", _request, nano_prompt(system_prompt(), _history, line), 0.7)
		"LiteRT-LM":
			_litert.call("ask", _request, line)
		_:
			_stream_nobodywho(_chat.ask(line), _request)
	_history.append({"role": "user", "content": line})
	return true


## Starts again with nothing said: the duck keeps its memories and personality.
func new_conversation() -> void:
	if mind != null:
		mind.new_conversation()
	new_conversation_from([])


## Takes up a conversation already had, [{role, content}]: its last messages are in mind again.
func new_conversation_from(messages: Array) -> void:
	_history.clear()
	for message: Variant in messages:
		if message is Dictionary and str(message.get("role", "")) in ["user", "assistant"]:
			_history.append({"role": str(message["role"]), "content": str(message.get("content", ""))})
	_history = _history.slice(maxi(0, _history.size() - max_history))
	if engine == "LiteRT-LM":
		_litert.call("reset", system_prompt(), JSON.stringify(_history))
	if _chat != null:
		_chat.reset_chat(system_prompt(), [])
		# NobodyWho's history must end with the user's line, so only an exchange that does is restored.
		if not _history.is_empty() and _history[-1]["role"] == "user":
			_chat.set_chat_history(_history)


## Lets go of the model and its memory: a new start() loads it again.
func stop() -> void:
	_request += 1
	_session += 1
	stopped = true
	if _chat != null:
		_chat.stop_generation()
	_chat = null
	engine = ""
	model_name = ""
	_busy = false
	_starting = false
	if _http != null:
		_http.cancel_request()
		DirAccess.remove_absolute(_http.download_file)
		_http.queue_free()
		_http = null
	if _nano != null:
		_nano.call("release")
	if _litert != null:
		_litert.call("release")
	_set_status("Stopped: the model is not loaded. Start it again on the Stats tab.")


func system_prompt() -> String:
	return "%s\n\n%s" % [mind.stable_prompt() if mind != null else "", role]


## The folders models are downloaded to: NobodyWho's and LiteRT-LM's.
static func model_folders() -> PackedStringArray:
	return PackedStringArray([OS.get_cache_dir().path_join("nobodywho").path_join("models"), OS.get_cache_dir().path_join("litertlm")])


## Deletes every model under `folders`, any download left unfinished, and what LiteRT-LM compiled
## for the GPU, so the next start is as from a fresh install. Returns the bytes freed.
static func clear_models(folders: PackedStringArray) -> int:
	var freed: int = 0
	for folder: String in folders:
		freed += remove_tree(folder.path_join("compiled"))
		freed += prune_models(folder, "")
	return freed


## Keeps only the model at `path`: an older one, or a download cut short, would sit in the phone's
## storage for nothing.
func _keep_only(path: String) -> void:
	var freed: int = 0
	for folder: String in model_folders():
		freed += prune_models(folder, path)
	if freed > 0:
		print("Local LLM: removed %d MB of models no longer used" % (freed / 1000000))


## "auto" after Gemini Nano: the setup at `index` in `auto_setups`, where this build can run
## LiteRT-LM, or once they are all tried, NobodyWho. `why` says what happened before.
func _start_auto(why: String, index: int) -> void:
	if Engine.has_singleton("LiteRtLm") and index < auto_setups.size():
		_auto_index = index
		_start_litert(setup_for(auto_setups[index]))
		return
	_auto_index = -1
	_start_nobodywho(why)


func _start_nano() -> void:
	_nano = Engine.get_singleton("GeminiNano")
	if not _nano.is_connected("nano_status", _on_nano_status):
		_nano.connect("nano_status", _on_nano_status)
		_nano.connect("nano_chunk", _on_nano_chunk)
		_nano.connect("nano_done", _on_nano_done)
		_nano.connect("nano_failed", _on_nano_failed)
	_set_status("Asking the phone for Gemini Nano...")
	_nano.call("prepare")


## Loads `wanted`, or `model_path` when "", through NobodyWho. In "auto", a model named by path that
## will not load (the memory is short, the download failed) gives way to "auto".
func _start_nobodywho(why: String, wanted: String = "") -> void:
	if not ClassDB.class_exists(&"NobodyWhoChat"):
		_fail(("%s " % why if not why.is_empty() else "") + "No model can run on this phone: NobodyWho is not in this build.")
		return
	_starting = true
	# "auto" picks by the memory free at that moment, so it can pick another model on another day;
	# once one is downloaded, it is the duck's model from then on.
	var cache: String = model_folders()[0]
	var path: String = wanted if not wanted.is_empty() else model_path
	if path == "auto" and not newest_model_file(cache).is_empty():
		path = newest_model_file(cache)
		_set_status(("%s " % why if not why.is_empty() else "") + "Waking %s up..." % model_label(path.get_base_dir().get_file()))
	elif FileAccess.file_exists(cached_path(cache, path)):
		_set_status("Waking %s up..." % model_label(path.get_base_dir().get_file()))
	else:
		_set_status(("%s " % why if not why.is_empty() else "") + "Fetching the model (the first time only: 1 to 5 GB, a few minutes on Wi-Fi)...")
	var session: int = _session
	var pending: Variant = ClassDB.class_call_static(&"NobodyWhoChat", &"create", path, {"system_prompt": system_prompt(), "n_ctx": context_tokens})
	# NobodyWho says nothing while it downloads, so the file it is writing is watched instead.
	var watch: Timer = Timer.new()
	watch.wait_time = 1.0
	watch.timeout.connect(_show_download)
	add_child(watch)
	watch.start()
	var chat: Variant = await pending
	watch.queue_free()
	if session != _session:
		# Stopped while it loaded: let it go at once.
		return
	if chat == null and path.begins_with("hf://") and setup_id == "auto":
		_start_nobodywho("%s would not load here, so another model that fits is used." % model_label(path.get_base_dir().get_file()), "auto")
		return
	if chat == null:
		_fail("The model would not load. Check the Wi-Fi for the first download, then try again.")
		return
	var loaded: String = newest_model_file(cache) if path == "auto" else cached_path(cache, path)
	_downloaded(loaded)
	_chat = chat
	# Reasoning models think aloud first, which reads badly when spoken.
	await _chat.set_template_variable("enable_thinking", false)
	_ready_with("NobodyWho", model_label(loaded.get_base_dir().get_file()) if not loaded.is_empty() else "picked by memory", {})
	if not loaded.is_empty() and loaded.begins_with(cache):
		_keep_only(loaded)


## The model being downloaded and how far it has got, from the file NobodyWho is writing; once the
## file is whole, the download is timed.
func _show_download() -> void:
	var found: Dictionary = partial_download(model_folders()[0])
	if found.is_empty():
		if _download_seen and _downloaded_at == 0.0:
			_downloaded_at = _now()
		return
	_download_seen = true
	model_name = found["model"]
	_set_status("Fetching %s (the first time only): %d MB so far..." % [found["model"], found["bytes"] / 1000000])


## Records the download of `path`, if there was one, once it is whole.
func _downloaded(path: String) -> void:
	if not _download_seen:
		return
	if _downloaded_at == 0.0:
		_downloaded_at = _now()
	var size: int = 0
	if FileAccess.file_exists(path):
		var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
		size = handle.get_length() if handle != null else 0
	var took: float = _downloaded_at - _began_at
	_record("download", {"mb": size / 1000000, "seconds": snappedf(took, 0.01), "mb_per_s": snappedf(size / 1000000.0 / maxf(took, 0.001), 0.1)})


## Downloads the setup's .litertlm if it is not here yet, then starts LiteRT-LM on it.
func _start_litert(setup: Dictionary) -> void:
	if not Engine.has_singleton("LiteRtLm"):
		_fail("LiteRT-LM needs the GeminiNano Android plugin, which is not in this build.")
		return
	_litert = Engine.get_singleton("LiteRtLm")
	if not _litert.is_connected("litert_status", _on_litert_status):
		_litert.connect("litert_status", _on_litert_status)
		_litert.connect("litert_chunk", _on_litert_chunk)
		_litert.connect("litert_done", _on_litert_done)
		_litert.connect("litert_failed", _on_litert_failed)
	_litert_setup = setup
	var file: String = litert_path(model_folders()[1], setup["model"])
	var session: int = _session
	if not FileAccess.file_exists(file):
		if not await _download(hf_url(setup["model"]), file, setup["label"]):
			if session == _session:
				_fail("The model did not download. Check the Wi-Fi, then try again.")
			return
	_set_status("Waking %s up..." % setup["label"])
	# LiteRT-LM keeps what it compiles for the GPU here, and will not start if the folder is missing.
	var compiled: String = model_folders()[1].path_join("compiled")
	DirAccess.make_dir_recursive_absolute(compiled)
	_litert.call("load", _session, file, setup["backend"], compiled, system_prompt(), JSON.stringify(_history))


## Downloads `url` to `file`, through a .part file that is renamed once whole, saying how far it has
## got. True once it is there.
func _download(url: String, file: String, label: String) -> bool:
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	_http = HTTPRequest.new()
	_http.download_file = file + ".part"
	_http.use_threads = true
	_http.download_chunk_size = 4 * 1024 * 1024
	add_child(_http)
	_download_seen = true
	var http: HTTPRequest = _http
	var watch: Timer = Timer.new()
	watch.wait_time = 1.0
	watch.timeout.connect(_show_fetch.bind(http, label))
	add_child(watch)
	watch.start()
	var ok: bool = http.request(url) == OK
	if ok:
		var result: Array = await http.request_completed
		ok = result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	watch.queue_free()
	if http != _http:
		# Stopped while it downloaded: stop() has let it go.
		return false
	_http = null
	http.queue_free()
	if not ok or DirAccess.rename_absolute(file + ".part", file) != OK:
		DirAccess.remove_absolute(file + ".part")
		return false
	_downloaded_at = _now()
	_downloaded(file)
	return true


func _show_fetch(http: HTTPRequest, label: String) -> void:
	if not is_instance_valid(http):
		return
	var took: float = maxf(_now() - _began_at, 0.001)
	var got: float = http.get_downloaded_bytes() / 1000000.0
	var size: int = http.get_body_size()
	_set_status("Fetching %s (the first time only): %d%s MB, %.0f MB/s..." % [label, int(got), (" of %d" % (size / 1000000)) if size > 0 else "", got / took])


## Where a LiteRT-LM model hf://owner/repo/file is kept under `folder`: folder/owner/repo/file.
static func litert_path(folder: String, model: String) -> String:
	return folder.path_join(model.trim_prefix("hf://"))


## The download address of hf://owner/repo/file on Hugging Face.
static func hf_url(model: String) -> String:
	var parts: PackedStringArray = model.trim_prefix("hf://").split("/")
	return "https://huggingface.co/%s/%s/resolve/main/%s" % [parts[0], parts[1], "/".join(parts.slice(2))]


func _on_litert_status(load_number: int, state: String, detail: String) -> void:
	if load_number != _session or stopped:
		return
	if state != "ready":
		_fail("LiteRT-LM could not start the model: %s" % detail)
		return
	_ready_with("LiteRT-LM", _litert_setup.get("label", ""), {"init_s": float(detail)})
	_keep_only(litert_path(model_folders()[1], _litert_setup["model"]))


func _on_litert_chunk(request: int, text: String) -> void:
	if request == _request:
		_take(text)


func _on_litert_done(request: int, text: String, benchmark: String) -> void:
	if request == _request:
		var timings: Variant = JSON.parse_string(benchmark)
		_finish(text if not text.is_empty() else _raw, timings if timings is Dictionary else {})


func _on_litert_failed(request: int, message: String) -> void:
	if request == _request:
		_finish(_raw if not _raw.is_empty() else "My little brain hiccupped: %s" % message)


## The model is loaded and answering: the warm-up is timed from the end of its download.
func _ready_with(which: String, label: String, extra: Dictionary) -> void:
	_starting = false
	_auto_index = -1
	engine = which
	model_name = label
	_turn = 0
	var timing: Dictionary = {"seconds": snappedf(_now() - (_downloaded_at if _downloaded_at > 0.0 else _began_at), 0.01)}
	timing.merge(extra)
	_record("load", timing)
	_set_status("Ready, thinking on this phone.")


## Says why the model did not start; in "auto", the next one is tried instead.
func _fail(why: String) -> void:
	_record("failed", {"why": why})
	if _auto_index >= 0:
		_start_auto(why, _auto_index + 1)
		return
	_starting = false
	_set_status(why)


## The model a download was for, by its repository's folder ("Qwen_Qwen3.5-2B-GGUF" says
## "Qwen 3.5 2B"), and its size so far, from the .part file under `folder`. {} for none.
static func partial_download(folder: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(folder):
		return {}
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".part"):
			var handle: FileAccess = FileAccess.open(folder.path_join(file), FileAccess.READ)
			var size: int = handle.get_length() if handle != null else 0
			return {"model": model_label(folder.get_file()), "bytes": size}
	for sub: String in DirAccess.get_directories_at(folder):
		var found: Dictionary = partial_download(folder.path_join(sub))
		if not found.is_empty():
			return found
	return {}


## Deletes every model under `folder` but `keep` (.gguf and .litertlm files), any download left
## unfinished, and the folders they leave empty. Returns the bytes freed.
static func prune_models(folder: String, keep: String) -> int:
	var freed: int = 0
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	for sub: String in DirAccess.get_directories_at(folder):
		freed += prune_models(folder.path_join(sub), keep)
	for file: String in DirAccess.get_files_at(folder):
		var path: String = folder.path_join(file)
		if path != keep and (file.ends_with(".gguf") or file.ends_with(".litertlm") or file.ends_with(".part")):
			freed += _remove_file(path)
	if DirAccess.get_files_at(folder).is_empty() and DirAccess.get_directories_at(folder).is_empty() and not keep.begins_with(folder):
		DirAccess.remove_absolute(folder)
	return freed


## Deletes `folder` and everything in it. Returns the bytes freed.
static func remove_tree(folder: String) -> int:
	var freed: int = 0
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	for sub: String in DirAccess.get_directories_at(folder):
		freed += remove_tree(folder.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		freed += _remove_file(folder.path_join(file))
	DirAccess.remove_absolute(folder)
	return freed


static func _remove_file(path: String) -> int:
	var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
	var size: int = handle.get_length() if handle != null else 0
	handle = null
	return size if DirAccess.remove_absolute(path) == OK else 0


## Where NobodyWho keeps an hf://owner/repo/file model under `cache`: cache/owner/repo/file. Any other
## path is itself.
static func cached_path(cache: String, path: String) -> String:
	return cache.path_join(path.trim_prefix("hf://")) if path.begins_with("hf://") else path


## The newest model file downloaded under `folder`, "" for none.
static func newest_model_file(folder: String) -> String:
	var newest: String = ""
	var newest_time: int = -1
	var folders: Array[String] = [folder]
	while not folders.is_empty():
		var at: String = folders.pop_back()
		if not DirAccess.dir_exists_absolute(at):
			continue
		for sub: String in DirAccess.get_directories_at(at):
			folders.append(at.path_join(sub))
		for file: String in DirAccess.get_files_at(at):
			if file.ends_with(".gguf"):
				var changed: int = FileAccess.get_modified_time(at.path_join(file))
				if changed > newest_time:
					newest_time = changed
					newest = at.path_join(file)
	return newest


## A model repository's name as it is said: "Qwen_Qwen3.5-2B-GGUF" is "Qwen 3.5 2B",
## "Google_Gemma4-E4B-GGUF" is "Gemma 4 E4B".
static func model_label(repository: String) -> String:
	var name: String = repository.trim_suffix("-GGUF")
	var owner: int = name.find("_")
	if owner >= 0:
		name = name.substr(owner + 1)
	name = RegEx.create_from_string(r"^([A-Za-z]+)(\d)").sub(name, "$1 $2")
	return name.replace("-", " ")


func _stream_nobodywho(stream: Variant, request: int) -> void:
	while true:
		var token: Variant = await stream.next_token()
		if request != _request:
			return
		if token == null:
			break
		_take(str(token))
	_finish(_raw)


func _on_nano_status(state: String, detail: String) -> void:
	if stopped:
		return
	match state:
		"ready":
			_ready_with("Gemini Nano", "Gemini Nano, Android AICore", {})
		"downloading":
			_set_status("Fetching Gemini Nano (the first time only)... %s" % detail)
		_:
			if setup_id == "auto":
				_start_auto("Gemini Nano is not available here (%s)." % detail, 0)
			else:
				_fail("Gemini Nano is not available here (%s)." % detail)


func _on_nano_chunk(request: int, text: String) -> void:
	if request == _request:
		_take(text)


func _on_nano_done(request: int, text: String) -> void:
	if request == _request:
		_finish(text if not text.is_empty() else _raw)


func _on_nano_failed(request: int, message: String) -> void:
	if request == _request:
		_finish(_raw if not _raw.is_empty() else "My little brain hiccupped: %s" % message)


## More of the answer: every whole sentence in it goes out at once.
func _take(piece: String) -> void:
	if _first_piece_at == 0.0:
		_first_piece_at = _now()
	_pieces += 1
	_raw += piece
	var found: Array = whole_sentences(_raw, _sent_upto)
	_sent_upto = found[1]
	for said: String in found[0]:
		_say(said)


## The answer is whole: it is said, remembered and timed. `timings` are the engine's own, where it
## keeps them (LiteRT-LM).
func _finish(text: String, timings: Dictionary = {}) -> void:
	_raw = text
	var rest: String = text.substr(_sent_upto).strip_edges()
	if not rest.is_empty():
		_say(rest)
	var reply: String = spoken(text)
	if mind != null:
		mind.digest(text, _asked)
		mind.record("assistant", reply)
	_history.append({"role": "assistant", "content": reply})
	_history = _history.slice(maxi(0, _history.size() - max_history))
	_busy = false
	_record("answer", answer_metrics(_asked_at, _first_piece_at, _first_sentence_at, _now(), _turn, _pieces, reply.length(), timings))
	replied.emit(reply)


## One answer's metrics, from the clock readings (seconds) around it. A rate needs pieces after the
## first; LiteRT-LM's own `timings` take the place of what they also measure.
static func answer_metrics(asked: float, first_piece: float, first_sentence: float, done: float, turn: int, pieces: int, chars: int, timings: Dictionary) -> Dictionary:
	var found: Dictionary = {"turn": turn, "total_s": snappedf(done - asked, 0.001), "chars": chars, "pieces": pieces}
	if first_piece > 0.0:
		found["first_word_s"] = snappedf(first_piece - asked, 0.001)
		if pieces > 1 and done > first_piece:
			found["decode_tps"] = snappedf((pieces - 1) / (done - first_piece), 0.1)
	if first_sentence > 0.0:
		found["first_sentence_s"] = snappedf(first_sentence - asked, 0.001)
	for key: String in timings:
		found[key] = snappedf(float(timings[key]), 0.001)
	return found


func _say(text: String) -> void:
	var said: String = spoken(text)
	if not said.is_empty():
		if _first_sentence_at == 0.0:
			_first_sentence_at = _now()
		sentence.emit(said)


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


func _record(kind: String, extra: Dictionary) -> void:
	var setup: Dictionary = setup_for(setup_id)
	var entry: Dictionary = {
		"kind": kind,
		"setup": setup_id,
		"label": setup.get("label", "Auto: %s, %s" % [model_name, engine]),
		"engine": setup.get("engine", engine),
		"backend": setup.get("backend", ""),
		"run": run,
	}
	entry.merge(extra, true)
	LlmMetrics.record(entry, metrics_path)


static func _now() -> float:
	return Time.get_ticks_usec() / 1000000.0


## The whole sentences in `text` after `from`, and where the last of them ends: a sentence ends at
## . ! or ? followed by a space or a line break.
static func whole_sentences(text: String, from: int) -> Array:
	var found: PackedStringArray = PackedStringArray()
	var ends: RegEx = RegEx.create_from_string(r"[.!?]+[\"')\]]*(?=\s)")
	var at: int = from
	for hit: RegExMatch in ends.search_all(text, from):
		var said: String = text.substr(at, hit.get_end() - at).strip_edges()
		if not said.is_empty():
			found.append(said)
		at = hit.get_end()
	return [found, at]


## `text` as it may be said: no memory tags, no emoji, no markdown marks.
static func spoken(text: String) -> String:
	var said: String = Brain.speakable(text)
	said = RegEx.create_from_string("[\\x{1F000}-\\x{1FFFF}\\x{2600}-\\x{27BF}\\x{FE0F}\\x{200D}]").sub(said, "", true)
	said = RegEx.create_from_string(r"[*_#`]").sub(said, "", true)
	return RegEx.create_from_string(r"\s{2,}").sub(said, " ", true).strip_edges()


## One prompt for a model that takes no chat, such as Gemini Nano: who it is, the last messages,
## and the user's line, ending where the duck's answer begins.
static func nano_prompt(system: String, history: Array[Dictionary], line: String) -> String:
	var parts: PackedStringArray = PackedStringArray([system.strip_edges(), ""])
	for message: Dictionary in history:
		parts.append("%s: %s" % ["User" if message.get("role") == "user" else "Duck", message.get("content", "")])
	parts.append("User: " + line)
	parts.append("Duck:")
	return "\n".join(parts)
