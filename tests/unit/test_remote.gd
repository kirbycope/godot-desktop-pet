extends GutTest
## The phone's link to the duck: frames, pairing, the beacon, and a real WebSocket over loopback.

const SETTINGS: String = "user://test_remote.cfg"

var remote: Remote


func before_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	remote = Remote.new()
	remote.enabled = false
	remote.settings_path = SETTINGS
	var clock: Timer = Timer.new()
	clock.name = "BeaconClock"
	remote.add_child(clock)
	add_child_autofree(remote)


func after_all() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


## Polls the client until it is open, or gives up after about two seconds.
func _open(client: WebSocketPeer) -> bool:
	for i: int in 120:
		client.poll()
		if client.get_ready_state() == WebSocketPeer.STATE_OPEN:
			return true
		await get_tree().process_frame
	return false


## The next `count` frames the client receives, text as dictionaries, binary as {"bytes": ...}.
func _read(client: WebSocketPeer, count: int) -> Array:
	var frames: Array = []
	for i: int in 240:
		client.poll()
		while client.get_available_packet_count() > 0:
			var packet: PackedByteArray = client.get_packet()
			frames.append(Remote.parse_frame(packet.get_string_from_utf8()) if client.was_string_packet() else {"bytes": packet})
		if frames.size() >= count:
			break
		await get_tree().process_frame
	return frames


func _connect() -> WebSocketPeer:
	var client: WebSocketPeer = WebSocketPeer.new()
	client.inbound_buffer_size = Remote.BUFFER_BYTES
	client.connect_to_url("ws://127.0.0.1:%d" % remote.port)
	return client


func test_frames_are_json_and_audio_is_kind_index_wav() -> void:
	assert_eq(Remote.parse_frame('{"say": "hi"}'), {"say": "hi"})
	assert_eq(Remote.parse_frame("not json"), {})
	assert_eq(Remote.parse_frame("[1, 2]"), {}, "an object or nothing")
	var wav: PackedByteArray = PackedByteArray([82, 73, 70, 70, 1, 2, 3])
	var frame: PackedByteArray = Remote.audio_frame(Remote.AUDIO_OUT, 7, wav)
	assert_eq(frame.size(), 5 + wav.size())
	assert_eq(Remote.read_audio_frame(frame), {"kind": Remote.AUDIO_OUT, "index": 7, "wav": wav})
	assert_eq(Remote.read_audio_frame(PackedByteArray([1, 2])), {}, "too short")


func test_the_beacon_names_the_port_and_the_duck() -> void:
	assert_eq(Remote.beacon_line(39842, "Ducky"), "duck 39842 Ducky")
	assert_eq(Remote.parse_beacon("duck 39842 Ducky the Great"), {"port": 39842, "name": "Ducky the Great"})
	assert_eq(Remote.parse_beacon("duck 39842"), {"port": 39842, "name": ""})
	assert_eq(Remote.parse_beacon("hello there"), {})


func test_the_code_is_six_digits_and_kept() -> void:
	var code: String = remote.code()
	assert_eq(code.length(), 6)
	assert_true(code.is_valid_int())
	assert_eq(remote.code(), code, "the same next time")
	assert_eq(Remote.make_code().length(), 6)


func test_only_home_network_addresses_are_offered() -> void:
	assert_eq(Remote.private_addresses(PackedStringArray(["127.0.0.1", "192.168.4.63", "fe80::1", "10.0.0.5", "172.20.1.2", "172.40.1.2", "8.8.8.8"])), PackedStringArray(["192.168.4.63", "10.0.0.5", "172.20.1.2"]))


func test_a_phone_with_the_code_pairs_and_hears_the_answer() -> void:
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client), "connected")
	client.send_text(JSON.stringify({"hello": remote.code(), "name": "Pixel"}))
	var welcome: Array = await _read(client, 1)
	assert_true(welcome[0].has("welcome"), "welcomed")
	assert_eq(remote.phone(), "Pixel")
	client.send_text(JSON.stringify({"ping": 5}))
	assert_eq((await _read(client, 1))[0], {"pong": 5.0})
	# A turn as the scene's signals would drive it.
	remote._on_pet_turn_started("why does this crash?")
	remote._on_brain_sentence("The sprite is null.")
	remote._on_kokoro_rendered(1, PackedByteArray([82, 73, 70, 70]))
	remote._on_pet_answered("The sprite is null.", "")
	var frames: Array = await _read(client, 4)
	assert_eq(frames[0], {"you": "why does this crash?"})
	assert_eq(frames[1], {"sentence": "The sprite is null.", "index": 1.0})
	assert_eq(Remote.read_audio_frame(frames[2]["bytes"])["index"], 1, "its audio, by index")
	assert_eq(frames[3], {"replied": "The sprite is null.", "notes": ""})
	client.close()


func test_a_wrong_code_is_turned_away_and_hears_nothing() -> void:
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client))
	client.send_text(JSON.stringify({"hello": "000000" if remote.code() != "000000" else "111111"}))
	var frames: Array = await _read(client, 1)
	assert_eq(frames[0], {"bye": "wrong code"})
	remote._on_brain_sentence("A secret.")
	assert_eq(remote.phone(), "", "not paired")


func test_with_no_pet_a_line_is_answered_busy() -> void:
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client))
	client.send_text(JSON.stringify({"hello": remote.code()}))
	await _read(client, 1)
	client.send_text(JSON.stringify({"say": "hello"}))
	assert_eq((await _read(client, 1))[0].get("busy"), true)
	client.close()


func test_the_pet_scene_wires_the_remote() -> void:
	var state: SceneState = (load("res://scenes/pet.tscn") as PackedScene).get_state()
	var wired: PackedStringArray = PackedStringArray()
	for i: int in state.get_connection_count():
		if str(state.get_connection_target(i)) == "Remote":
			wired.append(state.get_connection_method(i))
	for method: String in ["_on_beacon_clock_timeout", "_on_brain_sentence", "_on_brain_status_changed", "_on_pet_turn_started", "_on_pet_answered", "_on_kokoro_rendered", "_on_listener_heard_from_phone"]:
		assert_has(wired, method)
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var linked: Remote = pet.get_node("Remote")
	assert_not_null(linked.brain)
	assert_not_null(linked.label)
	pet.free()


func test_the_phone_starts_lists_and_opens_conversations() -> void:
	var mind: Mind = load("res://scripts/mind.gd").new()
	mind.root = "user://test_remote_mind"
	add_child_autofree(mind)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("user://test_remote_mind/conversations")):
		for file: String in DirAccess.get_files_at("user://test_remote_mind/conversations"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_remote_mind/conversations".path_join(file)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_remote_mind/current.txt"))
	mind.record("user", "Do you have any grapes?")
	# Out of the tree, so it does not start Foundry: starting and opening conversations need none.
	var brain: Brain = autofree(Brain.new())
	brain.mind = mind
	brain.conversation_changed.connect(remote._on_brain_conversation_changed)
	remote.mind = mind
	remote.brain = brain
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client))
	client.send_text(JSON.stringify({"hello": remote.code()}))
	var welcome: Dictionary = (await _read(client, 1))[0]
	var first: String = welcome["conversation"]
	client.send_text(JSON.stringify({"new": true}))
	var changed: Dictionary = (await _read(client, 1))[0]
	assert_ne(changed["conversation"], first, "a new one")
	assert_eq(changed["messages"], [], "empty")
	client.send_text(JSON.stringify({"list": true}))
	var listed: Dictionary = (await _read(client, 1))[0]
	assert_eq(listed["conversations"][0]["title"], "Do you have any grapes?", "the new one has no file until something is said")
	client.send_text(JSON.stringify({"open": first}))
	var reopened: Dictionary = (await _read(client, 1))[0]
	assert_eq(reopened["conversation"], first)
	assert_eq(reopened["messages"][0]["content"], "Do you have any grapes?")
	client.close()


func test_a_muted_phone_gets_no_audio_and_none_is_made_for_it() -> void:
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client))
	client.send_text(JSON.stringify({"hello": remote.code()}))
	await _read(client, 1)
	assert_true(remote.listening(), "sound on")
	client.send_text(JSON.stringify({"mute": true}))
	for i: int in 10:
		await get_tree().process_frame
	assert_false(remote.listening(), "muted: Kokoro is not asked")
	remote._on_kokoro_rendered(1, PackedByteArray([82, 73, 70, 70]))
	remote._on_pet_answered("Quack.", "")
	var frames: Array = await _read(client, 1)
	assert_eq(frames[0], {"replied": "Quack.", "notes": ""}, "the text still comes, the audio does not")
	client.close()


func test_the_phone_hears_when_the_hat_changes() -> void:
	assert_eq(remote.start(39900 + randi() % 80), OK)
	var client: WebSocketPeer = _connect()
	assert_true(await _open(client))
	client.send_text(JSON.stringify({"hello": remote.code()}))
	var welcome: Dictionary = (await _read(client, 1))[0]
	assert_eq(welcome["hat"], false, "with no pet, no hat")
	remote._on_pet_hat_changed(true)
	assert_eq((await _read(client, 1))[0], {"hat": true})
	client.close()
