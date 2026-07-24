extends Node2D
##
## Level orchestrator for Clockwork — sits on the root of a level scene.
## Catches Flag.player_won and runs the win flow:
##   1. Pause the clock so the world stops rotating.
##   2. Wait for the player to press Space/Enter to continue.
##   3. Transition to the next level (or end the game if no next).
##
## Catches Player.died and runs the death flow:
##   1. The player has already done the death animation (flash → hide).
##   2. Reload the scene to reset everything to its starting state.
##

# Path to the next level scene. Empty = end of the game.
# Set per-level via the Inspector on the inherited scene.
@export var next_level_path: String = ""

@onready var _flag: Area2D = $RotatingLevelComponents/Flag
@onready var _clock: CanvasLayer = $ClockUI
@onready var _player: CharacterBody2D = $Player

func _ready() -> void:
	_flag.player_won.connect(_on_player_won)
	_player.died.connect(_on_player_died)

func _on_player_won() -> void:
	# Pause the clock so rotation halts — the world freezes on the
	# moment of victory. LevelCompleteUI will fade in here once we
	# have that scene; for now we just log.
	_clock.pause()
	print("[level] player won — clock paused, waiting for input")

	# Wait for the player to acknowledge before advancing.
	# ui_accept is Space/Enter by default; works on gamepads too.
	await _wait_for_confirm()

	# Advance to the next level, or end the game if no next is set.
	if next_level_path.is_empty():
		print("[level] no next level set — game over (placeholder)")
		# TODO: end-screen UI
		return
	get_tree().change_scene_to_file(next_level_path)

func _wait_for_confirm() -> void:
	# Wait for a fresh ui_accept press to advance. Leading await
	# consumes any input that was processed on the same frame as the
	# win (rare but possible — pressing Space AND touching the flag
	# in the same frame would otherwise auto-advance immediately).
	await get_tree().process_frame
	while not Input.is_action_just_pressed("ui_accept"):
		await get_tree().process_frame

func _on_player_died() -> void:
	# The player has already done the death animation (flash → hide)
	# before emitting `died`. Reload the scene to reset the level:
	# player position, clock, and any other transient state.
	#
	# reload_current_scene() is a full re-instantiation, which is the
	# simplest reset for a jam. A softer reset (manually re-positioning
	# the player + resetting the clock) would be cheaper but couples
	# this orchestrator to all the level's per-node state.
	get_tree().reload_current_scene()
