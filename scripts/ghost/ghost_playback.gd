class_name GhostPlayback
extends AnimatableBody2D

const TIMESTAMP_EPSILON: float = 0.000001
const GHOST_COLLISION_LAYER: int = 4
const DETECTION_PRIORITY: int = 1

var display_loop_index: int = 0
var detection_prefix: StringName = &"ghost"
var display_prefix: String = "GHOST"
var playback_time: float = 0.0
var facing_direction: Vector2 = Vector2.RIGHT
var playback_velocity: Vector2 = Vector2.ZERO

var _recording: LoopRecording
var _registry: ObjectRegistry
var _next_event_index: int = 0
var _sample_index: int = 0
var _has_advanced: bool = false
var _warned_non_monotonic_time: bool = false

@onready var _visual: PlayerVisual = %VisualRoot
@onready var _loop_label: Label = get_node_or_null(^"LoopLabel") as Label


func _enter_tree() -> void:
	add_to_group(&"timeline_actor")
	add_to_group(&"ghost_actor")
	add_to_group(&"detectable_actor")


func _ready() -> void:
	collision_layer = GHOST_COLLISION_LAYER
	collision_mask = 0
	sync_to_physics = false
	_update_label()
	_visual.reset_visual(Vector2.DOWN)
	if _recording != null and not _recording.samples.is_empty():
		_apply_sample(_recording.samples[0])


func configure(
		recording: LoopRecording,
		registry: ObjectRegistry,
		p_display_loop_index: int
) -> bool:
	if recording == null:
		push_error("GhostPlayback cannot configure without a LoopRecording.")
		_recording = null
		_registry = registry
		return false
	_recording = recording.duplicate_recording()
	_registry = registry
	display_loop_index = maxi(0, p_display_loop_index)
	_update_label()
	reset_playback()
	return true


func configure_echo_segment(
		recording: LoopRecording,
		registry: ObjectRegistry,
		echo_sequence: int
) -> bool:
	detection_prefix = &"echo"
	display_prefix = "ECHO"
	return configure(recording, registry, echo_sequence)


func reset_playback() -> void:
	playback_time = 0.0
	_next_event_index = 0
	_sample_index = 0
	_has_advanced = false
	_warned_non_monotonic_time = false
	playback_velocity = Vector2.ZERO
	_visual.reset_visual(Vector2.DOWN)
	if _recording == null or _recording.samples.is_empty():
		return
	_apply_sample(_recording.samples[0])


func advance_to(timeline_time: float) -> void:
	if _recording == null:
		return
	var target_time: float = clampf(timeline_time, 0.0, _recording.duration)
	if _has_advanced and target_time + TIMESTAMP_EPSILON < playback_time:
		if not _warned_non_monotonic_time:
			push_warning(
				"GhostPlayback loop %d ignored non-monotonic time %.6f after %.6f; call reset_playback() first."
				% [display_loop_index, target_time, playback_time]
			)
			_warned_non_monotonic_time = true
		return

	playback_time = maxf(playback_time, target_time)
	_has_advanced = true
	_apply_transform_at(playback_time)
	_dispatch_events_through(playback_time)


func get_recording() -> LoopRecording:
	return _recording


func get_facing_direction() -> Vector2:
	return facing_direction


func get_visual() -> PlayerVisual:
	return _visual


func get_visibility_sample_position() -> Vector2:
	return global_position + Vector2(0.0, -18.0)


func get_detection_id() -> StringName:
	return StringName("%s_%03d" % [detection_prefix, display_loop_index])


func get_detection_priority() -> int:
	return DETECTION_PRIORITY


func is_detectable_by_guard() -> bool:
	return _recording != null and not is_playback_complete()


func is_playback_complete() -> bool:
	if _recording == null:
		return true
	return (
		playback_time + TIMESTAMP_EPSILON >= _recording.duration
		and _next_event_index >= _recording.events.size()
	)


func _apply_transform_at(target_time: float) -> void:
	if _recording.samples.is_empty():
		return
	while (
		_sample_index + 1 < _recording.samples.size()
		and _recording.samples[_sample_index + 1].timestamp <= target_time
	):
		_sample_index += 1

	var from_sample: TransformSample = _recording.samples[_sample_index]
	if _sample_index + 1 >= _recording.samples.size():
		_apply_terminal_sample(from_sample)
		return
	var to_sample: TransformSample = _recording.samples[_sample_index + 1]
	var span: float = to_sample.timestamp - from_sample.timestamp
	if span <= TIMESTAMP_EPSILON:
		_apply_sample(to_sample)
		return
	var weight: float = clampf((target_time - from_sample.timestamp) / span, 0.0, 1.0)
	global_position = from_sample.position.lerp(to_sample.position, weight)
	facing_direction = _interpolate_facing(
		from_sample.facing_direction,
		to_sample.facing_direction,
		weight
	)
	playback_velocity = from_sample.velocity.lerp(to_sample.velocity, weight)
	var animation_state := (
		to_sample.animation_state if weight >= 0.5 else from_sample.animation_state
	)
	_visual.update_motion(facing_direction, playback_velocity, animation_state)


func _apply_sample(sample: TransformSample) -> void:
	global_position = sample.position
	facing_direction = sample.facing_direction
	playback_velocity = sample.velocity
	_visual.update_motion(facing_direction, playback_velocity, sample.animation_state)


func _apply_terminal_sample(sample: TransformSample) -> void:
	global_position = sample.position
	facing_direction = sample.facing_direction
	playback_velocity = Vector2.ZERO
	_visual.update_motion(facing_direction, playback_velocity, &"idle")


func _dispatch_events_through(target_time: float) -> void:
	while _next_event_index < _recording.events.size():
		var event: RecordedEvent = _recording.events[_next_event_index]
		if event.timestamp > target_time + TIMESTAMP_EPSILON:
			break
		# Advance first so a target callback cannot re-enter and dispatch this event twice.
		_next_event_index += 1
		_dispatch_event(event)


func _dispatch_event(event: RecordedEvent) -> void:
	if RecordedEvent.is_interaction_event(event.event_type):
		_visual.play_interaction()
	if _registry == null or not is_instance_valid(_registry):
		push_warning(
			"GhostPlayback loop %d skipped event '%s': ObjectRegistry is unavailable."
			% [display_loop_index, event.event_type]
		)
		return
	var target: Node = _registry.get_object(event.target_object_id)
	if target == null:
		push_warning(
			"GhostPlayback loop %d skipped event '%s': target '%s' is not registered."
			% [display_loop_index, event.event_type, event.target_object_id]
		)
		return

	var replay_payload: Dictionary = event.payload.duplicate(true)
	if target.has_method(&"replay_event"):
		target.call(&"replay_event", event.event_type, self, replay_payload)
		return
	if not RecordedEvent.is_interaction_event(event.event_type):
		push_warning(
			"GhostPlayback loop %d target '%s' cannot replay event type '%s'."
			% [display_loop_index, event.target_object_id, event.event_type]
		)
		return
	if target.has_method(&"can_interact"):
		var can_interact_result: Variant = target.call(&"can_interact", self)
		if typeof(can_interact_result) == TYPE_BOOL and not bool(can_interact_result):
			return
	if not target.has_method(&"interact"):
		push_warning(
			"GhostPlayback loop %d target '%s' does not implement interact(actor)."
			% [display_loop_index, event.target_object_id]
		)
		return
	target.call(&"interact", self)


func _update_label() -> void:
	if _loop_label != null:
		_loop_label.text = "%s %d" % [display_prefix, display_loop_index]


static func _interpolate_facing(from: Vector2, to: Vector2, weight: float) -> Vector2:
	if from.is_zero_approx():
		return to.normalized() if not to.is_zero_approx() else Vector2.RIGHT
	if to.is_zero_approx():
		return from.normalized()
	return Vector2.RIGHT.rotated(lerp_angle(from.angle(), to.angle(), weight))
