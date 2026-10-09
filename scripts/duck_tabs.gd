class_name DuckTabs
extends TabContainer
## The duck's tabs: Chat, Pomodoro, Stats, Settings and Duck. The same scene sits in the PC duck's
## bubble and in the phone app. It only shows things and says what was pressed: the PC wires its
## signals to the duck itself, the phone to its link with the PC.
##
## Sizes, fonts and the chat's bubbles come from the host's theme, so the one scene is compact in
## the PC's bubble and large on a phone. The chat uses the theme type variations YourBubble and
## DuckBubble (PanelContainer) and YourText, DuckText and Note (Label).

## Typed and sent, with Enter or Send.
signal line_sent(line: String)
signal input_changed(text: String)
signal mic_toggled(on: bool)
signal new_pressed
## Past was pressed: the host answers with `show_past`.
signal past_pressed
signal conversation_chosen(id: String)
## start, pause, resume, skip or stop.
signal pomodoro_pressed(action: String)
## [focus, short break, long break] in minutes.
signal lengths_changed(minutes: Array[int])
## The Stats tab's button: stop the language model (false) or start it again (true).
signal model_toggled(run: bool)
## A voice was picked from the list, or DOWNLOAD_KOKORO, the natural voices' download entry.
signal voice_selected(id: String)
signal voice_tested(id: String)
signal voice_applied(id: String)
signal mic_chosen(device: String)
signal mute_toggled(on: bool)
signal name_saved(duck_name: String)
signal hat_toggled(on: bool)
signal memory_forgotten(index: int)
signal folder_pressed

## Stands for the natural voices' download entry in the voice list.
const DOWNLOAD_KOKORO: String = "kokoro:download"

## A chat bubble is at most this share of the chat's width, and as narrow as its text otherwise.
@export_range(0.3, 1.0) var bubble_share: float = 0.8

## The duck's bubble for the answer under way, and whether a sentence of it has arrived yet.
var _answer: Label = null
var _answer_started: bool = false
## The timer as last shown, and when, so the clock counts down between updates.
var _pomodoro: Dictionary = {}
var _pomodoro_at: int = 0
var _scroll_tween: Tween

@onready var conversation: ScrollContainer = $Chat/Conversation
@onready var messages_box: VBoxContainer = $Chat/Conversation/Messages
@onready var past_list: ItemList = $Chat/PastList
@onready var new_button: Button = $Chat/Top/New
@onready var past_button: Button = $Chat/Top/Past
@onready var input: LineEdit = $Chat/Entry/Input
@onready var send_button: Button = $Chat/Entry/Send
@onready var mic_button: Button = $Chat/Entry/Mic
@onready var mic_dot: Panel = $Chat/Entry/Mic/Dot
@onready var status: PanelContainer = $Chat/Entry/Status
@onready var status_label: Label = $Chat/Entry/Status/Row/Label
@onready var level_meter: ProgressBar = $Chat/Entry/Status/Row/Level
@onready var phase_label: Label = $Pomodoro/Phase
@onready var time_label: Label = $Pomodoro/Time
@onready var bar: ProgressBar = $Pomodoro/Bar
@onready var start_button: Button = $Pomodoro/Buttons/Start
@onready var skip_button: Button = $Pomodoro/Buttons/Skip
@onready var stop_button: Button = $Pomodoro/Buttons/Stop
@onready var focus_box: SpinBox = $Pomodoro/Lengths/Focus
@onready var short_box: SpinBox = $Pomodoro/Lengths/Short
@onready var long_box: SpinBox = $Pomodoro/Lengths/Long
@onready var tick: Timer = $Pomodoro/Tick
@onready var stats: RichTextLabel = $Stats/Text
@onready var model_button: Button = $Stats/Model
@onready var voices: OptionButton = $Settings/Voices
@onready var test_button: Button = $Settings/Buttons/Test
@onready var apply_button: Button = $Settings/Buttons/Apply
@onready var current_voice: Label = $Settings/Current
@onready var mics: OptionButton = $Settings/MicRow/Mics
@onready var mute_box: CheckBox = $Settings/Mute
@onready var pairing_label: Label = $Settings/Phone
@onready var name_field: LineEdit = $Duck/NameRow/Name
@onready var hat_box: CheckBox = $Duck/HatRow/Hat
@onready var memory_list: ItemList = $Duck/Memories
@onready var folder_button: Button = $Duck/Buttons/Folder


func _ready() -> void:
	show_pomodoro({})


# Chat

## A message in its bubble, yours on the right or the duck's on the left; returns its label, for an
## answer to grow.
func add_message(role: String, text: String) -> Label:
	var yours: bool = role == "user"
	var row: HBoxContainer = HBoxContainer.new()
	var bubble: PanelContainer = PanelContainer.new()
	var label: Label = Label.new()
	bubble.theme_type_variation = &"YourBubble" if yours else &"DuckBubble"
	label.theme_type_variation = &"YourText" if yours else &"DuckText"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(label)
	row.alignment = BoxContainer.ALIGNMENT_END if yours else BoxContainer.ALIGNMENT_BEGIN
	row.add_child(bubble)
	messages_box.add_child(row)
	_fit(label)
	scroll_to_end()
	return label


## What the duck remembered or learned on the way: small and grey, in the middle.
func add_note(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var label: Label = Label.new()
	label.theme_type_variation = &"Note"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	messages_box.add_child(label)
	scroll_to_end()


## Your line, then the duck's bubble for the answer, showing `waiting` until the answer comes.
func begin_answer(line: String, waiting: String = "...") -> void:
	if not line.is_empty():
		add_message("user", line)
	_answer = add_message("assistant", waiting)
	_answer_started = false


## The answer's bubble says `text` now: what the duck is doing before it answers, or the whole answer.
func set_answer(text: String) -> void:
	if _answer == null or not is_instance_valid(_answer):
		_answer = add_message("assistant", text)
	else:
		_answer.text = text
		_fit(_answer)
		scroll_to_end()


## A sentence of the answer: the first replaces what the bubble was saying while it waited.
func add_sentence(text: String) -> void:
	if _answer_started and _answer != null and is_instance_valid(_answer):
		set_answer(_answer.text + " " + text)
	else:
		set_answer(text)
	_answer_started = true


func answer_started() -> bool:
	return _answer_started


## A line from the duck on its own, such as its greeting.
func say(text: String) -> void:
	add_message("assistant", text)
	_answer = null
	_answer_started = false


## The conversation as it stands: [{role, content}].
func show_conversation(messages: Array) -> void:
	for child: Node in messages_box.get_children():
		child.queue_free()
	_answer = null
	_answer_started = false
	for message: Variant in messages:
		if message is Dictionary and str(message.get("role", "")) in ["user", "assistant"]:
			add_message(str(message.get("role", "")), str(message.get("content", "")))


## The past conversations, [{id, when, title}], in place of this one until one is picked or Past is
## pressed again; `current` is marked.
func show_past(items: Array, current: String) -> void:
	past_list.clear()
	for item: Variant in items:
		if item is Dictionary:
			past_list.add_item(history_line(item, current))
			past_list.set_item_metadata(past_list.item_count - 1, str(item.get("id", "")))
	if past_list.item_count == 0:
		past_list.add_item("Nothing yet: what you say starts the first one.")
		past_list.set_item_disabled(0, true)
	_show_past(true)


func scroll_to_end() -> void:
	if _scroll_tween != null:
		_scroll_tween.kill()
	await get_tree().process_frame
	if is_instance_valid(conversation):
		conversation.scroll_vertical = int(conversation.get_v_scroll_bar().max_value)


## Glides the conversation from the answer's top to the end over `seconds`, about as long as it
## takes to say, so a long answer can be read as it is spoken. The wheel still scrolls it by hand.
func glide_to_end(seconds: float) -> void:
	var scroll_bar: VScrollBar = conversation.get_v_scroll_bar()
	var end: float = maxf(scroll_bar.max_value - scroll_bar.page, 0.0)
	if _answer == null or not is_instance_valid(_answer) or end <= 0.0:
		return
	var top: float = minf(_answer.get_parent().get_parent().position.y, end)
	scroll_bar.value = top
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(scroll_bar, "value", end, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## A bubble as wide as its text, up to `bubble_share` of the chat.
func _fit(label: Label) -> void:
	var font: Font = label.get_theme_font("font")
	var size: int = label.get_theme_font_size("font_size")
	var widest: float = 0.0
	for line: String in label.text.split("\n"):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
	var panel: StyleBox = (label.get_parent() as Control).get_theme_stylebox("panel")
	var padding: float = panel.get_margin(SIDE_LEFT) + panel.get_margin(SIDE_RIGHT) if panel != null else 0.0
	var room: float = maxf(conversation.size.x, 200.0) * bubble_share - padding
	label.custom_minimum_size.x = bubble_width(widest, room)


func _show_past(on: bool) -> void:
	past_list.visible = on
	conversation.visible = not on
	past_button.set_pressed_no_signal(on)


func _on_input_text_submitted(text: String) -> void:
	_send(text)


func _on_send_pressed() -> void:
	_send(input.text)


func _send(text: String) -> void:
	var line: String = text.strip_edges()
	if line.is_empty() or send_button.disabled or not input.editable:
		return
	input.clear()
	line_sent.emit(line)


func _on_input_text_changed(text: String) -> void:
	input_changed.emit(text)


func _on_mic_toggled(on: bool) -> void:
	mic_toggled.emit(on)


func _on_new_pressed() -> void:
	_show_past(false)
	new_pressed.emit()


func _on_past_toggled(on: bool) -> void:
	if on:
		past_pressed.emit()
	else:
		_show_past(false)


func _on_past_list_item_selected(index: int) -> void:
	var id: String = str(past_list.get_item_metadata(index))
	_show_past(false)
	if not id.is_empty():
		conversation_chosen.emit(id)


# Pomodoro

## The timer as Pomodoro.state() gives it; {} for one not running. The clock counts down from here
## until the next.
func show_pomodoro(state: Dictionary) -> void:
	_pomodoro = state
	_pomodoro_at = Time.get_ticks_msec()
	var minutes: Array[int] = Pomodoro.clamped_lengths(state.get("lengths", Pomodoro.DEFAULT_LENGTHS))
	focus_box.set_value_no_signal(minutes[0])
	short_box.set_value_no_signal(minutes[1])
	long_box.set_value_no_signal(minutes[2])
	if _ticking():
		tick.start()
	else:
		tick.stop()
	_show_clock()


## Seconds left in the phase shown, counted down since it was shown.
func pomodoro_left() -> float:
	var left: float = float(_pomodoro.get("left", 0.0))
	if _ticking():
		left -= (Time.get_ticks_msec() - _pomodoro_at) / 1000.0
	return maxf(left, 0.0)


func _ticking() -> bool:
	return bool(_pomodoro.get("running", false)) and not bool(_pomodoro.get("paused", false))


func _show_clock() -> void:
	var running: bool = bool(_pomodoro.get("running", false))
	var paused: bool = bool(_pomodoro.get("paused", false))
	var length: float = float(_pomodoro.get("length", 0.0))
	phase_label.text = str(_pomodoro.get("title", "Not running")) + (" (paused)" if paused else "")
	time_label.text = Pomodoro.clock(ceili(pomodoro_left()) if running else int(focus_box.value) * 60)
	bar.value = 1.0 - pomodoro_left() / length if running and length > 0.0 else 0.0
	start_button.text = "Start" if not running else ("Resume" if paused else "Pause")
	skip_button.disabled = not running
	stop_button.disabled = not running


func _on_tick_timeout() -> void:
	_show_clock()


func _on_start_pressed() -> void:
	var running: bool = bool(_pomodoro.get("running", false))
	pomodoro_pressed.emit("start" if not running else ("resume" if bool(_pomodoro.get("paused", false)) else "pause"))


func _on_skip_pressed() -> void:
	pomodoro_pressed.emit("skip")


func _on_stop_pressed() -> void:
	pomodoro_pressed.emit("stop")


func _on_length_changed(_value: float) -> void:
	lengths_changed.emit([int(focus_box.value), int(short_box.value), int(long_box.value)] as Array[int])


# Stats

## The model button: Stop while a model runs, Start once it has been stopped, and grey while one is
## loading (stopping it then would wait on a download) or when there is none to run.
func show_model(running: bool, stopped: bool) -> void:
	model_button.text = "Start the model" if stopped else "Stop the model"
	model_button.disabled = not running and not stopped


func _on_model_pressed() -> void:
	model_toggled.emit(model_button.text == "Start the model")


# Settings

## The voices to choose from, as `voice_items` makes them, the one chosen, and the line under them.
func show_voices(items: Array, chosen: String, note: String) -> void:
	voices.clear()
	for item: Variant in items:
		if not item is Dictionary:
			continue
		if bool(item.get("separator", false)):
			voices.add_separator(str(item.get("text", "")))
			continue
		voices.add_item(str(item.get("text", "")))
		voices.set_item_metadata(voices.item_count - 1, str(item.get("id", "")))
		voices.set_item_disabled(voices.item_count - 1, bool(item.get("disabled", false)))
		if str(item.get("id", "")) == chosen:
			voices.select(voices.item_count - 1)
	voices.disabled = voices.item_count == 0
	current_voice.text = note
	_update_voice_buttons()


## The line under the voices, such as the download's progress, also shown on the download entry.
func show_voice_note(note: String, on_download_entry: bool = false) -> void:
	current_voice.text = note
	if on_download_entry:
		for i: int in voices.item_count:
			if str(voices.get_item_metadata(i)) == DOWNLOAD_KOKORO:
				voices.set_item_text(i, note)


## The voice picked in the list, "" for none or the download entry.
func selected_voice() -> String:
	var id: String = str(voices.get_selected_metadata()) if voices.selected >= 0 else ""
	return "" if id == DOWNLOAD_KOKORO else id


func show_mics(devices: PackedStringArray, chosen: String) -> void:
	mics.clear()
	for device: String in devices:
		mics.add_item(device)
		if device == chosen:
			mics.select(mics.item_count - 1)


## Test and Apply are grey unless the selected voice can speak now.
func _update_voice_buttons() -> void:
	var index: int = voices.selected
	var usable: bool = index >= 0 and not voices.is_item_disabled(index) and str(voices.get_item_metadata(index)) != DOWNLOAD_KOKORO
	test_button.disabled = not usable
	apply_button.disabled = not usable


func _on_voices_item_selected(index: int) -> void:
	voice_selected.emit(str(voices.get_item_metadata(index)))
	_update_voice_buttons()


func _on_test_pressed() -> void:
	voice_tested.emit(selected_voice())


func _on_apply_pressed() -> void:
	if not selected_voice().is_empty():
		voice_applied.emit(selected_voice())


func _on_mics_item_selected(index: int) -> void:
	mic_chosen.emit(mics.get_item_text(index))


func _on_mute_toggled(on: bool) -> void:
	mute_toggled.emit(on)


# Duck

func show_duck(duck_name: String, memories: PackedStringArray) -> void:
	name_field.text = duck_name
	memory_list.clear()
	for memory: String in memories:
		memory_list.add_item(memory)


func show_hat(on: bool) -> void:
	hat_box.set_pressed_no_signal(on)


func _on_name_submitted(_text: String) -> void:
	_save_name()


func _on_save_name_pressed() -> void:
	_save_name()


func _save_name() -> void:
	if not name_field.text.strip_edges().is_empty():
		name_saved.emit(name_field.text.strip_edges())


func _on_hat_toggled(on: bool) -> void:
	hat_toggled.emit(on)


func _on_forget_pressed() -> void:
	var selected: PackedInt32Array = memory_list.get_selected_items()
	if not selected.is_empty():
		memory_forgotten.emit(selected[0])


func _on_folder_pressed() -> void:
	folder_pressed.emit()


## The entries of the voice list from Voice.available(): the system's voices, then the natural
## Kokoro ones under their own heading, greyed out with a download entry above them until they are
## installed. Each is {id, text, disabled}, or {separator, text} for the heading.
static func voice_items(available: Array, kokoro_ready: bool, installing: bool, download_text: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var kokoro_listed: bool = false
	for entry: Variant in available:
		if not entry is Dictionary:
			continue
		var kokoro: bool = bool(entry.get("kokoro", false))
		if kokoro and not kokoro_listed:
			kokoro_listed = true
			items.append({"separator": true, "text": "Natural voices (Kokoro)"})
			if not kokoro_ready:
				items.append({"id": DOWNLOAD_KOKORO, "text": download_text, "disabled": installing})
		items.append({"id": str(entry.get("id", "")), "text": str(entry.get("name", "")) if kokoro else Voice.label_for(entry), "disabled": kokoro and not kokoro_ready})
	return items


## A past conversation in the list: when it began and what you said first; the one under way marked.
static func history_line(found_one: Dictionary, current: String) -> String:
	var line: String = "%s   %s" % [found_one.get("when", ""), found_one.get("title", "")]
	return line + "   (now)" if str(found_one.get("id", "")) == current else line


## How wide a bubble's text is: as wide as the text, but no wider than `room`.
static func bubble_width(text_width: float, room: float) -> float:
	return minf(ceilf(text_width) + 2.0, room)
