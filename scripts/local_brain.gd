class_name LocalBrain
extends Node
## The duck's brain on a phone with no PC: a model running on the phone itself. Gemini Nano through
## Android's AICore, on the phone's NPU, when the GeminiNano plugin is there and the phone has it;
## otherwise the largest model that fits through NobodyWho (llama.cpp, on the GPU). Its name,
## personality and memories are the phone's own Mind. Answers come sentence by sentence, as from the
## PC's Brain, for the phone to show and say in its own voice.
##
## NobodyWho is a GDExtension fetched into addons/nobodywho, so it is reached through ClassDB rather
## than by its class names: a checkout without it still loads and runs.

signal status_changed(text: String)
## One sentence of the answer, cleaned for saying aloud, as soon as it is written.
signal sentence(text: String)
## The whole answer, after the last sentence.
signal replied(text: String)

## The NobodyWho model, "auto" to pick the largest that fits the memory free now (from 0.6B to 27B
## parameters, see NobodyWho's model_selection.rs), or an hf:// path to a .gguf.
@export var model_path: String = "auto"
@export var context_tokens: int = 4096
## The last messages kept in mind for Gemini Nano, which takes one prompt rather than a chat.
@export var max_history: int = 6
@export var mind: Mind
## Who the duck is here. Its name, personality and memories come from `mind`.
@export_multiline var role: String = "You are a friendly little rubber duck who lives on the user's phone and keeps them company. Chat happily about whatever they bring up and follow the conversation. When they bring you a coding problem, be a great rubber duck: ask one sharp question at a time. Your answers are read aloud, so keep each turn to two or three short sentences, with no lists, markdown or emoji."

## Which model answers: "Gemini Nano" or "NobodyWho", "" until one is ready.
var engine: String = ""
var model_name: String = ""
var status: String = "Not started."
## Set once the model has been stopped, from the Stats tab or as the app goes to the background.
var stopped: bool = false
var _starting: bool = false
## Counts starts, so a model that finishes loading after stop() is dropped rather than kept.
var _session: int = 0
var _nano: Object = null
var _chat: Variant = null
var _busy: bool = false
var _request: int = 0
## The answer being written, how much of it has gone out as sentences, and the line it answers.
var _raw: String = ""
var _sent_upto: int = 0
var _asked: String = ""
var _history: Array[Dictionary] = []


func is_ready() -> bool:
	return not engine.is_empty()


func is_busy() -> bool:
	return _busy


func is_starting() -> bool:
	return _starting


## Finds a model: Gemini Nano first, then NobodyWho. Says how it goes through `status_changed`.
func start() -> void:
	if is_ready() or _starting:
		return
	_starting = true
	stopped = false
	_session += 1
	if Engine.has_singleton("GeminiNano"):
		_nano = Engine.get_singleton("GeminiNano")
		if not _nano.is_connected("nano_status", _on_nano_status):
			_nano.connect("nano_status", _on_nano_status)
			_nano.connect("nano_chunk", _on_nano_chunk)
			_nano.connect("nano_done", _on_nano_done)
			_nano.connect("nano_failed", _on_nano_failed)
		_set_status("Asking the phone for Gemini Nano...")
		_nano.call("prepare")
		return
	_start_nobodywho("")


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
	if engine == "Gemini Nano":
		_nano.call("ask", _request, nano_prompt(system_prompt(), _history, line), 0.7)
	else:
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
	if _nano != null:
		_nano.call("release")
	_set_status("Stopped: the model is not loaded. Start it again on the Stats tab.")


func system_prompt() -> String:
	return "%s\n\n%s" % [mind.stable_prompt() if mind != null else "", role]


func _start_nobodywho(why: String) -> void:
	if not ClassDB.class_exists(&"NobodyWhoChat"):
		_starting = false
		_set_status(("%s " % why if not why.is_empty() else "") + "No model can run on this phone: NobodyWho is not in this build.")
		return
	# "auto" picks by the memory free at that moment, so it can pick another model on another day;
	# once one is downloaded, it is the duck's model from then on.
	var cache: String = OS.get_cache_dir().path_join("nobodywho").path_join("models")
	var path: String = model_path
	if path == "auto" and not newest_model_file(cache).is_empty():
		path = newest_model_file(cache)
		_set_status(("%s " % why if not why.is_empty() else "") + "Waking %s up..." % model_label(path.get_base_dir().get_file()))
	else:
		_set_status(("%s " % why if not why.is_empty() else "") + "Fetching a model that fits this phone (the first time only: 1 to 3 GB, a few minutes on Wi-Fi)...")
	var session: int = _session
	var pending: Variant = ClassDB.class_call_static(&"NobodyWhoChat", &"create", path, {"system_prompt": system_prompt(), "n_ctx": context_tokens})
	# NobodyWho says nothing while it downloads, so the file it is writing is watched instead.
	var watch: Timer = Timer.new()
	watch.wait_time = 2.0
	watch.timeout.connect(_show_download)
	add_child(watch)
	watch.start()
	var chat: Variant = await pending
	watch.queue_free()
	if session != _session:
		# Stopped while it loaded: let it go at once.
		return
	_starting = false
	if chat == null:
		_set_status("The model would not load. Check the Wi-Fi for the first download, then try again.")
		return
	_chat = chat
	# Reasoning models think aloud first, which reads badly when spoken.
	await _chat.set_template_variable("enable_thinking", false)
	engine = "NobodyWho"
	var loaded: String = newest_model_file(cache) if path == "auto" else path
	model_name = model_label(loaded.get_base_dir().get_file()) if not loaded.is_empty() else "picked by memory"
	# Only the model in use is kept: an older one "auto" picked another day, or a download cut short,
	# would sit in the phone's storage for nothing.
	if not loaded.is_empty() and loaded.begins_with(cache):
		var freed: int = prune_models(cache, loaded)
		if freed > 0:
			print("Local LLM: removed %d MB of models no longer used" % (freed / 1000000))
	_set_status("Ready, thinking on this phone.")


## The model being downloaded and how far it has got, from the file NobodyWho is writing.
func _show_download() -> void:
	var found: Dictionary = partial_download(OS.get_cache_dir().path_join("nobodywho").path_join("models"))
	if found.is_empty():
		return
	model_name = found["model"]
	_set_status("Fetching %s (the first time only): %d MB so far..." % [found["model"], found["bytes"] / 1000000])


## The file still downloading under `folder`, as {model, bytes}: the model's name from its
## repository's folder ("Qwen_Qwen3.5-2B-GGUF" says "Qwen 3.5 2B"), and its size so far. {} for none.
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


## Deletes every model under `folder` but `keep`, and any download left unfinished, and the folders
## they leave empty. Returns the bytes freed.
static func prune_models(folder: String, keep: String) -> int:
	var freed: int = 0
	if not DirAccess.dir_exists_absolute(folder):
		return 0
	for sub: String in DirAccess.get_directories_at(folder):
		freed += prune_models(folder.path_join(sub), keep)
	for file: String in DirAccess.get_files_at(folder):
		var path: String = folder.path_join(file)
		if path != keep and (file.ends_with(".gguf") or file.ends_with(".part")):
			var handle: FileAccess = FileAccess.open(path, FileAccess.READ)
			var size: int = handle.get_length() if handle != null else 0
			handle = null
			if DirAccess.remove_absolute(path) == OK:
				freed += size
	if DirAccess.get_files_at(folder).is_empty() and DirAccess.get_directories_at(folder).is_empty() and not keep.begins_with(folder):
		DirAccess.remove_absolute(folder)
	return freed


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
			_starting = false
			engine = "Gemini Nano"
			model_name = "Gemini Nano, Android AICore"
			_set_status("Ready, thinking on this phone's NPU.")
		"downloading":
			_set_status("Fetching Gemini Nano (the first time only)... %s" % detail)
		_:
			_start_nobodywho("Gemini Nano is not available here (%s)." % detail)


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
	_raw += piece
	var found: Array = whole_sentences(_raw, _sent_upto)
	_sent_upto = found[1]
	for said: String in found[0]:
		_say(said)


func _finish(text: String) -> void:
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
	replied.emit(reply)


func _say(text: String) -> void:
	var said: String = spoken(text)
	if not said.is_empty():
		sentence.emit(said)


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


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
