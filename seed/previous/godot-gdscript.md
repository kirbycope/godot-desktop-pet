---
name: godot-gdscript
triggers: godot, gdscript, extends, func, signal, onready, node, scene, tscn
---
The user is working in Godot 4 with GDScript. Common causes worth asking about:

- A node path in `$Name` or `get_node` that does not match the scene tree, or a node used before
  `_ready()`, which leaves `@onready` variables null.
- A signal connected to a method whose name or argument count does not match.
- A node freed and then used again; `is_instance_valid()` guards against that.
- Code in `_process` that should run once, or a timer or tween started every frame.
- Godot 3 syntax in Godot 4, such as `yield` instead of `await`, or `onready var` without the `@`.
