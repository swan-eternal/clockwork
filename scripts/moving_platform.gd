@tool
extends RigidBody2D

# A platform that moves along a single-axis rail due to gravity/buoyancy.
# Children of RotatingLevelComponents — the rail rotates with the level.
#
# Place BalloonPlatform or WeightPlatform preset in a level scene. Configure
# rail_start, rail_end, starting_position, gravity, and buoyancy in the
# inspector.
#
# Motion is force-based:
#   - Weight platform: gravity pulls it toward rail_end (falls). Stops at rail_end.
#   - Balloon platform: buoyancy pushes it toward rail_end (rises). Stops at rail_end.
#   - Neither auto-reverses; no ping-pong.
#   - Player weight does NOT affect motion — the player can ride either direction.
#
# On level reset (scene reload), platforms return to starting_position.
#
# Note on rotated rails: when the level rotates 90°, the rail becomes horizontal
# in world frame, so gravity has no component along the rail — the platform
# stops moving until the next rotation. At 180° rotation the rail is inverted
# and motion reverses direction. This is emergent behavior from the physics.

## Platform type — documentation only; defaults are set per scene preset.
## "Balloon" rises due to buoyancy (against gravity).
## "Weight" falls due to gravity.
@export_enum("Balloon", "Weight") var platform_type: String = "Balloon"

## Start point of the rail in local coords (relative to RotatingLevelComponents).
@export var rail_start: Vector2 = Vector2(0, 100):
	set(value):
		rail_start = value
		if is_inside_tree():
			_update_position_from_starting()
			queue_redraw()

## End point of the rail in local coords.
@export var rail_end: Vector2 = Vector2(0, -100):
	set(value):
		rail_end = value
		if is_inside_tree():
			_update_position_from_starting()
			queue_redraw()

## Initial position along the rail (0 = rail_start, 1 = rail_end).
## The platform returns here on level reset. Designer can place it anywhere.
@export_range(0.0, 1.0, 0.01) var starting_position: float = 0.0:
	set(value):
		starting_position = value
		if is_inside_tree():
			_update_position_from_starting()
			queue_redraw()

## Gravity acceleration in pixels/sec² along the world-down axis.
@export_range(0.0, 5000.0, 10.0) var gravity: float = 980.0

## Buoyancy acceleration in pixels/sec² along the world-up axis.
## Only applies to Balloon platforms. Should exceed `gravity` for the
## balloon to actually rise.
@export_range(0.0, 5000.0, 10.0) var buoyancy: float = 1500.0

## Collision shape + visual size. (64, 16) = long flat platform.
@export var platform_size: Vector2 = Vector2(64, 16):
	set(value):
		platform_size = value
		if is_inside_tree():
			_update_collision()
			_update_visual()

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var platform_visual: Polygon2D = $PlatformVisual

# Internal state — parameter along the rail (0 = rail_start, 1 = rail_end).
var _t: float = 0.0
# Velocity along the rail in parameter-space (1/s).
var _velocity: float = 0.0


func _ready() -> void:
	# freeze = true + FREEZE_MODE_STATIC makes this RigidBody2D act like a kinematic
	# platform — it doesn't respond to gravity/physics forces, but the script's
	# position assignment each frame still pushes the player correctly. Unlike
	# AnimatableBody2D + sync_to_physics, this also makes the body inherit parent
	# rotation reliably (workaround for a Godot 4 quirk).
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	_update_collision()
	_update_visual()
	# Reset state on level load (also handles death-and-reset via scene reload).
	_t = starting_position
	_velocity = 0.0
	position = rail_start.lerp(rail_end, _t)


func _physics_process(delta: float) -> void:
	# Don't move in editor preview — only at runtime.
	if Engine.is_editor_hint():
		return
	# Rail direction in local frame (unit vector). Zero-length rail = no motion.
	var local_rail_direction: Vector2 = (rail_end - rail_start).normalized()
	if local_rail_direction.length_squared() <= 0.0:
		return

	# Transform to world frame by rotating by the node's global rotation.
	# The dot product with world-frame forces (gravity, buoyancy) needs the rail's
	# world-frame direction — otherwise after the level rotates, the projection
	# sign flips and the platform sticks at rail endpoints.
	var world_rail_direction: Vector2 = local_rail_direction.rotated(global_rotation)

	# Compute net world-frame acceleration along the rail.
	# World-down is (0, +1) in Godot 2D; gravity points that way.
	var net_world_accel: float = Vector2(0, gravity).dot(world_rail_direction)
	# Buoyancy adds an opposing force for balloon platforms.
	if platform_type == "Balloon":
		net_world_accel += Vector2(0, -buoyancy).dot(world_rail_direction)

	# Convert from pixels/sec² (world space) to parameter-space (1/sec²).
	# Rail length is world units per parameter unit (t goes 0..1 along the rail).
	var rail_length: float = rail_start.distance_to(rail_end)
	if rail_length <= 0.0:
		return
	var net_param_accel: float = net_world_accel / rail_length

	# Integrate: velocity → position.
	_velocity += net_param_accel * delta
	_t += _velocity * delta

	# Stop at endpoints (no bounce, no reverse).
	if _t <= 0.0:
		_t = 0.0
		_velocity = 0.0
	elif _t >= 1.0:
		_t = 1.0
		_velocity = 0.0

	# Apply position in local coords.
	position = rail_start.lerp(rail_end, _t)


# Snap the platform's position to lerp(rail_start, rail_end, starting_position).
# Called from setters so the editor preview reflects the @export value.
func _update_position_from_starting() -> void:
	position = rail_start.lerp(rail_end, starting_position)


# Resize the CollisionShape2D to match platform_size.
func _update_collision() -> void:
	if collision_shape == null:
		return
	var shape: Shape2D = collision_shape.shape
	if shape is RectangleShape2D:
		(shape as RectangleShape2D).size = platform_size


# Rebuild the Polygon2D placeholder rectangle to match platform_size.
# Replaced by art (LibreSprite) when Jason drops in a sprite.
func _update_visual() -> void:
	if platform_visual == null:
		return
	var half: Vector2 = platform_size * 0.5
	platform_visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


# Editor gizmo — draws the rail as a line with endpoint dots, plus a smaller
# marker at starting_position so the level designer can see where the platform
# begins and which direction it will travel.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rail_color: Color = Color(0.4, 0.7, 1.0, 0.9)
	var endpoint_color: Color = Color(1.0, 0.6, 0.3, 0.9)
	var start_marker_color: Color = Color(0.3, 1.0, 0.3, 0.9)
	draw_line(rail_start, rail_end, rail_color, 2.0)
	draw_circle(rail_start, 5.0, endpoint_color)
	draw_circle(rail_end, 5.0, endpoint_color)
	# Marker for starting_position along the rail.
	var start_pos: Vector2 = rail_start.lerp(rail_end, starting_position)
	draw_circle(start_pos, 3.0, start_marker_color)