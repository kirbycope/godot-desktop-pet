class_name Remote
extends Node
## Lets the phone app talk to this duck over the home network. The phone is a remote control: the
## brain, the duck's memory and the screen reading all stay here, and a line from the phone is the
## same turn as one typed here. One WebSocket connection per phone, made with a TCPServer and
## WebSocketPeer.accept_stream; a beacon broadcast once a second lets the phone find this PC.
##
## The protocol, text frames as JSON:
##   phone: {"hello": code, "name": phone}      PC: {"welcome": duck name, "ready", "status", "speaks", "recent"}
##   phone: {"say": line}                        PC: {"you": line}, then {"sentence": text, "index": n}...
##                                               PC: {"replied": text, "notes": what it remembered}
##   PC: {"status": text, "ready": bool}         phone: {"ping": t}  PC: {"pong": t}
##   PC: {"busy": true} when a turn is already under way; {"bye": why} before closing
##   phone: {"new": true} starts a new conversation; {"list": true} asks for the past ones, answered
##   {"conversations": [{id, title, when, messages}], "current": id}; {"open": id} takes one up again.
##   PC: {"conversation": id, "messages": [...]} whenever the conversation under way changes
##   phone: {"mute": true|false}: muted, the PC makes no audio for it, which saves the synthesis time
##   phone: {"hat": true|false} puts the captain's hat on or off; PC: {"hat": bool} when it changes
##   phone: {"pomodoro": true|false} starts or stops the Pomodoro timer (its Timer button);
##   PC: {"tomato": bool} as the timer starts or stops, the duck a tomato while it runs
## Binary frames are audio: a kind byte, the sentence index as a little-endian uint32, then a WAV.
## The phone sends kind 1 (a sentence it heard, transcribed here); the PC sends kind 2 (a sentence
## spoken by Kokoro, for the phone to play).

## A phone paired or left; "" when none is connected.
signal phone_changed(phone_name: String)

const AUDIO_IN: int = 1
const AUDIO_OUT: int = 2
## A spoken sentence from the phone is at most 30 s of 16 kHz 16-bit mono, about 1 MB; answers
## come back as Kokoro WAVs of a few hundred kB each.
const BUFFER_BYTES: int = 4 << 20

## Listen for phones. The beacon and the server start with the duck, except in headless runs (tests,
## tools), which start them themselves.
@export var enabled: bool = true
@export var port: int = 39842
@export var beacon_port: int = 39843
## Also speak here what the phone says aloud; off, the duck here stays quiet on the phone's turns.
@export var speak_here_too: bool = false
@export var pet: Pet
@export var brain: Brain
@export var mind: Mind
@export var voice: Voice
@export var listener: Listener
## Where the pairing code and this PC's address are shown, on the Settings tab.
@export var label: Label
## Where the pairing code is kept, beside the chosen voice and microphone. Tests point it elsewhere.
@export var settings_path: String = "user://settings.cfg"

var _server: TCPServer = TCPServer.new()
## {peer: WebSocketPeer, paired: bool, name: String}
var _clients: Array[Dictionary] = []
var _beacon: PacketPeerUDP = null
## Whether the turn under way came from the phone, so its sentences are spoken for it.
var _phone_turn: bool = false
var _index: int = 0

@onready var beacon_clock: Timer = $BeaconClock


func _ready() -> void:
	if enabled and (DisplayServer.get_name() != "headless" or OS.get_environment("DUCK_REMOTE") == "1"):
		start()
	_show()


func _exit_tree() -> void:
	stop()


## Starts listening on `listen_port` (0 for `port`). Returns the error, OK when listening.
func start(listen_port: int = 0) -> Error:
	if listen_port > 0:
		port = listen_port
	var failed: Error = _server.listen(port, "*")
	if failed != OK:
		return failed
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", beacon_port)
	beacon_clock.start()
	set_process(true)
	return OK


func stop() -> void:
	for client: Dictionary in _clients:
		(client["peer"] as WebSocketPeer).close()
	_clients.clear()
	_server.stop()
	if _beacon != null:
		_beacon.close()
		_beacon = null
	if is_node_ready():
		beacon_clock.stop()


func is_listening() -> bool:
	return _server.is_listening()


## The name of the paired phone, or "".
func phone() -> String:
	for client: Dictionary in _clients:
		if client["paired"]:
			return client["name"]
	return ""


func _process(_delta: float) -> void:
	while _server.is_connection_available():
		var peer: WebSocketPeer = WebSocketPeer.new()
		peer.inbound_buffer_size = BUFFER_BYTES
		peer.outbound_buffer_size = BUFFER_BYTES
		peer.accept_stream(_server.take_connection())
		_clients.append({"peer": peer, "paired": false, "name": "", "muted": false})
	for client: Dictionary in _clients.duplicate():
		var peer: WebSocketPeer = client["peer"]
		peer.poll()
		if client.has("close_at") and Time.get_ticks_msec() >= int(client["close_at"]):
			client.erase("close_at")
			peer.close(4001, "wrong code")
		match peer.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				while peer.get_available_packet_count() > 0:
					var packet: PackedByteArray = peer.get_packet()
					if peer.was_string_packet():
						_on_text(client, parse_frame(packet.get_string_from_utf8()))
					else:
						_on_audio(client, read_audio_frame(packet))
			WebSocketPeer.STATE_CLOSED:
				_clients.erase(client)
				if client["paired"]:
					phone_changed.emit(phone())
					_show()


func _on_text(client: Dictionary, frame: Dictionary) -> void:
	if client.has("close_at"):
		return
	if frame.has("hello"):
		if str(frame["hello"]) != code():
			# Closed a moment later, so the phone reads why before the socket goes.
			_send_to(client, {"bye": "wrong code"})
			client["close_at"] = Time.get_ticks_msec() + 500
			return
		client["paired"] = true
		client["name"] = str(frame.get("name", "phone")).left(40)
		_send_to(client, welcome())
		phone_changed.emit(client["name"])
		_show()
		return
	if not client["paired"]:
		return
	if frame.has("ping"):
		_send_to(client, {"pong": frame["ping"]})
	elif frame.has("mute"):
		client["muted"] = bool(frame["mute"])
	elif frame.has("hat"):
		if pet != null:
			pet.set_hat(bool(frame["hat"]))
	elif frame.has("pomodoro"):
		# The phone's Timer button; every phone hears {"tomato": bool} as the timer starts or stops.
		if pet != null and pet.pomodoro != null:
			pet.pomodoro.carry_out({"action": "start" if bool(frame["pomodoro"]) else "stop"})
	elif frame.has("new"):
		if brain == null or not brain.new_conversation():
			_send_to(client, {"busy": true})
	elif frame.has("list"):
		_send_to(client, {"conversations": mind.conversations() if mind != null else [], "current": mind.conversation_id() if mind != null else ""})
	elif frame.has("open"):
		if brain == null or not brain.open_conversation(str(frame["open"])):
			_send_to(client, {"busy": true})
	elif frame.has("say"):
		_say(client, str(frame["say"]))


func _on_audio(client: Dictionary, frame: Dictionary) -> void:
	if not client["paired"] or frame.get("kind", 0) != AUDIO_IN:
		return
	if pet == null or not brain.is_ready() or pet.is_thinking():
		_send_to(client, {"busy": true})
		return
	listener.foundry_path = brain.foundry_path()
	listener.model_alias = brain.speech_name
	if not listener.transcribe_wav(frame["wav"]):
		_send_to(client, {"busy": true})


func _on_listener_heard_from_phone(text: String) -> void:
	if text.is_empty():
		_broadcast({"you": "", "error": listener.last_error if not listener.last_error.is_empty() else "I didn't catch that."})
		return
	_say({}, text)


## A line from the phone becomes a turn here; the answer goes to every paired phone.
func _say(client: Dictionary, line: String) -> void:
	_phone_turn = true
	if pet == null or not pet.send_remote(line, not speak_here_too):
		_phone_turn = false
		var busy: Dictionary = {"busy": true, "status": brain.status if brain != null else ""}
		if client.is_empty():
			_broadcast(busy)
		else:
			_send_to(client, busy)


func _on_pet_turn_started(line: String) -> void:
	_index = 0
	_broadcast({"you": line})


func _on_brain_sentence(text: String) -> void:
	_index += 1
	_broadcast({"sentence": text, "index": _index})
	if _phone_turn and speaks() and listening():
		voice.kokoro.render(text, Kokoro.sid_of(voice.voice_id), _index)


## Sent even when synthesis failed, with no WAV, so the phone knows not to wait for that sentence.
func _on_kokoro_rendered(index: int, wav: PackedByteArray) -> void:
	_broadcast_bytes(audio_frame(AUDIO_OUT, index, wav))


func _on_pet_answered(text: String, notes: String) -> void:
	_phone_turn = false
	_broadcast({"replied": text, "notes": notes})


func _on_brain_conversation_changed(id: String) -> void:
	_broadcast({"conversation": id, "messages": shown(mind.conversation(id))})


func _on_pet_hat_changed(on: bool) -> void:
	_broadcast({"hat": on})


func _on_pomodoro_phase_changed(phase: Pomodoro.Phase) -> void:
	_broadcast({"tomato": phase != Pomodoro.Phase.OFF})


func _on_brain_status_changed(text: String) -> void:
	_broadcast({"status": text, "ready": brain.is_ready()})


func _on_beacon_clock_timeout() -> void:
	if _beacon != null:
		_beacon.put_packet(beacon_line(port, mind.duck_name() if mind != null else "").to_utf8_buffer())


## Whether answers are spoken here for the phone: only with a Kokoro voice. With a system voice the
## phone speaks with its own.
func speaks() -> bool:
	return voice != null and Kokoro.sid_of(voice.voice_id) >= 0 and voice.kokoro_ready()


func welcome() -> Dictionary:
	var recent: Array = []
	if mind != null:
		for message: Dictionary in mind.recent(6):
			recent.append({"role": message.get("role", ""), "content": message.get("content", "")})
	return {
		"welcome": mind.duck_name() if mind != null else "",
		"conversation": mind.conversation_id() if mind != null else "",
		"hat": pet != null and pet.duck != null and pet.duck.hat,
		"tomato": pet != null and pet.duck != null and pet.duck.tomato,
		"ready": brain != null and brain.is_ready(),
		"status": brain.status if brain != null else "",
		"speaks": speaks(),
		"recent": recent,
	}


func _send_to(client: Dictionary, frame: Dictionary) -> void:
	var peer: WebSocketPeer = client.get("peer")
	if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(frame))


func _broadcast(frame: Dictionary) -> void:
	for client: Dictionary in _clients:
		if client["paired"]:
			_send_to(client, frame)


## Whether a paired phone has its sound on: with every one muted, no audio is made at all.
func listening() -> bool:
	return _clients.any(func(client: Dictionary) -> bool: return client["paired"] and not client["muted"])


func _broadcast_bytes(bytes: PackedByteArray) -> void:
	for client: Dictionary in _clients:
		var peer: WebSocketPeer = client["peer"]
		if client["paired"] and not client["muted"] and peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send(bytes, WebSocketPeer.WRITE_MODE_BINARY)


## The pairing code, made once and kept in settings.cfg.
func code() -> String:
	var config: ConfigFile = ConfigFile.new()
	config.load(settings_path)
	var kept: String = str(config.get_value("remote", "code", ""))
	if kept.length() == 6 and kept.is_valid_int():
		return kept
	kept = make_code()
	config.set_value("remote", "code", kept)
	config.save(settings_path)
	return kept


func _show() -> void:
	if label == null:
		return
	if not is_listening():
		label.text = "Phone: off"
		return
	var addresses: PackedStringArray = private_addresses(IP.get_local_addresses())
	var connected: String = phone()
	label.text = "Phone: code %s  %s:%d  %s" % [code(), addresses[0] if not addresses.is_empty() else "?", port, connected if not connected.is_empty() else "(none)"]
	label.tooltip_text = "Pair the phone app with code %s. This PC: %s, port %d." % [code(), ", ".join(addresses), port]


## The last messages of a conversation, as the phone shows them: enough to read back, not a whole
## day of talk in one frame.
static func shown(said: Array[Dictionary]) -> Array:
	var kept: Array = []
	for message: Dictionary in said.slice(maxi(0, said.size() - 40)):
		kept.append({"role": message.get("role", ""), "content": message.get("content", "")})
	return kept


static func make_code() -> String:
	return "%06d" % (randi() % 1000000)


static func parse_frame(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	return json.data if json.parse(text) == OK and json.data is Dictionary else {}


## kind, then the index as a little-endian uint32, then the WAV.
static func audio_frame(kind: int, index: int, wav: PackedByteArray) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray([kind, 0, 0, 0, 0])
	bytes.encode_u32(1, index)
	bytes.append_array(wav)
	return bytes


## {kind, index, wav}, or {} when it is too short to be one.
static func read_audio_frame(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 5:
		return {}
	return {"kind": bytes[0], "index": bytes.decode_u32(1), "wav": bytes.slice(5)}


static func beacon_line(listen_port: int, duck_name: String) -> String:
	return "duck %d %s" % [listen_port, duck_name]


## {port, name} from a beacon, or {} when it is not one.
static func parse_beacon(text: String) -> Dictionary:
	var parts: PackedStringArray = text.split(" ", true, 2)
	if parts.size() < 2 or parts[0] != "duck" or not parts[1].is_valid_int():
		return {}
	return {"port": int(parts[1]), "name": parts[2] if parts.size() > 2 else ""}


## The private IPv4 addresses among `addresses`: the ones a phone on the same network can reach.
static func private_addresses(addresses: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var private: RegEx = RegEx.create_from_string(r"^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)\d+\.\d+")
	for address: String in addresses:
		if private.search(address) != null:
			found.append(address)
	return found
