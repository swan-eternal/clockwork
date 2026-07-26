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

# Debug flag for the off-axis-settling bug. While true, _physics_process
# prints the current gravity, computed anti-gravity, positions, and
# velocity every ~0.5 sec so we can see what the balloon is doing as
# gravity rotates. Set to false once the bug is found and fixed.
const DEBUG_OUTPUT: bool = true

# Frame counter for the throttled debug print.
var _debug_frame_count: int = 0


func _ready() -> void:
	# Defensive: explicitly unfreeze in case platform.gd's setter chain
	# hasn't run yet (Godot property-setting order isn't strictly
	# guaranteed — child's properties may be set before the parent's
	# setters that override them). platform.gd's motion_type setter
	# re-applies the correct freeze state, so this is a one-shot fix
	# that gets overwritten if motion_type=WEIGHT.
	freeze = false
	# Belt-and-suspenders against the off-axis-settling bug. If the
	# body sleeps, the spring can't pull it back to the cardinal
	# equilibrium — forces don't apply to sleeping bodies. The
	# `can_sleep = false` flag in the scene file should already do
	# this, but it apparently isn't taking effect at runtime, so set
	# it again in code and explicitly wake the body.
	can_sleep = false
	sleeping = false


func _physics_process(_delta: float) -> void:
	# `freeze` is set externally by platform.gd (gated on motion_type
	# and balloon_enabled). When frozen, no physics sim and no force
	# application — the balloon sits anchored at its initial position.
	if freeze:
		return
	# Keep the body awake each frame. The spring force at the wrong
	# displacement should pull the balloon back to the cardinal
	# equilibrium, but only if the body is awake. Without this, a
	# brief moment of low velocity can put the body to sleep and the
	# spring stops being able to correct it.
	if sleeping:
		wake_up()
	# Read gravity directly from the global singleton each tick. A
	# Vector2 read is cheap and avoids the "did I miss the signal?"
	# bug class entirely — no subscription bookkeeping.
	var g: Vector2 = GravityManager.gravity_direction
	_anti_gravity = -g.normalized()
	apply_central_force(_anti_gravity * buoyancy_strength)
	if DEBUG_OUTPUT:
		_debug_frame_count += 1
		if _debug_frame_count >= 30:
			_debug_frame_count = 0
			var body: Node = get_parent().get_node_or_null("AnimatableBody2D")
			var body_pos: Vector2 = body.global_position if body else Vector2.ZERO
			var joint: Node = get_parent().get_node_or_null("BalloonJoint")
			var joint_stiffness: float = joint.stiffness if joint else -1.0
			var joint_rest_length: float = joint.rest_length if joint else -1.0
			var joint_damping: float = joint.damping if joint else -1.0
			var length: float = (body_pos - global_position).length() if body else -1.0
			var spring_disp: float = length - joint_rest_length if joint and body else -1.0
			print("[Balloon] gravity=%s anti_gravity=%s buoyancy=%s pos=%s body_pos=%s offset=%s vel=%s | joint: stiffness=%s rest_len=%s damping=%s length=%s disp=%s" % [
				g, _anti_gravity, buoyancy_strength, global_position, body_pos,
				global_position - body_pos, linear_velocity,
				joint_stiffness, joint_rest_length, joint_damping, length, spring_disp,
			])