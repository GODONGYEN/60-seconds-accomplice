class_name ObjectiveGraph
extends RefCounted

signal objective_state_changed(
	objective_id: StringName,
	previous_state: ObjectiveState,
	current_state: ObjectiveState
)

enum ObjectiveState {
	LOCKED,
	AVAILABLE,
	ACTIVE,
	COMPLETED,
	FAILED,
}

const STATE_NAMES: Dictionary = {
	ObjectiveState.LOCKED: &"locked",
	ObjectiveState.AVAILABLE: &"available",
	ObjectiveState.ACTIVE: &"active",
	ObjectiveState.COMPLETED: &"completed",
	ObjectiveState.FAILED: &"failed",
}

var _objectives: Dictionary[StringName, Dictionary] = {}
var _order: Array[StringName] = []


func add_objective(
	objective_id: StringName,
	title: String,
	all_of: Array[StringName] = [],
	any_of: Array[StringName] = [],
	optional: bool = false
) -> bool:
	if objective_id == StringName():
		push_error("ObjectiveGraph cannot add an objective with an empty ID")
		return false
	if _objectives.has(objective_id):
		push_error("ObjectiveGraph duplicate objective ID '%s'" % objective_id)
		return false
	if title.strip_edges().is_empty():
		push_error("ObjectiveGraph objective '%s' requires a title" % objective_id)
		return false
	_objectives[objective_id] = {
		"title": title,
		"state": ObjectiveState.LOCKED,
		"all_of": all_of.duplicate(),
		"any_of": any_of.duplicate(),
		"optional": optional,
	}
	_order.append(objective_id)
	return true


func validate() -> bool:
	var valid := not _objectives.is_empty()
	for objective_id: StringName in _order:
		var entry: Dictionary = _objectives[objective_id]
		for prerequisite: StringName in _read_ids(entry, "all_of"):
			if not _objectives.has(prerequisite):
				push_error(
					"Objective '%s' references missing prerequisite '%s'"
					% [objective_id, prerequisite]
				)
				valid = false
		for prerequisite: StringName in _read_ids(entry, "any_of"):
			if not _objectives.has(prerequisite):
				push_error(
					"Objective '%s' references missing OR prerequisite '%s'"
					% [objective_id, prerequisite]
				)
				valid = false
		if _has_cycle_from(objective_id, {}, {}):
			push_error("Objective graph contains a cycle at '%s'" % objective_id)
			valid = false
	return valid


func initialize() -> void:
	for objective_id: StringName in _order:
		_set_state(objective_id, ObjectiveState.LOCKED)
	refresh_availability()


func refresh_availability() -> void:
	for objective_id: StringName in _order:
		var current_state := get_state(objective_id)
		if current_state == ObjectiveState.COMPLETED or current_state == ObjectiveState.FAILED:
			continue
		if are_prerequisites_met(objective_id):
			if current_state == ObjectiveState.LOCKED:
				_set_state(objective_id, ObjectiveState.AVAILABLE)
		elif current_state == ObjectiveState.AVAILABLE or current_state == ObjectiveState.ACTIVE:
			_set_state(objective_id, ObjectiveState.LOCKED)


func activate_objective(objective_id: StringName) -> bool:
	if get_state(objective_id) != ObjectiveState.AVAILABLE:
		return false
	_set_state(objective_id, ObjectiveState.ACTIVE)
	return true


func complete_objective(objective_id: StringName) -> bool:
	var current_state := get_state(objective_id)
	if current_state != ObjectiveState.AVAILABLE and current_state != ObjectiveState.ACTIVE:
		push_warning(
			"Objective '%s' cannot complete from state '%s'"
			% [objective_id, get_state_name(objective_id)]
		)
		return false
	_set_state(objective_id, ObjectiveState.COMPLETED)
	refresh_availability()
	return true


func fail_objective(objective_id: StringName) -> bool:
	if not _objectives.has(objective_id):
		return false
	var current_state := get_state(objective_id)
	if current_state == ObjectiveState.COMPLETED or current_state == ObjectiveState.FAILED:
		return false
	_set_state(objective_id, ObjectiveState.FAILED)
	return true


func are_prerequisites_met(objective_id: StringName) -> bool:
	if not _objectives.has(objective_id):
		return false
	var entry: Dictionary = _objectives[objective_id]
	for prerequisite: StringName in _read_ids(entry, "all_of"):
		if get_state(prerequisite) != ObjectiveState.COMPLETED:
			return false
	var any_of := _read_ids(entry, "any_of")
	if any_of.is_empty():
		return true
	for prerequisite: StringName in any_of:
		if get_state(prerequisite) == ObjectiveState.COMPLETED:
			return true
	return false


func get_state(objective_id: StringName) -> ObjectiveState:
	if not _objectives.has(objective_id):
		return ObjectiveState.LOCKED
	return int(_objectives[objective_id].get("state", ObjectiveState.LOCKED)) as ObjectiveState


func get_state_name(objective_id: StringName) -> StringName:
	return StringName(STATE_NAMES.get(get_state(objective_id), &"locked"))


func get_title(objective_id: StringName) -> String:
	if not _objectives.has(objective_id):
		return ""
	return String(_objectives[objective_id].get("title", ""))


func is_optional(objective_id: StringName) -> bool:
	return bool(_objectives.get(objective_id, {}).get("optional", false))


func has_objective(objective_id: StringName) -> bool:
	return _objectives.has(objective_id)


func get_objective_ids() -> Array[StringName]:
	return _order.duplicate()


func get_actionable_objectives(maximum_count: int = 3) -> Array[StringName]:
	var result: Array[StringName] = []
	for objective_id: StringName in _order:
		var state := get_state(objective_id)
		if state == ObjectiveState.ACTIVE or state == ObjectiveState.AVAILABLE:
			result.append(objective_id)
			if result.size() >= maximum_count:
				break
	return result


func capture_state() -> Dictionary:
	var states: Dictionary[StringName, int] = {}
	for objective_id: StringName in _order:
		states[objective_id] = get_state(objective_id)
	return {"states": states}


func restore_state(snapshot: Dictionary) -> bool:
	var states_variant: Variant = snapshot.get("states", {})
	if not states_variant is Dictionary:
		push_warning("ObjectiveGraph rejected a snapshot without a states dictionary")
		return false
	var states := states_variant as Dictionary
	for objective_id: StringName in _order:
		if not states.has(objective_id):
			push_warning("ObjectiveGraph snapshot is missing '%s'" % objective_id)
			return false
		var restored_state := clampi(
			int(states[objective_id]),
			ObjectiveState.LOCKED,
			ObjectiveState.FAILED
		) as ObjectiveState
		_set_state(objective_id, restored_state)
	return true


func _set_state(objective_id: StringName, next_state: ObjectiveState) -> void:
	if not _objectives.has(objective_id):
		return
	var entry: Dictionary = _objectives[objective_id]
	var previous_state := int(entry.get("state", ObjectiveState.LOCKED)) as ObjectiveState
	if previous_state == next_state:
		return
	entry["state"] = next_state
	_objectives[objective_id] = entry
	objective_state_changed.emit(objective_id, previous_state, next_state)


func _read_ids(entry: Dictionary, key: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var values_variant: Variant = entry.get(key, [])
	if not values_variant is Array:
		return result
	for value: Variant in values_variant as Array:
		result.append(StringName(str(value)))
	return result


func _has_cycle_from(
	objective_id: StringName,
	visiting: Dictionary,
	visited: Dictionary
) -> bool:
	if bool(visiting.get(objective_id, false)):
		return true
	if bool(visited.get(objective_id, false)):
		return false
	visiting[objective_id] = true
	var entry: Dictionary = _objectives.get(objective_id, {})
	var prerequisites := _read_ids(entry, "all_of")
	prerequisites.append_array(_read_ids(entry, "any_of"))
	for prerequisite: StringName in prerequisites:
		if _objectives.has(prerequisite) and _has_cycle_from(prerequisite, visiting, visited):
			return true
	visiting.erase(objective_id)
	visited[objective_id] = true
	return false
