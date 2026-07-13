class_name RewindStateRegistry
extends RefCounted

signal registry_changed(entry_count: int)
signal snapshot_failed(message: String)

const DEFAULT_GROUP: StringName = &"recall_rewindable"
const MAX_STATE_DEPTH: int = 24

enum RestorePhase {
	MANAGERS = 0,
	WORLD = 100,
	ACTORS = 200,
	OBJECTIVES = 300,
}

var _entries: Array[Dictionary] = []
var _nodes_by_id: Dictionary[StringName, Node] = {}


func rebuild_from_group(
	root: Node,
	group_name: StringName = DEFAULT_GROUP
) -> bool:
	clear()
	if root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return _fail("RewindStateRegistry requires an in-tree root for group discovery.")
	if group_name == StringName():
		return _fail("RewindStateRegistry group name cannot be empty.")
	var succeeded: bool = true
	for candidate: Node in root.get_tree().get_nodes_in_group(group_name):
		if candidate != root and not root.is_ancestor_of(candidate):
			continue
		if not register_rewindable(candidate):
			succeeded = false
	_sort_entries()
	registry_changed.emit(_entries.size())
	return succeeded and validate_registry()


func register_rewindable(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return _fail("RewindStateRegistry cannot register an invalid node.")
	var capture_method: StringName = _find_capture_method(node)
	var restore_method: StringName = _find_restore_method(node)
	if capture_method == StringName():
		return _fail(
			"Rewindable '%s' has no capture_rewind_state() or capture_recall_state()."
			% _describe(node)
		)
	if restore_method == StringName():
		return _fail(
			"Rewindable '%s' has no restore_rewind_state() or restore_recall_state()."
			% _describe(node)
		)
	var rewind_id: StringName = _read_rewind_id(node)
	if rewind_id == StringName():
		return _fail("Rewindable '%s' has an empty stable rewind ID." % _describe(node))
	if _nodes_by_id.has(rewind_id):
		return _fail(
			"Duplicate rewind ID '%s': '%s' conflicts with '%s'."
			% [rewind_id, _describe(_nodes_by_id[rewind_id]), _describe(node)]
		)
	var phase: int = RestorePhase.WORLD
	if node.has_method(&"get_rewind_restore_phase"):
		phase = int(node.call(&"get_rewind_restore_phase"))
	elif node.has_method(&"get_recall_restore_phase"):
		phase = int(node.call(&"get_recall_restore_phase"))
	_entries.append({
		"id": rewind_id,
		"node": node,
		"phase": phase,
		"capture_method": capture_method,
		"restore_method": restore_method,
	})
	_nodes_by_id[rewind_id] = node
	_sort_entries()
	registry_changed.emit(_entries.size())
	return true


func register_contracts_under(root: Node) -> bool:
	if root == null or not is_instance_valid(root):
		return _fail("RewindStateRegistry cannot scan an invalid root.")
	var candidates: Array[Node] = [root]
	for descendant: Node in root.find_children("*", "", true, false):
		candidates.append(descendant)
	candidates.sort_custom(
		func(left: Node, right: Node) -> bool:
			return _describe(left) < _describe(right)
	)
	var succeeded: bool = true
	for candidate: Node in candidates:
		if has_rewindable_node(candidate):
			continue
		if _find_capture_method(candidate) == StringName():
			continue
		if _find_restore_method(candidate) == StringName():
			continue
		if not register_rewindable(candidate):
			succeeded = false
	return succeeded


func unregister_rewindable(rewind_id: StringName, expected_node: Node = null) -> bool:
	if not _nodes_by_id.has(rewind_id):
		return false
	var registered_node: Node = _nodes_by_id[rewind_id]
	if expected_node != null and registered_node != expected_node:
		push_warning(
			"RewindStateRegistry refused to unregister '%s': node mismatch." % rewind_id
		)
		return false
	_nodes_by_id.erase(rewind_id)
	for index: int in range(_entries.size() - 1, -1, -1):
		if StringName(_entries[index].get("id", StringName())) == rewind_id:
			_entries.remove_at(index)
	registry_changed.emit(_entries.size())
	return true


func clear() -> void:
	_entries.clear()
	_nodes_by_id.clear()
	registry_changed.emit(0)


func validate_registry() -> bool:
	var succeeded: bool = true
	var seen_ids: Dictionary[StringName, bool] = {}
	for entry: Dictionary in _entries:
		var rewind_id := StringName(entry.get("id", StringName()))
		var node := entry.get("node") as Node
		if rewind_id == StringName():
			succeeded = _fail("RewindStateRegistry contains an empty rewind ID.") and succeeded
			continue
		if seen_ids.has(rewind_id):
			succeeded = _fail("RewindStateRegistry contains duplicate ID '%s'." % rewind_id) and succeeded
			continue
		seen_ids[rewind_id] = true
		if node == null or not is_instance_valid(node):
			succeeded = _fail("Rewindable '%s' points to an invalid node." % rewind_id) and succeeded
			continue
		if _read_rewind_id(node) != rewind_id:
			succeeded = _fail(
				"Rewindable '%s' changed its stable ID to '%s'."
				% [rewind_id, _read_rewind_id(node)]
			) and succeeded
	return succeeded


func capture_snapshot(timestamp: float) -> Dictionary:
	var states: Dictionary[StringName, Dictionary] = {}
	var succeeded: bool = validate_registry()
	for entry: Dictionary in _entries:
		var rewind_id := StringName(entry["id"])
		var node := entry["node"] as Node
		if node == null or not is_instance_valid(node):
			succeeded = false
			continue
		var capture_method := StringName(entry.get("capture_method", StringName()))
		var captured_value: Variant = node.call(capture_method)
		if typeof(captured_value) != TYPE_DICTIONARY:
			_fail(
				"Rewindable '%s' capture_rewind_state() must return a Dictionary."
				% rewind_id
			)
			succeeded = false
			continue
		var captured_state: Dictionary = captured_value
		if _contains_object_reference(captured_state):
			_fail(
				"Rewindable '%s' produced state containing an Object reference."
				% rewind_id
			)
			succeeded = false
			continue
		states[rewind_id] = captured_state.duplicate(true)
	return {
		"timestamp": maxf(0.0, timestamp),
		"states": states,
		"valid": succeeded,
	}


func can_restore_snapshot(snapshot: Dictionary) -> bool:
	if not bool(snapshot.get("valid", false)):
		return false
	var states_value: Variant = snapshot.get("states", {})
	if typeof(states_value) != TYPE_DICTIONARY:
		return false
	var states: Dictionary = states_value
	for entry: Dictionary in _entries:
		var rewind_id := StringName(entry["id"])
		if not states.has(rewind_id):
			return false
		if typeof(states[rewind_id]) != TYPE_DICTIONARY:
			return false
	return validate_registry()


func restore_snapshot(snapshot: Dictionary) -> bool:
	if not can_restore_snapshot(snapshot):
		return _fail("RewindStateRegistry rejected an incomplete or invalid snapshot.")
	var states: Dictionary = snapshot["states"]
	var succeeded: bool = true

	# All participants are prepared before any state is applied. This prevents
	# callbacks from observing a half-restored world.
	for entry: Dictionary in _entries:
		var prepare_node := entry["node"] as Node
		if prepare_node != null and prepare_node.has_method(&"prepare_for_rewind"):
			prepare_node.call(&"prepare_for_rewind")

	for entry: Dictionary in _entries:
		var rewind_id := StringName(entry["id"])
		var node := entry["node"] as Node
		if node == null or not is_instance_valid(node):
			succeeded = false
			continue
		var state: Dictionary = (states[rewind_id] as Dictionary).duplicate(true)
		var restore_method := StringName(entry.get("restore_method", StringName()))
		var restore_result: Variant = node.call(restore_method, state)
		if typeof(restore_result) == TYPE_BOOL and not bool(restore_result):
			_fail("Rewindable '%s' reported a restore failure." % rewind_id)
			succeeded = false

	for entry: Dictionary in _entries:
		var complete_node := entry["node"] as Node
		if complete_node != null and complete_node.has_method(&"complete_rewind"):
			complete_node.call(&"complete_rewind")
	return succeeded


func get_registered_count() -> int:
	return _entries.size()


func get_registered_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for entry: Dictionary in _entries:
		result.append(StringName(entry["id"]))
	return result


func get_node(rewind_id: StringName) -> Node:
	var node: Node = _nodes_by_id.get(rewind_id) as Node
	if node != null and not is_instance_valid(node):
		unregister_rewindable(rewind_id)
		return null
	return node


func has_rewindable_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for entry: Dictionary in _entries:
		if entry.get("node") == node:
			return true
	return false


func register_recallable(node: Node) -> bool:
	return register_rewindable(node)


func unregister_recallable(rewind_id: StringName, expected_node: Node = null) -> bool:
	return unregister_rewindable(rewind_id, expected_node)


func _sort_entries() -> void:
	_entries.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var left_phase := int(left.get("phase", RestorePhase.WORLD))
			var right_phase := int(right.get("phase", RestorePhase.WORLD))
			if left_phase != right_phase:
				return left_phase < right_phase
			return String(left.get("id", "")) < String(right.get("id", ""))
	)


func _read_rewind_id(node: Node) -> StringName:
	if node.has_method(&"get_rewind_id"):
		return StringName(str(node.call(&"get_rewind_id")))
	if node.has_method(&"get_recall_state_id"):
		return StringName(str(node.call(&"get_recall_state_id")))
	if node.has_method(&"get_object_id"):
		return StringName(str(node.call(&"get_object_id")))
	return StringName()


func _find_capture_method(node: Node) -> StringName:
	if node.has_method(&"capture_rewind_state"):
		return &"capture_rewind_state"
	if node.has_method(&"capture_recall_state"):
		return &"capture_recall_state"
	return StringName()


func _find_restore_method(node: Node) -> StringName:
	if node.has_method(&"restore_rewind_state"):
		return &"restore_rewind_state"
	if node.has_method(&"restore_recall_state"):
		return &"restore_recall_state"
	return StringName()


func _fail(message: String) -> bool:
	push_error(message)
	snapshot_failed.emit(message)
	return false


static func _describe(node: Node) -> String:
	if node == null or not is_instance_valid(node):
		return "<invalid node>"
	return str(node.get_path()) if node.is_inside_tree() else str(node.name)


static func _contains_object_reference(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_STATE_DEPTH:
		return true
	match typeof(value):
		TYPE_OBJECT:
			return value != null
		TYPE_ARRAY:
			var values: Array = value
			for item: Variant in values:
				if _contains_object_reference(item, depth + 1):
					return true
		TYPE_DICTIONARY:
			var values: Dictionary = value
			for key: Variant in values:
				if _contains_object_reference(key, depth + 1):
					return true
				if _contains_object_reference(values[key], depth + 1):
					return true
	return false
