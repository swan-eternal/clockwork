@tool
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
## for editor-visible rail extent.
##
## Editor reactivity: setters look up the AnimatableBody2D and Line2D
## via get_node_or_null() rather than @onready references, so they work
## in the editor (where _ready() doesn't run) as well as at runtime.
## @onready vars are null in the editor and would silently no-op the
## updates; get_node_or_null returns the nodes whenever they're in
## the tree (editor or runtime).
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
## platforms are vertical). Setter updates the rail preview and the
## platform body's position so inspector changes show up live.
@export var axis: Axis = Axis.Y:
	set(value):
		axis = value
		_rail_direction = Vector2.RIGHT if axis == Axis.X else Vector2.DOWN
		_update_rail_preview()
		_update_platform_size()
		_update_position()

## Rail length in units of 32 pixels (matching the default tile size).
## rail_length_units=2 -> 64px, =3 -> 96px, etc. Snaps to grid by design.
## Setter updates the rail preview and platform position.
@export_range(1, 16, 1) var rail_length_units: int = 3:
	set(value):
		rail_length_units = value
		_rail_length = float(value) * TILE_SIZE
		_update_rail_preview()
		_update_position()

## Initial t along the rail. 0 = at wrapper origin, 1 = at rail_length
## away along the axis. Slider range 0..1. Setter moves the platform
## body so the starting position is visible in the editor (and re-applied
## at runtime if changed).
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.0:
	set(value):
		starting_position = value
		_t = clampf(value, 0.0, 1.0)
		_update_position()

## Constant lerp speed in pixels per second.
@export var motion_speed: float = 60.0

# AnimatableBody2D and Line2D are looked up via get_node_or_null() in
# _update_position() / _update_rail_preview() rather than cached as
# @onready vars. This is so the setters work in the editor (where
# _ready() doesn't run and @onready vars are null).

const TILE_SIZE := 32.0

# Computed rail geometry (cached on _ready and on axis/length setters).
var _rail_direction: Vector2 = Vector2.DOWN  # Vector2.RIGHT or Vector2.DOWN
var _rail_length: float = TILE_SIZE * 3.0

# Normalized position along the rail (0..1). Set by starting_position
# setter and by _on_gravity_changed at runtime.
var _t: float = 0.0
# +1 toward rail_end, -1 toward rail_start. Set by _on_gravity_changed.
var _direction: float = 1.0
# False when gravity is perpendicular to rail -- platform stays still.
var _active: bool = false
# True for 30x60 (2-tile-wide) platforms, false for 30x30. Auto-detected
# by _update_platform_size() from the CollisionShape2D's bounding box
# (width != height), so the same script works for both platform.tscn
# and platform_2x1.tscn without an explicit @export flag.
var _is_wide_platform: bool = false

func _ready() -> void:
	# _t was already set by the starting_position setter. Re-apply in
	# case the setter didn't run (e.g., if the node was instantiated
	# without going through the script's setter chain -- e.g., loading
	# a scene where some children aren't yet in the tree).
	_t = clampf(starting_position, 0.0, 1.0)
	_update_position()
	_update_rail_preview()
	# Runtime-only: signal connection + initial gravity sync. Gate
	# with is_editor_hint so @tool doesn't connect signals in the
	# editor (they don't fire there anyway, but connecting is wasted
	# work and the initial sync would mark the platform active based
	# on the editor's view of gravity).
	if Engine.is_editor_hint():
		return
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
	# Skip motion in the editor -- @tool runs _physics_process, but
	# we only want motion at runtime.
	if Engine.is_editor_hint():
		return
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

# Update the platform's collision shape and polygon visual based on the
# current axis. For 30x30 platforms, no change. For 30x60 (wide) platforms,
# the long side is always perpendicular to the rail: Y axis -> long side
# horizontal (60 wide x 30 tall, polygon (-30,-15) to (30,15)); X axis ->
# long side vertical (30 wide x 60 tall, polygon (-15,-30) to (15,30)).
# The wrapper node is at (0,0) so the rail line (line points [0,0] to
# [rail_direction * rail_length]) always passes through the platform's
# center, satisfying the "rail through the middle" requirement.
# Auto-detects wide from the initial shape (width != height), so this
# works for both platform.tscn (30x30) and platform_2x1.tscn (30x60)
# without per-scene configuration.
func _update_platform_size() -> void:
	var body := get_node_or_null("AnimatableBody2D")
	if not body:
		return
	var collision_shape_node := body.get_node_or_null("CollisionShape2D")
	if not collision_shape_node or not collision_shape_node.shape is RectangleShape2D:
		return
	var shape := collision_shape_node.shape as RectangleShape2D
	_is_wide_platform = shape.size.x != shape.size.y
	if not _is_wide_platform:
		return
	var polygon := body.get_node_or_null("Polygon2D") as Polygon2D
	if axis == Axis.Y:
		# Vertical rail: long side horizontal.
		shape.size = Vector2(60, 30)
		if polygon:
			polygon.polygon = PackedVector2Array([Vector2(-30, -15), Vector2(30, -15), Vector2(30, 15), Vector2(-30, 15)])
	else:
		# Horizontal rail: long side vertical.
		shape.size = Vector2(30, 60)
		if polygon:
			polygon.polygon = PackedVector2Array([Vector2(-15, -30), Vector2(15, -30), Vector2(15, 30), Vector2(-15, 30)])

# Updates the platform body's local position along the rail. Looks up
# the body via get_node_or_null() (not @onready) so this works in the
# editor as well as at runtime -- @onready vars are null in the editor
# since _ready() doesn't run without @tool.
func _update_position() -> void:
	var body := get_node_or_null("AnimatableBody2D") as AnimatableBody2D
	if body:
		body.position = _rail_direction * (_rail_length * _t)

# Updates the editor-visible Line2D rail preview. Looks up the Line2D
# via get_node_or_null() (not @onready) so this works in the editor.
func _update_rail_preview() -> void:
	var preview := get_node_or_null("RailPreview") as Line2D
	if preview:
		preview.points = [Vector2.ZERO, _rail_direction * _rail_length]
