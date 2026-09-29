class_name LevelBar
extends Control
## A thin glowing bar: how far into the current level a rider is.

var ratio := 0.0:
	set(v):
		ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
var color := UiStyle.ACCENT


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 12)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(color, 0.15))
	if ratio > 0.0:
		var fill := Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y))
		draw_rect(fill.grow(2.0), Color(color, 0.25))
		draw_rect(fill, color)
	draw_rect(r, Color(color, 0.5), false, 1.0)
