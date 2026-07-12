class_name LoopRecording
extends RefCounted

const TIMESTAMP_EPSILON: float = 0.000001

var duration: float = 0.0
var loop_index: int = 0
var samples: Array[TransformSample] = []
var events: Array[RecordedEvent] = []

# Kept as a read alias because the architecture document calls these snapshots.
var snapshots: Array[TransformSample]:
	get:
		return samples


func _init(
		p_duration: float = 0.0,
		p_samples: Array[TransformSample] = [],
		p_events: Array[RecordedEvent] = [],
		p_loop_index: int = 0
) -> void:
	duration = maxf(0.0, p_duration)
	loop_index = maxi(0, p_loop_index)
	_warn_if_source_order_is_invalid(p_samples, p_events)
	_copy_samples(p_samples)
	_copy_events(p_events)
	samples.sort_custom(_sample_comes_before)
	events.sort_custom(_event_comes_before)


func _warn_if_source_order_is_invalid(
	source_samples: Array[TransformSample],
	source_events: Array[RecordedEvent]
) -> void:
	for index: int in range(1, source_samples.size()):
		var previous_sample := source_samples[index - 1]
		var current_sample := source_samples[index]
		if (
			previous_sample != null
			and current_sample != null
			and current_sample.timestamp + TIMESTAMP_EPSILON < previous_sample.timestamp
		):
			push_warning(
				"LoopRecording received transform samples out of timestamp order; sorting a defensive copy."
			)
			break
	for index: int in range(1, source_events.size()):
		var previous_event := source_events[index - 1]
		var current_event := source_events[index]
		if (
			previous_event != null
			and current_event != null
			and current_event.timestamp + TIMESTAMP_EPSILON < previous_event.timestamp
		):
			push_warning(
				"LoopRecording received discrete events out of timestamp order; sorting a defensive copy."
			)
			break


func duplicate_recording() -> LoopRecording:
	return LoopRecording.new(duration, samples, events, loop_index)


func is_empty() -> bool:
	return samples.is_empty() and events.is_empty()


func is_chronological() -> bool:
	for index: int in range(1, samples.size()):
		if samples[index].timestamp + TIMESTAMP_EPSILON < samples[index - 1].timestamp:
			return false
	for index: int in range(1, events.size()):
		var previous: RecordedEvent = events[index - 1]
		var current: RecordedEvent = events[index]
		if current.timestamp + TIMESTAMP_EPSILON < previous.timestamp:
			return false
		if is_equal_approx(current.timestamp, previous.timestamp) and current.sequence < previous.sequence:
			return false
	return true


func _copy_samples(source_samples: Array[TransformSample]) -> void:
	samples.clear()
	for source: TransformSample in source_samples:
		if source == null:
			push_warning("LoopRecording ignored a null transform sample.")
			continue
		var copied: TransformSample = source.duplicate_sample()
		copied.timestamp = _normalize_timestamp(copied.timestamp, "transform sample")
		samples.append(copied)


func _copy_events(source_events: Array[RecordedEvent]) -> void:
	events.clear()
	var source_order: int = 0
	for source: RecordedEvent in source_events:
		if source == null:
			push_warning("LoopRecording ignored a null recorded event.")
			continue
		var copied: RecordedEvent = source.duplicate_event()
		copied.timestamp = _normalize_timestamp(copied.timestamp, "recorded event")
		# Array order is the authoritative tie breaker for equal timestamps.
		copied.sequence = source_order
		events.append(copied)
		source_order += 1


func _normalize_timestamp(value: float, value_kind: String) -> float:
	if value < 0.0:
		push_warning("LoopRecording clamped negative %s timestamp %.6f." % [value_kind, value])
		return 0.0
	if value > duration:
		push_warning(
			"LoopRecording clamped %s timestamp %.6f to duration %.6f."
			% [value_kind, value, duration]
		)
		return duration
	return value


static func _sample_comes_before(a: TransformSample, b: TransformSample) -> bool:
	return a.timestamp < b.timestamp


static func _event_comes_before(a: RecordedEvent, b: RecordedEvent) -> bool:
	if a.timestamp == b.timestamp:
		return a.sequence < b.sequence
	return a.timestamp < b.timestamp
