extends SceneTree
## A duck for a phone or an emulator to talk to, headless, with a scratch mind folder so the real
## duck's conversation is left alone. Prints the pairing code. An Android emulator reaches this PC
## at 10.0.2.2. Stop it with Ctrl+C.
##
##   godot --headless --path . -s res://tools/remote_host.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var pet: Node = load("res://scenes/pet.tscn").instantiate()
	(pet.get_node("Mind") as Mind).root = "user://remote_host_mind"
	var remote: Remote = pet.get_node("Remote")
	remote.enabled = false
	remote.settings_path = "user://remote_host.cfg"
	root.add_child(pet)
	print("listening on %d: %s, code %s" % [remote.port, error_string(remote.start()), remote.code()])
	remote.phone_changed.connect(func(phone: String) -> void: print("phone: ", phone if not phone.is_empty() else "(left)"))
	pet.get_node("Brain").status_changed.connect(func(text: String) -> void: print("brain: ", text))
	pet.turn_started.connect(func(line: String) -> void: print("you: ", line))
	pet.answered.connect(func(text: String, _notes: String) -> void: print("duck: ", text))
