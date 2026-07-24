@tool
extends RigidBody2D
##
## Moving platform for Clockwork — slides back and forth along a
## rail between two endpoints. Two variants:
##   - "Balloon" — buoyancy > gravity, rises from rail_start to rail_end
##   - "Weight" — falls under gravity, drops from rail_start to rail_end
##
## Rail endpoints can be set two ways:
##   1. The @export rail_start / rail_end properties (Inspector panel)
##   2. RailStart / RailEnd child marker nodes (draggable in the
##      2D viewport — preferred for level design)
## If marker nodes exist in the scene, their positions override the
## @export values at _ready(). This lets the level designer drag the
## endpoints visually in the editor instead of typing numbers.
##

# Variant label. Drives the gravity/buoyancy direction in _ready().
# "Balloon" rises (buoyancy > gravity); "Weight" falls (gravity).
@export var platform_type: String = "Balloon"

# Direction lock between the two rail markers (RailStart / RailEnd).
# When the designer drags one marker, the other is snapped so the
# rail direction stays at this axis. "free" = no constraint.
# "vertical" = same X (RailEnd.x locked to RailStart.x). "horizontal"
# = same Y. "diagonal" = 45° (RailEnd - RailStart = (d, d), preserves
# the original X-distance d). Applies only in the editor via the
# marker nodes' position_manually_set signal.
@export_enum("free", "vertical", "horizontal", "diagonal") var rail_constraint: String = "free"

# Rail endpoints in platform-local coordinates. The platform moves
# back and forth between these along the line connecting them.
# @export so a level designer can set them via the Inspector.
# Preferred for level design: instance RailStart / RailEnd child
# nodes and drag them in the 2D viewport — the script picks up the
# marker positions in _ready() and uses them over the @export values.
@export var rail_start: Vector2 = Vector2(0, 100)
@export var rail_end: Vector2 = Vector2(0, -100)

# Starting position on the rail. 0.0 = at rail_start; 1.0 = at
# rail_end. The platform resets to this on each level load.
# (Use the slider on the Inspector or set per-level via _ready.)
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.0

# Acceleration in pixels/sec² along world-down. Multiplied by gravity_scale
# (1.0 for Weight, -0.8 for Balloon → see _ready) to get the actual
# world-frame acceleration that the platform's physics body experiences.
@export_range(0.0, 5000.0, 10.0) var gravity: float = 980.0

# Buoyancy acceleration in pixels/sec² along world-up. Multiplied by
# gravity_scale (1.0 for Weight, 0 for Balloon → see _ready) to get
# the actual world-frame acceleration. For a Balloon, set this ABOVE
# `gravity` so buoyancy wins; for a Weight, it doesn't matter.
@export_range(0.0, 5000.0, 10.0) var buoyancy: float = 1500.0

# Collision shape + visual size. (64, 16) = long flat platform.
@export var platform_size: Vector2 = Vector2(64, 16):
	set(value):
		platform_size = value
		_update_collision()
		_update_visual()

# Marker nodes for the rail endpoints. If present in the scene, their
# positions override the @export rail_start/rail_end values at _ready()
# — letting the level designer drag the endpoints in the 2D editor
# instead of typing numbers in the Inspector. Add RailStart / RailEnd
# as Node2D children of the platform preset for this workflow.
@onready var _rail_start_marker: Node2D = get_node_or_null("RailStart")
@onready var _rail_end_marker: Node2D = get_node_or_null("RailEnd")

# Internal state — parameter along the rail (0 = at rail_start, 1 = at
# rail_end), plus per-tick velocity.
var _t: float = 0.0
var _velocity: float = 0.0

# True while the constraint handler is programmatically moving the
# other marker in response to one marker being moved. Prevents the
# marker A moves → marker B moves → marker A moves loop.
var _processing_marker_constraint: bool = false

# The CollisionShape2D and Polygon2D visual are children of the
# platform node, populated from the @tool-evaluated scene tree.
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _platform_visual: Polygon2D = $PlatformVisual


func _ready() -> void:
	# If marker nodes exist, use their positions. This lets the level
	# designer drag the endpoints in the 2D editor (RailStart / RailEnd
	# child nodes) instead of typing numbers in the Inspector. If no
	# markers are present, fall back to the @export values.
	if _rail_start_marker != null:
		rail_start = _rail_start_marker.position
	if _rail_end_marker != null:
		rail_end = _rail_end_marker.position

	# Connect to the markers' position_manually_set signal so the
	# constraint (rail_constraint) is enforced when the designer drags
	# them. Only meaningful in the editor — at runtime the markers
	# don't move, so no signal fires and the constraint is a no-op.
	if _rail_start_marker != null and _rail_start_marker.has_signal("position_manually_set"):
		_rail_start_marker.position_manually_set.connect(_on_start_marker_moved)
	if _rail_end_marker != null and _rail_end_marker.has_signal("position_manually_set"):
		_rail_end_marker.position_manually_set.connect(_on_end_marker_moved)

	# Apply the gravity_scale based on platform_type so the same @export
	# values for gravity/buoyancy give the right behavior in both
	# variants without the level designer having to set them.
	match platform_type:
		"Balloon":
			# Negative gravity_scale makes world-down gravity act as
			# buoyancy (the platform wants to rise). gravity_scale is
			# computed against the @export gravity (which is the
			# world-frame "down" magnitude).
			if gravity > 0.0:
				gravity_scale = -buoyancy / gravity
		"Weight":
			gravity_scale = 1.0

	# Initial state — start at the configured starting_position on the
	# rail with zero velocity.
	_t = starting_position
	_velocity = 0.0
	position = rail_start.lerp(rail_end, _t)


func _physics_process(delta: float) -> void:
	# Don't move in editor preview — only at runtime.
	if Engine.is_editor_hint():
		return

	# Rail length (and bail early if the rail has zero length so we
	# don't divide by zero).
	var rail_length := rail_start.distance_to(rail_end)
	if rail_length <= 0.0:
		return

	# World-frame acceleration along the rail, computed from gravity
	# (always world-down) and buoyancy (world-up, Balloon only).
	# Each gets projected onto the rail's world-frame direction.
	var rail_direction := (rail_end - rail_start).normalized()
	var net_world_accel := Vector2(0.0, gravity).dot(rail_direction)
	match platform_type:
		"Balloon":
			net_world_accel += Vector2(0.0, -buoyancy).dot(rail_direction)

	# Convert from pixels/sec² (world space) to parameter-space (1/sec²)
	# so we can integrate _t directly.
	var net_param_accel := net_world_accel / rail_length

	# Semi-implicit Euler: integrate velocity, then position.
	_velocity += net_param_accel * delta
	_t += _velocity * delta

	# Stop at endpoints. Don't bounce, don't reverse — just halt.
	if _t <= 0.0:
		_t = 0.0
		_velocity = 0.0
	elif _t >= 1.0:
		_t = 1.0
		_velocity = 0.0

	# Apply position in local coords.
	position = rail_start.lerp(rail_end, _t)


# Resize the CollisionShape2D RectangleShape2D to match platform_size.
func _update_collision() -> void:
	if _collision_shape == null:
		return
	var shape := _collision_shape.shape
	if shape is RectangleShape2D:
		(shape as RectangleShape2D).size = platform_size


# Rebuild the Polygon2D visual to match platform_size. A 4-vertex
# rectangle centered on the platform's local origin.
func _update_visual() -> void:
	if _platform_visual == null:
		return
	var half := platform_size * 0.5
	_platform_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


# Draw a line between the rail endpoints in the editor. Gives the
# level designer a visual reference for the rail's extent, even
# when the markers are at their default positions. Draws only in
# the editor (Engine.is_editor_hint() check) so it doesn't show
# at runtime.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_line(rail_start, rail_end, Color(0.5, 0.8, 1.0, 0.6), 2.0)
	draw_circle(rail_start, 4.0, Color(0.5, 0.8, 1.0, 0.8))
	draw_circle(rail_end, 4.0, Color(0.5, 0.8, 1.0, 0.8))


# Called when the designer drags RailStart in the editor. Snaps
# RailEnd to maintain the rail_constraint lock. Editor-only (the
# signal is fired in the marker's @tool _notification, which doesn't
# fire at runtime in a meaningful way). The _processing_marker_constraint
# flag prevents the loop where moving RailEnd programmatically would
# re-fire RailStart's signal and trigger another move.
func _on_start_marker_moved(new_pos: Vector2) -> void:
	if _processing_marker_constraint or not Engine.is_editor_hint():
		return
	if _rail_end_marker == null:
		return
	_processing_marker_constraint = true
	match rail_constraint:
		"vertical":
			# Same X — the rail is vertical. Keep RailEnd's X, take
			# RailStart's Y (snap RailEnd horizontally to match).
			_rail_end_marker.position = Vector2(_rail_end_marker.position.x, new_pos.y)
		"horizontal":
			# Same Y — rail is horizontal. Keep RailEnd's Y, take
			# RailStart's X.
			_rail_end_marker.position = Vector2(new_pos.x, _rail_end_marker.position.y)
		"diagonal":
			# 45° line. Preserve the original X-distance d between
			# the markers; set RailEnd to RailStart + (d, d).
			var dx: float = _rail_end_marker.position.x - _rail_start_marker.position.x
			_rail_end_marker.position = Vector2(new_pos.x + dx, new_pos.y + dx)
	_processing_marker_constraint = false


# Mirror of _on_start_marker_moved, but for RailEnd. Snaps
# RailStart to maintain the constraint when RailEnd moves.
func _on_end_marker_moved(new_pos: Vector2) -> void:
	if _processing_marker_constraint or not Engine.is_editor_hint():
		return
	if _rail_start_marker == null:
		return
	_processing_marker_constraint = true
	match rail_constraint:
		"vertical":
			_rail_start_marker.position = Vector2(new_pos.x, _rail_start_marker.position.y)
		"horizontal":
			_rail_start_marker.position = Vector2(new_pos.x, _rail_start_marker.position.y)
		"diagonal":
			var dx: float = _rail_end_marker.position.x - _rail_start_marker.position.x
			_rail_start_marker.position = Vector2(new_pos.x - dx, new_pos.y - dx)
	_processing_marker_constraint = false