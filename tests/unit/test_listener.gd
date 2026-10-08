extends GutTest


func test_wav_header_is_16_bit_mono_pcm() -> void:
	var wav: PackedByteArray = Listener.to_wav(PackedFloat32Array([0.0, 0.5, -0.5, 1.0]), 16000)
	assert_eq(wav.size(), 44 + 8)
	assert_eq(wav.slice(0, 4).get_string_from_ascii(), "RIFF")
	assert_eq(wav.slice(8, 12).get_string_from_ascii(), "WAVE")
	assert_eq(wav.decode_u16(20), 1, "PCM")
	assert_eq(wav.decode_u16(22), 1, "mono")
	assert_eq(wav.decode_u32(24), 16000)
	assert_eq(wav.decode_u16(34), 16, "16 bit")
	assert_eq(wav.decode_u32(40), 8, "data size")
	assert_eq(wav.decode_s16(44 + 6), 32767, "full scale")


func test_resampling_48k_to_16k_keeps_a_third() -> void:
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(4800)
	assert_eq(Listener.resample(samples, 48000.0, 16000.0).size(), 1600)
	assert_eq(Listener.resample(samples, 16000.0, 16000.0).size(), 4800)


func test_level_tells_speech_from_silence() -> void:
	var quiet: PackedFloat32Array = PackedFloat32Array([0.001, -0.001, 0.001, -0.001])
	var loud: PackedFloat32Array = PackedFloat32Array([0.3, -0.3, 0.3, -0.3])
	assert_lt(Listener.level_db(quiet), -40.0)
	assert_gt(Listener.level_db(loud), -40.0)
	assert_eq(Listener.level_db(PackedFloat32Array()), -INF)


func test_stereo_is_folded_to_mono() -> void:
	assert_eq(Listener.to_mono(PackedVector2Array([Vector2(1, 0), Vector2(0.5, 0.5)])), PackedFloat32Array([0.5, 0.5]))


func test_reads_foundry_transcribe_json() -> void:
	# What `foundry transcribe -o json` printed for the test sentence, file path left out.
	var json: String = '{"model":"parakeet-tdt-0.6b-v2-cuda-gpu","text":" Why does my function return null when the list is empty?","language":"en","durationSeconds":null}'
	assert_eq(Listener.parse_transcript(json), "Why does my function return null when the list is empty?")
	assert_eq(Listener.parse_transcript(""), "")
	assert_eq(Listener.parse_transcript("Error: model not found"), "")


func test_mic_bus_is_muted_and_captured() -> void:
	var bus: int = AudioServer.get_bus_index(Listener.BUS)
	assert_gt(bus, 0, "the Mic bus is in default_bus_layout.tres")
	assert_true(AudioServer.is_bus_mute(bus), "muted, so you do not hear yourself")
	assert_true(AudioServer.get_bus_effect(bus, 0) is AudioEffectCapture)


func test_listening_starts_and_stops() -> void:
	var listener: Listener = load("res://scripts/listener.gd").new()
	var mic: AudioStreamPlayer = AudioStreamPlayer.new()
	mic.name = "Mic"
	mic.stream = AudioStreamMicrophone.new()
	mic.bus = Listener.BUS
	listener.add_child(mic)
	add_child_autofree(listener)
	assert_true(listener.is_supported())
	listener.start()
	assert_eq(listener.mode, Listener.Mode.OFF, "no speech model chosen yet")
	listener.model_alias = "parakeet-tdt-0.6b-v2"
	listener.start()
	assert_eq(listener.mode, Listener.Mode.WAITING)
	listener.pause()
	assert_eq(listener.mode, Listener.Mode.PAUSED)
	listener.resume()
	assert_eq(listener.mode, Listener.Mode.WAITING)
	listener.stop()
	assert_eq(listener.mode, Listener.Mode.OFF)


func test_the_chosen_microphone_is_remembered() -> void:
	var path: String = "user://test_mic_settings.cfg"
	assert_eq(Listener.load_device(path), "")
	Listener.save_device(path, "Microphone Array (AMD Audio Device)")
	assert_eq(Listener.load_device(path), "Microphone Array (AMD Audio Device)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_settings_offer_a_microphone_choice() -> void:
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	assert_not_null(pet.get_node("Bubble/Panel/Margin/Tabs/Settings/MicRow/Mics") as OptionButton)
	var methods: PackedStringArray = PackedStringArray()
	var state: SceneState = (load("res://scenes/pet.tscn") as PackedScene).get_state()
	for i: int in state.get_connection_count():
		methods.append(state.get_connection_method(i))
	assert_has(methods, "_on_mic_selected")
	pet.free()


func test_on_the_phone_a_sentence_is_handed_over_not_transcribed() -> void:
	var listener: Listener = load("res://scripts/listener.gd").new()
	listener.hand_off = true
	watch_signals(listener)
	listener._samples = PackedFloat32Array([0.0, 0.5, -0.5, 0.25])
	listener._transcribe(16000.0)
	assert_signal_emitted(listener, "wav_ready")
	var wav: PackedByteArray = get_signal_parameters(listener, "wav_ready")[0]
	assert_eq(wav.slice(0, 4).get_string_from_ascii(), "RIFF", "a WAV")
	assert_eq(listener.mode, Listener.Mode.PAUSED, "waits for the answer")
	listener.free()


func test_turning_the_mic_off_mid_sentence_sends_it() -> void:
	var listener: Listener = load("res://scripts/listener.gd").new()
	var mic: AudioStreamPlayer = AudioStreamPlayer.new()
	mic.name = "Mic"
	listener.add_child(mic)
	listener.hand_off = true
	add_child_autofree(listener)
	watch_signals(listener)
	listener.mode = Listener.Mode.HEARING
	listener._voiced = listener.min_speech_seconds
	listener._samples = PackedFloat32Array([0.0, 0.5, -0.5, 0.25])
	assert_true(listener.finish(), "there was a sentence")
	assert_signal_emitted(listener, "wav_ready", "it went to be written down")
	assert_eq(listener.mode, Listener.Mode.OFF, "and the mic is off")
	listener.mode = Listener.Mode.HEARING
	listener._voiced = 0.0
	assert_false(listener.finish(), "a cough is not a sentence")
	assert_signal_emit_count(listener, "wav_ready", 1)
	listener.mode = Listener.Mode.WAITING
	assert_false(listener.finish(), "nor is silence")


func test_a_phone_recording_needs_a_speech_model_and_some_sound() -> void:
	var listener: Listener = load("res://scripts/listener.gd").new()
	assert_false(listener.transcribe_wav(PackedByteArray([1, 2, 3])), "no speech model chosen yet")
	listener.model_alias = "parakeet-tdt-0.6b-v2"
	assert_false(listener.transcribe_wav(PackedByteArray()), "nothing to transcribe")
	listener.free()


func test_the_phone_listens_without_a_speech_model_of_its_own() -> void:
	var app: Node = (load("res://scenes/remote.tscn") as PackedScene).instantiate()
	var listener: Listener = app.get_node("Listener")
	add_child_autofree(app)
	assert_true(listener.model_alias.is_empty(), "the phone has none")
	listener.start()
	assert_eq(listener.mode, Listener.Mode.WAITING, "it listens anyway: the PC writes its sentences down")
	listener.stop()
