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
