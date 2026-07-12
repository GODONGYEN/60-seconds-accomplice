class_name ObjectRegistry
extends Node

signal registry_rebuilt(object_count: int, validation_succeeded: bool)

const DEFAULT_REGISTRY_GROUP: StringName = &"stable_object"

@export var registry_group: StringName = DEFAULT_REGISTRY_GROUP
@export var rebuild_on_ready: bool = false

var _objects: Dictionary[StringName, Node] = {}
var _last_rebuild_succeeded: bool = false


func _ready() -> void:
	if rebuild_on_ready:
		call_deferred(&"rebuild", get_parent())


func rebuild(level_root: Node = null) -> bool:
	_objects.clear()
	_last_rebuild_succeeded = true
	if registry_group == StringName():
		push_error("ObjectRegistry registry_group cannot be empty.")
		_last_rebuild_succeeded = false
		registry_rebuilt.emit(0, false)
		return false
	if not is_inside_tree():
		push_error("ObjectRegistry must be inside a SceneTree before rebuild().")
		_last_rebuild_succeeded = false
		registry_rebuilt.emit(0, false)
		return false

	var root: Node = level_root
	if root == null:
		root = get_parent()
	var candidates: Array[Node] = get_tree().get_nodes_in_group(registry_group)
	for candidate: Node in candidates:
		if root != null and candidate != root and not root.is_ancestor_of(candidate):
			continue
		var object_id: StringName = _extract_object_id(candidate)
		if object_id == StringName():
			push_error(
				"ObjectRegistry found '%s' in group '%s' without a non-empty stable object ID."
				% [_describe_node(candidate), registry_group]
			)
			_last_rebuild_succeeded = false
			continue
		if _objects.has(object_id):
			var existing: Node = _objects[object_id]
			push_error(
				"ObjectRegistry duplicate object ID '%s': '%s' conflicts with '%s'."
				% [object_id, _describe_node(existing), _describe_node(candidate)]
			)
			_last_rebuild_succeeded = false
			continue
		_objects[object_id] = candidate

	registry_rebuilt.emit(_objects.size(), _last_rebuild_succeeded)
	return _last_rebuild_succeeded


func register_object(object_id: StringName, object: Node) -> bool:
	if object_id == StringName():
		push_error("ObjectRegistry cannot register an empty object ID.")
		return false
	if object == null or not is_instance_valid(object):
		push_error("ObjectRegistry cannot register invalid object '%s'." % object_id)
		return false
	if _objects.has(object_id):
		push_error(
			"ObjectRegistry duplicate object ID '%s': '%s' conflicts with '%s'."
			% [object_id, _describe_node(_objects[object_id]), _describe_node(object)]
		)
		return false
	_objects[object_id] = object
	return true


func unregister_object(object_id: StringName, expected_object: Node = null) -> bool:
	if not _objects.has(object_id):
		return false
	if expected_object != null and _objects[object_id] != expected_object:
		push_warning(
			"ObjectRegistry refused to unregister '%s' because the registered node differs."
			% object_id
		)
		return false
	_objects.erase(object_id)
	return true


func get_object(object_id: StringName) -> Node:
	var object: Node = _objects.get(object_id) as Node
	if object != null and not is_instance_valid(object):
		_objects.erase(object_id)
		return null
	return object


func has_object(object_id: StringName) -> bool:
	return get_object(object_id) != null


func get_registered_count() -> int:
	return _objects.size()


func get_registered_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for object_id: StringName in _objects:
		result.append(object_id)
	result.sort()
	return result


func last_rebuild_succeeded() -> bool:
	return _last_rebuild_succeeded


func validate_registry() -> bool:
	var validation_succeeded: bool = _last_rebuild_succeeded
	if _objects.is_empty():
		push_error("ObjectRegistry validation failed because no stable objects are registered.")
		validation_succeeded = false
	for object_id: StringName in _objects:
		var registered_object: Node = _objects[object_id]
		if registered_object == null or not is_instance_valid(registered_object):
			push_error("ObjectRegistry entry '%s' points to an invalid node." % object_id)
			validation_succeeded = false
			continue
		var current_id: StringName = _extract_object_id(registered_object)
		if current_id != object_id:
			push_error(
				"ObjectRegistry entry '%s' changed its stable ID to '%s' on '%s'."
				% [object_id, current_id, _describe_node(registered_object)]
			)
			validation_succeeded = false
	return validation_succeeded


func clear_registry() -> void:
	_objects.clear()
	_last_rebuild_succeeded = false


func _extract_object_id(candidate: Node) -> StringName:
	if candidate.has_method(&"get_object_id"):
		var method_result: Variant = candidate.call(&"get_object_id")
		return StringName(str(method_result))
	for property_info: Dictionary in candidate.get_property_list():
		if StringName(str(property_info.get("name", ""))) == &"object_id":
			return StringName(str(candidate.get(&"object_id")))
	return StringName()


static func _describe_node(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "<invalid node>"
	if node.is_inside_tree():
		return str(node.get_path())
	return str(node.name)
