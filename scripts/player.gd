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
## Jump impulse magnitude. Applied in the current "up" direction
## (opposite of gravity). Stored as a negative number (up); the
## magnitude is |JUMP_VELOCITY|.
@export var JUMP_VELOCITY := -400.0
## Gravitational acceleration magnitude (px/s²). Used together with
## gravity_direction to apply gravity in the current "down" direction.
# Bumped from 980 to 1500 (2026-07-25) per Jason's playtest: more
# gravity = more slide acceleration on slopes, which makes the
# 'rolling' feel more pronounced. If tumbling emerges from
# overspeed rather than under-anchoring, dial this back down.
@export var gravity_strength := 1500.0

## If true, the body keeps the same horizontal speed on slopes (no
## acceleration downhill, no deceleration uphill). Without this,
## gravity 1500 + low-friction slopes makes the player build speed
## quickly on downhills, and the engine briefly loses contact at
## slope transitions (steep->flat, etc.) - the result is a visible
## "hop" or "bounce" feel.
## Set false for the original "rolling ball picks up speed" feel.
@export var FLOOR_CONSTANT_SPEED: bool = true
## How far (px) along the body's up_direction the engine will try to
## keep the player snapped to the floor on slope transitions. Larger
## = smoother slope continuity; default in Godot 4 is 1.0, which is
## too tight for slopes the player can build significant speed on.
## Combined with FLOOR_CONSTANT_SPEED this gives a smooth slide
## rather than a bouncy one.
@export var FLOOR_SNAP_LENGTH: float = 4.0

## Minimum downward speed (px/s, in the gravity direction) at which a
## landing plays the landing SFX. Any value below this is considered a
## "small bump" (walking off a curb, stepping onto a tile) and stays
## silent. A normal jump lands at ~400 px/s (JUMP_VELOCITY magnitude
## with gravity 1500), so 200 filters out tiny step-ups without
## silencing ordinary landings.
const LANDING_SOUND_MIN_SPEED: float = 200.0

## Direction of gravity in world coordinates. Starts pointing down
## (Vector2.DOWN = (0, 1)). Rotates 90° CW on each clock tick.
var gravity_direction: Vector2 = Vector2.DOWN
## How fast the player stops on flat ground (px/s²). On slopes,
## momentum is preserved — the slope slide + friction handle
## deceleration instead.
@export var GROUND_DECEL := 1500.0

## Extra acceleration while the down arrow is held. Applied in the
## current gravity direction, so "down" always means "toward gravity"
## regardless of which way gravity currently points.
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
## Magnitude: 1500 is ~1.5x gravity_strength. Strong enough to feel
## snappy on slopes, not so strong it feels like a teleport. Tune in
## the inspector once L1 has slopes in it.
@export var DOWN_BOOST: float = 1500.0

## Number of physics frames a jump press is remembered while airborne.
## 5 frames (~83ms at 60fps) is a common platformer feel.
## Higher = more forgiving; lower = stricter timing required.
@export var JUMP_BUFFER_FRAMES: int = 5

## Number of physics frames AFTER leaving the floor that the player
## can still jump (the "coyote time" window). 5 frames (~83ms)
## mirrors JUMP_BUFFER_FRAMES for symmetric feel. Higher = more
## forgiving (jumping just after walking off a ledge still works);
## lower = stricter timing. Without this, jumping the instant you
## walk off a ledge feels unresponsive.
@export var COYOTE_FRAMES: int = 5

## Number of physics frames AFTER dislodging from a sticky wall during
## which the player cannot re-engage a sticky tile. Prevents pinball-
## chain wall-jumps where the player can immediately re-stick on the
## same tile. 4 frames (~67ms at 60fps) gives a short breath between
## jumps so the dislodge feels deliberate.
@export var STICKY_REFRACTION_FRAMES: int = 4

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

## How long the camera rotation takes to complete after each gravity
## change. Small enough to feel responsive, large enough to be
## readable — 0.25 is a quick pan; bump up for more dramatic
## transitions.
@export var camera_rotation_duration: float = 0.25

## Camera zoom multiplier. Values < 1 zoom out (see more of the
## scene), values > 1 zoom in (objects appear larger, less area
## visible). Default (1, 1) = no zoom change. Same value applies
## to both X and Y for an isotropic zoom.
@export var camera_zoom: Vector2 = Vector2(1, 1)

# Reference to the TileMapLayer for per-tile friction lookup.
# TileMapLayer is a sibling of Player under Main, so "../TileMapLayer"
# is the relative path.
@onready var _tile_map: TileMapLayer = $"../TileMapLayer"

# Reference to the CollisionShape2D — used to compute the player's
# bottom offset for the friction query. Different shapes have
# different "bottoms" — see _get_bottom_offset().
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

# SFX — AudioStreamPlayer children configured in player.tscn with the
# matching .wav streams. play() called at the moment the action fires
# (jump input handled below; death triggered in _die()).
@onready var _jump_sound: AudioStreamPlayer = $JumpSound
@onready var _land_sound: AudioStreamPlayer = $LandSound
@onready var _die_sound: AudioStreamPlayer = $DieSound

# Camera created programmatically (added as a child in _create_camera).
# Follows the player automatically as a child node. Rotates to match the
# new "down" direction on each clock tick (see _rotate_gravity_cw).
@onready var _camera: Camera2D = _create_camera()

# Emitted when the player enters a death zone. The level orchestrator
# listens for this and runs the death flow (flash → freeze → hide → reset).
signal died

# Emitted when gravity rotates to a new direction. Listeners (e.g.,
# moving platforms) use this to update motion state without needing
# to track ticks separately. Player remains the source of truth for
# its own gravity_direction.
signal gravity_changed(new_direction: Vector2)

var _jump_buffer: int = 0
# Frames since the player last touched the floor. Drives coyote time:
# while _frames_since_grounded <= COYOTE_FRAMES, the player can
# still jump even though they're airborne. Initial value (1000) is
# large so a freshly-spawned player doesn't get coyote time on the
# first air frame; reset to 1000 after each successful jump so
# coyote jumps can't chain without touching ground in between.
var _frames_since_grounded: int = 1000
var _debug_accum: float = 0.0
# Tracks the current camera rotation tween so a new one can kill the
# old one if a tick fires mid-rotation.
var _camera_tween: Tween = null
# Tracks the floor state from the previous physics frame so the
# landing-detection logic can fire on the airborne->grounded transition
# (not on every frame the player happens to be on the floor).
var _was_on_floor: bool = false
# Death-in-progress flag. Set true when _die() starts so _physics_process
# early-returns and input handlers ignore presses. Prevents double-fire
# from the DeathDetector while the death animation is running.
var _is_dying: bool = false
# True when the player is currently clinging to a sticky tile. While
# true, horizontal input + gravity + down-boost are all skipped --
# the player is fully locked to the wall. Cleared by jump (via the
# dislodge code in the jump branch of _physics_process).
var _is_stuck_to_wall: bool = false
# Counts down from STICKY_REFRACTION_FRAMES after a dislodge. While > 0,
# _is_stuck_to_wall cannot be re-engaged, so the jump arc can clear
# the sticky tile before another sticky attachment is allowed.
var _frames_since_disloged: int = 0

func _ready() -> void:
	# Slope-feel setup: apply floor physics tunables before any motion.
	# These are CharacterBody2D properties; setting them in code
	# (rather than via the scene file) keeps the tunables visible as
	# @export vars in the inspector and easy to tweak per-player if
	# needed later. floor_constant_speed eliminates the velocity jump
	# at slope transitions; floor_snap_length widens the snap window
	# so the engine keeps the player attached across small slope-
	# normal shifts mid-tick.
	floor_constant_speed = FLOOR_CONSTANT_SPEED
	floor_snap_length = FLOOR_SNAP_LENGTH
	# Tag the player so damage / pickup / win-zone checks can find us
	# without hardcoded path lookups. Same convention as the raccoon
	# Metroidvania project — write the is_in_group check AND the
	# add_to_group call in the same commit, never split them up.
	add_to_group("player")
	# Connect to the clock's tick event. Each countdown_zero rotates
	# gravity 90° CW. ClockUI is a sibling of Player under Main, so
	# look it up via the parent.
	var clock := get_parent().get_node_or_null("ClockUI")
	if clock and clock.has_signal("countdown_zero"):
		clock.countdown_zero.connect(_rotate_gravity_cw)

# Creates the camera as a child of the player so it follows automatically.
# Called from the @onready var initialization. The first enabled
# Camera2D in the scene tree becomes the current camera, so this
# just works without needing to set anything else.
func _create_camera() -> Camera2D:
	var camera := Camera2D.new()
	# ignore_rotation defaults to true which in some Godot 4 builds
	# effectively pins the camera's effective rotation to 0 when the
	# parent isn't rotating -- the tween sets _camera.rotation but
	# the visual stays still. Set false so our tween actually drives
	# the view rotation.
	camera.ignore_rotation = false
	camera.zoom = camera_zoom
	add_child(camera)
	# Make explicit so this is always the current camera, even if
	# another Camera2D enters the tree first (e.g., from a future
	# scene loaded on top).
	camera.make_current()
	return camera

func _physics_process(delta: float) -> void:
	# Death freezes the player — skip all movement/physics while dying.
	# The level orchestrator handles the reset; this is just the freeze.
	if _is_dying:
		return
	# Decrement sticky refraction cooldown. While > 0, the player cannot
	# re-engage sticky (prevents pinball-chain wall-jumps where the
	# player can immediately re-stick on the same tile after dislodging).
	if _frames_since_disloged > 0:
		_frames_since_disloged -= 1
	# Detect sticky: if the wall we're currently touching has a tile
	# marked sticky=true, set _is_stuck_to_wall. Uses the previous
	# frame's wall collision (move_and_slide updated is_on_wall last
	# frame -- this 1-frame delay is imperceptible at 60fps). Skipped
	# during the refraction cooldown so a dislodge arc can clear the
	# wall before another attachment is allowed.
	if is_on_wall() and _frames_since_disloged == 0:
		_is_stuck_to_wall = _is_wall_tile_sticky()
	else:
		_is_stuck_to_wall = false
	# Maintain coyote-time counter: 0 while grounded, +1 per air frame.
	# Reset to 1000 after a successful jump (below) so coyote jumps
	# can't chain without the player touching ground in between.
	if is_on_floor():
		_frames_since_grounded = 0
	else:
		_frames_since_grounded += 1
	# Capture velocity before move_and_slide so we can recover the
	# impact speed (the velocity the player hit the ground with) even
	# after move_and_slide zeroes the floor-normal component. Then
	# detect the airborne->grounded transition and play the landing
	# SFX if the impact speed in the gravity direction exceeds the
	# threshold.
	var pre_move_velocity := velocity
	move_and_slide()
	if not _was_on_floor and is_on_floor():
		var impact_speed := pre_move_velocity.dot(gravity_direction)
		if impact_speed > LANDING_SOUND_MIN_SPEED:
			_land_sound.play()
	_was_on_floor = is_on_floor()
	# Horizontal input from left/right arrows or A/D.
	var input_dir := Input.get_axis("ui_left", "ui_right")

	# Read surface friction (0 = ice, 1 = full grip). Default 1.0
	# (no slip) when no query point hits a tile with friction data.
	var friction := _get_current_friction()

	# Apply horizontal velocity. Gravity-relative: "press right" always
	# means "right from the player's perspective", which is the direction
	# perpendicular to gravity, rotated 90° CW from gravity. With gravity
	# straight down, right is +x. With gravity pointing right, right is
	# -y (the player walks 'up' the wall). Etc.
	#
	# Three cases:
	#   - In the air: accelerate toward RUN_SPEED at AIR_ACCEL (reduced
	#     control so jumps feel committed and momentum is preserved).
	#     No horizontal decel — momentum is preserved mid-flight.
	#   - On the ground with input: accelerate toward RUN_SPEED at
	#     RUN_ACCEL. Don't hard-cap so the player can exceed RUN_SPEED
	#     via ramp launches and drops.
	#   - On the ground with no input: decelerate only on flat ground
	#     (relative to gravity, not just world-flat). On slopes, the
	#     slope slide + friction handle deceleration naturally.
	# When stuck to a wall, skip all horizontal motion -- the player is
	# fully locked. Jump is the only way to dislodge (see below).
	if not _is_stuck_to_wall:
		var right_direction := gravity_direction.rotated(-PI / 2.0)
		if not is_on_floor():
			if input_dir != 0:
				var current_right_speed := velocity.dot(right_direction)
				# Don't fight momentum. If the player is already at or above
				# RUN_SPEED in the input direction, skip input acceleration
				# entirely so slope slides and jumps preserve their velocity.
				# (The comment block above says "don't hard-cap" but the
				# original code did via move_toward; this restores the
				# intended behavior -- ramps feel like ramps because you
				# can build speed on them and carry it off into a jump.)
				if input_dir * current_right_speed < RUN_SPEED:
					var target_right_speed := input_dir * RUN_SPEED
					var new_right_speed := move_toward(current_right_speed, target_right_speed, AIR_ACCEL * delta)
					velocity += (new_right_speed - current_right_speed) * right_direction
		elif input_dir != 0:
			var current_right_speed := velocity.dot(right_direction)
			# Same skip-if-over-target logic as the air branch -- the
			# player can build speed on a slope and carry it off the ramp
			# (or use it to jump farther) without the input fighting it.
			if input_dir * current_right_speed < RUN_SPEED:
				var target_right_speed := input_dir * RUN_SPEED
				var new_right_speed := move_toward(current_right_speed, target_right_speed, RUN_ACCEL * delta)
				velocity += (new_right_speed - current_right_speed) * right_direction
		else:
			# Grounded with no input. Decel only on flat ground relative
		# to gravity (floor_normal aligned with -gravity_direction).
			if abs(get_floor_normal().dot(-gravity_direction)) >= 0.999:
				var decel := GROUND_DECEL * friction
				var current_right_speed := velocity.dot(right_direction)
				var new_right_speed := move_toward(current_right_speed, 0, decel * delta)
				velocity += (new_right_speed - current_right_speed) * right_direction

	# Jump with input buffering. If the player presses jump while airborne,
	# the press is queued for up to JUMP_BUFFER_FRAMES frames so it
	# triggers as soon as they land. Without this, players have to time
	# the press to the exact landing frame, which feels bad.
	if Input.is_action_just_pressed("ui_accept"):
		# Coyote time: also allow jump within COYOTE_FRAMES frames
		# of leaving the floor. is_on_floor() is checked first so a
		# real grounded jump takes the immediate path (and resets the
		# counter below).
		# Allow jump if on floor, within coyote time, OR stuck to a wall.
		# is_on_floor() is checked first so a real grounded jump takes
		# the immediate path (and resets the counter below).
		if is_on_floor() or _frames_since_grounded <= COYOTE_FRAMES or _is_stuck_to_wall:
			# Jump in the current "up" direction (opposite of gravity).
			# Keep velocity perpendicular to gravity, replace the
			# along-gravity component with the jump speed. JUMP_VELOCITY
			# is stored as a negative number (up), so the magnitude is
			# -JUMP_VELOCITY.
			var along_gravity := velocity.dot(gravity_direction) * gravity_direction
			var perp_to_gravity := velocity - along_gravity
			velocity = perp_to_gravity + gravity_direction * JUMP_VELOCITY
			_jump_sound.play()
			_jump_buffer = 0
			# Consume coyote time after a successful jump so the player
			# must touch the floor again before another coyote jump.
			_frames_since_grounded = 1000
			# If we jumped off a sticky wall, disengage sticky and start
			# the refraction cooldown so the jump arc can clear the tile
			# before another attachment is allowed.
			if _is_stuck_to_wall:
				_is_stuck_to_wall = false
				_frames_since_disloged = STICKY_REFRACTION_FRAMES
		else:
			_jump_buffer = JUMP_BUFFER_FRAMES
	elif _jump_buffer > 0 and is_on_floor():
		# Buffered jump fires within JUMP_BUFFER_FRAMES frames of landing.
		# Same up-direction logic as the immediate jump above.
		var along_gravity := velocity.dot(gravity_direction) * gravity_direction
		var perp_to_gravity := velocity - along_gravity
		velocity = perp_to_gravity + gravity_direction * JUMP_VELOCITY
		_jump_sound.play()
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
	# Skipped when stuck to a wall -- the player can't push the wall
	# with "down" while clinging.
	if not _is_stuck_to_wall and Input.is_action_pressed("ui_down"):
		# Down-boost in the current gravity direction. On slopes this
		# augments the gravity-projected slide; in midair it doubles
		# as a fast-fall.
		velocity += gravity_direction * DOWN_BOOST * delta

	# Vertical physics: gravity when airborne, slope slide when grounded.
	# Skipped when stuck to a wall -- the player defies gravity while
	# clinging. The sticky attachment holds them in place.
	if _is_stuck_to_wall:
		pass  # No gravity, no slope slide -- player locked to wall.
	elif not is_on_floor():
		velocity += gravity_direction * gravity_strength * delta
	else:
		# On a slope, project gravity onto the slope plane and apply as
		# acceleration. The player slides down slopes instead of sticking.
		# Friction scales the slide: ice (0) = full slide, dirt (1) = none.
		_apply_slope_slide(delta, friction)

	# move_and_slide resolves collisions against walls / platforms using
	# this body's CollisionShape2D. Must be the LAST physics line —
	# anything after it reads the post-collision velocity. Uses the
	# up_direction property (set by _rotate_gravity_cw) to determine
	# the "up" direction for collision resolution and slope sliding.
	move_and_slide()

	# Debug output: print state to console every debug_poll_interval
	# seconds. Toggle off via debug_output = false in the inspector.
	if debug_output:
		_debug_accum += delta
		if _debug_accum >= debug_poll_interval:
			_debug_accum = 0.0
			_print_debug_state()

# Returns true if the player is currently touching a sticky tile on a
# wall. Looks up the wall-side tile via the TileMap, checks its
# "sticky" custom data field (set per-tile in the editor). Returns
# false if not touching any wall, or if the wall tile doesn't have
# sticky=true.
#
# Uses get_wall_normal() to find the wall direction: the tile is in
# the direction opposite wall_normal, at a sample distance slightly
# outside the player's collision radius (14px for the default 13px
# circle).
func _is_wall_tile_sticky() -> bool:
	if not _tile_map or not is_on_wall():
		return false
	var wall_normal := get_wall_normal()
	if wall_normal == Vector2.ZERO:
		return false
	# The wall tile is at global_position + (-wall_normal) * sample_distance.
	var sample := global_position + (-wall_normal) * 14.0
	var local_pos := _tile_map.to_local(sample)
	var cell := _tile_map.local_to_map(local_pos)
	var tile_data := _tile_map.get_cell_tile_data(cell)
	if tile_data and tile_data.has_custom_data("sticky"):
		return bool(tile_data.get_custom_data("sticky"))
	return false


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
	var best := {"friction": 0.5, "contact_cell": Vector2i(-1, -1)}
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
	# On flat ground (floor_normal aligned with -gravity_direction),
	# the projection is zero — no slide. Friction scales the slide
	# via (1 - friction).
	#
	# Godot's documented convention is floor_normal points AWAY from
	# the surface (toward the player). So flat ground has floor_normal
	# aligned with -gravity_direction. The abs() check handles both
	# sign conventions of the normal.
	#
	# 1-frame delay (uses last frame's floor_normal) is barely
	# noticeable. A frame-perfect version would defer this until
	# after move_and_slide, but for game-jam timing it's fine.
	var floor_normal := get_floor_normal()
	if abs(floor_normal.dot(-gravity_direction)) >= 0.999:
		return  # flat ground relative to gravity, no slide needed
	var gravity := gravity_direction * gravity_strength
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
	_die_sound.play()
	modulate = DEATH_FLASH_COLOR
	await get_tree().create_timer(DEATH_FLASH_TIME).timeout
	visible = false
	await get_tree().create_timer(DEATH_HOLD_TIME).timeout
	died.emit()


# Rotates gravity 90° clockwise. Called on each ClockUI.countdown_zero
# signal. 90° CW in Godot 2D is -PI/2 radians (rotation is CCW-positive).
# Also updates up_direction so move_and_slide uses the correct "up" for
# collision resolution and slope sliding — defaults to Vector2.UP which
# only matches our setup when gravity is straight down. And tweens the
# camera rotation to the new "down" direction over
# camera_rotation_duration seconds (not instant — a quick pan reads
# better than a snap). The tween uses shortest-arc delta so each tick
# rotates exactly PI/2 regardless of the accumulated angle.
func _rotate_gravity_cw() -> void:
	gravity_direction = gravity_direction.rotated(-PI / 2.0)
	up_direction = -gravity_direction
	gravity_changed.emit(gravity_direction)
	# Camera rotation: gravity_direction.angle() - PI/2 so the camera's
	# local "up" points in the anti-gravity direction (Vector2.UP when
	# gravity is straight down). Use shortest-arc delta so each tick
	# rotates exactly PI/2 regardless of the current accumulated angle
	# -- without this, the third tick would target +PI/2 from a current
	# rotation of -PI (a +3PI/2 swing) and the tween would spin the
	# camera 270° the long way around instead of 90°. Kill any in-
	# flight tween first so a tick that fires mid-rotation starts from
	# the current value.
	var target_angle := gravity_direction.angle() - PI / 2.0
	var delta := _shortest_angle_delta(_camera.rotation, target_angle)
	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.tween_property(_camera, "rotation", _camera.rotation + delta, camera_rotation_duration)


# Returns the shortest signed angular delta from `from` to `to`,
# wrapped to [-PI, PI]. Used by _rotate_gravity_cw so the camera
# tween always takes the shortest arc -- a 90° gravity rotation
# should spin the camera 90°, not 270° the long way around when the
# target angle crosses the -PI/PI boundary.
func _shortest_angle_delta(from: float, to: float) -> float:
	return fposmod(to - from + PI, TAU) - PI
