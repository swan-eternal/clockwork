extends RigidBody2D

# Decorative balloon attached to a buoyant platform in Clockwork.
#
# Listens to the Player's gravity_changed signal and applies an
# anti-gravity buoyancy force each physics tick, making the balloon
# float "up" (against the current gravity direction). A DampedSpring
# Joint2D in the parent platform keeps the balloon tethered to the
# platform's center.
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

# Cached anti-gravity direction. Updated by _on_gravity_changed when
# the Player emits gravity_changed. Defaults to Vector2.UP as a safe
# starting state before the Player is found in the tree.
var _anti_gravity: Vector2 = Vector2.UP


func _ready() -> void:
	# Defensive: explicitly unfreeze in case platform.gd's setter chain
	# hasn't run yet (Godot property-setting order isn't strictly
	# guaranteed — child's properties may be set before the parent's
	# setters that override them). platform.gd's motion_type setter
	# re-applies the correct freeze state, so this is a one-shot fix
	# that gets overwritten if motion_type=WEIGHT.
	freeze = false
	# Best-effort: try to connect at _ready, but if the Player isn't
	# in the tree yet (sibling-order issue at scene load), _physics_process
	# will retry each tick. Same lazy-init pattern as platform.gd.
	_try_connect_to_player()


func _physics_process(_delta: float) -> void:
	# `freeze` is set externally by platform.gd (gated on motion_type
	# and balloon_enabled). When frozen, no physics sim and no force
	# application — the balloon sits anchored at its initial position.
	if freeze:
		return
	_try_connect_to_player()
	apply_central_force(_anti_gravity * buoyancy_strength)


# Find the Player in the parent scene and subscribe to its
# gravity_changed signal. No-op if already connected or the Player
# isn't in the tree yet (caller retries next physics tick).
#
# Two-level parent walk: balloon.gd is a child of the platform
# wrapper (Node2D), and the Player is a sibling of the platform in
# the level scene — so the Player lives at the wrapper's grandparent.
func _try_connect_to_player() -> void:
	var player := get_parent().get_parent().get_node_or_null("Player")
	if not player:
		return
	if not player.has_signal("gravity_changed"):
		return
	if player.gravity_changed.is_connected(_on_gravity_changed):
		return
	player.gravity_changed.connect(_on_gravity_changed)
	# Initial sync — set _anti_gravity from current Player state so we
	# don't have to wait for the next gravity_changed emission.
	if "gravity_direction" in player:
		_on_gravity_changed(player.gravity_direction)


# Callback for the Player's gravity_changed signal. Caches the
# anti-gravity direction (negated + normalized) so _physics_process
# can apply buoyancy without re-deriving it each tick.
func _on_gravity_changed(new_gravity: Vector2) -> void:
	_anti_gravity = -new_gravity.normalized()