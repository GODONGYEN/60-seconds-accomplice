class_name GuardController
extends CharacterBody2D

signal state_changed(previous_state: GuardState, current_state: GuardState)
signal status_changed(state_name: StringName, suspicion: float, target_id: StringName)
signal alert_raised(target_id: StringName)
signal capture_requested(player: PlayerController)

enum GuardState {
	IDLE,
	PATROL,
	SUSPICIOUS,
	CHASE,
	SEARCH,
	RETURN,
}

const STATE_NAMES: Dictionary = {
	GuardState.IDLE: &"idle",
	GuardState.PATROL: &"patrol",
	GuardState.SUSPICIOUS: &"suspicious",
	GuardState.CHASE: &"chase",
	GuardState.SEARCH: &"search",
	GuardState.RETURN: &"return",
}
const TARGET_POSITION_EPSILON_SQUARED: float = 64.0
const SUSPICION_EPSILON: float = 0.0001

@export_range(0.0, 200.0, 1.0) var patrol_speed: float = 52.0
@export_range(0.0, 300.0, 1.0) var chase_speed: float = 96.0
@export_range(0.0, 5.0, 0.05) var idle_duration: float = 0.7
@export_range(0.1, 10.0, 0.1) var suspicion_gain_per_second: float = 1.4
@export_range(0.1, 10.0, 0.1) var suspicion_loss_per_second: float = 0.8
@export_range(0.0, 2.0, 0.05) var lose_target_delay: float = 0.5
@export_range(0.1, 10.0, 0.1) var search_duration: float = 2.5
@export_range(4.0, 64.0, 1.0) var capture_distance: float = 18.0
@export_range(0.0, 2.0, 0.05) var capture_hold_time: float = 0.2
@export_range(1.0, 32.0, 1.0) var waypoint_arrival_distance: float = 5.0
@export_range(0.01, 1.0, 0.01) var perception_update_interval: float = 0.05
@export_range(0.01, 1.0, 0.01) var navigation_update_interval: float = 0.1
@export_range(0.1, 3.0, 0.1) var blocked_timeout: float = 0.8
@export_range(0.0, 3.0, 0.05) var reset_perception_grace: float = 0.75
@export var initial_facing: Vector2 = Vector2.RIGHT
@export var patrol_route_path: NodePath
@export var debug_overlay_enabled: bool = false

@onready var visual: GuardVisual = %VisualRoot
@onready var perception: GuardPerception = %Perception
@onready var navigation: GuardNavigation = %GuardNavigation
@onready var capture_area: Area2D = %CaptureArea
@onready var capture_shape: CollisionShape2D = %CaptureShape

var state: GuardState = GuardState.IDLE
var suspicion: float = 0.0
var current_target: Node2D = null
var last_seen_position: Vector2 = Vector2.ZERO

var _initial_global_position: Vector2 = Vector2.ZERO
var _facing_direction: Vector2 = Vector2.RIGHT
var _patrol_points: Array[Vector2] = []
var _patrol_index: int = 0
var _return_patrol_index: int = 0
var _idle_timer: float = 0.0
var _lose_target_timer: float = 0.0
var _search_timer: float = 0.0
var _capture_timer: float = 0.0
var _perception_accumulator: float = 0.0
var _navigation_refresh_timer: float = 0.0
var _perception_grace_remaining: float = 0.0
var _simulation_enabled: bool = true
var _target_visible: bool = false
var _capture_committed: bool = false
var _entered_chase_this_tick: bool = false
var _last_reported_suspicion: float = -1.0
var _last_reported_target_id: StringName = &"__unset"


func _ready() -> void:
	add_to_group(&"loop_resettable")
	add_to_group(&"guard_actor")
	process_physics_priority = 200
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	_initial_global_position = global_position
	_facing_direction = _normalized_facing(initial_facing)
	navigation.configure(self)
	_sync_capture_radius()
	_resolve_patrol_route()
	reset_for_loop()


func _physics_process(delta: float) -> void:
	advance_ai(delta)


func advance_ai(delta: float) -> void:
	if not _simulation_enabled or delta <= 0.0:
		return
	var safe_delta := maxf(0.0, delta)
	_entered_chase_this_tick = false
	if current_target != null and not is_instance_valid(current_target):
		current_target = null
		_target_visible = false
	if _perception_grace_remaining > 0.0:
		_perception_grace_remaining = maxf(0.0, _perception_grace_remaining - safe_delta)
		perception.set_detection_enabled(false)
		_target_visible = false
	else:
		if not perception.is_detection_enabled():
			perception.set_detection_enabled(true)
			_perception_accumulator = perception_update_interval
		_update_perception(safe_delta)

	match state:
		GuardState.IDLE:
			_update_idle(safe_delta)
		GuardState.PATROL:
			_update_patrol(safe_delta)
		GuardState.SUSPICIOUS:
			_update_suspicious(safe_delta)
		GuardState.CHASE:
			_update_chase(safe_delta)
		GuardState.SEARCH:
			_update_search(safe_delta)
		GuardState.RETURN:
			_update_return(safe_delta)

	_update_capture(safe_delta)
	_update_facing_from_motion()
	visual.update_state(_facing_direction, velocity, get_state_name(), suspicion)
	visual.set_debug_data(_build_debug_text(), debug_overlay_enabled)
	_emit_status_if_changed()


func transition_to(next_state: GuardState) -> void:
	if not STATE_NAMES.has(next_state):
		push_warning("Guard '%s' ignored invalid state transition: %s" % [name, next_state])
		return
	if state == next_state:
		return
	var previous_state := state
	state = next_state
	_idle_timer = 0.0
	_navigation_refresh_timer = 0.0
	match state:
		GuardState.IDLE:
			navigation.stop()
		GuardState.PATROL:
			_set_navigation_target(_patrol_points[_patrol_index])
		GuardState.SUSPICIOUS:
			navigation.stop()
		GuardState.CHASE:
			_entered_chase_this_tick = true
			suspicion = 1.0
			_lose_target_timer = 0.0
			alert_raised.emit(get_current_target_id())
		GuardState.SEARCH:
			_search_timer = 0.0
			_lose_target_timer = 0.0
			_set_navigation_target(last_seen_position)
		GuardState.RETURN:
			current_target = null
			_target_visible = false
			capture_area.monitoring = true
			_return_patrol_index = _find_nearest_patrol_index(global_position)
			_patrol_index = _return_patrol_index
			_set_navigation_target(_patrol_points[_patrol_index])
	state_changed.emit(previous_state, state)
	_emit_status(true)


func reset_for_loop() -> void:
	global_position = _initial_global_position
	velocity = Vector2.ZERO
	state = GuardState.IDLE
	suspicion = 0.0
	current_target = null
	last_seen_position = _initial_global_position
	_facing_direction = _normalized_facing(initial_facing)
	_patrol_index = 0
	_return_patrol_index = 0
	_idle_timer = 0.0
	_lose_target_timer = 0.0
	_search_timer = 0.0
	_capture_timer = 0.0
	_perception_accumulator = 0.0
	_navigation_refresh_timer = 0.0
	_perception_grace_remaining = reset_perception_grace
	_target_visible = false
	_capture_committed = false
	_entered_chase_this_tick = false
	_last_reported_suspicion = -1.0
	_last_reported_target_id = &"__unset"
	navigation.clear_target()
	perception.set_detection_enabled(false)
	capture_area.monitoring = _simulation_enabled
	visual.reset_visual(_facing_direction)
	visual.configure_vision(perception.vision_distance, perception.vision_half_angle_degrees)
	visual.set_debug_data("", false)
	set_physics_process(_simulation_enabled)
	_emit_status(true)


func set_simulation_enabled(enabled: bool) -> void:
	_simulation_enabled = enabled
	set_physics_process(enabled)
	perception.set_detection_enabled(enabled and _perception_grace_remaining <= 0.0)
	capture_area.monitoring = enabled
	if not enabled:
		velocity = Vector2.ZERO
		navigation.stop()
		_target_visible = false
		_capture_timer = 0.0
	visual.set_animation_paused(not enabled)


func is_simulation_enabled() -> bool:
	return _simulation_enabled


func get_visual() -> GuardVisual:
	return visual


func get_perception() -> GuardPerception:
	return perception


func get_state_name() -> StringName:
	return StringName(STATE_NAMES.get(state, &"unknown"))


func get_suspicion() -> float:
	return suspicion


func get_current_target_id() -> StringName:
	if current_target == null or not is_instance_valid(current_target):
		return StringName()
	return _get_actor_detection_id(current_target)


func get_patrol_index() -> int:
	return _patrol_index


func get_last_seen_position() -> Vector2:
	return last_seen_position


func get_facing_direction() -> Vector2:
	return _facing_direction


func get_capture_timer() -> float:
	return _capture_timer


func has_valid_patrol_route() -> bool:
	return _patrol_points.size() >= 2


func get_patrol_point_count() -> int:
	return _patrol_points.size()


func _update_perception(delta: float) -> void:
	_perception_accumulator += delta
	if _perception_accumulator + SUSPICION_EPSILON < perception_update_interval:
		return
	_perception_accumulator = fmod(_perception_accumulator, perception_update_interval)
	var visible_targets := perception.get_visible_targets(_facing_direction)
	var selected_target: Node2D = visible_targets[0] if not visible_targets.is_empty() else null
	_target_visible = selected_target != null
	if selected_target == null:
		if current_target != null and not is_instance_valid(current_target):
			current_target = null
		return
	if selected_target != current_target:
		var preserve_alert := (
			state == GuardState.CHASE and selected_target.is_in_group(&"player_actor")
		)
		current_target = selected_target
		if not preserve_alert:
			suspicion = 0.0
	last_seen_position = selected_target.global_position
	_lose_target_timer = 0.0
	if state == GuardState.CHASE:
		return
	if state != GuardState.SUSPICIOUS:
		transition_to(GuardState.SUSPICIOUS)


func _update_idle(delta: float) -> void:
	navigation.stop()
	if _target_visible:
		transition_to(GuardState.SUSPICIOUS)
		return
	_idle_timer += delta
	if _idle_timer < idle_duration:
		return
	_patrol_index = (_patrol_index + 1) % _patrol_points.size()
	transition_to(GuardState.PATROL)


func _update_patrol(delta: float) -> void:
	if _target_visible:
		transition_to(GuardState.SUSPICIOUS)
		return
	_set_navigation_target(_patrol_points[_patrol_index])
	if navigation.move_toward_target(delta, patrol_speed, waypoint_arrival_distance):
		transition_to(GuardState.IDLE)


func _update_suspicious(delta: float) -> void:
	navigation.stop()
	if _target_visible and current_target != null:
		_face_position(current_target.global_position)
		last_seen_position = current_target.global_position
		suspicion = clampf(suspicion + suspicion_gain_per_second * delta, 0.0, 1.0)
		if suspicion >= 1.0 - SUSPICION_EPSILON:
			transition_to(GuardState.CHASE)
		return
	suspicion = clampf(suspicion - suspicion_loss_per_second * delta, 0.0, 1.0)
	if suspicion <= SUSPICION_EPSILON:
		transition_to(GuardState.RETURN)


func _update_chase(delta: float) -> void:
	suspicion = 1.0
	if _target_visible and current_target != null:
		last_seen_position = current_target.global_position
		_lose_target_timer = 0.0
		_update_chase_target(delta, last_seen_position)
		return
	_lose_target_timer += delta
	_update_chase_target(delta, last_seen_position)
	if _lose_target_timer >= lose_target_delay or navigation.get_blocked_time() >= blocked_timeout:
		transition_to(GuardState.SEARCH)


func _update_search(delta: float) -> void:
	if _target_visible and current_target != null:
		suspicion = 1.0
		transition_to(GuardState.CHASE)
		return
	suspicion = clampf(suspicion - suspicion_loss_per_second * delta, 0.0, 1.0)
	var arrived := navigation.move_toward_target(
		delta,
		patrol_speed,
		waypoint_arrival_distance
	)
	if not arrived and navigation.get_blocked_time() < blocked_timeout:
		return
	navigation.stop()
	_search_timer += delta
	var quarter_duration := maxf(0.1, search_duration / 4.0)
	var quarter_turn := int(floor(_search_timer / quarter_duration)) % 4
	_facing_direction = Vector2.RIGHT.rotated(float(quarter_turn) * PI * 0.5)
	if _search_timer >= search_duration:
		transition_to(GuardState.RETURN)


func _update_return(delta: float) -> void:
	if _target_visible:
		transition_to(GuardState.SUSPICIOUS)
		return
	_set_navigation_target(_patrol_points[_patrol_index])
	if navigation.move_toward_target(delta, patrol_speed, waypoint_arrival_distance):
		transition_to(GuardState.IDLE)


func _update_chase_target(delta: float, target_position: Vector2) -> void:
	_navigation_refresh_timer -= delta
	if (
		not navigation.has_target()
		or _navigation_refresh_timer <= 0.0
		or navigation.get_target_position().distance_squared_to(target_position)
			>= TARGET_POSITION_EPSILON_SQUARED
	):
		_set_navigation_target(target_position)
		_navigation_refresh_timer = navigation_update_interval
	navigation.move_toward_target(delta, chase_speed, waypoint_arrival_distance)


func _update_capture(delta: float) -> void:
	if _capture_committed or state != GuardState.CHASE or _entered_chase_this_tick:
		_capture_timer = 0.0
		return
	var player := current_target as PlayerController
	if player == null or not is_instance_valid(player) or not _target_visible:
		_capture_timer = 0.0
		return
	if global_position.distance_to(player.global_position) > capture_distance:
		_capture_timer = 0.0
		return
	if not perception.has_clear_line_of_sight(player):
		_capture_timer = 0.0
		return
	_capture_timer += delta
	if _capture_timer + SUSPICION_EPSILON < capture_hold_time:
		return
	_capture_committed = true
	velocity = Vector2.ZERO
	navigation.stop()
	capture_requested.emit(player)


func _set_navigation_target(target_position: Vector2) -> void:
	if (
		navigation.has_target()
		and navigation.get_target_position().is_equal_approx(target_position)
	):
		return
	navigation.set_target_position(target_position)


func _update_facing_from_motion() -> void:
	if velocity.length_squared() > 1.0:
		_facing_direction = velocity.normalized()
	elif current_target != null and is_instance_valid(current_target) and _target_visible:
		_face_position(current_target.global_position)


func _face_position(target_position: Vector2) -> void:
	var direction := target_position - global_position
	if not direction.is_zero_approx():
		_facing_direction = direction.normalized()


func _resolve_patrol_route() -> void:
	_patrol_points.clear()
	var route := get_node_or_null(patrol_route_path) as Node2D
	if route != null:
		for child: Node in route.get_children():
			if child is Marker2D:
				_patrol_points.append((child as Marker2D).global_position)
	if _patrol_points.is_empty():
		_patrol_points.append(_initial_global_position)
	if _patrol_points.size() < 2 and not patrol_route_path.is_empty():
		push_warning(
			"Guard '%s' patrol route '%s' requires at least two Marker2D children."
			% [name, patrol_route_path]
		)


func _find_nearest_patrol_index(from_position: Vector2) -> int:
	var nearest_index := 0
	var nearest_distance := INF
	for index: int in range(_patrol_points.size()):
		var distance := from_position.distance_squared_to(_patrol_points[index])
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return nearest_index


func _sync_capture_radius() -> void:
	var circle := capture_shape.shape as CircleShape2D
	if circle == null:
		push_error("Guard CaptureShape must use CircleShape2D")
		return
	circle.radius = capture_distance


func _normalized_facing(direction: Vector2) -> Vector2:
	return direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT


func _get_actor_detection_id(actor: Node2D) -> StringName:
	if actor == null or not is_instance_valid(actor):
		return StringName()
	if actor.has_method(&"get_detection_id"):
		return StringName(actor.call(&"get_detection_id"))
	return StringName("instance_%d" % actor.get_instance_id())


func _emit_status_if_changed() -> void:
	var target_id := get_current_target_id()
	if (
		absf(suspicion - _last_reported_suspicion) < 0.01
		and target_id == _last_reported_target_id
	):
		return
	_emit_status(false)


func _emit_status(force: bool) -> void:
	var target_id := get_current_target_id()
	if not force and (
		absf(suspicion - _last_reported_suspicion) < 0.01
		and target_id == _last_reported_target_id
	):
		return
	_last_reported_suspicion = suspicion
	_last_reported_target_id = target_id
	status_changed.emit(get_state_name(), suspicion, target_id)


func _build_debug_text() -> String:
	return "STATE %s\nTARGET %s\nSUSPICION %.2f\nWAYPOINT %d\nCAPTURE %.2f" % [
		get_state_name(),
		get_current_target_id(),
		suspicion,
		_patrol_index,
		_capture_timer,
	]
