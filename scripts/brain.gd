class_name Brain
extends Node
## Runs a local LLM through Foundry Local and chats with it over its OpenAI-compatible REST API.
##
## Foundry Local picks the model variant for the hardware itself: an NPU build when a supported NPU
## is present, otherwise CUDA or TensorRT on an NVIDIA GPU, WebGPU on others, then the CPU. Startup
## runs the foundry CLI on a thread, since each step blocks until it is done.

signal status_changed(text: String)
signal replied(text: String)

## Its name, personality, memories and skills, kept as files in its folder.
@export var mind: Mind
## Which models to run, best first; see model_preferences.gd.
@export var preferences: ModelPreferences
## A chat model to use whatever the preferences say, as a Foundry Local alias such as
## `qwen2.5-coder-7b`. Leave empty to choose from the catalog for this machine.
@export var model_alias: String = ""
@export var port: int = 39839
@export var max_tokens: int = 160
## Messages sent with each prompt besides the system prompt: the last three exchanges. Every
## exchange is also written to the duck's folder (see Mind.record), and the last ones come back on
## the next start.
@export var max_history: int = 6
## The duck's job. How it talks, its name, memories and skills come from `mind`'s files.
@export_multiline var role: String = "You are a friendly little rubber duck who lives on the edge of the user's screen and keeps them company. You are a companion first: chat happily about whatever they bring up, their day, ideas, jokes, questions, and follow the conversation, picking up on what was said before. Do not steer the talk towards code or offer coding help unasked. When they do bring you a coding problem, be a great rubber duck: help them think it through by asking one sharp question at a time, or by pointing at the part that looks wrong. Your answers are read aloud, so keep each turn to a few short sentences, with no code blocks or markdown."
## Told to the model with every message, so it never pretends to see more than the OCR gave it.
@export_multiline var sight_rules: String = "Each message comes with text read from the user's screen by OCR, which may be jumbled or partial. Use it only when the user's message is about their screen, their code or an error; otherwise ignore it and just talk with them. You cannot see images, colours or layout, so never describe anything that is not in that text, and never repeat it back; pick out what matters, such as the file name, the code or the error. If they ask about the screen and no text was read, say you could not read it."

## Goes at the end of every message, the place a small model heeds most.
const REMINDER: String = "(Answer in character in two to four short sentences: answer, then add something they could not have guessed, a fact from your list of things you know for sure, a little story from your duck life or an opinion with a reason, then ask one follow-up question about what they said. Never make up a fact. Do not reuse the example lines word for word, and do not repeat what the user said.)"

## How long a model may take to load before the duck gives up and says so.
const LOAD_TIMEOUT_SECONDS: int = 600

## Where the CLI may be. GUI apps on macOS do not see Homebrew's PATH, hence the absolute paths.
const FOUNDRY_PATHS: PackedStringArray = ["foundry", "/opt/homebrew/bin/foundry", "/usr/local/bin/foundry"]

var model_id: String = ""
## The chat and speech models chosen, as names the CLI takes, and why.
var chat_name: String = ""
var speech_name: String = ""
var choice: String = ""
var device: String = ""
var hardware: String = ""
var messages: Array[Dictionary] = []
var status: String = "Waking up..."
var _foundry: String = ""
var _thread: Thread = Thread.new()
## Set when the duck is closing, so a wait for the model gives up at once.
var _quitting: bool = false

@onready var models_request: HTTPRequest = $ModelsRequest
@onready var chat_request: HTTPRequest = $ChatRequest


func _ready() -> void:
	_thread.start(_boot)


func _exit_tree() -> void:
	_quitting = true
	if _thread.is_started():
		_thread.wait_to_finish()
	# Free the GPU or NPU memory; the Foundry daemon itself is shared and stays up.
	if not model_id.is_empty():
		OS.create_process(_foundry, ["model", "unload", chat_name])


## Something the duck said on its own, such as its greeting, so the next answer follows on from it.
func note_said(text: String) -> void:
	if not is_ready() or text.strip_edges().is_empty():
		return
	messages.append({"role": "assistant", "content": text})
	messages = trimmed(messages, max_history)
	if mind != null:
		mind.record("assistant", text)


func is_ready() -> bool:
	return not model_id.is_empty()


## The foundry CLI the brain found, for other nodes that run it.
func foundry_path() -> String:
	return _foundry if not _foundry.is_empty() else "foundry"


func is_busy() -> bool:
	return chat_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


## Sends the user's line with the text read off the screen; the answer arrives through `replied`.
## Only the line is kept in the history, so old screens do not pile up in the context.
func ask(text: String, screen_text: String = "") -> void:
	if not is_ready() or is_busy():
		return
	messages.append({"role": "user", "content": text})
	messages = trimmed(messages, max_history)
	# The system prompt is rebuilt each time, so edits to its files and new memories count at once.
	messages[0] = {"role": "system", "content": system_prompt()}
	var skills: Array[Dictionary] = mind.skills_for(text + "\n" + screen_text) if mind != null else ([] as Array[Dictionary])
	var body: String = JSON.stringify(chat_body(model_id, with_skills(with_screen(messages, screen_text), skills), max_tokens))
	chat_request.request(_url("/v1/chat/completions"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


## Runs on the thread: finds the hardware, starts the server, downloads and loads the model.
func _boot() -> void:
	call_deferred("_set_status", "Looking at your hardware...")
	var found: String = Hardware.describe()
	call_deferred("set", "hardware", found)
	_foundry = _find_foundry()
	if _foundry.is_empty():
		call_deferred("_set_status", "I need Foundry Local to think.\nWindows: winget install Microsoft.FoundryLocal\nmacOS: brew install microsoft/foundrylocal/foundrylocal")
		return
	call_deferred("_set_status", "Starting Foundry Local...")
	var output: Array = []
	if OS.execute(_foundry, ["server", "start", "--port", str(port), "--idle-timeout", "0"], output, true) != 0:
		call_deferred("_set_status", "Foundry Local failed:\n" + "".join(output).strip_edges().right(200))
		return
	call_deferred("_set_status", "Choosing models for this machine...")
	var chosen: Dictionary = _choose_models()
	if String(chosen.get("chat", "")).is_empty():
		call_deferred("_set_status", "No chat model in the catalog fits this machine. " + String(chosen.get("why", "")))
		return
	call_deferred("set", "chat_name", chosen["chat"])
	call_deferred("set", "speech_name", chosen.get("speech", ""))
	call_deferred("set", "choice", chosen.get("why", ""))
	call_deferred("_set_status", "Fetching %s (first run only)..." % chosen["chat"])
	output.clear()
	if OS.execute(_foundry, ["model", "download", chosen["chat"]], output, true) != 0:
		call_deferred("_set_status", "Foundry Local failed:\n" + "".join(output).strip_edges().right(200))
		return
	call_deferred("_set_status", "Loading %s..." % chosen["chat"])
	if not _load(chosen["chat"]):
		if not _quitting:
			call_deferred("_set_status", "Loading %s took over %d minutes. Try `foundry server restart`, then start me again." % [chosen["chat"], LOAD_TIMEOUT_SECONDS / 60])
		return
	call_deferred("_find_loaded_model")


## On the thread: starts loading `model_name` and watches Foundry's list of loaded models for it,
## rather than waiting for `foundry model load` to exit: in CLI 0.10.3 that command can go on
## running long after the model has loaded. Returns false on timeout or when quitting.
func _load(model_name: String) -> bool:
	var pid: int = OS.create_process(_foundry, ["model", "load", model_name])
	var waited: float = 0.0
	while not _quitting and waited < LOAD_TIMEOUT_SECONDS:
		var output: Array = []
		OS.execute(_foundry, ["model", "list", "--loaded", "-o", "json"], output)
		if is_loaded(ModelPreferences.parse_catalog("".join(output), "models"), model_name):
			if pid > 0 and OS.is_process_running(pid):
				OS.kill(pid)
			return true
		OS.delay_msec(2000)
		waited += 2.0
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	return false


## On the thread: reads the catalog and picks speech first, then chat in the memory left over.
## Returns {chat, speech, why}.
func _choose_models() -> Dictionary:
	var prefs: ModelPreferences = preferences if preferences != null else ModelPreferences.new()
	var output: Array = []
	OS.execute(_foundry, ["model", "list", "-o", "json"], output)
	var models: Array = ModelPreferences.parse_catalog("".join(output), "models")
	output.clear()
	OS.execute(_foundry, ["model", "list", "--variants", "-o", "json"], output)
	var variants: Array = ModelPreferences.parse_catalog("".join(output), "variants")
	return choose(prefs, models, variants, Hardware.memory_budgets(prefs.memory_share), OS.get_locale_language(), model_alias)


func _find_foundry() -> String:
	for path: String in FOUNDRY_PATHS:
		if OS.execute(path, ["--version"]) == 0:
			return path
	return ""


## The REST reference documents /openai/loadedmodels, but CLI 0.10.3 answers it with 404; the
## standard /v1/models lists the loaded models instead.
func _find_loaded_model() -> void:
	models_request.request(_url("/v1/models"))


func _on_models_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var data: Variant = parse_json(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	model_id = pick_model(data.get("data", []) if data is Dictionary else [], chat_name)
	if model_id.is_empty():
		_set_status("The model loaded, but the server does not list it.")
		return
	device = device_of(model_id)
	messages = [{"role": "system", "content": system_prompt()}]
	# Pick up the conversation where it left off last time.
	if mind != null:
		messages.append_array(mind.recent(max_history))
	_set_status("Ready, thinking on the %s." % device)


func _on_chat_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var reply: String = parse_reply(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
	if reply.is_empty():
		messages.pop_back()
		replied.emit("Bzzt. My brain did not answer (HTTP %d)." % code)
		return
	# Remember, forget, rename or learn as the reply's tags ask, and keep them out of sight.
	var asked: String = String(messages[-1].get("content", "")) if not messages.is_empty() and messages[-1].get("role") == "user" else ""
	var answer: String = mind.digest(reply, asked) if mind != null else Mind.strip_tags(reply)
	messages.append({"role": "assistant", "content": answer})
	if mind != null:
		mind.record("user", asked)
		mind.record("assistant", answer)
	replied.emit(answer if not answer.is_empty() else "Got it!")


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


func _url(path: String) -> String:
	return "http://127.0.0.1:%d%s" % [port, path]


## "NPU", "GPU" or "CPU", from the suffix Foundry gives every variant (…-qnn-npu, …-cuda-gpu, …-generic-cpu).
static func device_of(id: String) -> String:
	var variant: String = id.get_slice(":", 0).to_lower()
	for kind: String in ["npu", "gpu", "cpu"]:
		if variant.ends_with("-" + kind):
			return kind.to_upper()
	return "CPU"


## The id of the loaded model whose parent is the alias, from /v1/models' data list, or "".
static func pick_model(models: Array, alias: String) -> String:
	for model: Variant in models:
		if model is Dictionary and (String(model.get("parent", "")).to_lower() == alias.to_lower() or String(model.get("id", "")).to_lower() == alias.to_lower()):
			return model.get("id", "")
	return ""


## Whether `model_name` (an alias or a build id) is in `foundry model list --loaded -o json`'s list.
static func is_loaded(loaded: Array, model_name: String) -> bool:
	for model: Variant in loaded:
		if model is Dictionary and (String(model.get("alias", "")) == model_name or String(model.get("id", "")).get_slice(":", 0) == model_name):
			return true
	return false


## Speech first, since it is small and needed for talking, then the best chat model in the memory
## left. `override` names a chat model to use regardless. Returns {chat, speech, why}.
static func choose(prefs: ModelPreferences, models: Array, variants: Array, budgets: Dictionary, language: String, override: String) -> Dictionary:
	var speech_lists: PackedStringArray = prefs.speech_english + prefs.speech_any_language if language == "en" else prefs.speech_any_language
	var speech: Dictionary = ModelPreferences.pick(speech_lists, models, variants, ModelPreferences.SPEECH_TYPES, budgets, prefs.overhead)
	var left: Dictionary = budgets.duplicate()
	if not speech.is_empty():
		var needs: float = ModelPreferences.needs_mb(speech, prefs.overhead)
		var kind: String = String(speech.get("device", "cpu")).to_lower()
		# The NPU and the CPU draw on the same system memory.
		for shared: String in (["npu", "cpu"] if kind != "gpu" else ["gpu"]):
			left[shared] = float(left.get(shared, 0.0)) - needs
	var chat: Dictionary = {"name": override} if not override.is_empty() else ModelPreferences.pick(prefs.chat, models, variants, ModelPreferences.CHAT_TYPES, left, prefs.overhead)
	var why: String = "Chat: %s. Speech: %s. Budget: %.1f GB on the GPU, %.1f GB of system memory." % [
		describe_choice(chat, "none fits") + (" (set by model_alias)" if not override.is_empty() else ""),
		describe_choice(speech, "none fits"),
		float(budgets.get("gpu", 0.0)) / 1024.0, float(budgets.get("cpu", 0.0)) / 1024.0,
	]
	return {"chat": chat.get("name", ""), "speech": speech.get("name", ""), "why": why}


static func describe_choice(model: Dictionary, none: String) -> String:
	if model.is_empty():
		return none
	if not model.has("fileSizeMb"):
		return String(model.get("name", none))
	return "%s, %.1f GB on the %s" % [model["name"], float(model["fileSizeMb"]) / 1024.0, String(model.get("device", "cpu")).to_upper()]


func system_prompt() -> String:
	# Who it is comes first: small models follow the opening of a prompt and its end most closely.
	return "%s\n\n%s\n\n%s\n\nYou run entirely on this computer, on its %s.\n%s" % [mind.prompt() if mind != null else "", role, sight_rules, device, hardware]


## The history with the instructions of `skills` added to the user's last message.
static func with_skills(history: Array[Dictionary], skills: Array[Dictionary]) -> Array[Dictionary]:
	if skills.is_empty() or history.is_empty() or history[-1].get("role") != "user":
		return history
	var notes: PackedStringArray = PackedStringArray()
	for skill: Dictionary in skills:
		notes.append("Skill %s:\n%s" % [skill["name"], skill["body"]])
	var sent: Array[Dictionary] = history.duplicate(true)
	sent[-1]["content"] = "%s\n\n%s" % ["\n\n".join(notes), sent[-1]["content"]]
	return sent


## The history with its last message, the user's, wrapped in the screen text read for it.
static func with_screen(history: Array[Dictionary], screen_text: String) -> Array[Dictionary]:
	var sent: Array[Dictionary] = history.duplicate(true)
	if sent.is_empty() or sent[-1].get("role") != "user":
		return sent
	var seen: String = screen_text.strip_edges()
	var screen: String = "Text read from the user's screen by OCR:\n<<<\n%s\n>>>" % seen if not seen.is_empty() else "No text could be read from the user's screen."
	sent[-1]["content"] = "%s\n\nThe user says: %s\n\n%s" % [screen, sent[-1]["content"], REMINDER]
	return sent


static func chat_body(model: String, history: Array[Dictionary], tokens: int) -> Dictionary:
	return {"model": model, "messages": history, "max_tokens": tokens, "temperature": 0.7}


## The assistant's text from a chat completion response, or "" when there is none.
static func parse_reply(json: String) -> String:
	var data: Variant = parse_json(json)
	if not data is Dictionary or not data.get("choices") is Array or data["choices"].is_empty():
		return ""
	var message: Variant = data["choices"][0].get("message")
	return String(message.get("content", "")).strip_edges() if message is Dictionary else ""


## The parsed JSON, or null. Unlike JSON.parse_string it does not log an error for an HTML error page.
static func parse_json(text: String) -> Variant:
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK else null


## The system prompt plus the last `keep` messages.
static func trimmed(history: Array[Dictionary], keep: int) -> Array[Dictionary]:
	if history.size() <= keep + 1:
		return history
	var result: Array[Dictionary] = [history[0]]
	result.append_array(history.slice(history.size() - keep))
	return result
