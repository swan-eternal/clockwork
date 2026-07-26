extends RigidBody2D

# Decorative balloon attached to a buoyant platform in Clockwork.
#
# Each physics frame, reads the current gravity from the global
# GravityManager singleton and applies an anti-gravity buoyancy force
# at the cached _anti_gravity direction. A DampedSpringJoint2D in the
# parent platform keeps the balloon tethered to the platform's center.
#
# The balloon has no collision (collision_layer=0, mask=0 in the scene
# file) so it never interacts with the player, walls, or other bodies —
# purely visual.
#
# When the parent platform's motion_type is WEIGHT, the balloon is
# frozen by platform.gd (no physics sim, no force application) and
# invisible. The motion_type setter handles the toggle.

# Buoyancy force magnitude, set by platform.gd in its setter chain.
# Force is applied along the cached anti-gravity direction each
# physics tick — higher values pull the balloon harder against gravity,
# which the spring joint counters to settle at rest_length offset.
var buoyancy_strength: float = 200.0

# Cached anti-gravity direction. Recomputed each physics frame from
# GravityManager.gravity_direction. Defaults to Vector2.UP as a safe
# starting state before the singleton is queried.
var _anti_gravity: Vector2 = Vector2.UP


func _ready() -> void:
	# Defensive: explicitly unfreeze in case platform.gd's setter chain
	# hasn't run yet (Godot property-setting order isn't strictly
	# guaranteed — child's properties may be set before the parent's
	# setters that override them). platform.gd's motion_type setter
	# re-applies the correct freeze state, so this is a one-shot fix
	# that gets overwritten if motion_type=WEIGHT.
	freeze = false


func _physics_process(_delta: float) -> void:
	# `freeze` is set externally by platform.gd (gated on motion_type
	# and balloon_enabled). When frozen, no physics sim and no force
	# application — the balloon sits anchored at its initial position.
	if freeze:
		return
	# Read gravity directly from the global singleton each tick. A
	# Vector2 read is cheap and avoids the "did I miss the signal?"
	# bug class entirely — no subscription bookkeeping.
	var g: Vector2 = GravityManager.gravity_direction
	_anti_gravity = -g.normalized()
	apply_central_force(_anti_gravity * buoyancy_strength)