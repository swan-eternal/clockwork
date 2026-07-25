@tool
extends Node2D
##
## "Fake" / non-physics moving platform. Slides along a rail at
## CONSTANT speed (no force integration), gated by the level's
## rotation state — runs in parallel with platform.gd but doesn't
## use physics. Designed for Clockwork's rotating-level puzzle
## logic: the platform moves when the rail is "with gravity"
## (vertical in world frame), stays put when horizontal, and
## reverses direction every 180° of level rotation (2 quarter-
## rotations).
##
## Behavior summary, with level_rot measured from game start:
##   - Vertical axis:    moves Q0 (0-90°),    stat Q1, moves Q2 (180-270°), stat Q3
##   - Horizontal axis:  stat Q0,             moves Q1,  stat Q2,          moves Q3
##   - Direction sign:   +1 for level_rot_mod in [0, 180), -1 for [180, 360)
##                      (alternates every 180° of level rotation = "two rotations")
##
## Both axes have player collision (RigidBody2D kinematic under
## the wrapper). The wrapper has all the @exports so designers
## can tune the platform from the inspector with live visual
## updates, mirroring the pattern from platform.gd after the
## setter bug-fix at commit 3709b4a.
##

# --- Designer config ----------------------------------------------------

# Motion axis in LOCAL frame. "Vertical" rail moves when the level
# is roughly upright (rail vertical in world frame, gravity has a
# component along the rail). "Horizontal" rail does the opposite —
# moves when the level has rotated ~90° (rail vertical in world).
@export_enum("Vertical", "Horizontal") var axis: String = "Vertical":
	set(value):
		axis = value
		_recompute_rail()
		queue_redraw()

# Length of the rail (in local px). Rail is centered at the
# wrapper's placed position when both rail_start and rail_end
# are Vector2.ZERO (the default).
@export var rail_length: float = 200.0:
	set(value):
		rail_length = value
		_recompute_rail()
		queue_redraw()

# Constant platform speed along the rail, in pixels per second.
# The platform moves at this rate during "moving" quadrants, and
# is frozen during "stationary" quadrants.
@export var speed: float = 80.0:
	set(value):
		speed = value
		queue_redraw()

# Starting position along the rail. 0.0 = at rail_start, 1.0 = at
# rail_end. Default 0.5 = rail's center (aligned with wrapper).
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.5:
	set(value):
		starting_position = value
		_t = value
		if _rigid_body:
			_rigid_body.position = lerp(_effective_rail_start, _effective_rail_end, _t)
		queue_redraw()

# Collision shape + visual size. Default (64, 16) = long flat platform.
@export var platform_size: Vector2 = Vector2(64, 16):
	set(value):
		platform_size = value
		_apply_platform_size()
		queue_redraw()

# Rail endpoints in LOCAL frame. Leave BOTH at Vector2.ZERO to
# auto-compute from axis + rail_length. Set BOTH manually for
# non-axis-aligned rails.
@export var rail_start: Vector2 = Vector2.ZERO:
	set(value):
		rail_start = value
		_recompute_rail()
		queue_redraw()

@export var rail_end: Vector2 = Vector2.ZERO:
	set(value):
		rail_end = value
		_recompute_rail()
		queue_redraw()

# --- Internal state -----------------------------------------------------

# Position along the rail (0..1). Incremented/decremented at
# constant speed during moving quadrants; frozen during stationary.
var _t: float = 0.5

# Direction sign along the rail: +1 or -1, flipped every 180° of
# level rotation per the cycle above.
var _direction_sign: float = 1.0

# Effective rail endpoints used at runtime + in the editor preview.
# Derived from @export rail_start/rail_end + axis + rail_length.
# Private so the setter chain on auto-compute doesn't cascade.
var _effective_rail_start: Vector2 = Vector2.ZERO
var _effective_rail_end: Vector2 = Vector2.ZERO

# Unit vector along the rail (local frame). Computed once per
# recompute. (Not currently used at runtime — the rail endpoints
# do all the work via lerp — but kept for symmetry with platform.gd
# and possible future debug visualizations.)
var _rail_direction: Vector2 = Vector2.DOWN

@onready var _rigid_body: RigidBody2D = $RigidBody2D
@onready var _collision_shape: CollisionShape2D = $RigidBody2D/CollisionShape2D
@onready var _platform_visual: Polygon2D = $RigidBody2D/PlatformVisual


func _ready() -> void:
	# Configure the RigidBody2D child as a kinematic body: ignores
	# gravity/physics, but pushes other bodies (the player) correctly.
	_rigid_body.freeze = true
	_rigid_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	_recompute_rail()
	_apply_platform_size()


# Recompute the effective rail endpoints + direction from the current
# @export values, and snap the platform to starting_position. Called
# from _ready (initial setup) and from any setter that affects the rail.
func _recompute_rail() -> void:
	if rail_start == Vector2.ZERO and rail_end == Vector2.ZERO:
		if axis == "Vertical":
			_effective_rail_start = Vector2(0, -rail_length * 0.5)
			_effective_rail_end = Vector2(0, rail_length * 0.5)
		else:
			_effective_rail_start = Vector2(-rail_length * 0.5, 0)
			_effective_rail_end = Vector2(rail_length * 0.5, 0)
	else:
		_effective_rail_start = rail_start
		_effective_rail_end = rail_end
	_rail_direction = (_effective_rail_end - _effective_rail_start).normalized()

	_t = starting_position
	if _rigid_body:
		_rigid_body.position = lerp(_effective_rail_start, _effective_rail_end, _t)


# Resize the collision shape + visual to match platform_size.
func _apply_platform_size() -> void:
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


# The fake/non-physics motion: read the level's current rotation,
# decide if this quadrant is "moving" or "stationary" for our axis,
# and update _t at constant speed during moving quarters only.
func _physics_process(delta: float) -> void:
	# Skip motion in the editor — get_parent() in the 2D editor
	# preview SubViewport is a SubViewport (no real Node2D ancestor),
	# and reading rotation_degrees there is fine, but we don't need
	# motion in editor anyway; the visual setup is enough.
	if Engine.is_editor_hint():
		return

	# Read the level's current rotation. Positive = counter-clockwise
	# in Godot's 2D convention (Y-down); sign doesn't matter for the
	# quadrant decision because we fposmod into [0, 360).
	var level_rot_mod: float = fposmod(get_parent().rotation_degrees, 360.0)
	var quadrant: int = int(level_rot_mod / 90.0) % 4

	# Decide whether this quadrant is "moving" for our axis:
	#   Vertical rail moves when the level is roughly upright
	#   (Q0 = 0-90° or Q2 = 180-270°).
	#   Horizontal rail moves when the level has rotated ~90°
	#   (Q1 or Q3).
	var is_moving: bool
	if axis == "Vertical":
		is_moving = (quadrant == 0 or quadrant == 2)
	else:
		is_moving = (quadrant == 1 or quadrant == 3)

	if not is_moving:
		return  # freeze at current position

	# Direction alternates every 180° of level rotation = 2 quarter-rotations.
	# rot_mod in [0, 180) -> +1, [180, 360) -> -1.
	_direction_sign = 1.0 if int(level_rot_mod / 180.0) % 2 == 0 else -1.0

	# Move at constant speed along the rail. speed is in px/s; rail_length
	# in px; so we divide by rail_length to convert to t-units/s.
	_t += _direction_sign * speed * delta / rail_length

	# Clamp at endpoints (no bounce — flip-back only happens once
	# the direction sign changes on the next 180° tick).
	_t = clamp(_t, 0.0, 1.0)

	# Apply rail offset to the RigidBody2D's local position. The
	# parent's rotation rotates this for free (SceneTree transform
	# hierarchy) — same trick as platform.gd.
	_rigid_body.position = lerp(_effective_rail_start, _effective_rail_end, _t)


# Editor-only: draw the rail line + endpoint markers on the WRAPPER.
# queue_redraw() (called from the @export setters) is what makes
# this update live on property changes.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_line(_effective_rail_start, _effective_rail_end, Color(0.5, 0.8, 0.5, 0.6), 2.0)
	draw_circle(_effective_rail_start, 4.0, Color(0.5, 0.8, 0.5, 0.8))
	draw_circle(_effective_rail_end, 4.0, Color(0.5, 0.8, 0.5, 0.8))
