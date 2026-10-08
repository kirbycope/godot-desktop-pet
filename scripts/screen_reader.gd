class_name ScreenReader
extends Node
## Reads the text on the screen with the operating system's own OCR, so the duck can see what you see.
##
## The screen is captured with DisplayServer.screen_get_image() and cut down to the window the user
## was last working in (not the duck's own), the pet's own windows are blanked out, and the picture
## goes to Windows.Media.Ocr (Windows 10 and later, nothing to install) in a PowerShell process kept
## running between reads, so neither PowerShell nor the OCR engine starts up each time. That process
## also notes which window is in front, four times a second. OCR runs on a thread; the result arrives
## through `read_finished`. Other platforms read nothing yet, and the duck is told so.

signal read_finished(text: String)

## The most screen text sent to the model, so a busy screen cannot crowd out the conversation.
@export var max_characters: int = 6000

const IMAGE_PATH: String = "user://screen.png"
## The OCR process can keep the last picture open a while, so pictures for it take turns between
## these, and the next one is never written over one still open.
const ROTATING_IMAGE: String = "user://screen_%d.png"
const TEXT_PATH: String = "user://screen.txt"
const SCRIPT_PATH: String = "user://ocr.ps1"
const SERVER_PATH: String = "user://ocr_server.ps1"

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

## The same OCR as a process that stays up: one tab-separated command a line on stdin, one answer a
## line on stdout. "ocr<TAB>image<TAB>text file" answers "ok" or "error <why>"; "window" answers
## "left top right bottom" of the last window in front that is not the duck's (process `$OwnPid`),
## in physical pixels. It waits for a command a quarter of a second at a time and notes the window
## in front in between.
const WINDOWS_OCR_SERVER: String = """param([int]$OwnPid)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await($operation, [Type]$type) { $task = $asTask.MakeGenericMethod($type).Invoke($null, @($operation)); $task.Wait() | Out-Null; $task.Result }
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class DuckFront {
	[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
	[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
	[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
	[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);
	[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[void][DuckFront]::SetProcessDPIAware()
$front = '0 0 0 0'
$pending = [Console]::In.ReadLineAsync()
while ($true) {
	$window = [DuckFront]::GetForegroundWindow()
	$owner = [uint32]0
	[void][DuckFront]::GetWindowThreadProcessId($window, [ref]$owner)
	if ($window -ne [IntPtr]::Zero -and $owner -ne $OwnPid) {
		$rect = New-Object DuckFront+RECT
		if ([DuckFront]::GetWindowRect($window, [ref]$rect)) { $front = '{0} {1} {2} {3}' -f $rect.Left, $rect.Top, $rect.Right, $rect.Bottom }
	}
	if ($pending.Wait(250)) {
		$line = $pending.Result
		if ($null -eq $line) { break }
		$parts = $line.Split("`t")
		if ($parts[0] -eq 'window') {
			[Console]::Out.WriteLine($front)
		} elseif ($parts[0] -eq 'ocr') {
			try {
				$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync([System.IO.Path]::GetFullPath($parts[1]))) ([Windows.Storage.StorageFile])
				$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
				$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
				$bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
				$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
				[System.IO.File]::WriteAllLines([System.IO.Path]::GetFullPath($parts[2]), [string[]]($result.Lines | ForEach-Object { $_.Text }), (New-Object System.Text.UTF8Encoding $false))
				$stream.Dispose()
				[Console]::Out.WriteLine('ok')
			} catch {
				[Console]::Out.WriteLine('error ' + $_.Exception.Message.Replace("`n", ' '))
			}
		}
		[Console]::Out.Flush()
		$pending = [Console]::In.ReadLineAsync()
	}
}
"""

## Why the last read came back empty, or "" when it worked.
var last_error: String = ""
var _thread: Thread = Thread.new()
## The OCR process, from OS.execute_with_pipe, and a lock so one request at a time goes down it.
var _server: Dictionary = {}
var _server_lock: Mutex = Mutex.new()
var _image: String = IMAGE_PATH
var _reads: int = 0


func _ready() -> void:
	# Started now, so the first read does not wait for PowerShell and the OCR engine to load.
	if is_supported():
		_start_server()


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	_stop_server()


func _start_server() -> bool:
	if not _server.is_empty() and OS.is_process_running(int(_server.get("pid", -1))):
		return true
	_server.clear()
	if not FileAccess.file_exists(SERVER_PATH) or FileAccess.get_file_as_string(SERVER_PATH) != WINDOWS_OCR_SERVER:
		var file: FileAccess = FileAccess.open(SERVER_PATH, FileAccess.WRITE)
		file.store_string(WINDOWS_OCR_SERVER)
		file.close()
	_server = OS.execute_with_pipe("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SERVER_PATH), str(OS.get_process_id())])
	return not _server.is_empty()


func _stop_server() -> void:
	if _server.is_empty():
		return
	var pipe: FileAccess = _server.get("stdio")
	if pipe != null:
		pipe.close()
	if OS.is_process_running(int(_server.get("pid", -1))):
		OS.kill(int(_server["pid"]))
	_server.clear()


## One command to the OCR process and its answer, or "" when it is not running.
func _ask_server(command: String) -> String:
	_server_lock.lock()
	var answer: String = ""
	var pipe: FileAccess = _server.get("stdio")
	if pipe != null and pipe.is_open():
		pipe.store_line(command)
		pipe.flush()
		answer = pipe.get_line().strip_edges()
	_server_lock.unlock()
	return answer


## The last window in front that was not the duck's, in screen coordinates, or an empty rect.
func front_window() -> Rect2i:
	if not _start_server():
		return Rect2i()
	return parse_rect(_ask_server("window"))


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
	var origin: Vector2i = DisplayServer.screen_get_position(screen)
	blank(image, blank_out, origin)
	# Only the window they were working in: no file tree from another app, no taskbar, and a
	# smaller picture to read.
	var window: Rect2i = crop_to(image.get_size(), front_window(), origin)
	if window.has_area():
		image = image.get_region(window)
	_reads += 1
	_image = ROTATING_IMAGE % (_reads % 3) if not _server.is_empty() else IMAGE_PATH
	image.save_png(_image)
	_thread.start(_recognise)


## The part of a screen image of `size` at `origin` that `window` covers, or an empty rect when it
## covers too little of the screen to be worth reading alone (under 300 by 150).
static func crop_to(size: Vector2i, window: Rect2i, origin: Vector2i) -> Rect2i:
	var local: Rect2i = Rect2i(window.position - origin, window.size).intersection(Rect2i(Vector2i.ZERO, size))
	return local if local.size.x >= 300 and local.size.y >= 150 else Rect2i()


## "left top right bottom" to a rect; empty when it is not four numbers.
static func parse_rect(text: String) -> Rect2i:
	var parts: PackedStringArray = text.split(" ", false)
	if parts.size() != 4 or not Array(parts).all(func(part: String) -> bool: return part.is_valid_int()):
		return Rect2i()
	return Rect2i(int(parts[0]), int(parts[1]), int(parts[2]) - int(parts[0]), int(parts[3]) - int(parts[1]))


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


## Lines that report an error.
## "Error" counts capitalised (TypeError, Parse Error, ERROR) or as "error:", so prose that
## mentions an error does not.
const ERROR_LINE: String = r"[A-Za-z]*Error\b|ERROR|\berror:|(?i:exception|traceback|at function:|null instance|\bundefined\b|uncaught|not a function|failed)|res://\S+:\d+|File \"[^\"]+\", line \d+"


## The screen text with what matters first: error lines at the top, then everything else minus
## noise, cut to `limit`. Noise is a line seen before, and a run of four or more short lines without
## code in them (a file tree, a menu). A small model reads the top of its input best, and the cap
## then cuts noise rather than the error.
static func focus(text: String, limit: int) -> String:
	var errors: PackedStringArray = error_lines(text)
	var rest: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	var run: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n", false):
		if line in errors or seen.has(line):
			continue
		seen[line] = true
		if is_plain_word_line(line):
			run.append(line)
			continue
		if run.size() < 4:
			rest.append_array(run)
		run.clear()
		rest.append(line)
	if run.size() < 4:
		rest.append_array(run)
	var out: String = "\n".join(rest)
	if not errors.is_empty():
		out = "Errors:\n%s\n\nThe rest of the screen:\n%s" % ["\n".join(errors), out]
	return out.left(limit)


## The lines of `text` that report an error, in order, each once.
static func error_lines(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var error: RegEx = RegEx.create_from_string(ERROR_LINE)
	for line: String in text.split("\n", false):
		if error.search(line) != null and not line in found:
			found.append(line)
	return found


## A line of one or two words with nothing of code in it: a file name in a tree, a menu entry.
static func is_plain_word_line(line: String) -> bool:
	return line.split(" ", false).size() <= 2 and RegEx.create_from_string(r"[(){}\[\]=:;\"'<>]").search(line) == null


func _recognise() -> void:
	if not FileAccess.file_exists(SCRIPT_PATH) or FileAccess.get_file_as_string(SCRIPT_PATH) != WINDOWS_OCR:
		var file: FileAccess = FileAccess.open(SCRIPT_PATH, FileAccess.WRITE)
		file.store_string(WINDOWS_OCR)
		file.close()
	if FileAccess.file_exists(TEXT_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEXT_PATH))
	var code: int = 0
	var output: Array = []
	var answer: String = _ask_server("ocr\t%s\t%s" % [ProjectSettings.globalize_path(_image), ProjectSettings.globalize_path(TEXT_PATH)]) if not _server.is_empty() else ""
	if answer != "ok":
		# The process is gone or failed: the one-off script, as before.
		code = OS.execute("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path(SCRIPT_PATH), ProjectSettings.globalize_path(_image), ProjectSettings.globalize_path(TEXT_PATH)], output, true)
	var text: String = FileAccess.get_file_as_string(TEXT_PATH) if code == 0 else ""
	set_deferred("last_error", "" if code == 0 else "OCR failed (exit %d): %s" % [code, "".join(output).strip_edges().left(300)])
	read_finished.emit.call_deferred(focus(tidy(text, 1 << 20), max_characters))
