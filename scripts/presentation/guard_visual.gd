class_name GuardVisual
extends Node2D

const MOVEMENT_THRESHOLD_SQUARED: float = 1.0

@onready var animated_sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var alert_indicator: CanvasItem = %AlertIndicator

var _last_facing: CharacterAnimationNames.Facing = CharacterAnimationNames.Facing.DOWN
var _is_alerted: bool = false


func _ready() -> void:
	reset_visual(Vector2.DOWN)


func update_state(facing_direction: Vector2, velocity: Vector2, alerted: bool) -> void:
	var direction_source := facing_direction
	if velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED:
		direction_source = velocity
	_last_facing = CharacterAnimationNames.from_vector(direction_source, _last_facing)
	_is_alerted = alerted
	alert_indicator.visible = alerted
	var animation := CharacterAnimationNames.idle(_last_facing)
	if alerted:
		animation = CharacterAnimationNames.alert(_last_facing)
	elif velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED:
		animation = CharacterAnimationNames.walk(_last_facing)
	_play_if_changed(animation)


func reset_visual(facing_direction: Vector2 = Vector2.DOWN) -> void:
	_last_facing = CharacterAnimationNames.from_vector(
		facing_direction,
		CharacterAnimationNames.Facing.DOWN
	)
	_is_alerted = false
	if is_instance_valid(alert_indicator):
		alert_indicator.visible = false
	if is_instance_valid(animated_sprite):
		animated_sprite.stop()
		animated_sprite.animation = CharacterAnimationNames.idle(_last_facing)
		animated_sprite.frame = 0
		animated_sprite.play()


func get_current_animation() -> StringName:
	return animated_sprite.animation


func get_sprite_frames() -> SpriteFrames:
	return animated_sprite.sprite_frames


func is_alerted() -> bool:
	return _is_alerted


func set_animation_paused(paused: bool) -> void:
	animated_sprite.speed_scale = 0.0 if paused else 1.0
	if not paused and not animated_sprite.is_playing():
		animated_sprite.play()


func _play_if_changed(animation: StringName) -> void:
	if animated_sprite.animation != animation:
		animated_sprite.play(animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()
