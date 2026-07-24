extends CharacterBody2D
##
## Clockwork player — a small blob that hops between platforms.
##
## Visual is a colored box for now (Polygon2D child);
## will be replaced with an AnimatedSprite2D when Jason's sprite art lands.
##

# Death animation — total ~0.3s (flash + hold) before the level
# orchestrator reloads the scene. Tune both together if the death
# feels too snappy or too drawn out.
const DEATH_FLASH_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const DEATH_FLASH_TIME := 0.1
const DEATH_HOLD_TIME := 0.2

# Movement tuning — tweak together once level layouts exist.
## Horizontal speed (px/s) the input drives the player toward.
## The player can EXCEED this via ramp launches and drops — this is
## a target, not a hard cap.
@export var RUN_SPEED := 200.0
## Lateral acceleration toward RUN_SPEED (px/s²) on the ground.
@export var RUN_ACCEL: float = 1500.0
## Lateral acceleration toward RUN_SPEED (px/s²) in the air. Reduced
## vs RUN_ACCEL so jumps feel committed and momentum is preserved —
## the player can nudge their trajectory mid-air but not redirect it.
@export var AIR_ACCEL: float = 700.0
## Upward impulse on jump (negative = up).
@export var JUMP_VELOCITY := -400.0
## Downward acceleration (px/s²).
@export var GRAVITY := 980.0
## How fast the player stops on flat ground (px/s²). On slopes,
## momentum is preserved — the slope slide + friction handle
## deceleration instead.
@export var GROUND_DECEL := 1500.0

## Extra downward acceleration while the down arrow is held. Adds to
## Vector2.DOWN in world coords, so the world doesn't need to know
## which way gravity "points" — the level rotates around the player
## but gravity itself stays Vector2.DOWN (per Jason, 2026-07-24).
##
## Effects:
##   - On slopes: augments the gravity-projected slope slide, so the
##     player can push through high-friction slopes instead of slowing
##     down. Move-and-slide naturally projects the extra downward
##     velocity onto the slope plane.
##   - In midair: doubles as a fast-fall (player falls faster when
##     pressing down).
##   - On flat ground: no visible effect — move_and_slide clamps the
##     extra downward velocity back to zero against the floor.
##
## Magnitude: 1500 is ~1.5x GRAVITY. Strong enough to feel snappy on
## slopes, not so strong it feels like a teleport. Tune in the
## inspector once L1 has slopes in it.
@export var DOWN_BOOST: float = 1500.0

## Number of physics frames a jump press is remembered while airborne.
## 5 frames (~83ms at 60fps) is a common platformer feel.
## Higher = more forgiving; lower = stricter timing required.
@export var JUMP_BUFFER_FRAMES: int = 5

## Sample depth (px) below the player's bottom to look for the contact cell.
## Tune in the inspector for different player sizes or tile sizes.
@export var surface_query_depth: float = 4.0
## X offsets (relative to player center) of the surface query points.
## Default 3 points (left, center, right at -12/0/+12) catch the slope
## cells at a 45-degree V joint: the center point lands in the V (no
## data), the side points land on the slopes. The MIN friction across
## all points is used (most slippery surface in contact).
##
## Steeper slopes + larger V width may need wider X offsets to catch
## the slope cells past the V.
@export var surface_query_x_offsets: PackedFloat32Array = [-12.0, 0.0, 12.0]

## Master toggle for the per-frame debug print. Set false in the inspector
## to silence the console output when not debugging.
@export var debug_output: bool = true
## Seconds between debug prints. Smaller = more frequent, more spammy.
@export var debug_poll_interval: float = 0.5

# Reference to the TileMapLayer for per-tile friction lookup.
# RotatingLevelComponents is a sibling of Player under Main, so
# "../RotatingLevelComponents/TileMapLayer" is the relative path.
@onready var _tile_map: TileMapLayer = $"../RotatingLevelComponents/TileMapLayer"

# Reference to the CollisionShape2D — used to compute the player's
# bottom offset for the friction query. Different shapes have
# different "bottoms" — see _get_bottom_offset().
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

# Emitted when the player enters a death zone. The level orchestrator
# listens for this and runs the death flow (flash → freeze → hide → reset).
signal died

var _jump_buffer: int = 0
var _debug_accum: float = 0.0
# Death-in-progress flag. Set true when _die() starts so _physics_process
# early-returns and input handlers ignore presses. Prevents double-fire
# from the DeathDetector while the death animation is running.
var _is_dying: bool = false

func _ready() -> void:
	# Tag the player so damage / pickup / win-zone checks can find us
	# without hardcoded path lookups. Same convention as the raccoon
	# Metroidvania project — write the is_in_group check AND the
	# add_to_group call in the same commit, never split them up.
	add_to_group("player")

func _physics_process(delta: float) -> void:
	# Death freezes the player — skip all movement/physics while dying.
	# The level orchestrator handles the reset; this is just the freeze.
	if _is_dying:
		return
	# Horizontal input from left/right arrows or A/D.
	var input_dir := Input.get_axis("ui_left", "ui_right")

	# Read surface friction (0 = ice, 1 = full grip). Default 1.0
	# (no slip) when no query point hits a tile with friction data.
	var friction := _get_current_friction()

	# Apply horizontal velocity. Three cases:
	#   - In the air: accelerate toward RUN_SPEED at AIR_ACCEL (reduced
	#     control so jumps feel committed and momentum is preserved).
	#     No horizontal decel — momentum is preserved mid-flight.
	#   - On the ground with input: accelerate toward RUN_SPEED at
	#     RUN_ACCEL. Don't hard-cap so the player can exceed RUN_SPEED
	#     via ramp launches and drops.
	#   - On the ground with no input: decelerate only on flat ground.
	#     On slopes, the slope slide + friction handle deceleration
	#     naturally — adding horizontal decel on top would eat the
	#     momentum the player built up on the ramp or drop.
	if not is_on_floor():
		if input_dir != 0:
			velocity.x = move_toward(velocity.x, input_dir * RUN_SPEED, AIR_ACCEL * delta)
	elif input_dir != 0:
		velocity.x = move_toward(velocity.x, input_dir * RUN_SPEED, RUN_ACCEL * delta)
	else:
		# Grounded with no input. Decel only on flat ground.
		if abs(get_floor_normal().y) >= 0.999:
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

	# Down arrow applies extra downward force (Vector2.DOWN in world coords).
	# On slopes it augments the gravity-projected slide so the player can
	# push through high-friction slopes; in midair it doubles as a fast-fall.
	# Placed BEFORE vertical physics so the boost combines with gravity /
	# slope slide in the same frame — one velocity vector goes into move_and_slide.
	if Input.is_action_pressed("ui_down"):
		velocity += Vector2.DOWN * DOWN_BOOST * delta

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
	# On flat ground (|floor_normal.y| ≈ 1), the projection is zero —
	# no slide. Friction scales the slide via (1 - friction).
	#
	# Godot's documented convention is floor_normal points UP toward
	# the player (so flat ground gives y = -1). The abs() check handles
	# both sign conventions of the normal.
	#
	# 1-frame delay (uses last frame's floor_normal) is barely
	# noticeable. A frame-perfect version would defer this until
	# after move_and_slide, but for game-jam timing it's fine.
	var floor_normal := get_floor_normal()
	if abs(floor_normal.y) >= 0.999:
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

func _on_death_detector_body_entered(_body: Node2D) -> void:
	# DeathDetector (an Area2D child with collision_mask = 2) fires this
	# whenever a body on the TileSet's physics_layer_1 (the "death"
	# layer) enters the player's space. The body itself is just the
	# spike tile's StaticBody2D -- we don't need to inspect it, any
	# overlap with the death layer is fatal.
	#
	# Guard against double-fire: a multi-tile spike row can trigger
	# body_entered on consecutive frames; _is_dying makes sure we only
	# start the death sequence once.
	if _is_dying:
		return
	_die()

func _die() -> void:
	# Flash red → brief hold → hide → emit `died`. The level
	# orchestrator listens for `died` and reloads the scene.
	# Total duration = DEATH_FLASH_TIME + DEATH_HOLD_TIME (~0.3s).
	#
	# modulate is set on the Player node so it tints all children
	# (AnimatedSprite2D, Polygon2D visual, etc.). visible = false on
	# Player hides everything together.
	_is_dying = true
	modulate = DEATH_FLASH_COLOR
	await get_tree().create_timer(DEATH_FLASH_TIME).timeout
	visible = false
	await get_tree().create_timer(DEATH_HOLD_TIME).timeout
	died.emit()
