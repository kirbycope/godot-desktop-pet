class_name Brain
extends Node
## Runs a local LLM through Foundry Local and chats with it over its OpenAI-compatible REST API.
##
## Foundry Local picks the model variant for the hardware itself: an NPU build when a supported NPU
## is present, otherwise CUDA or TensorRT on an NVIDIA GPU, WebGPU on others, then the CPU. Startup
## runs the foundry CLI on a thread, since each step blocks until it is done.

signal status_changed(text: String)
signal replied(text: String)
## Facts pulled out of web search results by `learn_facts`.
signal facts_found(facts: PackedStringArray)

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

## Goes in REMINDER's place while the user is working on code (see `is_debugging`).
const DEBUG_REMINDER: String = "(They are working on code, so be their rubber duck: no duck facts, stories or jokes this turn. In two or three short sentences, go through it step by step, name the line or step that looks wrong and say why in plain words, then ask one short question that helps them check it. If nothing looks wrong, ask what they expected to happen and what happened instead. It is read aloud, so no lists, headings or code blocks: quote a few words of code inline at most.)"
## Words and marks that say a line is about code or a bug.
const DEBUG_WORDS: String = r"(?i)\b(bugs?|crash\w*|errors?|exceptions?|traceback|broken|wrong|fix|debug\w*|stuck|doesn'?t work|does not work|not working|null|undefined|compil\w*|code|function|script|returns?)\b|\w\(\)|\w\.\w+\(|==|!=|[{};]"

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
## The last request's messages, kept to send it back once when the reply repeats itself.
var _sent: Array[Dictionary] = []
var _retried: bool = false
## Whether the last message was about code, so a retry asks for something new in the same vein.
var _debugging: bool = false

@onready var models_request: HTTPRequest = $ModelsRequest
@onready var chat_request: HTTPRequest = $ChatRequest
@onready var fact_request: HTTPRequest = $FactRequest


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


## Sends the user's line with the text read off the screen, and the web results when it asked for a
## search; the answer arrives through `replied`. Only the line is kept in the history, so old
## screens and results do not pile up in the context.
func ask(text: String, screen_text: String = "", web_text: String = "") -> void:
	if not is_ready() or is_busy():
		return
	messages.append({"role": "user", "content": text})
	messages = trimmed(messages, max_history)
	# The system prompt is rebuilt each time, so edits to its files and new memories count at once.
	messages[0] = {"role": "system", "content": system_prompt()}
	var skills: Array[Dictionary] = mind.skills_for(text + "\n" + screen_text) if mind != null else ([] as Array[Dictionary])
	# Debugging gets the rubber duck's reminder: no duck facts or jokes in the middle of a bug.
	_debugging = is_debugging(text, earlier_user_line(messages), screen_text)
	var reminder: String = DEBUG_REMINDER if _debugging else REMINDER
	_sent = with_skills(with_web(with_screen(messages, screen_text, reminder), web_text), skills)
	_retried = false
	var body: String = JSON.stringify(chat_body(model_id, _sent, max_tokens, _debugging))
	chat_request.request(_url("/v1/chat/completions"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


## Has the model pick out the facts that web search results state plainly, so the duck has new
## things to tell; they arrive through `facts_found`. Its own request, so it never holds up a reply.
func learn_facts(results: Array[Dictionary]) -> void:
	if not is_ready() or results.is_empty() or fact_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	# Plain copying: no repetition penalties, which would put it off starting every line with "- ".
	var body: Dictionary = chat_body(model_id, facts_prompt(results), 220, true)
	body["temperature"] = 0.2
	fact_request.request(_url("/v1/chat/completions"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))


func _on_fact_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		facts_found.emit(parse_facts(parse_reply(body.get_string_from_utf8())))


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
	# Small models copy their own last answer, or ask the same question again; the prompt alone does
	# not stop it, so a repeat goes back once with what it repeated.
	# A reply stuck on one word is cut back to its last whole sentence, and lines of these very
	# instructions said back to the user are dropped.
	reply = Mind.without_babble(reply)
	reply = Mind.without_repeats(reply, PackedStringArray([Mind.PROTOCOL, REMINDER, DEBUG_REMINDER]), PackedStringArray(), 5, 0.8)
	# The personality's example answers count as said already, since those get copied too.
	var said: PackedStringArray = earlier_replies(messages, 3)
	var questions: PackedStringArray = PackedStringArray()
	# While debugging only a copied answer counts: "what did you expect to happen?" is fair to ask twice.
	if mind != null and not _debugging:
		said.append_array(mind.example_replies())
		questions = mind.asked()
	var repeated: String = Mind.repetition(Mind.strip_tags(reply), said, questions)
	if not repeated.is_empty() and not _retried:
		_retried = true
		var again: Array[Dictionary] = _sent.duplicate(true)
		again.append({"role": "assistant", "content": reply})
		var instead: String = "look at another line or step, or ask a different question" if _debugging else "a different story, opinion or fact, and a different question, or none"
		again.append({"role": "user", "content": "You said this before: \"%s\". Answer my last message again, saying something new: %s." % [repeated, instead]})
		var retry: Dictionary = chat_body(model_id, again, max_tokens, _debugging)
		retry["temperature"] = 1.0
		chat_request.request(_url("/v1/chat/completions"), ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(retry))
		return
	# Still repeating after a second go: cut the repeats out, so a copy never reaches the history,
	# where the model would copy it again.
	if not repeated.is_empty():
		reply = Mind.without_repeats(reply, said, questions)
		if Mind.strip_tags(reply).strip_edges().is_empty():
			reply = fresh_fallback(said)
	# Remember, forget, rename or learn as the reply's tags ask, and keep them out of sight.
	var asked: String = String(messages[-1].get("content", "")) if not messages.is_empty() and messages[-1].get("role") == "user" else ""
	var answer: String = mind.digest(reply, asked) if mind != null else Mind.strip_tags(reply)
	messages.append({"role": "assistant", "content": answer})
	if mind != null:
		mind.record("user", asked)
		mind.record("assistant", answer)
		mind.notice(answer)
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
static func with_screen(history: Array[Dictionary], screen_text: String, reminder: String = REMINDER) -> Array[Dictionary]:
	var sent: Array[Dictionary] = history.duplicate(true)
	if sent.is_empty() or sent[-1].get("role") != "user":
		return sent
	var seen: String = screen_text.strip_edges()
	var screen: String = "Text read from the user's screen by OCR:\n<<<\n%s\n>>>" % seen if not seen.is_empty() else "No text could be read from the user's screen."
	sent[-1]["content"] = "%s\n\nThe user says: %s\n\n%s" % [screen, sent[-1]["content"], reminder]
	return sent


## Whether the user is working on code: their line talks about a bug or holds code, or points at
## the screen ("what's this?") while an error is on it. The line before counts too, so a debugging
## conversation stays one while they explain.
static func is_debugging(line: String, earlier_line: String, screen_text: String) -> bool:
	var about_code: RegEx = RegEx.create_from_string(DEBUG_WORDS)
	if about_code.search(line) != null or about_code.search(earlier_line) != null:
		return true
	var pointing: bool = RegEx.create_from_string(r"(?i)\b(this|here|that|screen|it)\b").search(line) != null
	return pointing and RegEx.create_from_string(r"(?i)error|exception|traceback|uncaught|null instance|undefined|failed").search(screen_text) != null


## The user's message before the last, or "".
static func earlier_user_line(history: Array[Dictionary]) -> String:
	var seen: int = 0
	for i: int in range(history.size() - 1, -1, -1):
		if history[i].get("role") == "user":
			seen += 1
			if seen == 2:
				return String(history[i].get("content", ""))
	return ""


## The history with web search results put ahead of the user's last message.
static func with_web(history: Array[Dictionary], web_text: String) -> Array[Dictionary]:
	if web_text.strip_edges().is_empty() or history.is_empty() or history[-1].get("role") != "user":
		return history
	var sent: Array[Dictionary] = history.duplicate(true)
	sent[-1]["content"] = "%s\n\n%s" % [web_text.strip_edges(), sent[-1]["content"]]
	return sent


## Said when every sentence of an answer was a repeat: whichever of these it has not just said.
const FALLBACKS: PackedStringArray = ["Ooh, I've lost my thread! Tell me more about that.", "Hmm, my head's full of bubbles. Go on, I'm listening!", "Quack, I was miles away! Say that again?", "I'm all ears. Well, all beak. What happened next?"]


static func fresh_fallback(said: PackedStringArray) -> String:
	for line: String in FALLBACKS:
		if not line in said:
			return line
	return FALLBACKS[randi() % FALLBACKS.size()]


## The duck's last `count` answers in the history, newest last.
static func earlier_replies(history: Array[Dictionary], count: int) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for message: Dictionary in history:
		if message.get("role") == "assistant":
			found.append(String(message.get("content", "")))
	return found.slice(maxi(found.size() - count, 0))


static func chat_body(model: String, history: Array[Dictionary], tokens: int, about_code: bool = false) -> Dictionary:
	var body: Dictionary = {"model": model, "messages": history, "max_tokens": tokens, "temperature": 0.8}
	# The penalties discourage repeating its own words within a chatty reply. Code repeats its
	# marks and names all the time, so with them on it drops backticks and "+" and stops short.
	if not about_code:
		body["presence_penalty"] = 0.6
		body["frequency_penalty"] = 0.4
	return body


## The assistant's text from a chat completion response, or "" when there is none.
## The request that pulls facts out of search results.
static func facts_prompt(results: Array[Dictionary]) -> Array[Dictionary]:
	var lines: PackedStringArray = PackedStringArray()
	for found: Dictionary in results:
		lines.append("%s: %s" % [found["title"], found["snippet"]])
	return [
		{"role": "system", "content": "You pick facts out of web search results. You never add anything the results do not say."},
		{"role": "user", "content": "Search results:\n%s\n\nCopy out up to three facts these results state, one per line, each starting with \"- \", rewritten as a short sentence that makes sense on its own. A fact says what is true about the world. Tips, instructions, care advice and anything telling the reader what to do or buy are not facts: leave them out. If the results state no facts, write NONE." % "\n".join(lines)},
	]


## The "- " lines of the model's answer to `facts_prompt`.
static func parse_facts(reply: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var bullet: RegEx = RegEx.create_from_string(r"^(?:[-*]|\d+[.)])\s+")
	for line: String in reply.split("\n"):
		# A bullet or a number in front is dropped; a line that introduces the list ends in ":".
		var fact: String = bullet.sub(line.strip_edges(), "")
		if fact.length() > 15 and not fact.ends_with(":") and fact != "NONE":
			found.append(fact)
	return found.slice(0, 3)


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
