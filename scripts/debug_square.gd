@tool
extends Control
##
## Debug overlay for level design — draws a rectangle outline at
## the play area boundary. Useful for placing tiles precisely
## during L1–L3 painting. Instance scenes/debug_square.tscn into a
## level scene as a child node, then toggle "Show Square" in the
## inspector to see the boundary.
##

# Play area center. Matches RotatingLevelComponents' position in
# scenes/level_template.tscn (576, 324).
@export var square_center: Vector2 = Vector2(576, 324):
	set(value):
		square_center = value
		queue_redraw()

# Play area side length. Matches the TileMapLayer grid (608x608).
@export var square_size: float = 608.0:
	set(value):
		square_size = value
		queue_redraw()

# Outline color.
@export var line_color: Color = Color(1.0, 0.4, 0.4, 0.8):
	set(value):
		line_color = value
		queue_redraw()

# Outline width in pixels.
@export var line_width: float = 2.0:
	set(value):
		line_width = value
		queue_redraw()

# Toggle the overlay on/off. When true, the rectangle is drawn.
@export var show_square: bool = false:
	set(value):
		show_square = value
		queue_redraw()


func _draw() -> void:
	if not show_square:
		return
	var rect := Rect2(
		square_center.x - square_size * 0.5,
		square_center.y - square_size * 0.5,
		square_size,
		square_size
	)
	draw_rect(rect, line_color, false, line_width)