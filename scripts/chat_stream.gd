class_name ChatStream
extends Node
## One streamed chat completion from an OpenAI-compatible server such as Foundry Local: the reply
## arrives a few words at a time through `delta`, then whole through `finished`. HTTPRequest only
## hands over a finished body, so this polls an HTTPClient every frame and reads the server-sent
## events ("data: {...}" lines, then "data: [DONE]") as they come.

## The next piece of the reply.
signal delta(text: String)
## The whole reply. `code` is the HTTP status, 0 when the server could not be reached or took longer
## than `timeout_seconds`; `finish_reason` is "stop", or "length" when it ran out of tokens.
signal finished(text: String, code: int, finish_reason: String)

@export var timeout_seconds: float = 120.0

var _client: HTTPClient = null
var _path: String = ""
var _body: String = ""
var _requested: bool = false
var _bytes: PackedByteArray = PackedByteArray()
var _text: String = ""
var _finish_reason: String = ""
var _started_at: int = 0


func _ready() -> void:
	set_process(false)


## Posts `body` (a chat completion request with "stream": true) to `path` on host:port.
func start(host: String, port: int, path: String, body: String) -> void:
	cancel()
	_client = HTTPClient.new()
	_path = path
	_body = body
	_requested = false
	_bytes.clear()
	_text = ""
	_finish_reason = ""
	_started_at = Time.get_ticks_msec()
	if _client.connect_to_host(host, port) != OK:
		_end(0)
		return
	set_process(true)


func is_busy() -> bool:
	return _client != null


## Drops the request; nothing more is emitted for it.
func cancel() -> void:
	if _client != null:
		_client.close()
	_client = null
	set_process(false)


func _process(_frame: float) -> void:
	if _client == null:
		return
	if Time.get_ticks_msec() - _started_at > timeout_seconds * 1000.0:
		_end(0)
		return
	_client.poll()
	match _client.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				_client.request(HTTPClient.METHOD_POST, _path, ["Content-Type: application/json", "Accept: text/event-stream"], _body)
			else:
				# The body has been read and the connection kept alive for the next one.
				_end(_client.get_response_code())
		HTTPClient.STATUS_BODY:
			# Everything that has come in, not one chunk a frame, so a quick reply is not held back.
			var chunk: PackedByteArray = _client.read_response_body_chunk()
			while not chunk.is_empty() and _client != null:
				_feed(chunk)
				if _client == null:
					return
				_client.poll()
				chunk = _client.read_response_body_chunk() if _client.get_status() == HTTPClient.STATUS_BODY else PackedByteArray()
		HTTPClient.STATUS_DISCONNECTED:
			_end(_client.get_response_code() if _requested else 0)
		HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			_end(0)


## Splits what came in into lines, keeping a part line for the next chunk, so a character split
## across two chunks is decoded whole.
func _feed(chunk: PackedByteArray) -> void:
	_bytes.append_array(chunk)
	var newline: int = _bytes.find(10)
	while newline >= 0:
		var line: String = _bytes.slice(0, newline).get_string_from_utf8()
		_bytes = _bytes.slice(newline + 1)
		var event: Dictionary = parse_event(line)
		if event.get("done", false):
			_end(200)
			return
		if not String(event.get("content", "")).is_empty():
			_text += event["content"]
			delta.emit(event["content"])
		if not String(event.get("finish_reason", "")).is_empty():
			_finish_reason = event["finish_reason"]
		newline = _bytes.find(10)


func _end(code: int) -> void:
	if _client == null:
		return
	cancel()
	finished.emit(_text, code, _finish_reason)


## One line of the event stream: {"content", "finish_reason"} from a "data: {...}" line, {"done":
## true} for "data: [DONE]", {} for anything else. The last event before [DONE] may carry only usage,
## with no choices.
static func parse_event(line: String) -> Dictionary:
	var stripped: String = line.strip_edges()
	if not stripped.begins_with("data:"):
		return {}
	var payload: String = stripped.substr(5).strip_edges()
	if payload == "[DONE]":
		return {"done": true}
	var json: JSON = JSON.new()
	if json.parse(payload) != OK or not json.data is Dictionary:
		return {}
	var choices: Variant = json.data.get("choices")
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return {}
	var event: Dictionary = {}
	var piece: Variant = choices[0].get("delta", {})
	if piece is Dictionary and piece.get("content") is String:
		event["content"] = piece["content"]
	if choices[0].get("finish_reason") is String:
		event["finish_reason"] = choices[0]["finish_reason"]
	return event


## The body for a streamed request, made from a chat_body dictionary.
static func streamed(body: Dictionary) -> String:
	var copy: Dictionary = body.duplicate()
	copy["stream"] = true
	return JSON.stringify(copy)
