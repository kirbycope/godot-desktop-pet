class_name ScreenReader
extends Node
## Reads the text on the screen with the operating system's own OCR, so the duck can see what you see.
##
## The screen is captured with DisplayServer.screen_get_image(), the pet's own windows are blanked out,
## and the picture goes to Windows.Media.Ocr through PowerShell (Windows 10 and later, nothing to
## install). OCR runs on a thread; the result arrives through `read_finished`. Other platforms read
## nothing yet, and the duck is told so.

signal read_finished(text: String)

## The most screen text sent to the model, so a busy screen cannot crowd out the conversation.
@export var max_characters: int = 6000

const IMAGE_PATH: String = "user://screen.png"
const TEXT_PATH: String = "user://screen.txt"
const SCRIPT_PATH: String = "user://ocr.ps1"

## WinRT OCR from PowerShell 5.1: load the image, decode it, recognise it, print one line per line.
## StorageFile refuses Godot's forward-slash paths, so the path is normalised first. The text goes to
## a UTF-8 file rather than stdout, which Godot would decode in the console's code page.
const WINDOWS_OCR: String = """param([string]$Path, [string]$Out)
$ErrorActionPreference = 'Stop'
$Path = [System.IO.Path]::GetFullPath($Path)
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($operation, [Type]$type) { $task = $asTask.MakeGenericMethod($type).Invoke($null, @($operation)); $task.Wait() | Out-Null; $task.Result }
$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Path)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
[System.IO.File]::WriteAllLines([System.IO.Path]::GetFullPath($Out), [string[]]($result.Lines | ForEach-Object { $_.Text }), (New-Object System.Text.UTF8Encoding $false))
$stream.Dispose()
"""

## Why the last read came back empty, or "" when it worked.
var last_error: String = ""
var _thread: Thread = Thread.new()


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()


static func is_supported() -> bool:
	return OS.get_name() == "Windows"


func is_reading() -> bool:
	return _thread.is_started() and _thread.is_alive()


## Captures `screen` with each rect in `blank_out` (screen coordinates) blanked, then reads it on a thread.
func read(screen: int, blank_out: Array[Rect2i]) -> void:
	if not is_supported() or is_reading():
		read_finished.emit.call_deferred("")
		return
	if _thread.is_started():
		_thread.wait_to_finish()
	var image: Image = DisplayServer.screen_get_image(screen)
	if image == null or image.is_empty():
		read_finished.emit.call_deferred("")
		return
	blank(image, blank_out, DisplayServer.screen_get_position(screen))
	image.save_png(IMAGE_PATH)
	_thread.start(_recognise)


## Fills every rect in `blank_out` with white, so the duck does not read its own bubble back to itself.
static func blank(image: Image, blank_out: Array[Rect2i], screen_origin: Vector2i) -> void:
	var bounds: Rect2i = Rect2i(Vector2i.ZERO, image.get_size())
	for rect: Rect2i in blank_out:
		var local: Rect2i = Rect2i(rect.position - screen_origin, rect.size).intersection(bounds)
		if local.has_area():
			image.fill_rect(local, Color.WHITE)


## The OCR lines as one block, blank lines dropped, cut to `limit` characters.
static func tidy(lines: String, limit: int) -> String:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in lines.split("\n", false):
		if not line.strip_edges().is_empty():
			kept.append(line.strip_edges())
	var text: String = "\n".join(kept)
	return text.left(limit) if text.length() > limit else text


func _recognise() -> void:
	if not FileAccess.file_exists(SCRIPT_PATH) or FileAccess.get_file_as_string(SCRIPT_PATH) != WINDOWS_OCR:
		var file: FileAccess = FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
		file.store_string(WINDOWS_OCR)
		file.close()
	if FileAccess.file_exists(TEXT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEXT_PATH))
	var output: Array = []
	var code: int = OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SCRIPT_PATH), ProjectSettings.globalize_path(IMAGE_PATH), ProjectSettings.globalize_path(TEXT_PATH)], output, true)
	var text: String = FileAccess.get_file_as_string(TEXT_PATH) if code == 0 else ""
	set_deferred("last_error", "" if code == 0 else "OCR failed (exit %d): %s" % [code, "".join(output).strip_edges().left(300)])
	read_finished.emit.call_deferred(tidy(text, max_characters))
