class_name RecordedEvent
extends RefCounted

const INTERACT: StringName = &"interact"
const INTERACTION_PRESSED: StringName = &"interaction_pressed"
const INTERACTION_RELEASED: StringName = &"interaction_released"

var timestamp: float = 0.0
var target_object_id: StringName = &""
var event_type: StringName = INTERACT
var payload: Dictionary = {}
var sequence: int = -1


func _init(
		p_timestamp: float = 0.0,
		p_target_object_id: StringName = &"",
		p_event_type: StringName = INTERACT,
		p_payload: Dictionary = {},
		p_sequence: int = -1
) -> void:
	timestamp = p_timestamp
	target_object_id = p_target_object_id
	event_type = p_event_type
	payload = p_payload.duplicate(true)
	sequence = p_sequence


func duplicate_event() -> RecordedEvent:
	return RecordedEvent.new(
		timestamp,
		target_object_id,
		event_type,
		payload,
		sequence
	)


static func is_interaction_event(value: StringName) -> bool:
	return value == INTERACT or value == INTERACTION_PRESSED
