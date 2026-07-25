extends Node2D
##
## Clockwork moving platform — "fake it" motion (V3).
##
## The platform moves at constant speed along a rail defined by
## `rail_start` (where t=0 sits, the editor anchor) and `rail_end`
## (where t=1 sits). The RigidBody2D child is a kinematic collision
## carrier so the player can ride it; the motion itself is fully
## scripted — no physics forces, no rotation-frame math.
##
## Direction reversal is triggered by the level rotation, not by the
## endpoints. On `rotation_completed` (signal from the parent
## RotatingLevelComponents), the script flips `_direction` (multiplies
## by -1), which reverses the direction of motion. The platform stays
## at its current position (it does NOT teleport) and resumes moving
## in the opposite direction. The platform also pauses during the
## rotation tween so the player can get on or off.
##

# Motion type. Set by the scene preset (WEIGHT falls from the anchor
# toward rail_end; BUOYANT rises from rail_end toward the anchor).
enum MotionType { WEIGHT, BUOYANT }

## Motion type: WEIGHT (falls) or BUOYANT (rises). Set per-scene.
@export var motion: MotionType = MotionType.WEIGHT

## Constant speed in pixels per second. Tune per-platform in the inspector.
@export var motion_speed: float = 60.0

## Local-frame position where t=0 sits. Defaults to (0, 0) — the wrapper's
## origin (the editor drag target). Override for non-axis-aligned rails.
@export var rail_start: Vector2 = Vector2(0, 0)

## Local-frame position where t=1 sits. The default depends on the scene
## preset (see the README's Scene Presets table). Override in the inspector
## to adjust the rail length or change the rail direction.
@export var rail_end: Vector2 = Vector2(0, 96)

## Initial position along the rail at level start, 0..1 (clamped). 0 = rail_start
## (the anchor); 1 = rail_end; 0.5 = mid-rail. Defaults to 0.
@export var starting_position: float = 0.0

# The kinematic collision carrier. Configured in _ready() (freeze +
# KINEMATIC). Its local position is set every frame by the motion logic.
@onready var _rigid_body: RigidBody2D = $RigidBody2D

# Normalized position along the rail (0..1). Direction is given by
# `_direction` (+1 = toward rail_end; -1 = toward rail_start).
var _t: float = 0.0

# Direction of motion along the rail. +1 = toward rail_end (forward);
# -1 = toward rail_start (backward). Flipped on rotation_completed.
var _direction: float = 1.0

# True between rotation_started and rotation_completed. While true,
# _physics_process early-returns so the platform doesn't move during
# the rotation tween.
var _is_rotating: bool = false


func _ready() -> void:
	# Configure the RigidBody2D as a kinematic collision carrier. We
	# manually set its position every frame; the player rides it via
	# Godot's standard collision resolution.
	_rigid_body.freeze = true
	_rigid_body.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC

	# Initialize t clamped to [0, 1] and direction forward. Set the
	# RigidBody2D's position immediately so the platform doesn't
	# visibly snap from origin to its actual start in the first frame.
	_t = clamp(starting_position, 0.0, 1.0)
	_direction = 1.0
	_rigid_body.position = rail_start.lerp(rail_end, _t)

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
	# Pause during the rotation tween.
	if _is_rotating:
		return

	# Zero-length rail — nothing to do. Avoids division by zero.
	var length := rail_start.distance_to(rail_end)
	if length <= 0.0:
		return

	# Advance t at constant speed in the current direction. The
	# direction is reversed on rotation_completed (see below).
	_t += _direction * (motion_speed / length) * delta

	# Clamp at the endpoints. No bounce, no loop — the platform waits
	# at the rail end until the next rotation reverses its direction.
	_t = clamp(_t, 0.0, 1.0)

	# Apply the position to the kinematic body. The RigidBody2D's
	# position is in the wrapper's local frame, so when the parent
	# (RotatingLevelComponents) rotates, the platform's world
	# position rotates automatically via the SceneTree transform
	# hierarchy. The motion is in local frame.
	_rigid_body.position = rail_start.lerp(rail_end, _t)


# Called when the level rotation tween starts. Freezes the platform
# so it doesn't move during the rotation animation.
func _on_rotation_started() -> void:
	_is_rotating = true


# Called when the level rotation tween completes. Clears the freeze
# flag and flips `_direction` (multiplies by -1), which reverses the
# direction of motion. The platform stays at its current position
# (it does NOT teleport) and resumes moving in the opposite direction.
func _on_rotation_completed() -> void:
	_is_rotating = false
	_direction *= -1.0
