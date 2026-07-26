extends Node2D
##
## Tutorial label — text in the level that stays upright in the
## camera view as gravity rotates around the world.
##
## Drop into a level scene (any child of Main), position it where the
## tutorial message should appear in the level, and set the `text`
## property in the inspector. The label auto-rotates on every gravity
## tick so the text always reads upright, even when the camera has
## rotated 90° / 180° / 270° to compensate for the rotated "down".
##
## Implementation note: this used to extend Label2D, but that class
## isn't registered in the target Godot build — the parser reported
## "Could not find base class 'Label2D'" on load. Falling back to a
## custom Node2D that draws text directly via Font.draw_string() and
## Font.draw_string_outline() inside _draw(). Same gravity-tracking
## behavior, same rotation math.
##
## Earlier versions of this script used `@tool` so the 2D editor would
## preview the text live, but @tool + an autoload without `class_name`
## triggers a static-analysis gap (`Invalid access to property or key`)
## when the script reaches into the autoload at editor time. The label
## now runs at runtime only — the trade-off is no live editor preview
## (you'll see the text when you Play), but autoload access works
## cleanly in the normal runtime path.
##

# ---- Inspector-tunable properties ----
# Each visual property setter calls queue_redraw() so changes show up
# at runtime when the scene updates.

## The tutorial message to display. Edited directly in the inspector.
@export var text: String = "Tutorial text — edit me":
	set(value):
		if text == value:
			return
		text = value
		queue_redraw()

## Font size in pixels at unit scale. Final render height in world
## units is `font_size * pixel_size`. 24 reads at near-tile-height
## when paired with the default pixel_size = 1.0 in 32px-tile levels.
@export var font_size: int = 24:
	set(value):
		if font_size == value:
			return
		font_size = value
		queue_redraw()

## Outline thickness (px) drawn behind the text. 0 = no outline.
## Useful when the text needs to pop against busy tile backgrounds.
@export var outline_size: int = 4:
	set(value):
		if outline_size == value:
			return
		outline_size = value
		queue_redraw()

## Scale multiplier applied to the node. 1.0 = font_size world-px
## tall. 0.5 = half that. Combined with font_size, controls how big
## the text appears in the level.
@export var pixel_size: float = 1.0:
	set(value):
		if pixel_size == value:
			return
		pixel_size = value
		# Apply directly to the node's transform. Position stays in
		# world coords (scale doesn't move the origin); rotation is
		# applied independently; only the rendered text scales.
		scale = Vector2(value, value)
		queue_redraw()

## Text fill color. Default white reads cleanly on dark backgrounds.
@export var font_color: Color = Color.WHITE:
	set(value):
		if font_color == value:
			return
		font_color = value
		queue_redraw()

## Outline color. Default black for max contrast against white text.
@export var outline_color: Color = Color.BLACK:
	set(value):
		if outline_color == value:
			return
		outline_color = value
		queue_redraw()

# ---- Internal state ----

# Resolved font. Filled from ThemeDB.fallback_font on _ready() — the
# engine's built-in sans, so text always renders even if the user
# hasn't attached a font resource to the node.
var _font: Font = null


# ---- Lifecycle ----

func _ready() -> void:
	# Resolve once, not at every draw. ThemeDB lookup cost is small
	# but unnecessary per-frame when the answer is stable.
	_font = ThemeDB.fallback_font
	# Apply initial state so the label is correctly oriented on the
	# very first rendered frame, before any countdown tick fires.
	scale = Vector2(pixel_size, pixel_size)
	_apply_rotation_from_gravity()
	# Subscribe to every subsequent rotation. The signal carries the
	# new direction but we read from GravityManager anyway, so the
	# argument is unused. The default parameter lets us reuse this
	# function for the initial sync above (called with no arguments).
	# String-based connect is used here so GDScript's static analyzer
	# doesn't try to look up signal metadata on the autoload's Node
	# type at parse time — same goes for the get() below.
	GravityManager.connect("gravity_changed", _apply_rotation_from_gravity)


# ---- Gravity tracking ----

# Updates the label's rotation so it stays upright in the camera view.
# Called once on _ready (initial sync) AND on every
# GravityManager.gravity_changed (runtime tick updates). The argument
# is ignored — we read directly from GravityManager.
func _apply_rotation_from_gravity(_new_direction: Vector2 = Vector2.ZERO) -> void:
	# Player._rotate_gravity_cw tweens the camera to:
	#   target = gravity_direction.angle() - PI / 2.0
	# We mirror that exactly. Because the camera is a child of Player
	# (added via add_child in Player._create_camera) and Player
	# itself doesn't rotate, camera.global_rotation equals its local
	# rotation, which equals gravity_direction.angle() - PI/2.
	#
	# This Node2D in this project is a child of Main (no rotation on
	# the chain above it), so its global_rotation == rotation. For
	# the label to render upright in the rotated camera view, the
	# rendered rotation must be 0:
	#   rendered = label.global_rotation - camera.global_rotation
	#             = (gravity.angle() - PI/2) - (gravity.angle() - PI/2)
	#             = 0   ✓
	#
	# Keeping these two formulas identical is the entire trick. If
	# Player._rotate_gravity_cw's camera formula ever changes, update
	# this line to match — otherwise the label drifts out of alignment
	# with the camera by whatever difference was introduced.
	#
	# Dynamic .get() access is used here for the same reason as
	# connect() above — bypasses static-analysis warnings when this
	# script runs without `class_name` on the autoload.
	var gravity_dir: Vector2 = GravityManager.get("gravity_direction")
	rotation = gravity_dir.angle() - PI / 2.0
	# Transform changes alone might redraw, but queue_redraw() is
	# explicit so behavior is consistent across both edit-preview
	# and runtime paths.
	queue_redraw()


# ---- Rendering ----

func _draw() -> void:
	# Skip the work if there's nothing to render — empty text or
	# missing font both fall through silently.
	if _font == null or text.is_empty():
		return
	# Canvas item handle (RID) for all draw calls in this frame.
	var canvas := get_canvas_item()
	# Text is anchored at the label's local origin (0, 0). The
	# node's position/rotation/scale transform applies on top.
	var pos := Vector2.ZERO
	# Outline pass first (drawn behind), then fill on top. Both
	# calls use the same scale/position; outline just renders thicker
	# (size = outline_size) and in outline_color, then the fill on
	# top hides the outline's interior.
	#
	# draw_string_outline signature (Godot 4.7):
	#   (canvas_item, pos, text, alignment, width, font_size,
	#    size, modulate, ...)
	# `size` is the outline thickness, not the font size.
	if outline_size > 0:
		_font.draw_string_outline(canvas, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color)
	_font.draw_string(canvas, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, font_color)
