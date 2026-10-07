class_name Voice
extends Node
## Speaks through the operating system's own text-to-speech voices and remembers which one was chosen.
##
## Godot's DisplayServer TTS uses SAPI and OneCore voices on Windows, AVSpeechSynthesizer on macOS and
## speech-dispatcher on Linux. It needs `audio/general/text_to_speech` on in the project settings.

## Emitted when the last thing said has finished or was cut off.
signal finished

const SETTINGS_PATH: String = "user://settings.cfg"

@export_range(0, 100) var volume: int = 70
@export_range(0.1, 10.0) var rate: float = 1.0

var voice_id: String = ""
var _utterance: int = 0


func _ready() -> void:
	var voices: Array[Dictionary] = available()
	voice_id = load_saved(SETTINGS_PATH)
	if not has_voice(voices, voice_id):
		voice_id = default_voice(voices, OS.get_locale_language())
	if is_supported():
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_done)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _on_utterance_done)


func _exit_tree() -> void:
	stop()


static func is_supported() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)


## Every voice the system offers: dictionaries with name, id and language. Empty without TTS.
func available() -> Array[Dictionary]:
	return DisplayServer.tts_get_voices() if is_supported() else ([] as Array[Dictionary])


## Says `text` in the chosen voice, or in `id` to try one out, cutting off anything still being said.
func speak(text: String, id: String = voice_id) -> void:
	if id.is_empty() or not is_supported():
		return
	_utterance += 1
	DisplayServer.tts_speak(text, id, volume, 1.0, rate, _utterance, true)


func stop() -> void:
	if is_supported():
		DisplayServer.tts_stop()


## Makes `id` the voice from now on and saves it for the next run.
func apply(id: String) -> void:
	voice_id = id
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
