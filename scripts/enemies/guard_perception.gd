class_name GuardPerception
extends Area2D

signal candidate_count_changed(candidate_count: int)

enum DetectionMode {
	NONE,
	VISION,
	PROXIMITY,
	CONTACT,
}

const WORLD_COLLISION_MASK: int = 1
const TARGET_HEIGHT_OFFSET: Vector2 = Vector2(0.0, -18.0)

@export_range(32.0, 640.0, 1.0) var vision_distance: float = 220.0
@export_range(5.0, 89.0, 1.0) var vision_half_angle_degrees: float = 38.0
@export_range(8.0, 64.0, 1.0) var direct_contact_distance: float = 18.0

var _candidates: Array[Node2D] = []
var _detection_enabled: bool = true

@onready var detection_shape: CollisionShape2D = %DetectionShape


func _ready() -> void:
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_sync_detection_radius()


func set_detection_enabled(enabled: bool) -> void:
	_detection_enabled = enabled
	monitoring = enabled
	if not enabled:
		clear_candidates()


func is_detection_enabled() -> bool:
	return _detection_enabled


func clear_candidates() -> void:
	if _candidates.is_empty():
		return
	_candidates.clear()
	candidate_count_changed.emit(0)


func get_candidate_count() -> int:
	_prune_invalid_candidates()
	return _candidates.size()


func get_visible_targets(facing_direction: Vector2) -> Array[Node2D]:
	var visible_targets: Array[Node2D] = []
	if not _detection_enabled:
		return visible_targets
	_prune_invalid_candidates()
	for candidate: Node2D in _candidates:
		if get_detection_mode(candidate, facing_direction) != DetectionMode.NONE:
			visible_targets.append(candidate)
	visible_targets.sort_custom(_candidate_less_than)
	return visible_targets


func is_target_visible(target: Node2D, facing_direction: Vector2) -> bool:
	if not _detection_enabled or not _is_detectable_actor(target):
		return false
	var target_position := target.global_position + TARGET_HEIGHT_OFFSET
	if not is_point_in_view(
		global_position,
		target_position,
		facing_direction,
		vision_distance,
		vision_half_angle_degrees
	):
		return false
	return has_clear_line_of_sight(target)


func get_detection_mode(target: Node2D, facing_direction: Vector2) -> DetectionMode:
	if not _detection_enabled or not _is_detectable_actor(target):
		return DetectionMode.NONE
	var target_position := target.global_position + TARGET_HEIGHT_OFFSET
	var distance := global_position.distance_to(target_position)
	if distance > vision_distance:
		return DetectionMode.NONE
	if not has_clear_line_of_sight(target):
		return DetectionMode.NONE
	if distance <= direct_contact_distance:
		return DetectionMode.CONTACT
	if is_point_in_view(
		global_position,
		target_position,
		facing_direction,
		vision_distance,
		vision_half_angle_degrees
	):
		return DetectionMode.VISION
	var proximity_radius := 42.0
	if target.has_method(&"get_proximity_awareness_radius"):
		proximity_radius = maxf(
			0.0,
			float(target.call(&"get_proximity_awareness_radius"))
		)
	return DetectionMode.PROXIMITY if distance <= proximity_radius else DetectionMode.NONE


func is_target_in_proximity(target: Node2D, facing_direction: Vector2) -> bool:
	var mode := get_detection_mode(target, facing_direction)
	return mode == DetectionMode.PROXIMITY or mode == DetectionMode.CONTACT


func has_clear_line_of_sight(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target) or not is_inside_tree():
		return false
	var excluded_rids: Array[RID] = []
	var guard_body := get_parent() as CollisionObject2D
	if guard_body != null:
		excluded_rids.append(guard_body.get_rid())
	return WorldLineOfSight2D.has_clear_line(
		get_world_2d().direct_space_state,
		global_position,
		target.global_position + TARGET_HEIGHT_OFFSET,
		WORLD_COLLISION_MASK,
		excluded_rids
	)


static func is_point_in_view(
	origin: Vector2,
	target_position: Vector2,
	facing_direction: Vector2,
	maximum_distance: float,
	half_angle_degrees: float
) -> bool:
	var to_target := target_position - origin
	var distance_squared := to_target.length_squared()
	if distance_squared > maximum_distance * maximum_distance:
		return false
	if distance_squared <= 0.000001:
		return true
	var normalized_facing := (
		facing_direction.normalized()
		if not facing_direction.is_zero_approx()
		else Vector2.RIGHT
	)
	var minimum_dot := cos(deg_to_rad(clampf(half_angle_degrees, 0.0, 180.0)))
	return normalized_facing.dot(to_target.normalized()) >= minimum_dot


func _on_body_entered(body: Node2D) -> void:
	if not _detection_enabled or not _is_detectable_actor(body):
		return
	if _candidates.has(body):
		return
	_candidates.append(body)
	candidate_count_changed.emit(_candidates.size())


func _on_body_exited(body: Node2D) -> void:
	var previous_size := _candidates.size()
	_candidates.erase(body)
	if previous_size != _candidates.size():
		candidate_count_changed.emit(_candidates.size())


func _prune_invalid_candidates() -> void:
	var changed := false
	for index: int in range(_candidates.size() - 1, -1, -1):
		if not is_instance_valid(_candidates[index]):
			_candidates.remove_at(index)
			changed = true
	if changed:
		candidate_count_changed.emit(_candidates.size())


func _is_detectable_actor(candidate: Node2D) -> bool:
	if candidate == null or not is_instance_valid(candidate):
		return false
	if not candidate.is_in_group(&"detectable_actor"):
		return false
	if candidate.has_method(&"is_detectable_by_guard"):
		return bool(candidate.call(&"is_detectable_by_guard"))
	return true


func _candidate_less_than(left: Node2D, right: Node2D) -> bool:
	var left_priority := _get_detection_priority(left)
	var right_priority := _get_detection_priority(right)
	if left_priority != right_priority:
		return left_priority < right_priority
	return String(_get_detection_id(left)) < String(_get_detection_id(right))


func _get_detection_priority(candidate: Node2D) -> int:
	if candidate.has_method(&"get_detection_priority"):
		return int(candidate.call(&"get_detection_priority"))
	return 0 if candidate.is_in_group(&"player_actor") else 1


func _get_detection_id(candidate: Node2D) -> StringName:
	if candidate.has_method(&"get_detection_id"):
		return StringName(candidate.call(&"get_detection_id"))
	return StringName("instance_%d" % candidate.get_instance_id())


func _sync_detection_radius() -> void:
	if detection_shape == null:
		return
	var circle := detection_shape.shape as CircleShape2D
	if circle == null:
		push_error("GuardPerception requires a CircleShape2D DetectionShape")
		return
	circle.radius = vision_distance
