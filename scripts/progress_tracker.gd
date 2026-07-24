extends Node
##
## Tracks which levels the player has completed.
##
## Registered as an autoload (see project.godot's [autoload] section),
## so it's accessible from any script as `ProgressTracker.completed_levels`.
##
## State is in-memory only -- it resets every time the game launches.
## Persistence (ConfigFile on disk) is a separate TODO; see the README's
## 'Settings persistence' item. For a 3-level jam this is fine.
##

# Emitted when a level is marked complete. Listeners (e.g. the level
## select screen) can refresh their UI in response.
signal level_completed(level_path: String)

# Map of level_path (String) -> completed (bool). Using a Dictionary
## rather than an Array because level paths are arbitrary strings --
## the level select screen passes them in by config, not by index.
var completed_levels: Dictionary = {}

func mark_completed(level_path: String) -> void:
	# Idempotent -- calling this twice for the same level is fine.
	# Only emits the signal on the first transition to completed so
	# listeners can avoid redundant UI refreshes.
	if completed_levels.get(level_path, false):
		return
	completed_levels[level_path] = true
	level_completed.emit(level_path)

func is_completed(level_path: String) -> bool:
	return completed_levels.get(level_path, false)
