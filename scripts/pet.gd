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
enum State { WALK, IDLE, DRAG, FALL, CHAT }

@export var speed: float = 60.0
@export var fall_speed: float = 700.0
## Chance of stopping for a rest at a bottom corner, as in the original project.
@export_range(0.0, 1.0) var idle_chance: float = 0.3
## Chance of climbing round a corner rather than turning back.
@export_range(0.0, 1.0) var climb_chance: float = 0.5
## How far the mouse may move between press and release for it still to count as a click.
@export var click_slop: float = 4.0
## Said aloud and shown when the bubble opens; one is picked at random each time.
@export var greetings: Array[String] = [
	"Quack! What are we debugging?", "Hi! Walk me through it.", "Quack. Tell me what it should do.",
	"Oh, hello! What's broken?", "Ready to listen. Start from the top.", "Quack quack! Show me the code.",
	"I'm all ears. Well, no ears. But listening!", "Explain it to me like I'm a duck.",
	"Hi again! Where does it go wrong?", "Quack! What did you expect, and what happened?",
]
## What the Test button says in the voice being tried.
@export var test_line: String = "Quack! I'm your rubber duck. Is this how you want me to sound?"

var edge: Edge = Edge.BOTTOM
## +1 is rightwards on the top and bottom edges and downwards on the sides.
var direction: int = 1
var state: State = State.WALK:
	set = _set_state
var screen_position: Vector2 = Vector2.ZERO
## What the last look at the screen found, for the Stats tab; "" before the first look.
var screen_note: String = ""
var _drag_offset: Vector2 = Vector2.ZERO
var _press_position: Vector2 = Vector2.ZERO
var _pending_line: String = ""

@onready var duck: Duck = $View/Viewport/Duck
@onready var hit_area: Area2D = $Body
@onready var hit_shape: CollisionShape2D = $Body/Shape
@onready var idle_timer: Timer = $IdleTimer
@onready var brain: Brain = $Brain
@onready var voice: Voice = $Voice
@onready var screen_reader: ScreenReader = $ScreenReader
@onready var bubble: Window = $Bubble
@onready var tabs: TabContainer = $Bubble/Panel/Margin/Tabs
@onready var bubble_text: RichTextLabel = $Bubble/Panel/Margin/Tabs/Chat/Text
@onready var bubble_input: LineEdit = $Bubble/Panel/Margin/Tabs/Chat/Entry/Input
@onready var send_button: Button = $Bubble/Panel/Margin/Tabs/Chat/Entry/Send
@onready var stats: RichTextLabel = $Bubble/Panel/Margin/Tabs/Stats
@onready var voices: OptionButton = $Bubble/Panel/Margin/Tabs/Settings/Voices
@onready var current_voice: Label = $Bubble/Panel/Margin/Tabs/Settings/Current
@onready var menu: PopupMenu = $Menu


func _ready() -> void:
	var area: Rect2 = usable_area()
	screen_position = Vector2(area.get_center().x - window_size().x / 2.0, area.end.y - window_size().y)
	_apply_position()
	_play_for_edge()
	_fill_voices()
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


func _input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if state != State.DRAG or button == null or button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return
	if Vector2(DisplayServer.mouse_get_position()).distance_to(_press_position) <= click_slop:
		state = State.CHAT
	else:
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


## Turns the duck, its click area and the window's mouse passthrough to stand on `on_edge`.
func _stand_on(on_edge: Edge) -> void:
	duck.roll = roll_for(on_edge)
	# 3D roll is counter-clockwise on screen; 2D rotation is clockwise, hence the minus.
	hit_area.rotation = -deg_to_rad(duck.roll)
	# Only the duck takes the mouse; clicks on the empty rest of the window go through to the desktop.
	var half: Vector2 = (hit_shape.shape as RectangleShape2D).size / 2.0
	var to_screen: Transform2D = hit_area.transform * hit_shape.transform
	DisplayServer.window_set_mouse_passthrough(to_screen * PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y),
	]))


func _set_state(value: State) -> void:
	var was: State = state
	state = value
	if not is_node_ready():
		return
	match value:
		State.WALK:
			_play_for_edge()
		State.IDLE:
			if was != State.FALL:
				duck.play([&"idle", &"cheer", &"think"].pick_random())
				idle_timer.start(randf_range(1.0, 3.0))
		State.DRAG:
			_stand_on(Edge.BOTTOM)
			duck.play(&"hang")
		State.FALL:
			duck.play(&"fall")
		State.CHAT:
			_open_bubble()
	if was == State.CHAT and value != State.CHAT:
		voice.stop()
		bubble.hide()


func _open_bubble() -> void:
	tabs.current_tab = 0
	_update_stats()
	if brain.is_busy() or screen_reader.is_reading():
		duck.play(&"think")
	else:
		var greeting: String = greetings.pick_random() if not greetings.is_empty() else "Quack!"
		bubble_text.text = greeting
		_say(greeting)
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
	duck.play(&"talk")
	if voice.voice_id.is_empty():
		idle_timer.start(1.5)
	voice.speak(text)


## The Stats tab, and whether the chat input is open yet.
func _update_stats() -> void:
	stats.text = stats_text(brain.status, brain.hardware, brain.model_id, _voice_name(voice.voice_id), screen_note)
	var open: bool = brain.is_ready() and not brain.is_busy() and not screen_reader.is_reading()
	bubble_input.editable = open
	send_button.disabled = not open
	bubble_input.placeholder_text = "Explain your code, then Enter" if brain.is_ready() else brain.status.get_slice("\n", 0)


func _fill_voices() -> void:
	voices.clear()
	for entry: Dictionary in voice.available():
		voices.add_item(Voice.label_for(entry))
		voices.set_item_metadata(voices.item_count - 1, entry["id"])
		if entry["id"] == voice.voice_id:
			voices.select(voices.item_count - 1)
	voices.disabled = voices.item_count == 0
	current_voice.text = "Speaking as: " + _voice_name(voice.voice_id) if voices.item_count > 0 else "This system offers no text-to-speech voices."


func _voice_name(id: String) -> String:
	for entry: Dictionary in voice.available():
		if entry["id"] == id:
			return entry.get("name", id)
	return "none"


func _selected_voice() -> String:
	return voices.get_selected_metadata() if voices.selected >= 0 else ""


func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		menu.position = DisplayServer.mouse_get_position()
		menu.popup()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		if state == State.CHAT:
			state = State.WALK
			return
		_press_position = Vector2(DisplayServer.mouse_get_position())
		_drag_offset = _press_position - screen_position
		state = State.DRAG


func _on_idle_timer_timeout() -> void:
	if state == State.IDLE:
		state = State.WALK
	elif state == State.CHAT and duck.animation == &"talk":
		duck.play(&"idle")


func _on_voice_finished() -> void:
	if state == State.CHAT and duck.animation == &"talk":
		duck.play(&"idle")


func _on_brain_status_changed(_text: String) -> void:
	_update_stats()


func _on_brain_replied(text: String) -> void:
	bubble_text.text = text
	_update_stats()
	if state == State.CHAT:
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


## Looks at the screen first; the line goes to the brain once the screen has been read.
func _on_input_text_submitted(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty() or brain.is_busy() or screen_reader.is_reading():
		return
	_pending_line = line
	bubble_input.clear()
	bubble_text.text = "Looking at your screen..."
	duck.play(&"think")
	var window: Window = get_window()
	var own_windows: Array[Rect2i] = [Rect2i(window.position, window.size), Rect2i(bubble.position, bubble.size)]
	screen_reader.read(window.current_screen, own_windows)
	_update_stats()


func _on_screen_reader_read_finished(text: String) -> void:
	screen_note = screen_reader.last_error if not screen_reader.last_error.is_empty() else "%d characters read last time" % text.length()
	bubble_text.text = "..."
	brain.ask(_pending_line, text)
	_update_stats()


func _on_bubble_window_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		state = State.WALK


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
static func stats_text(status: String, hardware: String, model: String, voice_name: String, screen: String = "") -> String:
	var lines: PackedStringArray = PackedStringArray([status])
	if not hardware.is_empty():
		lines.append(hardware)
	if not model.is_empty():
		lines.append("Model: " + model)
	lines.append("Voice: " + voice_name)
	if not screen.is_empty():
		lines.append("Screen: " + screen)
	return "\n".join(lines)


static func animation_for(on_edge: Edge) -> StringName:
	match on_edge:
		Edge.BOTTOM:
			return &"walk"
		Edge.TOP:
			return &"hang"
	return &"climb"
