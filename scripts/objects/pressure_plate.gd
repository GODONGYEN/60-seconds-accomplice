class_name PressurePlate
extends Area2D

signal active_changed(is_active: bool)

const INACTIVE_COLOR := Color("715c2f")
const ACTIVE_COLOR := Color("38e8a0")
const OUTLINE_COLOR := Color("ffd76a")

@export var object_id: StringName = &"plate_entry_01"

var is_active: bool = false
var _occupying_actor_ids: Dictionary[int, bool] = {}


func _ready() -> void:
	add_to_group("stable_object")
	add_to_group("loop_resettable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func get_object_id() -> StringName:
	return object_id


func reset_for_loop() -> void:
	_occupying_actor_ids.clear()
	_set_active(false)


func get_occupant_count() -> int:
	return _occupying_actor_ids.size()


func _on_body_entered(body: Node2D) -> void:
	if not _is_timeline_actor(body):
		return
	_occupying_actor_ids[body.get_instance_id()] = true
	_set_active(not _occupying_actor_ids.is_empty())


func _on_body_exited(body: Node2D) -> void:
	if not _is_timeline_actor(body):
		return
	_occupying_actor_ids.erase(body.get_instance_id())
	_set_active(not _occupying_actor_ids.is_empty())


func _is_timeline_actor(body: Node) -> bool:
	return body.is_in_group("player_actor") or body.is_in_group("ghost_actor")


func _set_active(value: bool) -> void:
	if is_active == value:
		return
	is_active = value
	queue_redraw()
	active_changed.emit(is_active)


func _draw() -> void:
	var fill_color := ACTIVE_COLOR if is_active else INACTIVE_COLOR
	draw_rect(Rect2(-52.0, -30.0, 104.0, 60.0), fill_color, true)
	draw_rect(Rect2(-52.0, -30.0, 104.0, 60.0), OUTLINE_COLOR, false, 4.0)
	draw_circle(Vector2.ZERO, 9.0, Color.WHITE if is_active else OUTLINE_COLOR)

