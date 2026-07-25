@tool
extends RigidBody2D
##
## Clockwork moving platform. Slides along a rail in LOCAL frame under
## gravity (Weight) or against gravity (Balloon). The platform is a
## child of RotatingLevelComponents, so its local frame rotates with
## the level — the rail's world-frame direction follows the rotation
## automatically, with no joint, no sync_to_physics trick, no
## freeze-mode gymnastics.
##
## The four "types" are two @export enums in combination:
##   - axis:   "Vertical" (rail along local Y) or "Horizontal" (rail along local X)
##   - motion: "Weight" (falls with gravity) or "Balloon" (rises with buoyancy)
##
## The platform is a kinematic RigidBody2D (freeze = true,
## freeze_mode = FREEZE_MODE_KINEMATIC). When frozen, it doesn't
## respond to gravity or forces, but it can be moved by setting
## position, and it pushes other bodies (like the player) out of the way.
## The rotation is handled by the SceneTree transform hierarchy — the
## platform is a child of RotatingLevelComponents, so as the parent
## rotates, the platform's global_rotation follows.
##

# --- Designer config ----------------------------------------------------

# Motion axis in LOCAL frame. "Vertical" = rail along local Y (the
# platform slides up/down in its local frame). "Horizontal" = rail
# along local X (the platform slides left/right in its local frame).
# The parent rotation rotates the rail's world-frame direction with
# the level — no special handling needed in the script.
@export_enum("Vertical", "Horizontal") var axis: String = "Vertical"

# "Weight" = falls with gravity (force = Vector2.DOWN * gravity).
# "Balloon" = rises against gravity (force = Vector2.UP * buoyancy).
@export_enum("Weight", "Balloon") var motion: String = "Weight"

# Length of the rail (in local px). The rail is centered at the
# platform's placed position (the .tscn's `position` field).
@export var rail_length: float = 200.0

# Starting position along the rail. 0.0 = at rail_start, 1.0 = at
# rail_end. Resets on level reload (the script re-runs _ready).
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.0

# Force magnitudes (px/s²). Same units for Weight and Balloon — the
# difference is the direction (DOWN vs UP). Exported as separate
# values so the designer can tune fall vs rise feel independently.
@export var gravity: float = 980.0
@export var buoyancy: float = 1500.0

# Collision shape + visual size. Default (64, 16) = long flat platform.
@export var platform_size: Vector2 = Vector2(64, 16)

# Rail endpoints in LOCAL frame. Auto-computed from axis + rail_length
# at _ready() — leaving both at Vector2.ZERO triggers the auto-compute.
# Override for non-axis-aligned rails (e.g. a 45° diagonal).
@export var rail_start: Vector2 = Vector2.ZERO
@export var rail_end: Vector2 = Vector2.ZERO

# --- Internal state -----------------------------------------------------

# Per-frame state. _t is the position along the rail (0..1); _velocity
# is the rate of change in `_t` units per second.
var _t: float = 0.0
var _velocity: float = 0.0

# Unit vector along the rail (local frame). Computed once in _ready().
var _rail_direction: Vector2 = Vector2.DOWN

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _platform_visual: Polygon2D = $PlatformVisual


func _ready() -> void:
	# Kinematic body: ignore gravity/physics, but push other bodies correctly.
	# FREEZE_MODE_KINEMATIC treats the body as a kinematic actor — it can
	# be moved by setting position, and physics-aware bodies (like the
	# player's CharacterBody2D) interact with it as a moving platform.
	freeze = true
	freeze_mode = FREEZE_MODE_KINEMATIC

	# Auto-compute rail endpoints if not overridden. Rail is centered
	# at the platform's placed position (the .tscn's `position` field).
	if rail_start == Vector2.ZERO and rail_end == Vector2.ZERO:
		if axis == "Vertical":
			rail_start = Vector2(0, -rail_length * 0.5)
			rail_end = Vector2(0, rail_length * 0.5)
		else:
			rail_start = Vector2(-rail_length * 0.5, 0)
			rail_end = Vector2(rail_length * 0.5, 0)
	_rail_direction = (rail_end - rail_start).normalized()

	# Initial state — start at the configured starting_position on the
	# rail with zero velocity.
	_t = starting_position
	_velocity = 0.0
	position = lerp(rail_start, rail_end, _t)

	# Match the collision shape and visual to platform_size.
	if _collision_shape and _collision_shape.shape is RectangleShape2D:
		(_collision_shape.shape as RectangleShape2D).size = platform_size
	if _platform_visual:
		var half: Vector2 = platform_size * 0.5
		_platform_visual.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])


func _physics_process(delta: float) -> void:
	# World-frame force: gravity for Weight, opposite-of-gravity for Balloon.
	var world_force: Vector2
	if motion == "Weight":
		world_force = Vector2.DOWN * gravity
	else:
		world_force = Vector2.UP * buoyancy

	# Transform world force into OUR local frame. The parent's rotation
	# rotates the result with the level — that's how the rail's
	# world-frame direction ends up following the rotation.
	#
	# Affine_inverse() includes the parent's rotation; basis_xform()
	# applies just the rotation part to the vector (no translation).
	var local_force: Vector2 = get_parent().global_transform.affine_inverse().basis_xform(world_force)

	# Project onto the rail direction (also in local frame).
	# Result: how much of the force acts along the rail this frame.
	var force_along_rail: float = local_force.dot(_rail_direction)

	# Integrate. Force is acceleration (mass = 1).
	_velocity += force_along_rail * delta
	_t += _velocity * delta

	# Clamp at endpoints. Stop at the boundary (no bounce, no reverse).
	if _t < 0.0:
		_t = 0.0
		_velocity = 0.0
	elif _t > 1.0:
		_t = 1.0
		_velocity = 0.0

	# Apply rail offset to local position. The parent's rotation
	# rotates this for free (SceneTree transform hierarchy).
	position = lerp(rail_start, rail_end, _t)


# Editor-only: draw a rail line + endpoint markers so the level
# designer can see where the platform will travel. Drawn only in
# the editor (not at runtime).
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_line(rail_start, rail_end, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	draw_circle(rail_start, 4.0, Color(0.5, 0.8, 1.0, 0.8))
	draw_circle(rail_end, 4.0, Color(0.5, 0.8, 1.0, 0.8))
