extends Node2D
##
## Scripted moving platform. Pretends to be driven by gravity: when
## gravity rotates 90° CW per tick, the platform's motion direction is
## determined by how gravity projects onto its rail axis. When gravity
## is parallel to the rail, the platform moves in the gravity direction
## (WEIGHT) or opposite (BUOYANT). When gravity is perpendicular to the
## rail, the platform doesn't move.
##
## This naturally gives "every two ticks" motion: gravity rotates 90°
## per tick and alternates between parallel and perpendicular to a
## given rail axis, so motion is active on every other tick. Direction
## reverses when gravity rotates 180° (every 2 active ticks).
##
## Architecture: Node2D wrapper for editor ergonomics (drag handle +
## @export inspector on the wrapper); AnimatableBody2D as the kinematic
## collision carrier (player rides via collision); Line2D as a sibling
## for editor-visible rail extent, updated by setters so inspector
## changes show up live.
##

## WEIGHT: falls with gravity. BUOYANT: rises against gravity.
## Implemented as a sign flip on the motion direction relative to
## gravity's projection on the rail -- effectively "reverses start
## direction" relative to WEIGHT for the same gravity state.
enum MotionType { WEIGHT, BUOYANT }

## X = horizontal rail (along world +x). Y = vertical rail (along
## world +y, i.e., downward in Godot's screen coords).
enum Axis { X, Y }

## Motion type. WEIGHT falls in the direction of gravity; BUOYANT
## rises against gravity.
@export var motion_type: MotionType = MotionType.WEIGHT

## Rail axis. X = horizontal. Y = vertical (default -- most platformer
## platforms are vertical).
@export var axis: Axis = Axis.Y:
	set(value):
		axis = value
		_rail_direction = Vector2.RIGHT if axis == Axis.X else Vector2.DOWN
		if is_inside_tree():
			_update_rail_preview()
			_update_position()

## Rail length in units of 32 pixels (matching the default tile size).
## rail_length_units=2 -> 64px, =3 -> 96px, etc. Snaps to grid by design.
@export_range(1, 16, 1) var rail_length_units: int = 3:
	set(value):
		rail_length_units = value
		_rail_length = float(value) * TILE_SIZE
		if is_inside_tree():
			_update_rail_preview()
			_update_position()

## Initial t along the rail. 0 = at wrapper origin, 1 = at rail_length
## away along the axis. Slider range 0..1.
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.0

## Constant lerp speed in pixels per second.
@export var motion_speed: float = 60.0

@onready var _body: AnimatableBody2D = $AnimatableBody2D
@onready var _rail_preview: Line2D = $RailPreview

const TILE_SIZE := 32.0

# Computed rail geometry (cached on _ready and on axis/length setters).
var _rail_direction: Vector2 = Vector2.DOWN  # Vector2.RIGHT or Vector2.DOWN
var _rail_length: float = TILE_SIZE * 3.0

# Normalized position along the rail (0..1). Set by gravity_changed signal.
var _t: float = 0.0
# +1 toward rail_end, -1 toward rail_start. Set by _on_gravity_changed.
var _direction: float = 1.0
# False when gravity is perpendicular to rail -- platform stays still.
var _active: bool = false

func _ready() -> void:
	_t = clampf(starting_position, 0.0, 1.0)
	_update_position()
	_update_rail_preview()
	# Listen to gravity changes from the Player. The Player is the
	# source of truth for gravity_direction; initial sync applies the
	# current gravity so the platform is moving immediately at scene
	# load if gravity happens to be aligned with the rail.
	var player := get_parent().get_node_or_null("Player")
	if player:
		if "gravity_direction" in player:
			_on_gravity_changed(player.gravity_direction)
		if player.has_signal("gravity_changed"):
			player.gravity_changed.connect(_on_gravity_changed)

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_t += _direction * (motion_speed / _rail_length) * delta
	_t = clampf(_t, 0.0, 1.0)
	_update_position()

func _on_gravity_changed(new_gravity: Vector2) -> void:
	# Project gravity onto rail axis. |dot| near 1 = parallel; near 0
	# = perpendicular. In our game, gravity is always one of the
	# cardinal directions, so the dot is exactly +/-1 or 0; we use 0.5
	# as a defensive threshold against floating-point drift.
	var dot := new_gravity.dot(_rail_direction)
	if absf(dot) < 0.5:
		# Gravity is perpendicular to rail -- the platform stays still
		# (gravity has no component along the rail axis).
		_active = false
		return
	# Gravity has a meaningful component along the rail. WEIGHT moves
	# in gravity's direction; BUOYANT moves opposite. Sign of dot
	# tells us which way along the rail.
	var gravity_sign := 1.0 if dot > 0.0 else -1.0
	var motion_sign := gravity_sign if motion_type == MotionType.WEIGHT else -gravity_sign
	_direction = motion_sign
	_active = true

func _update_position() -> void:
	_body.position = _rail_direction * (_rail_length * _t)

func _update_rail_preview() -> void:
	if _rail_preview:
		_rail_preview.points = [Vector2.ZERO, _rail_direction * _rail_length]