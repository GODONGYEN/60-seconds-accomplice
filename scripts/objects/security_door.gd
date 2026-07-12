class_name SecurityDoor
extends StaticBody2D

signal open_state_changed(is_open: bool)

const CLOSED_COLOR := Color("ef596f")
const OPEN_COLOR := Color("38e8d0")
const FRAME_COLOR := Color("c9d4e7")

@export var object_id: StringName = &"door_vault_01"

@onready var blocker: CollisionShape2D = %Blocker
@onready var safety_area: Area2D = %SafetyArea

var is_open: bool = false
var _close_pending: bool = false


func _ready() -> void:
	add_to_group("stable_object")
	add_to_group("loop_resettable")
	safety_area.body_exited.connect(_on_safety_body_exited)
	_apply_open_state(false, true)


func get_object_id() -> StringName:
	return object_id


func set_open(requested_open: bool) -> void:
	if requested_open:
		_close_pending = false
		_apply_open_state(true)
		return
	if _has_player_in_clearance():
		_close_pending = true
		return
	_close_pending = false
	_apply_open_state(false)


func reset_for_loop() -> void:
	_close_pending = false
	_apply_open_state(false, true)


func _has_player_in_clearance() -> bool:
	for body: Node2D in safety_area.get_overlapping_bodies():
		if body.is_in_group("player_actor"):
			return true
	return false


func _on_safety_body_exited(_body: Node2D) -> void:
	if not _close_pending or _has_player_in_clearance():
		return
	_close_pending = false
	_apply_open_state(false)


func _apply_open_state(value: bool, force: bool = false) -> void:
	if not force and is_open == value:
		return
	is_open = value
	blocker.set_deferred("disabled", is_open)
	queue_redraw()
	open_state_changed.emit(is_open)


func _draw() -> void:
	var panel_color := OPEN_COLOR if is_open else CLOSED_COLOR
	draw_rect(Rect2(-28.0, -82.0, 56.0, 164.0), FRAME_COLOR, true)
	if is_open:
		draw_rect(Rect2(-28.0, -82.0, 11.0, 164.0), panel_color, true)
		draw_rect(Rect2(17.0, -82.0, 11.0, 164.0), panel_color, true)
		draw_line(Vector2(-10.0, 0.0), Vector2(10.0, 0.0), panel_color, 4.0)
	else:
		draw_rect(Rect2(-22.0, -76.0, 44.0, 152.0), panel_color, true)
		draw_line(Vector2(-16.0, 0.0), Vector2(16.0, 0.0), Color.WHITE, 4.0)

