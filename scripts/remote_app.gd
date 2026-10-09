class_name RemoteApp
extends Control
## The duck on your phone: a remote control for the duck on your PC. The duck sits on the top half,
## and the bottom half has the same tabs as the PC's bubble (DuckTabs): Chat, Pomodoro, Stats,
## Settings and Duck, showing the PC duck's and changing it. What you type or say goes to the PC,
## which answers as it would there, screen reading and all; its sentences come back as text and,
## with a Kokoro voice chosen on the PC, as audio. The phone finds the PC by its beacon (see
## remote.gd) or by an address typed in, and pairs with the code shown on the PC's Settings tab.

## Whose duck this is: the PC's (paired, or looking for it), the Pomodoro timer alone with no PC,
## or a model running on the phone.
enum Mode { PC, POMODORO, LOCAL }

const SETTINGS_PATH: String = "user://remote.cfg"
## Missed pongs before the PC counts as lost.
const MAX_MISSED: int = 3

@export var port: int = 39842
@export var beacon_port: int = 39843
## A jolt of the phone stronger than this, in m/sÂ² beyond its steady pull, stirs the bath.
@export var shake_threshold: float = 2.5
## How long the bath takes to settle by half after a stir, in seconds.
@export var settle_half_life: float = 0.8
## The swell when calm; a stir raises it up to `stir_swell` times.
@export var calm_swell: float = 0.004
@export var stir_swell: float = 6.0
## Picked up, dropped and thrown, as on the PC: metres a second squared pulling it back to the water,
## the fastest it can be thrown in metres a second, how far from its middle a press still picks it
## up (metres), and how far a finger moves (pixels) before a press is a pick-up rather than a tap.
@export var toss_gravity: float = 5.0
@export var max_toss_speed: float = 6.0
@export var grab_radius: float = 0.17
@export var drag_slop: float = 12.0

var mode: Mode = Mode.PC
## {address: {port, name}} of the PCs whose beacons were heard.
var found: Dictionary = {}
var _client: WebSocketPeer = null
var _host: String = ""
var _code: String = ""
var _paired: bool = false
## Whether the PC sends audio, and whether its brain is awake.
var _speaks: bool = false
var _awake: bool = false
var _waiting: bool = false
## Spoken sentences by index, played in order from `_next_audio`; false for one the PC could not
## synthesise, which is skipped.
var _audio: Dictionary = {}
var _next_audio: int = 1
## The last sentence of this answer so far: its audio has to have played before the mic opens again,
## or the mic hears the duck and sends its own words back as yours.
var _last_sentence: int = 0
## Counts answers, so a give-up timer from an earlier one does nothing.
var _turn: int = 0
## Muted: nothing is said here, and the PC makes no audio for this phone.
var _muted: bool = false
## How stirred the bath is, from 0 (calm) to 1, and the phone's steady pull, to tell a jolt from it.
var _stir: float = 0.0
var _steady: Vector3 = Vector3.ZERO
var _last_burst: int = -100000
## A press on the duck view: where, whether it was on the duck, and the finger now.
var _pressed: bool = false
var _press_at: Vector2 = Vector2.ZERO
var _on_duck: bool = false
var _finger: Vector2 = Vector2.ZERO
## Held: where on the duck it was picked up, and [msec, position] over the last tenth of a second,
## for the throw. Flying: its speed (x, y in metres a second) and spin.
var _held: bool = false
## The highest it has been lifted out of the water while held, in metres.
var _lifted: float = 0.0
var _grab_offset: Vector2 = Vector2.ZERO
var _trail: Array = []
var _flying: bool = false
var _toss: Vector2 = Vector2.ZERO
var _spin: float = 0.0
## What it was doing before it was picked up, to go back to once it has landed.
var _mood: StringName = &"idle"
var _missed: int = 0
var _beacon: PacketPeerUDP = PacketPeerUDP.new()
var _utterance: int = 0

@onready var duck: Duck = $Layout/DuckView/Viewport/Duck
@onready var duck_view: SubViewportContainer = $Layout/DuckView
@onready var title: Label = $Layout/Chat/Margin/Column/Header/Title
@onready var status: Label = $Layout/Chat/Margin/Column/Header/Status
## The same tabs as the PC's bubble (scenes/duck_tabs.tscn).
@onready var tabs: DuckTabs = $Layout/Chat/Margin/Column/Tabs
@onready var find_pc_button: Button = $Layout/Chat/Margin/Column/Header/FindPc
## The phone's own timer, mind and brain, for when there is no PC.
@onready var local_pomodoro: Pomodoro = $Pomodoro
@onready var mind: Mind = $Mind
@onready var local_brain: LocalBrain = $LocalBrain
@onready var pairing: Control = $Pairing
@onready var found_list: ItemList = $Pairing/Margin/Column/Found
@onready var address: LineEdit = $Pairing/Margin/Column/Address
@onready var code_input: LineEdit = $Pairing/Margin/Column/Code
@onready var pairing_note: Label = $Pairing/Margin/Column/Note
@onready var player: AudioStreamPlayer = $Player
@onready var squeak: AudioStreamPlayer = $Squeak
## Quick squeaks, one of five, for a throw, a bounce off the side and a splash.
@onready var fast_squeak: AudioStreamPlayer = $FastSqueak
@onready var listener: Listener = $Listener
@onready var ping_clock: Timer = $PingClock
@onready var bubbles: CPUParticles3D = $Layout/DuckView/Viewport/Bubbles
@onready var water: MeshInstance3D = $Layout/DuckView/Viewport/Water
@onready var pond_camera: Camera3D = $Layout/DuckView/Viewport/PondCamera


func _ready() -> void:
	duck.looking_at_viewer = true
	duck.play(&"sleep")
	if OS.get_name() == "Android":
		OS.request_permissions()
	_beacon.bind(beacon_port)
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	_host = str(config.get_value("pc", "address", ""))
	_code = str(config.get_value("pc", "code", ""))
	address.text = _host
	code_input.text = _code
	_muted = bool(config.get_value("sound", "muted", false))
	tabs.mute_box.set_pressed_no_signal(_muted)
	tabs.mute_box.tooltip_text = "Say nothing on this phone: answers are written only, and the PC makes no audio for it."
	var mic: String = Listener.load_device(Listener.SETTINGS_PATH)
	tabs.show_mics(AudioServer.get_input_device_list(), mic if not mic.is_empty() else AudioServer.input_device)
	tabs.mics.tooltip_text = "The microphone this phone listens through."
	tabs.pairing_label.text = "Not paired with a PC yet."
	# Nothing to say or ask until a PC answers.
	_set_awake(false, "")
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _on_utterance_ended)
	if not _host.is_empty() and not _code.is_empty():
		_connect()
	else:
		_show_pairing("Looking for your PC...")


func _process(delta: float) -> void:
	# A jolt of the phone stirs the bath: the pull of gravity is steady, a shake is not.
	var pull: Vector3 = Input.get_accelerometer()
	if pull != Vector3.ZERO:
		_steady = pull if _steady == Vector3.ZERO else _steady.lerp(pull, 1.0 - exp(-4.0 * delta))
		var jolt: float = (pull - _steady).length()
		if jolt > shake_threshold:
			_disturb(stir_for(jolt, shake_threshold))
	_stir = settled_stir(_stir, delta, settle_half_life)
	# Afloat: a gentle bob and roll on the swell, a good deal more when stirred.
	var t: float = Time.get_ticks_msec() / 1000.0
	var rock: float = 1.0 + _stir * 4.0
	var at: Vector2 = Vector2(duck.position.x, duck.position.y)
	if _held:
		# Dangling from your finger, never pushed under the water.
		at = _on_plane(_finger) + _grab_offset
		at.y = maxf(at.y, 0.0)
		_lifted = maxf(_lifted, at.y)
		var now: int = Time.get_ticks_msec()
		_trail.append([now, at])
		while _trail.size() > 2 and now - int(_trail[0][0]) > 100:
			_trail.pop_front()
		duck.rotation.z = lerp_angle(duck.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))
	elif _flying:
		var step: Dictionary = toss(at, _toss, _bounds(), delta, toss_gravity)
		at = step["position"]
		_toss = step["velocity"]
		if at.y > 0.0:
			_spin = lerpf(_spin, -_toss.x * 4.0, 1.0 - exp(-3.0 * delta))
			duck.rotation.z += _spin * delta
		else:
			# In the water it rights itself rather than sliding along on its side.
			_spin = 0.0
			duck.rotation.z = lerp_angle(duck.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))
		if step["splash"] > 0.0:
			_splash(step["splash"])
		elif step["bump"] > 1.5:
			fast_squeak.play()
		if step["resting"]:
			_flying = false
			get_tree().create_timer(0.8).timeout.connect(_after_landing)
	else:
		# Afloat: a gentle bob and roll on the swell, a good deal more when stirred, drifting back
		# to the middle of its suds.
		at = Vector2(lerpf(at.x, 0.0, 1.0 - exp(-0.6 * delta)), sin(t * 1.6) * 0.006 * rock)
		duck.rotation.z = lerp_angle(duck.rotation.z, sin(t * 1.1) * 0.035 * rock, 1.0 - exp(-5.0 * delta))
	duck.position.x = at.x
	duck.position.y = at.y
	var bath: ShaderMaterial = water.mesh.surface_get_material(0)
	bath.set_shader_parameter("wave_amplitude", calm_swell * (1.0 + _stir * (stir_swell - 1.0)))
	# The contact foam rings the duck while it sits in the water, and nothing while it is out of it.
	bath.set_shader_parameter("contact_footprint", Vector4(at.x, 0.0 if at.y < 0.03 else 100.0, 0.125, 0.15))
	while _beacon.get_available_packet_count() > 0:
		var heard: Dictionary = Remote.parse_beacon(_beacon.get_packet().get_string_from_utf8())
		var from: String = _beacon.get_packet_ip()
		if not heard.is_empty() and not found.has(from):
			found[from] = heard
			found_list.add_item("%s  (%s)" % [heard["name"] if not str(heard["name"]).is_empty() else "Duck", from])
			found_list.set_item_metadata(found_list.item_count - 1, from)
	if _client == null:
		return
	_client.poll()
	match _client.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _client.get_available_packet_count() > 0:
				var packet: PackedByteArray = _client.get_packet()
				if _client.was_string_packet():
					_on_frame(Remote.parse_frame(packet.get_string_from_utf8()))
				else:
					_on_audio(Remote.read_audio_frame(packet))
		WebSocketPeer.STATE_CLOSED:
			_client = null
			ping_clock.stop()
			if _paired:
				_paired = false
				_set_status("Lost the PC. Reconnecting...")
				get_tree().create_timer(3.0).timeout.connect(_connect)
			else:
				_show_pairing("Couldn't reach the duck at %s." % _host)


func _connect() -> void:
	if _host.is_empty() or _client != null:
		return
	_client = WebSocketPeer.new()
	_client.inbound_buffer_size = Remote.BUFFER_BYTES
	_client.outbound_buffer_size = Remote.BUFFER_BYTES
	_set_status("Connecting to %s..." % _host)
	if _client.connect_to_url("ws://%s:%d" % [_host, port]) != OK:
		_client = null
		_show_pairing("That address doesn't look right.")
		return
	# The hello goes as soon as the socket opens.
	_await_open()


func _await_open() -> void:
	while _client != null and _client.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		await get_tree().process_frame
	if _client != null and _client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_client.send_text(JSON.stringify({"hello": _code, "name": OS.get_model_name()}))


func _on_frame(frame: Dictionary) -> void:
	if frame.has("welcome"):
		_paired = true
		_missed = 0
		ping_clock.start()
		pairing.visible = false
		_save()
		_tell_pc({"mute": _muted})
		_speaks = frame.get("speaks", false)
		tabs.show_conversation(frame.get("recent", []))
		_show_duck(str(frame["welcome"]), frame.get("memories", []))
		_show_hat(bool(frame.get("hat", false)))
		duck.tomato = bool(frame.get("tomato", false))
		tabs.show_pomodoro(frame.get("pomodoro_state", {}))
		tabs.stats.text = str(frame.get("stats", ""))
		var voices: Dictionary = frame.get("voices", {})
		tabs.show_voices(voices.get("items", []), str(voices.get("chosen", "")), str(voices.get("note", "")))
		tabs.pairing_label.text = "Paired with the duck at %s." % _host
		tabs.show_model(bool(frame.get("ready", false)), bool(frame.get("stopped", false)))
		_set_awake(frame.get("ready", false), str(frame.get("status", "")))
	elif frame.has("hat") and frame.size() == 1:
		_show_hat(bool(frame["hat"]))
	elif frame.has("tomato") and frame.size() == 1:
		# A tomato while the Pomodoro timer runs on the PC.
		duck.tomato = bool(frame["tomato"])
	elif frame.has("pomodoro_state"):
		tabs.show_pomodoro(frame["pomodoro_state"])
	elif frame.has("stats"):
		tabs.stats.text = str(frame["stats"])
	elif frame.has("voices"):
		tabs.show_voices(frame["voices"], str(frame.get("chosen", "")), str(frame.get("note", "")))
	elif frame.has("voice_note"):
		tabs.show_voice_note(str(frame["voice_note"]), true)
	elif frame.has("duck_name"):
		_show_duck(str(frame["duck_name"]), frame.get("memories", []))
	elif frame.has("conversations"):
		tabs.show_past(frame["conversations"], str(frame.get("current", "")))
	elif frame.has("conversation"):
		player.stop()
		_audio.clear()
		tabs.show_conversation(frame.get("messages", []))
		_set_status("New conversation" if (frame.get("messages", []) as Array).is_empty() else "")
	elif frame.has("bye"):
		_paired = false
		_show_pairing("The PC said: %s. Check the code on its Settings tab." % frame["bye"])
	elif frame.has("pong"):
		_missed = 0
	elif frame.has("status"):
		tabs.show_model(bool(frame.get("ready", _awake)), bool(frame.get("stopped", false)))
		_set_awake(frame.get("ready", _awake), str(frame["status"]))
	elif frame.has("you"):
		if str(frame["you"]).is_empty():
			_set_status(str(frame.get("error", "I didn't catch that.")))
			_listen_again()
		else:
			_waiting = true
			_turn += 1
			_audio.clear()
			_next_audio = 1
			_last_sentence = 0
			player.stop()
			listener.pause()
			# The duck's bubble now, "..." until its first sentence; the rest join it as they come.
			tabs.begin_answer(str(frame["you"]))
			duck.play(&"think")
			_set_status("Thinking...")
	elif frame.has("sentence"):
		_last_sentence = maxi(_last_sentence, int(frame.get("index", 0)))
		tabs.add_sentence(str(frame["sentence"]))
		if not _speaks and not _muted:
			_utterance += 1
			DisplayServer.tts_speak(str(frame["sentence"]), Voice.default_voice(DisplayServer.tts_get_voices(), OS.get_locale_language()), 70, 1.0, 1.0, _utterance, false)
			duck.play(&"talk")
	elif frame.has("replied"):
		_waiting = false
		if not tabs.answer_started():
			tabs.set_answer(str(frame["replied"]))
		tabs.add_note(str(frame.get("notes", "")))
		_set_status("")
		# Audio for a sentence that never comes must not keep the mic shut for good.
		get_tree().create_timer(20.0).timeout.connect(_give_up_on_audio.bind(_turn))
		_after_speaking()
	elif frame.has("busy"):
		_set_status("The duck is busy. Try again in a moment.")
		_listen_again()


func _on_audio(frame: Dictionary) -> void:
	if frame.get("kind", 0) != Remote.AUDIO_OUT or _muted:
		return
	var wav: PackedByteArray = frame["wav"]
	var stream: AudioStreamWAV = AudioStreamWAV.load_from_buffer(wav) if not wav.is_empty() else null
	_audio[int(frame["index"])] = stream if stream != null else false
	_play_next()


func _play_next() -> void:
	if player.playing:
		return
	while _audio.get(_next_audio) is bool:
		_audio.erase(_next_audio)
		_next_audio += 1
	var stream: AudioStreamWAV = next_audio(_audio, _next_audio)
	if stream == null:
		_after_speaking()
		return
	_audio.erase(_next_audio)
	_next_audio += 1
	player.stream = stream
	player.play()
	duck.play(&"talk")


func _on_player_finished() -> void:
	_play_next()


func _on_utterance_ended(id: int) -> void:
	if id == _utterance:
		_after_speaking.call_deferred()


## Back to idle and listening once the answer is in and nothing is left to say.
func _after_speaking() -> void:
	if _waiting or player.playing or not _audio.is_empty() or (not _speaks and DisplayServer.tts_is_speaking()):
		return
	if _speaks and not _muted and owes_audio(_next_audio, _last_sentence):
		return
	duck.play(&"idle" if _awake else &"sleep")
	_listen_again()


func _listen_again() -> void:
	if tabs.mic_button.button_pressed:
		listener.resume()


func _set_awake(awake: bool, text: String) -> void:
	if awake and not _awake:
		duck.play(&"wake")
	elif not awake:
		duck.play(&"sleep")
	_awake = awake
	_set_status("" if awake else text)
	tabs.input.editable = awake
	tabs.send_button.disabled = not awake
	tabs.mic_button.disabled = not awake
	tabs.new_button.disabled = not awake
	tabs.past_button.disabled = not awake


func _set_status(text: String) -> void:
	status.text = text


## Sends `frame` to the PC; false when there is no PC to send it to.
func _tell_pc(frame: Dictionary) -> bool:
	if _client == null or not _paired:
		return false
	_client.send_text(JSON.stringify(frame))
	return true


## Typed and sent on the Chat tab: to the PC, or with no PC to the phone's own duck, which answers a
## Pomodoro request itself as the PC does.
func _on_tabs_line_sent(line: String) -> void:
	if mode != Mode.LOCAL:
		_tell_pc({"say": line})
		return
	var request: Dictionary = Pomodoro.request_in(line)
	if not request.is_empty():
		var said: String = local_pomodoro.carry_out(request)
		tabs.begin_answer(line, said)
		_speak_here(said, true)
		return
	if local_brain.ask(line):
		tabs.begin_answer(line)
		duck.play(&"think")
		_set_local_entry()


## The duck's name, as the title and on the Duck tab, and what it remembers.
func _show_duck(duck_name: String, memories: Array) -> void:
	title.text = duck_name if not duck_name.is_empty() else "Rubber Duck"
	tabs.show_duck(duck_name, PackedStringArray(memories))


## Puts the captain's hat on or takes it off, here and on the PC duck.
func _on_hat_toggled(on: bool) -> void:
	duck.hat = on
	_tell_pc({"hat": on})


## The hat as the PC has it, without sending it back.
func _show_hat(on: bool) -> void:
	duck.hat = on
	tabs.show_hat(on)


## The Pomodoro tab's buttons and lengths work the PC's timer, whose state comes back to the tab;
## with no PC, the phone's own.
func _on_pomodoro_pressed(action: String) -> void:
	if mode == Mode.PC:
		_tell_pc({"pomodoro": action})
	else:
		local_pomodoro.act(action)


func _on_lengths_changed(minutes: Array[int]) -> void:
	if mode == Mode.PC:
		_tell_pc({"lengths": minutes})
	else:
		local_pomodoro.set_lengths(minutes)


## The duck on its own, with just the Pomodoro timer.
func _on_pomodoro_only_pressed() -> void:
	_go_alone(Mode.POMODORO)


## The duck on its own with a model on the phone: Gemini Nano, or the largest that fits.
func _on_local_llm_pressed() -> void:
	_go_alone(Mode.LOCAL)
	local_brain.start()


## Stops looking for the PC and runs the duck on the phone: in Pomodoro only, every tab but the
## timer's is off, since the rest needs a model.
func _go_alone(alone: Mode) -> void:
	mode = alone
	if _client != null:
		_client.close()
		_client = null
	_paired = false
	ping_clock.stop()
	pairing.visible = false
	find_pc_button.visible = true
	_set_status("No PC: just the timer" if alone == Mode.POMODORO else local_brain.status)
	for i: int in tabs.get_tab_count():
		tabs.set_tab_disabled(i, alone == Mode.POMODORO and tabs.get_tab_control(i).name != &"Pomodoro")
	tabs.show_pomodoro(local_pomodoro.state())
	duck.tomato = local_pomodoro.is_running()
	duck.play(&"wake")
	_awake = true
	if alone == Mode.POMODORO:
		title.text = "Pomodoro"
		tabs.current_tab = tabs.get_tab_idx_from_control(tabs.get_node("Pomodoro"))
		return
	# The phone's own duck: its name, memories and conversation, its voices, and no PC to listen.
	_show_duck(mind.duck_name(), Array(mind.memories()))
	tabs.show_conversation(Remote.shown(mind.conversation(mind.conversation_id())))
	_fill_phone_voices()
	tabs.stats.text = local_stats()
	tabs.pairing_label.text = "No PC: the duck runs on this phone."
	tabs.current_tab = 0
	_set_local_entry()


## In local mode the box opens once a model is ready; the mic stays off, as the PC is what writes
## down speech.
func _set_local_entry() -> void:
	tabs.input.editable = local_brain.is_ready()
	tabs.send_button.disabled = not local_brain.is_ready() or local_brain.is_busy()
	tabs.mic_button.disabled = true
	tabs.mic_button.tooltip_text = "Talking needs the PC, which writes down what you say. Type here instead."
	tabs.new_button.disabled = false
	tabs.past_button.disabled = false


func _on_local_brain_status_changed(text: String) -> void:
	if mode != Mode.LOCAL:
		return
	_set_status(text if not local_brain.is_ready() else "")
	tabs.stats.text = local_stats()
	tabs.show_model(local_brain.is_ready(), local_brain.stopped)
	_set_local_entry()
	duck.play(&"idle" if local_brain.is_ready() else &"sleep")


## The Stats tab's button: the phone's own model with no PC, or the PC's from a paired phone.
func _on_model_toggled(run: bool) -> void:
	if mode != Mode.LOCAL:
		_tell_pc({"model": run})
		return
	if run:
		local_brain.start()
	else:
		DisplayServer.tts_stop()
		local_brain.stop()


## Whether the phone's model is to wake again when the app comes back from the background.
var _wake_local: bool = false


## A phone app in the background holds its memory for nothing, and closing it must not leave a model
## behind, so the phone's model stops as the app goes to the background or closes; coming back wakes
## it again, from the model already downloaded.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			if mode == Mode.LOCAL and (local_brain.is_ready() or local_brain.is_starting()):
				_wake_local = true
				DisplayServer.tts_stop()
				local_brain.stop()
		NOTIFICATION_APPLICATION_RESUMED:
			if _wake_local and mode == Mode.LOCAL:
				_wake_local = false
				local_brain.start()
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			if is_instance_valid(local_brain):
				local_brain.stop()


func _on_local_brain_sentence(text: String) -> void:
	if mode != Mode.LOCAL:
		return
	tabs.add_sentence(text)
	_speak_here(text, false)
	duck.play(&"talk")


func _on_local_brain_replied(text: String) -> void:
	if mode != Mode.LOCAL:
		return
	if not tabs.answer_started():
		tabs.set_answer(text)
		_speak_here(text, false)
	tabs.add_note(_take_notes())
	_set_status("")
	_set_local_entry()
	duck.play(&"idle")


## What the duck remembered or learned on the way, noted under the answer.
var _notes: Array[String] = []


func _on_mind_changed(note: String) -> void:
	_notes.append(note)
	if mode == Mode.LOCAL:
		_show_duck(mind.duck_name(), Array(mind.memories()))


func _take_notes() -> String:
	var text: String = "; ".join(_notes)
	_notes.clear()
	return text


## The Stats tab with no PC: which model answers on this phone, and how it is going.
func local_stats() -> String:
	return "%s\nModel: %s\nEngine: %s" % [local_brain.status, local_brain.model_name if not local_brain.model_name.is_empty() else "not loaded yet", local_brain.engine if not local_brain.engine.is_empty() else "none yet"]


## Says `text` in this phone's voice, after what it is saying unless `interrupt`.
func _speak_here(text: String, interrupt: bool) -> void:
	if _muted or not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	_utterance += 1
	DisplayServer.tts_speak(text, _phone_voice(), 70, 1.0, 1.0, _utterance, interrupt)


## The phone voice chosen on the Settings tab in local mode, or the phone's default for its language.
func _phone_voice() -> String:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	var chosen: String = str(config.get_value("sound", "voice", ""))
	var voices: Array[Dictionary] = DisplayServer.tts_get_voices()
	if not chosen.is_empty() and voices.any(func(v: Dictionary) -> bool: return v.get("id", "") == chosen):
		return chosen
	return Voice.default_voice(voices, OS.get_locale_language())


## The Settings tab's voices with no PC: the phone's own.
func _fill_phone_voices() -> void:
	var items: Array[Dictionary] = DuckTabs.voice_items(DisplayServer.tts_get_voices(), false, false, "")
	var chosen: String = _phone_voice()
	tabs.show_voices(items, chosen, "Speaking with this phone's voice." if not items.is_empty() else "This phone offers no voices; answers are written only.")


## Back to looking for the PC: the phone's own timer stops, as the PC keeps its own, and its model
## lets go of the memory.
func _on_find_pc_pressed() -> void:
	mode = Mode.PC
	if local_pomodoro.is_running():
		local_pomodoro.stop()
	local_brain.stop()
	DisplayServer.tts_stop()
	tabs.show_model(false, false)
	tabs.mic_button.tooltip_text = "Talk to the duck. It sends when you pause, and listens again after it answers. Click again to stop."
	find_pc_button.visible = false
	for i: int in tabs.get_tab_count():
		tabs.set_tab_disabled(i, false)
	tabs.current_tab = 0
	title.text = "Rubber Duck"
	_set_awake(false, "")
	if not _host.is_empty() and not _code.is_empty():
		_connect()
	_show_pairing("Looking for your PC...")


func _on_local_pomodoro_changed() -> void:
	if mode != Mode.PC:
		tabs.show_pomodoro(local_pomodoro.state())


## A tomato while the phone's timer runs, with the screen kept on so the phone does not sleep
## through the end of a phase.
func _on_local_pomodoro_phase_changed(phase: Pomodoro.Phase) -> void:
	if mode == Mode.PC:
		return
	duck.tomato = phase != Pomodoro.Phase.OFF
	DisplayServer.screen_set_keep_on(phase != Pomodoro.Phase.OFF)
	if phase == Pomodoro.Phase.OFF and mode == Mode.POMODORO:
		_set_status("No PC: just the timer")


## Time is up on the phone's timer: a squeak, a hop, and the news in the phone's own voice.
func _on_local_pomodoro_time_up(next: Pomodoro.Phase) -> void:
	if mode == Mode.PC:
		return
	var text: String = Pomodoro.announcement(next, local_pomodoro.minutes_for(next), local_pomodoro.finished, local_pomodoro.rounds)
	squeak.play()
	duck.play(&"cheer", true)
	get_tree().create_timer(Duck.HOP_SECONDS * 3.0).timeout.connect(_after_landing)
	_set_status(text)
	if not _muted and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		_utterance += 1
		DisplayServer.tts_speak(text, Voice.default_voice(DisplayServer.tts_get_voices(), OS.get_locale_language()), 70, 1.0, 1.0, _utterance, true)


## The download entry in the voice list starts the natural voices downloading on the PC.
func _on_voice_selected(id: String) -> void:
	if id == DuckTabs.DOWNLOAD_KOKORO:
		_tell_pc({"download_voices": true})


## Test says the line on the PC, the way the PC's own Test does; with no PC, here.
func _on_voice_tested(id: String) -> void:
	if mode != Mode.LOCAL:
		_tell_pc({"test_voice": id})
	elif not id.is_empty():
		DisplayServer.tts_speak("Quack! I'm your rubber duck. Is this how you want me to sound?", id, 70, 1.0, 1.0, 0, true)


func _on_voice_applied(id: String) -> void:
	if mode != Mode.LOCAL:
		_tell_pc({"voice": id})
		return
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("sound", "voice", id)
	config.save(SETTINGS_PATH)
	_fill_phone_voices()


## The phone's own microphone.
func _on_mic_chosen(device: String) -> void:
	listener.use_device(device)


func _on_name_saved(duck_name: String) -> void:
	if mode == Mode.LOCAL:
		mind.set_duck_name(duck_name)
	else:
		_tell_pc({"name": duck_name})


func _on_memory_forgotten(index: int) -> void:
	if mode == Mode.LOCAL:
		mind.forget_at(index)
	else:
		_tell_pc({"forget": index})


func _on_mute_toggled(on: bool) -> void:
	_muted = on
	if on:
		player.stop()
		_audio.clear()
		DisplayServer.tts_stop()
	_tell_pc({"mute": on})
	_save()
	_after_speaking()


func _on_new_pressed() -> void:
	if mode == Mode.LOCAL:
		if not local_brain.is_busy():
			local_brain.new_conversation()
			tabs.show_conversation([])
		return
	_tell_pc({"new": true})


func _on_past_pressed() -> void:
	if mode == Mode.LOCAL:
		tabs.show_past(mind.conversations(), mind.conversation_id())
	elif not _tell_pc({"list": true}):
		tabs.show_past([], "")


func _on_conversation_chosen(id: String) -> void:
	if mode == Mode.LOCAL:
		if not local_brain.is_busy() and mind.open_conversation(id):
			local_brain.new_conversation_from(Remote.shown(mind.conversation(id)))
			tabs.show_conversation(Remote.shown(mind.conversation(id)))
		return
	_tell_pc({"open": id})


func _on_mic_toggled(on: bool) -> void:
	tabs.mic_dot.visible = on
	if on:
		listener.start()
		if listener.mode == Listener.Mode.OFF:
			_set_status("The mic didn't open. Is the microphone allowed for this app?")
	elif not listener.finish():
		_set_status("")


## What the mic is doing, in the status line, so a mic that hears nothing is plain to see.
func _on_listener_mode_changed(mode: Listener.Mode) -> void:
	if not tabs.mic_button.button_pressed:
		return
	match mode:
		Listener.Mode.WAITING:
			if not _waiting:
				_set_status("Listening...")
		Listener.Mode.HEARING:
			_set_status("Hearing you...")


## A spoken sentence goes to the PC to be written down and answered.
func _on_listener_wav_ready(wav: PackedByteArray) -> void:
	if _client == null or not _paired:
		return
	_client.send(Remote.audio_frame(Remote.AUDIO_IN, 0, wav), WebSocketPeer.WRITE_MODE_BINARY)
	_set_status("Writing it down...")


func _on_ping_clock_timeout() -> void:
	if _client == null:
		return
	_missed += 1
	if _missed > MAX_MISSED:
		_client.close()
		return
	_client.send_text(JSON.stringify({"ping": Time.get_ticks_msec()}))


## A tap squeezes the duck, a double tap swaps its hat, and a press on it that moves picks it up:
## let go to drop it, or let go mid-swing to throw it. Touches arrive as the mouse events Godot
## makes from them, so this reads those alone and a tap is not handled twice.
func _on_duck_view_gui_input(event: InputEvent) -> void:
	var press: InputEventMouseButton = event as InputEventMouseButton
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		_finger = motion.position
		if _pressed and _on_duck and not _held and _finger.distance_to(_press_at) > drag_slop:
			_pick_up()
		return
	if press == null or press.button_index != MOUSE_BUTTON_LEFT:
		return
	if press.pressed:
		if press.double_click:
			# A double tap swaps the captain's hat, on the PC duck too.
			tabs.hat_box.button_pressed = not tabs.hat_box.button_pressed
			return
		_pressed = true
		_press_at = press.position
		_finger = press.position
		var at: Vector2 = _on_plane(press.position)
		_on_duck = at.distance_to(Vector2(duck.position.x, duck.position.y - 0.05)) < grab_radius
		_grab_offset = Vector2(duck.position.x, duck.position.y) - at
		return
	if _held and is_squash(_lifted, Pet.throw_velocity(_trail, max_toss_speed)):
		# Pushed down into the water, or barely lifted and let go: a squeeze, not a drop.
		_held = false
		duck.play(&"squeeze", true)
		squeak.play()
		_disturb(0.6)
		get_tree().create_timer(0.8).timeout.connect(_after_landing)
	elif _held:
		# Let go mid-swing and it keeps the finger's speed: a gentle drop or a proper throw.
		_held = false
		_flying = true
		_toss = Pet.throw_velocity(_trail, max_toss_speed)
		_spin = -_toss.x * 4.0
		duck.play(&"fall")
		if _toss.length() > 1.5:
			fast_squeak.play()
	elif _pressed:
		duck.play(&"squeeze", true)
		squeak.play()
		_disturb(0.6)
	_pressed = false


func _pick_up() -> void:
	if not _flying:
		_mood = duck.animation
	_held = true
	_flying = false
	_lifted = 0.0
	_trail.clear()
	duck.play(&"hang")


## Whether letting go of a duck lifted at most `lifted` metres and moving at `speed` is a squeeze
## rather than a drop: pushed down into the water, or never really out of it, and not flung.
static func is_squash(lifted: float, speed: Vector2) -> bool:
	return lifted < 0.03 and speed.length() < 1.5


## Back in the water: a splash as hard as it came down, a squeak if it was a real belly flop.
func _splash(speed: float) -> void:
	bubbles.position.x = duck.position.x
	_last_burst = -100000
	_disturb(clampf(speed / 2.5, 0.3, 1.0))
	duck.play(&"land", true)
	if speed > 1.5:
		fast_squeak.play()


func _after_landing() -> void:
	if not _held and not _flying:
		duck.play(_mood)


## Where a point on the duck view meets the plane the duck floats in (x, y in metres).
func _on_plane(point: Vector2) -> Vector2:
	var hit: Variant = Plane(Vector3.BACK, duck.position.z).intersects_ray(pond_camera.project_ray_origin(point), pond_camera.project_ray_normal(point))
	return Vector2(hit.x, hit.y) if hit != null else Vector2(duck.position.x, duck.position.y)


## How far it can fly: the view's sides, less half a tumbling duck, and its top, less its height.
func _bounds() -> Rect2:
	var view: Vector2 = Vector2(duck_view.size)
	var left: float = _on_plane(Vector2(0.0, view.y / 2.0)).x + 0.2
	var right: float = _on_plane(Vector2(view.x, view.y / 2.0)).x - 0.2
	var top: float = _on_plane(Vector2(view.x / 2.0, 0.0)).y - 0.12
	return Rect2(left, 0.0, right - left, top)


## One step of a thrown duck's flight in the plane it floats in, y up and the water at y = 0: it
## bounces off the sides and the top of `bounds`, and splashes down, bobbing up again a little after
## a hard landing. Returns its new position and velocity, how fast it hit the water (`splash`) or a
## side or the top (`bump`) this step (0 if it did not), and whether it has settled.
static func toss(from: Vector2, speed: Vector2, bounds: Rect2, delta: float, pull: float) -> Dictionary:
	var v: Vector2 = speed + Vector2(0.0, -pull * delta)
	var p: Vector2 = from + v * delta
	var splash: float = 0.0
	var bump: float = 0.0
	if p.x < bounds.position.x or p.x > bounds.end.x:
		bump = absf(v.x)
		p.x = clampf(p.x, bounds.position.x, bounds.end.x)
		v.x = -v.x * 0.55
	if p.y > bounds.end.y:
		bump = maxf(bump, absf(v.y))
		p.y = bounds.end.y
		v.y = -absf(v.y) * 0.55
	if p.y <= 0.0:
		p.y = 0.0
		if v.y < 0.0:
			splash = -v.y
			v.y = -v.y * 0.2 if splash > 1.0 else 0.0
		v.x *= exp(-8.0 * delta)
	var resting: bool = p.y <= 0.0 and v.y == 0.0 and absf(v.x) < 0.05
	return {"position": p, "velocity": v, "splash": splash, "bump": bump, "resting": resting}


## The bath is stirred by `strength` (0 to 1): the swell rises and a burst of bubbles comes up,
## at most one burst every 0.4 s however hard it is shaken.
func _disturb(strength: float) -> void:
	_stir = maxf(_stir, strength)
	if Time.get_ticks_msec() - _last_burst > 400:
		_last_burst = Time.get_ticks_msec()
		bubbles.restart()


func _on_found_item_selected(index: int) -> void:
	address.text = str(found_list.get_item_metadata(index))
	code_input.grab_focus()


func _on_connect_pressed() -> void:
	_host = address.text.strip_edges()
	_code = code_input.text.strip_edges()
	if _host.is_empty() or _code.length() != 6:
		pairing_note.text = "Pick your PC or type its address, and the six-digit code from its Settings tab."
		return
	pairing_note.text = "Connecting..."
	_connect()


## Done on the keyboard connects, as the button does.
func _on_code_submitted(_text: String) -> void:
	_on_connect_pressed()


func _show_pairing(note: String) -> void:
	pairing.visible = true
	pairing_note.text = note


func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("pc", "address", _host)
	config.set_value("pc", "code", _code)
	config.set_value("sound", "muted", _muted)
	config.save(SETTINGS_PATH)


func _give_up_on_audio(turn: int) -> void:
	if turn == _turn and owes_audio(_next_audio, _last_sentence) and not player.playing:
		_next_audio = _last_sentence + 1
		_audio.clear()
		_after_speaking()


## Whether sentences up to `last` are still to be heard, the next being `next_index`.
static func owes_audio(next_index: int, last: int) -> bool:
	return next_index <= last


## How hard a jolt of `jolt` m/sÂ² stirs the bath: a shake just past the threshold a little, a hard
## one fully.
static func stir_for(jolt: float, threshold: float) -> float:
	return clampf((jolt - threshold) / 6.0 + 0.3, 0.3, 1.0)


## The stir after `delta` seconds of settling, halving every `half_life`.
static func settled_stir(stir: float, delta: float, half_life: float) -> float:
	return stir * pow(0.5, delta / maxf(half_life, 0.01))


## The stream to play next: the one at `index`, or null while it has not arrived.
static func next_audio(queue: Dictionary, index: int) -> AudioStreamWAV:
	var stream: Variant = queue.get(index)
	return stream if stream is AudioStreamWAV else null
