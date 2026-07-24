extends CanvasLayer
##
## Fullscreen chromatic aberration post-process. Registered as an
## autoload so it's present in every scene (main menu, settings,
## levels, etc.) -- the autoload's CanvasLayer stays in the tree
## across `change_scene_to_file` calls.
##
## The settings menu's "Chromatic Aberration" slider drives the
## shader's `intensity` uniform in real time via set_intensity().
## Default 0.05 is subtle but visible (about 0.75px horizontal
## channel separation on a 1000px wide screen).
##

## Starting intensity. 0.05 = "on by default, small amount"
## per Jason's 2026-07-24 design call. The user can crank it
## from the settings menu (0..1 range; the slider maps to this).
@export var default_intensity: float = 0.05

@onready var _color_rect: ColorRect = $ColorRect
var _intensity: float = default_intensity

func _ready() -> void:
	# Layer 100 ensures we render above every other CanvasLayer
	# in the project (default layer is 0/1 for our UI scenes).
	# The chromatic aberration should affect the whole screen,
	# not sit behind any of the menus.
	layer = 100
	# Apply the default intensity immediately so the first rendered
	# frame already has the effect, not "no effect for 1 frame
	# then snap to 0.05".
	_color_rect.material.set_shader_parameter("intensity", _intensity)

func set_intensity(value: float) -> void:
	# Clamp to the valid range so a misconfigured caller can't
	# push the shader into a state that produces artifacts (e.g.
	# negative intensity would flip the channel direction).
	_intensity = clamp(value, 0.0, 1.0)
	_color_rect.material.set_shader_parameter("intensity", _intensity)

func get_intensity() -> float:
	return _intensity
