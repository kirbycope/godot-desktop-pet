extends SceneTree
## A phone on the command line: pairs with a duck, says a line, and prints what comes back with its
## timings, saving the spoken sentences as WAVs in user://remote_client/. With no DUCK_HOST it runs a
## duck in this same process (a scratch mind folder, the real brain), so the PC side can be checked
## end to end before any phone exists.
##
##   godot --headless --path . -s res://tools/remote_client.gd
##   DUCK_LINE="why does this crash?"  DUCK_HOST=192.168.4.63  DUCK_CODE=123456
##   DUCK_WAV=C:/path/to/speech.wav sends a recording instead of a line, as the phone's mic does

const OUT: String = "user://remote_client"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host: String = OS.get_environment("DUCK_HOST")
	var code: String = OS.get_environment("DUCK_CODE")
	var line: String = OS.get_environment("DUCK_LINE") if not OS.get_environment("DUCK_LINE").is_empty() else "hi! what are you up to?"
	var port: int = 39842
	if host.is_empty():
		var pet: Node = load("res://scenes/pet.tscn").instantiate()
		(pet.get_node("Mind") as Mind).root = "user://remote_client_mind"
		var remote: Remote = pet.get_node("Remote")
		remote.enabled = false
		remote.settings_path = "user://remote_client.cfg"
		root.add_child(pet)
		port = 39890
		print("local duck: ", error_string(remote.start(port)))
		code = remote.code()
		host = "127.0.0.1"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var client: WebSocketPeer = WebSocketPeer.new()
	client.inbound_buffer_size = Remote.BUFFER_BYTES
	client.outbound_buffer_size = Remote.BUFFER_BYTES
	client.connect_to_url("ws://%s:%d" % [host, port])
	var started: int = Time.get_ticks_msec()
	var sent_at: int = -1
	var paired: bool = false
	var audio: int = 0
	while Time.get_ticks_msec() - started < 180000:
		await process_frame
		client.poll()
		var opened: bool = client.get_ready_state() == WebSocketPeer.STATE_OPEN
		if opened and not paired:
			client.send_text(JSON.stringify({"hello": code, "name": "remote_client"}))
			paired = true
		while client.get_available_packet_count() > 0:
			var packet: PackedByteArray = client.get_packet()
			var at: String = "%6d ms" % (Time.get_ticks_msec() - sent_at) if sent_at >= 0 else "  waiting"
			if not client.was_string_packet():
				var frame: Dictionary = Remote.read_audio_frame(packet)
				audio += 1
				var path: String = OUT.path_join("sentence_%d.wav" % frame["index"])
				var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
				file.store_buffer(frame["wav"])
				file.close()
				print("%s  AUDIO %d, %d kB -> %s" % [at, frame["index"], frame["wav"].size() / 1024, ProjectSettings.globalize_path(path)])
				continue
			var frame: Dictionary = Remote.parse_frame(packet.get_string_from_utf8())
			print("%s  %s" % [at, JSON.stringify(frame).left(220)])
			if frame.get("ready", false) and sent_at < 0:
				# DUCK_WAV sends a recording instead, as the phone's mic does.
				var wav_path: String = OS.get_environment("DUCK_WAV")
				if wav_path.is_empty():
					client.send_text(JSON.stringify({"say": line}))
				else:
					client.send(Remote.audio_frame(Remote.AUDIO_IN, 0, FileAccess.get_file_as_bytes(wav_path)), WebSocketPeer.WRITE_MODE_BINARY)
				sent_at = Time.get_ticks_msec()
			if frame.has("replied"):
				# Kokoro may still be rendering the last sentences.
				var waited: int = Time.get_ticks_msec()
				while Time.get_ticks_msec() - waited < 8000:
					await process_frame
					client.poll()
					while client.get_available_packet_count() > 0:
						var late: Dictionary = Remote.read_audio_frame(client.get_packet())
						if not late.is_empty():
							audio += 1
							print("%6d ms  AUDIO %d, %d kB (after the text)" % [Time.get_ticks_msec() - sent_at, late["index"], late["wav"].size() / 1024])
				print("DONE: %d audio frames" % audio)
				client.close()
				quit()
				return
	print("TIMED OUT")
	quit(1)
