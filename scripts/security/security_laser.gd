class_name SecurityLaser
extends Area2D

signal tripped(actor: Node, zone_id: StringName)
signal active_changed(is_active: bool)

@export var object_id: StringName = &"laser_vault_corridor_01"
@export var zone_id: StringName = &"vault_wing"
@export var starts_active: bool = true

@onready var trigger_shape: CollisionShape2D = %TriggerShape

var is_active: bool = true


func _ready() -> void:
	add_to_group(&"stable_object")
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	body_entered.connect(_on_body_entered)
	set_active(starts_active, true)


func get_object_id() -> StringName:
	return object_id


func set_active(value: bool, force: bool = false) -> void:
	if not force and is_active == value:
		return
	is_active = value
	monitoring = is_active
	trigger_shape.set_deferred(&"disabled", not is_active)
	queue_redraw()
	active_changed.emit(is_active)


func reset_mission() -> void:
	set_active(starts_active, true)


func capture_recall_state() -> Dictionary:
	return {"is_active": is_active}


func restore_recall_state(snapshot: Dictionary) -> bool:
	set_active(bool(snapshot.get("is_active", starts_active)), true)
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return
	# Echoes are temporal projections: cameras and Guards can see them, but a
	# projection does not conduct a physical laser beam or end playback.
	if body.is_in_group(&"ghost_actor"):
		return
	if body.is_in_group(&"player_actor"):
		tripped.emit(body, zone_id)


func _draw() -> void:
	var color := Color("ff344f") if is_active else Color("4a736f")
	draw_rect(Rect2(-14.0, -52.0, 28.0, 12.0), Color("26364a"), true)
	draw_rect(Rect2(-14.0, 40.0, 28.0, 12.0), Color("26364a"), true)
	if is_active:
		for x: float in [-7.0, 0.0, 7.0]:
			draw_line(Vector2(x, -40.0), Vector2(x, 40.0), Color(color, 0.86), 3.0)
	else:
		draw_line(Vector2(-8.0, 0.0), Vector2(8.0, 0.0), color, 3.0)
