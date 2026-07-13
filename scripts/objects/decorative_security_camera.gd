class_name DecorativeSecurityCamera
extends Node2D

const HOUSING_COLOR := Color("6f7d8d")
const OFFLINE_COLOR := Color("d78a45")


func _ready() -> void:
	queue_redraw()


func get_visibility_sample_position() -> Vector2:
	return global_position


func _draw() -> void:
	# This is deliberately crossed out and has no physics/detection component.
	# It reads as facility dressing without promising a second perception system.
	draw_rect(Rect2(-17.0, -9.0, 27.0, 18.0), HOUSING_COLOR, true)
	draw_colored_polygon(
		PackedVector2Array([Vector2(10.0, -7.0), Vector2(19.0, -3.0), Vector2(19.0, 3.0), Vector2(10.0, 7.0)]),
		Color("273647")
	)
	draw_circle(Vector2(-7.0, 0.0), 4.0, Color("15202c"))
	draw_line(Vector2(-20.0, -12.0), Vector2(20.0, 12.0), OFFLINE_COLOR, 3.0, true)
