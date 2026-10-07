extends GutTest

const PATH: String = "user://test_voice_settings.cfg"

# The shape DisplayServer.tts_get_voices() returns.
var voices: Array[Dictionary] = [
	{"name": "Microsoft Hedda", "id": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\TTS_MS_DE-DE_HEDDA_11.0", "language": "de_DE"},
	{"name": "Microsoft Zira", "id": "HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech\\Voices\\Tokens\\TTS_MS_EN-US_ZIRA_11.0", "language": "en_US"},
]


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


func test_default_voice_speaks_the_users_language() -> void:
	assert_eq(Voice.default_voice(voices, "en"), voices[1]["id"])
	assert_eq(Voice.default_voice(voices, "de"), voices[0]["id"])


func test_default_voice_falls_back_to_the_first_then_to_none() -> void:
	assert_eq(Voice.default_voice(voices, "ja"), voices[0]["id"])
	assert_eq(Voice.default_voice([] as Array[Dictionary], "en"), "")


func test_has_voice() -> void:
	assert_true(Voice.has_voice(voices, voices[1]["id"]))
	assert_false(Voice.has_voice(voices, "gone"))
	assert_false(Voice.has_voice(voices, ""))


func test_label_names_the_voice_and_its_language() -> void:
	assert_eq(Voice.label_for(voices[1]), "Microsoft Zira (en_US)")


func test_applied_voice_survives_a_restart() -> void:
	assert_eq(Voice.load_saved(PATH), "", "nothing saved yet")
	Voice.save(PATH, voices[0]["id"])
	assert_eq(Voice.load_saved(PATH), voices[0]["id"])
	Voice.save(PATH, voices[1]["id"])
	assert_eq(Voice.load_saved(PATH), voices[1]["id"], "a second apply replaces the first")


func test_speaking_without_tts_is_harmless() -> void:
	# Headless Godot has no TTS, the way a machine without voices has none.
	var voice: Voice = Voice.new()
	add_child_autofree(voice)
	voice.speak("hello")
	voice.stop()
	assert_eq(voice.available(), [] as Array[Dictionary])
