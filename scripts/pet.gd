class_name Pet
extends Node2D
## A 3D rubber duck that lives in its own small transparent window and walks the edges of the screen.
##
## It waddles along the bottom of the usable area (above the taskbar or Dock), climbs the sides and
## hangs from the top. Drag it to move it and it falls back down; click it to talk; right-click for
## the menu. Every message you send goes with the text read off your screen, so you can explain your
## code to it the way you would to a real rubber duck. Based on DigiKey's "Desktop Pet" project,
## which moves the window rather than a sprite.

enum Edge { BOTTOM, RIGHT, TOP, LEFT }
## DOCK: sitting still in the top-right corner while the Pomodoro timer runs, out of the way but
## still a click away for the chat.
enum State { WALK, IDLE, DRAG, FALL, CHAT, SLEEP, DOCK }

## A line is on its way to the brain, typed, spoken or from the phone.
signal turn_started(line: String)
## The whole answer, with what the duck remembered or learned on the way ("" if nothing).
signal answered(text: String, notes: String)
## The captain's hat went on or came off, here or from the phone.
signal hat_changed(on: bool)
## The Settings tab's voices changed: the list (empty when only the note changed), the chosen one,
## and the line under them, such as the natural voices' download progress.
signal voices_changed(items: Array, chosen: String, note: String)
## The Duck tab's name and memories changed.
signal duck_shown(duck_name: String, memories: PackedStringArray)
## The Stats tab's text changed.
signal stats_changed(text: String)

@export var speed: float = 60.0
## Pixels a second squared pulling the duck down when it is dropped or thrown.
@export var gravity: float = 2600.0
## How much speed a bounce keeps, from 0 (thud) to 1 (superball).
@export_range(0.0, 1.0) var bounciness: float = 0.55
## How quickly sliding along the bottom slows it, per second.
@export var floor_friction: float = 4.0
## The fastest it can be thrown, in pixels a second.
@export var max_throw_speed: float = 4500.0
## A bounce faster than this squashes it and squeaks; a throw faster than this squeaks as it goes.
@export var hard_bounce: float = 650.0
## Chance of stopping for a rest at a bottom corner, as in the original project.
@export_range(0.0, 1.0) var idle_chance: float = 0.3
## Chance of climbing round a corner rather than turning back.
@export_range(0.0, 1.0) var climb_chance: float = 0.5
## How far the mouse may move between press and release for it still to count as a click.
@export var click_slop: float = 4.0
## The part of the window that takes the mouse, standing on the floor: its size, and its centre's
## offset from the window's centre. It turns with the duck on the walls and the ceiling.
@export var hit_size: Vector2 = Vector2(124, 108)
@export var hit_offset: Vector2 = Vector2(0, 32)
## Empty window above the duck's head on the floor, kept for the hat and for stretching; the bubble
## overlaps it rather than floating that far above the duck.
@export var headroom: float = 32.0
## How much higher the part that takes the mouse reaches while the duck wears its hat. On Windows
## nothing outside that part is drawn either, so it has to cover the hat however far the duck
## stretches: 60 px takes it to 6 px from the window's top, past the crown of a falling duck at 11.
@export var hat_reach: float = 60.0
## The same for the tomato's leaves, which stand lower than the hat.
@export var leaf_reach: float = 26.0
## Pixels between the docked duck (leaves and all) and the corner's right and top edges. The top one
## clears a maximised window's title bar, so its close button is not under the duck.
@export var dock_margin: Vector2 = Vector2(8, 40)
## How long the duck takes to glide to its dock.
@export var dock_seconds: float = 0.9
## Said aloud and shown when the bubble opens; one is picked at random each time.
@export var greetings: Array[String] = [
	"Quack! Hi there!", "Oh, hello! How's it going?", "Hi! What's up?", "Quack quack! Good to see you.",
	"I'm all ears. Well, no ears. But listening!", "Hello again! What are you up to?",
	"Hey! I was just having a little waddle.", "Hi! Anything on your mind?",
	"Quack! What shall we talk about?", "Oh hi! Got a puzzle for me, or just saying hello?",
]
## What the Test button says in the voice being tried.
@export var test_line: String = "Quack! I'm your rubber duck. Is this how you want me to sound?"
## Where the hat is kept, beside the chosen voice and microphone.
const SETTINGS_PATH: String = "user://settings.cfg"

## The screen is read as the user starts typing or speaking; at Send that reading is used if it is
## at most this many milliseconds old, so Send does not wait on OCR.
@export var read_ahead_ms: int = 3000

var edge: Edge = Edge.BOTTOM
## +1 is rightwards on the top and bottom edges and downwards on the sides.
var direction: int = 1
## It sleeps until its brain is ready, then wakes and walks.
var state: State = State.SLEEP:
	set = _set_state
var screen_position: Vector2 = Vector2.ZERO
## What the last look at the screen found, for the Stats tab; "" before the first look.
var screen_note: String = ""
## Whether the answer coming in has shown a sentence yet, and how long reading the screen took.
var _streamed: bool = false
var _read_ms: int = -1
var _look_started: int = 0
## The screen read ahead, while the user was typing or talking, and when; used at Send if fresh.
var _reading_ahead: bool = false
var _ahead_text: String = ""
var _ahead_at: int = -1
## Seconds spent waking up, for the warm-up message.
var _waking_seconds: int = 0
var _drag_offset: Vector2 = Vector2.ZERO
var _press_position: Vector2 = Vector2.ZERO
## Where the mouse was over the last tenth of a second of a drag, [msec, position], for the throw.
var _drag_trail: Array = []
## The duck's speed in flight, in pixels a second, and how fast it spins.
var velocity: Vector2 = Vector2.ZERO
var _spin: float = 0.0
## A line waiting for the screen to be read, or for the brain to wake up.
var _pending_line: String = ""
## What a search asked for by the pending line found, as the model reads it.
var _web_text: String = ""
## The last line sent, kept above the answer so you can see what the duck was asked.
var _last_line: String = ""
## The turn under way came from the phone, which speaks it, so the duck here stays quiet.
var _quiet: bool = false
## Said once the squeak has finished.
var _greeting: String = ""
## What the duck remembered or learned since the last answer, shown under the next one.
var _notes: Array[String] = []
## The answer being spoken, glided through once as it is said.
var _spoken: String = ""
## Whether its place is the dock rather than the edges: while the Pomodoro timer runs.
var _docked: bool = false
## The glide to the dock.
var _glide: Tween

@onready var duck: Duck = $View/Viewport/Duck
@onready var idle_timer: Timer = $IdleTimer
@onready var brain: Brain = $Brain
@onready var voice: Voice = $Voice
@onready var screen_reader: ScreenReader = $ScreenReader
@onready var searcher: Searcher = $Searcher
@onready var listener: Listener = $Listener
@onready var squeak: AudioStreamPlayer = $Squeak
## Quick squeaks, one of five, for a throw and a hard bounce.
@onready var fast_squeak: AudioStreamPlayer = $FastSqueak
@onready var bubble: Window = $Bubble
## The bubble's tabs, the same scene as the phone app's (scenes/duck_tabs.tscn).
@onready var tabs: DuckTabs = $Bubble/Panel/Margin/Tabs
@onready var bubble_input: LineEdit = $Bubble/Panel/Margin/Tabs/Chat/Entry/Input
@onready var send_button: Button = $Bubble/Panel/Margin/Tabs/Chat/Entry/Send
@onready var mic_button: Button = $Bubble/Panel/Margin/Tabs/Chat/Entry/Mic
@onready var mic_dot: Panel = $Bubble/Panel/Margin/Tabs/Chat/Entry/Mic/Dot
@onready var status: PanelContainer = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status
@onready var status_label: Label = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Label
@onready var level_meter: ProgressBar = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Level
@onready var listen_timer: Timer = $ListenTimer
@onready var wake_clock: Timer = $WakeClock
@onready var mind: Mind = $Mind
@onready var pomodoro: Pomodoro = $Pomodoro
@onready var menu: PopupMenu = $Menu


func _ready() -> void:
	var area: Rect2 = usable_area()
	screen_position = Vector2(area.get_center().x - window_size().x / 2.0, area.end.y - window_size().y)
	_apply_position()
	_stand_on(Edge.BOTTOM)
	state = State.SLEEP
	_fill_voices()
	_fill_mics()
	_fill_mind()
	set_hat(load_hat(SETTINGS_PATH))
	tabs.show_conversation(Remote.shown(mind.conversation(mind.conversation_id())))
	tabs.show_pomodoro(pomodoro.state())
	_update_stats()


func _physics_process(delta: float) -> void:
	match state:
		State.WALK:
			_walk(speed * delta)
		State.DRAG:
			var mouse: Vector2 = Vector2(DisplayServer.mouse_get_position())
			screen_position = mouse - _drag_offset
			_apply_position()
			var now: int = Time.get_ticks_msec()
			_drag_trail.append([now, mouse])
			while _drag_trail.size() > 2 and now - int(_drag_trail[0][0]) > 100:
				_drag_trail.pop_front()
		State.FALL:
			_fly(delta)


## The window lets the mouse through everywhere but the duck, so every button event that reaches it
## is on the duck. Handling press and release here, rather than through physics picking, keeps a
## quick click from being lost: picking only sees the press on the next physics frame, by which time
## the release has already gone by.
func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null:
		return
	if button.pressed and button.button_index == MOUSE_BUTTON_RIGHT:
		menu.position = DisplayServer.mouse_get_position()
		menu.popup()
	elif button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if state == State.CHAT:
			state = State.WALK
			return
		_press_position = Vector2(DisplayServer.mouse_get_position())
		_drag_offset = _press_position - screen_position
		_drag_trail.clear()
		state = State.DRAG
	elif not button.pressed and button.button_index == MOUSE_BUTTON_LEFT and state == State.DRAG:
		if is_click(_press_position, Vector2(DisplayServer.mouse_get_position()), click_slop):
			state = State.CHAT
		else:
			# Let go mid-swing and it keeps the mouse's speed: a gentle drop or a proper yeet.
			velocity = throw_velocity(_drag_trail, max_throw_speed)
			_spin = velocity.x * 0.25
			if velocity.length() > hard_bounce:
				fast_squeak.play()
			state = State.FALL


func usable_area() -> Rect2:
	return Rect2(DisplayServer.screen_get_usable_rect(get_window().current_screen))


func window_size() -> Vector2:
	return Vector2(get_window().size)


func _walk(distance: float) -> void:
	var moved: Array = walk(edge, direction, screen_position, usable_area(), window_size(), distance)
	screen_position = moved[0]
	_apply_position()
	if not moved[1]:
		return
	if edge == Edge.BOTTOM and randf() < idle_chance:
		state = State.IDLE
		return
	if randf() < climb_chance:
		var turned: Array = around_corner(edge, direction)
		edge = turned[0]
		direction = turned[1]
	else:
		direction = -direction
	_play_for_edge()


## One frame of flight: gravity, bounces off the screen's edges, sliding along the bottom, and
## spinning as it goes. It lands once it has settled on the bottom.
func _fly(delta: float) -> void:
	var step: Dictionary = fly(screen_position, velocity, usable_area(), window_size(), delta, gravity, bounciness, floor_friction)
	screen_position = step["position"]
	velocity = step["velocity"]
	_apply_position()
	_spin = lerpf(_spin, velocity.x * 0.25, 1.0 - exp(-3.0 * delta))
	duck.roll = fmod(duck.roll + _spin * delta, 360.0)
	if step["impact"] > hard_bounce:
		duck.play(&"land")
		fast_squeak.play()
	elif duck.animation == &"land" and not step["resting"]:
		duck.play(&"fall")
	if step["resting"]:
		velocity = Vector2.ZERO
		edge = Edge.BOTTOM
		direction = 1 if randf() < 0.5 else -1
		_stand_on(Edge.BOTTOM)
		duck.play(&"land")
		idle_timer.start(0.4)
		state = State.IDLE


func _apply_position() -> void:
	DisplayServer.window_set_position(Vector2i(screen_position.round()))


func _play_for_edge() -> void:
	_stand_on(edge)
	duck.facing = facing_for(edge, direction)
	duck.play(animation_for(edge))


## Turns the duck and the window's mouse passthrough to stand on `on_edge`. Only the duck takes the
## mouse; clicks on the empty rest of the window go through to the desktop.
func _stand_on(on_edge: Edge) -> void:
	duck.roll = roll_for(on_edge)
	_update_passthrough()


func _update_passthrough() -> void:
	var reach: float = reach_for(duck.hat, duck.tomato, hat_reach, leaf_reach)
	DisplayServer.window_set_mouse_passthrough(hit_outline(window_size(), hit_size, hit_offset, duck.roll, reach))


func _set_state(value: State) -> void:
	var was: State = state
	state = settle_state(value, brain != null and brain.is_ready(), _docked, is_inside_tree() and _stranded())
	if not is_node_ready():
		return
	if _glide != null and (state == State.DRAG or state == State.FALL):
		_glide.kill()
	match state:
		State.SLEEP:
			_stand_on(Edge.BOTTOM)
			duck.play(&"sleep")
		State.WALK:
			_play_for_edge()
		State.IDLE:
			if was == State.SLEEP:
				duck.play(&"wake")
				idle_timer.start(1.3)
			elif was != State.FALL:
				duck.play([&"idle", &"cheer", &"think"].pick_random())
				idle_timer.start(randf_range(1.0, 3.0))
		State.DRAG:
			_stand_on(Edge.BOTTOM)
			duck.play(&"hang")
		State.FALL:
			duck.play(&"fall")
		State.CHAT:
			duck.looking_at_viewer = true
			_open_bubble()
		State.DOCK:
			edge = Edge.BOTTOM
			_stand_on(Edge.BOTTOM)
			duck.facing = -1
			_glide_to(dock_position(usable_area(), window_size(), hit_size, hit_offset, reach_for(duck.hat, duck.tomato, hat_reach, leaf_reach), dock_margin))
	if was == State.CHAT and state != State.CHAT:
		duck.looking_at_viewer = false
		_greeting = ""
		voice.stop()
		listener.stop()
		mic_button.set_pressed_no_signal(false)
		bubble.hide()


func _open_bubble() -> void:
	tabs.current_tab = 0
	_update_stats()
	if not brain.is_ready():
		# The status line says how the waking up is going.
		duck.play(&"sleep")
	elif is_thinking():
		duck.play(&"think")
	else:
		# Squeak first; the greeting is shown now and said once the squeak is over.
		_greeting = greetings.pick_random() if not greetings.is_empty() else "Quack!"
		tabs.say(_greeting)
		duck.play(&"squeeze")
		squeak.play()
	_place_bubble()
	bubble.show()
	bubble.grab_focus()
	bubble_input.grab_focus()
	tabs.scroll_to_end()


## Over the duck, or under it where there is no room above, as in the dock.
func _place_bubble() -> void:
	var area: Rect2 = usable_area()
	var size: Vector2 = Vector2(bubble.size)
	var above: float = screen_position.y + headroom - size.y
	var at: Vector2 = Vector2(screen_position.x + (window_size().x - size.x) / 2.0, above if above >= area.position.y else screen_position.y + window_size().y)
	at.x = clampf(at.x, area.position.x, area.end.x - size.x)
	bubble.position = Vector2i(at.round())


## Glides the window to `target`, or settles at once when it is there already. A bubble open
## comes along.
func _glide_to(target: Vector2) -> void:
	if _glide != null:
		_glide.kill()
	if screen_position.distance_to(target) < 1.0:
		_on_glide_finished()
		return
	if state != State.CHAT:
		duck.play(&"fall")
	_glide = create_tween()
	_glide.tween_method(_glide_step.bind(screen_position, target), 0.0, 1.0, dock_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_glide.tween_callback(_on_glide_finished)


func _glide_step(t: float, from: Vector2, to: Vector2) -> void:
	screen_position = from.lerp(to, t)
	_apply_position()
	if state == State.CHAT:
		_place_bubble()


func _on_glide_finished() -> void:
	if state == State.DOCK:
		duck.play(&"land")
		idle_timer.start(0.6)


## Standing on the bottom edge but up off the floor, as it is when the timer stops in the dock.
func _stranded() -> bool:
	return edge == Edge.BOTTOM and screen_position.y < usable_area().end.y - window_size().y - 1.0


## Speaks `text` and quacks along while it does; with no voice, a short quack then idle.
func _say(text: String) -> void:
	listener.pause()
	# Thinking until the sound starts: a natural voice takes a second or two to synthesise.
	duck.play(&"think")
	voice.speak(text)
	# The voice says when it has finished, but in case it never does, listening comes back after
	# about as long as the words take to say.
	listen_timer.start(speaking_seconds(text) + (3.0 if Kokoro.sid_of(voice.voice_id) >= 0 else 0.0) if not voice.voice_id.is_empty() else 1.5)
	_update_status()


## The Stats tab, and whether the chat input is open yet.
func _update_stats() -> void:
	var shown: String = stats_text(brain.status, brain.hardware, brain.model_id, _voice_name(voice.voice_id), screen_note, brain.choice, timing_text(brain.timings, _read_ms))
	if shown != tabs.stats.text:
		tabs.stats.text = shown
		stats_changed.emit(shown)
	# Nothing to type into until it is awake, and nothing to send while it is thinking.
	bubble_input.editable = brain.is_ready()
	send_button.disabled = not brain.is_ready() or is_thinking()
	mic_button.disabled = not brain.is_ready() or not listener.is_supported()
	bubble_input.placeholder_text = placeholder_for(listener.mode, brain.is_ready())
	_update_status()


## Reading the screen or waiting on an answer.
func is_thinking() -> bool:
	return brain.is_busy() or screen_reader.is_reading() or searcher.is_searching() or not _pending_line.is_empty()


## The system's voices, then the natural Kokoro ones: greyed out with a download entry above them
## until they are installed, then white like the rest. The phone gets the same list.
func _fill_voices() -> void:
	var installing: bool = voice.kokoro != null and voice.kokoro.is_installing()
	var download: String = _download_text if installing else "Download natural voices (%d MB)" % Kokoro.download_mb()
	var items: Array[Dictionary] = DuckTabs.voice_items(voice.available(), voice.kokoro_ready(), installing, download)
	var note: String = "Speaking as: " + _voice_name(voice.voice_id)
	if installing:
		note = _download_text
	elif items.is_empty():
		note = "This system offers no text-to-speech voices."
	# While it downloads the list stays on the download entry, which shows the progress.
	var chosen: String = DuckTabs.DOWNLOAD_KOKORO if installing else voice.voice_id
	tabs.show_voices(items, chosen, note)
	_shown_voices = {"items": items, "chosen": chosen, "note": note}
	voices_changed.emit(items, chosen, note)


## Choosing the download entry starts the download.
func _on_voice_selected(id: String) -> void:
	if id == DuckTabs.DOWNLOAD_KOKORO:
		download_voices()


## Starts downloading the natural voices, from here or the phone.
func download_voices() -> void:
	if voice.kokoro != null and not voice.kokoro.is_installing() and not voice.kokoro_ready():
		voice.kokoro.install()
		_download_text = "Starting the download..."
		_fill_voices()


func _on_kokoro_progress(_fraction: float, text: String) -> void:
	_download_text = text
	_shown_voices["note"] = text
	tabs.show_voice_note(text, true)
	voices_changed.emit([], "", text)


func _on_kokoro_installed() -> void:
	_fill_voices()
	tabs.show_voice_note("Natural voices ready: pick one.")


func _on_kokoro_failed(message: String) -> void:
	_fill_voices()
	tabs.show_voice_note(message)


func _fill_mics() -> void:
	# The saved choice, since AudioServer reports "Default" until the microphone first opens.
	var chosen: String = Listener.load_device(Listener.SETTINGS_PATH)
	tabs.show_mics(AudioServer.get_input_device_list(), chosen if not chosen.is_empty() else AudioServer.input_device)


func _on_mic_selected(device: String) -> void:
	listener.use_device(device)


## The latest download progress, shown on the download entry while it downloads.
var _download_text: String = "Downloading natural voices..."
## The Settings tab's voices as last shown, for a phone that pairs.
var _shown_voices: Dictionary = {}


func _voice_name(id: String) -> String:
	for entry: Dictionary in voice.available():
		if entry["id"] == id:
			return entry.get("name", id)
	return "none"


func _on_idle_timer_timeout() -> void:
	if state == State.IDLE:
		state = State.WALK
	elif state == State.DOCK:
		duck.play(&"idle")


func _on_voice_started() -> void:
	if state == State.CHAT:
		duck.play(&"talk")
		# Once per answer, when the whole of it is known; it starts on its first sentence.
		_glide_spoken()
	_update_status()


## Glides the chat through the answer being said, once, over about as long as it takes to say, so
## a long answer can be read all the way through as it is spoken.
func _glide_spoken() -> void:
	if _spoken.is_empty():
		return
	tabs.glide_to_end(scroll_seconds(_spoken))
	_spoken = ""


## Speech runs near 14 characters a second; the first second or so is the top of the answer.
static func scroll_seconds(text: String) -> float:
	return maxf(text.length() / 14.0 - 1.0, 0.5)


func _on_voice_finished() -> void:
	listen_timer.stop()
	_done_talking()


func _on_listen_timer_timeout() -> void:
	# Still talking after all: look again shortly.
	if voice.is_speaking():
		listen_timer.start(0.5)
		return
	_done_talking()


## The duck has finished saying something: back to idle, and listening again in a conversation.
## Whatever the duck happens to be doing, so a changed animation can never leave it deaf.
func _done_talking() -> void:
	if state != State.CHAT:
		return
	if duck.animation == &"talk":
		duck.play(&"idle")
	if not is_thinking():
		listener.resume()
	_update_status()


func _on_squeak_finished() -> void:
	if state == State.CHAT and not _greeting.is_empty():
		brain.note_said(_greeting)
		_say(_greeting)
	_greeting = ""


func _on_brain_status_changed(_text: String) -> void:
	_update_stats()
	if not brain.is_ready():
		return
	wake_clock.stop()
	if state == State.SLEEP:
		state = State.IDLE
	elif state == State.CHAT and _last_line.is_empty():
		# Awake with the bubble open: say hello properly now.
		_greeting = "I'm awake! " + (greetings.pick_random() if not greetings.is_empty() else "Quack!")
		tabs.say(_greeting)
		duck.play(&"squeeze")
		squeak.play()
		bubble_input.grab_focus()


func _on_wake_clock_timeout() -> void:
	_waking_seconds += 1
	_update_status()


## Another conversation is under way, started or taken up here or from the phone: the chat shows it.
func _on_brain_conversation_changed(id: String) -> void:
	_last_line = ""
	tabs.show_conversation(Remote.shown(mind.conversation(id)))


func _on_tabs_new_pressed() -> void:
	if not brain.new_conversation():
		tabs.add_note("Not while I'm answering.")


func _on_tabs_past_pressed() -> void:
	tabs.show_past(mind.conversations(), mind.conversation_id())


func _on_tabs_conversation_chosen(id: String) -> void:
	if not brain.open_conversation(id):
		tabs.add_note("Not while I'm answering.")


## A line from the phone: the same turn as one typed here, screen read and all. `quiet` leaves the
## speaking to the phone. False when the brain is asleep or busy.
func send_remote(line: String, quiet: bool) -> bool:
	if brain == null or not brain.is_ready() or is_thinking() or line.strip_edges().is_empty():
		return false
	_quiet = quiet
	_send(line.strip_edges())
	return true


## A sentence of the answer, as soon as it is written: shown, and said after the one before.
func _on_brain_sentence(text: String) -> void:
	tabs.add_sentence(text)
	if not _streamed:
		_streamed = true
		if state == State.CHAT and not _quiet:
			_say(text)
		return
	if state == State.CHAT and not _quiet:
		voice.add(text)
		listen_timer.start(listen_timer.time_left + text.length() / 14.0)


func _on_brain_replied(text: String) -> void:
	var notes: String = _take_notes().strip_edges().trim_prefix("(").trim_suffix(")")
	tabs.set_answer(text)
	tabs.add_note(notes)
	_update_stats()
	answered.emit(text, notes)
	if _quiet:
		# The phone said it; here the mic, if it was on, comes back now.
		_quiet = false
		_done_talking()
		return
	if state != State.CHAT:
		return
	_spoken = text
	match after_answer(_streamed, voice.is_speaking()):
		&"say":
			# Nothing came as sentences, such as "my brain did not answer": say it whole.
			_say(text)
		&"scroll":
			_glide_spoken()
		&"listen":
			_done_talking()
	bubble_input.grab_focus()


## What follows a whole answer: "say" it when none of it came as sentences, "scroll" along while
## the voice is still saying them (its `finished` turns the mic back on), else "listen" again now.
## The voice can finish the last sentence it was given while the model is still writing, and the
## rest of the answer can turn out to be repeats that are never said; the mic used to stay off then,
## since it is not turned back on while the duck is still thinking.
static func after_answer(streamed: bool, speaking: bool) -> StringName:
	if not streamed:
		return &"say"
	return &"scroll" if speaking else &"listen"


func _on_test_pressed(id: String) -> void:
	test_voice(id)


func _on_apply_pressed(id: String) -> void:
	apply_voice(id)


## Says the test line in voice `id` here, without changing the duck's voice.
func test_voice(id: String) -> void:
	if not id.is_empty():
		voice.speak(test_line, id)


## Makes `id` the duck's voice, here and for the phone.
func apply_voice(id: String) -> void:
	if id.is_empty():
		return
	voice.apply(id)
	_fill_voices()
	_update_stats()


## The Settings tab's voices as last shown: {items, chosen, note}, for a phone that pairs.
func shown_voices() -> Dictionary:
	return _shown_voices


## Typed and sent: Enter, or Send.
func _on_tabs_line_sent(line: String) -> void:
	if not is_thinking():
		_send(line)


## Typed or spoken, a line goes the same way: look at the screen, then ask. A line sent before the
## brain is awake waits for it.
func _send(line: String) -> void:
	if not brain.is_ready():
		return
	# "Start a pomodoro", "pause the pomodoro": the timer's, answered here without the model.
	var request: Dictionary = Pomodoro.request_in(line)
	if not request.is_empty():
		_answer_here(line, pomodoro.carry_out(request))
		return
	_pending_line = line
	turn_started.emit(line)
	# "Your name is ...", "remember that ...": done now, so the answer already knows. After the line
	# is pending, so the note waits for the answer rather than being written over.
	mind.heed(line)
	_last_line = line
	_greeting = ""
	squeak.stop()
	voice.stop()
	listener.pause()
	duck.play(&"think")
	_web_text = ""
	# "Search for ...", "look up ...": the web first, then the screen as always.
	var query: String = Searcher.query_in(line)
	if not query.is_empty():
		tabs.begin_answer(line, "Searching DuckDuckGo for %s..." % query)
		searcher.search(query)
	else:
		tabs.begin_answer(line, "Looking at your screen...")
		_look_or_reuse()
	_update_stats()


## A line the duck answers itself, such as one for the Pomodoro timer: no screen, no model.
func _answer_here(line: String, text: String) -> void:
	turn_started.emit(line)
	_last_line = line
	_greeting = ""
	squeak.stop()
	tabs.begin_answer(line, text)
	answered.emit(text, "")
	if _quiet:
		_quiet = false
		_done_talking()
	elif state == State.CHAT:
		_say(text)
	_update_stats()


## The duck is a tomato while the Pomodoro timer runs, docked in the top-right corner; when it
## stops, the duck drops from there and goes back to walking.
func _on_pomodoro_phase_changed(phase: Pomodoro.Phase) -> void:
	var running: bool = phase != Pomodoro.Phase.OFF
	duck.tomato = running
	_update_passthrough()
	if running == _docked:
		return
	_docked = running
	if running:
		if state == State.CHAT:
			_glide_to(dock_position(usable_area(), window_size(), hit_size, hit_offset, reach_for(duck.hat, duck.tomato, hat_reach, leaf_reach), dock_margin))
		elif state == State.WALK or state == State.IDLE:
			state = State.DOCK
	elif state == State.DOCK:
		velocity = Vector2.ZERO
		_spin = 0.0
		state = State.FALL


## Time is up on a focus or a break: a squeak, a hop where it can, and the news said aloud, after
## whatever it is saying now.
func _on_pomodoro_time_up(next: Pomodoro.Phase) -> void:
	var text: String = Pomodoro.announcement(next, pomodoro.minutes_for(next), pomodoro.finished, pomodoro.rounds)
	squeak.play()
	if state == State.CHAT:
		if is_thinking() or voice.is_speaking():
			voice.add(text)
		else:
			tabs.say(text)
			_say(text)
		return
	if state == State.DOCK:
		duck.play(&"cheer")
		idle_timer.start(Duck.HOP_SECONDS * 3.0)
	elif state == State.IDLE or (state == State.WALK and edge == Edge.BOTTOM):
		state = State.IDLE
		duck.play(&"cheer")
		idle_timer.start(Duck.HOP_SECONDS * 3.0)
	voice.speak(text)


func _on_searcher_searched(results: Array[Dictionary]) -> void:
	var query: String = Searcher.query_in(_pending_line)
	_web_text = Searcher.as_prompt(query, results)
	if not results.is_empty():
		_notes.append(Searcher.as_sources(results))
	elif not searcher.last_error.is_empty():
		_notes.append(searcher.last_error)
	tabs.set_answer("Looking at your screen...")
	_look_or_reuse()


## The screen read while they were typing or talking, if it is fresh; one being read now, waited for;
## otherwise a new read.
func _look_or_reuse() -> void:
	if is_fresh(_ahead_at, Time.get_ticks_msec(), read_ahead_ms):
		_ahead_at = -1
		_read_ms = 0
		_on_screen_reader_read_finished.call_deferred(_ahead_text)
	elif not _reading_ahead:
		_look()


## Starts reading the screen ahead of Send: on the first letter typed, or as the mic hears speech.
func _read_ahead() -> void:
	if not brain.is_ready() or screen_reader.is_reading() or not _pending_line.is_empty():
		return
	_reading_ahead = true
	_look()


func _on_input_text_changed(text: String) -> void:
	if text.length() == 1:
		_read_ahead()


static func is_fresh(read_at: int, now: int, limit_ms: int) -> bool:
	return read_at >= 0 and now - read_at <= limit_ms


func _look() -> void:
	_read_ms = -1
	_look_started = Time.get_ticks_msec()
	var window: Window = get_window()
	var own_windows: Array[Rect2i] = [Rect2i(window.position, window.size), Rect2i(bubble.position, bubble.size)]
	screen_reader.read(window.current_screen, own_windows)


func _on_screen_reader_read_finished(text: String) -> void:
	if _reading_ahead:
		_reading_ahead = false
		_ahead_text = text
		_ahead_at = Time.get_ticks_msec()
		# Nobody is waiting yet: keep it for Send.
		if _pending_line.is_empty():
			return
		_ahead_at = -1
	screen_note = screen_reader.last_error if not screen_reader.last_error.is_empty() else "%d characters read last time" % text.length()
	if _read_ms < 0:
		_read_ms = Time.get_ticks_msec() - _look_started
	tabs.set_answer("...")
	_streamed = false
	_spoken = ""
	brain.ask(_pending_line, text, _web_text)
	_pending_line = ""
	_web_text = ""
	_update_stats()


## The mic turns on a conversation: talk, pause, the duck answers, then it listens again.
func _on_mic_toggled(on: bool) -> void:
	if not on:
		listener.finish()
		return
	listener.foundry_path = brain.foundry_path()
	listener.model_alias = brain.speech_name
	if listener.model_alias.is_empty():
		tabs.add_note("No speech model fits this machine, or I am still waking up." if brain.is_ready() else "Still waking up. Try the mic again in a moment.")
		mic_button.set_pressed_no_signal(false)
		return
	listener.start()
	squeak.stop()
	_greeting = ""
	if is_thinking() or voice.is_speaking():
		listener.pause()


func _on_listener_heard(text: String) -> void:
	if text.is_empty():
		if not listener.last_error.is_empty():
			tabs.add_note(listener.last_error)
		listener.resume()
		return
	_send(text)


func _on_listener_mode_changed(mode: Listener.Mode) -> void:
	if mode == Listener.Mode.HEARING:
		_read_ahead()
	_update_stats()
	_update_status()


func _on_listener_level_changed(db: float) -> void:
	level_meter.value = db


## The red dot on the mic and the line above the box: plain to see whether it is listening.
func _update_status() -> void:
	var on: bool = listener.mode != Listener.Mode.OFF
	mic_dot.visible = on
	mic_dot.self_modulate.a = 1.0 if listener.mode == Listener.Mode.HEARING else 0.7
	status.visible = on or not brain.is_ready()
	# The status stands in for the box, in the same row, so the answer keeps its room.
	bubble_input.visible = not status.visible
	if not brain.is_ready():
		status_label.text = waking_text(brain.status, _waking_seconds)
	else:
		status_label.text = status_for(listener.mode, is_thinking(), voice.is_speaking() or duck.animation == &"talk")
	level_meter.visible = listener.mode == Listener.Mode.WAITING or listener.mode == Listener.Mode.HEARING
	if not level_meter.visible:
		level_meter.value = level_meter.min_value


func _on_bubble_window_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		state = State.WALK


## The Duck tab: its name and what it remembers.
## Puts the captain's hat on or takes it off, keeps the choice, and tells the phone.
func set_hat(on: bool) -> void:
	duck.hat = on
	_update_passthrough()
	tabs.show_hat(on)
	save_hat(SETTINGS_PATH, on)
	hat_changed.emit(on)


func _on_hat_toggled(on: bool) -> void:
	set_hat(on)


static func load_hat(path: String) -> bool:
	var config: ConfigFile = ConfigFile.new()
	return bool(config.get_value("duck", "hat", false)) if config.load(path) == OK else false


static func save_hat(path: String, on: bool) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(path)
	config.set_value("duck", "hat", on)
	config.save(path)


## The Duck tab: its name and what it remembers, here and on the phone.
func _fill_mind() -> void:
	bubble.title = mind.duck_name() if not mind.duck_name().is_empty() else "Rubber Duck"
	tabs.show_duck(mind.duck_name(), mind.memories())
	duck_shown.emit(mind.duck_name(), mind.memories())


## Something was remembered, forgotten, learned or renamed. The Duck tab shows it at once; the
## chat notes it under the next answer, so a note made mid-answer is not written over.
func _on_mind_changed(note: String) -> void:
	_fill_mind()
	_notes.append(note)


func _take_notes() -> String:
	if _notes.is_empty():
		return ""
	var text: String = "\n\n(%s)" % "; ".join(_notes)
	_notes.clear()
	return text


func _on_name_saved(duck_name: String) -> void:
	mind.set_duck_name(duck_name)


func _on_memory_forgotten(index: int) -> void:
	mind.forget_at(index)


## The timer changed: its tab shows it, here and (through Remote) on the phone.
func _on_pomodoro_changed() -> void:
	tabs.show_pomodoro(pomodoro.state())


func _on_folder_pressed() -> void:
	OS.shell_open(mind.folder_path())


func _on_menu_id_pressed(id: int) -> void:
	if id == 0:
		get_tree().quit()


## Moves `distance` pixels along `edge` in `direction`, stopping at the corner.
## Returns [new position, whether a corner was reached].
static func walk(on_edge: Edge, toward: int, from: Vector2, area: Rect2, size: Vector2, distance: float) -> Array:
	var low: Vector2 = area.position
	var high: Vector2 = area.end - size
	var to: Vector2 = from
	if on_edge == Edge.BOTTOM or on_edge == Edge.TOP:
		to.y = high.y if on_edge == Edge.BOTTOM else low.y
		to.x = clampf(from.x + toward * distance, low.x, high.x)
		return [to, to.x <= low.x or to.x >= high.x]
	to.x = high.x if on_edge == Edge.RIGHT else low.x
	to.y = clampf(from.y + toward * distance, low.y, high.y)
	return [to, to.y <= low.y or to.y >= high.y]


## The edge and direction after climbing round the corner reached by travelling `toward` along `on_edge`.
static func around_corner(on_edge: Edge, toward: int) -> Array:
	match on_edge:
		Edge.BOTTOM:
			return [Edge.RIGHT if toward > 0 else Edge.LEFT, -1]
		Edge.TOP:
			return [Edge.RIGHT if toward > 0 else Edge.LEFT, 1]
		Edge.RIGHT:
			return [Edge.BOTTOM if toward > 0 else Edge.TOP, -1]
	return [Edge.BOTTOM if toward > 0 else Edge.TOP, 1]


## The mouse's speed over a drag's last moments, from [msec, position] samples, capped at `cap`.
static func throw_velocity(trail: Array, cap: float) -> Vector2:
	if trail.size() < 2:
		return Vector2.ZERO
	var seconds: float = (int(trail[-1][0]) - int(trail[0][0])) / 1000.0
	if seconds <= 0.0:
		return Vector2.ZERO
	return (((trail[-1][1] as Vector2) - (trail[0][1] as Vector2)) / seconds).limit_length(cap)


## One step of flight inside `area` for a window of `size`: returns its new position and velocity,
## how hard it hit anything this step (the speed lost into the bounce), and whether it has come to
## rest on the bottom.
static func fly(from: Vector2, speed: Vector2, area: Rect2, size: Vector2, delta: float, pull: float, bounce: float, friction: float) -> Dictionary:
	var low: Vector2 = area.position
	var high: Vector2 = area.end - size
	var v: Vector2 = speed + Vector2(0.0, pull * delta)
	var p: Vector2 = from + v * delta
	var impact: float = 0.0
	if p.x < low.x or p.x > high.x:
		impact = maxf(impact, absf(v.x))
		p.x = clampf(p.x, low.x, high.x)
		v.x = -v.x * bounce
	if p.y < low.y:
		impact = maxf(impact, absf(v.y))
		p.y = low.y
		v.y = -v.y * bounce
	var on_floor: bool = p.y >= high.y
	if on_floor:
		p.y = high.y
		if v.y > 0.0:
			impact = maxf(impact, v.y)
			v.y = -v.y * bounce if v.y > 250.0 else 0.0
		v.x *= exp(-friction * delta)
	var resting: bool = on_floor and absf(v.y) < 1.0 and absf(v.x) < 40.0
	return {"position": p, "velocity": v, "impact": impact, "resting": resting}


## Whether a press and release `slop` pixels apart or closer is a click rather than a drag.
static func is_click(pressed_at: Vector2, released_at: Vector2, slop: float) -> bool:
	return pressed_at.distance_to(released_at) <= slop


## How much higher than the duck's head the part that takes the mouse reaches: the tomato's leaves
## take the hat's place, so they decide it while it is a tomato.
static func reach_for(hat: bool, tomato: bool, hat_height: float, leaf_height: float) -> float:
	if tomato:
		return leaf_height
	return hat_height if hat else 0.0


## The window-space outline that takes the mouse, turned with a duck rolled `roll` degrees.
## 3D roll is anticlockwise on screen and 2D rotation clockwise, hence the minus.
static func hit_outline(window: Vector2, size: Vector2, offset: Vector2, roll: float, reach: float = 0.0) -> PackedVector2Array:
	# `reach` raises the top edge (the duck's head side) and leaves the base where it is.
	size.y += reach
	offset.y -= reach / 2.0
	var half: Vector2 = size / 2.0
	var to_window: Transform2D = Transform2D(-deg_to_rad(roll), window / 2.0) * Transform2D(0.0, offset)
	return to_window * PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])


## Degrees the duck rolls to stand on an edge with its base against it.
static func roll_for(on_edge: Edge) -> float:
	match on_edge:
		Edge.RIGHT:
			return 90.0
		Edge.TOP:
			return 180.0
		Edge.LEFT:
			return -90.0
	return 0.0


## Which way the rolled duck must face to look where it is going. Rolled, the duck's own right
## points up the right wall, left along the ceiling and down the left wall.
static func facing_for(on_edge: Edge, toward: int) -> int:
	return toward if on_edge == Edge.BOTTOM or on_edge == Edge.LEFT else -toward


## What the Stats tab shows: the brain's state, the hardware, the model, the voice and the last look.
static func stats_text(status: String, hardware: String, model: String, voice_name: String, screen: String = "", choice: String = "", last_answer: String = "") -> String:
	var lines: PackedStringArray = PackedStringArray([status])
	if not hardware.is_empty():
		lines.append(hardware)
	if not model.is_empty():
		lines.append("Model: " + model)
	if not choice.is_empty():
		lines.append(choice)
	lines.append("Voice: " + voice_name)
	if not screen.is_empty():
		lines.append("Screen: " + screen)
	if not last_answer.is_empty():
		lines.append("Last answer: " + last_answer)
	return "\n".join(lines)


## How quickly the last answer came: reading the screen, the first word, the first sentence, the
## whole of it, and how it ended ("stop", or "length" when it ran out of tokens).
static func timing_text(timings: Dictionary, read_ms: int) -> String:
	if not timings.has("reply"):
		return ""
	var parts: PackedStringArray = PackedStringArray()
	if read_ms >= 0:
		parts.append("screen %d ms" % read_ms)
	if timings.has("first_token"):
		parts.append("first word %d ms" % timings["first_token"])
	if timings.has("first_sentence"):
		parts.append("first sentence %d ms" % timings["first_sentence"])
	parts.append("whole %.1f s" % (float(timings["reply"]) / 1000.0))
	var ended: String = String(timings.get("finish_reason", ""))
	return ", ".join(parts) + (" (%s%s)" % [ended, ", debugging" if timings.get("debugging", false) else ""] if not ended.is_empty() else "")


## What the status line says while the mic is on.
static func status_for(mode: Listener.Mode, thinking: bool, talking: bool) -> String:
	match mode:
		Listener.Mode.WAITING:
			return "Listening..."
		Listener.Mode.HEARING:
			return "Hearing you..."
		Listener.Mode.TRANSCRIBING:
			return "Writing it down..."
	if thinking:
		return "Thinking..."
	if talking:
		return "Talking..."
	return "Mic paused"


## About how long `text` takes to say aloud, with a margin: speech runs near 14 characters a second.
static func speaking_seconds(text: String) -> float:
	return text.length() / 14.0 + 2.0


## The input box's hint: what the mic is doing, or what typing will do.
static func placeholder_for(mode: Listener.Mode, ready: bool) -> String:
	match mode:
		Listener.Mode.WAITING:
			return "Listening... talk, then pause"
		Listener.Mode.HEARING:
			return "Hearing you..."
		Listener.Mode.TRANSCRIBING:
			return "Writing down what you said..."
	return "Talk to me, then Enter" if ready else "Still waking up..."


## Walking and resting wait until the brain is ready: until then the duck sleeps.
## Sleeping until its brain is ready; back to the dock rather than walking while `docked`; and
## dropping to the floor rather than walking in mid-air when it is `stranded` there by a timer
## stopped while it was docked.
static func settle_state(requested: State, ready: bool, docked: bool = false, stranded: bool = false) -> State:
	if not ready and (requested == State.WALK or requested == State.IDLE):
		return State.SLEEP
	if requested == State.WALK and docked:
		return State.DOCK
	if requested == State.WALK and stranded:
		return State.FALL
	return requested


## Where the window goes to dock the duck in the top-right corner of `area`: the part that takes
## the mouse, leaves or hat included (`reach`), `margin.x` in from the right edge and `margin.y`
## down from the top. The window's empty edges may hang off the screen.
static func dock_position(area: Rect2, window: Vector2, size: Vector2, offset: Vector2, reach: float, margin: Vector2) -> Vector2:
	var right: float = window.x / 2.0 + offset.x + size.x / 2.0
	var top: float = window.y / 2.0 + offset.y - size.y / 2.0 - reach
	return Vector2(area.end.x - margin.x - right, area.position.y + margin.y - top)


## The warm-up line: how long and what the brain is doing, "Waking up, 23 s: Loading ...". The
## seconds come first so a long step clipped by the bubble still shows it is moving.
static func waking_text(status: String, seconds: int) -> String:
	var doing: String = status.get_slice("\n", 0).trim_suffix("...").trim_suffix(".")
	return "Waking up, %d s: %s" % [seconds, doing]


static func animation_for(on_edge: Edge) -> StringName:
	match on_edge:
		Edge.BOTTOM:
			return &"walk"
		Edge.TOP:
			return &"hang"
	return &"climb"
