class_name CharacterAnimationNames
extends RefCounted

enum Facing {
	DOWN,
	LEFT,
	RIGHT,
	UP,
}

const IDLE_DOWN: StringName = &"idle_down"
const IDLE_LEFT: StringName = &"idle_left"
const IDLE_RIGHT: StringName = &"idle_right"
const IDLE_UP: StringName = &"idle_up"

const WALK_DOWN: StringName = &"walk_down"
const WALK_LEFT: StringName = &"walk_left"
const WALK_RIGHT: StringName = &"walk_right"
const WALK_UP: StringName = &"walk_up"

const INTERACT_DOWN: StringName = &"interact_down"
const INTERACT_LEFT: StringName = &"interact_left"
const INTERACT_RIGHT: StringName = &"interact_right"
const INTERACT_UP: StringName = &"interact_up"

const ALERT_DOWN: StringName = &"alert_down"
const ALERT_LEFT: StringName = &"alert_left"
const ALERT_RIGHT: StringName = &"alert_right"
const ALERT_UP: StringName = &"alert_up"

const IDLE_BY_FACING: Dictionary = {
	Facing.DOWN: IDLE_DOWN,
	Facing.LEFT: IDLE_LEFT,
	Facing.RIGHT: IDLE_RIGHT,
	Facing.UP: IDLE_UP,
}
const WALK_BY_FACING: Dictionary = {
	Facing.DOWN: WALK_DOWN,
	Facing.LEFT: WALK_LEFT,
	Facing.RIGHT: WALK_RIGHT,
	Facing.UP: WALK_UP,
}
const INTERACT_BY_FACING: Dictionary = {
	Facing.DOWN: INTERACT_DOWN,
	Facing.LEFT: INTERACT_LEFT,
	Facing.RIGHT: INTERACT_RIGHT,
	Facing.UP: INTERACT_UP,
}
const ALERT_BY_FACING: Dictionary = {
	Facing.DOWN: ALERT_DOWN,
	Facing.LEFT: ALERT_LEFT,
	Facing.RIGHT: ALERT_RIGHT,
	Facing.UP: ALERT_UP,
}


static func from_vector(direction: Vector2, fallback: Facing = Facing.DOWN) -> Facing:
	if direction.is_zero_approx():
		return fallback
	var horizontal_strength: float = absf(direction.x)
	var vertical_strength: float = absf(direction.y)
	if is_equal_approx(horizontal_strength, vertical_strength):
		return fallback
	if horizontal_strength > vertical_strength:
		return Facing.RIGHT if direction.x > 0.0 else Facing.LEFT
	return Facing.DOWN if direction.y > 0.0 else Facing.UP


static func idle(facing: Facing) -> StringName:
	return StringName(IDLE_BY_FACING.get(facing, IDLE_DOWN))


static func walk(facing: Facing) -> StringName:
	return StringName(WALK_BY_FACING.get(facing, WALK_DOWN))


static func interact(facing: Facing) -> StringName:
	return StringName(INTERACT_BY_FACING.get(facing, INTERACT_DOWN))


static func alert(facing: Facing) -> StringName:
	return StringName(ALERT_BY_FACING.get(facing, ALERT_DOWN))


static func to_vector(facing: Facing) -> Vector2:
	match facing:
		Facing.LEFT:
			return Vector2.LEFT
		Facing.RIGHT:
			return Vector2.RIGHT
		Facing.UP:
			return Vector2.UP
		_:
			return Vector2.DOWN
