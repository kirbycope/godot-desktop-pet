class_name Brain
extends Node
## Runs a local LLM through Foundry Local and chats with it over its OpenAI-compatible REST API.
##
## Foundry Local picks the model variant for the hardware itself: an NPU build when a supported NPU
## is present, otherwise CUDA or TensorRT on an NVIDIA GPU, WebGPU on others, then the CPU. Startup
## runs the foundry CLI on a thread, since each step blocks until it is done.

signal status_changed(text: String)
## One sentence of the answer, as soon as the model has written it, already checked for repeats.
signal sentence(text: String)
## The whole answer, after the last sentence.
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
## While debugging: room to finish an explanation (they run 100 to 135 tokens; 160 cut them off),
## and a low temperature, since the same bug was found one time in three at 0.8.
@export var debug_max_tokens: int = 220
@export var debug_temperature: float = 0.3
## Leave the chat model loaded when the duck closes, if it was run from the Godot editor, so the
## next run starts in a second instead of 45. Run any other way, it frees the memory as it closes.
@export var keep_loaded_from_editor: bool = true
## Messages sent with each prompt besides the system prompt: the last three exchanges. Every
## exchange is also written to the duck's folder (see Mind.record), and the last ones come back on
## the next start.
@export var max_history: int = 6
## The duck's job. How it talks, its name, memories and skills come from `mind`'s files.
@export_multiline var role: String = "You are a friendly little rubber duck who lives on the edge of the user's screen and keeps them company. You are a companion first: chat happily about whatever they bring up, their day, ideas, jokes, questions, and follow the conversation, picking up on what was said before. Do not steer the talk towards code or offer coding help unasked. When they do bring you a coding problem, be a great rubber duck: help them think it through by asking one sharp question at a time, or by pointing at the part that looks wrong. Your answers are read aloud, so keep each turn to a few short sentences, with no code blocks or markdown."
## Who the duck is while debugging, in place of the whole personality: a short prompt answers in
## half the time and leaves nothing to tempt a duck fact into the middle of a bug.
@export_multiline var debug_role: String = "You are a cheerful little rubber duck on the edge of the user's screen, and right now you are their rubber duck for debugging: sunny and encouraging, never mean, but no stories, duck facts or jokes while there is a bug to find. Help them find the bug by going through what the code does, one step at a time. Your answers are read aloud, so keep each turn to two or three short sentences, with no lists, headings or code blocks.\n\nA good turn, for the shape of it: they ask why their game crashes, and the screen shows `velocity = speed * direction` with the error \"Invalid operands 'Nil' and 'float'\". You say: The error is on the line that uses speed, and speed is Nil there, so it never got a value. Where do you set speed, and does that run before this line?"
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
## The last request's messages.
var _sent: Array[Dictionary] = []
## Whether the last message was about code.
var _debugging: bool = false
## The answer being streamed: everything so far, how many of its sentences have been looked at,
## the ones kept, and what they must not repeat.
var _raw: String = ""
var _handled: int = 0
var _kept: PackedStringArray = PackedStringArray()
var _said: PackedStringArray = PackedStringArray()
var _questions: PackedStringArray = PackedStringArray()
var _done: bool = true
## How the last answer went, in milliseconds from the request: first_token, first_sentence, reply;
## and tokens, finish_reason, debugging. Shown on the Stats tab.
var timings: Dictionary = {}
var _asked_at: int = 0
## The error being worked on, kept while the conversation stays on it, so it is not lost when the
## user switches windows to explain.
var _thread_error: String = ""

@onready var models_request: HTTPRequest = $ModelsRequest
@onready var chat_stream: ChatStream = $ChatStream
@onready var fact_request: HTTPRequest = $FactRequest


func _ready() -> void:
	_thread.start(_boot)


func _exit_tree() -> void:
	_quitting = true
	if _thread.is_started():
		_thread.wait_to_finish()
	# Free the GPU or NPU memory; the Foundry daemon itself is shared and stays up.
	if not model_id.is_empty() and not keeps_model(keep_loaded_from_editor, EngineDebugger.is_active()):
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
	return chat_stream.is_busy()


## Sends the user's line with the text read off the screen, and the web results when it asked for a
## search; the answer arrives through `replied`. Only the line is kept in the history, so old
## screens and results do not pile up in the context.
func ask(text: String, screen_text: String = "", web_text: String = "") -> void:
	if not is_ready() or is_busy():
		return
	messages.append({"role": "user", "content": text})
	messages = trimmed(messages, max_history)
	# Debugging gets the rubber duck: a slim prompt and its reminder, no duck facts or jokes.
	_debugging = is_debugging(text, earlier_user_line(messages), screen_text)
	# The system prompt is rebuilt each time, so edits to its files and new memories count at once.
	messages[0] = {"role": "system", "content": system_prompt(_debugging)}
	var skills: Array[Dictionary] = mind.skills_for(text + "\n" + screen_text) if mind != null else ([] as Array[Dictionary])
	var reminder: String = DEBUG_REMINDER if _debugging else REMINDER
	var hints: PackedStringArray = PackedStringArray()
	if _debugging:
		var errors: PackedStringArray = ScreenReader.error_lines(screen_text)
		if not errors.is_empty():
			_thread_error = "\n".join(errors).left(600)
		elif not _thread_error.is_empty():
			hints.append("They are still working on this error from before: " + _thread_error)
		hints.append_array(Hints.for_text(screen_text, user_lines(messages)))
	else:
		_thread_error = ""
	_sent = with_skills(with_web(with_screen(messages, screen_text, reminder, hints), web_text), skills)
	# What the answer must not repeat: its last answers; in chat also the personality's example
	# answers and its recent questions. While debugging "what did you expect?" is fair to ask twice.
	_said = earlier_replies(messages, 3)
	_questions = PackedStringArray()
	if mind != null and not _debugging:
		_said.append_array(mind.example_replies())
		_questions = mind.asked()
	_raw = ""
	_handled = 0
	_kept = PackedStringArray()
	_done = false
	_asked_at = Time.get_ticks_msec()
	timings = {"debugging": _debugging}
	var body: Dictionary = chat_body(model_id, _sent, debug_max_tokens if _debugging else max_tokens, _debugging)
	if _debugging:
		body["temperature"] = debug_temperature
	chat_stream.start("127.0.0.1", port, "/v1/chat/completions", ChatStream.streamed(body))


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
	if not _start_server(output):
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


## On the thread: starts Foundry's server, putting what went wrong in `output` on failure.
func _start_server(output: Array) -> bool:
	var command: PackedStringArray = server_start_command(_foundry, port, OS.get_name())
	if command[0] == _foundry:
		return OS.execute(_foundry, command.slice(1), output, true) == 0
	if OS.execute(command[0], command.slice(1)) == 0:
		return true
	OS.execute(_foundry, ["server", "status"], output, true)
	return false


## The command that starts the server, program first. OS.execute reads a child's stdout until it
## closes, and on macOS and Linux the daemon `foundry server start` leaves running inherits that
## stdout, so the read never ended and the duck stayed on "Starting Foundry Local..." for good
## (CLI 0.10.3). There it goes through a shell that sends the output to /dev/null instead. The path
## is quoted into the script, since Godot does not pass arguments after `sh -c`'s script on.
static func server_start_command(foundry: String, server_port: int, os_name: String) -> PackedStringArray:
	if os_name == "Windows":
		return PackedStringArray([foundry, "server", "start", "--port", str(server_port), "--idle-timeout", "0"])
	var quoted: String = "'" + foundry.replace("'", "'\\''") + "'"
	return PackedStringArray(["/bin/sh", "-c", "exec %s server start --port %d --idle-timeout 0 </dev/null >/dev/null 2>&1" % [quoted, server_port]])


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


func _on_chat_stream_delta(piece: String) -> void:
	if _done:
		return
	if not timings.has("first_token"):
		timings["first_token"] = Time.get_ticks_msec() - _asked_at
	_raw += piece
	_take_sentences(false)


func _on_chat_stream_finished(_text: String, code: int, finish_reason: String) -> void:
	if _done:
		return
	timings["finish_reason"] = finish_reason
	if code != 200 or _raw.strip_edges().is_empty():
		_done = true
		messages.pop_back()
		replied.emit("Bzzt. My brain did not answer (HTTP %d)." % code)
		return
	_take_sentences(true)
	_finish()


## Hands on each sentence of the answer that is complete. A sentence is complete once the next has
## begun, or when the answer has ended (`last`). A reply stuck on one word ends there.
func _take_sentences(last: bool) -> void:
	var visible: String = speakable(_raw)
	var unstuck: String = Mind.without_babble(visible)
	var stuck: bool = unstuck != visible
	var all: PackedStringArray = Mind.sentences_in(unstuck)
	var complete: int = all.size() if last or stuck else all.size() - 1
	while _handled < complete:
		var kept: String = keep_sentence(all[_handled], _said, _questions)
		_handled += 1
		if kept.is_empty():
			continue
		_kept.append(kept)
		if not timings.has("first_sentence"):
			timings["first_sentence"] = Time.get_ticks_msec() - _asked_at
		sentence.emit(kept)
	if stuck and not last:
		chat_stream.cancel()
		timings["finish_reason"] = "stuck"
		_finish()


## The answer is in: carry out its tags, keep it, and say it is done.
func _finish() -> void:
	_done = true
	var asked: String = String(messages[-1].get("content", "")) if not messages.is_empty() and messages[-1].get("role") == "user" else ""
	# Remember, forget, rename or learn as the reply's tags ask; they were never shown or spoken.
	if mind != null:
		mind.digest(_raw, asked)
	var answer: String = " ".join(_kept)
	if answer.is_empty():
		# Every sentence was a repeat: something short and fresh instead.
		answer = fresh_fallback(_said)
		sentence.emit(answer)
	messages.append({"role": "assistant", "content": answer})
	if mind != null:
		mind.record("user", asked)
		mind.record("assistant", answer)
		mind.notice(answer)
	timings["reply"] = Time.get_ticks_msec() - _asked_at
	timings["tokens"] = _raw.length() / 4
	replied.emit(answer)


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


func system_prompt(debugging: bool = false) -> String:
	if debugging:
		var called: String = mind.duck_name() if mind != null else ""
		return "%s%s\n\n%s" % ["Your name is %s. " % called if not called.is_empty() else "", debug_role, sight_rules]
	# Who it is comes first: small models follow the opening of a prompt and its end most closely.
	return "%s\n\n%s\n\n%s\n\nYou run entirely on this computer, on its %s.\n%s" % [mind.prompt() if mind != null else "", role, sight_rules, device, hardware]


## Whether to leave the model loaded on closing: only when run from the editor, whose debugger is
## attached to the running duck, and only if `keep_loaded_from_editor` allows it.
static func keeps_model(allowed: bool, from_editor: bool) -> bool:
	return allowed and from_editor


## The answer as far as it can be shown and spoken: tags taken out, and anything from a "[" that has
## not closed yet held back, in case it is the start of one.
static func speakable(raw: String) -> String:
	var text: String = Mind.strip_tags(raw)
	var open: int = text.rfind("[")
	if open >= 0 and text.find("]", open) < 0:
		text = text.left(open)
	return text


## `text` if it may be said: "" when it repeats lines of the duck's own instructions, an earlier
## answer, or a question asked lately, or has no words at all ("1.").
static func keep_sentence(text: String, said: PackedStringArray, questions: PackedStringArray) -> String:
	if RegEx.create_from_string(r"[A-Za-z]").search(text) == null:
		return ""
	if Mind.without_repeats(text, PackedStringArray([Mind.PROTOCOL, REMINDER, DEBUG_REMINDER]), PackedStringArray(), 5, 0.8).is_empty():
		return ""
	return Mind.without_repeats(text, said, questions)


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
static func with_screen(history: Array[Dictionary], screen_text: String, reminder: String = REMINDER, hints: PackedStringArray = PackedStringArray()) -> Array[Dictionary]:
	var sent: Array[Dictionary] = history.duplicate(true)
	if sent.is_empty() or sent[-1].get("role") != "user":
		return sent
	var seen: String = screen_text.strip_edges()
	var screen: String = "Text read from the user's screen by OCR:\n<<<\n%s\n>>>" % seen if not seen.is_empty() else "No text could be read from the user's screen."
	# The hints go after the user's line, near the end, where a small model heeds them.
	var checks: String = ""
	if not hints.is_empty():
		checks = "Things to check, from a quick look done in code. They may be wrong: check each against the code before you mention it.\n- %s\n\n" % "\n- ".join(hints)
	sent[-1]["content"] = "%s\n\nThe user says: %s\n\n%s%s" % [screen, sent[-1]["content"], checks, reminder]
	return sent


## Everything the user has said in `history`, one message a line.
static func user_lines(history: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for message: Dictionary in history:
		if message.get("role") == "user":
			lines.append(String(message.get("content", "")))
	return "\n".join(lines)


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
