class_name ObjectiveItem
extends Interactable

signal collected(actor: Node)

const CORE_COLOR := Color("ffcf4a")
const CORE_GLOW_COLOR := Color(1.0, 0.81, 0.29, 0.25)

@onready var collision_shape: CollisionShape2D = %CollisionShape2D

var is_collected: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group("loop_resettable")
	queue_redraw()


func _process(delta: float) -> void:
	if is_collected:
		return
	_pulse_time = fmod(_pulse_time + delta, TAU)
	queue_redraw()


func can_interact(actor: Node) -> bool:
	return not is_collected and actor.is_in_group("player_actor")


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	is_collected = true
	visible = false
	monitorable = false
	collision_shape.set_deferred("disabled", true)
	collected.emit(actor)
	return true


func reset_for_loop() -> void:
	is_collected = false
	_pulse_time = 0.0
	visible = true
	monitorable = true
	collision_shape.set_deferred("disabled", false)
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + sin(_pulse_time * 2.0) * 0.12
	draw_circle(Vector2.ZERO, 30.0 * pulse, CORE_GLOW_COLOR)
	draw_circle(Vector2.ZERO, 16.0, CORE_COLOR)
	draw_circle(Vector2.ZERO, 8.0, Color.WHITE)
	draw_line(Vector2(-23.0, 0.0), Vector2(23.0, 0.0), CORE_COLOR, 2.0)
	draw_line(Vector2(0.0, -23.0), Vector2(0.0, 23.0), CORE_COLOR, 2.0)

