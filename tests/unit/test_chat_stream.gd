extends GutTest
## The server-sent events Foundry Local streams a reply as (CLI 0.10.3).


func test_a_piece_of_the_reply() -> void:
	assert_eq(ChatStream.parse_event('data: {"choices":[{"index":0,"delta":{"content":"Oh"},"finish_reason":null}]}'), {"content": "Oh"})


func test_the_end_of_the_reply() -> void:
	assert_eq(ChatStream.parse_event('data: {"choices":[{"delta":{},"finish_reason":"length"}]}'), {"finish_reason": "length"})
	assert_eq(ChatStream.parse_event("data: [DONE]"), {"done": true})


func test_usage_only_and_other_lines_carry_nothing() -> void:
	assert_eq(ChatStream.parse_event('data: {"choices":[],"usage":{"prompt_tokens":835}}'), {}, "the last event can have no choices")
	assert_eq(ChatStream.parse_event(""), {})
	assert_eq(ChatStream.parse_event(": keep-alive"), {})
	assert_eq(ChatStream.parse_event("data: not json"), {})


func test_a_request_is_marked_as_streamed() -> void:
	var body: Dictionary = JSON.parse_string(ChatStream.streamed({"model": "m", "messages": []}))
	assert_eq(body["stream"], true)
	assert_eq(body["model"], "m")


func test_lines_split_across_chunks_come_out_whole() -> void:
	var stream: ChatStream = ChatStream.new()
	add_child_autofree(stream)
	var pieces: Array[String] = []
	stream.delta.connect(func(text: String) -> void: pieces.append(text))
	stream._client = HTTPClient.new()
	var bytes: PackedByteArray = 'data: {"choices":[{"delta":{"content":"Quack é"}}]}\n\n'.to_utf8_buffer()
	var split: int = bytes.find(0xC3) + 1
	stream._feed(bytes.slice(0, split))
	assert_eq(pieces.size(), 0, "half a line waits")
	stream._feed(bytes.slice(split))
	assert_eq(pieces, ["Quack é"] as Array[String], "and a letter split between chunks comes out whole")
	stream.cancel()
