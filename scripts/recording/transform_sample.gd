class_name TransformSample
extends RefCounted

var timestamp: float = 0.0
var position: Vector2 = Vector2.ZERO
var facing_direction: Vector2 = Vector2.RIGHT
var animation_state: StringName = &""
var velocity: Vector2 = Vector2.ZERO


func _init(
		p_timestamp: float = 0.0,
		p_position: Vector2 = Vector2.ZERO,
		p_facing_direction: Vector2 = Vector2.RIGHT,
		p_animation_state: StringName = &"",
		p_velocity: Vector2 = Vector2.ZERO
) -> void:
	timestamp = p_timestamp
	position = p_position
	facing_direction = _safe_facing(p_facing_direction)
	animation_state = p_animation_state
	velocity = p_velocity


func duplicate_sample() -> TransformSample:
	return TransformSample.new(
		timestamp,
		position,
		facing_direction,
		animation_state,
		velocity
	)


static func _safe_facing(value: Vector2) -> Vector2:
	if value.is_zero_approx():
		return Vector2.RIGHT
	return value.normalized()
