extends Node2D
##
## Scripted moving platform. Lerps between rail_start and rail_end at
## constant speed. On each ClockUI.countdown_zero signal, the motion
## direction reverses — the platform pretends to be driven by gravity:
## when gravity rotates 90° CW, the platform's fall direction reverses.
##
## At endpoints the platform clamps (no ping-pong) and waits for the
## next tick to reverse direction. Tune rail length + motion_speed per
## instance so the platform is in motion long enough to be a puzzle,
## not so long it never reaches an endpoint between ticks.
##
## Architecture: Node2D wrapper for editor ergonomics (drag handle +
## @export inspector on the wrapper); AnimatableBody2D as the kinematic
## collision carrier so the player rides via physics collision.
##

## Local-space start of the rail. The platform's position lerps
## between this and rail_end.
@export var rail_start: Vector2 = Vector2.ZERO

## Local-space end of the rail. Direction toward here is the initial
## "+" direction; on each tick this reverses.
@export var rail_end: Vector2 = Vector2(0, 96)

## Constant lerp speed in pixels per second.
@export var motion_speed: float = 60.0

## Initial t along the rail (0 = rail_start, 1 = rail_end). Clamped.
@export var starting_position: float = 0.0

@onready var _body: AnimatableBody2D = $AnimatableBody2D

# Normalized position along the rail (0..1). Direction is +1 toward
# rail_end, -1 toward rail_start. Reversed on each countdown_zero.
var _t: float = 0.0
var _direction: float = 1.0

func _ready() -> void:
	# Reset to starting position. Level reload (death flow) calls
	# _ready() on the new instance, so this also returns the platform
	# to its initial state on death.
	_t = clampf(starting_position, 0.0, 1.0)
	_update_position()
	# Connect to the clock. Each countdown_zero reverses direction --
	# the platform is "driven by gravity", so when gravity rotates 90°
	# the platform's fall direction reverses. Look up ClockUI by name
	# in the parent (sibling pattern, same as Player._ready()).
	var clock := get_parent().get_node_or_null("ClockUI")
	if clock and clock.has_signal("countdown_zero"):
		clock.countdown_zero.connect(_on_tick)

func _physics_process(delta: float) -> void:
	# Clamped lerp: at endpoints we sit still until the next tick
	# reverses our direction. No ping-pong at endpoints -- the tick
	# is the only mechanism for direction change.
	_t += _direction * (motion_speed / _get_rail_length()) * delta
	_t = clampf(_t, 0.0, 1.0)
	_update_position()

func _on_tick() -> void:
	_direction *= -1.0

func _update_position() -> void:
	_body.position = rail_start.lerp(rail_end, _t)

func _get_rail_length() -> float:
	# Avoid div-by-zero for zero-length rails (a level-design bug, but
	# defensive). distance_squared_to avoids the sqrt on the hot path;
	# sqrt once here is fine since we only call this per frame.
	var len_sq := rail_start.distance_squared_to(rail_end)
	return sqrt(len_sq) if len_sq > 0.0 else 1.0