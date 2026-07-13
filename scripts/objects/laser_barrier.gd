class_name LaserBarrier
extends Area2D

signal active_changed(is_active: bool)
signal tripped(player: PlayerController)

const ACTIVE_COLOR := Color(1.0, 0.16, 0.22, 0.95)
const DISABLED_COLOR := Color(0.2, 0.86, 0.78, 0.75)

@export var object_id: StringName = &"laser_right_01"
@export var starts_active: bool = true

@onready var trigger_shape: CollisionShape2D = %TriggerShape

var is_active: bool = true
var _trip_committed: bool = false


func _ready() -> void:
	add_to_group(&"stable_object")
	add_to_group(&"loop_resettable")
	body_entered.connect(_on_body_entered)
	_apply_active_state(starts_active, true)


func get_object_id() -> StringName:
	return object_id


func set_active(value: bool) -> void:
	_apply_active_state(value)


func reset_for_loop() -> void:
	_trip_committed = false
	_apply_active_state(starts_active, true)


func get_visibility_sample_position() -> Vector2:
	return global_position


func _on_body_entered(body: Node2D) -> void:
	if not is_active or _trip_committed:
		return
	var player := body as PlayerController
	if player == null or not player.is_in_group(&"player_actor"):
		return
	_trip_committed = true
	tripped.emit(player)


func _apply_active_state(value: bool, force: bool = false) -> void:
	if not force and is_active == value:
		return
	is_active = value
	monitoring = is_active
	trigger_shape.set_deferred(&"disabled", not is_active)
	queue_redraw()
	active_changed.emit(is_active)


func _draw() -> void:
	var emitter_color := ACTIVE_COLOR if is_active else DISABLED_COLOR
	draw_rect(Rect2(-12.0, -52.0, 24.0, 12.0), Color("28384d"), true)
	draw_rect(Rect2(-12.0, 40.0, 24.0, 12.0), Color("28384d"), true)
	draw_circle(Vector2(0.0, -46.0), 4.0, emitter_color)
	draw_circle(Vector2(0.0, 46.0), 4.0, emitter_color)
	if not is_active:
		draw_line(Vector2(-7.0, 0.0), Vector2(7.0, 0.0), emitter_color, 3.0)
		return
	for x_offset: float in [-4.0, 0.0, 4.0]:
		draw_line(
			Vector2(x_offset, -42.0),
			Vector2(x_offset, 42.0),
			Color(ACTIVE_COLOR, 0.55 if x_offset != 0.0 else 0.95),
			2.0
		)
