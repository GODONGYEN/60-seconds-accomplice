class_name GuardVisual
extends Node2D

const MOVEMENT_THRESHOLD_SQUARED: float = 1.0
const CONE_SEGMENTS: int = 18
const CONE_NEUTRAL := Color(0.28, 0.78, 0.92, 0.11)
const CONE_SUSPICIOUS := Color(1.0, 0.58, 0.18, 0.18)
const CONE_CHASE := Color(1.0, 0.18, 0.22, 0.24)
const CONE_SEARCH := Color(1.0, 0.58, 0.18, 0.13)

@onready var animated_sprite: AnimatedSprite2D = %AnimatedSprite2D
@onready var alert_indicator: Label = %AlertIndicator
@onready var suspicion_meter: ProgressBar = %SuspicionMeter
@onready var vision_cone_root: Node2D = %VisionConeRoot
@onready var vision_cone: Polygon2D = %VisionCone
@onready var debug_label: Label = %DebugLabel

var _last_facing: CharacterAnimationNames.Facing = CharacterAnimationNames.Facing.DOWN
var _last_facing_vector: Vector2 = Vector2.DOWN
var _is_alerted: bool = false
var _state_name: StringName = &"idle"


func _ready() -> void:
	reset_visual(Vector2.DOWN)


func configure_vision(distance: float, half_angle_degrees: float) -> void:
	var points := PackedVector2Array([Vector2.ZERO])
	var half_angle := deg_to_rad(half_angle_degrees)
	for index: int in range(CONE_SEGMENTS + 1):
		var weight := float(index) / float(CONE_SEGMENTS)
		var angle := lerpf(-half_angle, half_angle, weight)
		points.append(Vector2.RIGHT.rotated(angle) * distance)
	vision_cone.polygon = points


func update_state(
	facing_direction: Vector2,
	velocity: Vector2,
	state_name: StringName,
	suspicion: float
) -> void:
	var direction_source := facing_direction
	if velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED:
		direction_source = velocity
	_last_facing = CharacterAnimationNames.from_vector(direction_source, _last_facing)
	_last_facing_vector = (
		facing_direction.normalized()
		if not facing_direction.is_zero_approx()
		else CharacterAnimationNames.to_vector(_last_facing)
	)
	_state_name = state_name
	_is_alerted = state_name == &"chase"
	vision_cone_root.rotation = _last_facing_vector.angle()
	_update_awareness_feedback(clampf(suspicion, 0.0, 1.0))
	var animation := CharacterAnimationNames.idle(_last_facing)
	if state_name == &"suspicious" or state_name == &"chase" or state_name == &"search":
		animation = CharacterAnimationNames.alert(_last_facing)
	elif velocity.length_squared() > MOVEMENT_THRESHOLD_SQUARED:
		animation = CharacterAnimationNames.walk(_last_facing)
	_play_if_changed(animation)


func reset_visual(facing_direction: Vector2 = Vector2.DOWN) -> void:
	_last_facing = CharacterAnimationNames.from_vector(
		facing_direction,
		CharacterAnimationNames.Facing.DOWN
	)
	_last_facing_vector = CharacterAnimationNames.to_vector(_last_facing)
	_is_alerted = false
	_state_name = &"idle"
	if is_instance_valid(alert_indicator):
		alert_indicator.visible = false
		alert_indicator.text = "?"
	if is_instance_valid(suspicion_meter):
		suspicion_meter.visible = false
		suspicion_meter.value = 0.0
	if is_instance_valid(vision_cone_root):
		vision_cone_root.rotation = _last_facing_vector.angle()
	if is_instance_valid(vision_cone):
		vision_cone.color = CONE_NEUTRAL
	if is_instance_valid(debug_label):
		debug_label.visible = false
		debug_label.text = ""
	if is_instance_valid(animated_sprite):
		animated_sprite.stop()
		animated_sprite.animation = CharacterAnimationNames.idle(_last_facing)
		animated_sprite.frame = 0
		animated_sprite.play()


func set_debug_data(message: String, enabled: bool) -> void:
	debug_label.text = message
	debug_label.visible = enabled


func get_current_animation() -> StringName:
	return animated_sprite.animation


func get_sprite_frames() -> SpriteFrames:
	return animated_sprite.sprite_frames


func is_alerted() -> bool:
	return _is_alerted


func get_state_name() -> StringName:
	return _state_name


func get_indicator_text() -> String:
	return alert_indicator.text


func get_vision_polygon() -> PackedVector2Array:
	return vision_cone.polygon


func get_cone_color() -> Color:
	return vision_cone.color


func set_animation_paused(paused: bool) -> void:
	animated_sprite.speed_scale = 0.0 if paused else 1.0
	if not paused and not animated_sprite.is_playing():
		animated_sprite.play()


func _update_awareness_feedback(suspicion: float) -> void:
	suspicion_meter.value = suspicion * 100.0
	suspicion_meter.visible = suspicion > 0.001 or _state_name == &"chase"
	match _state_name:
		&"suspicious":
			alert_indicator.visible = true
			alert_indicator.text = "?"
			alert_indicator.modulate = Color("ff9b3d")
			vision_cone.color = CONE_SUSPICIOUS
		&"chase":
			alert_indicator.visible = true
			alert_indicator.text = "!"
			alert_indicator.modulate = Color("ff3f52")
			vision_cone.color = CONE_CHASE
		&"search":
			alert_indicator.visible = true
			alert_indicator.text = "?"
			alert_indicator.modulate = Color("ffb04d")
			vision_cone.color = CONE_SEARCH
		_:
			alert_indicator.visible = false
			alert_indicator.text = "?"
			vision_cone.color = CONE_NEUTRAL


func _play_if_changed(animation: StringName) -> void:
	if animated_sprite.animation != animation:
		animated_sprite.play(animation)
	elif not animated_sprite.is_playing():
		animated_sprite.play()
