extends GutTest

const PATH: String = "user://test_kept_model.cfg"


func after_each() -> void:
	KeptModel.forget(PATH)


func test_a_kept_model_is_remembered_and_forgotten() -> void:
	KeptModel.remember(PATH, "C:/foundry.exe", "qwen2.5-7b", 0)
	assert_eq(KeptModel.read(PATH), {"foundry": "C:/foundry.exe", "name": "qwen2.5-7b", "llama_port": 0})
	KeptModel.forget(PATH)
	assert_eq(KeptModel.read(PATH), {}, "nothing kept")


func test_foundrys_server_is_stopped_and_llama_server_too_by_port() -> void:
	assert_eq(KeptModel.free_commands("foundry", 0), [PackedStringArray(["foundry", "server", "stop"])] as Array[PackedStringArray], "stopping the server unloads its models")
	assert_eq(KeptModel.free_commands("foundry", 39841), [
		PackedStringArray(["/usr/bin/pkill", "-f", "llama-server.*--port 39841"]),
		PackedStringArray(["foundry", "server", "stop"]),
	] as Array[PackedStringArray], "on the Mac Foundry still runs the speech model")


func test_releasing_forgets_the_model_and_does_nothing_twice() -> void:
	# A harmless program in Foundry's place, so nothing real is unloaded.
	KeptModel.remember(PATH, "where" if OS.get_name() == "Windows" else "true", "qwen2.5-7b", 0)
	assert_true(KeptModel.release(PATH))
	assert_false(FileAccess.file_exists(PATH))
	assert_false(KeptModel.release(PATH), "already released")


func test_the_editor_plugin_compiles_and_is_enabled() -> void:
	# A preload or class it cannot find is a compile error, and load() comes back null.
	assert_not_null(load("res://addons/kept_model/plugin.gd"))
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_has(enabled, "res://addons/kept_model/plugin.cfg")
