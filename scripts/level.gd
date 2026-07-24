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
##   2. Show a brief "You died" overlay so death feels intentional.
##   3. After a short pause, reload the scene to reset everything.
##

# Path to the next level scene. Empty = end of the game.
# Set per-level via the Inspector on the inherited scene.
@export var next_level_path: String = ""

## How long the "You died" overlay stays on screen before the
## scene reload. Long enough to read, short enough that death
## doesn't feel like a long pause.
@export var death_overlay_duration: float = 0.5

@onready var _flag: Area2D = $RotatingLevelComponents/Flag
@onready var _clock: CanvasLayer = $ClockUI
@onready var _player: CharacterBody2D = $Player
@onready var _level_complete_ui: CanvasLayer = $LevelCompleteUI
@onready var _game_complete_ui: CanvasLayer = $GameCompleteUI
@onready var _game_over_overlay: CanvasLayer = _create_game_over_overlay()

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
	# Two paths after a win: if there's a next level, show the
	# LevelCompleteUI (which waits for Space/Enter and advances).
	# If not (L3 is the last level), show the GameCompleteUI which
	# has a Back to Main Menu button.
	if next_level_path.is_empty():
		_game_complete_ui.show_end_screen()
		return
	_level_complete_ui.show_win_screen()
	await _level_complete_ui.continue_pressed
	get_tree().change_scene_to_file(next_level_path)

func _on_player_died() -> void:
	# The player has already done the death animation (flash → hide)
	# before emitting `died`. Show a brief "You died" overlay so death
	# feels intentional rather than a glitch, then reload the scene
	# to reset the level (player position, clock, and any other
	# transient state).
	_game_over_overlay.visible = true
	await get_tree().create_timer(death_overlay_duration).timeout
	get_tree().reload_current_scene()

# Build a self-contained "You died" overlay as a CanvasLayer at runtime.
# Hidden by default; toggled visible in _on_player_died. Lives on a high
# layer so it draws above the rest of the scene (above ClockUI,
# LevelCompleteUI, GameCompleteUI, and any other layer the level uses).
func _create_game_over_overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 10  # Above other layers.
	var label := Label.new()
	label.text = "You died"
	# Red color to match the death-flash theme; large enough to read
	# at a glance during the brief overlay window.
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	label.add_theme_font_size_override("font_size", 64)
	# Full-rect anchors so the text centers on the viewport regardless
	# of resolution; alignment puts it in the middle of that rect.
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(label)
	layer.visible = false
	add_child(layer)
	return layer