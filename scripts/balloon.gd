extends RigidBody2D

# Decorative balloon attached to a buoyant platform in Clockwork.
#
# State-machine approach: each physics frame, lerps the balloon's
# position toward a target computed from the current gravity and the
# parent platform's @export'd balloon parameters. Replaces the
# previous spring-based approach, which had sleep-related issues that
# left the balloon stuck at non-cardinal directions (the body would
# go to sleep at non-equilibrium positions and the spring force
# could no longer pull it back to the cardinal equilibrium).
#
# Reads the rest_length and spring_stiffness from the parent
# platform's @export'd values. The parent platform's setter for
# balloon_buoyancy calls _update_balloon() which sets
# buoyancy_strength; the other two are read directly each frame
# (cheap Variant reads).

# Buoyancy force magnitude. Set by platform.gd's _update_balloon
# from the parent platform's balloon_buoyancy @export. Used to
# compute equilibrium displacement: displacement = buoyancy / stiffness.
var buoyancy_strength: float = 200.0

# Cached anti-gravity direction. Recomputed each physics frame from
# GravityManager.gravity_direction. Defaults to Vector2.UP as a safe
# starting state before the singleton is queried.
var _anti_gravity: Vector2 = Vector2.UP

# Lerp rate for the state-machine position update. Higher = faster
# convergence. With rate = 10, position reaches ~99% of target in
# ~0.5 sec — same visual feel as the previous spring-based approach.
const LERP_RATE: float = 10.0


func _ready() -> void:
	# Override the scene's initial `freeze = true` — for the
	# state-machine to update the position, the body must be
	# un-frozen. The motion_type setter re-applies the correct
	# freeze state later (false for BUOYANT, true for WEIGHT).
	freeze = false


func _physics_process(delta: float) -> void:
	# `freeze` is set externally by platform.gd (gated on motion_type
	# and balloon_enabled). When frozen, the balloon sits anchored at
	# its initial position.
	if freeze:
		return
	var g: Vector2 = GravityManager.gravity_direction
	_anti_gravity = -g.normalized()
	# Compute the target position from the platform's @export'd
	# rest_length and stiffness. Cheap Variant reads.
	var platform: Node = get_parent()
	var rest_length: float = platform.balloon_rest_length
	var stiffness: float = platform.balloon_stiffness
	var body: Node = platform.get_node_or_null("AnimatableBody2D")
	if not body:
		return
	var displacement: float = buoyancy_strength / stiffness
	var target: Vector2 = body.global_position + _anti_gravity * (rest_length + displacement)
	# Lerp toward target. Use exp-based lerp for frame-rate
	# independence: t = 1 - exp(-rate * delta).
	var t: float = 1.0 - exp(-LERP_RATE * delta)
	global_position = global_position.lerp(target, t)
