class_name Kokoro
extends Node
## Natural voices: the open Kokoro model (82M parameters, Apache 2.0) run offline through sherpa-onnx.
##
## Nothing is downloaded until asked. `install` fetches sherpa-onnx's command-line tools for this
## platform and the full-precision Kokoro v1.0 model into user://kokoro and unpacks them with the
## system's `tar` (in Windows 10 and later, and macOS). `speak` writes the line to a WAV on a worker
## thread and plays it.
##
## sherpa-onnx's own command-line tool loads the model for every line, about a second each time, so
## the duck keeps it loaded in kokoro-server (tools/kokoro_server, built into bin/), one process
## that answers line after line: 0.3 to 1 s a reply instead of 1.4 to 2.2. Where that is missing,
## as on macOS until it is built there, the command-line tool is used instead. The int8 build of the model is smaller but measured four times slower on a
## desktop CPU (Ryzen 9 7845HX: 4.6 s against 1.1 s for 4.8 s of speech), so the full one is used.

signal install_progress(fraction: float, text: String)
signal installed
signal install_failed(message: String)
## Sound has begun: synthesis takes a second or two, so this comes after `speak`.
signal started
## A line finished playing. Not sent when it was stopped.
signal finished

const ROOT: String = "user://kokoro"
const MODEL_FOLDER: String = "kokoro-multi-lang-v1_0"
const MODEL_URL: String = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-multi-lang-v1_0.tar.bz2"
const MODEL_MB: int = 333
const SHERPA_VERSION: String = "1.13.8"
## sherpa-onnx's prebuilt tools per platform: [folder in the archive, download size in MB].
const SHERPA: Dictionary = {
	"Windows": ["sherpa-onnx-v1.13.8-win-x64-shared-MD-Release", 19],
	"macOS": ["sherpa-onnx-v1.13.8-osx-universal2-shared", 41],
}
## Kokoro v1.0's English speakers, by id: [name, accent, gender]. Ids 28 and up are other languages.
const VOICES: Array = [
	["Alloy", "US", "female"], ["Aoede", "US", "female"], ["Bella", "US", "female"], ["Heart", "US", "female"],
	["Jessica", "US", "female"], ["Kore", "US", "female"], ["Nicole", "US", "female"], ["Nova", "US", "female"],
	["River", "US", "female"], ["Sarah", "US", "female"], ["Sky", "US", "female"],
	["Adam", "US", "male"], ["Echo", "US", "male"], ["Eric", "US", "male"], ["Fenrir", "US", "male"],
	["Liam", "US", "male"], ["Michael", "US", "male"], ["Onyx", "US", "male"], ["Puck", "US", "male"], ["Santa", "US", "male"],
	["Alice", "GB", "female"], ["Emma", "GB", "female"], ["Isabella", "GB", "female"], ["Lily", "GB", "female"],
	["Daniel", "GB", "male"], ["Fable", "GB", "male"], ["George", "GB", "male"], ["Lewis", "GB", "male"],
]

## CPU threads for synthesis; 8 was quickest on a 12-core laptop.
@export var threads: int = 8

var _installing: bool = false
var _steps: Array = []
var _step: int = -1
var _thread: Thread = Thread.new()
## Sentences queued to say, in order: {index, done, stream}. `_batch` changes on stop, so a
## sentence synthesised for an answer that was cut off is thrown away.
var _pending: Array[Dictionary] = []
var _queued: int = 0
var _batch: int = 0
var _server: Dictionary = {}
var _server_lock: Mutex = Mutex.new()

@onready var download: HTTPRequest = $Download
@onready var speaker: AudioStreamPlayer = $Speaker
@onready var progress_clock: Timer = $ProgressClock


func _exit_tree() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
	_stop_server()


static func is_platform_supported() -> bool:
	return SHERPA.has(OS.get_name())


func is_installed() -> bool:
	return is_platform_supported() and FileAccess.file_exists(exe_path()) and FileAccess.file_exists(model_path().path_join("model.onnx"))


func is_installing() -> bool:
	return _installing


static func download_mb() -> int:
	return MODEL_MB + (SHERPA[OS.get_name()][1] if is_platform_supported() else 0)


func exe_path() -> String:
	var tool: String = "sherpa-onnx-offline-tts.exe" if OS.get_name() == "Windows" else "sherpa-onnx-offline-tts"
	return ROOT.path_join(SHERPA.get(OS.get_name(), [""])[0]).path_join("bin").path_join(tool)


## Where kokoro-server goes: beside sherpa-onnx's C library, which it needs.
func server_path() -> String:
	var tool: String = "kokoro-server.exe" if OS.get_name() == "Windows" else "kokoro-server"
	return ROOT.path_join(SHERPA.get(OS.get_name(), [""])[0]).path_join("lib").path_join(tool)


## The built kokoro-server for this platform, in the project's bin/.
static func bundled_server() -> String:
	return "res://bin/windows/kokoro-server.exe" if OS.get_name() == "Windows" else "res://bin/macos/kokoro-server"


func model_path() -> String:
	return ROOT.path_join(MODEL_FOLDER)


static func sherpa_url(folder: String) -> String:
	return "https://github.com/k2-fsa/sherpa-onnx/releases/download/v%s/%s.tar.bz2" % [SHERPA_VERSION, folder]


## Downloads and unpacks whatever is missing; progress, then `installed` or `install_failed`.
func install() -> void:
	if _installing or is_installed() or not is_platform_supported():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	_steps.clear()
	var tools: Array = SHERPA[OS.get_name()]
	if not FileAccess.file_exists(exe_path()):
		_steps.append([sherpa_url(tools[0]), "sherpa-onnx.tar.bz2", tools[1]])
	if not FileAccess.file_exists(model_path().path_join("model.onnx")):
		_steps.append([MODEL_URL, "kokoro.tar.bz2", MODEL_MB])
	_installing = true
	_step = -1
	_next_step()


func _next_step() -> void:
	_step += 1
	if _step >= _steps.size():
		_installing = false
		if is_installed():
			installed.emit()
		else:
			install_failed.emit("The download unpacked, but the voice files are not where they should be.")
		return
	download.download_file = ProjectSettings.globalize_path(ROOT.path_join(_steps[_step][1]))
	if download.request(_steps[_step][0]) != OK:
		_fail("Could not start the download.")
		return
	progress_clock.start()
	_on_progress_clock_timeout()


## Progress is read off the request while it runs; nothing reports it unasked.
func _on_progress_clock_timeout() -> void:
	var total: float = 0.0
	var done: float = 0.0
	for i: int in _steps.size():
		total += _steps[i][2]
		if i < _step:
			done += _steps[i][2]
	done += download.get_downloaded_bytes() / 1048576.0
	install_progress.emit(clampf(done / maxf(total, 1.0), 0.0, 1.0), "Downloading: %d of %d MB" % [int(done), int(total)])


func _on_download_request_completed(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	progress_clock.stop()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("The download failed (%s). Check the internet connection and try again." % (("HTTP %d" % code) if result == HTTPRequest.RESULT_SUCCESS else "error %d" % result))
		return
	install_progress.emit(float(_step + 1) / _steps.size(), "Unpacking natural voices...")
	if _thread.is_started():
		_thread.wait_to_finish()
	_thread.start(_unpack.bind(ProjectSettings.globalize_path(ROOT.path_join(_steps[_step][1]))))


## On the thread: unpacks an archive into the folder and deletes it.
func _unpack(archive: String) -> void:
	var output: Array = []
	var code: int = OS.execute("tar", ["-xjf", archive, "-C", ProjectSettings.globalize_path(ROOT)], output, true)
	DirAccess.remove_absolute(archive)
	_unpacked.call_deferred(code, "".join(output).strip_edges().left(200))


func _unpacked(code: int, output: String) -> void:
	_thread.wait_to_finish()
	if code != 0:
		_fail("Unpacking failed: " + output)
		return
	_place_server()
	_next_step()


## Copies kokoro-server next to sherpa-onnx's library, when this platform has one built.
func _place_server() -> void:
	if FileAccess.file_exists(server_path()) or not FileAccess.file_exists(bundled_server()):
		return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(server_path().get_base_dir())):
		var file: FileAccess = FileAccess.open(server_path(), FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(bundled_server()))
		file.close()


func _fail(message: String) -> void:
	_installing = false
	install_failed.emit(message)


## Says `text` in English voice `sid` (0 to 27), cutting off anything still being said.
func speak(text: String, sid: int) -> void:
	stop()
	add(text, sid)


## Says `text` after whatever is queued already. Each sentence of a streamed answer comes this way:
## it is synthesised at once, while the one before is still playing, and played in turn.
func add(text: String, sid: int) -> void:
	if not is_installed() or sid < 0 or sid >= VOICES.size() or text.strip_edges().is_empty():
		return
	var index: int = _queued
	_queued += 1
	var wav: String = ProjectSettings.globalize_path(ROOT.path_join("say_%d.wav" % (index % 8)))
	_pending.append({"index": index, "done": false, "stream": null})
	if _start_server():
		WorkerThreadPool.add_task(_ask_server.bind(request(sid, text, wav), wav, _batch, index))
	else:
		var command: PackedStringArray = args(ProjectSettings.globalize_path(model_path()), sid, text, wav, threads)
		WorkerThreadPool.add_task(_synthesize.bind(ProjectSettings.globalize_path(exe_path()), command, wav, _batch, index))


## Loads the model in the background ahead of the first line, so that line comes quickly.
func warm_up(sid: int) -> void:
	if is_installed() and _start_server():
		var wav: String = ProjectSettings.globalize_path(ROOT.path_join("warm_up.wav"))
		WorkerThreadPool.add_task(_ask_server.bind(request(sid, ".", wav), wav, -1, -1))


func _synthesize(exe: String, command: PackedStringArray, wav: String, batch: int, index: int) -> void:
	var code: int = OS.execute(exe, command)
	_synthesized.call_deferred(wav, batch, index, code == 0)


## On a worker: one request to kokoro-server, one answer. The lock keeps requests in turn.
func _ask_server(line_text: String, wav: String, batch: int, index: int) -> void:
	_server_lock.lock()
	var pipe: FileAccess = _server.get("stdio")
	var answer: String = ""
	if pipe != null and pipe.is_open():
		pipe.store_line(line_text)
		pipe.flush()
		answer = pipe.get_line().strip_edges()
	_server_lock.unlock()
	if index >= 0:
		_synthesized.call_deferred(wav, batch, index, answer == "ok")


## Starts kokoro-server if it is here and not yet running. False means use the command-line tool.
func _start_server() -> bool:
	_place_server()
	if not _server.is_empty() and OS.is_process_running(int(_server.get("pid", -1))):
		return true
	_server.clear()
	if not FileAccess.file_exists(server_path()):
		return false
	_server = OS.execute_with_pipe(ProjectSettings.globalize_path(server_path()), [ProjectSettings.globalize_path(model_path()), str(threads)])
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


## A sentence is ready. It is read into memory now, so its file can be reused, and played when its
## turn comes.
func _synthesized(wav: String, batch: int, index: int, ok: bool) -> void:
	if batch != _batch:
		return
	for entry: Dictionary in _pending:
		if entry["index"] == index:
			entry["done"] = true
			entry["stream"] = AudioStreamWAV.load_from_file(wav) if ok else null
	_play_next()


## Plays the next sentence if it is ready and nothing is playing; says `finished` when none are left.
func _play_next() -> void:
	if not is_node_ready() or speaker.playing:
		return
	while not _pending.is_empty() and _pending[0]["done"]:
		var entry: Dictionary = _pending.pop_front()
		if entry["stream"] != null:
			speaker.stream = entry["stream"]
			speaker.play()
			started.emit()
			return
	if _pending.is_empty():
		finished.emit()


func stop() -> void:
	_batch += 1
	_pending.clear()
	if is_node_ready() and speaker.playing:
		speaker.stop()


## Synthesising or playing.
func is_speaking() -> bool:
	return not _pending.is_empty() or (is_node_ready() and speaker.playing)


func _on_speaker_finished() -> void:
	_play_next()


## The lexicon a voice reads with: British voices with the British one.
static func lexicon_for(sid: int) -> String:
	return "lexicon-gb-en.txt" if sid >= 0 and sid < VOICES.size() and VOICES[sid][1] == "GB" else "lexicon-us-en.txt"


## One kokoro-server request: speaker, lexicon, WAV and text, tab-separated on one line.
static func request(sid: int, text: String, wav: String) -> String:
	var flat: String = text.replace("\t", " ").replace("\r", " ").replace("\n", " ").strip_edges()
	return "%d\t%s\t%s\t%s" % [sid, lexicon_for(sid), wav, flat if not flat.is_empty() else "."]


## sherpa-onnx-offline-tts's arguments for one line, the fallback without kokoro-server.
static func args(model_dir: String, sid: int, text: String, wav: String, thread_count: int) -> PackedStringArray:
	var lexicon: String = model_dir.path_join(lexicon_for(sid))
	return PackedStringArray([
		"--kokoro-model=" + model_dir.path_join("model.onnx"),
		"--kokoro-voices=" + model_dir.path_join("voices.bin"),
		"--kokoro-tokens=" + model_dir.path_join("tokens.txt"),
		"--kokoro-data-dir=" + model_dir.path_join("espeak-ng-data"),
		"--kokoro-dict-dir=" + model_dir.path_join("dict"),
		"--kokoro-lexicon=" + lexicon,
		"--num-threads=%d" % thread_count,
		"--sid=%d" % sid,
		"--output-filename=" + wav,
		text,
	])


## The voices as the Voice node lists them: id "kokoro:<sid>", a name and a language.
static func voice_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for sid: int in VOICES.size():
		list.append({"id": voice_id(sid), "name": "%s, %s %s" % [VOICES[sid][0], "American" if VOICES[sid][1] == "US" else "British", VOICES[sid][2]], "language": "en_US" if VOICES[sid][1] == "US" else "en_GB", "kokoro": true})
	return list


static func voice_id(sid: int) -> String:
	return "kokoro:%d" % sid


## The speaker id in a Kokoro voice id, or -1 for any other voice.
static func sid_of(id: String) -> int:
	return id.trim_prefix("kokoro:").to_int() if id.begins_with("kokoro:") and id.trim_prefix("kokoro:").is_valid_int() else -1
