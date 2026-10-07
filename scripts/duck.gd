class_name Duck
extends Node3D
## The rubber duck in 3D, posed in code: it waddles, hops, tilts, quacks and tumbles.
##
## It keeps the AnimatedSprite2D's little interface (`play()`, `animation`) so the pet drives it the
## same way it drove the 2D robot. `roll` stands it on whichever screen edge it is on, and `facing`
## turns it left or right.

## Everything the pet asks for. The model's own "Take 001" clip is not used.
const ANIMATIONS: Array[StringName] = [&"walk", &"climb", &"hang", &"idle", &"cheer", &"think", &"talk", &"fall", &"land"]
## Where the model's base sits: the bottom of the 0.34 m tall orthographic view, a hair above it.
const BASE: Vector3 = Vector3(0.0, -0.168, 0.0)

## Degrees the duck turns towards the camera, so it is seen three-quarters on rather than in profile.
@export_range(0.0, 90.0) var turn_to_camera: float = 30.0

var animation: StringName = &"idle"
## +1 faces right (the model's +X), -1 faces left, both along the edge it stands on.
var facing: int = 1:
	set(value):
		facing = value
		if is_node_ready():
			yaw.rotation_degrees.y = yaw_for(facing, turn_to_camera)
## Degrees round the view axis: 0 on the floor, 90 on the right wall, 180 on the ceiling, -90 on the left.
var roll: float = 0.0:
	set(value):
		roll = value
		if is_node_ready():
			pivot.rotation_degrees.z = roll
var _time: float = 0.0

@onready var pivot: Node3D = $Pivot
@onready var body: Node3D = $Pivot/Body
@onready var yaw: Node3D = $Pivot/Body/Yaw


func _ready() -> void:
	yaw.rotation_degrees.y = yaw_for(facing, turn_to_camera)
	pivot.rotation_degrees.z = roll


func _process(delta: float) -> void:
	_time += delta
	var p: Array = pose(animation, _time)
	body.position = p[0]
	body.rotation_degrees = p[1]
	body.scale = p[2]


func play(name: StringName) -> void:
	if name != animation:
		_time = 0.0
	animation = name


static func yaw_for(toward: int, turn: float) -> float:
	return -turn if toward > 0 else 180.0 + turn


## [offset from the duck's base point, rotation in degrees, scale] at `t` seconds into `anim`.
## The base point is the bottom of the view, so rotations pivot on the duck's bottom.
static func pose(anim: StringName, t: float) -> Array:
	var offset: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var size: Vector3 = Vector3.ONE
	match anim:
		&"walk":
			rotation.z = sin(t * 10.0) * 8.0
			offset.y = absf(sin(t * 10.0)) * 0.008
		&"climb":
			rotation.z = sin(t * 14.0) * 10.0
			offset.y = absf(sin(t * 14.0)) * 0.006
		&"hang":
			rotation.z = sin(t * 3.0) * 12.0
		&"idle":
			offset.y = (sin(t * 2.0) + 1.0) * 0.003
			rotation.y = sin(t * 0.7) * 10.0
		&"cheer":
			offset.y = absf(sin(t * 6.0)) * 0.04
			rotation.y = fmod(t * 360.0, 360.0)
		&"think":
			rotation.z = 14.0 * minf(t * 4.0, 1.0)
			rotation.y = sin(t * 1.5) * 15.0
		&"talk":
			size.y = 1.0 + absf(sin(t * 14.0)) * 0.07
			size.x = 1.0 - absf(sin(t * 14.0)) * 0.03
			rotation.z = sin(t * 7.0) * 3.0
		&"fall":
			offset.y = 0.06
			rotation.z = fmod(t * 540.0, 360.0)
		&"land":
			var squash: float = maxf(0.0, 1.0 - t / 0.4)
			size = Vector3(1.0 + 0.18 * squash, 1.0 - 0.25 * squash, 1.0 + 0.18 * squash)
	return [BASE + offset, rotation, size]
