class_name SecurityTerminal
extends Interactable

signal activated(actor: Node)

const INACTIVE_SCREEN := Color(0.18, 0.83, 0.92, 0.95)
const ACTIVE_SCREEN := Color(0.25, 1.0, 0.62, 0.95)

var is_activated: bool = false


func _ready() -> void:
	super._ready()
	add_to_group(&"loop_resettable")
	queue_redraw()


func can_interact(actor: Node) -> bool:
	return (
		not is_activated
		and (actor.is_in_group(&"player_actor") or actor.is_in_group(&"ghost_actor"))
	)


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	is_activated = true
	queue_redraw()
	activated.emit(actor)
	return true


func get_interaction_prompt(_actor: Node) -> String:
	return "E  DISABLE LASER GRID" if not is_activated else "LASER GRID DISABLED"


func reset_for_loop() -> void:
	is_activated = false
	queue_redraw()


func get_visibility_sample_position() -> Vector2:
	return global_position + Vector2(0.0, -12.0)


func _draw() -> void:
	draw_rect(Rect2(-22.0, -25.0, 44.0, 50.0), Color("17263a"), true)
	draw_rect(Rect2(-18.0, -21.0, 36.0, 26.0), Color("081521"), true)
	var screen_color := ACTIVE_SCREEN if is_activated else INACTIVE_SCREEN
	draw_rect(Rect2(-14.0, -17.0, 28.0, 18.0), Color(screen_color, 0.38), true)
	draw_line(Vector2(-10.0, -8.0), Vector2(10.0, -8.0), screen_color, 2.0)
	draw_circle(Vector2(0.0, 15.0), 4.0, screen_color)
