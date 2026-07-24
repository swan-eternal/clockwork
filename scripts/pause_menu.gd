extends CanvasLayer
##
## Pause menu for Clockwork. Toggled by ui_cancel (Escape by
## default) while a level scene is running. Uses Godot's built-in
## SceneTree.paused flag to freeze the game.
##
## IMPORTANT: this CanvasLayer has process_mode = PROCESS_MODE_ALWAYS
## (set in the .tscn). The default PAUSABLE mode would freeze this
## menu's input along with the rest of the tree, so the buttons
## would be unclickable while paused -- the whole point of the menu.
## ALWAYS lets the menu's _unhandled_input and the button clicks
## keep running even when get_tree().paused = true.
##
## Buttons:
##   - Resume: unpause and hide
##   - Restart: unpause and reload the current level
##   - Back to Main Menu: unpause and return to the main menu
##

# Where "Back to Main Menu" takes the player.
@export var main_menu_scene: String = "res://scenes/main_menu.tscn"
## Where the Settings button takes the player. Unpauses first so
## the settings scene doesn't inherit a paused state.
@export var settings_scene: String = "res://scenes/settings.tscn"
# Action that toggles pause. Defaults to ui_cancel (Escape).
@export var pause_action: String = "ui_cancel"

@onready var _resume_button: Button = $Center/VBox/ResumeButton
@onready var _restart_button: Button = $Center/VBox/RestartButton
@onready var _settings_button: Button = $Center/VBox/SettingsButton
@onready var _main_menu_button: Button = $Center/VBox/MainMenuButton

func _ready() -> void:
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
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

func _on_settings_pressed() -> void:
	# Open the settings scene. Unpause first so the settings scene
	# doesn't inherit the paused state (its own scene tree starts
	# unpaused; the settings UI uses _process for slider updates
	# and a paused tree would freeze those).
	#
	# Note: this loses the current level state. The player exits
	# to the settings scene, and clicking Back from there goes to
	# the main menu (per settings.tscn's back_scene default). A
	# future improvement would be to show settings as an overlay
	# so the level state is preserved.
	get_tree().paused = false
	get_tree().change_scene_to_file(settings_scene)

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
