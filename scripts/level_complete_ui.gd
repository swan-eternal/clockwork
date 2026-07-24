extends CanvasLayer
##
## Win screen — fades in when the level is won, shows "Level
## Complete!" with a continue prompt, then emits `continue_pressed`
## when the player confirms (Space/Enter) so the level orchestrator
## can advance to the next level.
##
## Hidden by default (visible = false, modulate.a = 0). The level's
## win flow calls show_win_screen() to reveal and animate it.
##

# Texts shown in the UI. @export so per-level variants (e.g. a
## "Boss Defeated!" message) can override via the Inspector without
## touching the script.
## Title shown in the big text.
@export var title_text: String = "Level Complete!"
## Continue prompt shown below the title. Tells the player which
## input advances. Matches the `ui_accept` action (Space / Enter /
## gamepad A by default).
@export var prompt_text: String = "Press [Space] to continue"
## Fade-in duration in seconds. 0.3s feels snappy without being abrupt.
@export var fade_in_time: float = 0.3

# Emitted when the player confirms. Level orchestrator awaits this and
## advances to the next scene.
signal continue_pressed

# Cached node references -- resolved in _ready(). Using full paths
## (not relative) since the structure is fixed in level_complete_ui.tscn.
@onready var _background: ColorRect = $Background
@onready var _center: Control = $Center
@onready var _title: Label = $Center/VBox/Title
@onready var _prompt: Label = $Center/VBox/Prompt

func _ready() -> void:
	# Start hidden. modulate.a = 0 makes the fade-in work cleanly;
	# visible = false keeps the UI out of the input/layout pass
	# entirely until the win flow actually shows it.
	visible = false
	_background.modulate.a = 0.0
	_center.modulate.a = 0.0

func show_win_screen() -> void:
	# Called by the level orchestrator on win. Resolves once the player
	# has pressed the continue input (so callers can `await` this).
	#
	# Note: this function does NOT call `await` from the perspective
	# of the caller -- the caller `await`s the `continue_pressed`
	# signal directly. Keeping show_win_screen as a void function
	# matches the rest of the codebase's style.
	visible = true
	_title.text = title_text
	_prompt.text = prompt_text

	# Tween background + center in parallel so the overlay and the
	# panel fade in together rather than sequentially.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_background, "modulate:a", 1.0, fade_in_time)
	tween.tween_property(_center, "modulate:a", 1.0, fade_in_time)
	await tween.finished

	# Consume any input that was on the same frame as the win (rare,
	# but possible if the player presses Space and touches the flag
	# in the same frame). Without this, the win screen would auto-
	# advance on the very first input poll.
	await get_tree().process_frame
	while not Input.is_action_just_pressed("ui_accept"):
		await get_tree().process_frame

	continue_pressed.emit()
