class_name Duck
extends Node3D
## The rubber duck in 3D, posed in code: it waddles, hops, tilts, quacks and tumbles.
##
## It keeps the AnimatedSprite2D's little interface (`play()`, `animation`) so the pet drives it the
## same way it drove the 2D robot. `roll` stands it on whichever screen edge it is on, and `facing`
## turns it left or right.

## Everything the pet asks for. The model's own "Take 001" clip is not used.
const ANIMATIONS: Array[StringName] = [&"walk", &"climb", &"hang", &"idle", &"cheer", &"think", &"talk", &"fall", &"land", &"squeeze", &"sleep", &"wake"]
## How long one hop of `cheer` takes: crouch, leap, land, settle.
const HOP_SECONDS: float = 0.9
## The yaw that points the model's face (its +X) at the camera.
const VIEWER_YAW: float = -90.0
## Where the model's base sits: the bottom of the 0.4156 m tall orthographic view, a hair above it.
## The view is taller than the duck so the captain's hat stays in it when the duck stretches to fall
## or hop; the pivot it rolls about is the view's centre, 0.0378 m above the model's origin.
const BASE: Vector3 = Vector3(0.0, -0.205778, 0.0)

## The tomato's colours, in place of the model's yellow body (surface 0) and orange beak (surface 1).
@export var tomato_skin: Material
@export var tomato_beak: Material
## Degrees the duck turns towards the camera, so it is seen three-quarters on rather than in profile.
@export_range(0.0, 90.0) var turn_to_camera: float = 30.0
## How quickly it turns, to look at you or to walk the other way; higher is quicker.
@export var turn_speed: float = 10.0

var animation: StringName = &"idle"
## +1 faces right (the model's +X), -1 faces left, both along the edge it stands on.
var facing: int = 1
## True while it is talking with you: it turns round to face the camera, and perks up as it does.
var looking_at_viewer: bool = false:
	set(value):
		if value and not looking_at_viewer:
			_perk_time = 0.0
		looking_at_viewer = value
## Degrees round the view axis: 0 on the floor, 90 on the right wall, 180 on the ceiling, -90 on the left.
var roll: float = 0.0:
	set(value):
		roll = value
		if is_node_ready():
			pivot.rotation_degrees.z = roll
## Wears the captain's hat (scenes/hat.tscn, sitting on its head and turning with it).
var hat: bool = false:
	set(value):
		hat = value
		if is_node_ready():
			_dress()
## A tomato, while the Pomodoro timer runs: red all over, with green leaves on its head
## (scenes/tomato_leaves.tscn) where the hat would be. The eyes stay as they are.
var tomato: bool = false:
	set(value):
		tomato = value
		if is_node_ready():
			_dress()
var _time: float = 0.0
var _perk_time: float = INF

@onready var pivot: Node3D = $Pivot
@onready var body: Node3D = $Pivot/Body
@onready var yaw: Node3D = $Pivot/Body/Yaw
@onready var hat_node: Node3D = $Pivot/Body/Yaw/Hat
@onready var leaves: Node3D = $Pivot/Body/Yaw/Leaves
@onready var model_mesh: MeshInstance3D = $"Pivot/Body/Yaw/Model/Rubber Duck"
@onready var zzz: Array[Label3D] = [$Zzz/Z1, $Zzz/Z2, $Zzz/Z3]


func _ready() -> void:
	yaw.rotation_degrees.y = target_yaw()
	pivot.rotation_degrees.z = roll
	_dress()


## The hat, or the tomato's leaves and colours in its place.
func _dress() -> void:
	hat_node.visible = hat and not tomato
	leaves.visible = tomato
	model_mesh.set_surface_override_material(0, tomato_skin if tomato else null)
	model_mesh.set_surface_override_material(1, tomato_beak if tomato else null)


func _process(delta: float) -> void:
	_time += delta
	_perk_time += delta
	var p: Array = pose(animation, _time)
	body.position = p[0]
	body.rotation_degrees = p[1]
	body.scale = p[2] * squash(perk(_perk_time))
	# Eases round rather than snapping; turning about takes the short way, past your side.
	yaw.rotation.y = lerp_angle(yaw.rotation.y, deg_to_rad(target_yaw()), 1.0 - exp(-turn_speed * delta))
	for i: int in zzz.size():
		zzz[i].visible = animation == &"sleep"
		if zzz[i].visible:
			var z: Array = z_at(_time, i)
			zzz[i].position = z[0]
			zzz[i].modulate.a = z[1]
			zzz[i].scale = Vector3.ONE * z[2]


## Where it faces now: you while it talks with you, otherwise the way it is going.
func target_yaw() -> float:
	return VIEWER_YAW if looking_at_viewer else yaw_for(facing, turn_to_camera)


## Plays `name`; one already playing carries on, unless `from_start`, as for a squeeze on each tap.
func play(name: StringName, from_start: bool = false) -> void:
	if name != animation or from_start:
		_time = 0.0
	animation = name


static func yaw_for(toward: int, turn: float) -> float:
	return -turn if toward > 0 else 180.0 + turn


## [offset from the duck's base point, rotation in degrees, scale] at `t` seconds into `anim`.
## The base point is the bottom of the view, so rotations and scaling pivot on the duck's bottom and
## a squash keeps it sitting on its edge.
##
## Every move uses squash and stretch: the duck flattens as it lands or gathers itself, stretches as
## it rises, falls or dangles, and its volume stays the same throughout (`squash`), so it reads as
## soft rubber rather than as something shrinking. Impacts settle with a damped wobble (`settle`).
static func pose(anim: StringName, t: float) -> Array:
	var offset: Vector3 = Vector3.ZERO
	var rotation: Vector3 = Vector3.ZERO
	var stretch: float = 0.0
	match anim:
		&"walk":
			# Squashed as each foot lands, stretched at the top of the step.
			var step: float = absf(sin(t * 10.0))
			rotation.z = sin(t * 10.0) * 8.0
			offset.y = step * 0.008
			stretch = (step * 2.0 - 1.0) * 0.06
		&"climb":
			var step: float = absf(sin(t * 14.0))
			rotation.z = sin(t * 14.0) * 10.0
			offset.y = step * 0.006
			stretch = (step * 2.0 - 1.0) * 0.05
		&"hang":
			# Dangling: pulled long by its own weight, swinging.
			rotation.z = sin(t * 3.0) * 12.0
			stretch = 0.1 + sin(t * 6.0) * 0.03
		&"idle":
			# Breathing.
			offset.y = (sin(t * 2.0) + 1.0) * 0.003
			rotation.y = sin(t * 0.7) * 10.0
			stretch = sin(t * 2.0) * 0.025
		&"cheer":
			var hop: Array = hop_at(fmod(t, HOP_SECONDS))
			offset.y = hop[0]
			stretch = hop[1]
			rotation.y = hop[2]
		&"think":
			rotation.z = 14.0 * minf(t * 4.0, 1.0)
			rotation.y = sin(t * 1.5) * 15.0
			stretch = -0.04 * minf(t * 4.0, 1.0) + sin(t * 1.5) * 0.015
		&"talk":
			# A stretch on every syllable, a little squash between them.
			var syllable: float = absf(sin(t * 14.0))
			rotation.z = sin(t * 7.0) * 3.0
			stretch = syllable * 0.12 - 0.03
		&"fall":
			# Stretched along the fall, more the longer it falls.
			offset.y = 0.06
			rotation.z = sin(t * 9.0) * 10.0
			stretch = 0.22 * minf(t / 0.15, 1.0)
		&"land":
			# Flattened by the impact, then wobbling back past round and settling.
			stretch = settle(t, -0.38, 20.0, 7.0)
		&"sleep":
			# Settled low and breathing slowly and deeply, head nodding.
			rotation.z = -8.0 + sin(t * 1.2) * 3.0
			stretch = -0.05 + sin(t * 1.6) * 0.035
		&"wake":
			# A big stretch and yawn, then a wobble as it comes to.
			if t < 0.45:
				stretch = 0.24 * sin(PI * 0.5 * t / 0.45)
				rotation.z = -8.0 * (1.0 - t / 0.45)
			else:
				stretch = settle(t - 0.45, 0.24, 16.0, 6.0)
		&"squeeze":
			# Squeezed like a real rubber duck as it squeaks: flattened hard, then springing back.
			stretch = settle(t, -0.32, 24.0, 6.5)
			rotation.z = settle(t, 6.0, 24.0, 6.5)
	return [BASE + offset, rotation, squash(stretch)]


## [position, opacity, size] of the `index`th Z of three, rising from the duck's head while it
## sleeps, each a third of a cycle behind the last.
static func z_at(t: float, index: int) -> Array:
	var phase: float = fmod(t * 0.5 + index / 3.0, 1.0)
	return [Vector3(0.02 + phase * 0.05, 0.04 + phase * 0.11, 0.1), sin(PI * phase), 0.6 + phase * 0.8]


## A scale that stretches the duck along its up axis (`amount` above 0) or squashes it (below 0)
## while keeping its volume: what it loses in height it gains in width and depth.
static func squash(amount: float) -> Vector3:
	var height: float = maxf(1.0 + amount, 0.2)
	var width: float = 1.0 / sqrt(height)
	return Vector3(width, height, width)


## The stretch of perking up to look at you: it rises, stands tall, dips past round and settles.
static func perk(t: float) -> float:
	return 0.14 * exp(-6.0 * t) * sin(16.0 * t) if t < 2.0 else 0.0


## A damped wobble: `amplitude` at the start, overshooting the other way and dying away.
## `speed` is in radians a second, `damping` how fast it dies.
static func settle(t: float, amplitude: float, speed: float, damping: float) -> float:
	return amplitude * exp(-damping * t) * cos(speed * t)


## [height, stretch, spin in degrees] at `u` seconds into one hop: a crouch to gather itself, a
## stretched leap with a spin, a squash as it lands, then a wobble before the next.
static func hop_at(u: float) -> Array:
	const CROUCH: float = 0.15
	const AIR: float = 0.35
	if u < CROUCH:
		return [0.0, -0.18 * sin(PI * 0.5 * u / CROUCH), 0.0]
	if u < CROUCH + AIR:
		var flight: float = (u - CROUCH) / AIR
		return [0.05 * sin(PI * flight), 0.16 * (1.0 - flight) - 0.04 * flight, 360.0 * flight]
	return [0.0, settle(u - CROUCH - AIR, -0.22, 22.0, 9.0), 0.0]
