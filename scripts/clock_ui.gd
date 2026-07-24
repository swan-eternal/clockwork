extends CanvasLayer
##
## Clockwork countdown clock — top-center Label that ticks down
## from `STARTING_SECONDS` to 0. When it hits 0, emits
## `countdown_zero` (connected to RotatingLevelComponents for rotation).
##
## Also pauses itself while the level is rotating (so the player
## doesn't lose time during the rotation animation) and once the
## level has been won (so the clock doesn't tick during the win
## flow).
##

signal countdown_zero

# Starting value. Default 10s per the jam concept. Tweak per-level
# via the Inspector once we know what feels right.
@export var STARTING_SECONDS := 10.0

# When true, the clock freezes in place. Set during the win flow
# and during level rotation. Use pause()/won() or assign directly
# (`clock.paused = true`).
@export var paused: bool = false

# True once the level has been won (player touched the flag). Once
# set, the clock stays paused permanently for this level. The
# rotation completion handler checks this so it doesn't un-pause
# the clock if the player won during a rotation animation.
var _won: bool = false

@onready var _label: Label = $Label
var _remaining: float

func _ready() -> void:
	# Reset the timer to starting value when the scene loads.
	_remaining = STARTING_SECONDS
	_update_label()
	# Pause the countdown while the world is rotating, so the player
	# doesn't lose time during the rotation animation. The rotation
	# wrapper is a sibling of this node under Main, so look it up
	# via the parent.
	var rotating := get_parent().get_node_or_null("RotatingLevelComponents")
	if rotating:
		if rotating.has_signal("rotation_started"):
			rotating.rotation_started.connect(_on_rotation_started)
		if rotating.has_signal("rotation_completed"):
			rotating.rotation_completed.connect(_on_rotation_completed)

func _process(delta: float) -> void:
	# Frozen during win flow (and any future pause states). Rotation
	# stops with us because RotatingLevelComponents only rotates on
	# countdown_zero, which won't fire while we're frozen.
	if paused:
		return

	# Cycle behavior — restart at STARTING_SECONDS after hitting zero
	# so the clock visibly ticks during testing.
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

func pause() -> void:
	paused = true

func resume() -> void:
	paused = false

# Marks the level as won — pauses the clock and sets the `_won` flag
# so the rotation completion handler doesn't accidentally un-pause
# the clock if the player won during a rotation animation. Use this
# instead of pause() from the level's win flow.
func won() -> void:
	paused = true
	_won = true

func _on_rotation_started() -> void:
	paused = true

func _on_rotation_completed() -> void:
	# Don't un-pause if the level was won during the rotation — the
	# clock should stay paused for the rest of the win flow.
	if _won:
		return
	paused = false