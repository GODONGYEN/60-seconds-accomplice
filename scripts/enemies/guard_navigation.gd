class_name GuardNavigation
extends Node

const MIN_PROGRESS_PER_TICK: float = 0.05

var _body: CharacterBody2D = null
var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _blocked_time: float = 0.0
var _guard_id: StringName = StringName()
var _patrol_scheduler: PatrolScheduler = null


func configure(body: CharacterBody2D) -> void:
	_body = body
	clear_target()


func configure_scheduler(guard_id: StringName, scheduler: PatrolScheduler) -> void:
	_guard_id = guard_id
	_patrol_scheduler = scheduler
	if _patrol_scheduler != null and _body != null:
		_patrol_scheduler.register_guard(_guard_id, _body.global_position)
		_patrol_scheduler.commit_guard_position(_guard_id, _body.global_position)


func sync_scheduler_position() -> void:
	if _patrol_scheduler != null and _body != null:
		_patrol_scheduler.commit_guard_position(_guard_id, _body.global_position)


func set_target_position(target_position: Vector2) -> void:
	_target_position = target_position
	_has_target = true


func clear_target() -> void:
	_has_target = false
	_blocked_time = 0.0
	if _body != null:
		_body.velocity = Vector2.ZERO
	if _patrol_scheduler != null:
		_patrol_scheduler.release_guard_reservation(_guard_id)


func move_toward_target(delta: float, speed: float, arrival_distance: float) -> bool:
	if _body == null or not is_instance_valid(_body) or not _has_target:
		return true
	var to_target := _target_position - _body.global_position
	var distance := to_target.length()
	if distance <= arrival_distance:
		_body.velocity = Vector2.ZERO
		_blocked_time = 0.0
		return true
	if delta <= 0.0 or speed <= 0.0:
		_body.velocity = Vector2.ZERO
		return false
	var before := _body.global_position
	var step_speed := minf(speed, distance / delta)
	var intended_velocity := to_target.normalized() * step_speed
	var proposed_position := before + intended_velocity * delta
	if (
		_patrol_scheduler != null
		and not _patrol_scheduler.request_world_reservation(
			_guard_id,
			proposed_position,
			delta
		)
	):
		_body.velocity = Vector2.ZERO
		_blocked_time += delta
		return false
	_body.velocity = intended_velocity
	_body.move_and_slide()
	if _patrol_scheduler != null:
		_patrol_scheduler.commit_guard_position(_guard_id, _body.global_position)
	var progress := before.distance_to(_target_position) - _body.global_position.distance_to(
		_target_position
	)
	if progress < MIN_PROGRESS_PER_TICK:
		_blocked_time += delta
	else:
		_blocked_time = 0.0
	return _body.global_position.distance_to(_target_position) <= arrival_distance


func stop() -> void:
	if _body != null:
		_body.velocity = Vector2.ZERO


func has_target() -> bool:
	return _has_target


func get_target_position() -> Vector2:
	return _target_position


func get_blocked_time() -> float:
	return _blocked_time
