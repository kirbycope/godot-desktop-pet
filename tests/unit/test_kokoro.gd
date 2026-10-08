extends GutTest


func test_twenty_eight_english_voices_american_then_british() -> void:
	assert_eq(Kokoro.VOICES.size(), 28)
	assert_eq(Kokoro.VOICES[3], ["Heart", "US", "female"], "id 3 is af_heart in sherpa-onnx's v1.0 table")
	assert_eq(Kokoro.VOICES[16], ["Michael", "US", "male"])
	assert_eq(Kokoro.VOICES[21], ["Emma", "GB", "female"])
	assert_eq(Kokoro.VOICES[27], ["Lewis", "GB", "male"])


func test_voice_ids_round_trip() -> void:
	assert_eq(Kokoro.voice_id(21), "kokoro:21")
	assert_eq(Kokoro.sid_of("kokoro:21"), 21)
	assert_eq(Kokoro.sid_of("HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Speech_OneCore\\Voices\\Tokens\\MSTTS_V110_enUS_ZiraM"), -1)
	assert_eq(Kokoro.sid_of("kokoro:download"), -1, "the download entry is not a voice")


func test_the_voice_list_reads_well() -> void:
	var list: Array[Dictionary] = Kokoro.voice_list()
	assert_eq(list.size(), 28)
	assert_eq(list[3], {"id": "kokoro:3", "name": "Heart, American female", "language": "en_US", "kokoro": true})
	assert_eq(list[24]["name"], "Daniel, British male")
	assert_eq(list[24]["language"], "en_GB")


func test_british_voices_read_with_the_british_lexicon() -> void:
	assert_eq(Kokoro.lexicon_for(3), "lexicon-us-en.txt")
	assert_eq(Kokoro.lexicon_for(21), "lexicon-gb-en.txt")
	assert_has(Kokoro.args("C:/k", 26, "Hello", "C:/o.wav", 8), "--kokoro-lexicon=C:/k/lexicon-gb-en.txt")


func test_a_server_request_is_one_tab_separated_line() -> void:
	assert_eq(Kokoro.request(3, "Hi there!\nHow are you?\tFine.", "C:/say.wav"), "3\tlexicon-us-en.txt\tC:/say.wav\tHi there! How are you? Fine.")
	assert_string_ends_with(Kokoro.request(3, "  ", "C:/w.wav"), "\t.", "never an empty line to say")


func test_the_command_line_fallback_has_every_kokoro_file() -> void:
	var command: PackedStringArray = Kokoro.args("C:/k", 3, "Hello there", "C:/o.wav", 8)
	for flag: String in ["--kokoro-model=C:/k/model.onnx", "--kokoro-voices=C:/k/voices.bin", "--kokoro-tokens=C:/k/tokens.txt", "--kokoro-data-dir=C:/k/espeak-ng-data", "--kokoro-dict-dir=C:/k/dict", "--num-threads=8", "--sid=3", "--output-filename=C:/o.wav"]:
		assert_has(command, flag)
	assert_eq(command[-1], "Hello there", "the text comes last")


func test_downloads_come_from_sherpa_onnx_releases() -> void:
	assert_eq(Kokoro.sherpa_url("sherpa-onnx-v1.13.8-win-x64-shared-MD-Release"), "https://github.com/k2-fsa/sherpa-onnx/releases/download/v1.13.8/sherpa-onnx-v1.13.8-win-x64-shared-MD-Release.tar.bz2")
	assert_string_ends_with(Kokoro.MODEL_URL, "/tts-models/kokoro-multi-lang-v1_0.tar.bz2", "the full model; int8 measured four times slower")
	if OS.get_name() == "Windows":
		assert_eq(Kokoro.download_mb(), 352)


func test_the_windows_server_is_built_into_bin() -> void:
	if OS.get_name() != "Windows":
		pass_test("the macOS build is not made yet")
		return
	assert_true(FileAccess.file_exists("res://bin/windows/kokoro-server.exe"))


func test_the_voice_node_offers_kokoro_beside_the_system_voices() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var voice: Voice = pet.get_node("Voice")
	assert_not_null(voice.get_node("Kokoro") as Kokoro)
	assert_not_null(voice.get_node("Kokoro/Download") as HTTPRequest)
	pet.free()


func test_a_lone_voice_node_still_works_without_kokoro() -> void:
	var voice: Voice = Voice.new()
	add_child_autofree(voice)
	assert_false(voice.kokoro_ready())
	assert_false(voice.is_speaking())
	voice.speak("hello", "kokoro:3")
	voice.stop()
	assert_eq(voice.available(), [] as Array[Dictionary], "headless: no system voices, and no Kokoro node")


func test_the_settings_tab_fits_with_room_for_the_status_line() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var settings: Control = pet.get_node("Bubble/Panel/Margin/Tabs/Settings")
	var panel: Control = pet.get_node("Bubble/Panel")
	(pet.get_node("Bubble/Panel/Margin/Tabs/Settings/Current") as Label).text = "Downloading natural voices: 120 of 352 MB"
	settings.visible = true
	pet.get_node("Bubble/Panel/Margin/Tabs/Chat").visible = false
	assert_lte(panel.get_combined_minimum_size().y, float((pet.get_node("Bubble") as Window).size.y), "everything fits in the 240 px bubble")
	assert_lt(settings.get_node("Current").get_index(), settings.get_node("MicRow").get_index(), "the status sits under Test and Apply")
	pet.free()
