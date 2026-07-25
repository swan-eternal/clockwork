extends Node
##
## Tracks the previously-active scene path. When a screen like
## Settings is opened from the pause menu, the caller sets
## previous_scene_path so the callee (Settings) can return there
## on its Back button instead of dropping the player at the main
## menu and losing their level state.
##
## Usage:
##   - Caller (e.g., pause_menu) sets this BEFORE opening Settings:
##         SceneHistory.previous_scene_path = get_tree().current_scene.scene_file_path
##         get_tree().change_scene_to_file(settings_scene)
##   - Callee (e.g., settings) reads it on Back:
##         var target := SceneHistory.previous_scene_path if not empty else back_scene
##         SceneHistory.previous_scene_path = ""  # clear so next open starts fresh
##         get_tree().change_scene_to_file(target)
##

var previous_scene_path: String = ""
