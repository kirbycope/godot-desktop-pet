class_name Voice
extends Node
## Speaks through the operating system's own text-to-speech voices, or the natural Kokoro voices once
## they are downloaded, and remembers which one was chosen.
##
## Godot's DisplayServer TTS uses OneCore voices on Windows (SAPI only where OneCore is missing),
## AVSpeechSynthesizer on macOS and speech-dispatcher on Linux. It needs `audio/general/text_to_speech`
## on in the project settings. Kokoro voices have ids "kokoro:<n>"; see kokoro.gd.

## Emitted when the last thing said has finished or was cut off.
signal finished
## Sound has begun. At once for a system voice; after a second or two of synthesis for Kokoro.
signal started

const SETTINGS_PATH: String = "user://settings.cfg"

@export_range(0, 100) var volume: int = 70
@export_range(0.1, 10.0) var rate: float = 1.0

var voice_id: String = ""
var _utterance: int = 0

## Null when the node stands alone, as in a test: then there are only system voices.
@onready var kokoro: Kokoro = get_node_or_null("Kokoro")


func _ready() -> void:
	var voices: Array[Dictionary] = available()
	voice_id = load_saved(SETTINGS_PATH)
	if not has_voice(voices, voice_id) or (Kokoro.sid_of(voice_id) >= 0 and not kokoro_ready()):
		voice_id = default_voice(voices, OS.get_locale_language())
	# A natural voice loads its model now, in the background, so the first reply is quick.
	if Kokoro.sid_of(voice_id) >= 0 and kokoro_ready():
		kokoro.warm_up(Kokoro.sid_of(voice_id))
	if is_supported():
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_done)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_done)


func _exit_tree() -> void:
	stop()


static func is_supported() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## The system's voices, then Kokoro's (marked "kokoro": true, installed or not): dictionaries with
## name, id and language.
func available() -> Array[Dictionary]:
	var voices: Array[Dictionary] = system_voices()
	if kokoro != null and Kokoro.is_platform_supported():
		voices.append_array(Kokoro.voice_list())
	return voices


## Every voice the system offers. Empty without TTS.
func system_voices() -> Array[Dictionary]:
	return DisplayServer.tts_get_voices() if is_supported() else ([] as Array[Dictionary])


## Says `text` in the chosen voice, or in `id` to try one out, cutting off anything still being said.
func speak(text: String, id: String = voice_id) -> void:
	stop()
	add(text, id)


## Says `text` after whatever is being said, as each sentence of a streamed answer arrives.
## `finished` comes once, after the last.
func add(text: String, id: String = voice_id) -> void:
	if Kokoro.sid_of(id) >= 0:
		if kokoro_ready():
			kokoro.add(text, Kokoro.sid_of(id))
		return
	if id.is_empty() or not is_supported() or text.strip_edges().is_empty():
		return
	_utterance += 1
	# Not interrupting: the system queues it behind the sentence before.
	DisplayServer.tts_speak(text, id, volume, 1.0, rate, _utterance, false)
	started.emit.call_deferred()


func is_speaking() -> bool:
	return (is_supported() and DisplayServer.tts_is_speaking()) or (kokoro != null and kokoro.is_speaking())


func kokoro_ready() -> bool:
	return kokoro != null and kokoro.is_installed()


func stop() -> void:
	if kokoro != null:
		kokoro.stop()
	if is_supported():
		DisplayServer.tts_stop()


func _on_kokoro_started() -> void:
	started.emit()


func _on_kokoro_finished() -> void:
	finished.emit()


## Makes `id` the voice from now on and saves it for the next run.
func apply(id: String) -> void:
	voice_id = id
	if Kokoro.sid_of(id) >= 0 and kokoro_ready():
		kokoro.warm_up(Kokoro.sid_of(id))
	save(SETTINGS_PATH, id)


## The OS calls back from its own thread, so the signal is sent from the main one.
func _on_utterance_done(id: int) -> void:
	if id == _utterance:
		finished.emit.call_deferred()


static func has_voice(voices: Array[Dictionary], id: String) -> bool:
	return voices.any(func(voice: Dictionary) -> bool: return voice.get("id", "") == id)


## The first voice in the user's language, else the first voice, else "".
static func default_voice(voices: Array[Dictionary], language: String) -> String:
	for voice: Dictionary in voices:
		if String(voice.get("language", "")).begins_with(language):
			return voice["id"]
	return voices[0]["id"] if not voices.is_empty() else ""


static func label_for(voice: Dictionary) -> String:
	return "%s (%s)" % [voice.get("name", "?"), voice.get("language", "?")]


static func load_saved(path: String) -> String:
	var config: ConfigFile = ConfigFile.new()
	return config.get_value("voice", "id", "") if config.load(path) == OK else ""


static func save(path: String, id: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value("voice", "id", id)
	config.save(path)
