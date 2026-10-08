class_name Searcher
extends Node
## Looks things up on DuckDuckGo when the user asks the duck to: "search for ...", "look up ...",
## "google ...". DuckDuckGo's plain results pages (no key, no account) are fetched by the Request
## child and the top results go to the model with the user's line; the answer arrives through
## `searched`, an empty list when nothing came back.

signal searched(results: Array[Dictionary])

## How many results go to the model.
@export var max_results: int = 5
## The results pages, tried in turn while each answers with its "are you a robot?" check (HTTP
## 202): Lite is the lighter, and asks sooner after a few searches. The query is posted as a form,
## as their own search boxes do; a GET with the query in the address gets the check at once.
@export var search_urls: PackedStringArray = ["https://lite.duckduckgo.com/lite/", "https://html.duckduckgo.com/html/"]
## Snippets longer than this are cut, so the results cannot crowd out the conversation.
@export var max_snippet: int = 300

## Why the last search came back empty, or "" when it worked.
var last_error: String = ""
var _query: String = ""
var _page: int = 0

@onready var request: HTTPRequest = $Request


func search(query: String) -> void:
	last_error = ""
	_query = query
	_page = 0
	_ask()


func _ask() -> void:
	request.cancel_request()
	# DuckDuckGo turns away requests that do not look like a browser's.
	var headers: PackedStringArray = ["User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36", "Content-Type: application/x-www-form-urlencoded"]
	var failed: Error = request.request(search_urls[_page], headers, HTTPClient.METHOD_POST, "q=" + _query.uri_encode())
	if failed != OK:
		last_error = "The search could not be sent (%s)." % error_string(failed)
		searched.emit([] as Array[Dictionary])


func is_searching() -> bool:
	return request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var found: Array[Dictionary] = []
	if code == 202 and _page + 1 < search_urls.size():
		_page += 1
		_ask()
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# 202 is DuckDuckGo asking whether this is a robot.
		last_error = "DuckDuckGo did not answer (result %d, HTTP %d)." % [result, code] if code != 202 else "DuckDuckGo thinks I'm a robot just now. Try again in a minute."
	else:
		found = parse_results(body.get_string_from_utf8(), max_results, max_snippet)
		if found.is_empty():
			last_error = "DuckDuckGo found nothing."
	searched.emit(found)


## What a line asks to be looked up, or "" when it is not a request to search.
static func query_in(line: String) -> String:
	var hit: RegExMatch = RegEx.create_from_string(r"(?i)^\s*(?:[\w']+[,:]\s+)?(?:(?:can|could|would|will)\s+you\s+|please\s+)?(?:search(?:\s+the\s+web|\s+online|\s+duckduckgo)?(?:\s+for)?|look\s+up|google|duckduckgo)\s+(.+?)(?:\s+(?:for\s+me|please|online))?[\s?.!]*$").search(line)
	return hit.get_string(1).strip_edges() if hit != null else ""


## The results on a DuckDuckGo Lite or HTML page: title, the page's own address, and the snippet.
static func parse_results(html: String, count: int, snippet_length: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var lite: RegEx = RegEx.create_from_string(r"(?s)href=\"([^\"]*)\"\s+class='result-link'>(.*?)</a>.*?class='result-snippet'>(.*?)</td>")
	var full: RegEx = RegEx.create_from_string(r"(?s)class=\"result__a\" href=\"([^\"]*)\">(.*?)</a>.*?class=\"result__snippet\"[^>]*>(.*?)</a>")
	var hits: Array[RegExMatch] = lite.search_all(html)
	if hits.is_empty():
		hits = full.search_all(html)
	for hit: RegExMatch in hits:
		var link: String = hit.get_string(1)
		# A searched-by-address page links through DuckDuckGo's redirect with the page in uddg; a
		# posted search links straight to it. Adverts go through DuckDuckGo's y.js.
		if "uddg=" in link:
			link = link.get_slice("uddg=", 1).get_slice("&", 0).uri_decode()
		if "duckduckgo.com/" in link or not link.begins_with("http"):
			continue
		var snippet: String = plain(hit.get_string(3))
		if snippet.length() > snippet_length:
			snippet = snippet.left(snippet_length).strip_edges() + "..."
		found.append({"title": plain(hit.get_string(2)), "url": link, "snippet": snippet})
		if found.size() >= count:
			break
	return found


## HTML to one line of plain text.
static func plain(html: String) -> String:
	var text: String = RegEx.create_from_string(r"<[^>]+>").sub(html, "", true).replace("&nbsp;", " ").xml_unescape()
	return RegEx.create_from_string(r"\s+").sub(text, " ", true).strip_edges()


## The results as the model reads them.
static func as_prompt(query: String, results: Array[Dictionary]) -> String:
	if results.is_empty():
		return "The user asked you to search the web for \"%s\", but the search found nothing. Say so." % query
	var lines: PackedStringArray = PackedStringArray(["Web search results from DuckDuckGo for \"%s\". Answer from these, and you may tell facts from them, saying where you read it:" % query])
	for i: int in results.size():
		lines.append("%d. %s (%s): %s" % [i + 1, results[i]["title"], results[i]["url"], results[i]["snippet"]])
	return "\n".join(lines)


## The sources, shown under the answer.
static func as_sources(results: Array[Dictionary]) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for found: Dictionary in results.slice(0, 3):
		lines.append("%s: %s" % [found["title"], found["url"]])
	return "Searched DuckDuckGo:\n" + "\n".join(lines)
