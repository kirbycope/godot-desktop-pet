class_name Pomodoro
extends VBoxContainer
## The Pomodoro tab: focus for 25 minutes, break for 5, and after every fourth focus a 15 minute
## break, round and round until stopped. The duck is a tomato while it runs. Said or typed
## ("start a pomodoro", "a 50 minute pomodoro", "pause the pomodoro", "how long is left on the
## pomodoro?"), the pet hands the line to `request_in` and what it finds to `carry_out`, and the
## duck answers without asking the model.

## Any change: started, stopped, or on to the next phase.
signal phase_changed(phase: Phase)
## A phase ran out and `next` began; the pet says so.
signal time_up(next: Phase)

enum Phase { OFF, FOCUS, SHORT_BREAK, LONG_BREAK }

## Focus rounds before a long break.
@export var rounds: int = 4

## Where the lengths are kept, beside the hat, the voice and the microphone.
const SETTINGS_PATH: String = "user://settings.cfg"
## A word for "pomodoro" as a line must name it, including the ways speech-to-text spells it.
const NAMES: String = r"(?i)\b(?:pom+[oa]dor+o?s?|tomato\s+(?:timer|mode|time)|focus\s+(?:timer|session))\b"
const NUMBER_WORDS: Dictionary[String, int] = {
	"five": 5, "ten": 10, "fifteen": 15, "twenty": 20, "twenty five": 25, "twenty-five": 25,
	"thirty": 30, "forty": 40, "forty five": 45, "forty-five": 45, "fifty": 50, "sixty": 60, "ninety": 90,
}

var phase: Phase = Phase.OFF
## Focus rounds finished since it was started.
var finished: int = 0

@onready var phase_timer: Timer = $PhaseTimer
@onready var tick: Timer = $Tick
@onready var phase_label: Label = $Phase
@onready var time_label: Label = $Time
@onready var bar: ProgressBar = $Bar
@onready var start_button: Button = $Buttons/Start
@onready var skip_button: Button = $Buttons/Skip
@onready var stop_button: Button = $Buttons/Stop
@onready var focus_box: SpinBox = $Lengths/Focus
@onready var short_box: SpinBox = $Lengths/Short
@onready var long_box: SpinBox = $Lengths/Long


func _ready() -> void:
	var lengths: Array[int] = load_lengths(SETTINGS_PATH, [int(focus_box.value), int(short_box.value), int(long_box.value)])
	focus_box.set_value_no_signal(lengths[0])
	short_box.set_value_no_signal(lengths[1])
	long_box.set_value_no_signal(lengths[2])
	_show()


func is_running() -> bool:
	return phase != Phase.OFF


func is_paused() -> bool:
	return is_running() and phase_timer.paused


func seconds_left() -> int:
	return ceili(phase_timer.time_left) if is_running() else 0


## Starts again from the first focus round; `minutes` above 0 sets this round's length.
func start(minutes: int = 0) -> void:
	finished = 0
	_begin(Phase.FOCUS, minutes if minutes > 0 else minutes_for(Phase.FOCUS))


func stop() -> void:
	phase_timer.stop()
	tick.stop()
	phase_timer.paused = false
	phase = Phase.OFF
	finished = 0
	_show()
	phase_changed.emit(phase)


func pause() -> void:
	phase_timer.paused = true
	tick.stop()
	_show()


func resume() -> void:
	phase_timer.paused = false
	tick.start()
	_show()


## Ends the phase under way now, as though its time were up.
func skip() -> void:
	if is_running():
		_on_phase_timer_timeout()


func minutes_for(which: Phase) -> int:
	match which:
		Phase.FOCUS:
			return int(focus_box.value)
		Phase.SHORT_BREAK:
			return int(short_box.value)
		Phase.LONG_BREAK:
			return int(long_box.value)
	return 0


## Does what `request_in` found and returns what the duck says about it.
func carry_out(request: Dictionary) -> String:
	match request.get("action", ""):
		"start":
			start(int(request.get("minutes", 0)))
			return "Tomato time! %d minutes of focus. I'll tell you when it's time for a break." % ceili(phase_timer.wait_time / 60.0)
		"stop":
			if not is_running():
				return "There's no pomodoro running."
			stop()
			return "Pomodoro stopped. Back to being a plain old duck."
		"pause":
			if not is_running() or is_paused():
				return "There's nothing ticking to pause."
			pause()
			return "Paused, with %s left." % spoken_time(seconds_left())
		"resume":
			if not is_paused():
				return "The pomodoro is already ticking." if is_running() else "There's no pomodoro to carry on with. Ask me to start one."
			resume()
			return "And we're off again, %s to go." % spoken_time(seconds_left())
		"skip":
			if not is_running():
				return "There's no pomodoro running."
			skip()
			return "Skipped. " + announcement(phase, minutes_for(phase), finished, rounds)
		"status":
			if not is_running():
				return "No pomodoro running. Say start a pomodoro and I'll keep time."
			return "%s, %s left%s." % [title_for(phase, finished, rounds), spoken_time(seconds_left()), ", paused" if is_paused() else ""]
	return ""


func _begin(next: Phase, minutes: int) -> void:
	phase = next
	phase_timer.paused = false
	phase_timer.start(maxi(minutes, 1) * 60.0)
	tick.start()
	_show()
	phase_changed.emit(phase)


func _on_phase_timer_timeout() -> void:
	if phase == Phase.FOCUS:
		finished += 1
	var next: Phase = next_phase(phase, finished, rounds)
	_begin(next, minutes_for(next))
	time_up.emit(next)


func _on_tick_timeout() -> void:
	_show()


func _on_start_pressed() -> void:
	if not is_running():
		start()
	elif is_paused():
		resume()
	else:
		pause()


func _on_skip_pressed() -> void:
	skip()


func _on_stop_pressed() -> void:
	stop()


func _on_length_changed(_value: float) -> void:
	save_lengths(SETTINGS_PATH, [int(focus_box.value), int(short_box.value), int(long_box.value)])


## The tab as things stand: the phase, the time left, how far through, and what Start does now.
func _show() -> void:
	phase_label.text = title_for(phase, finished, rounds) + (" (paused)" if is_paused() else "")
	time_label.text = clock(seconds_left() if is_running() else minutes_for(Phase.FOCUS) * 60)
	bar.value = 1.0 - phase_timer.time_left / phase_timer.wait_time if is_running() else 0.0
	start_button.text = "Start" if not is_running() else ("Resume" if is_paused() else "Pause")
	skip_button.disabled = not is_running()
	stop_button.disabled = not is_running()


## What comes after `current`, `done` focus rounds in: a break after focus, the long one every
## `per_long` rounds, and focus after either break.
static func next_phase(current: Phase, done: int, per_long: int) -> Phase:
	match current:
		Phase.FOCUS:
			return Phase.LONG_BREAK if per_long > 0 and done > 0 and done % per_long == 0 else Phase.SHORT_BREAK
		Phase.SHORT_BREAK, Phase.LONG_BREAK:
			return Phase.FOCUS
	return Phase.OFF


## "Focus, round 2 of 4", "Short break", "Not running".
static func title_for(current: Phase, done: int, per_long: int) -> String:
	match current:
		Phase.FOCUS:
			return "Focus, round %d of %d" % [done % maxi(per_long, 1) + 1, per_long]
		Phase.SHORT_BREAK:
			return "Short break"
		Phase.LONG_BREAK:
			return "Long break"
	return "Not running"


## What the duck says as `next` begins, `minutes` long.
static func announcement(next: Phase, minutes: int, done: int, per_long: int) -> String:
	match next:
		Phase.SHORT_BREAK:
			return "Ding! That's a pomodoro done. Take a %d minute break: stretch, have some water." % minutes
		Phase.LONG_BREAK:
			return "Ding! That's %d pomodoros! Take a long break, %d minutes. You've earned it." % [per_long if per_long > 0 else done, minutes]
		Phase.FOCUS:
			return "Break's over! Back to it: %d minutes of focus." % minutes
	return ""


## mm:ss.
static func clock(seconds: int) -> String:
	return "%02d:%02d" % [seconds / 60, seconds % 60]


## The time left as it is said: "12 minutes", "1 minute", "40 seconds".
static func spoken_time(seconds: int) -> String:
	if seconds >= 60:
		var minutes: int = roundi(seconds / 60.0)
		return "%d minute%s" % [minutes, "" if minutes == 1 else "s"]
	return "%d second%s" % [seconds, "" if seconds == 1 else "s"]


## What a line asks of the timer: {action: start, stop, pause, resume, skip or status, minutes},
## or {} when it is not about the timer, or only asks what one is.
static func request_in(line: String) -> Dictionary:
	if RegEx.create_from_string(NAMES).search(line) == null:
		return {}
	# Asking about it first, so "when does the pomodoro end?" does not end it.
	var action: String = ""
	if _has(line, r"\b(?:how\s+(?:long|much)|when\s+(?:does|will|is)|left|remaining|status)\b"):
		action = "status"
	elif _has(line, r"\b(?:stop|cancel|end\s+(?:the|my|this|it)|quit|turn\s+off|kill|reset|enough)\b"):
		action = "stop"
	elif _has(line, r"\b(?:pause|hold\s+on|freeze)\b"):
		action = "pause"
	elif _has(line, r"\b(?:resume|unpause|continue|carry\s+on)\b"):
		action = "resume"
	elif _has(line, r"\b(?:skip|next)\b"):
		action = "skip"
	elif _has(line, r"\b(?:start|begin|set|run|kick\s+off|turn\s+on|launch|let'?s|give\s+me|i(?:\s+want|\s+need|'d\s+like|\s+would\s+like)|another|time\s+for)\b"):
		action = "start"
	if action.is_empty():
		return {}
	return {"action": action, "minutes": minutes_in(line) if action == "start" else 0}


## The length a line asks for, "a 50 minute pomodoro", "twenty-five minutes", or 0.
static func minutes_in(line: String) -> int:
	var digits: RegExMatch = RegEx.create_from_string(r"(?i)\b(\d{1,3})\s*-?\s*(?:min|minute|minutes|mins)\b").search(line)
	if digits != null:
		return clampi(digits.get_string(1).to_int(), 1, 180)
	var words: RegExMatch = RegEx.create_from_string(r"(?i)\b(twenty[\s-]five|forty[\s-]five|five|ten|fifteen|twenty|thirty|forty|fifty|sixty|ninety)\s*-?\s*(?:min|minute|minutes|mins)\b").search(line)
	if words != null:
		return NUMBER_WORDS.get(words.get_string(1).to_lower(), 0)
	return 0


static func _has(line: String, pattern: String) -> bool:
	return RegEx.create_from_string("(?i)" + pattern).search(line) != null


## [focus, short break, long break] in minutes from the settings file, `defaults` for any not there.
static func load_lengths(path: String, defaults: Array[int]) -> Array[int]:
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) != OK:
		return defaults
	return [
		int(config.get_value("pomodoro", "focus", defaults[0])),
		int(config.get_value("pomodoro", "short_break", defaults[1])),
		int(config.get_value("pomodoro", "long_break", defaults[2])),
	]


static func save_lengths(path: String, lengths: Array[int]) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value("pomodoro", "focus", lengths[0])
	config.set_value("pomodoro", "short_break", lengths[1])
	config.set_value("pomodoro", "long_break", lengths[2])
	config.save(path)
