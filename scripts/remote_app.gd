class_name RemoteApp
extends Control
## The duck on your phone: a remote control for the duck on your PC. The duck sits on the top half,
## the chat on the bottom half. What you type or say goes to the PC, which answers as it would
## there, screen reading and all; its sentences come back as text and, with a Kokoro voice chosen
## on the PC, as audio. The phone finds the PC by its beacon (see remote.gd) or by an address typed
## in, and pairs with the code shown on the PC's Settings tab.

const SETTINGS_PATH: String = "user://remote.cfg"
## Missed pongs before the PC counts as lost.
const MAX_MISSED: int = 3

@export var port: int = 39842
@export var beacon_port: int = 39843
## The bubbles: yours on the right, the duck's on the left, as in a messaging app.
@export var your_bubble: StyleBox
@export var duck_bubble: StyleBox
## A jolt of the phone stronger than this, in m/s² beyond its steady pull, stirs the bath.
@export var shake_threshold: float = 2.5
## How long the bath takes to settle by half after a stir, in seconds.
@export var settle_half_life: float = 0.8
## The swell when calm; a stir raises it up to `stir_swell` times.
@export var calm_swell: float = 0.004
@export var stir_swell: float = 6.0
## A bubble is at most this share of the chat's width, and as narrow as its text otherwise.
@export_range(0.3, 1.0) var bubble_share: float = 0.78
## Picked up, dropped and thrown, as on the PC: metres a second squared pulling it back to the water,
## the fastest it can be thrown in metres a second, how far from its middle a press still picks it
## up (metres), and how far a finger moves (pixels) before a press is a pick-up rather than a tap.
@export var toss_gravity: float = 5.0
@export var max_toss_speed: float = 6.0
@export var grab_radius: float = 0.17
@export var drag_slop: float = 12.0

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
## The duck's bubble for the answer coming in, and whether a sentence has reached it yet.
var _answer: Label = null
var _answer_started: bool = false
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
@onready var conversation: ScrollContainer = $Layout/Chat/Margin/Column/Conversation
@onready var messages_box: VBoxContainer = $Layout/Chat/Margin/Column/Conversation/Messages
@onready var input: LineEdit = $Layout/Chat/Margin/Column/Entry/Input
@onready var mic_button: Button = $Layout/Chat/Margin/Column/Entry/Mic
@onready var mic_dot: Control = $Layout/Chat/Margin/Column/Entry/Mic/Dot
@onready var send_button: Button = $Layout/Chat/Margin/Column/Entry/Send
@onready var new_button: Button = $Layout/Chat/Margin/Column/Header/New
@onready var mute_button: Button = $Layout/Chat/Margin/Column/Header/Mute
@onready var hat_button: Button = $Layout/Chat/Margin/Column/Header/Hat
@onready var timer_button: Button = $Layout/Chat/Margin/Column/Header/Timer
@onready var past_button: Button = $Layout/Chat/Margin/Column/Header/Past
@onready var history: Control = $History
@onready var history_list: ItemList = $History/Margin/Column/List
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
	mute_button.set_pressed_no_signal(_muted)
	mute_button.text = "Unmute" if _muted else "Mute"
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
		_client.send_text(JSON.stringify({"mute": _muted}))
		title.text = str(frame["welcome"]) if not str(frame["welcome"]).is_empty() else "Rubber Duck"
		_speaks = frame.get("speaks", false)
		_show_conversation(frame.get("recent", []))
		_show_hat(bool(frame.get("hat", false)))
		_show_tomato(bool(frame.get("tomato", false)))
		_set_awake(frame.get("ready", false), str(frame.get("status", "")))
	elif frame.has("hat") and frame.size() == 1:
		_show_hat(bool(frame["hat"]))
	elif frame.has("tomato") and frame.size() == 1:
		# A tomato while the Pomodoro timer runs on the PC.
		_show_tomato(bool(frame["tomato"]))
	elif frame.has("conversations"):
		history_list.clear()
		for found_one: Variant in frame["conversations"]:
			if found_one is Dictionary:
				history_list.add_item(history_line(found_one, str(frame.get("current", ""))))
				history_list.set_item_metadata(history_list.item_count - 1, str(found_one.get("id", "")))
		if history_list.item_count == 0:
			history_list.add_item("Nothing yet: what you say starts the first one.")
			history_list.set_item_disabled(0, true)
		history.visible = true
	elif frame.has("conversation"):
		history.visible = false
		player.stop()
		_audio.clear()
		_show_conversation(frame.get("messages", []))
		_set_status("New conversation" if (frame.get("messages", []) as Array).is_empty() else "")
	elif frame.has("bye"):
		_paired = false
		_show_pairing("The PC said: %s. Check the code on its Settings tab." % frame["bye"])
	elif frame.has("pong"):
		_missed = 0
	elif frame.has("status"):
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
			_add_message("user", str(frame["you"]))
			# The duck's bubble now, "..." until its first sentence; the rest join it as they come.
			_answer = _add_message("assistant", "...")
			_answer_started = false
			duck.play(&"think")
			_set_status("Thinking...")
	elif frame.has("sentence"):
		_last_sentence = maxi(_last_sentence, int(frame.get("index", 0)))
		if _answer != null:
			_answer.text = str(frame["sentence"]) if not _answer_started else _answer.text + " " + str(frame["sentence"])
			_answer_started = true
			_fit(_answer)
			_scroll_down()
		if not _speaks and not _muted:
			_utterance += 1
			DisplayServer.tts_speak(str(frame["sentence"]), Voice.default_voice(DisplayServer.tts_get_voices(), OS.get_locale_language()), 70, 1.0, 1.0, _utterance, false)
			duck.play(&"talk")
	elif frame.has("replied"):
		_waiting = false
		if not str(frame.get("notes", "")).is_empty():
			_add_note(str(frame["notes"]))
		if _answer != null and not _answer_started:
			_answer.text = str(frame["replied"])
			_fit(_answer)
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
	if mic_button.button_pressed:
		listener.resume()


func _set_awake(awake: bool, text: String) -> void:
	if awake and not _awake:
		duck.play(&"wake")
	elif not awake:
		duck.play(&"sleep")
	_awake = awake
	_set_status("" if awake else text)
	input.editable = awake
	send_button.disabled = not awake
	mic_button.disabled = not awake
	new_button.disabled = not awake
	past_button.disabled = not awake


func _set_status(text: String) -> void:
	status.text = text


## A message in its bubble, on your side or the duck's; returns its label, for the answer to grow.
func _add_message(role: String, text: String) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	var bubble: PanelContainer = PanelContainer.new()
	var label: Label = Label.new()
	var yours: bool = role == "user"
	bubble.add_theme_stylebox_override("panel", your_bubble if yours else duck_bubble)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color.WHITE if yours else Color(0.12, 0.13, 0.17))
	bubble.add_child(label)
	row.alignment = BoxContainer.ALIGNMENT_END if yours else BoxContainer.ALIGNMENT_BEGIN
	row.add_child(bubble)
	messages_box.add_child(row)
	_fit(label)
	_scroll_down()
	return label


## What the duck remembered on the way: small and grey, in the middle.
func _add_note(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.45, 0.48, 0.55))
	messages_box.add_child(label)
	_scroll_down()


## A bubble as wide as its text, up to `bubble_share` of the chat.
func _fit(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var widest: float = 0.0
	for line: String in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var room: float = maxf(conversation.size.x, 300.0) * bubble_share - 44.0
	label.custom_minimum_size.x = bubble_width(widest, room)


func _scroll_down() -> void:
	await get_tree().process_frame
	if is_instance_valid(conversation):
		conversation.scroll_vertical = int(conversation.get_v_scroll_bar().max_value)


func _send(line: String) -> void:
	if line.strip_edges().is_empty() or _client == null or not _paired:
		return
	_client.send_text(JSON.stringify({"say": line.strip_edges()}))
	input.clear()


func _show_conversation(messages: Array) -> void:
	for child: Node in messages_box.get_children():
		child.queue_free()
	_answer = null
	for message: Variant in messages:
		if message is Dictionary:
			_add_message(str(message.get("role", "")), str(message.get("content", "")))


## Puts the captain's hat on or takes it off, here and on the PC duck.
func _on_hat_toggled(on: bool) -> void:
	duck.hat = on
	if _client != null and _paired:
		_client.send_text(JSON.stringify({"hat": on}))


## The hat as the PC has it, without sending it back.
func _show_hat(on: bool) -> void:
	duck.hat = on
	hat_button.set_pressed_no_signal(on)


## Starts or stops the Pomodoro timer on the PC. The duck here turns tomato, and the button stays
## down, once the PC says the timer runs; with no PC to ask, the button comes back up.
func _on_timer_toggled(on: bool) -> void:
	if _client != null and _paired:
		_client.send_text(JSON.stringify({"pomodoro": on}))
	else:
		timer_button.set_pressed_no_signal(false)


## The duck a tomato, and the Timer button down, while the PC's Pomodoro timer runs.
func _show_tomato(on: bool) -> void:
	duck.tomato = on
	timer_button.set_pressed_no_signal(on)


func _on_mute_toggled(on: bool) -> void:
	_muted = on
	mute_button.text = "Unmute" if on else "Mute"
	if on:
		player.stop()
		_audio.clear()
		DisplayServer.tts_stop()
	if _client != null and _paired:
		_client.send_text(JSON.stringify({"mute": on}))
	_save()
	_after_speaking()


func _on_new_pressed() -> void:
	if _client != null and _paired:
		_client.send_text(JSON.stringify({"new": true}))


func _on_past_pressed() -> void:
	if _client != null and _paired:
		_client.send_text(JSON.stringify({"list": true}))


func _on_history_item_selected(index: int) -> void:
	var id: String = str(history_list.get_item_metadata(index))
	if not id.is_empty() and _client != null:
		_client.send_text(JSON.stringify({"open": id}))


func _on_history_close_pressed() -> void:
	history.visible = false


func _on_send_pressed() -> void:
	_send(input.text)


func _on_input_text_submitted(text: String) -> void:
	_send(text)


func _on_mic_toggled(on: bool) -> void:
	mic_dot.visible = on
	if on:
		listener.start()
		if listener.mode == Listener.Mode.OFF:
			_set_status("The mic didn't open. Is the microphone allowed for this app?")
	elif not listener.finish():
		_set_status("")


## What the mic is doing, in the status line, so a mic that hears nothing is plain to see.
func _on_listener_mode_changed(mode: Listener.Mode) -> void:
	if not mic_button.button_pressed:
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
			hat_button.button_pressed = not hat_button.button_pressed
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


## How hard a jolt of `jolt` m/s² stirs the bath: a shake just past the threshold a little, a hard
## one fully.
static func stir_for(jolt: float, threshold: float) -> float:
	return clampf((jolt - threshold) / 6.0 + 0.3, 0.3, 1.0)


## The stir after `delta` seconds of settling, halving every `half_life`.
static func settled_stir(stir: float, delta: float, half_life: float) -> float:
	return stir * pow(0.5, delta / maxf(half_life, 0.01))


## A past conversation in the list: when it began and what you said first; the one under way marked.
static func history_line(found_one: Dictionary, current: String) -> String:
	var line: String = "%s   %s" % [found_one.get("when", ""), found_one.get("title", "")]
	return line + "   (now)" if str(found_one.get("id", "")) == current else line


## How wide a bubble's text is: as wide as the text, but no wider than `room`.
static func bubble_width(text_width: float, room: float) -> float:
	return minf(ceilf(text_width) + 2.0, room)


## The stream to play next: the one at `index`, or null while it has not arrived.
static func next_audio(queue: Dictionary, index: int) -> AudioStreamWAV:
	var stream: Variant = queue.get(index)
	return stream if stream is AudioStreamWAV else null
