extends CanvasLayer
##
## Pause menu for Clockwork. Toggled by ui_cancel (Escape by
## default) while a level scene is running. Uses Godot's built-in
## SceneTree.paused flag to freeze the game; this menu's input
## handling still runs because _input is not affected by the
## pause flag (only _process / _physics_process are).
##
## Buttons:
##   - Resume: unpause and hide
##   - Restart: unpause and reload the current level
##   - Back to Main Menu: unpause and return to the main menu
##

# Where "Back to Main Menu" takes the player.
@export var main_menu_scene: String = "res://scenes/main_menu.tscn"
# Action that toggles pause. Defaults to ui_cancel (Escape).
@export var pause_action: String = "ui_cancel"

@onready var _resume_button: Button = $Center/VBox/ResumeButton
@onready var _restart_button: Button = $Center/VBox/RestartButton
@onready var _main_menu_button: Button = $Center/VBox/MainMenuButton

func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	# Start hidden -- the menu only appears after the player
	# presses Escape (or whatever pause_action maps to).
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	# Use _unhandled_input rather than _input so UI elements (like
	# the player jump) can claim the cancel action if needed in
	# the future. The pause toggle still catches it if nothing
	# else does.
	if event.is_action_pressed(pause_action):
		if get_tree().paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _on_resume_pressed() -> void:
	_resume()

func _on_restart_pressed() -> void:
	# Unpause BEFORE reloading. The new scene tree starts
	# unpaused; if we left the old tree paused, the new scene
	# would also start paused.
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	# Same reasoning as _on_restart_pressed -- unpause first so
	# the main menu doesn't inherit a paused state.
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene)

func _pause() -> void:
	# Setting SceneTree.paused = true freezes _process and
	# _physics_process on all PROCESS_MODE_PAUSABLE nodes (which
	# is the default for any node we create). The pause menu
	# itself stays interactive because _input still fires while
	# the tree is paused, and the menu's button signals don't go
	# through the process loop.
	get_tree().paused = true
	visible = true

func _resume() -> void:
	get_tree().paused = false
	visible = false
