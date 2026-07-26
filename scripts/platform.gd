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

## Which side of the platform the spikes are on. UP/DOWN are the
## short ends of the platform (perpendicular to the rail axis).
## LEFT/RIGHT are along the rail axis -- less common but allowed
## for symmetric cases.
##
## For the 30x60 wide variant, the side adapts to the platform's
## current orientation: spike_direction=UP means "top edge in the
## platform's local frame", which is the long side for axis=Y and
## the short side for axis=X. The polygon is recomputed when axis
## changes so the spike count and width track the side length.
enum SpikeDirection { UP, DOWN, LEFT, RIGHT }

## Motion type. WEIGHT falls in the direction of gravity; BUOYANT
## rises against gravity. Setter auto-toggles the balloon — BUOYANT
## shows it, WEIGHT hides it (balloon_enabled must also be true).
@export var motion_type: MotionType = MotionType.WEIGHT:
	set(value):
		motion_type = value
		_update_balloon_visibility()

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
		_update_spikes()

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

## If true, the platform has kill-spikes on the chosen side. Spikes
## are a separate Area2D child (SpikesArea, collision_layer = 2 to
## match the player's DeathDetector mask) so the regular platform
## collision (AnimatableBody2D) is unaffected -- the player can still
## stand on the platform body, but walking into the spikes triggers
## death. Setter toggles the Area2D's monitoring and updates the
## spike polygon.
@export var has_spikes: bool = false:
	set(value):
		has_spikes = value
		_update_spikes()

## Which side of the platform the spikes are on. See SpikeDirection
## enum for the orientation semantics. Setter recomputes the spike
## polygon (the side length depends on the platform's current shape
## size, which changes with axis for the wide variant).
@export var spike_direction: SpikeDirection = SpikeDirection.UP:
	set(value):
		spike_direction = value
		_update_spikes()

## Per-instance kill switch for the balloon. The motion_type setter
## auto-toggles visibility (BUOYANT shows, WEIGHT hides) — set this
## to false on a specific buoyant platform to permanently hide the
## balloon (e.g., for design reasons or to save physics cost).
@export var balloon_enabled: bool = true:
	set(value):
		balloon_enabled = value
		_update_balloon_visibility()

## Buoyancy force magnitude. The force pulls the balloon against the
## current gravity each physics tick; the spring joint counters it so
## the balloon settles near rest_length offset from the platform center.
@export_range(0.0, 1000.0, 10.0) var balloon_buoyancy: float = 200.0:
	set(value):
		balloon_buoyancy = value
		_update_balloon()

## Spring stiffness. Higher = tighter tether, less bobbing. The
## equilibrium offset of the balloon from rest_length is buoyancy/stiffness
## — at defaults (200/15) the balloon sits ~13 px above rest position,
## giving a visible bob when gravity rotates. Raise for a stiffer feel,
## lower for a slingshotty tether.
@export_range(0.0, 1000.0, 5.0) var balloon_stiffness: float = 15.0:
	set(value):
		balloon_stiffness = value
		_update_joint()

## Spring damping. Higher = oscillation settles faster. 0 = perpetual
## oscillation. 3 gives a slight underdamped bob that settles in ~1s.
@export_range(0.0, 100.0, 0.5) var balloon_damping: float = 3.0:
	set(value):
		balloon_damping = value
		_update_joint()

## Distance from the platform center to the balloon center at rest.
## Larger = balloon floats further from the platform.
@export_range(10.0, 200.0, 5.0) var balloon_rest_length: float = 70.0:
	set(value):
		balloon_rest_length = value
		_update_joint()
		_update_balloon_string()

## Balloon visual + collision-shape radius. The collision shape is
## required by RigidBody2D for mass calculation, but the balloon has
## no actual collision (collision_layer = 0 in the scene file).
@export_range(4.0, 64.0, 1.0) var balloon_radius: float = 16.0:
	set(value):
		balloon_radius = value
		_update_balloon_shape()

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
	_update_spikes()
	# _t was already set by the starting_position setter. Re-apply in
	# case the setter didn't run (e.g., if the node was instantiated
	# without going through the script's setter chain -- e.g., loading
	# a scene where some children aren't yet in the tree).
	_t = clampf(starting_position, 0.0, 1.0)
	_update_position()
	_update_rail_preview()
	# Balloon: push current @export values to the balloon node and
	# BalloonJoint, then apply the visibility gate based on motion_type
	# and balloon_enabled. Same get_node_or_null pattern as the spike /
	# rail helpers — works in the editor and at runtime.
	_update_balloon()
	_update_joint()
	_update_balloon_shape()
	_update_balloon_visibility()
	# Runtime-only: signal connection + initial gravity sync. Gate
	# with is_editor_hint so @tool doesn't connect signals in the
	# editor (they don't fire there anyway, but connecting is wasted
	# work and the initial sync would mark the platform active based
	# on the editor's view of gravity).
	if Engine.is_editor_hint():
		return
	# Listen to gravity changes from the global GravityManager
	# singleton (Player writes to it in _rotate_gravity_cw). Initial
	# sync applies the current gravity so the platform is moving
	# immediately at scene load if gravity happens to be aligned with
	# the rail.
	_on_gravity_changed(GravityManager.gravity_direction)
	GravityManager.gravity_changed.connect(_on_gravity_changed)

func _physics_process(delta: float) -> void:
	# Skip motion in the editor -- @tool runs _physics_process, but
	# we only want motion at runtime.
	if Engine.is_editor_hint():
		return
	if _active:
		_t += _direction * (motion_speed / _rail_length) * delta
		_t = clampf(_t, 0.0, 1.0)
		_update_position()
	# Always update the balloon string (even when the platform is
	# stationary) so the tether tracks the balloon's live position.
	_update_balloon_string()

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

# Update the spike area: if has_spikes is true, populate the spike
# polygon on the chosen side and enable the Area2D's monitoring. If
# false, disable monitoring and hide the visual. Called whenever
# axis, has_spikes, or spike_direction changes (and at _ready).
# Reads the platform's current shape size to compute the side length,
# so the spike count and width track the platform's orientation --
# important for the 30x60 wide variant where the long/short side
# swaps with axis.
func _update_spikes() -> void:
	var spikes_area := get_node_or_null("AnimatableBody2D/SpikesArea")
	if not spikes_area:
		return
	var collision_node := spikes_area.get_node_or_null("SpikeCollision")
	var visual_node := spikes_area.get_node_or_null("SpikeVisual")
	if has_spikes:
		var body := get_node_or_null("AnimatableBody2D")
		if not body:
			return
		var shape_node := body.get_node_or_null("CollisionShape2D")
		if not shape_node or not shape_node.shape is RectangleShape2D:
			return
		var size := (shape_node.shape as RectangleShape2D).size
		if collision_node:
			collision_node.polygon = _spike_collision_polygon(size, spike_direction)
			collision_node.disabled = false
		if visual_node:
			visual_node.polygon = _spike_visual_polygon(size, spike_direction)
			visual_node.visible = true
	else:
		if collision_node:
			collision_node.disabled = true
		if visual_node:
			visual_node.visible = false

# Build the collision polygon for a given platform size and direction.
# This is a simple rectangle covering the entire spike area (from the
# platform's edge to 30 px out). Godot's convex decomposition algorithm
# (used by CollisionPolygon2D with build_mode = SOLID) fails on the
# triangular zigzag pattern, so the collision uses a rectangle instead.
# The rectangle covers the entire spike zone, so the player is killed
# when they enter the spike area.
func _spike_collision_polygon(size: Vector2, direction: SpikeDirection) -> PackedVector2Array:
	var points: Array[Vector2] = []
	const PEAK_DISTANCE := 30.0
	match direction:
		SpikeDirection.UP:
			points.append(Vector2(-size.x / 2.0, -size.y / 2.0))
			points.append(Vector2(size.x / 2.0, -size.y / 2.0))
			points.append(Vector2(size.x / 2.0, -size.y / 2.0 - PEAK_DISTANCE))
			points.append(Vector2(-size.x / 2.0, -size.y / 2.0 - PEAK_DISTANCE))
		SpikeDirection.DOWN:
			points.append(Vector2(-size.x / 2.0, size.y / 2.0))
			points.append(Vector2(size.x / 2.0, size.y / 2.0))
			points.append(Vector2(size.x / 2.0, size.y / 2.0 + PEAK_DISTANCE))
			points.append(Vector2(-size.x / 2.0, size.y / 2.0 + PEAK_DISTANCE))
		SpikeDirection.LEFT:
			points.append(Vector2(-size.x / 2.0, -size.y / 2.0))
			points.append(Vector2(-size.x / 2.0 - PEAK_DISTANCE, -size.y / 2.0))
			points.append(Vector2(-size.x / 2.0 - PEAK_DISTANCE, size.y / 2.0))
			points.append(Vector2(-size.x / 2.0, size.y / 2.0))
		SpikeDirection.RIGHT:
			points.append(Vector2(size.x / 2.0, -size.y / 2.0))
			points.append(Vector2(size.x / 2.0 + PEAK_DISTANCE, -size.y / 2.0))
			points.append(Vector2(size.x / 2.0 + PEAK_DISTANCE, size.y / 2.0))
			points.append(Vector2(size.x / 2.0, size.y / 2.0))
	return PackedVector2Array(points)

# Build the visual polygon for a given platform size and direction.
# Returns a single zigzag polygon (3 peaks along the chosen side, each
# 30 pixels out from the platform's edge). The polygon is a single
# closed shape assigned to Polygon2D.polygon (singular); the visual
# is meant for display only, so any rendering artifacts from the
# concave polygon are acceptable. The collision uses a separate
# rectangle polygon (see _spike_collision_polygon) that Godot can
# actually decompose.
func _spike_visual_polygon(size: Vector2, direction: SpikeDirection) -> PackedVector2Array:
	var points: Array[Vector2] = []
	const PEAK_DISTANCE := 30.0
	const NUM_TRIANGLES := 3
	match direction:
		SpikeDirection.UP:
			var edge_y := -size.y / 2.0
			var tri_w := size.x / NUM_TRIANGLES
			for i in range(NUM_TRIANGLES + 1):
				var base_x := -size.x / 2.0 + i * tri_w
				points.append(Vector2(base_x, edge_y))
				if i < NUM_TRIANGLES:
					var peak_x := -size.x / 2.0 + (i + 0.5) * tri_w
					points.append(Vector2(peak_x, edge_y - PEAK_DISTANCE))
		SpikeDirection.DOWN:
			var edge_y := size.y / 2.0
			var tri_w := size.x / NUM_TRIANGLES
			for i in range(NUM_TRIANGLES + 1):
				var base_x := -size.x / 2.0 + i * tri_w
				points.append(Vector2(base_x, edge_y))
				if i < NUM_TRIANGLES:
					var peak_x := -size.x / 2.0 + (i + 0.5) * tri_w
					points.append(Vector2(peak_x, edge_y + PEAK_DISTANCE))
		SpikeDirection.LEFT:
			var edge_x := -size.x / 2.0
			var tri_h := size.y / NUM_TRIANGLES
			for i in range(NUM_TRIANGLES + 1):
				var base_y := -size.y / 2.0 + i * tri_h
				points.append(Vector2(edge_x, base_y))
				if i < NUM_TRIANGLES:
					var peak_y := -size.y / 2.0 + (i + 0.5) * tri_h
					points.append(Vector2(edge_x - PEAK_DISTANCE, peak_y))
		SpikeDirection.RIGHT:
			var edge_x := size.x / 2.0
			var tri_h := size.y / NUM_TRIANGLES
			for i in range(NUM_TRIANGLES + 1):
				var base_y := -size.y / 2.0 + i * tri_h
				points.append(Vector2(edge_x, base_y))
				if i < NUM_TRIANGLES:
					var peak_y := -size.y / 2.0 + (i + 0.5) * tri_h
					points.append(Vector2(edge_x + PEAK_DISTANCE, peak_y))
	return PackedVector2Array(points)

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


# ---- Balloon ----

# Show/hide the balloon and its joint/string based on motion_type and
# balloon_enabled. The balloon shows when BOTH conditions are true;
# setting motion_type to WEIGHT (or balloon_enabled to false) hides
# the balloon, freezes the RigidBody2D (no drift, no wasted physics),
# and disables the joint + string.
#
# Called from the motion_type setter (auto-toggle) and the
# balloon_enabled setter (per-instance kill switch). Also called from
# _ready so the initial state matches the scene's motion_type value.
func _update_balloon_visibility() -> void:
	var balloon := get_node_or_null("Balloon") as RigidBody2D
	if not balloon:
		return
	var visible_state := motion_type == MotionType.BUOYANT and balloon_enabled
	balloon.visible = visible_state
	balloon.freeze = not visible_state
	# DampedSpringJoint2D has no `enabled` property in Godot 4. A frozen
	# RigidBody2D doesn't respond to joint forces, so the balloon.freeze
	# above is enough to disable the joint — no separate gate needed.
	var string_node := get_node_or_null("AnimatableBody2D/BalloonString") as Line2D
	if string_node:
		string_node.visible = visible_state


# Push the current balloon_buoyancy value to the Balloon node. Called
# from the balloon_buoyancy setter and at _ready.
func _update_balloon() -> void:
	var balloon := get_node_or_null("Balloon")
	if balloon and "buoyancy_strength" in balloon:
		balloon.buoyancy_strength = balloon_buoyancy


# Push the current spring tuning to the BalloonJoint. Called from the
# stiffness/damping/rest_length setters and at _ready.
func _update_joint() -> void:
	var joint := get_node_or_null("BalloonJoint") as DampedSpringJoint2D
	if not joint:
		return
	joint.stiffness = balloon_stiffness
	joint.damping = balloon_damping
	joint.rest_length = balloon_rest_length


# Apply the current balloon_radius to the Balloon's collision shape
# (required by RigidBody2D for mass calc — no actual collision since
# collision_layer = 0) and visual polygon.
func _update_balloon_shape() -> void:
	var balloon := get_node_or_null("Balloon")
	if not balloon:
		return
	var shape := balloon.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape and shape.shape is CircleShape2D:
		(shape.shape as CircleShape2D).radius = balloon_radius
	var visual := balloon.get_node_or_null("BalloonVisual") as Polygon2D
	if visual:
		visual.polygon = _circle_polygon(balloon_radius)


# 32-sided circle approximation for the balloon visual placeholder.
# Replaced with pixel art by Jason later; this is a clean placeholder
# that reads as circular at typical viewing zoom.
func _circle_polygon(radius: float) -> PackedVector2Array:
	const SIDES := 32
	var points: Array[Vector2] = []
	for i in SIDES:
		var angle := TAU * float(i) / float(SIDES)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return PackedVector2Array(points)


# Update the balloon string (Line2D child of AnimatableBody2D) to
# connect the platform center to the balloon's current position.
# The string is in body-local space — Vector2.ZERO is the platform
# center, the second point is the balloon's position in the body's
# local frame.
#
# Skipped when the string is hidden (e.g., balloon is frozen because
# motion_type is WEIGHT) to avoid wasted work and stale-line flicker.
func _update_balloon_string() -> void:
	var string_node := get_node_or_null("AnimatableBody2D/BalloonString") as Line2D
	if not string_node or not string_node.visible:
		return
	var balloon := get_node_or_null("Balloon") as RigidBody2D
	if not balloon:
		return
	var body := get_node_or_null("AnimatableBody2D") as AnimatableBody2D
	if not body:
		return
	string_node.points = PackedVector2Array([
		Vector2.ZERO,
		body.to_local(balloon.global_position),
	])
