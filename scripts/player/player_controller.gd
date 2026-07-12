class_name PlayerController
extends CharacterBody2D

signal restart_requested
signal interaction_recorded(
	target_object_id: StringName,
	event_type: StringName,
	payload: Dictionary
)
signal interaction_prompt_changed(message: String)

const PLAYER_COLOR := Color("58a6ff")
const PLAYER_OUTLINE_COLOR := Color("e9f4ff")
const BODY_RADIUS := 18.0
const FACING_LENGTH := 29.0

@export_range(50.0, 800.0, 10.0) var move_speed: float = 260.0

@onready var interaction_area: Area2D = %InteractionArea

var _gameplay_input_enabled: bool = false
var _has_objective: bool = false
var _last_prompt: String = ""
var _facing_angle: float = 0.0


func _ready() -> void:
	add_to_group("timeline_actor")
	add_to_group("player_actor")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if not _gameplay_input_enabled:
		velocity = Vector2.ZERO
		_update_interaction_prompt()
		return

	var input_direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)
	velocity = input_direction * move_speed
	move_and_slide()
	_update_facing()
	_update_interaction_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_input_enabled:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart_loop"):
		restart_requested.emit()
		get_viewport().set_input_as_handled()


func initialize_at(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_has_objective = false
	_facing_angle = 0.0
	rotation = 0.0
	queue_redraw()


func set_gameplay_input_enabled(enabled: bool) -> void:
	_gameplay_input_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO


func is_gameplay_input_enabled() -> bool:
	return _gameplay_input_enabled


func grant_objective() -> void:
	_has_objective = true
	queue_redraw()


func has_objective_item() -> bool:
	return _has_objective


func get_facing_angle() -> float:
	return _facing_angle


func get_animation_state() -> StringName:
	return &"moving" if velocity.length_squared() > 1.0 else &"idle"


func get_recorded_velocity() -> Vector2:
	return velocity


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		velocity = Vector2.ZERO


func _update_facing() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() <= 1.0:
		return
	_facing_angle = to_mouse.angle()
	queue_redraw()


func _try_interact() -> void:
	var target := _find_nearest_interactable()
	if target == null:
		interaction_prompt_changed.emit("Nothing to interact with")
		return
	if not target.has_method("can_interact") or not target.has_method("interact"):
		push_warning("Interaction target does not implement the interactable contract: %s" % target.name)
		return
	if not bool(target.call("can_interact", self)):
		return
	var interaction_succeeded := bool(target.call("interact", self))
	if not interaction_succeeded:
		return
	var target_id := StringName()
	if target.has_method("get_object_id"):
		target_id = StringName(target.call("get_object_id"))
	if target_id == StringName():
		push_error("Successful interaction target has an empty stable object ID: %s" % target.name)
		return
	interaction_recorded.emit(target_id, &"interact", {})


func _find_nearest_interactable() -> Area2D:
	var nearest: Area2D = null
	var nearest_distance_squared := INF
	for candidate: Area2D in interaction_area.get_overlapping_areas():
		if not candidate.is_in_group("interactable"):
			continue
		var distance_squared := global_position.distance_squared_to(candidate.global_position)
		if distance_squared < nearest_distance_squared:
			nearest = candidate
			nearest_distance_squared = distance_squared
	return nearest


func _update_interaction_prompt() -> void:
	var target := _find_nearest_interactable()
	var prompt := ""
	if target != null:
		prompt = "E  COLLECT TIME CORE"
	if prompt == _last_prompt:
		return
	_last_prompt = prompt
	interaction_prompt_changed.emit(prompt)


func _draw() -> void:
	draw_circle(Vector2.ZERO, BODY_RADIUS + 3.0, PLAYER_OUTLINE_COLOR)
	draw_circle(Vector2.ZERO, BODY_RADIUS, PLAYER_COLOR)
	var facing_vector := Vector2.from_angle(_facing_angle) * FACING_LENGTH
	draw_line(Vector2.ZERO, facing_vector, PLAYER_OUTLINE_COLOR, 5.0, true)
	if _has_objective:
		draw_circle(Vector2(0.0, -29.0), 7.0, Color("ffcf4a"))
