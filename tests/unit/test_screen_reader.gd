extends GutTest


func test_blanks_the_pets_own_windows() -> void:
	var image: Image = Image.create_empty(100, 80, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	# A second monitor at x 1920: the rects are in screen space, the image is not.
	ScreenReader.blank(image, [Rect2i(1930, 10, 20, 20), Rect2i(2000, 70, 50, 50)] as Array[Rect2i], Vector2i(1920, 0))
	assert_eq(image.get_pixel(15, 15), Color.WHITE, "inside the first window")
	assert_eq(image.get_pixel(85, 75), Color.WHITE, "the part of the second window on this screen")
	assert_eq(image.get_pixel(50, 40), Color.BLACK, "the rest of the screen is untouched")


func test_windows_off_this_screen_are_ignored() -> void:
	var image: Image = Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLACK)
	ScreenReader.blank(image, [Rect2i(-500, -500, 20, 20)] as Array[Rect2i], Vector2i.ZERO)
	assert_eq(image.get_pixel(0, 0), Color.BLACK)


func test_tidy_drops_blank_lines_and_trims() -> void:
	assert_eq(ScreenReader.tidy("  func _ready():\r\n\n   pass  \n\n", 100), "func _ready():\npass")


func test_tidy_caps_the_length() -> void:
	assert_eq(ScreenReader.tidy("abcdefghij", 4), "abcd")


func test_only_windows_has_ocr_for_now() -> void:
	assert_eq(ScreenReader.is_supported(), OS.get_name() == "Windows")


func test_the_ocr_script_uses_the_built_in_engine() -> void:
	assert_string_contains(ScreenReader.WINDOWS_OCR, "Windows.Media.Ocr.OcrEngine")
	assert_string_contains(ScreenReader.WINDOWS_OCR, "TryCreateFromUserProfileLanguages")


func test_the_ocr_script_turns_godot_paths_into_windows_paths() -> void:
	# GetFileFromPathAsync fails on C:/Users/... with "One or more errors occurred".
	assert_string_contains(ScreenReader.WINDOWS_OCR, "[System.IO.Path]::GetFullPath($Path)")


func test_focus_puts_the_error_first_and_drops_a_file_tree() -> void:
	var screen: String = "addons\nscenes\nscripts\ntests\nREADME.md\nfunc _ready() -> void:\n    sprite.modulate = Color.RED\nInvalid assignment on a base object of type 'null instance'.\nres://player.gd:5 - at function: _ready\nfunc _ready() -> void:"
	var focused: String = ScreenReader.focus(screen, 6000)
	assert_string_starts_with(focused, "Errors:\nInvalid assignment on a base object of type 'null instance'.\nres://player.gd:5 - at function: _ready\n\nThe rest of the screen:\nfunc _ready() -> void:")
	assert_false("scenes" in focused, "a run of file names is noise")
	assert_eq(focused.count("func _ready() -> void:"), 1, "a line seen before is dropped")
	assert_eq(ScreenReader.focus("abcdefghij", 4), "abcd")


func test_error_lines_are_errors_not_prose() -> void:
	assert_eq(ScreenReader.error_lines("TypeError: res.json is not a function\nI think the error is here\nParse Error: yield was removed"), PackedStringArray(["TypeError: res.json is not a function", "Parse Error: yield was removed"]))
	assert_lte(ScreenReader.error_lines(FileAccess.get_file_as_string("res://tests/fixtures/ocr_editor.txt")).size(), 1, "a real editor with no error shows next to none")


func test_the_window_in_front_comes_as_four_numbers() -> void:
	assert_eq(ScreenReader.parse_rect("-8 -8 1928 1160"), Rect2i(-8, -8, 1936, 1168), "a maximised window hangs over the edges")
	assert_eq(ScreenReader.parse_rect("0 0 0 0"), Rect2i(), "none yet")
	assert_eq(ScreenReader.parse_rect("error nope"), Rect2i())


func test_the_picture_is_cut_to_the_window_in_front() -> void:
	assert_eq(ScreenReader.crop_to(Vector2i(1920, 1200), Rect2i(-8, -8, 1936, 1168), Vector2i.ZERO), Rect2i(0, 0, 1920, 1160), "kept inside the screen")
	assert_eq(ScreenReader.crop_to(Vector2i(1920, 1200), Rect2i(2000, 100, 800, 600), Vector2i(1920, 0)), Rect2i(80, 100, 800, 600), "on a second screen")
	assert_eq(ScreenReader.crop_to(Vector2i(1920, 1200), Rect2i(100, 100, 200, 80), Vector2i.ZERO), Rect2i(), "too small to read alone: the whole screen")
	assert_eq(ScreenReader.crop_to(Vector2i(1920, 1200), Rect2i(), Vector2i.ZERO), Rect2i(), "no window known")
