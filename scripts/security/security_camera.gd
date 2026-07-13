class_name SecurityCamera
extends Area2D

signal threshold_reached(
	camera_id: StringName,
	zone_id: StringName,
	actor_id: StringName,
	last_seen_position: Vector2
)
signal detection_changed(actor_id: StringName, detection: float)

const WORLD_COLLISION_MASK: int = 1
const TARGET_OFFSET := Vector2(0.0, -18.0)
const CONE_SEGMENTS: int = 18

@export var object_id: StringName = &"camera_reception_01"
@export var zone_id: StringName = &"reception_zone"
@export_range(64.0, 480.0, 1.0) var vision_distance: float = 196.0
@export_range(5.0, 80.0, 1.0) var vision_half_angle_degrees: float = 32.0
@export_range(0.0, 180.0, 1.0) var sweep_half_angle_degrees: float = 55.0
@export_range(1.0, 120.0, 1.0) var sweep_speed_degrees: float = 24.0
@export_range(0.0, 60.0, 0.1) var start_phase_seconds: float = 0.0
@export_range(0.1, 5.0, 0.1) var detection_gain_per_second: float = 0.75
@export_range(0.1, 5.0, 0.1) var detection_loss_per_second: float = 1.0
@export_range(0.02, 0.5, 0.01) var update_interval: float = 0.1
@export_range(0.0, 1.0, 0.01) var update_phase_seconds: float = 0.0
@export var initial_facing: Vector2 = Vector2.RIGHT

@onready var detection_shape: CollisionShape2D = %DetectionShape
@onready var cone_root: Node2D = %ConeRoot
@onready var vision_cone: Polygon2D = %VisionCone
@onready var status_light: Polygon2D = %StatusLight

var network_online: bool = true
var sweep_angle_radians: float = 0.0
var sweep_direction: float = 1.0

var _base_angle_radians: float = 0.0
var _sweep_elapsed_seconds: float = 0.0
var _update_accumulator: float = 0.0
var _candidates: Array[Node2D] = []
var _detection_by_id: Dictionary[StringName, float] = {}
var _latched_ids: Dictionary[StringName, bool] = {}
var _security_manager: SecuritySystemManager = null


func _ready() -> void:
	add_to_group(&"stable_object")
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	add_to_group(&"security_camera")
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_base_angle_radians = (
		initial_facing.angle()
		if not initial_facing.is_zero_approx()
		else 0.0
	)
	_sync_detection_radius()
	_build_cone_geometry()
	reset_mission()


func _physics_process(delta: float) -> void:
	advance_camera(delta)


func configure(security_manager: SecuritySystemManager) -> void:
	_security_manager = security_manager
	if _security_manager != null:
		if not _security_manager.cctv_network_changed.is_connected(set_network_online):
			_security_manager.cctv_network_changed.connect(set_network_online)
		set_network_online(_security_manager.cctv_online)


func advance_camera(delta: float) -> void:
	if not network_online or delta <= 0.0:
		return
	var safe_delta := maxf(0.0, delta)
	_update_sweep(safe_delta)
	_update_accumulator += safe_delta
	if _update_accumulator + 0.000001 < update_interval:
		return
	var evaluation_delta := _update_accumulator
	_update_accumulator = fmod(_update_accumulator, update_interval)
	_update_detection(evaluation_delta)


func set_network_online(value: bool) -> void:
	network_online = value
	monitoring = value
	if not value:
		_candidates.clear()
		_detection_by_id.clear()
		_latched_ids.clear()
	vision_cone.color = (
		Color(0.31, 0.86, 0.92, 0.1)
		if value
		else Color(0.28, 0.36, 0.4, 0.05)
	)
	status_light.color = Color("5df1df") if value else Color("536372")


func is_target_visible(target: Node2D) -> bool:
	if not network_online or not _is_detectable_actor(target):
		return false
	var facing := Vector2.RIGHT.rotated(get_facing_angle())
	if not GuardPerception.is_point_in_view(
		global_position,
		target.global_position + TARGET_OFFSET,
		facing,
		vision_distance,
		vision_half_angle_degrees
	):
		return false
	return has_clear_line_of_sight(target)


func has_clear_line_of_sight(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target) or not is_inside_tree():
		return false
	return WorldLineOfSight2D.has_clear_line(
		get_world_2d().direct_space_state,
		global_position,
		target.global_position + TARGET_OFFSET,
		WORLD_COLLISION_MASK,
		[get_rid()]
	)


func get_facing_angle() -> float:
	return _base_angle_radians + sweep_angle_radians


func get_detection(actor_id: StringName) -> float:
	return float(_detection_by_id.get(actor_id, 0.0))


static func evaluate_sweep_phase(
	half_angle_degrees: float,
	angular_speed_degrees_per_second: float,
	phase_seconds: float
) -> Vector2:
	var half_angle := maxf(0.0, half_angle_degrees)
	var speed := maxf(0.0, angular_speed_degrees_per_second)
	if half_angle <= 0.000001 or speed <= 0.000001:
		return Vector2.ZERO
	var distance := fposmod(speed * maxf(0.0, phase_seconds), half_angle * 4.0)
	if distance < half_angle:
		return Vector2(deg_to_rad(distance), 1.0)
	if distance < half_angle * 3.0:
		return Vector2(deg_to_rad(half_angle * 2.0 - distance), -1.0)
	return Vector2(deg_to_rad(distance - half_angle * 4.0), 1.0)


func get_object_id() -> StringName:
	return object_id


func get_visibility_sample_position() -> Vector2:
	return global_position


func reset_mission() -> void:
	_sweep_elapsed_seconds = maxf(0.0, start_phase_seconds)
	_apply_sweep_phase()
	_update_accumulator = fmod(update_phase_seconds, maxf(update_interval, 0.001))
	_candidates.clear()
	_detection_by_id.clear()
	_latched_ids.clear()
	set_network_online(true)
	_update_cone_rotation()


func capture_recall_state() -> Dictionary:
	return {
		"network_online": network_online,
		"sweep_elapsed_seconds": _sweep_elapsed_seconds,
		"sweep_angle_radians": sweep_angle_radians,
		"sweep_direction": sweep_direction,
		"detection_by_id": _detection_by_id.duplicate(true),
		"latched_ids": _latched_ids.duplicate(true),
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	var detections_variant: Variant = snapshot.get("detection_by_id", {})
	var latches_variant: Variant = snapshot.get("latched_ids", {})
	if not detections_variant is Dictionary or not latches_variant is Dictionary:
		return false
	if snapshot.has("sweep_elapsed_seconds"):
		_sweep_elapsed_seconds = maxf(
			0.0, float(snapshot.get("sweep_elapsed_seconds", start_phase_seconds))
		)
		_apply_sweep_phase()
	else:
		sweep_angle_radians = float(snapshot.get("sweep_angle_radians", 0.0))
		sweep_direction = (
			-1.0 if float(snapshot.get("sweep_direction", 1.0)) < 0.0 else 1.0
		)
	_detection_by_id.clear()
	for key: Variant in (detections_variant as Dictionary).keys():
		_detection_by_id[StringName(str(key))] = clampf(
			float((detections_variant as Dictionary)[key]),
			0.0,
			1.0
		)
	_latched_ids.clear()
	for key: Variant in (latches_variant as Dictionary).keys():
		_latched_ids[StringName(str(key))] = bool((latches_variant as Dictionary)[key])
	set_network_online(bool(snapshot.get("network_online", true)))
	_update_cone_rotation()
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _update_sweep(delta: float) -> void:
	_sweep_elapsed_seconds += maxf(0.0, delta)
	_apply_sweep_phase()
	_update_cone_rotation()


func _apply_sweep_phase() -> void:
	var phase := evaluate_sweep_phase(
		sweep_half_angle_degrees,
		sweep_speed_degrees,
		_sweep_elapsed_seconds
	)
	sweep_angle_radians = phase.x
	sweep_direction = phase.y if not phase.is_zero_approx() else 1.0


func _update_detection(delta: float) -> void:
	_prune_candidates()
	var visible_ids: Dictionary[StringName, bool] = {}
	var visible_targets: Array[Node2D] = []
	for candidate: Node2D in _candidates:
		if is_target_visible(candidate):
			visible_targets.append(candidate)
	visible_targets.sort_custom(_candidate_less_than)
	for candidate: Node2D in visible_targets:
		var actor_id := _get_detection_id(candidate)
		visible_ids[actor_id] = true
		var detection := clampf(
			get_detection(actor_id) + detection_gain_per_second * delta,
			0.0,
			1.0
		)
		_detection_by_id[actor_id] = detection
		detection_changed.emit(actor_id, detection)
		if detection >= 1.0 and not bool(_latched_ids.get(actor_id, false)):
			_latched_ids[actor_id] = true
			threshold_reached.emit(object_id, zone_id, actor_id, candidate.global_position)
			if _security_manager != null:
				var alert_level := (
					SecuritySystemManager.AlertLevel.ALERTED
					if candidate.is_in_group(&"player_actor")
					else SecuritySystemManager.AlertLevel.SUSPICIOUS
				)
				_security_manager.raise_zone_alert(
					zone_id,
					candidate.global_position,
					object_id,
					alert_level
				)
	var known_ids := _detection_by_id.keys()
	for actor_variant: Variant in known_ids:
		var actor_id := StringName(str(actor_variant))
		if bool(visible_ids.get(actor_id, false)):
			continue
		var detection := clampf(
			get_detection(actor_id) - detection_loss_per_second * delta,
			0.0,
			1.0
		)
		_detection_by_id[actor_id] = detection
		if detection <= 0.0:
			_detection_by_id.erase(actor_id)
			_latched_ids.erase(actor_id)
		detection_changed.emit(actor_id, detection)


func _on_body_entered(body: Node2D) -> void:
	if network_online and _is_detectable_actor(body) and not _candidates.has(body):
		_candidates.append(body)


func _on_body_exited(body: Node2D) -> void:
	_candidates.erase(body)


func _prune_candidates() -> void:
	for index: int in range(_candidates.size() - 1, -1, -1):
		if not is_instance_valid(_candidates[index]):
			_candidates.remove_at(index)


func _is_detectable_actor(actor: Node2D) -> bool:
	return (
		actor != null
		and is_instance_valid(actor)
		and actor.is_in_group(&"detectable_actor")
		and (
			not actor.has_method(&"is_detectable_by_guard")
			or bool(actor.call(&"is_detectable_by_guard"))
		)
	)


func _candidate_less_than(left: Node2D, right: Node2D) -> bool:
	var left_priority := 0 if left.is_in_group(&"player_actor") else 1
	var right_priority := 0 if right.is_in_group(&"player_actor") else 1
	if left_priority != right_priority:
		return left_priority < right_priority
	return String(_get_detection_id(left)) < String(_get_detection_id(right))


func _get_detection_id(actor: Node2D) -> StringName:
	if actor.has_method(&"get_detection_id"):
		return StringName(actor.call(&"get_detection_id"))
	return StringName("actor_%d" % actor.get_instance_id())


func _sync_detection_radius() -> void:
	var circle := detection_shape.shape as CircleShape2D
	if circle == null:
		push_error("SecurityCamera requires a CircleShape2D DetectionShape")
		return
	circle.radius = vision_distance


func _build_cone_geometry() -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	var half_angle := deg_to_rad(vision_half_angle_degrees)
	for index: int in range(CONE_SEGMENTS + 1):
		var weight := float(index) / float(CONE_SEGMENTS)
		points.append(Vector2.RIGHT.rotated(lerpf(-half_angle, half_angle, weight)) * vision_distance)
	vision_cone.polygon = points


func _update_cone_rotation() -> void:
	cone_root.rotation = get_facing_angle()
