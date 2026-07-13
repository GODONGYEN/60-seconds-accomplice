class_name ChronosCore
extends Interactable

signal stolen(actor: Node)
signal collection_progressed(normalized_progress: float)

@export_range(0.1, 5.0, 0.1) var interaction_duration_seconds: float = 1.2

@onready var collision_shape: CollisionShape2D = %CollisionShape2D

var is_stolen: bool = false
var collection_elapsed: float = 0.0
var _collection_check: Callable
var _collecting_actor: Node = null
var _pulse_time: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	queue_redraw()


func _process(delta: float) -> void:
	if is_stolen:
		return
	if _collecting_actor != null:
		advance_collection(delta)
	_pulse_time = fmod(_pulse_time + maxf(0.0, delta), TAU)
	queue_redraw()


func configure(collection_check: Callable) -> void:
	_collection_check = collection_check


func can_interact(actor: Node) -> bool:
	return (
		not is_stolen
		and _collecting_actor == null
		and actor != null
		and actor.is_in_group(&"player_actor")
		and (not _collection_check.is_valid() or bool(_collection_check.call()))
	)


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	_collecting_actor = actor
	collection_elapsed = 0.0
	if actor.has_method(&"set_gameplay_input_enabled"):
		actor.call(&"set_gameplay_input_enabled", false)
	collection_progressed.emit(0.0)
	queue_redraw()
	return true


func advance_collection(delta: float) -> void:
	if _collecting_actor == null:
		return
	if not is_instance_valid(_collecting_actor):
		_cancel_collection()
		return
	collection_elapsed = minf(
		interaction_duration_seconds,
		collection_elapsed + maxf(0.0, delta)
	)
	collection_progressed.emit(collection_elapsed / interaction_duration_seconds)
	queue_redraw()
	if collection_elapsed >= interaction_duration_seconds:
		_complete_collection()


func get_interaction_prompt(_actor: Node) -> String:
	if is_stolen:
		return "CHRONOS CORE SECURED"
	if _collecting_actor != null:
		return "SECURING CORE  %d%%" % roundi(
			100.0 * collection_elapsed / interaction_duration_seconds
		)
	return "E  SECURE CORE  %.1fs" % interaction_duration_seconds


func reset_mission() -> void:
	_cancel_collection()
	collection_elapsed = 0.0
	_apply_stolen(false)


func capture_recall_state() -> Dictionary:
	return {"is_stolen": is_stolen}


func restore_recall_state(snapshot: Dictionary) -> bool:
	_cancel_collection()
	collection_elapsed = 0.0
	_apply_stolen(bool(snapshot.get("is_stolen", false)))
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _complete_collection() -> void:
	var actor := _collecting_actor
	_collecting_actor = null
	collection_elapsed = interaction_duration_seconds
	if actor != null and is_instance_valid(actor) and actor.has_method(
		&"set_gameplay_input_enabled"
	):
		actor.call(&"set_gameplay_input_enabled", true)
	_apply_stolen(true)
	collection_progressed.emit(1.0)
	stolen.emit(actor)


func _cancel_collection() -> void:
	if _collecting_actor != null and is_instance_valid(_collecting_actor):
		if _collecting_actor.has_method(&"set_gameplay_input_enabled"):
			_collecting_actor.call(&"set_gameplay_input_enabled", true)
	_collecting_actor = null


func _apply_stolen(value: bool) -> void:
	is_stolen = value
	visible = not value
	monitorable = not value
	collision_shape.set_deferred(&"disabled", value)
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_pulse_time * 2.4) * 0.12
	draw_circle(Vector2.ZERO, 34.0 * pulse, Color(0.57, 0.3, 1.0, 0.18))
	draw_circle(Vector2.ZERO, 20.0, Color("b77aff"))
	draw_circle(Vector2.ZERO, 11.0, Color("53f4ec"))
	draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 32, Color("e9d3ff"), 3.0)
	if _collecting_actor != null:
		var progress := collection_elapsed / interaction_duration_seconds
		draw_rect(Rect2(-24.0, 38.0, 48.0, 5.0), Color("07131f"), true)
		draw_rect(Rect2(-24.0, 38.0, 48.0 * progress, 5.0), Color("53f4ec"), true)
