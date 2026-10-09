@tool
class_name KeptModel
extends RefCounted
## The chat model a duck run from the editor leaves loaded, written to a file so the editor can
## unload it as it closes (addons/kept_model). The duck cannot do that itself: the editor's Stop
## button kills it outright, before its _exit_tree runs.

const PATH: String = "user://kept_model.cfg"


## Notes that `model_name` is being kept loaded: on llama-server at `llama_port`, or on Foundry
## Local through the CLI at `foundry` when the port is 0.
static func remember(path: String, foundry: String, model_name: String, llama_port: int) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("model", "foundry", foundry)
	config.set_value("model", "name", model_name)
	config.set_value("model", "llama_port", llama_port)
	config.save(path)


## {foundry, name, llama_port}, or {} when nothing is kept.
static func read(path: String) -> Dictionary:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK or String(config.get_value("model", "name", "")).is_empty():
		return {}
	return {
		"foundry": String(config.get_value("model", "foundry", "foundry")),
		"name": String(config.get_value("model", "name", "")),
		"llama_port": int(config.get_value("model", "llama_port", 0)),
	}


static func forget(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Frees the model the file names, if any, and forgets it. True when there was one.
static func release(path: String) -> bool:
	var kept: Dictionary = read(path)
	forget(path)
	if kept.is_empty():
		return false
	for command: PackedStringArray in free_commands(kept["foundry"], kept["llama_port"]):
		OS.create_process(command[0], command.slice(1))
	return true


## The commands that free everything the duck runs, programs first: the llama-server on
## `llama_port` (when above 0), then Foundry Local's server, which unloads what it holds as it stops.
## The duck starts that server with no idle timeout, so left alone it would run for good.
static func free_commands(foundry: String, llama_port: int) -> Array[PackedStringArray]:
	var commands: Array[PackedStringArray] = []
	if llama_port > 0:
		commands.append(stop_llama_command(llama_port))
	commands.append(PackedStringArray([foundry, "server", "stop"]))
	return commands


## Stops whichever llama-server listens on `llama_port`.
static func stop_llama_command(llama_port: int) -> PackedStringArray:
	return PackedStringArray(["/usr/bin/pkill", "-f", "llama-server.*--port %d" % llama_port])
