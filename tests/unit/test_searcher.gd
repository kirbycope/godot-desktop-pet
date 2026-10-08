extends GutTest


func test_only_a_request_to_search_is_a_search() -> void:
	assert_eq(Searcher.query_in("search for godot 4.5 release date"), "godot 4.5 release date")
	assert_eq(Searcher.query_in("Can you look up the weather in Leeds?"), "the weather in Leeds")
	assert_eq(Searcher.query_in("Ducky, google rubber duck debugging please"), "rubber duck debugging")
	assert_eq(Searcher.query_in("search the web for kokoro tts"), "kokoro tts")
	assert_eq(Searcher.query_in("what's your favourite colour?"), "", "small talk is not a search")
	assert_eq(Searcher.query_in("I did a search yesterday"), "", "mentioning search is not asking for one")


func test_results_come_from_the_lite_page() -> void:
	var results: Array[Dictionary] = Searcher.parse_results(FileAccess.get_file_as_string("res://tests/fixtures/ddg_lite.html"), 5, 300)
	assert_eq(results.size(), 5)
	assert_eq(results[0]["title"], "Godot 4.5, making dreams accessible - Godot Engine")
	assert_eq(results[0]["url"], "https://godotengine.org/releases/4.5/", "the page itself, not DuckDuckGo's redirect")
	assert_string_starts_with(results[0]["snippet"], "Making dreams accessible")
	assert_false("<b>" in results[0]["snippet"], "tags stripped")
	assert_lte(results[0]["snippet"].length(), 303)


func test_the_model_gets_the_results_and_the_user_sees_the_sources() -> void:
	var results: Array[Dictionary] = [{"title": "Godot 4.5", "url": "https://godotengine.org/releases/4.5/", "snippet": "Released in September."}]
	var prompt: String = Searcher.as_prompt("godot 4.5", results)
	assert_string_contains(prompt, "1. Godot 4.5 (https://godotengine.org/releases/4.5/): Released in September.")
	assert_string_contains(Searcher.as_prompt("nothing", []), "found nothing")
	assert_string_contains(Searcher.as_sources(results), "Godot 4.5: https://godotengine.org/releases/4.5/")


func test_the_pet_scene_has_a_searcher_wired_in() -> void:
	var pet: Node = load("res://scenes/pet.tscn").instantiate()
	var searcher: Searcher = pet.get_node("Searcher") as Searcher
	assert_not_null(searcher)
	assert_true(searcher.searched.is_connected(pet._on_searcher_searched))
	assert_true(searcher.get_node("Request").request_completed.is_connected(searcher._on_request_completed))
	pet.free()


func test_a_posted_search_links_straight_to_the_pages() -> void:
	var results: Array[Dictionary] = Searcher.parse_results(FileAccess.get_file_as_string("res://tests/fixtures/ddg_lite_post.html"), 5, 300)
	assert_eq(results.size(), 5)
	assert_eq(results[0]["url"], "https://godotengine.org/releases/4.5/")
	assert_eq(results[1]["url"], "https://www.linuxcompatible.org/story/released-9a/")


func test_the_html_page_parses_too_for_when_lite_asks_if_it_is_a_robot() -> void:
	var results: Array[Dictionary] = Searcher.parse_results(FileAccess.get_file_as_string("res://tests/fixtures/ddg_html.html"), 5, 300)
	assert_eq(results.size(), 5)
	assert_eq(results[0]["url"], "https://www.luna-bella.com/blogs/news/longevity-tips-for-your-rubber-duck-collection")
	assert_string_starts_with(results[0]["snippet"], "Learn expert care tips")


func test_running_out_of_facts_searches_and_learns_through_the_scene() -> void:
	var pet: Node = load("res://scenes/pet.tscn").instantiate()
	var mind: Node = pet.get_node("Mind")
	var facts: Searcher = pet.get_node("FactSearcher") as Searcher
	var brain: Node = pet.get_node("Brain")
	assert_true(mind.out_of_facts.is_connected(facts.search))
	assert_true(facts.searched.is_connected(brain.learn_facts))
	assert_true(brain.facts_found.is_connected(mind.add_facts))
	assert_true(brain.get_node("FactRequest").request_completed.is_connected(brain._on_fact_request_completed))
	pet.free()
