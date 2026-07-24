extends Control
##
## Level select screen for Clockwork. Lists L1/L2/L3 as buttons;
## each loads the corresponding scene. Completion state comes from
## the ProgressTracker autoload (in-memory; resets per game launch).
##
## Refreshes its UI on `ProgressTracker.level_completed` so a level
## that gets completed in another scene (e.g. while playing) shows
## the updated state next time the player returns here.
##
## Note: the level select is reachable from main menu's "Level
## Select" button. There is no "return to level select after a
## level" flow -- the win UI only advances to the next level, and
## death reloads the current level. To replay / jump levels, the
## player uses this screen.
##

# Scene paths for the three level buttons. @export so the same
## script can be reused for builds with more (or fewer) levels.
## Default to the canonical L1/L2/L3 paths in the project.
@export var l1_path: String = "res://scenes/levels/L1.tscn"
@export var l2_path: String = "res://scenes/levels/L2.tscn"
@export var l3_path: String = "res://scenes/levels/L3.tscn"
## Where the Back button takes the player.
@export var back_scene: String = "res://scenes/main_menu.tscn"
## Suffix appended to a level button's text when that level has been
## completed. Empty = no visual completion indicator.
@export var completed_suffix: String = " (Complete)"

@onready var _l1_button: Button = $CenterContainer/VBox/L1Button
@onready var _l2_button: Button = $CenterContainer/VBox/L2Button
@onready var _l3_button: Button = $CenterContainer/VBox/L3Button
@onready var _back_button: Button = $CenterContainer/VBox/BackButton

func _ready() -> void:
	_l1_button.pressed.connect(_on_l1_pressed)
	_l2_button.pressed.connect(_on_l2_pressed)
	_l3_button.pressed.connect(_on_l3_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	# Refresh button labels to reflect current completion state.
	_refresh_labels()
	# Subscribe to future completion events so labels stay in sync
	# even if the player is on this screen when a level is marked
	# done (rare, but possible if the ProgressTracker autoload fires
	# while this screen is visible).
	ProgressTracker.level_completed.connect(_refresh_labels)

func _on_l1_pressed() -> void:
	get_tree().change_scene_to_file(l1_path)

func _on_l2_pressed() -> void:
	get_tree().change_scene_to_file(l2_path)

func _on_l3_pressed() -> void:
	get_tree().change_scene_to_file(l3_path)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)

func _refresh_labels() -> void:
	# Update each button's text to reflect whether the level is
	# completed. (Future: also adjust the button's visual state --
	# e.g. dimmed for locked levels, but for the jam all 3 are
	# always unlocked.)
	_l1_button.text = "Level 1" + _suffix_for(l1_path)
	_l2_button.text = "Level 2" + _suffix_for(l2_path)
	_l3_button.text = "Level 3" + _suffix_for(l3_path)

func _suffix_for(level_path: String) -> String:
	return completed_suffix if ProgressTracker.is_completed(level_path) else ""
