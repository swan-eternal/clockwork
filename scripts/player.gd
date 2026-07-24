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

# Reference to the TileMapLayer for per-tile friction lookup.
# RotatingLevelComponents is a sibling of Player under Main, so
# "../RotatingLevelComponents/TileMapLayer" is the relative path.
@onready var _tile_map: TileMapLayer = $"../RotatingLevelComponents/TileMapLayer"

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
	# (no slip) when there's no tile data or no friction set.
	var friction := _get_current_friction()

	# Apply horizontal velocity. With no input, decelerate to a stop;
	# friction scales the deceleration.
	if input_dir != 0:
		velocity.x = input_dir * RUN_SPEED
	else:
		var decel := GROUND_DECEL * friction
		velocity.x = move_toward(velocity.x, 0, decel * delta)

	# Jump: only if standing on something. is_on_floor() reads the
	# body's collision state from the last move_and_slide call.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Vertical physics: gravity when airborne, slope slide when grounded.
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		# On a slope, project gravity onto the slope plane and apply as
		# acceleration. The player slides down slopes instead of sticking.
		# Friction scales the slide: ice (0) = full slide, dirt (1) = none.
		_apply_slope_slide(delta, friction)

	# move_and_slide resolves collisions against walls / platforms using
	# this body's CollisionShape2D. Must be the LAST line of _physics_process
	# — anything after it reads the post-collision velocity.
	move_and_slide()

func _get_current_friction() -> float:
	# Read the tile under the player. Returns 1.0 (no slip) as a safe
	# default when there's no tile, no tile data, or no friction set.
	# to_local + local_to_map handle the rotating world's transform —
	# the query stays in TileMapLayer's local space regardless of the
	# world's current rotation.
	if not _tile_map:
		return 1.0
	var local_pos := _tile_map.to_local(global_position)
	var cell := _tile_map.local_to_map(local_pos)
	var tile_data := _tile_map.get_cell_tile_data(cell)
	if tile_data and tile_data.has_custom_data("friction"):
		return tile_data.get_custom_data("friction")
	return 1.0

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
