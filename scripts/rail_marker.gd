@tool
extends Node2D
##
## Marker node for rail endpoints. Used by BalloonPlatform and
## WeightPlatform so the level designer can drag the rail start
## and end in the 2D editor instead of typing numbers in the
## Inspector. Emits a signal when the marker moves in the editor,
## so the parent platform can react (e.g. enforce a vertical /
## horizontal / diagonal lock between the two markers).
##

# Emitted when this marker is moved in the editor. The parent
# platform listens for this and may snap the other marker to
# maintain a constraint (e.g. vertical / horizontal lock).
signal position_manually_set(new_pos: Vector2)

# Cached position for change detection. The @tool _process polls
# the editor every frame; if the position differs from the cached
# value, the signal is emitted. At runtime _process is short-circuited
# by the Engine.is_editor_hint() check, so there's no per-frame cost
# outside the editor.
var _last_pos: Vector2 = Vector2.ZERO
var _last_pos_initialized: bool = false


func _process(_delta: float) -> void:
	# Only poll in the editor. At runtime the markers are static
	# (set once from the .tscn at scene load), so there's no point
	# checking for changes.
	if not Engine.is_editor_hint():
		return
	# First frame after the scene loads in the editor: record the
	# marker's initial position without emitting. The position is
	# being populated from the .tscn, not from a user drag, so this
	# is a "set up" frame, not a "user moved" frame.
	if not _last_pos_initialized:
		_last_pos = position
		_last_pos_initialized = true
		return
	# Position changed since the previous frame — the user dragged
	# the marker in the editor. Emit so the parent can react (snap
	# the other marker to maintain a direction lock).
	if position != _last_pos:
		_last_pos = position
		position_manually_set.emit(position)