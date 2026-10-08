extends SceneTree
## How good and how quick the duck is at debugging: eight situations, each run ROUNDS times through
## the duck's own pipeline, in a scratch mind folder. An answer scores when it matches the case's
## pattern, the words a right answer has to contain. DUCK_MODEL picks a model.
##
##   godot --headless --path . -s res://tools/debug_bench.gd

const ROUNDS: int = 3
const FOLDER: String = "user://debug_bench"

## name, turns [[line, screen text]], and the pattern the last answer must match to score.
const CASES: Array = [
	{"name": "gdscript-null-path", "pattern": r"\$Sprit\b|typo|spell|\bSprit\b", "turns": [["why does this crash?", "player.gd\nextends CharacterBody2D\n@onready var sprite: Sprite2D = $Sprit\nfunc _ready() -> void:\n    sprite.modulate = Color.RED\nDebugger  Errors 1\nInvalid assignment of property or key 'modulate' with value of type 'Color' on a base object of type 'null instance'.\nres://player.gd:5 - at function: _ready\nScene  Player (CharacterBody2D)  Sprite (Sprite2D)  CollisionShape2D"]]},
	{"name": "python-average", "pattern": r"\+=|\badd(s|ing)?\b|accumulat|\bsum\b", "turns": [["my average is wrong, it should be 90", "average.py\ndef average(scores):\n    total = 0\n    for s in scores:\n        total = s\n    return total / len(scores)\nprint(average([80, 90, 100]))\nTERMINAL\n33.333333333333336"]]},
	{"name": "js-fetch-await", "pattern": r"(await|awaited)[^.?!]*fetch|fetch[^.?!]*(await|awaited)", "turns": [["what's going on here?", "user.js\nasync function loadUser(id) {\n  const res = fetch(`/api/users/${id}`);\n  const data = await res.json();\n  return data.name;\n}\nConsole\nUncaught (in promise) TypeError: res.json is not a function\n    at loadUser (user.js:3)"]]},
	{"name": "talked-through-pause", "pattern": r"paused\s*=\s*false|unpause|un-pause|still paused|never (un|set)|paused[^.?!]*(back|again|false|still true)", "turns": [
		["I'm stuck. My game's enemies stop moving after the first wave and I don't know why.", ""],
		["After the wave I show the shop and set get_tree().paused = true. When the shop closes I set Engine.time_scale = 1 and hide the shop. The enemies spawn fine, they just don't move.", ""],
	]},
	{"name": "gdscript-signal-args", "pattern": r"argument|parameter|\bdamage\b", "turns": [["why does this error when the enemy hits me?", "enemy.gd\nextends Area2D\nsignal hit(damage: int)\nfunc _on_body_entered(body: Node2D) -> void:\n    hit.emit(10)\nplayer.gd\nfunc _ready() -> void:\n    $Enemy.hit.connect(_on_enemy_hit)\nfunc _on_enemy_hit() -> void:\n    health -= 1\nDebugger  Errors 1\nError calling from signal 'hit' to callable: 'CharacterBody2D(player.gd)::_on_enemy_hit': Method expected 0 arguments, but called with 1."]]},
	{"name": "gdscript-godot3", "pattern": r"@onready|onready[^.?!]*@|\bannotation", "turns": [["this script won't run, what's wrong?", "door.gd\nextends Node2D\nonready var anim = $AnimationPlayer\nfunc open():\n    anim.play(\"open\")\n    yield(anim, \"animation_finished\")\n    queue_free()\nDebugger  Errors 2\nParse Error: Unexpected \"Identifier\" in class body.\nParse Error: \"yield\" was removed in Godot 4. Use \"await\" instead."]]},
	{"name": "python-index", "pattern": r"\+ ?1|off.by.one|one too (many|far)|one (extra|more)|extra (index|value)|one past|range\(len\(names\)\)|past the end|beyond the (end|last)", "turns": [["why does this crash at the end?", "names.py\nnames = [\"Ann\", \"Bob\", \"Cy\"]\nfor i in range(len(names) + 1):\n    print(i, names[i])\nTERMINAL\n0 Ann\n1 Bob\n2 Cy\nTraceback (most recent call last):\n  File \"names.py\", line 3, in <module>\n    print(i, names[i])\nIndexError: list index out of range"]]},
	{"name": "js-property-typo", "pattern": r"prise|typo|spell|misspel", "turns": [["why is my total NaN?", "cart.js\nconst item = { name: \"Duck\", price: 4 };\nconst total = item.prise * 2;\nconsole.log(total);\nConsole\nNaN"]]},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_empty(FOLDER)
	var pet: Node = load("res://scenes/pet.tscn").instantiate()
	var mind: Mind = pet.get_node("Mind")
	mind.root = FOLDER
	var brain: Brain = pet.get_node("Brain")
	brain.model_alias = OS.get_environment("DUCK_MODEL")
	root.add_child(pet)
	while not brain.is_ready():
		await create_timer(1.0).timeout
	print("MODEL ", brain.model_id)
	var scores: Dictionary = {}
	var timing_sums: Dictionary = {"first_token": 0.0, "first_sentence": 0.0, "reply": 0.0}
	var turns: int = 0
	for round: int in ROUNDS:
		for case: Dictionary in CASES:
			# Each situation starts a fresh conversation.
			brain.messages = [brain.messages[0]]
			var reply: String = ""
			for turn: Array in case["turns"]:
				brain.ask(turn[0], turn[1])
				reply = await brain.replied
				turns += 1
				var timed: Variant = brain.get("timings")
				for key: String in timing_sums:
					timing_sums[key] += float(timed.get(key, 0)) if timed is Dictionary else 0.0
			var hit: bool = RegEx.create_from_string("(?i)" + String(case["pattern"])).search(reply) != null
			scores[case["name"]] = int(scores.get(case["name"], 0)) + (1 if hit else 0)
			print("\n=== %s %d %s\nDUCK: %s\nTIMINGS: %s" % [case["name"], round + 1, "HIT" if hit else "miss", reply, brain.get("timings")])
	var total: int = 0
	print("\nSCORES (of %d each)" % ROUNDS)
	for case: Dictionary in CASES:
		print("  %-22s %d" % [case["name"], scores.get(case["name"], 0)])
		total += int(scores.get(case["name"], 0))
	print("TOTAL %d of %d" % [total, CASES.size() * ROUNDS])
	print("MEAN first word %d ms, first sentence %d ms, whole %d ms" % [timing_sums["first_token"] / turns, timing_sums["first_sentence"] / turns, timing_sums["reply"] / turns])
	pet.queue_free()
	await process_frame
	_empty(FOLDER)
	quit()


func _empty(path: String) -> void:
	for sub: String in DirAccess.get_directories_at(path):
		_empty(path.path_join(sub))
	for file: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file)))
