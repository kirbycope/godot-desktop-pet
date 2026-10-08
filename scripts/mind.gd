class_name Mind
extends Node
## What the duck knows about itself and you, kept as plain text files in its own folder.
##
##   user://duck/personality.md   how it talks; seeded from res://seed on first run, then yours to edit
##   user://duck/memories.md      one remembered fact per "- " line
##   user://duck/skills/*.md      instructions brought in when a message mentions their trigger words
##   user://duck/name.txt         its name, once it has one
##   user://duck/told.md          the facts it has already told, so it moves on
##   user://duck/asked.md         the questions it asked lately, so it asks something new
##   user://duck/learned.md       facts it found on the web once it had told all of its own
##   user://duck/searched.md      the topics it has searched for facts, so it picks a new one
##   user://duck/conversations/   everything said, one Markdown file a day; the last few exchanges
##                                go back into the prompt when the duck starts again
##
## The model asks for changes with tags at the end of a reply, such as [remember: ...]; `digest`
## carries them out and strips them before the reply is shown or spoken.

## Something was remembered, forgotten, learned or renamed, for the bubble to mention.
signal changed(note: String)
## Every fact has been told: time to look up some more about `topic`.
signal out_of_facts(topic: String)

## The duck's folder. Tests point it elsewhere.
@export var root: String = "user://duck"
## Where the first copies of the personality and the skills come from.
@export var seed: String = "res://seed"
## Memories beyond this many are left out of the prompt, oldest first.
@export var max_memories: int = 40
## How many of its own recent questions it is told not to ask again.
@export var max_asked: int = 12
## At most this many skills go with one message.
@export var max_skills: int = 2
## What it searches the web for, in turn, when it has told every fact it knows.
@export var fact_topics: PackedStringArray = ["surprising facts about ducks", "history of the rubber duck", "facts about mallard ducks", "facts about ducklings", "how ducks fly and migrate", "facts about duck feathers and swimming", "history of bath time", "Sesame Street history facts"]
## How long to wait before searching again when a search for facts found none, in seconds.
@export var fact_search_wait: float = 300.0

var _fact_search_at: int = -1

## One character of a sentence: anything but an ending, or a "." or "?" with no space after it, as in "4.5".
const SENTENCE: String = r"(?:[^.!?]|[.!?](?=[^\s.!?]))"

## Words too ordinary to say which fact a reply was telling.
const COMMON_WORDS: PackedStringArray = ["about", "after", "their", "there", "which", "where", "would", "could", "people", "other", "while", "every", "first", "being", "still", "these", "those", "ducks", "really", "thing", "things", "that", "with", "have", "this", "from", "they", "them", "then", "than", "what", "when", "your", "just", "like", "more", "some", "into", "were", "been", "also", "only", "over", "does", "duck", "very", "much", "here", "even", "each", "most", "make", "made"]

const TAG: String = "(?i)\\[(remember|forget|name|skill):\\s*(.*?)\\]"
## A request rather than a remark: the start of a sentence, or after "please", "and", "can you" and
## the like. "I can't remember why" and "do you remember" are not asking the duck to remember.
const REQUEST: String = r"(?i)(?:^|\b(?:please|and|also|so|now|oh|hey|can you|could you|would you|will you)\s+)(?:please\s+)?"

## How the model is told to use its memory. {name} is filled in.
const PROTOCOL: String = """You have a memory that lasts between conversations. When the user tells you a lasting fact worth keeping about themselves, their project or how they like to work, end your reply with [remember: the fact, in a few words]. Do not remember the problem you are working on right now, or anything already in what you remember. When they ask you to forget something, end it with [forget: words from that memory]. If they give you a new name, end it with [name: the name]. If they teach you a way of doing something to use again, end it with [skill: short-name | words that should bring it up, separated by commas | the steps]. Tags are hidden and never read aloud, so still answer in words."""


func _ready() -> void:
	ensure_seeded()


## Copies the seed personality and skills into the folder, never over a file already there.
func ensure_seeded() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("skills")))
	_copy_if_missing(seed.path_join("personality.md"), root.path_join("personality.md"))
	for file: String in DirAccess.get_files_at(seed.path_join("skills")):
		if file.ends_with(".md"):
			_copy_if_missing(seed.path_join("skills").path_join(file), root.path_join("skills").path_join(file))


func duck_name() -> String:
	return FileAccess.get_file_as_string(root.path_join("name.txt")).strip_edges() if FileAccess.file_exists(root.path_join("name.txt")) else ""


func set_duck_name(new_name: String) -> void:
	if new_name.strip_edges().is_empty() or new_name.strip_edges() == duck_name():
		return
	_write(root.path_join("name.txt"), new_name.strip_edges())
	changed.emit("Name: " + new_name.strip_edges())


func personality() -> String:
	return strip_comments(FileAccess.get_file_as_string(root.path_join("personality.md")))


func memories() -> PackedStringArray:
	return parse_memories(FileAccess.get_file_as_string(root.path_join("memories.md")))


func remember(fact: String) -> void:
	var fact_clean: String = fact.strip_edges()
	var known: PackedStringArray = memories()
	if fact_clean.is_empty() or already_known(known, fact_clean):
		return
	known.append(fact_clean)
	_save_memories(known)
	changed.emit("Remembered: " + fact_clean)


## Forgets the memories `phrase` names. Returns how many went.
func forget(phrase: String) -> int:
	var known: PackedStringArray = memories()
	var kept: PackedStringArray = forget_from(known, phrase)
	if kept.size() == known.size():
		return 0
	_save_memories(kept)
	changed.emit("Forgot: " + phrase.strip_edges())
	return known.size() - kept.size()


func forget_at(index: int) -> void:
	var known: PackedStringArray = memories()
	if index < 0 or index >= known.size():
		return
	var gone: String = known[index]
	known.remove_at(index)
	_save_memories(known)
	changed.emit("Forgot: " + gone)


## Every skill in the folder: [{name, triggers, body}].
func skills() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var folder: String = root.path_join("skills")
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".md"):
			var skill: Dictionary = parse_skill(FileAccess.get_file_as_string(folder.path_join(file)))
			if not skill.is_empty():
				found.append(skill)
	return found


## Writes a skill the user taught; "name | triggers | steps".
func learn(spec: String) -> void:
	var parts: PackedStringArray = spec.split("|")
	if parts.size() < 3:
		return
	var skill_name: String = slug(parts[0])
	if skill_name.is_empty():
		return
	var steps: String = "|".join(parts.slice(2)).strip_edges()
	_write(root.path_join("skills").path_join(skill_name + ".md"), "---\nname: %s\ntriggers: %s\n---\n%s\n" % [skill_name, parts[1].strip_edges(), steps])
	changed.emit("Learned the skill: " + skill_name)


## The skills whose trigger words appear in `text`, best first, at most `max_skills`.
func skills_for(text: String) -> Array[Dictionary]:
	return relevant_skills(skills(), text, max_skills)


## The system prompt's part that belongs to the duck: name, personality, memories, skills and the
## memory protocol.
func prompt() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var called: String = duck_name()
	parts.append("Your name is %s." % called if not called.is_empty() else "You do not have a name yet. If the user offers you one, take it happily.")
	# Facts it has already told are taken out, so it tells a new one; once all are told, it starts over.
	var untold: PackedStringArray = untold_facts()
	parts.append(with_facts(personality(), untold))
	parts.append(PROTOCOL)
	var recent_questions: PackedStringArray = asked()
	if not recent_questions.is_empty():
		parts.append("Questions you asked lately. Do not ask them again; ask about something new they said:\n- " + "\n- ".join(recent_questions))
	var known: PackedStringArray = memories()
	if not known.is_empty():
		var recent: PackedStringArray = known.slice(maxi(0, known.size() - max_memories))
		parts.append("What you remember:\n- " + "\n- ".join(recent))
	var all_skills: Array[Dictionary] = skills()
	if not all_skills.is_empty():
		parts.append("Skills you have, brought in when they apply: " + ", ".join(all_skills.map(func(s: Dictionary) -> String: return s["name"])) + ".")
	return "\n\n".join(parts)


## The facts listed under "Things you know for sure" in the personality, then those it found on the web.
func facts() -> PackedStringArray:
	var all: PackedStringArray = facts_in(personality())
	all.append_array(learned())
	return all


func learned() -> PackedStringArray:
	return parse_memories(FileAccess.get_file_as_string(root.path_join("learned.md")))


## Keeps facts found on the web, leaving out any it knows already.
func add_facts(found: PackedStringArray) -> void:
	var known: PackedStringArray = learned()
	var all: PackedStringArray = facts()
	var added: int = 0
	for fact: String in found:
		var clean: String = fact.strip_edges()
		if not clean.is_empty() and not already_known(all, clean):
			known.append(clean)
			all.append(clean)
			added += 1
	if added == 0:
		return
	_write(root.path_join("learned.md"), "".join(Array(known).map(func(f: String) -> String: return "- %s\n" % f)))
	changed.emit("Looked up %d new fact%s to tell you" % [added, "" if added == 1 else "s"])


## The next of `fact_topics` not searched yet; the first again once all have been.
func next_topic() -> String:
	if fact_topics.is_empty():
		return ""
	var searched: PackedStringArray = parse_memories(FileAccess.get_file_as_string(root.path_join("searched.md")))
	for topic: String in fact_topics:
		if not topic in searched:
			searched.append(topic)
			_write(root.path_join("searched.md"), "".join(Array(searched).map(func(t: String) -> String: return "- %s\n" % t)))
			return topic
	_write(root.path_join("searched.md"), "- %s\n" % fact_topics[0])
	return fact_topics[0]


## The duck's answers in the personality's "How you sound" examples, which a small model will copy
## word for word if let.
func example_replies() -> PackedStringArray:
	return example_replies_in(personality())


func told() -> PackedStringArray:
	return parse_memories(FileAccess.get_file_as_string(root.path_join("told.md")))


func asked() -> PackedStringArray:
	return parse_memories(FileAccess.get_file_as_string(root.path_join("asked.md")))


## The facts not told yet; all of them again while every one has been told and new ones are
## being looked up.
func untold_facts() -> PackedStringArray:
	var all: PackedStringArray = facts()
	var done: PackedStringArray = told()
	var left: PackedStringArray = PackedStringArray()
	for fact: String in all:
		if not fact in done:
			left.append(fact)
	return left if not left.is_empty() else all


## Notes which facts a reply told and which questions it asked.
func notice(reply: String) -> void:
	var done: PackedStringArray = told()
	var added: bool = false
	for fact: String in facts():
		if not fact in done and tells_fact(reply, fact):
			done.append(fact)
			added = true
	if added:
		_write(root.path_join("told.md"), "".join(Array(done).map(func(f: String) -> String: return "- %s\n" % f)))
	# All told: look some more up, though not again for a while if the last search found nothing.
	var now: int = Time.get_ticks_msec()
	if Array(facts()).all(func(f: String) -> bool: return f in done) and (_fact_search_at < 0 or now - _fact_search_at > fact_search_wait * 1000.0):
		var topic: String = next_topic()
		if not topic.is_empty():
			_fact_search_at = now
			out_of_facts.emit(topic)
	var questions: PackedStringArray = asked()
	questions.append_array(questions_in(reply))
	if questions.size() > max_asked:
		questions = questions.slice(questions.size() - max_asked)
	_write(root.path_join("asked.md"), "".join(Array(questions).map(func(q: String) -> String: return "- %s\n" % q)))


## Carries out plain requests in the user's own line before the model sees it: "your name is
## Quackers", "remember that ...", "don't forget ...", "forget ...". A small model cannot be trusted
## to answer these with tags, so they do not depend on it.
func heed(line: String) -> void:
	for command: Array in commands(line):
		match command[0]:
			"name":
				set_duck_name(command[1])
			"remember":
				remember(command[1])
			"forget":
				forget(command[1])


## Carries out the tags in a reply and returns the reply without them.
## `said` is the user's line it answers: the model may only remember something when that line
## tells it something about the user, as small models otherwise keep "the user said hello".
func digest(reply: String, said: String = "") -> String:
	for tag: Array in find_tags(reply):
		match tag[0]:
			"remember":
				if is_about_the_user(said):
					remember(tag[1])
			"forget":
				forget(tag[1])
			"name":
				set_duck_name(tag[1])
			"skill":
				learn(tag[1])
	return strip_tags(reply)


## Adds a line to today's conversation log: who said it ("user" or "assistant") and what.
func record(role: String, text: String) -> void:
	var said: String = text.replace("\r", " ").replace("\n", " ").strip_edges()
	if said.is_empty():
		return
	var folder: String = root.path_join("conversations")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path: String = folder.path_join(Time.get_date_string_from_system() + ".md")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_string(log_line(role, said, Time.get_time_string_from_system()))
	file.close()


## The last `count` messages from the newest conversation logs, oldest first, as chat messages.
func recent(count: int) -> Array[Dictionary]:
	var folder: String = root.path_join("conversations")
	var days: PackedStringArray = DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(folder)) else PackedStringArray()
	var found: Array[Dictionary] = []
	var sorted: Array = Array(days).filter(func(f: String) -> bool: return f.ends_with(".md"))
	sorted.sort()
	sorted.reverse()
	for day: String in sorted:
		var earlier: Array[Dictionary] = parse_log(FileAccess.get_file_as_string(folder.path_join(day)))
		earlier.append_array(found)
		found = earlier
		if found.size() >= count:
			break
	return found.slice(maxi(0, found.size() - count))


func folder_path() -> String:
	return ProjectSettings.globalize_path(root)


func _save_memories(known: PackedStringArray) -> void:
	_write(root.path_join("memories.md"), "".join(Array(known).map(func(m: String) -> String: return "- %s\n" % m)))


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()


func _copy_if_missing(from: String, to: String) -> void:
	if not FileAccess.file_exists(to) and FileAccess.file_exists(from):
		_write(to, FileAccess.get_file_as_string(from))


## [[kind, text], ...] for the requests in a line the user said or typed.
static func commands(line: String) -> Array:
	var found: Array = []
	var named: RegExMatch = RegEx.create_from_string(r"(?i)\b(?:your name is|your new name is|i(?:'ll| will) call you|i(?:'m| am) calling you|call yourself|i name you)\s+([\w'-]+)").search(line)
	if named != null:
		found.append(["name", named.get_string(1).capitalize()])
	for sentence: String in RegEx.create_from_string(r"[^.!?]+").search_all(line).map(func(m: RegExMatch) -> String: return m.get_string().strip_edges()):
		var kept: RegExMatch = RegEx.create_from_string(REQUEST + r"(?:remember|don't forget|do not forget)(?: that)?\s+(.+)$").search(sentence)
		if kept != null:
			found.append(["remember", about_the_user(kept.get_string(1))])
			continue
		var dropped: RegExMatch = RegEx.create_from_string(REQUEST + r"forget(?: that| about)?\s+(.+)$").search(sentence)
		if dropped != null:
			found.append(["forget", about_the_user(dropped.get_string(1))])
	return found


## Whether a line tells something about the speaker: "I", "my", "we" and the like.
static func is_about_the_user(line: String) -> bool:
	return RegEx.create_from_string(r"(?i)\b(i|i'm|i've|i'd|my|mine|me|we|we're|our)\b").search(line) != null


## "my game is called X" becomes "the user's game is called X", so memories read the same later.
static func about_the_user(text: String) -> String:
	var out: String = text.strip_edges()
	# "I prefer tabs" cannot become "the user prefer tabs", so a sentence about "I" keeps the
	# user's own words, quoted.
	if RegEx.create_from_string(r"(?i)\bi\b|\bi'm\b|\bi've\b|\bi'd\b|\bi'll\b").search(out) != null:
		return "The user said: \"%s\"" % out
	var swaps: Array = [[r"(?i)\bmy\b", "the user's"], [r"(?i)\bmine\b", "the user's"], [r"(?i)\bme\b", "the user"]]
	for swap: Array in swaps:
		out = RegEx.create_from_string(swap[0]).sub(out, swap[1], true)
	return out.left(1).to_upper() + out.substr(1)


## The bullets under the "## Things you know for sure" heading, each joined onto one line.
static func facts_in(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var inside: bool = false
	for line: String in text.split("\n"):
		if line.begins_with("## "):
			inside = line.strip_edges() == "## Things you know for sure"
			continue
		if not inside:
			continue
		if line.begins_with("- "):
			found.append(line.substr(2).strip_edges())
		elif not line.strip_edges().is_empty() and not found.is_empty():
			found[-1] = found[-1] + " " + line.strip_edges()
	return found


## The "You:" answers under the "## How you sound" heading, each joined onto one line.
static func example_replies_in(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var inside: bool = false
	var answering: bool = false
	for line: String in text.split("\n"):
		if line.begins_with("## "):
			inside = line.strip_edges() == "## How you sound"
			continue
		if not inside:
			continue
		var said: String = line.strip_edges()
		if said.begins_with("You:"):
			found.append(said.trim_prefix("You:").strip_edges())
			answering = true
		elif said.begins_with("- ") or said.is_empty():
			answering = false
		elif answering:
			found[-1] = found[-1] + " " + said
	return found


## The personality with its facts section holding only `facts`.
static func with_facts(text: String, facts: PackedStringArray) -> String:
	var out: PackedStringArray = PackedStringArray()
	var inside: bool = false
	for line: String in text.split("\n"):
		if line.begins_with("## "):
			inside = line.strip_edges() == "## Things you know for sure"
			out.append(line)
			if inside:
				for fact: String in facts:
					out.append("- " + fact)
			continue
		if not inside:
			out.append(line)
	return "\n".join(out)


## Whether `reply` tells `fact`: three of the fact's telling words (four letters or more and not
## ordinary, or numbers) turn up in it.
static func tells_fact(reply: String, fact: String) -> bool:
	var words: PackedStringArray = PackedStringArray()
	for word: String in RegEx.create_from_string(r"[a-z0-9,]+").search_all(fact.to_lower()).map(func(m: RegExMatch) -> String: return m.get_string().trim_suffix(",")):
		if (word.length() >= 4 or word.is_valid_int()) and not word in COMMON_WORDS and not word in words:
			words.append(word)
	if words.is_empty():
		return false
	var said: String = reply.to_lower()
	var hits: int = 0
	for word: String in words:
		if word in said:
			hits += 1
	# Three telling words are enough: a fact retold in other words keeps its names and numbers.
	return hits >= mini(3, words.size())


## What in `reply` repeats something said before: the earlier reply it copies, or the question it
## asks again; "" when it is new.
static func repetition(reply: String, earlier_replies: PackedStringArray, earlier_questions: PackedStringArray) -> String:
	for earlier: String in earlier_replies:
		if overlap(reply, earlier) >= 0.6:
			return earlier
	for question: String in questions_in(reply):
		for earlier: String in earlier_questions:
			if overlap(question, earlier) >= 0.8:
				return question
	return ""


## `reply` without the sentences said before, in `earlier_replies`, or asked before, in
## `earlier_questions`; "" when nothing new is left.
static func without_repeats(reply: String, earlier_replies: PackedStringArray, earlier_questions: PackedStringArray, min_words: int = 3, alike: float = 0.7) -> String:
	var said: PackedStringArray = PackedStringArray()
	for earlier: String in earlier_replies:
		said.append_array(sentences_in(earlier))
	var kept: PackedStringArray = PackedStringArray()
	for sentence: String in sentences_in(reply):
		var old: bool = false
		for earlier: String in said:
			if word_set(sentence).size() >= min_words and overlap(sentence, earlier) >= alike:
				old = true
		if sentence.ends_with("?"):
			for earlier: String in earlier_questions:
				if overlap(sentence, earlier) >= 0.8:
					old = true
		if not old:
			kept.append(sentence)
	return " ".join(kept)


static func sentences_in(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(SENTENCE + r"+[.!?]*").search_all(text):
		var sentence: String = hit.get_string().strip_edges()
		if not sentence.is_empty():
			found.append(sentence)
	return found


## `reply` cut short where it got stuck saying one word over and over ("gack-gack-gack-..."), back
## to the end of the last whole sentence before it.
static func without_babble(reply: String) -> String:
	var stuck: RegExMatch = RegEx.create_from_string(r"(?i)\b([\w']+)(?:[\s,-]+\1\b){4,}").search(reply)
	if stuck == null:
		return reply
	var before: String = reply.left(stuck.get_start())
	var end: int = maxi(maxi(before.rfind("."), before.rfind("!")), before.rfind("?"))
	if end > 0:
		return before.left(end + 1).strip_edges()
	return before.left(maxi(before.rfind(" "), 0)).strip_edges() + "..."


## How much of the shorter text's words, four letters or more, the other one has too, from 0 to 1.
static func overlap(a: String, b: String) -> float:
	var words_a: Dictionary = word_set(a)
	var words_b: Dictionary = word_set(b)
	if words_a.is_empty() or words_b.is_empty():
		return 0.0
	var shared: int = 0
	for word: String in words_a:
		if words_b.has(word):
			shared += 1
	return float(shared) / mini(words_a.size(), words_b.size())


static func word_set(text: String) -> Dictionary:
	var found: Dictionary = {}
	for hit: RegExMatch in RegEx.create_from_string(r"[a-z0-9']{4,}").search_all(text.to_lower()):
		found[hit.get_string()] = true
	return found


## The questions in a reply, each a sentence ending in "?".
static func questions_in(reply: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(SENTENCE + r"*\?").search_all(reply):
		var question: String = hit.get_string().strip_edges()
		if question.length() > 3:
			found.append(question)
	return found


## One line of the conversation log: "- 14:05:12 **You:** ..." or "- 14:05:13 **Duck:** ...".
static func log_line(role: String, text: String, time: String) -> String:
	return "- %s **%s:** %s\n" % [time, "You" if role == "user" else "Duck", text]


## The messages in a conversation log, oldest first.
static func parse_log(text: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var line_pattern: RegEx = RegEx.create_from_string(r"^- [\d:]+ \*\*(You|Duck):\*\* (.*)$")
	for line: String in text.split("\n", false):
		var hit: RegExMatch = line_pattern.search(line.strip_edges())
		if hit != null:
			found.append({"role": "user" if hit.get_string(1) == "You" else "assistant", "content": hit.get_string(2)})
	return found


## [[kind, text], ...] for each tag in `reply`.
static func find_tags(reply: String) -> Array:
	var tags: Array = []
	for found: RegExMatch in RegEx.create_from_string(TAG).search_all(reply):
		tags.append([found.get_string(1).to_lower(), found.get_string(2).strip_edges()])
	return tags


static func strip_tags(reply: String) -> String:
	var stripped: String = RegEx.create_from_string("\\s*" + TAG).sub(reply, "", true)
	# A tag left open runs to the end of the reply: the model forgot the "]".
	return RegEx.create_from_string(r"(?i)\s*\[(remember|forget|name|skill):[^\]]*$").sub(stripped, "").strip_edges()


static func strip_comments(text: String) -> String:
	return RegEx.create_from_string("(?s)<!--.*?-->").sub(text, "", true).strip_edges()


static func parse_memories(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n", false):
		if line.strip_edges().begins_with("- "):
			found.append(line.strip_edges().substr(2).strip_edges())
	return found


## Whether `fact` says nothing new: the same as a memory, or contained in one, or containing one.
static func already_known(known: PackedStringArray, fact: String) -> bool:
	var lower: String = fact.to_lower().trim_suffix(".")
	for memory: String in known:
		var other: String = memory.to_lower().trim_suffix(".")
		if lower in other or other in lower:
			return true
	return false


## The memories left after forgetting `phrase`: those containing it, or else those containing
## every word of it.
static func forget_from(known: PackedStringArray, phrase: String) -> PackedStringArray:
	var wanted: String = phrase.strip_edges().to_lower()
	if wanted.is_empty():
		return known
	var kept: PackedStringArray = PackedStringArray()
	for memory: String in known:
		if not wanted in memory.to_lower():
			kept.append(memory)
	if kept.size() < known.size():
		return kept
	kept.clear()
	var words: PackedStringArray = wanted.split(" ", false)
	for memory: String in known:
		var lower: String = memory.to_lower()
		if not Array(words).all(func(w: String) -> bool: return w in lower):
			kept.append(memory)
	return kept


## {name, triggers, body} from a skill file with a "---" header, or {} when it has none.
static func parse_skill(text: String) -> Dictionary:
	var found: RegExMatch = RegEx.create_from_string("(?s)^\\s*---\\s*\\n(.*?)\\n---\\s*\\n(.*)$").search(text)
	if found == null:
		return {}
	var skill: Dictionary = {"name": "", "triggers": PackedStringArray(), "body": found.get_string(2).strip_edges()}
	for line: String in found.get_string(1).split("\n", false):
		var key: String = line.get_slice(":", 0).strip_edges().to_lower()
		var value: String = line.substr(line.find(":") + 1).strip_edges()
		if key == "name":
			skill["name"] = value
		elif key == "triggers":
			for word: String in value.split(",", false):
				if not word.strip_edges().is_empty():
					skill["triggers"].append(word.strip_edges().to_lower())
	return skill if not skill["name"].is_empty() else {}


## Skills with a trigger word in `text`, most triggers matched first.
static func relevant_skills(all: Array[Dictionary], text: String, limit: int) -> Array[Dictionary]:
	var lower: String = text.to_lower()
	var scored: Array = []
	for skill: Dictionary in all:
		var hits: int = 0
		for trigger: String in skill["triggers"]:
			if RegEx.create_from_string("\\b" + escape(trigger) + "\\b").search(lower) != null:
				hits += 1
		if hits > 0:
			scored.append([hits, skill])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var picked: Array[Dictionary] = []
	for entry: Array in scored.slice(0, limit):
		picked.append(entry[1])
	return picked


static func escape(text: String) -> String:
	var out: String = ""
	for c: String in text:
		out += "\\" + c if c in ".^$*+?()[]{}|\\" else c
	return out


static func slug(text: String) -> String:
	return RegEx.create_from_string("[^a-z0-9]+").sub(text.strip_edges().to_lower(), "-", true).trim_prefix("-").trim_suffix("-")
