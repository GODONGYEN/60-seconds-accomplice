class_name PlayerController
extends CharacterBody2D

const DETECTION_ID: StringName = &"player_live"
const DETECTION_PRIORITY: int = 0
const FACILITY_CAMERA_SAFE_TOP_OFFSET := Vector2(0.0, -28.0)

signal restart_requested
signal chrono_recall_requested
signal map_requested
signal interaction_recorded(
	target_object_id: StringName,
	event_type: StringName,
	payload: Dictionary
)
signal interaction_prompt_changed(message: String)

@export_range(50.0, 800.0, 10.0) var move_speed: float = 260.0
@export var heist_controls_enabled: bool = false
@export var restart_loop_enabled: bool = true

@onready var interaction_area: Area2D = %InteractionArea
@onready var visual: PlayerVisual = %VisualRoot
@onready var visibility_probe: PlayerVisibilityProbe = %PlayerVision
@onready var vision_light: PointLight2D = %VisionLight
@onready var player_camera: Camera2D = %PlayerCamera

var _gameplay_input_enabled: bool = false
var _has_objective: bool = false
var _last_prompt: String = ""
var _facing_angle: float = 0.0
var _facility_view_configured: bool = false


func _ready() -> void:
	add_to_group("timeline_actor")
	add_to_group("player_actor")
	add_to_group("detectable_actor")
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	visual.reset_visual(Vector2.DOWN)


func _physics_process(_delta: float) -> void:
	if not _gameplay_input_enabled:
		velocity = Vector2.ZERO
		visual.update_motion(Vector2.from_angle(_facing_angle), velocity, &"idle")
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
	visual.update_motion(Vector2.from_angle(_facing_angle), velocity)
	_update_interaction_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if not _gameplay_input_enabled:
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("interact"):
		_try_interact()
		get_viewport().set_input_as_handled()
	elif heist_controls_enabled and event.is_action_pressed("chrono_recall"):
		chrono_recall_requested.emit()
		get_viewport().set_input_as_handled()
	elif heist_controls_enabled and event.is_action_pressed("open_map"):
		map_requested.emit()
		get_viewport().set_input_as_handled()
	elif restart_loop_enabled and event.is_action_pressed("restart_loop"):
		restart_requested.emit()
		get_viewport().set_input_as_handled()


func initialize_at(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	_has_objective = false
	_facing_angle = Vector2.DOWN.angle()
	rotation = 0.0
	visual.reset_visual(Vector2.DOWN)


func set_gameplay_input_enabled(enabled: bool) -> void:
	_gameplay_input_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
		visual.update_motion(Vector2.from_angle(_facing_angle), velocity, &"idle")


func configure_heist_controls(enabled: bool) -> void:
	heist_controls_enabled = enabled
	restart_loop_enabled = not enabled


func is_gameplay_input_enabled() -> bool:
	return _gameplay_input_enabled


func grant_objective() -> void:
	_has_objective = true
	visual.set_objective_visible(true)


func has_objective_item() -> bool:
	return _has_objective


func get_facing_angle() -> float:
	return _facing_angle


func get_animation_state() -> StringName:
	return &"moving" if velocity.length_squared() > 1.0 else &"idle"


func get_recorded_velocity() -> Vector2:
	return velocity


func get_visual() -> PlayerVisual:
	return visual


func get_visibility_probe() -> PlayerVisibilityProbe:
	return visibility_probe


func configure_facility_view(
	camera_bounds: Rect2,
	camera_zoom: Vector2,
	vision_radius: float
) -> void:
	_facility_view_configured = true
	visibility_probe.set_visibility_radius(vision_radius)
	# TimelineManager unlocks the query only after every resettable object, Ghost,
	# and the live Player are in their deterministic starting state.
	visibility_probe.set_query_enabled(false)
	vision_light.texture_scale = vision_radius / 256.0
	vision_light.enabled = false
	player_camera.limit_left = roundi(camera_bounds.position.x)
	player_camera.limit_top = roundi(camera_bounds.position.y)
	player_camera.limit_right = roundi(camera_bounds.end.x)
	player_camera.limit_bottom = roundi(camera_bounds.end.y)
	player_camera.zoom = camera_zoom
	# The operation HUD occupies the top of the viewport. Biasing the world view
	# upward keeps room landmarks and threats readable while the Player remains
	# below the HUD rather than directly beneath it.
	player_camera.offset = FACILITY_CAMERA_SAFE_TOP_OFFSET
	player_camera.enabled = true


func set_facility_visibility_enabled(enabled: bool) -> void:
	var facility_visibility_enabled := _facility_view_configured and enabled
	visibility_probe.set_query_enabled(facility_visibility_enabled)
	vision_light.enabled = facility_visibility_enabled


func disable_facility_view() -> void:
	_facility_view_configured = false
	visibility_probe.set_query_enabled(false)
	vision_light.enabled = false
	player_camera.offset = Vector2.ZERO
	player_camera.enabled = false


func get_detection_id() -> StringName:
	return DETECTION_ID


func get_detection_priority() -> int:
	return DETECTION_PRIORITY


func is_detectable_by_guard() -> bool:
	return true


func get_proximity_awareness_radius() -> float:
	return 88.0 if velocity.length_squared() > 100.0 else 46.0


func capture_recall_state() -> Dictionary:
	return {
		"global_position": global_position,
		"facing_angle": _facing_angle,
		"has_objective": _has_objective,
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	var position_variant: Variant = snapshot.get("global_position", global_position)
	if typeof(position_variant) != TYPE_VECTOR2:
		return false
	global_position = position_variant as Vector2
	velocity = Vector2.ZERO
	_facing_angle = float(snapshot.get("facing_angle", Vector2.DOWN.angle()))
	_has_objective = bool(snapshot.get("has_objective", false))
	visual.set_objective_visible(_has_objective)
	visual.update_motion(Vector2.from_angle(_facing_angle), velocity, &"idle")
	return true


func get_recall_state_id() -> StringName:
	return DETECTION_ID


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		velocity = Vector2.ZERO
		if is_instance_valid(visual):
			visual.update_motion(Vector2.from_angle(_facing_angle), velocity, &"idle")


func _update_facing() -> void:
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() <= 1.0:
		return
	_facing_angle = to_mouse.angle()


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
	visual.play_interaction()
	var payload: Dictionary = {}
	if target.has_method(&"get_recording_payload"):
		var payload_variant: Variant = target.call(&"get_recording_payload", self)
		if payload_variant is Dictionary:
			payload = (payload_variant as Dictionary).duplicate(true)
	interaction_recorded.emit(target_id, &"interact", payload)


func _find_nearest_interactable() -> Area2D:
	var nearest: Area2D = null
	var nearest_distance_squared := INF
	for candidate: Area2D in interaction_area.get_overlapping_areas():
		if not candidate.is_in_group("interactable"):
			continue
		if _facility_view_configured:
			if not visibility_probe.is_query_enabled():
				continue
			if not visibility_probe.is_actor_visible(candidate):
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
		if target.has_method(&"get_interaction_prompt"):
			prompt = String(target.call(&"get_interaction_prompt", self))
		else:
			prompt = "E  INTERACT"
	if prompt == _last_prompt:
		return
	_last_prompt = prompt
	interaction_prompt_changed.emit(prompt)
