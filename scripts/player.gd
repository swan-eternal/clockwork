extends CharacterBody2D
##
## Clockwork player — a small blob that hops between platforms.
##
## Visual is a colored box for now (Polygon2D child);
## will be replaced with an AnimatedSprite2D when Jason's sprite art lands.
##

# Movement tuning — tweak together once level layouts exist.
const RUN_SPEED := 200.0       # Horizontal speed (px/s) while moving
const JUMP_VELOCITY := -400.0  # Upward impulse on jump (negative = up)
const GRAVITY := 980.0         # Downward acceleration (px/s²)

func _ready() -> void:
	# Tag the player so damage / pickup / win-zone checks can find us
	# without hardcoded path lookups. Same convention as the raccoon
	# Metroidvania project — write the is_in_group check AND the
	# add_to_group call in the same commit, never split them up.
	add_to_group("player")

func _physics_process(delta: float) -> void:
	# Horizontal input from left/right arrows or A/D.
	# Input.get_axis returns -1 / 0 / +1 from two opposing actions.
	var input_dir := Input.get_axis("ui_left", "ui_right")
	velocity.x = input_dir * RUN_SPEED

	# Jump: only if standing on something. is_on_floor() reads the
	# body's collision state from the last move_and_slide call.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Apply gravity when airborne. This is "gravity toward current down" —
	# for now that's straight down (positive y). When the rotation system
	# (Task 4) lands, this will multiply by the current gravity vector
	# instead, so the blob falls toward whichever direction is "down".
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# move_and_slide resolves collisions against walls / platforms using
	# this body's CollisionShape2D. Must be the LAST line of _physics_process
	# — anything after it reads the post-collision velocity.
	move_and_slide()
