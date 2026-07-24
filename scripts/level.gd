extends Node2D
##
## Level orchestrator for Clockwork — sits on the root of a level scene.
## Catches Flag.player_won and runs the win flow:
##   1. Pause the clock so the world stops rotating.
##   2. Show the LevelCompleteUI (fades in, waits for Space/Enter).
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
@onready var _level_complete_ui: CanvasLayer = $LevelCompleteUI

func _ready() -> void:
	_flag.player_won.connect(_on_player_won)
	_player.died.connect(_on_player_died)

func _on_player_won() -> void:
	# Pause the clock so rotation halts — the world freezes on the
	# moment of victory.
	_clock.pause()
	# Mark this level complete for the level select screen's progress
	# indicator. Uses this node's scene_file_path (the .tscn this
	# scene was loaded from, e.g. "res://scenes/levels/L1.tscn") as
	# the key, so the level select screen works for any number of
	# levels without hardcoding names.
	ProgressTracker.mark_completed(scene_file_path)
	# Hand off to the LevelCompleteUI. It handles the fade-in, the
	# input wait, and emits `continue_pressed` when the player
	# confirms. We just await that signal to know when to advance.
	_level_complete_ui.show_win_screen()
	await _level_complete_ui.continue_pressed

	# Advance to the next level, or end the game if no next is set.
	if next_level_path.is_empty():
		print("[level] no next level set — game over (placeholder)")
		# TODO: end-screen UI
		return
	get_tree().change_scene_to_file(next_level_path)

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
