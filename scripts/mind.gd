class_name Mind
extends Node
## What the duck knows about itself and you, kept as plain text files in its own folder.
##
##   user://duck/personality.md   how it talks; seeded from res://seed on first run, then yours to edit
##   user://duck/memories.md      one remembered fact per "- " line
##   user://duck/skills/*.md      instructions brought in when a message mentions their trigger words
##   user://duck/name.txt         its name, once it has one
##   user://duck/conversations/   everything said, one Markdown file a day; the last few exchanges
##                                go back into the prompt when the duck starts again
##
## The model asks for changes with tags at the end of a reply, such as [remember: ...]; `digest`
## carries them out and strips them before the reply is shown or spoken.

## Something was remembered, forgotten, learned or renamed, for the bubble to mention.
signal changed(note: String)

## The duck's folder. Tests point it elsewhere.
@export var root: String = "user://duck"
## Where the first copies of the personality and the skills come from.
@export var seed: String = "res://seed"
## Memories beyond this many are left out of the prompt, oldest first.
@export var max_memories: int = 40
## At most this many skills go with one message.
@export var max_skills: int = 2

const TAG: String = "\\[(remember|forget|name|skill):\\s*(.*?)\\]"
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
	parts.append(personality())
	parts.append(PROTOCOL)
	var known: PackedStringArray = memories()
	if not known.is_empty():
		var recent: PackedStringArray = known.slice(maxi(0, known.size() - max_memories))
		parts.append("What you remember:\n- " + "\n- ".join(recent))
	var all_skills: Array[Dictionary] = skills()
	if not all_skills.is_empty():
		parts.append("Skills you have, brought in when they apply: " + ", ".join(all_skills.map(func(s: Dictionary) -> String: return s["name"])) + ".")
	return "\n\n".join(parts)


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
	return RegEx.create_from_string("\\s*" + TAG).sub(reply, "", true).strip_edges()


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
