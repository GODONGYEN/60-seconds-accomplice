class_name GuardController
extends CharacterBody2D

enum GuardState {
	PATROL,
	SUSPICIOUS,
	CHASE,
	ALERT,
}

@export_range(0.0, 200.0, 1.0) var patrol_speed: float = 36.0
@export_range(8.0, 160.0, 1.0) var patrol_half_distance: float = 48.0
@export var initial_facing: Vector2 = Vector2.RIGHT

@onready var visual: GuardVisual = %VisualRoot

var state: GuardState = GuardState.PATROL
var _initial_position: Vector2 = Vector2.ZERO
var _patrol_time: float = 0.0
var _simulation_enabled: bool = true


func _ready() -> void:
	add_to_group(&"loop_resettable")
	_initial_position = position
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	reset_for_loop()


func _physics_process(delta: float) -> void:
	if state != GuardState.PATROL or patrol_speed <= 0.0:
		velocity = initial_facing.normalized() * patrol_speed if state == GuardState.CHASE else Vector2.ZERO
		var alerted := state == GuardState.ALERT or state == GuardState.SUSPICIOUS
		visual.update_state(initial_facing, velocity, alerted)
		return
	_patrol_time += maxf(0.0, delta)
	var cycle_distance: float = patrol_half_distance * 4.0
	var distance: float = fmod(_patrol_time * patrol_speed, cycle_distance)
	var offset: float = distance
	var direction := Vector2.RIGHT
	if distance > patrol_half_distance and distance < patrol_half_distance * 3.0:
		offset = patrol_half_distance * 2.0 - distance
		direction = Vector2.LEFT
	elif distance >= patrol_half_distance * 3.0:
		offset = distance - patrol_half_distance * 4.0
	position = _initial_position + Vector2(offset, 0.0)
	velocity = direction * patrol_speed
	visual.update_state(direction, velocity, false)


func set_guard_state(new_state: GuardState) -> void:
	state = new_state
	var alerted := state == GuardState.ALERT or state == GuardState.SUSPICIOUS
	visual.update_state(initial_facing, velocity, alerted)


func reset_for_loop() -> void:
	state = GuardState.PATROL
	_patrol_time = 0.0
	position = _initial_position
	velocity = Vector2.ZERO
	set_simulation_enabled(true)
	if is_instance_valid(visual):
		visual.reset_visual(initial_facing)


func get_visual() -> GuardVisual:
	return visual


func set_simulation_enabled(enabled: bool) -> void:
	_simulation_enabled = enabled
	set_physics_process(enabled)
	if not enabled:
		velocity = Vector2.ZERO
	if is_instance_valid(visual):
		visual.set_animation_paused(not enabled)


func is_simulation_enabled() -> bool:
	return _simulation_enabled
