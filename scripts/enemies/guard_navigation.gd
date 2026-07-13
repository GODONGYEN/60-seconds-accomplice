class_name GuardNavigation
extends Node

const MIN_PROGRESS_PER_TICK: float = 0.05

var _body: CharacterBody2D = null
var _target_position: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _blocked_time: float = 0.0


func configure(body: CharacterBody2D) -> void:
	_body = body
	clear_target()


func set_target_position(target_position: Vector2) -> void:
	_target_position = target_position
	_has_target = true


func clear_target() -> void:
	_has_target = false
	_blocked_time = 0.0
	if _body != null:
		_body.velocity = Vector2.ZERO


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
	_body.velocity = to_target.normalized() * step_speed
	_body.move_and_slide()
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
