class_name RecallHistory
extends RefCounted

const TIMESTAMP_EPSILON: float = 0.000001
const MAX_PAYLOAD_DEPTH: int = 16

var sample_rate_hz: float = 20.0
var history_duration_seconds: float = 10.0

var _actor: Node2D = null
var _branch_start_time: float = 0.0
var _logical_oldest_time: float = 0.0
var _sample_interval: float = 0.05
var _next_sample_time: float = 0.0
var _last_observation_time: float = 0.0
var _last_observation_position: Vector2 = Vector2.ZERO
var _last_observation_facing: Vector2 = Vector2.RIGHT
var _last_observation_animation: StringName = &""
var _last_observation_velocity: Vector2 = Vector2.ZERO
var _event_sequence: int = 0
var _is_recording: bool = false
var _samples: Array[TransformSample] = []
var _events: Array[RecordedEvent] = []


func configure(p_sample_rate_hz: float, p_history_duration_seconds: float) -> bool:
	if p_sample_rate_hz <= 0.0:
		push_error("RecallHistory sample rate must be greater than zero.")
		return false
	if p_history_duration_seconds <= 0.0:
		push_error("RecallHistory duration must be greater than zero.")
		return false
	sample_rate_hz = p_sample_rate_hz
	history_duration_seconds = p_history_duration_seconds
	_sample_interval = 1.0 / sample_rate_hz
	return true


func begin_branch(actor: Node2D, world_time: float) -> bool:
	if actor == null or not is_instance_valid(actor):
		push_error("RecallHistory requires a valid Node2D actor.")
		return false
	if world_time < 0.0:
		push_error("RecallHistory world time cannot be negative.")
		return false
	clear()
	_actor = actor
	_branch_start_time = world_time
	_logical_oldest_time = world_time
	_next_sample_time = world_time
	_last_observation_time = world_time
	_observe_actor()
	_append_observed_sample(world_time)
	_next_sample_time += _sample_interval
	_is_recording = true
	return true


func capture_until(world_time: float) -> void:
	if not _is_recording:
		return
	if _actor == null or not is_instance_valid(_actor):
		push_error("RecallHistory lost its actor while recording.")
		_is_recording = false
		return
	if world_time + TIMESTAMP_EPSILON < _last_observation_time:
		push_warning(
			"RecallHistory ignored non-monotonic time %.6f after %.6f."
			% [world_time, _last_observation_time]
		)
		return

	var current_position: Vector2 = _actor.global_position
	var current_facing: Vector2 = _read_facing_direction()
	var current_animation: StringName = _read_animation_state()
	var current_velocity: Vector2 = _read_velocity()
	var observation_span: float = world_time - _last_observation_time

	while _next_sample_time <= world_time + TIMESTAMP_EPSILON:
		var weight: float = 1.0
		if observation_span > TIMESTAMP_EPSILON:
			weight = clampf(
				(_next_sample_time - _last_observation_time) / observation_span,
				0.0,
				1.0
			)
		_samples.append(TransformSample.new(
			_next_sample_time,
			_last_observation_position.lerp(current_position, weight),
			_interpolate_facing(_last_observation_facing, current_facing, weight),
			current_animation if weight >= 0.5 else _last_observation_animation,
			_last_observation_velocity.lerp(current_velocity, weight)
		))
		_next_sample_time += _sample_interval

	_last_observation_time = world_time
	_last_observation_position = current_position
	_last_observation_facing = current_facing
	_last_observation_animation = current_animation
	_last_observation_velocity = current_velocity
	_prune_before(world_time - history_duration_seconds)


func record_event(
	world_time: float,
	target_id: StringName,
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	if not _is_recording:
		push_warning("RecallHistory ignored an event because no branch is active.")
		return false
	if world_time + TIMESTAMP_EPSILON < _branch_start_time:
		push_warning("RecallHistory ignored an event before the current branch start.")
		return false
	if world_time + TIMESTAMP_EPSILON < _last_observation_time:
		push_warning("RecallHistory ignored a non-chronological event timestamp.")
		return false
	if (
		not _events.is_empty()
		and world_time + TIMESTAMP_EPSILON < _events.back().timestamp
	):
		push_warning("RecallHistory ignored an event older than its previous event.")
		return false
	if target_id == StringName() or event_type == StringName():
		push_warning("RecallHistory requires non-empty target and event IDs.")
		return false
	if _payload_contains_object(payload):
		push_warning(
			"RecallHistory ignored event '%s' for '%s': payload contains an Object reference."
			% [event_type, target_id]
		)
		return false
	capture_until(world_time)
	_events.append(RecordedEvent.new(
		world_time,
		target_id,
		event_type,
		payload,
		_event_sequence
	))
	_event_sequence += 1
	_prune_before(world_time - history_duration_seconds)
	return true


func build_segment(
	from_world_time: float,
	to_world_time: float,
	source_index: int = 0
) -> LoopRecording:
	if to_world_time + TIMESTAMP_EPSILON < from_world_time:
		push_warning("RecallHistory cannot build a segment with decreasing time.")
		return LoopRecording.new(0.0, [], [], source_index)
	var safe_from: float = maxf(from_world_time, get_oldest_time())
	var safe_to: float = minf(to_world_time, get_newest_time())
	if safe_to + TIMESTAMP_EPSILON < safe_from or _samples.is_empty():
		return LoopRecording.new(0.0, [], [], source_index)

	var duration: float = maxf(0.0, safe_to - safe_from)
	var segment_samples: Array[TransformSample] = []
	var start_sample: TransformSample = _sample_at(safe_from)
	if start_sample != null:
		start_sample.timestamp = 0.0
		segment_samples.append(start_sample)
	for sample: TransformSample in _samples:
		if sample.timestamp <= safe_from + TIMESTAMP_EPSILON:
			continue
		if sample.timestamp >= safe_to - TIMESTAMP_EPSILON:
			break
		var copied_sample: TransformSample = sample.duplicate_sample()
		copied_sample.timestamp -= safe_from
		segment_samples.append(copied_sample)
	var end_sample: TransformSample = _sample_at(safe_to)
	if end_sample != null and (
		segment_samples.is_empty()
		or absf(segment_samples.back().timestamp - duration) > TIMESTAMP_EPSILON
	):
		end_sample.timestamp = duration
		segment_samples.append(end_sample)

	var segment_events: Array[RecordedEvent] = []
	for event: RecordedEvent in _events:
		# State at the restore snapshot already contains events committed at its
		# exact timestamp, so Echo playback begins strictly after that boundary.
		if event.timestamp <= safe_from + TIMESTAMP_EPSILON:
			continue
		if event.timestamp > safe_to + TIMESTAMP_EPSILON:
			break
		var copied_event: RecordedEvent = event.duplicate_event()
		copied_event.timestamp -= safe_from
		segment_events.append(copied_event)

	return LoopRecording.new(duration, segment_samples, segment_events, source_index)


func clear() -> void:
	_actor = null
	_branch_start_time = 0.0
	_logical_oldest_time = 0.0
	_next_sample_time = 0.0
	_last_observation_time = 0.0
	_last_observation_position = Vector2.ZERO
	_last_observation_facing = Vector2.RIGHT
	_last_observation_animation = StringName()
	_last_observation_velocity = Vector2.ZERO
	_event_sequence = 0
	_is_recording = false
	_samples.clear()
	_events.clear()


func is_recording() -> bool:
	return _is_recording


func get_sample_count() -> int:
	return _samples.size()


func get_event_count() -> int:
	return _events.size()


func get_oldest_time() -> float:
	return minf(_logical_oldest_time, get_newest_time())


func get_newest_time() -> float:
	return _last_observation_time if not _samples.is_empty() else _branch_start_time


func get_available_duration() -> float:
	return maxf(0.0, get_newest_time() - get_oldest_time())


func get_branch_start_time() -> float:
	return _branch_start_time


func _prune_before(cutoff_time: float) -> void:
	_logical_oldest_time = maxf(_branch_start_time, cutoff_time)
	# Keep one sample before the boundary so the exact rewind boundary can be
	# interpolated without retaining an unbounded history.
	while _samples.size() > 2 and _samples[1].timestamp < cutoff_time - TIMESTAMP_EPSILON:
		_samples.remove_at(0)
	while not _events.is_empty() and _events[0].timestamp < cutoff_time - TIMESTAMP_EPSILON:
		_events.remove_at(0)


func _sample_at(world_time: float) -> TransformSample:
	if _samples.is_empty():
		return null
	if world_time <= _samples[0].timestamp + TIMESTAMP_EPSILON:
		return _samples[0].duplicate_sample()
	for index: int in range(_samples.size() - 1):
		var from_sample: TransformSample = _samples[index]
		var to_sample: TransformSample = _samples[index + 1]
		if world_time > to_sample.timestamp + TIMESTAMP_EPSILON:
			continue
		var span: float = to_sample.timestamp - from_sample.timestamp
		if span <= TIMESTAMP_EPSILON:
			return to_sample.duplicate_sample()
		var weight: float = clampf(
			(world_time - from_sample.timestamp) / span,
			0.0,
			1.0
		)
		return TransformSample.new(
			world_time,
			from_sample.position.lerp(to_sample.position, weight),
			_interpolate_facing(
				from_sample.facing_direction,
				to_sample.facing_direction,
				weight
			),
			to_sample.animation_state if weight >= 0.5 else from_sample.animation_state,
			from_sample.velocity.lerp(to_sample.velocity, weight)
		)
	var last_sample: TransformSample = _samples.back()
	if (
		world_time > last_sample.timestamp + TIMESTAMP_EPSILON
		and _last_observation_time > last_sample.timestamp + TIMESTAMP_EPSILON
	):
		var final_weight: float = clampf(
			(world_time - last_sample.timestamp)
			/ (_last_observation_time - last_sample.timestamp),
			0.0,
			1.0
		)
		return TransformSample.new(
			world_time,
			last_sample.position.lerp(_last_observation_position, final_weight),
			_interpolate_facing(
				last_sample.facing_direction,
				_last_observation_facing,
				final_weight
			),
			_last_observation_animation
				if final_weight >= 0.5
				else last_sample.animation_state,
			last_sample.velocity.lerp(_last_observation_velocity, final_weight)
		)
	return _samples.back().duplicate_sample()


func _observe_actor() -> void:
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
		return StringName(str(_actor.call(&"get_recording_animation_state")))
	if _actor.has_method(&"get_animation_state"):
		return StringName(str(_actor.call(&"get_animation_state")))
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


static func _interpolate_facing(from: Vector2, to: Vector2, weight: float) -> Vector2:
	if from.is_zero_approx():
		return to.normalized() if not to.is_zero_approx() else Vector2.RIGHT
	if to.is_zero_approx():
		return from.normalized()
	return Vector2.RIGHT.rotated(lerp_angle(from.angle(), to.angle(), weight))


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
