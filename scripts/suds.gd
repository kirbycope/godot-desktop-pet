class_name Suds
extends MultiMeshInstance3D
## The bubble bath's foam, as geometry: many small foam bubbles (the `sud_mesh`, drawn with
## assets/water/suds.gdshader), piled round the duck where it sits in the water, densest against it
## and thinning outward, and gathered into clumps floating about the bath. Placed once from `seed`,
## so the bath looks the same every time.

## One foam bubble: a sphere of radius 0.5, scaled per bubble.
@export var sud_mesh: Mesh
@export var seed: int = 7
## The water's surface, in metres; the suds sit half sunk in it.
@export var water_level: float = -0.13
## Half the duck's footprint across (x) and front to back (z); the pile starts at its edge.
@export var footprint: Vector2 = Vector2(0.125, 0.15)
## How far the pile reaches out from the duck, in metres.
@export var pile_width: float = 0.07
@export var pile_count: int = 280
## Floating clumps: how many, how many bubbles each, and where they may float (x, z, width, depth).
@export var clumps: int = 8
@export var clump_size: Vector2i = Vector2i(30, 80)
@export var area: Rect2 = Rect2(-1.0, -2.8, 2.0, 2.9)
## Bubble sizes, as radii in metres.
@export var radius: Vector2 = Vector2(0.004, 0.017)


func _ready() -> void:
	build()


func build() -> void:
	var placed: Array[Transform3D] = layout(seed, water_level, footprint, pile_width, pile_count, clumps, clump_size, area, radius)
	var mesh_set: MultiMesh = MultiMesh.new()
	mesh_set.transform_format = MultiMesh.TRANSFORM_3D
	mesh_set.mesh = sud_mesh
	mesh_set.instance_count = placed.size()
	for i: int in placed.size():
		mesh_set.set_instance_transform(i, placed[i])
	multimesh = mesh_set


## Where every foam bubble goes: the pile round the duck first, then the clumps.
static func layout(seed_value: int, level: float, foot: Vector2, width: float, pile: int, clump_total: int, per_clump: Vector2i, region: Rect2, radii: Vector2) -> Array[Transform3D]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var placed: Array[Transform3D] = []
	for i: int in pile:
		var angle: float = rng.randf() * TAU
		# Most of the pile hugs the duck; a few bubbles stray further out.
		var out: float = pow(rng.randf(), 2.0) * width
		var r: float = rng.randf_range(radii.x, radii.y) * (1.0 - out / width * 0.5)
		var at: Vector3 = Vector3(cos(angle) * (foot.x + out + r * 0.5), 0.0, sin(angle) * (foot.y + out + r * 0.5))
		at.y = level + r * rng.randf_range(0.0, 0.6) + (width - out) / width * r * 0.8
		placed.append(Transform3D(Basis.from_scale(Vector3.ONE * r * 2.0), at))
	for c: int in clump_total:
		var centre: Vector3 = Vector3(rng.randf_range(region.position.x, region.end.x), level, rng.randf_range(region.position.y, region.end.y))
		# Clear of the duck and its pile.
		if Vector2(centre.x / (foot.x + width + 0.12), centre.z / (foot.y + width + 0.12)).length() < 1.0:
			centre.x += signf(centre.x if centre.x != 0.0 else 1.0) * (foot.x + width + 0.2)
		var spread: float = rng.randf_range(0.05, 0.13)
		for i: int in rng.randi_range(per_clump.x, per_clump.y):
			var angle: float = rng.randf() * TAU
			var out: float = sqrt(rng.randf()) * spread
			var r: float = rng.randf_range(radii.x, radii.y) * (1.0 - out / spread * 0.5)
			# A mound: highest in the middle.
			var rise: float = (1.0 - out / spread) * spread * 0.35
			var at: Vector3 = centre + Vector3(cos(angle) * out, rise + r * rng.randf_range(-0.3, 0.4), sin(angle) * out * 0.8)
			placed.append(Transform3D(Basis.from_scale(Vector3.ONE * r * 2.0), at))
	return placed
