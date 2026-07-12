class_name ActionRecorder
extends Node

const TIMESTAMP_EPSILON: float = 0.000001
const MAX_PAYLOAD_DEPTH: int = 16

@export_range(1.0, 120.0, 1.0) var sample_rate_hz: float = 20.0

var _actor: Node2D
var _max_duration: float = 0.0
var _sample_interval: float = 0.05
var _next_sample_time: float = 0.0
var _last_observation_time: float = 0.0
var _last_observation_position: Vector2 = Vector2.ZERO
var _last_observation_facing: Vector2 = Vector2.RIGHT
var _last_observation_animation: StringName = &""
var _last_observation_velocity: Vector2 = Vector2.ZERO
var _event_sequence: int = 0
var _is_recording: bool = false
var _warned_past_duration: bool = false
var _samples: Array[TransformSample] = []
var _events: Array[RecordedEvent] = []


func begin_recording(actor: Node2D, max_duration: float) -> bool:
	if actor == null or not is_instance_valid(actor):
		push_error("ActionRecorder cannot begin without a valid Node2D actor.")
		return false
	if max_duration <= 0.0:
		push_error("ActionRecorder max_duration must be greater than zero (received %.6f)." % max_duration)
		return false
	if sample_rate_hz <= 0.0:
		push_error("ActionRecorder sample_rate_hz must be greater than zero.")
		return false
	if _is_recording:
		push_warning("ActionRecorder replaced an unfinished recording.")

	_clear_state()
	_actor = actor
	_max_duration = max_duration
	_sample_interval = 1.0 / sample_rate_hz
	_is_recording = true
	_observe_actor_at(0.0)
	_append_observed_sample(0.0)
	_next_sample_time = _sample_interval
	return true


func capture_until(timestamp: float) -> void:
	if not _is_recording:
		return
	if _actor == null or not is_instance_valid(_actor):
		push_error("ActionRecorder lost its actor while recording.")
		return

	if timestamp > _max_duration + TIMESTAMP_EPSILON and not _warned_past_duration:
		push_warning(
			"ActionRecorder clamped capture time %.6f to max duration %.6f."
			% [timestamp, _max_duration]
		)
		_warned_past_duration = true
	var target_time: float = clampf(timestamp, 0.0, _max_duration)
	if target_time + TIMESTAMP_EPSILON < _last_observation_time:
		push_warning(
			"ActionRecorder ignored non-monotonic capture time %.6f after %.6f."
			% [target_time, _last_observation_time]
		)
		return

	var current_position: Vector2 = _actor.global_position
	var current_facing: Vector2 = _read_facing_direction()
	var current_animation: StringName = _read_animation_state()
	var current_velocity: Vector2 = _read_velocity()
	var observation_span: float = target_time - _last_observation_time

	while _next_sample_time <= target_time + TIMESTAMP_EPSILON:
		var weight: float = 1.0
		if observation_span > TIMESTAMP_EPSILON:
			weight = clampf(
				(_next_sample_time - _last_observation_time) / observation_span,
				0.0,
				1.0
			)
		var sample_position: Vector2 = _last_observation_position.lerp(current_position, weight)
		var sample_facing: Vector2 = _interpolate_facing(
			_last_observation_facing,
			current_facing,
			weight
		)
		var sample_animation: StringName = (
			current_animation if weight >= 0.5 else _last_observation_animation
		)
		var sample_velocity: Vector2 = _last_observation_velocity.lerp(current_velocity, weight)
		_samples.append(TransformSample.new(
			minf(_next_sample_time, _max_duration),
			sample_position,
			sample_facing,
			sample_animation,
			sample_velocity
		))
		_next_sample_time += _sample_interval

	_last_observation_time = target_time
	_last_observation_position = current_position
	_last_observation_facing = current_facing
	_last_observation_animation = current_animation
	_last_observation_velocity = current_velocity


func record_interaction(
		timestamp: float,
		target_id: StringName,
		event_type: StringName,
		payload: Dictionary = {}
) -> bool:
	if not _is_recording:
		push_warning("ActionRecorder ignored an interaction because no recording is active.")
		return false
	if target_id == StringName():
		push_warning("ActionRecorder ignored an interaction with an empty stable object ID.")
		return false
	if event_type == StringName():
		push_warning("ActionRecorder ignored an interaction with an empty event type.")
		return false
	if _payload_contains_object(payload):
		push_warning(
			"ActionRecorder ignored event '%s' for '%s': payload contains an Object reference."
			% [event_type, target_id]
		)
		return false

	capture_until(timestamp)
	var event_timestamp: float = clampf(timestamp, 0.0, _max_duration)
	_events.append(RecordedEvent.new(
		event_timestamp,
		target_id,
		event_type,
		payload,
		_event_sequence
	))
	_event_sequence += 1
	return true


func finish_recording(duration: float, loop_index: int) -> LoopRecording:
	if not _is_recording:
		push_warning("ActionRecorder finish requested with no active recording.")
		return LoopRecording.new(maxf(0.0, duration), [], [], loop_index)

	var final_duration: float = clampf(duration, 0.0, _max_duration)
	if final_duration + TIMESTAMP_EPSILON < _last_observation_time:
		push_warning(
			"ActionRecorder finish time %.6f preceded the last capture %.6f; using the last capture."
			% [final_duration, _last_observation_time]
		)
		final_duration = _last_observation_time
	capture_until(final_duration)

	if _samples.is_empty() or _samples.back().timestamp + TIMESTAMP_EPSILON < final_duration:
		_append_observed_sample(final_duration)

	var completed: LoopRecording = LoopRecording.new(
		final_duration,
		_samples,
		_events,
		loop_index
	)
	_clear_state()
	return completed


func cancel_recording() -> void:
	_clear_state()


func is_recording() -> bool:
	return _is_recording


func get_pending_sample_count() -> int:
	return _samples.size()


func get_pending_event_count() -> int:
	return _events.size()


func _observe_actor_at(timestamp: float) -> void:
	_last_observation_time = timestamp
	_last_observation_position = _actor.global_position
	_last_observation_facing = _read_facing_direction()
	_last_observation_animation = _read_animation_state()
	_last_observation_velocity = _read_velocity()


func _append_observed_sample(timestamp: float) -> void:
	_samples.append(TransformSample.new(
		timestamp,
		_last_observation_position,
		_last_observation_facing,
		_last_observation_animation,
		_last_observation_velocity
	))


func _read_facing_direction() -> Vector2:
	if _actor.has_method(&"get_facing_direction"):
		var direction_result: Variant = _actor.call(&"get_facing_direction")
		if typeof(direction_result) == TYPE_VECTOR2:
			var facing: Vector2 = direction_result
			if not facing.is_zero_approx():
				return facing.normalized()
	if _actor.has_method(&"get_facing_angle"):
		var angle_result: Variant = _actor.call(&"get_facing_angle")
		if typeof(angle_result) == TYPE_FLOAT or typeof(angle_result) == TYPE_INT:
			return Vector2.from_angle(float(angle_result))
	return Vector2.RIGHT.rotated(_actor.global_rotation)


func _read_animation_state() -> StringName:
	if _actor.has_method(&"get_recording_animation_state"):
		var recording_state: Variant = _actor.call(&"get_recording_animation_state")
		return StringName(str(recording_state))
	if _actor.has_method(&"get_animation_state"):
		var animation_state: Variant = _actor.call(&"get_animation_state")
		return StringName(str(animation_state))
	return StringName()


func _read_velocity() -> Vector2:
	if _actor.has_method(&"get_recording_velocity"):
		var recording_velocity: Variant = _actor.call(&"get_recording_velocity")
		if typeof(recording_velocity) == TYPE_VECTOR2:
			var typed_recording_velocity: Vector2 = recording_velocity
			return typed_recording_velocity
	if _actor.has_method(&"get_recorded_velocity"):
		var recorded_velocity: Variant = _actor.call(&"get_recorded_velocity")
		if typeof(recorded_velocity) == TYPE_VECTOR2:
			var typed_recorded_velocity: Vector2 = recorded_velocity
			return typed_recorded_velocity
	if _actor is CharacterBody2D:
		return (_actor as CharacterBody2D).velocity
	return Vector2.ZERO


func _clear_state() -> void:
	_actor = null
	_max_duration = 0.0
	_sample_interval = 0.05
	_next_sample_time = 0.0
	_last_observation_time = 0.0
	_last_observation_position = Vector2.ZERO
	_last_observation_facing = Vector2.RIGHT
	_last_observation_animation = StringName()
	_last_observation_velocity = Vector2.ZERO
	_event_sequence = 0
	_is_recording = false
	_warned_past_duration = false
	_samples.clear()
	_events.clear()


static func _interpolate_facing(from: Vector2, to: Vector2, weight: float) -> Vector2:
	if from.is_zero_approx():
		return to.normalized() if not to.is_zero_approx() else Vector2.RIGHT
	if to.is_zero_approx():
		return from.normalized()
	var angle: float = lerp_angle(from.angle(), to.angle(), weight)
	return Vector2.RIGHT.rotated(angle)


static func _payload_contains_object(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_PAYLOAD_DEPTH:
		return true
	match typeof(value):
		TYPE_OBJECT:
			return value != null
		TYPE_ARRAY:
			var array_values: Array = value
			for item: Variant in array_values:
				if _payload_contains_object(item, depth + 1):
					return true
		TYPE_DICTIONARY:
			var dictionary_values: Dictionary = value
			for key: Variant in dictionary_values:
				if _payload_contains_object(key, depth + 1):
					return true
				if _payload_contains_object(dictionary_values[key], depth + 1):
					return true
	return false
