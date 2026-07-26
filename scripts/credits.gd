extends Control
##
## Credits screen for Clockwork. Plain text version for now — Jason
## can fill in actual credits (engine, music, asset sources) once
## those are finalized. Reachable from the main menu and from the
## game-complete screen.
##

# Scene to return to when the Back button is pressed. @export so
# callers (main menu, game-complete) can point a single instance at
# different scenes if needed.
@export var back_scene: String = "res://scenes/main_menu.tscn"

@onready var _back_button: Button = $CenterContainer/VBox/BackButton

func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)
