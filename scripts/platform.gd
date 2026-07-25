@tool
extends Node2D
##
## Clockwork moving platform — "fake it" motion (V3).
##
## The platform moves at constant speed along a rail defined by
## `rail_direction` (set by the scene preset) and `rail_length` (in
## 32-pixel units, set in the inspector). The anchor is the wrapper's
## origin (0, 0); the rail end is `rail_direction * rail_length * 32`.
## The RigidBody2D child is a kinematic collision carrier so the
## player can ride it; the motion itself is fully scripted — no
## physics forces, no rotation-frame math.
##
## ON/OFF duty cycle: the platform toggles between ON (moving) and
## OFF (stationary) every `rotation_completed`. On the OFF → ON
## transition (every 2 rotations / 180°), the platform reverses
## direction. The platform also pauses during the rotation tween
## (regardless of ON/OFF state), so the player has time to get on
## or off.
##
## Editor preview: with `@tool`, the rail is drawn as a light-blue line
## in the 2D editor (from the anchor to the rail end). Only visible
## in the editor — not at runtime.
##

# Motion type. Set by the scene preset (internal, not shown in
# inspector — Weight and Buoyant have separate scenes).
enum MotionType { WEIGHT, BUOYANT }

# --- Internal state (set by scene presets, not shown in inspector) ---

## Motion type. Set by the scene preset.
@export_storage var motion: MotionType = MotionType.WEIGHT

## Rail direction in the wrapper's local frame. Set by the scene preset:
## (0, 1) for Y-axis (down), (1, 0) for X-axis (right), etc.
@export_storage var rail_direction: Vector2 = Vector2(0, 1)

## Initial ON/OFF state. Set by the scene preset: true for Y platforms
## (start moving immediately), false for X platforms (start stationary,
## move after the first rotation).
@export_storage var start_active: bool = true

## Initial direction of motion. Set by the scene preset: +1 for Y
## platforms, -1 for X platforms (so that after the first OFF → ON
## flip, the platform moves toward the rail end).
@export_storage var initial_direction: float = 1.0

# --- Designer-tunable @exports (shown in inspector) ---

## Constant speed in pixels per second. Tune per-platform in the inspector.
@export var motion_speed: float = 60.0

## Rail length in 32-pixel units. 1 = 32px, 2 = 64px, 3 = 96px, etc.
## The rail end is `rail_direction * rail_length * 32` in the wrapper's
## local frame. Setter clamps to at least 1 and triggers a redraw so
## the editor preview line updates.
@export var rail_length: int = 3:
	set(value):
		rail_length = maxi(1, value)
		queue_redraw()

## Initial position along the rail at level start, 0..1 (clamped). 0 = the
## anchor (wrapper's origin); 1 = the rail end; 0.5 = mid-rail.
@export var starting_position: float = 0.0

# --- Runtime state ---

# The kinematic collision carrier. Configured in _ready() (freeze +
# KINEMATIC). Its local position is set every frame by the motion logic.
@onready var _rigid_body: RigidBody2D = $RigidBody2D

# Normalized position along the rail (0..1). Direction is given by
# `_direction` (+1 = toward rail_end; -1 = toward rail_start).
var _t: float = 0.0

# Direction of motion along the rail. +1 = toward rail_end (forward);
# -1 = toward rail_start (backward). Flipped on the OFF → ON transition.
var _direction: float = 1.0

# True between rotation_started and rotation_completed. While true,
# _physics_process early-returns so the platform doesn't move during
# the rotation tween.
var _is_rotating: bool = false

# ON/OFF state. ON = moving (motion logic runs); OFF = stationary
# (motion logic skipped). Toggled every rotation_completed.
var _is_active: bool = true

# --- Constants ---

# Tile size in pixels. The rail length is measured in units of this size.
const _GRID_SIZE: float = 32.0

# Editor rail preview color (light blue, semi-transparent).
const _RAIL_COLOR := Color(0.5, 0.7, 1.0, 0.8)


func _ready() -> void:
	# In editor, just ensure the rail preview is drawn and return.
	# Don't configure the RigidBody2D or wire up signals — the editor
	# doesn't need them, and accessing them in the editor can cause
	# SubViewport issues.
	if Engine.is_editor_hint():
		queue_redraw()
		return

	# Configure the RigidBody2D as a kinematic collision carrier. We
	# manually set its position every frame; the player rides it via
	# Godot's standard collision resolution.
	_rigid_body.freeze = true
	_rigid_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	# The platform is always being driven by the script (never settles
	# on its own), so it must never sleep. Setting this in the script
	# (not just the .tscn) overrides the default on instances created
	# before this property was added to the platform scene — without
	# it, an old instance carries can_sleep = true and the body
	# sleeps during the OFF half of the ON/OFF cycle, which culls the
	# parent Platform's _physics_process and strands the platform at
	# a wrong position. wake_up() handles the case where the body
	# was already sleeping when this scene loaded.
	_rigid_body.can_sleep = false
	_rigid_body.wake_up()
	# The platform is always being driven by the script (never settles
	# on its own), so it must never sleep. Setting this in the script
	# (not just in the .tscn) overrides the default on instances
	# created before this property was added to the platform scene —
	# without it, an old instance in a level carries can_sleep = true
	# and the body sleeps during the OFF rotation, which culls the
	# parent Platform's _physics_process and leaves the platform
	# stranded at a wrong position until the next rotation's wake.
	# wake_up() handles the case where the body was already sleeping
	# when this scene loaded.
	_rigid_body.can_sleep = false
	_rigid_body.wake_up()
	# The platform is always being driven by the script (never settles
	# on its own), so it must never sleep. Setting this here (not just
	# in the .tscn) overrides the default on instances created before
	# this property was set on the platform scene — without it, an
	# old instance in a level carries can_sleep = true and goes to
	# sleep during the OFF rotation, which culls the parent Platform's
	# _physics_process and leaves the platform stranded at a wrong
	# position. wake_up() handles the case where the body was already
	# sleeping when the scene loaded.
	_rigid_body.can_sleep = false
	_rigid_body.wake_up()

	# Initialize state. Reset on death (reload_current_scene) is automatic
	# — _ready() runs again and the platform returns to its starting
	# position and ON state.
	_t = clampf(starting_position, 0.0, 1.0)
	_direction = initial_direction
	_is_active = start_active
	var rail_end := _compute_rail_end()
	_rigid_body.position = rail_end * _t

	# Wire up to the parent's rotation signals. The platform must be
	# a child of RotatingLevelComponents (or any node that emits
	# rotation_started / rotation_completed) for this to work.
	var parent := get_parent()
	if parent:
		if parent.has_signal("rotation_started"):
			parent.rotation_started.connect(_on_rotation_started)
		if parent.has_signal("rotation_completed"):
			parent.rotation_completed.connect(_on_rotation_completed)


func _physics_process(delta: float) -> void:
	# Don't run in editor — the editor doesn't need the motion logic,
	# and running it can cause issues with the SubViewport.
	if Engine.is_editor_hint():
		return

	# DEBUG: per-frame collision tracking (remove after diagnosis).
	var _cs: CollisionShape2D = _rigid_body.get_node("CollisionShape2D")
	print("rb.pos=", _rigid_body.position, " rb.global=", _rigid_body.global_position,
		" cs.global=", _cs.global_position, " is_rotating=", _is_rotating)

	# Pause during the rotation tween.
	if _is_rotating:
		return

	# Stationary during OFF times. The platform toggles ON/OFF every
	# rotation, so it sits still for half the cycle (between direction
	# reversals).
	if not _is_active:
		return

	# Zero-length rail — nothing to do. Avoids division by zero.
	var rail_end := _compute_rail_end()
	var length := rail_end.length()
	if length <= 0.0:
		return

	# Advance t at constant speed in the current direction. The
	# direction is reversed on the OFF → ON transition (see below).
	_t += _direction * (motion_speed / length) * delta

	# Clamp at the endpoints. No bounce, no loop — the platform waits
	# at the rail end until the next rotation reverses its direction.
	_t = clampf(_t, 0.0, 1.0)

	# Apply the position to the kinematic body. The RigidBody2D's
	# position is in the wrapper's local frame, so when the parent
	# (RotatingLevelComponents) rotates, the platform's world
	# position rotates automatically via the SceneTree transform
	# hierarchy. The motion is in local frame.
	_rigid_body.position = rail_end * _t
	# Debug — remove after diagnosis
	var _collision_shape: CollisionShape2D = _rigid_body.get_node("CollisionShape2D")
	var _sprite: Sprite2D = _rigid_body.get_node("Sprite2D")
	print("--- platform debug ---")
	print("  rb.pos=", _rigid_body.position, " rb.global=", _rigid_body.global_position)
	print("  rb.freeze=", _rigid_body.freeze, " rb.freeze_mode=", _rigid_body.freeze_mode)
	print("  parent.rot=", get_parent().rotation)
	print("  cs.pos=", _collision_shape.position, " cs.global=", _collision_shape.global_position)
	print("  sp.pos=", _sprite.position, " sp.global=", _sprite.global_position)



# Called when the level rotation tween starts. Freezes the platform
# so it doesn't move during the rotation animation.
func _on_rotation_started() -> void:
	_is_rotating = true


# Called when the level rotation tween completes. Clears the freeze
# flag, toggles the ON/OFF state, and — on the OFF → ON transition —
# flips `_direction` (multiplies by -1) to reverse the direction of
# motion. The platform stays at its current position (it does NOT
# teleport) and resumes moving in the opposite direction every 2
# rotations (180°).
func _on_rotation_completed() -> void:
	_is_rotating = false
	_is_active = not _is_active
	if _is_active:
		_direction *= -1.0
		# Belt-and-suspenders against the OFF-state "stable body →
		# sleep → script culled" trap. can_sleep = false in _ready()
		# should prevent this in the normal case, but if the body
		# did manage to sleep during the OFF cycle, this wake-up
		# kick ensures the next ON frame's _physics_process isn't
		# culled.
		_rigid_body.wake_up()
		# The body may have gone to sleep during the OFF rotation
		# (edge cases / older instances). Wake it explicitly so the
		# script's _physics_process isn't culled on the first ON
		# frame. can_sleep = false in _ready() should prevent this
		# in the normal case, but the explicit wake is a belt-and-
		# suspenders guard against the OFF-state "stable body →
		# sleep → script culled" trap.
		_rigid_body.wake_up()
		# The body may have gone to sleep during the OFF rotation (even
		# with can_sleep = false, edge cases / older instances can still
		# sleep). Wake it explicitly so the script's _physics_process
		# isn't culled on the first ON frame.
		_rigid_body.wake_up()


# Computes the rail end position from `rail_direction` and `rail_length`.
# The anchor is always the wrapper's origin (0, 0).
func _compute_rail_end() -> Vector2:
	return rail_direction * float(rail_length) * _GRID_SIZE


# Draws the rail as a light-blue line in the editor. This is an editor
# preview only — it doesn't appear at runtime.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	var rail_end := _compute_rail_end()
	draw_line(Vector2.ZERO, rail_end, _RAIL_COLOR, 2.0)
	draw_circle(Vector2.ZERO, 4.0, _RAIL_COLOR)
	draw_circle(rail_end, 4.0, _RAIL_COLOR)
