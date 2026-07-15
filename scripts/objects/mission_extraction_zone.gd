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
	var status_color := Color("30dde3") if is_active else Color("8390a3")
	draw_circle(Vector2.ZERO, 52.0, Color(accent, 0.16))
	draw_arc(Vector2.ZERO, 44.0, 0.0, TAU, 48, accent, 5.0)
	draw_arc(Vector2.ZERO, 34.0, -PI * 0.92, -PI * 0.08, 24, Color(accent, 0.72), 2.0)
	for direction: float in [-1.0, 1.0]:
		var side_x := 58.0 * direction
		draw_line(Vector2(side_x, -34.0), Vector2(side_x, 28.0), status_color, 4.0)
		draw_line(Vector2(side_x, -34.0), Vector2(38.0 * direction, -34.0), status_color, 4.0)
	for index: int in range(3):
		var x := -24.0 + index * 17.0
		draw_polyline(
			PackedVector2Array([
				Vector2(x, 16.0), Vector2(x + 8.0, 24.0), Vector2(x, 32.0),
			]),
			accent,
			3.0
		)
	var status := "EXTRACT READY" if is_active else "EXTRACT LOCKED"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-58.0, -57.0),
		status,
		HORIZONTAL_ALIGNMENT_CENTER,
		116.0,
		13,
		status_color
	)
