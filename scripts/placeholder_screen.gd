extends Control
##
## Generic placeholder for menu screens that aren't built yet
## (Settings, Level Select). Shows a title + Back button that returns
## to the main menu. When the real screen ships, replace this with
## a dedicated scene + script.
##

@export var screen_title: String = "Coming Soon"
@export var back_scene: String = "res://scenes/main_menu.tscn"

@onready var _title: Label = $CenterContainer/VBox/Title
@onready var _back_button: Button = $CenterContainer/VBox/BackButton

func _ready() -> void:
	# Set the title in code rather than the .tscn so a single scene
	# file can be reused across placeholders via @export override.
	_title.text = screen_title
	_back_button.pressed.connect(_on_back_pressed)

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)
