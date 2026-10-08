---
name: godot-gdscript
triggers: godot, gdscript, extends, func, signal, onready, node, scene, tscn
---
Usual causes in Godot 4 GDScript, worth checking against the code:
- A `$Name` or `get_node` path that does not match the scene tree leaves an `@onready` variable null.
- A signal connected to a method with a different number of arguments than the signal sends.
- A node freed and then used again.
- Something left paused, hidden or disabled: `get_tree().paused`, `visible`, `process_mode`.
- Godot 3 syntax: `yield`, `onready var` and `export var` without `@`, `instance()`.
