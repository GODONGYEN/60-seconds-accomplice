class_name ExitZone
extends Area2D

signal exit_requested(actor: Node)
signal feedback_requested(message: String)

const INACTIVE_COLOR := Color("46546a")
const ACTIVE_COLOR := Color("47e1a8")

@export var object_id: StringName = &"exit_zone_01"

var is_objective_available: bool = false


func _ready() -> void:
	add_to_group("stable_object")
	add_to_group("loop_resettable")
	body_entered.connect(_on_body_entered)
	queue_redraw()


func get_object_id() -> StringName:
	return object_id


func set_objective_available(value: bool) -> void:
	is_objective_available = value
	queue_redraw()


func reset_for_loop() -> void:
	is_objective_available = false
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player_actor"):
		return
	if body.has_method("has_objective_item") and bool(body.call("has_objective_item")):
		exit_requested.emit(body)
		return
	feedback_requested.emit("COLLECT THE TIME CORE BEHIND THE DOOR FIRST")


func _draw() -> void:
	var color := ACTIVE_COLOR if is_objective_available else INACTIVE_COLOR
	draw_circle(Vector2.ZERO, 44.0, Color(color, 0.18))
	draw_arc(Vector2.ZERO, 39.0, 0.0, TAU, 48, color, 6.0, true)
	draw_line(Vector2(-14.0, 0.0), Vector2(14.0, 0.0), color, 5.0, true)
	draw_line(Vector2(7.0, -8.0), Vector2(15.0, 0.0), color, 5.0, true)
	draw_line(Vector2(7.0, 8.0), Vector2(15.0, 0.0), color, 5.0, true)
