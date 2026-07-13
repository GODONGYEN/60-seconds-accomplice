class_name AccessCard
extends Interactable

signal collected(actor: Node, access_level: AccessControlManager.AccessLevel, card_id: StringName)

const LEVEL_COLORS: Dictionary = {
	AccessControlManager.AccessLevel.LEVEL_1: Color("52d8eb"),
	AccessControlManager.AccessLevel.LEVEL_2: Color("ffae45"),
	AccessControlManager.AccessLevel.VAULT: Color("c889ff"),
}

@export var access_level: AccessControlManager.AccessLevel = AccessControlManager.AccessLevel.LEVEL_1

@onready var collision_shape: CollisionShape2D = %CollisionShape2D

var is_collected: bool = false


func _ready() -> void:
	super._ready()
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	queue_redraw()


func can_interact(actor: Node) -> bool:
	return not is_collected and actor != null and actor.is_in_group(&"player_actor")


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	is_collected = true
	visible = false
	monitorable = false
	collision_shape.set_deferred(&"disabled", true)
	collected.emit(actor, access_level, object_id)
	return true


func get_interaction_prompt(_actor: Node) -> String:
	return "E  TAKE %s ACCESS CARD" % AccessControlManager.ACCESS_NAMES.get(
		access_level,
		&"SECURITY"
	)


func reset_mission() -> void:
	_apply_collected(false)


func capture_recall_state() -> Dictionary:
	return {"is_collected": is_collected}


func restore_recall_state(snapshot: Dictionary) -> bool:
	_apply_collected(bool(snapshot.get("is_collected", false)))
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _apply_collected(value: bool) -> void:
	is_collected = value
	visible = not value
	monitorable = not value
	collision_shape.set_deferred(&"disabled", value)
	queue_redraw()


func _draw() -> void:
	var accent: Color = LEVEL_COLORS.get(access_level, Color.WHITE)
	draw_rect(Rect2(-18.0, -11.0, 36.0, 22.0), Color("122438"), true)
	draw_rect(Rect2(-14.0, -7.0, 28.0, 14.0), Color(accent, 0.28), true)
	draw_circle(Vector2(-9.0, 0.0), 3.0, accent)
	draw_line(Vector2(-2.0, 0.0), Vector2(11.0, 0.0), accent, 3.0)
