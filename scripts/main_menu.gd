extends Control
##
## Main menu for Clockwork. Three buttons:
##   - Start: jump to the first level (currently main.tscn as a
##     placeholder; switch to scenes/levels/L1.tscn when it exists).
##   - Settings: jump to settings.tscn (placeholder).
##   - Level Select: jump to level_select.tscn (placeholder).
##

# Scene paths for navigation. The three are @export so they can be
# overridden in the inspector if a level needs a non-default start
# (e.g., a debug build that skips straight to L3).
@export var start_scene: String = "res://scenes/main.tscn"
@export var settings_scene: String = "res://scenes/settings.tscn"
@export var level_select_scene: String = "res://scenes/level_select.tscn"
@export var credits_scene: String = "res://scenes/credits.tscn"

@onready var _start_button: Button = $CenterContainer/VBox/StartButton
@onready var _settings_button: Button = $CenterContainer/VBox/SettingsButton
@onready var _level_select_button: Button = $CenterContainer/VBox/LevelSelectButton
@onready var _credits_button: Button = $CenterContainer/VBox/CreditsButton

func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_level_select_button.pressed.connect(_on_level_select_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file(start_scene)

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(settings_scene)

func _on_level_select_pressed() -> void:
	get_tree().change_scene_to_file(level_select_scene)

func _on_credits_pressed() -> void:
	get_tree().change_scene_to_file(credits_scene)
