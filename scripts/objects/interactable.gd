class_name Interactable
extends Area2D

@export var object_id: StringName


func _ready() -> void:
	add_to_group("stable_object")
	add_to_group("interactable")


func get_object_id() -> StringName:
	return object_id


func can_interact(_actor: Node) -> bool:
	return false


func interact(_actor: Node) -> bool:
	push_warning("Interactable.interact() must be overridden for object_id=%s" % object_id)
	return false


func replay_event(event_type: StringName, actor: Node, _payload: Dictionary) -> bool:
	if event_type != &"interact":
		return false
	if not can_interact(actor):
		return false
	return interact(actor)

