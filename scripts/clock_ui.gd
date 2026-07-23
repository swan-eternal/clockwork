extends CanvasLayer
##
## Clockwork countdown clock — top-center Label that ticks down
## from `STARTING_SECONDS` to 0. When it hits 0, emits
## `countdown_zero` (Task 4 will connect this to the rotation system).
##

signal countdown_zero

# Starting value. Default 10s per the jam concept. Tweak per-level
# via the Inspector once we know what feels right.
@export var STARTING_SECONDS := 10.0

@onready var _label: Label = $Label
var _remaining: float

func _ready() -> void:
	# Reset the timer to starting value when the scene loads.
	_remaining = STARTING_SECONDS
	_update_label()

func _process(delta: float) -> void:
	# Cycle behavior — restart at STARTING_SECONDS after hitting zero
	# so the clock visibly ticks during testing. Task 4 will replace
	# this loop with the rotation trigger.
	if _remaining <= 0.0:
		_remaining = STARTING_SECONDS
		_update_label()
		return

	_remaining -= delta
	if _remaining <= 0.0:
		_remaining = 0.0
		_update_label()
		countdown_zero.emit()
	else:
		_update_label()

func _update_label() -> void:
	# Display as integer seconds (no decimals).
	_label.text = str(int(_remaining))