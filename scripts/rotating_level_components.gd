extends Node2D
##
## RotatingLevelComponents wrapper for Clockwork — rotates 90°
## every time ClockUI emits countdown_zero. Everything that should
## be part of the rotating level (walls, TileMapLayer, flag, spikes,
## platforms, decorations) goes as a CHILD of this node, so it spins
## together. Player, ClockUI, and (eventual) Camera2D stay siblings
## at the root so they don't rotate.
##

# Angular speed for the level rotation, in degrees per second.
# 180 = a snappy half-second 90° turn. Lower = more dramatic,
# higher = snappier. Tune in the inspector per level.
@export var rotation_speed: float = 180.0

func _ready() -> void:
	# Wire to the ClockUI's countdown_zero signal. ClockUI is a sibling
	# of RotatingLevelComponents under Main, so we go up one level and over.
	var clock := get_parent().get_node_or_null("ClockUI")
	if clock and clock.has_signal("countdown_zero"):
		clock.countdown_zero.connect(_on_countdown_zero)

func _on_countdown_zero() -> void:
	_rotate_one_step(PI / 2.0)

func _rotate_one_step(angle: float) -> void:
	# Rotate by `angle` radians over (angle / speed) seconds.
	# Using a Tween keeps it dead-simple; if a second tick fires while
	# the first is still mid-tween, the new tween takes over from the
	# current rotation.
	var safe_speed := maxf(rotation_speed, 1.0)  # Avoid div-by-zero on bad inputs
	var target := rotation + angle
	var duration := angle / deg_to_rad(safe_speed)
	var tween := create_tween()
	tween.tween_property(self, "rotation", target, duration)
