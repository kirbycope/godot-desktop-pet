class_name Brain
extends Node
## Runs a local LLM through Foundry Local and chats with it over its OpenAI-compatible REST API.
##
## Foundry Local picks the model variant for the hardware itself: an NPU build when a supported NPU
## is present, otherwise CUDA or TensorRT on an NVIDIA GPU, WebGPU on others, then the CPU. Startup
## runs the foundry CLI on a thread, since each step blocks until it is done.

signal status_changed(text: String)
signal replied(text: String)

## Foundry Local catalog alias. `foundry model list` shows them all.
@export var model_alias: String = "qwen2.5-coder-7b"
@export var port: int = 39839
@export var max_tokens: int = 160
## Messages kept besides the system prompt, so the context stays small.
@export var max_history: int = 12
@export_multiline var personality: String = "You are a rubber duck debugging companion who sits on the edge of the user's screen. The user explains their code or problem to you out loud. Help them think it through: ask one sharp question, or point at the line or idea that looks wrong. Your answers are read aloud, so use one to three short sentences and no code blocks or markdown."
## Told to the model with every message, so it never pretends to see more than the OCR gave it.
@export_multiline var sight_rules: String = "You cannot see images, colours or layout. The only view you have of the screen is the text read from it by OCR, which comes with each message and may be jumbled or partial. Never describe anything that is not in that text. Never repeat the screen text back; pick out what matters, such as the file name, the code or the error, and talk about that. If no text was read, say you could not read the screen."

## Where the CLI may be. GUI apps on macOS do not see Homebrew's PATH, hence the absolute paths.
const FOUNDRY_PATHS: PackedStringArray = ["foundry", "/opt/homebrew/bin/foundry", "/usr/local/bin/foundry"]

var model_id: String = ""
var device: String = ""
var hardware: String = ""
var messages: Array[Dictionary] = []
var status: String = "Waking up..."
var _foundry: String = ""
var _thread: Thread = Thread.new()

@onready var models_request: HTTPRequest = $ModelsRequest
@onready var chat_request: HTTPRequest = $ChatRequest


func _ready() -> void:
	_thread.start(_boot)


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	# Free the GPU or NPU memory; the Foundry daemon itself is shared and stays up.
	if not model_id.is_empty():
		OS.create_process(_foundry, ["model", "unload", model_alias])


func is_ready() -> bool:
	return not model_id.is_empty()


func is_busy() -> bool:
	return chat_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


## Sends the user's line with the text read off the screen; the answer arrives through `replied`.
## Only the line is kept in the history, so old screens do not pile up in the context.
func ask(text: String, screen_text: String = "") -> void:
	if not is_ready() or is_busy():
		return
	messages.append({"role": "user", "content": text})
	messages = trimmed(messages, max_history)
	var body: String = JSON.stringify(chat_body(model_id, with_screen(messages, screen_text), max_tokens))
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
	var steps: Array[Array] = [
		["Starting Foundry Local...", ["server", "start", "--port", str(port), "--idle-timeout", "0"]],
		["Fetching %s (first run only)..." % model_alias, ["model", "download", model_alias]],
		["Loading %s..." % model_alias, ["model", "load", model_alias]],
	]
	for step: Array in steps:
		call_deferred("_set_status", step[0])
		var output: Array = []
		if OS.execute(_foundry, step[1], output, true) != 0:
			call_deferred("_set_status", "Foundry Local failed:\n" + "".join(output).strip_edges().right(200))
			return
	call_deferred("_find_loaded_model")


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
	model_id = pick_model(data.get("data", []) if data is Dictionary else [], model_alias)
	if model_id.is_empty():
		_set_status("The model loaded, but the server does not list it.")
		return
	device = device_of(model_id)
	messages = [{"role": "system", "content": "%s %s You run entirely on this computer, on its %s.\n%s" % [personality, sight_rules, device, hardware]}]
	_set_status("Ready, thinking on the %s." % device)


func _on_chat_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var reply: String = parse_reply(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else ""
	if reply.is_empty():
		messages.pop_back()
		replied.emit("Bzzt. My brain did not answer (HTTP %d)." % code)
		return
	messages.append({"role": "assistant", "content": reply})
	replied.emit(reply)


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
		if model is Dictionary and String(model.get("parent", "")).to_lower() == alias.to_lower():
			return model.get("id", "")
	return ""


## The history with its last message, the user's, wrapped in the screen text read for it.
static func with_screen(history: Array[Dictionary], screen_text: String) -> Array[Dictionary]:
	var sent: Array[Dictionary] = history.duplicate(true)
	if sent.is_empty() or sent[-1].get("role") != "user":
		return sent
	var seen: String = screen_text.strip_edges()
	var screen: String = "Text read from the user's screen by OCR:\n<<<\n%s\n>>>" % seen if not seen.is_empty() else "No text could be read from the user's screen."
	sent[-1]["content"] = "%s\n\nThe user says: %s" % [screen, sent[-1]["content"]]
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
