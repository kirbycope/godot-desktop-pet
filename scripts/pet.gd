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
enum State { WALK, IDLE, DRAG, FALL, CHAT, SLEEP }

@export var speed: float = 60.0
@export var fall_speed: float = 700.0
## Chance of stopping for a rest at a bottom corner, as in the original project.
@export_range(0.0, 1.0) var idle_chance: float = 0.3
## Chance of climbing round a corner rather than turning back.
@export_range(0.0, 1.0) var climb_chance: float = 0.5
## How far the mouse may move between press and release for it still to count as a click.
@export var click_slop: float = 4.0
## The part of the window that takes the mouse, standing on the floor: its size, and its centre's
## offset from the window's centre. It turns with the duck on the walls and the ceiling.
@export var hit_size: Vector2 = Vector2(124, 108)
@export var hit_offset: Vector2 = Vector2(0, 16)
## Said aloud and shown when the bubble opens; one is picked at random each time.
@export var greetings: Array[String] = [
	"Quack! Hi there!", "Oh, hello! How's it going?", "Hi! What's up?", "Quack quack! Good to see you.",
	"I'm all ears. Well, no ears. But listening!", "Hello again! What are you up to?",
	"Hey! I was just having a little waddle.", "Hi! Anything on your mind?",
	"Quack! What shall we talk about?", "Oh hi! Got a puzzle for me, or just saying hello?",
]
## What the Test button says in the voice being tried.
@export var test_line: String = "Quack! I'm your rubber duck. Is this how you want me to sound?"

var edge: Edge = Edge.BOTTOM
## +1 is rightwards on the top and bottom edges and downwards on the sides.
var direction: int = 1
## It sleeps until its brain is ready, then wakes and walks.
var state: State = State.SLEEP:
	set = _set_state
var screen_position: Vector2 = Vector2.ZERO
## What the last look at the screen found, for the Stats tab; "" before the first look.
var screen_note: String = ""
## Seconds spent waking up, for the warm-up message.
var _waking_seconds: int = 0
var _drag_offset: Vector2 = Vector2.ZERO
var _press_position: Vector2 = Vector2.ZERO
## A line waiting for the screen to be read, or for the brain to wake up.
var _pending_line: String = ""
## The last line sent, kept above the answer so you can see what the duck was asked.
var _last_line: String = ""
## Said once the squeak has finished.
var _greeting: String = ""
## What the duck remembered or learned since the last answer, shown under the next one.
var _notes: Array[String] = []
## The answer being spoken, and the tween that scrolls it along.
var _spoken: String = ""
var _scroll_tween: Tween

@onready var duck: Duck = $View/Viewport/Duck
@onready var idle_timer: Timer = $IdleTimer
@onready var brain: Brain = $Brain
@onready var voice: Voice = $Voice
@onready var screen_reader: ScreenReader = $ScreenReader
@onready var listener: Listener = $Listener
@onready var squeak: AudioStreamPlayer = $Squeak
@onready var bubble: Window = $Bubble
@onready var tabs: TabContainer = $Bubble/Panel/Margin/Tabs
@onready var bubble_text: RichTextLabel = $Bubble/Panel/Margin/Tabs/Chat/Text
@onready var bubble_input: LineEdit = $Bubble/Panel/Margin/Tabs/Chat/Entry/Input
@onready var send_button: Button = $Bubble/Panel/Margin/Tabs/Chat/Entry/Send
@onready var mic_button: Button = $Bubble/Panel/Margin/Tabs/Chat/Entry/Mic
@onready var mic_dot: Panel = $Bubble/Panel/Margin/Tabs/Chat/Entry/Mic/Dot
@onready var status: PanelContainer = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status
@onready var status_label: Label = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Label
@onready var level_meter: ProgressBar = $Bubble/Panel/Margin/Tabs/Chat/Entry/Status/Row/Level
@onready var listen_timer: Timer = $ListenTimer
@onready var wake_clock: Timer = $WakeClock
@onready var stats: RichTextLabel = $Bubble/Panel/Margin/Tabs/Stats
@onready var voices: OptionButton = $Bubble/Panel/Margin/Tabs/Settings/Voices
@onready var current_voice: Label = $Bubble/Panel/Margin/Tabs/Settings/Current
@onready var test_button: Button = $Bubble/Panel/Margin/Tabs/Settings/Buttons/Test
@onready var apply_button: Button = $Bubble/Panel/Margin/Tabs/Settings/Buttons/Apply
@onready var mics: OptionButton = $Bubble/Panel/Margin/Tabs/Settings/MicRow/Mics
@onready var mind: Mind = $Mind
@onready var name_field: LineEdit = $Bubble/Panel/Margin/Tabs/Duck/NameRow/Name
@onready var memory_list: ItemList = $Bubble/Panel/Margin/Tabs/Duck/Memories
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
	_update_stats()


func _physics_process(delta: float) -> void:
	match state:
		State.WALK:
			_walk(speed * delta)
		State.DRAG:
			screen_position = Vector2(DisplayServer.mouse_get_position()) - _drag_offset
			_apply_position()
		State.FALL:
			_fall(fall_speed * delta)


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
		state = State.DRAG
	elif not button.pressed and button.button_index == MOUSE_BUTTON_LEFT and state == State.DRAG:
		state = State.CHAT if is_click(_press_position, Vector2(DisplayServer.mouse_get_position()), click_slop) else State.FALL


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


func _fall(distance: float) -> void:
	var area: Rect2 = usable_area()
	var floor_y: float = area.end.y - window_size().y
	screen_position.x = clampf(screen_position.x, area.position.x, area.end.x - window_size().x)
	screen_position.y = minf(screen_position.y + distance, floor_y)
	_apply_position()
	if screen_position.y >= floor_y:
		edge = Edge.BOTTOM
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
	DisplayServer.window_set_mouse_passthrough(hit_outline(window_size(), hit_size, hit_offset, duck.roll))


func _set_state(value: State) -> void:
	var was: State = state
	state = settle_state(value, brain != null and brain.is_ready())
	if not is_node_ready():
		return
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
		duck.play(&"sleep")
		bubble_text.text = "Zzz... I'm still waking up. Give me a moment and I'll be right with you."
	elif is_thinking():
		duck.play(&"think")
	else:
		# Squeak first; the greeting is shown now and said once the squeak is over.
		_greeting = greetings.pick_random() if not greetings.is_empty() else "Quack!"
		bubble_text.text = _greeting
		duck.play(&"squeeze")
		squeak.play()
	var area: Rect2 = usable_area()
	var size: Vector2 = Vector2(bubble.size)
	var above: float = screen_position.y - size.y
	var at: Vector2 = Vector2(screen_position.x + (window_size().x - size.x) / 2.0, above if above >= area.position.y else screen_position.y + window_size().y)
	at.x = clampf(at.x, area.position.x, area.end.x - size.x)
	bubble.position = Vector2i(at.round())
	bubble.show()
	bubble.grab_focus()
	bubble_input.grab_focus()


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
	stats.text = stats_text(brain.status, brain.hardware, brain.model_id, _voice_name(voice.voice_id), screen_note, brain.choice)
	# Nothing to type into until it is awake, and nothing to send while it is thinking.
	bubble_input.editable = brain.is_ready()
	send_button.disabled = not brain.is_ready() or is_thinking()
	mic_button.disabled = not brain.is_ready() or not listener.is_supported()
	bubble_input.placeholder_text = placeholder_for(listener.mode, brain.is_ready())
	_update_status()


## Reading the screen or waiting on an answer.
func is_thinking() -> bool:
	return brain.is_busy() or screen_reader.is_reading() or not _pending_line.is_empty()


## The system's voices, then the natural Kokoro ones: greyed out with a download entry above them
## until they are installed, then white like the rest.
func _fill_voices() -> void:
	voices.clear()
	var kokoro_ready: bool = voice.kokoro_ready()
	var kokoro_listed: bool = false
	for entry: Dictionary in voice.available():
		if entry.get("kokoro", false) and not kokoro_listed:
			kokoro_listed = true
			voices.add_separator("Natural voices (Kokoro)")
			if not kokoro_ready:
				var installing: bool = voice.kokoro.is_installing()
				voices.add_item("Downloading natural voices..." if installing else "Download natural voices (%d MB)" % Kokoro.download_mb())
				voices.set_item_metadata(voices.item_count - 1, DOWNLOAD_KOKORO)
				voices.set_item_disabled(voices.item_count - 1, installing)
		voices.add_item(Voice.label_for(entry) if not entry.get("kokoro", false) else entry["name"])
		voices.set_item_metadata(voices.item_count - 1, entry["id"])
		if entry.get("kokoro", false) and not kokoro_ready:
			voices.set_item_disabled(voices.item_count - 1, true)
		if entry["id"] == voice.voice_id:
			voices.select(voices.item_count - 1)
	voices.disabled = voices.item_count == 0
	if voice.kokoro != null and voice.kokoro.is_installing():
		# Stay on the download entry, which shows the progress, while it downloads.
		voices.select(_download_index())
		voices.set_item_text(_download_index(), _download_text)
	elif voices.item_count == 0:
		current_voice.text = "This system offers no text-to-speech voices."
	else:
		current_voice.text = "Speaking as: " + _voice_name(voice.voice_id)
	_update_voice_buttons()


## Test and Apply are grey unless the selected voice can speak now.
func _update_voice_buttons() -> void:
	var index: int = voices.selected
	var usable: bool = index >= 0 and not voices.is_item_disabled(index) and str(voices.get_item_metadata(index)) != DOWNLOAD_KOKORO
	test_button.disabled = not usable
	apply_button.disabled = not usable


## Choosing the download entry starts the download.
func _on_voice_selected(index: int) -> void:
	if str(voices.get_item_metadata(index)) == DOWNLOAD_KOKORO:
		voice.kokoro.install()
		_fill_voices()
		current_voice.text = "Starting the download..."
	_update_voice_buttons()


func _on_kokoro_progress(_fraction: float, text: String) -> void:
	_download_text = text
	current_voice.text = text
	if _download_index() >= 0:
		voices.set_item_text(_download_index(), text)


## The download entry's place in the voice list, or -1 once the voices are installed.
func _download_index() -> int:
	for i: int in voices.item_count:
		if str(voices.get_item_metadata(i)) == DOWNLOAD_KOKORO:
			return i
	return -1


func _on_kokoro_installed() -> void:
	_fill_voices()
	current_voice.text = "Natural voices ready: pick one."


func _on_kokoro_failed(message: String) -> void:
	_fill_voices()
	current_voice.text = message


func _fill_mics() -> void:
	mics.clear()
	# The saved choice, since AudioServer reports "Default" until the microphone first opens.
	var chosen: String = Listener.load_device(Listener.SETTINGS_PATH)
	if chosen.is_empty():
		chosen = AudioServer.input_device
	for device: String in AudioServer.get_input_device_list():
		mics.add_item(device)
		if device == chosen:
			mics.select(mics.item_count - 1)


func _on_mic_selected(index: int) -> void:
	listener.use_device(mics.get_item_text(index))


## Stands for the download entry in the voice list's metadata.
const DOWNLOAD_KOKORO: String = "kokoro:download"
## The latest download progress, shown on the download entry while it downloads.
var _download_text: String = "Downloading natural voices..."


func _voice_name(id: String) -> String:
	for entry: Dictionary in voice.available():
		if entry["id"] == id:
			return entry.get("name", id)
	return "none"


func _selected_voice() -> String:
	var id: String = str(voices.get_selected_metadata()) if voices.selected >= 0 else ""
	return "" if id == DOWNLOAD_KOKORO else id


func _on_idle_timer_timeout() -> void:
	if state == State.IDLE:
		state = State.WALK


func _on_voice_started() -> void:
	if state == State.CHAT:
		duck.play(&"talk")
		_scroll_along(_spoken)
	_update_status()


## Glides the answer from the top to the bottom over about as long as it takes to say, so a long
## answer can be read all the way through as it is spoken. The wheel still scrolls it by hand.
func _scroll_along(text: String) -> void:
	var bar: VScrollBar = bubble_text.get_v_scroll_bar()
	if _scroll_tween != null:
		_scroll_tween.kill()
	var end: float = maxf(bar.max_value - bar.page, 0.0)
	if end <= 0.0:
		return
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(bar, "value", end, scroll_seconds(text)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
		bubble_text.text = _greeting
		duck.play(&"squeeze")
		squeak.play()
		bubble_input.grab_focus()


func _on_wake_clock_timeout() -> void:
	_waking_seconds += 1
	_update_status()


func _on_brain_replied(text: String) -> void:
	bubble_text.text = ("You: %s\n\n%s" % [_last_line, text] if not _last_line.is_empty() else text) + _take_notes()
	bubble_text.scroll_to_line(0)
	_update_stats()
	if state == State.CHAT:
		_spoken = text
		_say(text)
		bubble_input.grab_focus()


func _on_test_pressed() -> void:
	voice.speak(test_line, _selected_voice())


func _on_apply_pressed() -> void:
	var id: String = _selected_voice()
	if id.is_empty():
		return
	voice.apply(id)
	current_voice.text = "Speaking as: " + _voice_name(id)
	_update_stats()


func _on_send_pressed() -> void:
	_on_input_text_submitted(bubble_input.text)


func _on_input_text_submitted(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty() or is_thinking():
		return
	bubble_input.clear()
	_send(line)


## Typed or spoken, a line goes the same way: look at the screen, then ask. A line sent before the
## brain is awake waits for it.
func _send(line: String) -> void:
	if not brain.is_ready():
		return
	_pending_line = line
	# "Your name is ...", "remember that ...": done now, so the answer already knows. After the line
	# is pending, so the note waits for the answer rather than being written over.
	mind.heed(line)
	_last_line = line
	_greeting = ""
	squeak.stop()
	voice.stop()
	listener.pause()
	bubble_text.text = "You: %s\n\nLooking at your screen..." % line
	duck.play(&"think")
	_look()
	_update_stats()


func _look() -> void:
	var window: Window = get_window()
	var own_windows: Array[Rect2i] = [Rect2i(window.position, window.size), Rect2i(bubble.position, bubble.size)]
	screen_reader.read(window.current_screen, own_windows)


func _on_screen_reader_read_finished(text: String) -> void:
	screen_note = screen_reader.last_error if not screen_reader.last_error.is_empty() else "%d characters read last time" % text.length()
	bubble_text.text = "You: %s\n\n..." % _last_line
	brain.ask(_pending_line, text)
	_pending_line = ""
	_update_stats()


## The mic turns on a conversation: talk, pause, the duck answers, then it listens again.
func _on_mic_toggled(on: bool) -> void:
	if not on:
		listener.stop()
		return
	listener.foundry_path = brain.foundry_path()
	listener.model_alias = brain.speech_name
	if listener.model_alias.is_empty():
		bubble_text.text = "No speech model fits this machine, or I am still waking up." if brain.is_ready() else "Still waking up. Try the mic again in a moment."
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
			bubble_text.text = listener.last_error
		listener.resume()
		return
	_send(text)


func _on_listener_mode_changed(_mode: Listener.Mode) -> void:
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
func _fill_mind() -> void:
	name_field.text = mind.duck_name()
	bubble.title = mind.duck_name() if not mind.duck_name().is_empty() else "Rubber Duck"
	memory_list.clear()
	for memory: String in mind.memories():
		memory_list.add_item(memory)


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


func _on_name_submitted(_text: String) -> void:
	_on_save_name_pressed()


func _on_save_name_pressed() -> void:
	if not name_field.text.strip_edges().is_empty():
		mind.set_duck_name(name_field.text)


func _on_forget_pressed() -> void:
	var selected: PackedInt32Array = memory_list.get_selected_items()
	if not selected.is_empty():
		mind.forget_at(selected[0])


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


## Whether a press and release `slop` pixels apart or closer is a click rather than a drag.
static func is_click(pressed_at: Vector2, released_at: Vector2, slop: float) -> bool:
	return pressed_at.distance_to(released_at) <= slop


## The window-space outline that takes the mouse, turned with a duck rolled `roll` degrees.
## 3D roll is anticlockwise on screen and 2D rotation clockwise, hence the minus.
static func hit_outline(window: Vector2, size: Vector2, offset: Vector2, roll: float) -> PackedVector2Array:
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
static func stats_text(status: String, hardware: String, model: String, voice_name: String, screen: String = "", choice: String = "") -> String:
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
	return "\n".join(lines)


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
static func settle_state(requested: State, ready: bool) -> State:
	if not ready and (requested == State.WALK or requested == State.IDLE):
		return State.SLEEP
	return requested


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
