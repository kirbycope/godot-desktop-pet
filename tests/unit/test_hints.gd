extends GutTest
## The checks done in code before the model sees a bug. Each must fire on its slip and stay quiet on
## a screen with nothing wrong: tests/fixtures/ocr_editor.txt is real OCR of an editor.


func test_a_node_path_spelt_differently_from_the_scene_is_pointed_out() -> void:
	var screen: String = "@onready var sprite: Sprite2D = $Sprit\nScene  Player (CharacterBody2D)  Sprite (Sprite2D)"
	assert_eq(Hints.misspelt_names(screen), PackedStringArray(["`$Sprit` appears only here, but `Sprite` is on screen too: is it spelt right?"]))
	assert_eq(Hints.misspelt_names("@onready var sprite: Sprite2D = $Sprite\nSprite (Sprite2D)"), PackedStringArray(), "spelt right")


func test_a_misspelt_property_is_pointed_out() -> void:
	var screen: String = "const item = { name: \"Duck\", price: 4 };\nconst total = item.prise * 2;"
	assert_string_contains(Hints.misspelt_names(screen)[0], "`prise` appears only here, but `price`")


func test_a_plural_or_a_case_change_is_not_a_typo() -> void:
	assert_eq(Hints.closest("enemie", ["enemies"]), "", "an added s is left alone")
	assert_eq(Hints.closest("Player", ["player"]), "", "case only")


func test_distance_counts_edits() -> void:
	assert_eq(Hints.distance("Sprit", "Sprite"), 1)
	assert_eq(Hints.distance("prise", "price"), 1)
	assert_eq(Hints.distance("kitten", "sitting"), 3)


func test_a_fetch_without_await_is_pointed_out() -> void:
	assert_eq(Hints.unawaited_fetch("const res = fetch(url);\nconst data = await res.json();").size(), 1)
	assert_eq(Hints.unawaited_fetch("const res = await fetch(url);").size(), 0)
	assert_eq(Hints.unawaited_fetch("const p = fetch(url);\np.then(r => r.json())").size(), 0, "handled with then")


func test_godot_3_syntax_is_named() -> void:
	var found: PackedStringArray = Hints.godot_3("onready var anim = $AnimationPlayer\nexport var speed = 5\nyield(anim, \"animation_finished\")\nhit.connect(\"hit\", self, \"_on_hit\")\nvar e = scene.instance()")
	assert_eq(found.size(), 5)
	assert_eq(Hints.godot_3("@onready var anim = $AnimationPlayer\nawait anim.animation_finished\nscene.instantiate()").size(), 0)


func test_a_range_one_past_the_end() -> void:
	assert_string_contains(Hints.one_past_the_end("for i in range(len(names) + 1):")[0], "one past the last index of `names`")
	assert_eq(Hints.one_past_the_end("for i in range(len(names)):").size(), 0)


func test_a_flag_set_and_never_set_back() -> void:
	var said: String = "After the wave I set get_tree().paused = true and later Engine.time_scale = 1."
	assert_eq(Hints.never_set_back(said, said), PackedStringArray(["`get_tree().paused` is set to true, and nothing they said or showed sets it back to false."]))
	assert_eq(Hints.never_set_back(said, said + "\nget_tree().paused = false").size(), 0)


func test_the_error_location_is_read_from_a_traceback_or_the_debugger() -> void:
	assert_eq(Hints.error_location("  File \"names.py\", line 3, in <module>"), PackedStringArray(["The error points at names.py line 3."]))
	assert_eq(Hints.error_location("res://player.gd:5 - at function: _ready"), PackedStringArray(["The error points at res://player.gd line 5."]))


func test_a_screen_with_nothing_wrong_gets_no_hints() -> void:
	var screen: String = FileAccess.get_file_as_string("res://tests/fixtures/ocr_editor.txt")
	assert_gt(screen.length(), 1000)
	assert_eq(Hints.for_text(screen, "why doesn't this work?"), PackedStringArray())
