@tool
extends Node2D
##
## Marker node for rail endpoints. Used by BalloonPlatform and
## WeightPlatform so the level designer can drag the rail start
## and end in the 2D editor instead of typing numbers in the
## Inspector. Emits a signal when the user drags the marker in
## the editor, so the parent platform can react (e.g. enforce
## a vertical / horizontal / diagonal lock between the two
## markers).
##

# Emitted when the user moves this marker in the editor. The
# parent platform listens for this and may snap the other marker
# to maintain a constraint (e.g. vertical / horizontal lock).
signal position_manually_set(new_pos: Vector2)

func _ready() -> void:
	# Enable local-transform-change notifications. Without this,
	# the _notification(NOTIFICATION_LOCAL_TRANSFORM_CHANGED) below
	# never fires when the user drags the node in the editor.
	set_notify_local_transform_changes(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		# Local transform changed — emit so the parent platform
		# can react (e.g. enforce a direction lock).
		position_manually_set.emit(position)