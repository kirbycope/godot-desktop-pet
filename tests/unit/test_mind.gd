extends GutTest

const ROOT: String = "user://test_duck"

var mind: Mind


func before_each() -> void:
	_remove(ROOT)
	mind = load("res://scripts/mind.gd").new()
	mind.root = ROOT
	add_child_autofree(mind)


func after_all() -> void:
	_remove(ROOT)


func _remove(path: String) -> void:
	var folder: String = ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(folder):
		return
	for sub: String in DirAccess.get_directories_at(folder):
		_remove(path.path_join(sub))
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func test_first_run_seeds_the_personality_and_skills() -> void:
	assert_true(FileAccess.file_exists(ROOT.path_join("personality.md")))
	assert_string_contains(mind.personality(), "Ernie")
	assert_false("<!--" in mind.personality(), "the note to the user is not sent to the model")
	var names: Array = mind.skills().map(func(s: Dictionary) -> String: return s["name"])
	assert_has(names, "rubber-duck-method")
	assert_has(names, "reading-errors")
	assert_has(names, "godot-gdscript")


func test_seeding_never_overwrites_your_edits() -> void:
	var file: FileAccess = FileAccess.open(ROOT.path_join("personality.md"), FileAccess.WRITE)
	file.store_string("Grumpy, like Bert.")
	file.close()
	mind.ensure_seeded()
	assert_eq(mind.personality(), "Grumpy, like Bert.")


func test_it_remembers_and_forgets() -> void:
	mind.remember("The user's game is called Duck Hunt Deluxe")
	mind.remember("They prefer tabs over spaces")
	mind.remember("They prefer tabs over spaces")
	assert_eq(mind.memories(), PackedStringArray(["The user's game is called Duck Hunt Deluxe", "They prefer tabs over spaces"]), "no duplicates")
	assert_eq(mind.forget("tabs"), 1)
	assert_eq(mind.memories(), PackedStringArray(["The user's game is called Duck Hunt Deluxe"]))
	mind.forget_at(0)
	assert_eq(mind.memories().size(), 0)


func test_forgetting_by_words_when_the_phrase_is_not_exact() -> void:
	var known: PackedStringArray = ["Their cat is called Biscuit", "They use Godot 4"]
	assert_eq(Mind.forget_from(known, "biscuit the cat"), PackedStringArray(["They use Godot 4"]))
	assert_eq(Mind.forget_from(known, "dog"), known, "nothing matches, nothing goes")


func test_a_name_is_kept_and_used() -> void:
	assert_string_contains(mind.prompt(), "You do not have a name yet")
	mind.set_duck_name("  Quackers ")
	assert_eq(mind.duck_name(), "Quackers")
	assert_string_contains(mind.prompt(), "Your name is Quackers.")


func test_tags_are_carried_out_and_hidden() -> void:
	var said: String = mind.digest("Ooh, Quackers! I love it! [name: Quackers] [remember: The user works nights]", "Your name is Quackers, and I work nights.")
	assert_eq(said, "Ooh, Quackers! I love it!")
	assert_eq(mind.duck_name(), "Quackers")
	assert_has(mind.memories(), "The user works nights")
	assert_string_contains(mind.prompt(), "- The user works nights")


func test_a_taught_skill_is_written_and_brought_up_by_its_words() -> void:
	mind.digest("Got it! [skill: Git Rebase Help | rebase, conflict | Ask which branch is being rebased onto.]")
	var found: Array[Dictionary] = mind.skills_for("I have a merge conflict in my rebase")
	assert_eq(found.size(), 1)
	assert_eq(found[0]["name"], "git-rebase-help")
	assert_string_contains(found[0]["body"], "Ask which branch")


func test_skills_match_whole_words_most_hits_first() -> void:
	var picked: Array[Dictionary] = mind.skills_for("NullReferenceException error in my Godot node, the scene is broken")
	assert_eq(picked.size(), 2, "at most two skills a message")
	assert_eq(mind.skills_for("I am rebuilding the bugle").size(), 0, "no trigger word as a whole word")


func test_skill_files_parse() -> void:
	var skill: Dictionary = Mind.parse_skill("---\nname: test\ntriggers: one, Two Words\n---\nDo the thing.\n")
	assert_eq(skill["name"], "test")
	assert_eq(skill["triggers"], PackedStringArray(["one", "two words"]))
	assert_eq(skill["body"], "Do the thing.")
	assert_eq(Mind.parse_skill("no header here"), {})


func test_the_brain_puts_the_mind_in_its_prompt() -> void:
	var brain: Brain = load("res://scripts/brain.gd").new()
	brain.mind = mind
	mind.remember("They are building a desktop pet")
	var prompt: String = brain.system_prompt()
	assert_string_contains(prompt, "friendly little rubber duck")
	assert_string_contains(prompt, "They are building a desktop pet")
	assert_string_contains(prompt, "[remember:")
	brain.free()


func test_skills_ride_along_with_the_users_line_only() -> void:
	var history: Array[Dictionary] = [{"role": "system", "content": "s"}, {"role": "user", "content": "it crashed"}]
	var sent: Array[Dictionary] = Brain.with_skills(history, [{"name": "reading-errors", "body": "Find the first error."}])
	assert_string_starts_with(sent[1]["content"], "Skill reading-errors:\nFind the first error.")
	assert_string_ends_with(sent[1]["content"], "it crashed")
	assert_eq(history[1]["content"], "it crashed", "the kept history is untouched")


func test_plain_requests_are_heard_without_the_model() -> void:
	mind.heed("Hi! Your name is Quackers now. And please remember that my game is called Duck Hunt Deluxe.")
	assert_eq(mind.duck_name(), "Quackers")
	assert_eq(mind.memories(), PackedStringArray(["The user's game is called Duck Hunt Deluxe"]))
	mind.heed("Oh, and forget that my game is called Duck Hunt Deluxe.")
	assert_eq(mind.memories().size(), 0)


func test_remarks_about_remembering_are_not_requests() -> void:
	assert_eq(Mind.commands("I can't remember why this fails."), [])
	assert_eq(Mind.commands("Do you remember what my game is called?"), [])
	assert_eq(Mind.commands("I always forget the semicolon."), [])
	assert_eq(Mind.commands("Don't forget I use Godot 4."), [["remember", "The user said: \"I use Godot 4\""]])
	assert_eq(Mind.commands("Can you remember that I'm left-handed?"), [["remember", "The user said: \"I'm left-handed\""]])


func test_memories_read_as_about_the_user() -> void:
	assert_eq(Mind.about_the_user("my cat is called Biscuit"), "The user's cat is called Biscuit")
	assert_eq(Mind.about_the_user("I prefer tabs over spaces"), "The user said: \"I prefer tabs over spaces\"", "no 'the user prefer'")
	assert_eq(Mind.about_the_user("give me short answers"), "Give the user short answers")


func test_every_message_ends_with_the_in_character_reminder() -> void:
	var history: Array[Dictionary] = [{"role": "user", "content": "hi"}]
	assert_string_ends_with(Brain.with_screen(history, "x")[0]["content"], Brain.REMINDER)


func test_the_brain_in_the_scene_is_linked_to_the_mind() -> void:
	# An exported Node is only resolved when the scene lists it in node_paths; without that the
	# personality and memories silently never reach the model.
	var pet: Node = (load("res://scenes/pet.tscn") as PackedScene).instantiate()
	var brain: Brain = pet.get_node("Brain")
	assert_not_null(brain.mind)
	assert_eq(brain.mind, pet.get_node("Mind"))
	pet.free()


func test_a_fact_already_known_is_not_kept_twice() -> void:
	mind.remember("The user's game is called Duck Hunt Deluxe")
	mind.remember("game is called Duck Hunt Deluxe")
	mind.remember("The user's game is called Duck Hunt Deluxe, a shooter")
	assert_eq(mind.memories().size(), 1)


func test_the_model_is_told_not_to_keep_the_bug_of_the_moment() -> void:
	assert_string_contains(Mind.PROTOCOL, "Do not remember the problem you are working on right now")



func test_the_model_cannot_remember_small_talk() -> void:
	mind.digest("Hello there! [remember: how they are doing today]", "hello?")
	mind.digest("Ooh! [remember: user is looking for help]", "Can you help with this function?")
	assert_eq(mind.memories().size(), 0, "nothing in those lines was about the user")
	mind.digest("Night owl! [remember: The user works nights]", "I work nights, so I code late.")
	assert_eq(mind.memories(), PackedStringArray(["The user works nights"]))


func test_every_line_goes_into_todays_conversation_log() -> void:
	mind.record("user", "I had pancakes\nfor breakfast.")
	mind.record("assistant", "Pancakes! Ooh, with syrup?")
	var today: String = ROOT.path_join("conversations").path_join(Time.get_date_string_from_system() + ".md")
	assert_true(FileAccess.file_exists(today))
	var text: String = FileAccess.get_file_as_string(today)
	assert_string_contains(text, "**You:** I had pancakes for breakfast.")
	assert_string_contains(text, "**Duck:** Pancakes! Ooh, with syrup?")


func test_the_last_exchanges_come_back_oldest_first_across_days() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("conversations")))
	var yesterday: FileAccess = FileAccess.open(ROOT.path_join("conversations/2026-10-06.md"), FileAccess.WRITE)
	yesterday.store_string(Mind.log_line("user", "one", "10:00:00") + Mind.log_line("assistant", "two", "10:00:01") + Mind.log_line("user", "three", "10:00:02"))
	yesterday.close()
	var today: FileAccess = FileAccess.open(ROOT.path_join("conversations/2026-10-07.md"), FileAccess.WRITE)
	today.store_string(Mind.log_line("assistant", "four", "09:00:00") + Mind.log_line("user", "five", "09:00:01"))
	today.close()
	var last: Array[Dictionary] = mind.recent(4)
	assert_eq(last.map(func(m: Dictionary) -> String: return m["content"]), ["two", "three", "four", "five"])
	assert_eq(last[0]["role"], "assistant")
	assert_eq(last[3]["role"], "user")


func test_a_log_line_reads_back_as_the_same_message() -> void:
	var line: String = Mind.log_line("user", "What's my favourite colour?", "14:05:12")
	assert_eq(line, "- 14:05:12 **You:** What's my favourite colour?\n")
	assert_eq(Mind.parse_log(line + "not a log line\n"), [{"role": "user", "content": "What's my favourite colour?"}])


func test_the_personality_teaches_carrying_a_conversation() -> void:
	var seeded: String = mind.personality()
	assert_string_contains(seeded, "How you carry a conversation")
	assert_string_contains(seeded, "follow-up question")
	assert_string_contains(seeded, "Share as much as you ask")
	assert_string_contains(seeded, "Never make one up")
	assert_string_contains(seeded, "What's your favourite animal?", "a dry starter turned into a conversation")
	assert_false("Huang, Yeomans" in seeded, "the research notes stay in the comment, not the prompt")
