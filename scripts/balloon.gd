@tool
extends RigidBody2D

## World offset from the platform (in pixels). The balloon's world
## position is set each physics frame to parent.global_position + offset.
## Does NOT rotate with the platform — this is intentional buoyancy behavior:
## the balloon always stays at this world offset above (or relative to) the
## platform, regardless of how the platform rotates due to the level's clock ticks.
@export var offset: Vector2 = Vector2(0, -50)

## Mass of the balloon. Lower = more floaty / buoyant feel.
@export var balloon_mass: float = 0.5

## Radius of the balloon's collision shape. Used by the detect-and-nudge
## pass that pushes overlapping balloons apart.
@export var collision_radius: float = 8.0

@onready var string_line: Line2D = $StringLine


func _ready() -> void:
	mass = balloon_mass
	add_to_group("balloons")


func _physics_process(_delta: float) -> void:
	# Drive the balloon's world position directly each physics frame.
	# We override the engine's auto-global-transform behavior (which would
	# rotate the balloon with the platform, since BalloonPlatform is a
	# constantly-moving RigidBody2D ancestor). Direct positioning gives the
	# "buoyant above the platform" visual regardless of platform rotation.
	var platform := get_parent() as Node2D
	if not platform:
		return

	# Per-balloon phase-offset floating motion. Different phase per balloon
	# (derived from offset.x) keeps the cluster from being perfectly static
	# — the balloons drift slightly out of sync, giving them an "alive" feel.
	# The detect-and-nudge pass below resolves any overlap this causes.
	var time := Time.get_ticks_msec() / 1000.0
	var float_offset := Vector2(0.0, sin(time * 2.0 + offset.x * 0.5) * 2.0)

	var final_position := platform.global_position + offset + float_offset

	# Detect "overlap" with other balloons via group lookup and proximity check.
	# get_overlapping_bodies() is an Area2D method, not RigidBody2D, so we
	# iterate the "balloons" group and check distance ourselves. (Adding
	# contact_monitor + get_colliding_bodies() would also work but would only
	# fire on actual physical contact, not proximity — and our spacing doesn't
	# produce physical contact.)
	for other in get_tree().get_nodes_in_group("balloons"):
		if other == self:
			continue
		if not (other is RigidBody2D):
			continue
		var to_other: Vector2 = other.global_position - final_position
		var distance := to_other.length()
		if distance > 0.0 and distance < 2.0 * collision_radius:
			var overlap := 2.0 * collision_radius - distance
			final_position -= to_other.normalized() * overlap * 0.5

	global_position = final_position
	global_rotation = 0.0


func _process(_delta: float) -> void:
	# Update the visual "string" line connecting the balloon to the platform.
	# Since we lock the balloon's rotation to 0 in _physics_process, the
	# line's local frame matches world coords — so the platform-side endpoint
	# is just platform.global_position - global_position.
	if string_line:
		var platform := get_parent() as Node2D
		if platform:
			string_line.points = [
				Vector2(0, 0),
				platform.global_position - global_position,
			]