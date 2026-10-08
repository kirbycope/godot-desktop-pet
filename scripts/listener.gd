class_name Listener
extends Node
## Listens through the microphone and turns each spoken sentence into text, a pause marking its end.
##
## The microphone plays into the muted "Mic" bus, whose AudioEffectCapture hands over the samples. A
## sentence starts when the level rises above `speech_threshold_db` and ends after `pause_seconds`
## below it. It is written to a 16 kHz WAV and transcribed on a thread by Foundry Local's
## `foundry transcribe` command: the REST server of CLI 0.10.3 has no transcription endpoint, and its
## Whisper builds for CUDA return garbled text, so the default model is Parakeet.

## A sentence was transcribed; "" when nothing intelligible was said.
signal heard(text: String)
## A sentence the phone recorded was transcribed (see `transcribe_wav`); "" when nothing was heard.
signal heard_from_phone(text: String)
## With `hand_off` on, a sentence ready to transcribe, as a 16 kHz WAV, for something else to
## transcribe: the phone app sends it to the PC.
signal wav_ready(wav: PackedByteArray)
signal mode_changed(mode: Mode)
## The microphone's level in decibels, as it is heard, for a meter.
signal level_changed(db: float)

enum Mode { OFF, WAITING, HEARING, TRANSCRIBING, PAUSED }

## Foundry Local speech model; the pet sets it to the one the brain chose for this machine.
var model_alias: String = ""
## Language hint for the speech model; empty uses the system language.
@export var language: String = ""
## Louder than this is speech.
@export var speech_threshold_db: float = -40.0
## Quiet for this long ends the sentence and sends it. At 0.6 s a pause to think mid-sentence sent
## half of it ("He likes to float in more water and").
@export var pause_seconds: float = 1.2
## Shorter bursts (a cough, a click) are dropped.
@export var min_speech_seconds: float = 0.3
@export var max_seconds: float = 30.0
## Audio kept from just before the level rose, so the first syllable is not cut off.
@export var preroll_seconds: float = 0.3
## Hand each sentence over through `wav_ready` instead of transcribing it here: the phone app, which
## has no speech model, has the PC transcribe it. It waits, paused, until `resume`.
@export var hand_off: bool = false

const BUS: StringName = &"Mic"
const RATE: int = 16000
const WAV_PATH: String = "user://utterance.wav"
## Where the chosen microphone is kept, beside the chosen voice.
const SETTINGS_PATH: String = "user://settings.cfg"

var mode: Mode = Mode.OFF:
	set = _set_mode
## Set by the pet once the brain has found the CLI.
var foundry_path: String = "foundry"
## Why the last transcription came back empty, or "" when it worked.
var last_error: String = ""
var _capture: AudioEffectCapture
var _samples: PackedFloat32Array = PackedFloat32Array()
var _voiced: float = 0.0
var _silence: float = 0.0
var _model_fetched: bool = false
var _thread: Thread = Thread.new()
## Whether the transcription running is the phone's, so its text goes to `heard_from_phone`.
var _from_phone: bool = false

@onready var mic: AudioStreamPlayer = $Mic


func _ready() -> void:
	var saved: String = load_device(SETTINGS_PATH)
	if not saved.is_empty() and saved in AudioServer.get_input_device_list():
		AudioServer.input_device = saved
	var bus: int = AudioServer.get_bus_index(BUS)
	if bus >= 0 and AudioServer.get_bus_effect_count(bus) > 0:
		_capture = AudioServer.get_bus_effect(bus, 0) as AudioEffectCapture


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()


## Listens through `device` (a name from AudioServer.get_input_device_list()) from now on.
func use_device(device: String) -> void:
	AudioServer.input_device = device
	save_device(SETTINGS_PATH, device)


static func load_device(path: String) -> String:
	var config: ConfigFile = ConfigFile.new()
	return config.get_value("mic", "device", "") if config.load(path) == OK else ""


static func save_device(path: String, device: String) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value("mic", "device", device)
	config.save(path)


func is_supported() -> bool:
	return _capture != null


func start() -> void:
	# A listener that hands its sentences over (the phone's) needs no speech model of its own.
	if mode != Mode.OFF or not is_supported() or (model_alias.is_empty() and not hand_off):
		return
	_capture.clear_buffer()
	_samples.clear()
	mic.play()
	mode = Mode.WAITING


func stop() -> void:
	mic.stop()
	_samples.clear()
	mode = Mode.OFF


## Turns the mic off, but a sentence it is in the middle of hearing still goes to be written down,
## as though you had paused: you said it, so it is sent. True when there was one to send.
func finish() -> bool:
	var speaking: bool = mode == Mode.HEARING and _voiced >= min_speech_seconds
	if speaking:
		_transcribe(AudioServer.get_mix_rate())
	mic.stop()
	_samples.clear()
	# Off, but a transcription under way still ends in `heard` (or `wav_ready` has gone already).
	mode = Mode.OFF
	return speaking


## Stops listening for a while (the duck is thinking or talking) without turning the mic off.
func pause() -> void:
	if mode == Mode.WAITING or mode == Mode.HEARING:
		_samples.clear()
		mode = Mode.PAUSED


func resume() -> void:
	if mode == Mode.PAUSED:
		_capture.clear_buffer()
		mode = Mode.WAITING


## Pumps the captured audio every frame; a stream of samples has nothing to signal but its arrival.
func _process(_delta: float) -> void:
	if mode == Mode.OFF or _capture == null:
		return
	var available: int = _capture.get_frames_available()
	if available == 0:
		return
	var frames: PackedVector2Array = _capture.get_buffer(available)
	if mode == Mode.PAUSED or mode == Mode.TRANSCRIBING:
		return
	var mix_rate: float = AudioServer.get_mix_rate()
	var chunk: PackedFloat32Array = to_mono(frames)
	var seconds: float = chunk.size() / mix_rate
	var level: float = level_db(chunk)
	level_changed.emit(level)
	var loud: bool = level > speech_threshold_db
	_samples.append_array(chunk)
	if mode == Mode.WAITING:
		if loud:
			_voiced = seconds
			_silence = 0.0
			mode = Mode.HEARING
		else:
			var keep: int = int(preroll_seconds * mix_rate)
			if _samples.size() > keep:
				_samples = _samples.slice(_samples.size() - keep)
		return
	if loud:
		_voiced += seconds
		_silence = 0.0
	else:
		_silence += seconds
	if _silence >= pause_seconds or _samples.size() / mix_rate >= max_seconds:
		if _voiced >= min_speech_seconds:
			_transcribe(mix_rate)
		else:
			_samples.clear()
			mode = Mode.WAITING


func _transcribe(mix_rate: float) -> void:
	var wav: PackedByteArray = to_wav(resample(_samples, mix_rate, RATE), RATE)
	_samples.clear()
	if hand_off:
		mode = Mode.PAUSED
		wav_ready.emit(wav)
		return
	var file: FileAccess = FileAccess.open(WAV_PATH, FileAccess.WRITE)
	file.store_buffer(wav)
	file.close()
	mode = Mode.TRANSCRIBING
	if _thread.is_started():
		_thread.wait_to_finish()
	_thread.start(_run)


## On the thread: fetch the model the first time, then transcribe the WAV.
func _run() -> void:
	if not _model_fetched:
		OS.execute(foundry_path, ["model", "download", model_alias])
		_model_fetched = true
	var output: Array = []
	var args: PackedStringArray = ["transcribe", "-m", model_alias, "-f", ProjectSettings.globalize_path(WAV_PATH), "-o", "json"]
	args.append_array(["-l", language if not language.is_empty() else OS.get_locale_language()])
	var code: int = OS.execute(foundry_path, args, output)
	var raw: String = "".join(output)
	_finish.call_deferred(parse_transcript(raw) if code == 0 else "", "" if code == 0 else "Transcription failed (exit %d): %s" % [code, raw.strip_edges().left(200)])


func _finish(text: String, error: String) -> void:
	_thread.wait_to_finish()
	last_error = error
	if _from_phone:
		_from_phone = false
		heard_from_phone.emit(text)
		return
	if mode == Mode.TRANSCRIBING:
		mode = Mode.PAUSED
	heard.emit(text)


## Transcribes a sentence the phone recorded, `wav` as `to_wav` makes it; the text arrives through
## `heard_from_phone`. False when a transcription is already running, or there is no speech model.
func transcribe_wav(wav: PackedByteArray) -> bool:
	if _thread.is_started() and _thread.is_alive() or model_alias.is_empty() or wav.is_empty():
		return false
	if _thread.is_started():
		_thread.wait_to_finish()
	var file: FileAccess = FileAccess.open(WAV_PATH, FileAccess.WRITE)
	file.store_buffer(wav)
	file.close()
	_from_phone = true
	_thread.start(_run)
	return true


func _set_mode(value: Mode) -> void:
	if value == mode:
		return
	mode = value
	mode_changed.emit(value)


static func to_mono(frames: PackedVector2Array) -> PackedFloat32Array:
	var mono: PackedFloat32Array = PackedFloat32Array()
	mono.resize(frames.size())
	for i: int in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	return mono


## Root mean square level in decibels; -inf for silence.
static func level_db(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return -INF
	var sum: float = 0.0
	for s: float in samples:
		sum += s * s
	return linear_to_db(sqrt(sum / samples.size()))


## Linear resampling, plenty for speech going to a 16 kHz model.
static func resample(samples: PackedFloat32Array, from_rate: float, to_rate: float) -> PackedFloat32Array:
	if is_equal_approx(from_rate, to_rate) or samples.is_empty():
		return samples
	var ratio: float = from_rate / to_rate
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(int(samples.size() / ratio))
	for i: int in out.size():
		var at: float = i * ratio
		var index: int = int(at)
		var next: int = mini(index + 1, samples.size() - 1)
		out[i] = lerpf(samples[index], samples[next], at - index)
	return out


## A 16-bit mono PCM WAV file.
static func to_wav(samples: PackedFloat32Array, rate: int) -> PackedByteArray:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var header: PackedByteArray = PackedByteArray()
	header.resize(44)
	header.encode_u32(0, 0x46464952) # "RIFF"
	header.encode_u32(4, 36 + data.size())
	header.encode_u32(8, 0x45564157) # "WAVE"
	header.encode_u32(12, 0x20746d66) # "fmt "
	header.encode_u32(16, 16)
	header.encode_u16(20, 1) # PCM
	header.encode_u16(22, 1) # mono
	header.encode_u32(24, rate)
	header.encode_u32(28, rate * 2)
	header.encode_u16(32, 2)
	header.encode_u16(34, 16)
	header.encode_u32(36, 0x61746164) # "data"
	header.encode_u32(40, data.size())
	return header + data


## The text from `foundry transcribe -o json`, or "" when there is none.
static func parse_transcript(json: String) -> String:
	var parsed: JSON = JSON.new()
	if parsed.parse(json.strip_edges()) != OK or not parsed.data is Dictionary:
		return ""
	return String(parsed.data.get("text", "")).strip_edges()
