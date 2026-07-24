extends CharacterBody2D
##
## Clockwork player — a small blob that hops between platforms.
##
## Visual is a colored box for now (Polygon2D child);
## will be replaced with an AnimatedSprite2D when Jason's sprite art lands.
##

# Movement tuning — tweak together once level layouts exist.
@export var RUN_SPEED := 200.0       # Horizontal speed (px/s) while moving
@export var JUMP_VELOCITY := -400.0  # Upward impulse on jump (negative = up)
@export var GRAVITY := 980.0         # Downward acceleration (px/s²)
@export var GROUND_DECEL := 1500.0   # How fast the player stops on the ground (px/s²)

# Input buffering — number of physics frames a jump press is remembered
# while airborne. 5 frames (~83ms at 60fps) is a common platformer feel.
# Higher = more forgiving; lower = stricter timing required.
@export var JUMP_BUFFER_FRAMES: int = 5

# Surface query — sample a few points a few pixels below the player's
# bottom to find the actual contact cell. Default 3 points (left, center,
# right at -12/0/+12 from the player's center) catch the slope cells at
# a 45 degree V joint: the center point lands in the V (no data), the
# side points land on the slopes. We take the MIN friction (most
# slippery surface in contact).
#
# Tune in the inspector for different player sizes, tile sizes, or
# steeper slopes. Steeper slopes + larger V width may need wider X
# offsets to catch the slope cells past the V.
@export var surface_query_depth: float = 4.0
@export var surface_query_x_offsets: PackedFloat32Array = [-12.0, 0.0, 12.0]

# Debug output — prints state to console every debug_poll_interval seconds.
# Set debug_output = false in the inspector to silence when not debugging.
@export var debug_output: bool = true
@export var debug_poll_interval: float = 0.5

# Reference to the TileMapLayer for per-tile friction lookup.
# RotatingLevelComponents is a sibling of Player under Main, so
# "../RotatingLevelComponents/TileMapLayer" is the relative path.
@onready var _tile_map: TileMapLayer = $"../RotatingLevelComponents/TileMapLayer"

# Reference to the CollisionShape2D — used to compute the player's
# bottom offset for the friction query. Different shapes have
# different "bottoms" — see _get_bottom_offset().
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

var _jump_buffer: int = 0
var _debug_accum: float = 0.0

func _ready() -> void:
	# Tag the player so damage / pickup / win-zone checks can find us
	# without hardcoded path lookups. Same convention as the raccoon
	# Metroidvania project — write the is_in_group check AND the
	# add_to_group call in the same commit, never split them up.
	add_to_group("player")

func _physics_process(delta: float) -> void:
	# Horizontal input from left/right arrows or A/D.
	var input_dir := Input.get_axis("ui_left", "ui_right")

	# Read surface friction (0 = ice, 1 = full grip). Default 1.0
	# (no slip) when no query point hits a tile with friction data.
	var friction := _get_current_friction()

	# Apply horizontal velocity. With no input, decelerate to a stop;
	# friction scales the deceleration.
	if input_dir != 0:
		velocity.x = input_dir * RUN_SPEED
	else:
		var decel := GROUND_DECEL * friction
		velocity.x = move_toward(velocity.x, 0, decel * delta)

	# Jump with input buffering. If the player presses jump while airborne,
	# the press is queued for up to JUMP_BUFFER_FRAMES frames so it
	# triggers as soon as they land. Without this, players have to time
	# the press to the exact landing frame, which feels bad.
	if Input.is_action_just_pressed("ui_accept"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			_jump_buffer = 0
		else:
			_jump_buffer = JUMP_BUFFER_FRAMES
	elif _jump_buffer > 0 and is_on_floor():
		# Buffered jump fires within JUMP_BUFFER_FRAMES frames of landing.
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0

	# Buffer decrements each frame; if it hits 0 without firing, the
	# buffered press is forgotten.
	if _jump_buffer > 0:
		_jump_buffer -= 1

	# Vertical physics: gravity when airborne, slope slide when grounded.
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		# On a slope, project gravity onto the slope plane and apply as
		# acceleration. The player slides down slopes instead of sticking.
		# Friction scales the slide: ice (0) = full slide, dirt (1) = none.
		_apply_slope_slide(delta, friction)

	# move_and_slide resolves collisions against walls / platforms using
	# this body's CollisionShape2D. Must be the LAST physics line —
	# anything after it reads the post-collision velocity.
	move_and_slide()

	# Debug output: print state to console every debug_poll_interval
	# seconds. Toggle off via debug_output = false in the inspector.
	if debug_output:
		_debug_accum += delta
		if _debug_accum >= debug_poll_interval:
			_debug_accum = 0.0
			_print_debug_state()

func _get_current_friction() -> float:
	return _get_friction_info()["friction"]

func _get_friction_info() -> Dictionary:
	# Sample a few points a few pixels below the player's bottom. Each
	# X offset in surface_query_x_offsets is a separate query point;
	# the cell with the lowest friction is the contact (most slippery
	# surface in contact). The center point is the default contact;
	# side points catch the slope cells at V joints where the player's
	# bottom cell has no data.
	#
	# Returns {"friction": float, "contact_cell": Vector2i}.
	# contact_cell is (-1, -1) when no query point hits a tile with
	# friction data (i.e., the player is airborne).
	if not _tile_map:
		return {"friction": 1.0, "contact_cell": Vector2i(-1, -1)}
	var query_y := global_position.y + _get_bottom_offset() + surface_query_depth
	var best := {"friction": 1.0, "contact_cell": Vector2i(-1, -1)}
	for offset in surface_query_x_offsets:
		var query_point := Vector2(global_position.x + offset, query_y)
		var local_pos := _tile_map.to_local(query_point)
		var cell := _tile_map.local_to_map(local_pos)
		var tile_data := _tile_map.get_cell_tile_data(cell)
		if tile_data and tile_data.has_custom_data("friction"):
			var f := float(tile_data.get_custom_data("friction"))
			if f < best["friction"]:
				best["friction"] = f
				best["contact_cell"] = cell
	return best

func _get_bottom_offset() -> float:
	# y-offset from the player's center to the bottom of its collider.
	# Different shapes have different "bottoms":
	#   - Rectangle: half of size.y (the box's center is the body's center)
	#   - Circle: the radius (it's centered)
	#   - Capsule: half the height + the radius (rounded ends)
	if not _collision_shape or not _collision_shape.shape:
		return 0.0
	var shape := _collision_shape.shape
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5
	elif shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	elif shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		return cap.height * 0.5 + cap.radius
	return 0.0

func _apply_slope_slide(delta: float, friction: float) -> void:
	# Project gravity onto the slope plane and apply as acceleration.
	# On flat ground (floor_normal.y == 1), the projection is zero —
	# no slide. Friction scales the slide via (1 - friction).
	#
	# 1-frame delay (uses last frame's floor_normal) is barely
	# noticeable. A frame-perfect version would defer this until
	# after move_and_slide, but for game-jam timing it's fine.
	var floor_normal := get_floor_normal()
	if floor_normal.y >= 0.999:
		return  # flat ground, no slide needed
	var gravity := Vector2.DOWN * GRAVITY
	var slide := gravity - floor_normal * gravity.dot(floor_normal)
	velocity += slide * (1.0 - friction) * delta

func _print_debug_state() -> void:
	# One-line state dump for diagnosing wedges, friction mismatches,
	# and slope-slide behavior. contact_cell is the cell that
	# contributed the lowest friction — different from the player's
	# bottom cell when at a slope joint or straddling cells.
	if not _tile_map:
		return
	var info := _get_friction_info()
	var floor_normal_str := "(off ground)"
	if is_on_floor():
		floor_normal_str = str(get_floor_normal())
	var contact_str := "(no contact)"
	if info["contact_cell"] != Vector2i(-1, -1):
		contact_str = str(info["contact_cell"])
	print("[player] pos=", global_position,
		" contact_cell=", contact_str,
		" friction=", info["friction"],
		" on_floor=", is_on_floor(),
		" on_wall=", is_on_wall(),
		" floor_normal=", floor_normal_str,
		" vel=", velocity)
