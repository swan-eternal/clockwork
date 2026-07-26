extends Node

# Global gravity singleton (autoload). Single source of truth for the
# world's current gravity direction. The Player updates this when
# gravity rotates; consumers (platforms, balloons, anything gravity-
# reactive) read `gravity_direction` or connect to `gravity_changed`.
#
# Why an autoload: every gravity-reactive node in the scene tree would
# otherwise have to find the Player and subscribe to its signal. With
# a singleton, consumers just `GravityManager.gravity_direction` —
# no path-walking, no signal routing. Decouples consumers from the
# Player entirely; future non-Player gravity sources (cutscenes, test
# scenes) just write to the singleton.

# Emitted when gravity_direction changes. Listeners should treat this
# as the new authoritative gravity state.
signal gravity_changed(new_direction: Vector2)

# Current gravity direction in world coords. Default Vector2.DOWN
# matches the Player's initial state. The setter auto-emits the signal
# so consumers don't need to remember to call emit() after assignment.
var gravity_direction: Vector2 = Vector2.DOWN:
	set(value):
		gravity_direction = value
		gravity_changed.emit(value)
