class_name ModelPreferences
extends Resource
## Which Foundry Local models the duck prefers, best first, and how much memory they may use.
##
## At startup the brain reads Foundry Local's catalog (`foundry model list -o json`), which names, for
## this machine, the build each model would run (NPU, GPU or CPU) and its size. Each list is tried in
## order. An entry with a `*` is a family: the largest member that fits the memory budget wins, so a
## new family written at the top of a list is taken up as soon as Foundry publishes it, and a bigger
## machine gets a bigger model. An entry without one is a single model, taken as written. Entries
## match a model alias (`qwen2.5-coder-7b`, using the build Foundry picks for this machine) or a
## build id (`openai-whisper-small-generic-cpu`, to insist on that one build).

## Chat models for the conversation. Reasoning models are left out: they think aloud before
## answering, which reads badly when spoken.
@export var chat: PackedStringArray = ["qwen3-coder-*", "qwen2.5-coder-*", "phi-4-mini", "qwen2.5-*"]
## Speech models when the system language is English.
@export var speech_english: PackedStringArray = ["parakeet-tdt-*"]
## Speech models for any language, also the fallback for English. Foundry's CUDA Whisper builds
## return garbled text (CLI 0.10.3), so these name the CPU builds, smallest last.
@export var speech_any_language: PackedStringArray = ["openai-whisper-small-generic-cpu", "openai-whisper-base-generic-cpu", "openai-whisper-tiny-generic-cpu"]
## The share of the device's memory the duck's models may take together, leaving room for
## everything else (the desktop, the editor, the duck's own window).
@export_range(0.1, 1.0) var memory_share: float = 0.7
## Memory a model takes running, as a multiple of its download size (weights plus working memory).
@export var overhead: float = 1.2

const CHAT_TYPES: PackedStringArray = ["Chat", "Multimodal"]
const SPEECH_TYPES: PackedStringArray = ["Speech"]


## The best catalog entry for `entries` of one of `types`, or {} when none fits. `budgets` gives the
## megabytes free on each device kind ("gpu", "npu", "cpu"); each model is judged against the
## device its build runs on. `models` is this machine's catalog (one build per alias); `variants`
## is every build.
static func pick(entries: PackedStringArray, models: Array, variants: Array, types: PackedStringArray, budgets: Dictionary, overhead_factor: float) -> Dictionary:
	for entry: String in entries:
		var found: Array[Dictionary] = matches(entry, models, variants, types)
		var fitting: Array[Dictionary] = found.filter(func(m: Dictionary) -> bool: return needs_mb(m, overhead_factor) <= budget_for(m, budgets))
		if fitting.is_empty():
			continue
		if "*" not in entry:
			return fitting[0]
		fitting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("fileSizeMb", 0)) > float(b.get("fileSizeMb", 0)))
		return fitting[0]
	return {}


## Catalog entries that `entry` names: aliases first, then build ids. Each comes back with the
## name to give the CLI under "name".
static func matches(entry: String, models: Array, variants: Array, types: PackedStringArray) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for model: Variant in models:
		if model is Dictionary and String(model.get("type", "")) in types and String(model.get("alias", "")).matchn(entry):
			var copy: Dictionary = model.duplicate()
			copy["name"] = model["alias"]
			found.append(copy)
	if not found.is_empty():
		return found
	for variant: Variant in variants:
		if variant is Dictionary and String(variant.get("type", "")) in types and String(variant.get("variantName", "")).matchn(entry):
			var copy: Dictionary = variant.duplicate()
			copy["name"] = variant["variantName"]
			found.append(copy)
	return found


## The budget for the device `model` runs on; an unknown device counts as the CPU.
static func budget_for(model: Dictionary, budgets: Dictionary) -> float:
	return float(budgets.get(String(model.get("device", "cpu")).to_lower(), budgets.get("cpu", 0.0)))


static func needs_mb(model: Dictionary, overhead_factor: float) -> float:
	return float(model.get("fileSizeMb", 0)) * overhead_factor


## The catalog's own list from `foundry model list -o json` or `--variants -o json`.
static func parse_catalog(json: String, key: String) -> Array:
	var parsed: JSON = JSON.new()
	if parsed.parse(json) != OK or not parsed.data is Dictionary:
		return []
	var list: Variant = parsed.data.get(key, [])
	return list if list is Array else []
