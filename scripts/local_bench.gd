class_name LocalBench
extends Node
## Tries every way the duck can think on this phone, one after another, under the same conditions:
## for each of LocalBrain's SETUPS, the model before it is let go and every downloaded model is
## deleted, the phone gets a moment to settle, then the setup is downloaded, started and asked the
## same `prompts`. LocalBrain records each download, start and answer (LlmMetrics), tagged with
## this run; the Stats tab shows the summary. Its own Mind keeps the duck's real memories and
## conversations out of it.
##
## A run cut short (the app went to the background, or was reinstalled) is taken up again by the
## next run(): the setups it had not finished are tried under the same name, the one it was in the
## middle of from the start, and so are those that failed, in case what failed was put right. The
## metrics file says which: each setup tried ends with a "done" line, and the run with an "end" line.

## Where it has got, for the Stats tab and the status line.
signal progressed(text: String)
## A line asked, for the chat to show above the answer.
signal asked(line: String)
signal finished

@export var brain: LocalBrain
## A Mind of its own for the run, so the duck's memories and conversations are not touched.
@export var mind: Mind
## The first is the duck's first answer after it starts; the rest show it warmed up.
@export var prompts: PackedStringArray = PackedStringArray([
	"Hi duck, what do you like to do for fun?",
	"What's your favourite colour?",
	"My loop never ends. What should I check first?",
	"Tell me a short joke about ducks.",
])
## The setups to try, by id; empty tries every one of LocalBrain.SETUPS.
@export var setups: PackedStringArray = PackedStringArray()
## Seconds to settle after a model is let go and the models are deleted, before the next starts.
@export var settle_seconds: float = 10.0
## Where the models are deleted from between setups; empty is where LocalBrain downloads them.
## Tests point it elsewhere.
@export var model_folders: PackedStringArray = PackedStringArray()
## A phone warm from a download or the last model slows its own chips down, so before each setup
## starts, and again before its first line, the benchmark waits until Android's thermal state is
## at most `cool_thermal` (0 none, 1 light, 2 moderate...) and the battery no more than
## `cool_rise_c` warmer than when the benchmark began (a phone on its charger idles warm), for up to
## `cool_timeout` seconds. Off a phone there is nothing to wait for.
@export var cool_thermal: int = 0
@export var cool_rise_c: float = 1.0
@export var cool_timeout: float = 600.0
## Longest a setup may take to download and start, and an answer to come.
@export var start_timeout: float = 1800.0
@export var answer_timeout: float = 300.0

var running: bool = false
var _cancelled: bool = false
## The battery's temperature as the benchmark began, what the cool-downs wait to get back near.
var _start_battery_c: float = 0.0


## Runs the benchmark, or the rest of one cut short; finished comes at the end. Returns the run's
## name.
func run() -> String:
	running = true
	_cancelled = false
	var keep_setup: String = brain.setup_id
	var keep_mind: Mind = brain.mind
	brain.mind = mind
	var left: Dictionary = unfinished(LlmMetrics.read(brain.metrics_path)) if not brain.metrics_path.is_empty() else {}
	var run_name: String = left.get("run", Time.get_datetime_string_from_system().replace(":", "").replace("T", "-"))
	var ids: PackedStringArray = left.get("setups", setups if not setups.is_empty() else PackedStringArray(LocalBrain.SETUPS.map(func(s: Dictionary) -> String: return s["id"])))
	var total: int = left.get("total", ids.size())
	brain.run = run_name
	if left.is_empty():
		_start_battery_c = float(LlmMetrics.device_stats().get("battery_c", 0.0))
		LlmMetrics.record({"kind": "bench", "run": run_name, "device": LlmMetrics.device(), "setups": ids, "prompts": prompts}, brain.metrics_path)
	else:
		_start_battery_c = float(left.get("battery_c", 0.0))
		LlmMetrics.record({"kind": "resumed", "run": run_name, "setups": ids}, brain.metrics_path)
	for i: int in ids.size():
		if _cancelled:
			break
		await _try(ids[i], "%d of %d" % [total - ids.size() + i + 1, total])
	if not _cancelled:
		LlmMetrics.record({"kind": "end", "run": run_name}, brain.metrics_path)
	brain.stop()
	brain.run = ""
	brain.setup_id = keep_setup
	brain.mind = keep_mind
	running = false
	progressed.emit("Benchmark %s %s." % [run_name, "stopped" if _cancelled else "done"])
	finished.emit()
	return run_name


## Stops after the setup being tried.
func cancel() -> void:
	_cancelled = true


func _try(id: String, count: String) -> void:
	var setup: Dictionary = LocalBrain.setup_for(id)
	brain.stop()
	var freed: int = LocalBrain.clear_models(model_folders if not model_folders.is_empty() else LocalBrain.model_folders())
	if Engine.has_singleton("DuckDevice"):
		Engine.get_singleton("DuckDevice").call("trim")
	brain.setup_id = id
	LlmMetrics.record({"kind": "cleared", "setup": id, "label": setup.get("label", id), "run": brain.run, "mb": freed / 1000000}, brain.metrics_path)
	progressed.emit("%s: %s. Cleared %d MB of models; settling." % [count, setup.get("label", id), freed / 1000000])
	await get_tree().create_timer(settle_seconds).timeout
	await _cool_down(setup, "before starting", count)
	brain.new_conversation()
	brain.start()
	var began: float = Time.get_ticks_msec() / 1000.0
	while brain.is_starting() and Time.get_ticks_msec() / 1000.0 - began < start_timeout and not _cancelled:
		await get_tree().create_timer(0.25).timeout
	if not brain.is_ready():
		if not _cancelled:
			progressed.emit("%s: %s did not start: %s" % [count, setup.get("label", id), brain.status])
			_done(setup)
		return
	await _cool_down(setup, "before asking", count)
	for prompt: String in prompts:
		if _cancelled:
			return
		progressed.emit("%s: %s, asking \"%s\"" % [count, setup.get("label", id), prompt])
		asked.emit(prompt)
		if not brain.ask(prompt):
			return
		began = Time.get_ticks_msec() / 1000.0
		while brain.is_busy() and Time.get_ticks_msec() / 1000.0 - began < answer_timeout:
			await get_tree().create_timer(0.1).timeout
		if _cancelled:
			return
		if brain.is_busy():
			LlmMetrics.record({"kind": "failed", "setup": id, "label": setup.get("label", id), "run": brain.run, "why": "no answer in %d s" % answer_timeout}, brain.metrics_path)
			brain.stop()
			break
	_done(setup)


func _done(setup: Dictionary) -> void:
	LlmMetrics.record({"kind": "done", "setup": setup.get("id", ""), "label": setup.get("label", ""), "run": brain.run}, brain.metrics_path)


## The last benchmark in `entries` if it was cut short: {run, setups (those not done, or whose last
## try failed, in order), total, battery_c (as it began)}; {} when it ended, or there is none.
static func unfinished(entries: Array[Dictionary]) -> Dictionary:
	var bench: Dictionary = {}
	for entry: Dictionary in entries:
		if entry.get("kind") == "bench":
			bench = entry
	if bench.is_empty():
		return {}
	var done: Array = []
	var failed: Array = []
	for entry: Dictionary in entries:
		if entry.get("run") != bench["run"]:
			continue
		match entry.get("kind"):
			"end":
				return {}
			"done":
				done.append(entry.get("setup"))
			"cleared":
				failed.erase(entry.get("setup"))
			"failed":
				failed.append(entry.get("setup"))
	var left: PackedStringArray = PackedStringArray()
	for id: Variant in bench.get("setups", []):
		if not id in done or id in failed:
			left.append(str(id))
	if left.is_empty():
		return {}
	return {"run": bench["run"], "setups": left, "total": (bench.get("setups", []) as Array).size(), "battery_c": float(bench.get("battery_c", 0.0))}


## Waits, up to `cool_timeout`, for the phone to be cool, and records how long that took.
func _cool_down(setup: Dictionary, stage: String, count: String) -> void:
	var began: float = Time.get_ticks_msec() / 1000.0
	var stats: Dictionary = LlmMetrics.device_stats()
	while not cool_enough(stats, cool_thermal, _start_battery_c + cool_rise_c) and Time.get_ticks_msec() / 1000.0 - began < cool_timeout and not _cancelled:
		progressed.emit("%s: %s, cooling down %s (battery %.1f C, thermal %d)" % [count, setup.get("label", ""), stage, float(stats.get("battery_c", 0.0)), int(stats.get("thermal", 0))])
		await get_tree().create_timer(5.0).timeout
		stats = LlmMetrics.device_stats()
	LlmMetrics.record({"kind": "cooled", "setup": setup.get("id", ""), "label": setup.get("label", ""), "run": brain.run, "stage": stage, "seconds": snappedf(Time.get_ticks_msec() / 1000.0 - began, 0.1)}, brain.metrics_path)


## Whether the phone's `stats` (LlmMetrics.device_stats) say it is cool enough. No stats, as off a
## phone, is cool.
static func cool_enough(stats: Dictionary, thermal: int, battery_c: float) -> bool:
	return int(stats.get("thermal", 0)) <= thermal and float(stats.get("battery_c", 0.0)) <= battery_c
