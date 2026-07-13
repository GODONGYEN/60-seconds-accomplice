class_name PlayerVisual
extends Node2D

signal interaction_animation_finished

const MOVEMENT_THRESHOLD_SQUARED: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var objective_indicator: CanvasItem = get_node_or_null(^"ObjectiveIndicator") as CanvasItem

var _last_facing: CharacterAnimationNames.Facing = CharacterAnimationNames.Facing.DOWN
var _last_facing_vector: Vector2 = Vector2.DOWN
var _last_velocity: Vector2 = Vector2.ZERO
var _recorded_state: StringName = &"idle"
var _is_interacting: bool = false


func _ready() -> void:
	animated_sprite.animation_finished.connect(_on_animation_finished)
	reset_visual(Vector2.DOWN)


func update_motion(
	facing_direction: Vector2,
	velocity: Vector2,
	recorded_state: StringName = StringName()
) -> void:
	_last_facing_vector = (
		facing_direction.normalized()
		if not facing_direction.is_zero_approx()
		else CharacterAnimationNames.to_vector(_last_facing)
	)
	_last_velocity = velocity
	_recorded_state = recorded_state
	var direction_source := _last_facing_vector
	if _is_moving():
		direction_source = velocity if not velocity.is_zero_approx() else _last_facing_vector
	_last_facing = CharacterAnimationNames.from_vector(direction_source, _last_facing)
	if not _is_interacting:
		_apply_motion_animation()


func play_interaction() -> void:
	_is_interacting = true
	_play_if_changed(CharacterAnimationNames.interact(_last_facing), true)


func reset_visual(facing_direction: Vector2 = Vector2.DOWN) -> void:
	_last_facing = CharacterAnimationNames.from_vector(
		facing_direction,
		CharacterAnimationNames.Facing.DOWN
	)
	_last_facing_vector = CharacterAnimationNames.to_vector(_last_facing)
	_last_velocity = Vector2.ZERO
	_recorded_state = &"idle"
	_is_interacting = false
	if is_instance_valid(animated_sprite):
		animated_sprite.stop()
		animated_sprite.animation = CharacterAnimationNames.idle(_last_facing)
		animated_sprite.frame = 0
		animated_sprite.play()
	set_objective_visible(false)


func set_objective_visible(visible: bool) -> void:
	if objective_indicator != null:
		objective_indicator.visible = visible


func get_current_animation() -> StringName:
	return animated_sprite.animation


func get_sprite_frames() -> SpriteFrames:
	return animated_sprite.sprite_frames


func get_facing() -> CharacterAnimationNames.Facing:
	return _last_facing


func is_interacting() -> bool:
	return _is_interacting


func _is_moving() -> bool:
	if _recorded_state == &"moving":
		return true
	if _recorded_state == &"idle":
		return false
	return _last_velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED


func _apply_motion_animation() -> void:
	var animation := CharacterAnimationNames.idle(_last_facing)
	if _is_moving():
		animation = CharacterAnimationNames.walk(_last_facing)
	_play_if_changed(animation)


func _play_if_changed(animation: StringName, restart: bool = false) -> void:
	if restart:
		animated_sprite.stop()
		animated_sprite.animation = animation
		animated_sprite.frame = 0
		animated_sprite.play()
	elif animated_sprite.animation != animation:
		animated_sprite.play(animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()


func _on_animation_finished() -> void:
	if not _is_interacting:
		return
	_is_interacting = false
	_apply_motion_animation()
	interaction_animation_finished.emit()
