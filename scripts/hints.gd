class_name Hints
## Quick checks done in code for the slips a small model reads straight past: a misspelt node path
## or property, a fetch that is not awaited, Godot 3 syntax, a loop one past the end, a flag set and
## never set back. They go to the model as things to check, not as answers, and only fire when they
## are right nearly every time: a wrong hint is worse than none.


## Things to check in `screen` (the OCR text) and `said` (what the user has said in this
## conversation), each a sentence.
static func for_text(screen: String, said: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var all: String = screen + "\n" + said
	found.append_array(misspelt_names(all))
	found.append_array(unawaited_fetch(all))
	found.append_array(godot_3(all))
	found.append_array(one_past_the_end(all))
	found.append_array(never_set_back(said, all))
	found.append_array(error_location(screen))
	return found


## A node path (`$Sprit`, `get_node("Sprit")`) or a property (`item.prise`) whose name turns up
## nowhere else on screen while a name one or two letters away does.
static func misspelt_names(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var words: Dictionary = {}
	for hit: RegExMatch in RegEx.create_from_string(r"[A-Za-z_][A-Za-z0-9_]{2,}").search_all(text):
		words[hit.get_string()] = int(words.get(hit.get_string(), 0)) + 1
	var used: RegEx = RegEx.create_from_string(r"(\$|get_node\(\"|\w\.)([A-Za-z_][A-Za-z0-9_]{3,})")
	var seen: Dictionary = {}
	for hit: RegExMatch in used.search_all(text):
		var name: String = hit.get_string(2)
		if seen.has(name) or int(words.get(name, 0)) > 1:
			continue
		seen[name] = true
		var close: String = closest(name, words.keys())
		if close.is_empty():
			continue
		var shown: String = ("$" + name) if hit.get_string(1) == "$" else name
		found.append("`%s` appears only here, but `%s` is on screen too: is it spelt right?" % [shown, close])
	return found


## The other word in `words` one or two edits from `name` (and not just a different case or an
## added "s"), or "".
static func closest(name: String, words: Array) -> String:
	var best: String = ""
	var best_distance: int = 3
	for word: Variant in words:
		var other: String = str(word)
		if other == name or other.length() < 4 or other.to_lower() == name.to_lower() or other == name + "s" or name == other + "s":
			continue
		if absi(other.length() - name.length()) > 2:
			continue
		var d: int = distance(name, other)
		if d < best_distance:
			best_distance = d
			best = other
	return best


## Levenshtein distance.
static func distance(a: String, b: String) -> int:
	var row: PackedInt32Array = PackedInt32Array()
	for j: int in b.length() + 1:
		row.append(j)
	for i: int in range(1, a.length() + 1):
		var diagonal: int = row[0]
		row[0] = i
		for j: int in range(1, b.length() + 1):
			var above: int = row[j]
			row[j] = mini(mini(row[j] + 1, row[j - 1] + 1), diagonal + (0 if a[i - 1] == b[j - 1] else 1))
			diagonal = above
	return row[b.length()]


static func unawaited_fetch(text: String) -> PackedStringArray:
	var hit: RegExMatch = RegEx.create_from_string(r"(?m)^[^\n]*=\s*fetch\(").search(text)
	if hit == null or "await" in hit.get_string() or ".then(" in text:
		return PackedStringArray()
	return PackedStringArray(["`fetch(...)` is not awaited there, so what it gives back is a promise, not the response: should it be `await fetch(...)`?"])


static func godot_3(text: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if RegEx.create_from_string(r"(?m)^\s*onready\s+var").search(text) != null:
		found.append("`onready var` is Godot 3 syntax; Godot 4 writes `@onready var`.")
	if RegEx.create_from_string(r"(?m)^\s*export(\(.*\))?\s+var").search(text) != null:
		found.append("`export var` is Godot 3 syntax; Godot 4 writes `@export var`.")
	if RegEx.create_from_string(r"\byield\s*\(").search(text) != null:
		found.append("`yield(...)` is Godot 3; Godot 4 waits with `await`, as in `await anim.animation_finished`.")
	if RegEx.create_from_string(r"\.connect\(\s*\"\w+\"\s*,\s*self").search(text) != null:
		found.append("`connect(\"signal\", self, \"method\")` is Godot 3; Godot 4 writes `signal_name.connect(method)`.")
	if RegEx.create_from_string(r"\.instance\(\)").search(text) != null:
		found.append("`.instance()` is Godot 3; Godot 4 calls it `.instantiate()`.")
	return found


static func one_past_the_end(text: String) -> PackedStringArray:
	var hit: RegExMatch = RegEx.create_from_string(r"range\(\s*len\((\w+)\)\s*\+\s*1\s*\)").search(text)
	if hit == null:
		return PackedStringArray()
	return PackedStringArray(["`%s` goes one past the last index of `%s`, which ends at `len(%s) - 1`." % [hit.get_string(), hit.get_string(1), hit.get_string(1)]])


## Something the user says they set to true that is set back to false nowhere, the usual reason a
## thing stays paused, hidden or disabled.
static func never_set_back(said: String, all: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for hit: RegExMatch in RegEx.create_from_string(r"([A-Za-z_][\w.()]*)\s*=\s*true\b").search_all(said):
		var name: String = hit.get_string(1)
		if RegEx.create_from_string(Mind.escape(name) + r"\s*=\s*false").search(all) == null:
			found.append("`%s` is set to true, and nothing they said or showed sets it back to false." % name)
	return found


## Where a traceback or debugger line says the error happened.
static func error_location(screen: String) -> PackedStringArray:
	var python: RegExMatch = RegEx.create_from_string(r"File \"([^\"]+)\", line (\d+)").search(screen)
	if python != null:
		return PackedStringArray(["The error points at %s line %s." % [python.get_string(1), python.get_string(2)]])
	var godot: RegExMatch = RegEx.create_from_string(r"(res://[\w/.-]+):(\d+)").search(screen)
	if godot != null:
		return PackedStringArray(["The error points at %s line %s." % [godot.get_string(1), godot.get_string(2)]])
	return PackedStringArray()
