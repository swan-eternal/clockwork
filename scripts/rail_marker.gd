@tool
extends Node2D
##
## Marker node for rail endpoints. Used by BalloonPlatform and
## WeightPlatform so the level designer can drag the rail start
## and end in the 2D editor instead of typing numbers in the
## Inspector.
##

# Emitted when this marker is moved in the editor. (Currently unused
# — the constraint feature was rolled back — but kept here in case
# we want it again later.)
signal position_manually_set(new_pos: Vector2)


# Draw a small circle in the editor so the marker is visually
# distinct and easy to find in the Scene tree. The circle is
# centered on the marker's local origin. Drawn only in the editor
# (Engine.is_editor_hint() check) so it doesn't show at runtime.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	draw_circle(Vector2.ZERO, 6.0, Color(0.3, 0.6, 1.0, 0.8))
	draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 16, Color(0.1, 0.4, 0.9, 1.0), 1.0)