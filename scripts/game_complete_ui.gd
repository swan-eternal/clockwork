extends CanvasLayer
##
## End-game screen — shown when the player completes the last level
## (L3 in the current build). Distinct from LevelCompleteUI because
## there's no "next level" to continue to; instead the player gets
## a Back to Main Menu button.
##

## Where the Back button takes the player.
@export var back_scene: String = "res://scenes/main_menu.tscn"

@onready var _background: ColorRect = $Background
@onready var _center: Control = $Center
@onready var _back_button: Button = $Center/VBox/BackButton

func _ready() -> void:
	# Start hidden -- modulate 0 until the level orchestrator
	# shows it.
	visible = false
	_background.modulate.a = 0.0
	_center.modulate.a = 0.0
	_back_button.pressed.connect(_on_back_pressed)

func show_end_screen() -> void:
	# Called by the level orchestrator when the player has won the
	# last level. Fades in over 0.3s (matching LevelCompleteUI's
	# fade so the two screens feel like the same family of UI).
	visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_background, "modulate:a", 1.0, 0.3)
	tween.tween_property(_center, "modulate:a", 1.0, 0.3)
	await tween.finished

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(back_scene)
