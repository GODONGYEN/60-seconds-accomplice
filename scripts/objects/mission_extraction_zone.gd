class_name MissionExtractionZone
extends Area2D

signal extraction_requested(actor: Node)
signal extraction_denied(message: String)

@export var object_id: StringName = &"extraction_yard_01"

var is_active: bool = false


func _ready() -> void:
	add_to_group(&"stable_object")
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	body_entered.connect(_on_body_entered)
	queue_redraw()


func get_object_id() -> StringName:
	return object_id


func set_active(value: bool) -> void:
	is_active = value
	queue_redraw()


func reset_mission() -> void:
	set_active(false)


func capture_recall_state() -> Dictionary:
	return {"is_active": is_active}


func restore_recall_state(snapshot: Dictionary) -> bool:
	set_active(bool(snapshot.get("is_active", false)))
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player_actor"):
		return
	if not is_active:
		extraction_denied.emit("STEAL THE CHRONOS CORE BEFORE EXTRACTION")
		return
	extraction_requested.emit(body)


func _draw() -> void:
	var accent := Color("47e1a8") if is_active else Color("526078")
	draw_circle(Vector2.ZERO, 48.0, Color(accent, 0.18))
	draw_arc(Vector2.ZERO, 42.0, 0.0, TAU, 48, accent, 5.0)
	draw_string(ThemeDB.fallback_font, Vector2(-32.0, 5.0), "EXTRACT", HORIZONTAL_ALIGNMENT_CENTER, 64.0)
