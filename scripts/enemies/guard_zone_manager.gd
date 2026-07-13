class_name GuardZoneManager
extends Node

signal guard_registered(guard_id: StringName, zone_id: StringName)
signal guard_unregistered(guard_id: StringName, zone_id: StringName)
signal zone_alert_propagated(
	zone_id: StringName,
	position: Vector2,
	source_id: StringName,
	recipient_guard_ids: PackedStringArray
)

const DEFAULT_BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)
const POSITION_EPSILON: float = 0.001

@export_range(1, 256, 1) var tile_size: int = 32

var _zones: Dictionary[StringName, Dictionary] = {}
var _declared_guard_zones: Dictionary[StringName, StringName] = {}
var _declared_guard_chase_zones: Dictionary[StringName, Array] = {}
var _registered_guards: Dictionary[StringName, Node2D] = {}
var _registered_guard_zones: Dictionary[StringName, StringName] = {}
var _active_alerts: Dictionary[StringName, Dictionary] = {}
var _validation_errors: PackedStringArray = PackedStringArray()
var _configured: bool = false


func load_blueprint(path: String = DEFAULT_BLUEPRINT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_configuration_error("GuardZoneManager could not open blueprint '%s'" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_configuration_error("GuardZoneManager blueprint '%s' is not a JSON object" % path)
		return false
	return configure_from_blueprint(parsed as Dictionary)


func configure_from_blueprint(blueprint: Dictionary) -> bool:
	_zones.clear()
	_declared_guard_zones.clear()
	_declared_guard_chase_zones.clear()
	_registered_guards.clear()
	_registered_guard_zones.clear()
	_active_alerts.clear()
	_validation_errors = PackedStringArray()
	_configured = false

	var parsed_tile_size := int(blueprint.get("tile_size", 0))
	if parsed_tile_size <= 0:
		_add_validation_error("blueprint tile_size must be positive")
	else:
		tile_size = parsed_tile_size

	var zones_variant: Variant = blueprint.get("guard_zones", [])
	if not zones_variant is Array:
		_add_validation_error("blueprint guard_zones must be an array")
		return false
	for zone_variant: Variant in zones_variant as Array:
		if not zone_variant is Dictionary:
			_add_validation_error("guard_zones contains a non-object entry")
			continue
		_parse_zone(zone_variant as Dictionary)

	_validate_zone_references()
	_parse_and_validate_guard_assignments(blueprint)
	_configured = _validation_errors.is_empty()
	if not _configured:
		for message: String in _validation_errors:
			push_error("GuardZoneManager: %s" % message)
	return _configured


func is_configured() -> bool:
	return _configured


func get_validation_errors() -> PackedStringArray:
	return _validation_errors.duplicate()


func get_zone_ids() -> Array[StringName]:
	var zone_ids: Array[StringName] = []
	zone_ids.assign(_zones.keys())
	zone_ids.sort_custom(_string_name_less_than)
	return zone_ids


func has_zone(zone_id: StringName) -> bool:
	return _zones.has(zone_id)


func get_zone_rect_cells(zone_id: StringName) -> Rect2i:
	var zone: Dictionary = _zones.get(zone_id, {}) as Dictionary
	return zone.get("rect_cells", Rect2i()) as Rect2i


func get_zone_rect_world(zone_id: StringName) -> Rect2:
	var zone: Dictionary = _zones.get(zone_id, {}) as Dictionary
	return zone.get("rect_world", Rect2()) as Rect2


func get_zone_anchor_world(zone_id: StringName) -> Vector2:
	var zone: Dictionary = _zones.get(zone_id, {}) as Dictionary
	return zone.get("anchor_world", Vector2.ZERO) as Vector2


func get_adjacent_zone_ids(zone_id: StringName) -> Array[StringName]:
	var zone: Dictionary = _zones.get(zone_id, {}) as Dictionary
	var adjacent: Array[StringName] = []
	var stored: Variant = zone.get("adjacent", [])
	if stored is Array:
		for adjacent_variant: Variant in stored as Array:
			adjacent.append(StringName(adjacent_variant))
	adjacent.sort_custom(_string_name_less_than)
	return adjacent


func is_position_in_zone(zone_id: StringName, world_position: Vector2) -> bool:
	if not _zones.has(zone_id):
		return false
	return get_zone_rect_world(zone_id).has_point(world_position)


func get_zone_id_for_world_position(world_position: Vector2) -> StringName:
	var selected_id := StringName()
	var selected_area := INF
	for zone_id: StringName in get_zone_ids():
		var rect := get_zone_rect_world(zone_id)
		if not rect.has_point(world_position):
			continue
		var area := rect.size.x * rect.size.y
		if area < selected_area:
			selected_area = area
			selected_id = zone_id
	return selected_id


func clamp_to_zone(zone_id: StringName, world_position: Vector2) -> Vector2:
	if not _zones.has(zone_id):
		push_warning("GuardZoneManager cannot clamp to unknown zone '%s'" % zone_id)
		return world_position
	return _closest_point_in_rect(get_zone_rect_world(zone_id), world_position)


func clamp_to_chase_bounds(zone_id: StringName, world_position: Vector2) -> Vector2:
	if not _zones.has(zone_id):
		push_warning("GuardZoneManager cannot clamp chase for unknown zone '%s'" % zone_id)
		return world_position
	var chase_zone_ids: Array[StringName] = [zone_id]
	chase_zone_ids.append_array(get_adjacent_zone_ids(zone_id))
	for chase_zone_id: StringName in chase_zone_ids:
		if get_zone_rect_world(chase_zone_id).has_point(world_position):
			return world_position

	var nearest_position := world_position
	var nearest_distance_squared := INF
	for chase_zone_id: StringName in chase_zone_ids:
		var candidate := _closest_point_in_rect(
			get_zone_rect_world(chase_zone_id), world_position
		)
		var distance_squared := candidate.distance_squared_to(world_position)
		if distance_squared + POSITION_EPSILON < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_position = candidate
	return nearest_position


func clamp_guard_to_chase_bounds(
	guard_id: StringName,
	world_position: Vector2
) -> Vector2:
	var home_zone: StringName = _declared_guard_zones.get(guard_id, StringName())
	if home_zone == StringName() or not _zones.has(home_zone):
		push_warning("GuardZoneManager cannot clamp chase for unknown Guard '%s'" % guard_id)
		return world_position
	var chase_zone_ids := get_allowed_chase_zone_ids(guard_id)
	if chase_zone_ids.is_empty():
		chase_zone_ids.append(home_zone)
	for chase_zone_id: StringName in chase_zone_ids:
		if get_zone_rect_world(chase_zone_id).has_point(world_position):
			return world_position

	var nearest_position := world_position
	var nearest_distance_squared := INF
	for chase_zone_id: StringName in chase_zone_ids:
		var candidate := _closest_point_in_rect(
			get_zone_rect_world(chase_zone_id), world_position
		)
		var distance_squared := candidate.distance_squared_to(world_position)
		if distance_squared + POSITION_EPSILON < nearest_distance_squared:
			nearest_distance_squared = distance_squared
			nearest_position = candidate
	return nearest_position


func get_allowed_chase_zone_ids(guard_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var stored: Variant = _declared_guard_chase_zones.get(guard_id, [])
	if stored is Array:
		for zone_variant: Variant in stored as Array:
			result.append(StringName(zone_variant))
	result.sort_custom(_string_name_less_than)
	return result


func register_guard(guard: Node2D, requested_zone_id: StringName = StringName()) -> bool:
	if guard == null or not is_instance_valid(guard):
		push_error("GuardZoneManager cannot register an invalid Guard")
		return false
	var guard_id := _extract_guard_id(guard)
	if guard_id == StringName():
		push_error("GuardZoneManager rejected Guard '%s' with an empty stable ID" % guard.name)
		return false
	var zone_id := requested_zone_id
	if zone_id == StringName() and guard.has_method(&"get_zone_id"):
		zone_id = StringName(guard.call(&"get_zone_id"))
	if not _zones.has(zone_id):
		push_error("GuardZoneManager rejected Guard '%s': unknown zone '%s'" % [guard_id, zone_id])
		return false
	var declared_zone: StringName = _declared_guard_zones.get(guard_id, StringName())
	if declared_zone != StringName() and declared_zone != zone_id:
		push_error(
			"GuardZoneManager rejected Guard '%s': declared '%s', requested '%s'"
			% [guard_id, declared_zone, zone_id]
		)
		return false
	if _registered_guards.has(guard_id):
		return _registered_guards[guard_id] == guard and _registered_guard_zones[guard_id] == zone_id
	if get_registered_guard_ids(zone_id).size() >= _get_zone_capacity(zone_id):
		push_error("GuardZoneManager zone '%s' is already at capacity" % zone_id)
		return false
	_registered_guards[guard_id] = guard
	_registered_guard_zones[guard_id] = zone_id
	guard_registered.emit(guard_id, zone_id)
	return true


func unregister_guard(guard_id: StringName, expected_guard: Node2D = null) -> bool:
	if not _registered_guards.has(guard_id):
		return false
	if expected_guard != null and _registered_guards[guard_id] != expected_guard:
		return false
	var zone_id: StringName = _registered_guard_zones.get(guard_id, StringName())
	_registered_guards.erase(guard_id)
	_registered_guard_zones.erase(guard_id)
	guard_unregistered.emit(guard_id, zone_id)
	return true


func get_registered_guard_ids(zone_id: StringName = StringName()) -> Array[StringName]:
	_prune_invalid_guards()
	var guard_ids: Array[StringName] = []
	for guard_id: StringName in _registered_guards:
		if zone_id == StringName() or _registered_guard_zones.get(guard_id) == zone_id:
			guard_ids.append(guard_id)
	guard_ids.sort_custom(_string_name_less_than)
	return guard_ids


func validate_registered_assignments(require_all_declared: bool = false) -> bool:
	_prune_invalid_guards()
	for guard_id: StringName in _registered_guards:
		if _registered_guard_zones.get(guard_id) != _declared_guard_zones.get(guard_id):
			return false
	for zone_id: StringName in _zones:
		if get_registered_guard_ids(zone_id).size() > _get_zone_capacity(zone_id):
			return false
	if require_all_declared:
		for guard_id: StringName in _declared_guard_zones:
			if not _registered_guards.has(guard_id):
				return false
	return true


func get_alert_recipient_ids(
	zone_id: StringName,
	include_adjacent: bool = true
) -> Array[StringName]:
	if not _zones.has(zone_id):
		return []
	var recipient_zones: Array[StringName] = [zone_id]
	if include_adjacent:
		recipient_zones.append_array(get_adjacent_zone_ids(zone_id))
	var recipients: Array[StringName] = []
	for recipient_zone: StringName in recipient_zones:
		for guard_id: StringName in get_registered_guard_ids(recipient_zone):
			if not recipients.has(guard_id):
				recipients.append(guard_id)
	recipients.sort_custom(_string_name_less_than)
	return recipients


func propagate_zone_alert(
	zone_id: StringName,
	position: Vector2,
	source_id: StringName,
	include_adjacent: bool = true
) -> PackedStringArray:
	if not _zones.has(zone_id):
		push_warning("GuardZoneManager ignored alert for unknown zone '%s'" % zone_id)
		return PackedStringArray()
	var recipient_ids := get_alert_recipient_ids(zone_id, include_adjacent)
	var packed_recipients := PackedStringArray()
	for guard_id: StringName in recipient_ids:
		packed_recipients.append(String(guard_id))
		var guard: Node2D = _registered_guards.get(guard_id)
		if guard != null and is_instance_valid(guard) and guard.has_method(&"receive_zone_alert"):
			guard.call(&"receive_zone_alert", position, source_id, zone_id)
	_active_alerts[zone_id] = {
		"position": position,
		"source_id": source_id,
		"recipient_guard_ids": packed_recipients.duplicate(),
	}
	zone_alert_propagated.emit(zone_id, position, source_id, packed_recipients)
	return packed_recipients


func get_active_alert(zone_id: StringName) -> Dictionary:
	return (_active_alerts.get(zone_id, {}) as Dictionary).duplicate(true)


func clear_alerts() -> void:
	_active_alerts.clear()


func reset_for_mission() -> void:
	clear_alerts()
	_prune_invalid_guards()


func _parse_zone(source: Dictionary) -> void:
	var zone_id := StringName(str(source.get("id", "")))
	if zone_id == StringName():
		_add_validation_error("guard zone has an empty id")
		return
	if _zones.has(zone_id):
		_add_validation_error("duplicate guard zone id '%s'" % zone_id)
		return
	var rect_cells := _parse_rect(source.get("allowed_rect", []))
	if rect_cells.size.x <= 0 or rect_cells.size.y <= 0:
		_add_validation_error("guard zone '%s' has an invalid allowed_rect" % zone_id)
		return
	var anchor_cell := _parse_cell(source.get("anchor", []))
	if not rect_cells.has_point(anchor_cell):
		_add_validation_error("guard zone '%s' anchor is outside allowed_rect" % zone_id)
	var capacity := int(source.get("max_active_guards", 0))
	if capacity <= 0:
		_add_validation_error("guard zone '%s' max_active_guards must be positive" % zone_id)
	var adjacent := _parse_string_name_array(source.get("adjacent_chase_zones", []))
	var assigned := _parse_string_name_array(source.get("assigned_guards", []))
	if assigned.size() > capacity:
		_add_validation_error("guard zone '%s' assigns more Guards than its capacity" % zone_id)
	_zones[zone_id] = {
		"rect_cells": rect_cells,
		"rect_world": Rect2(
			Vector2(rect_cells.position * tile_size),
			Vector2(rect_cells.size * tile_size)
		),
		"anchor_cell": anchor_cell,
		"anchor_world": _cell_to_world(anchor_cell),
		"capacity": capacity,
		"adjacent": adjacent,
		"assigned_guards": assigned,
	}


func _validate_zone_references() -> void:
	for zone_id: StringName in _zones:
		var zone: Dictionary = _zones[zone_id]
		var adjacent: Variant = zone.get("adjacent", [])
		if adjacent is Array:
			for adjacent_variant: Variant in adjacent as Array:
				var adjacent_id := StringName(adjacent_variant)
				if adjacent_id == zone_id:
					_add_validation_error("guard zone '%s' cannot be adjacent to itself" % zone_id)
				elif not _zones.has(adjacent_id):
					_add_validation_error(
						"guard zone '%s' references unknown adjacent zone '%s'"
						% [zone_id, adjacent_id]
					)


func _parse_and_validate_guard_assignments(blueprint: Dictionary) -> void:
	var guards_variant: Variant = blueprint.get("guards", [])
	if not guards_variant is Array:
		_add_validation_error("blueprint guards must be an array")
		return
	for guard_variant: Variant in guards_variant as Array:
		if not guard_variant is Dictionary:
			_add_validation_error("guards contains a non-object entry")
			continue
		var guard_data := guard_variant as Dictionary
		var guard_id := StringName(str(guard_data.get("id", "")))
		var zone_id := StringName(str(guard_data.get("zone_id", "")))
		if guard_id == StringName():
			_add_validation_error("Guard definition has an empty id")
			continue
		if _declared_guard_zones.has(guard_id):
			_add_validation_error("duplicate Guard id '%s'" % guard_id)
			continue
		if not _zones.has(zone_id):
			_add_validation_error("Guard '%s' references unknown zone '%s'" % [guard_id, zone_id])
			continue
		_declared_guard_zones[guard_id] = zone_id
		var zone: Dictionary = _zones[zone_id]
		var assigned: Array = zone.get("assigned_guards", []) as Array
		if not assigned.has(guard_id):
			_add_validation_error("Guard '%s' is missing from zone '%s' assignment" % [guard_id, zone_id])
		_validate_guard_position(guard_id, zone_id, "spawn", guard_data.get("spawn", []))
		_validate_guard_position(
			guard_id, zone_id, "return_point", guard_data.get("return_point", [])
		)
		var waypoints_variant: Variant = guard_data.get("waypoints", [])
		if not waypoints_variant is Array or (waypoints_variant as Array).is_empty():
			_add_validation_error("Guard '%s' requires at least one waypoint" % guard_id)
		else:
			for waypoint_variant: Variant in waypoints_variant as Array:
				_validate_guard_position(guard_id, zone_id, "waypoint", waypoint_variant)
		var allowed_chase := _parse_string_name_array(
			guard_data.get("allowed_chase_zones", [])
		)
		if allowed_chase.is_empty():
			allowed_chase.append(zone_id)
		elif not allowed_chase.has(zone_id):
			_add_validation_error(
				"Guard '%s' allowed_chase_zones must include its home zone '%s'"
				% [guard_id, zone_id]
			)
		_declared_guard_chase_zones[guard_id] = allowed_chase.duplicate()
		var legal_chase_zones: Array[StringName] = [zone_id]
		legal_chase_zones.append_array(get_adjacent_zone_ids(zone_id))
		for chase_zone_id: StringName in allowed_chase:
			if not legal_chase_zones.has(chase_zone_id):
				_add_validation_error(
					"Guard '%s' chase zone '%s' is outside its zone adjacency"
					% [guard_id, chase_zone_id]
				)

	var assignment_owner: Dictionary[StringName, StringName] = {}
	for zone_id: StringName in _zones:
		var zone: Dictionary = _zones[zone_id]
		var assigned: Array = zone.get("assigned_guards", []) as Array
		for assigned_variant: Variant in assigned:
			var guard_id := StringName(assigned_variant)
			if assignment_owner.has(guard_id):
				_add_validation_error("Guard '%s' is assigned to multiple zones" % guard_id)
			elif not _declared_guard_zones.has(guard_id):
				_add_validation_error("zone '%s' assigns unknown Guard '%s'" % [zone_id, guard_id])
			else:
				assignment_owner[guard_id] = zone_id


func _validate_guard_position(
	guard_id: StringName,
	zone_id: StringName,
	label: String,
	cell_variant: Variant
) -> void:
	var values: Array = cell_variant as Array
	if values == null or values.size() != 2:
		_add_validation_error("Guard '%s' %s is not a two-value cell" % [guard_id, label])
		return
	var cell := Vector2i(int(values[0]), int(values[1]))
	if not get_zone_rect_cells(zone_id).has_point(cell):
		_add_validation_error("Guard '%s' %s is outside zone '%s'" % [guard_id, label, zone_id])


func _get_zone_capacity(zone_id: StringName) -> int:
	var zone: Dictionary = _zones.get(zone_id, {}) as Dictionary
	return int(zone.get("capacity", 0))


func _extract_guard_id(guard: Node2D) -> StringName:
	if guard.has_method(&"get_object_id"):
		return StringName(guard.call(&"get_object_id"))
	return StringName()


func _prune_invalid_guards() -> void:
	var stale_ids: Array[StringName] = []
	for guard_id: StringName in _registered_guards:
		if not is_instance_valid(_registered_guards[guard_id]):
			stale_ids.append(guard_id)
	for guard_id: StringName in stale_ids:
		_registered_guards.erase(guard_id)
		_registered_guard_zones.erase(guard_id)


func _parse_string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not value is Array:
		return result
	for item: Variant in value as Array:
		var parsed := StringName(str(item))
		if parsed != StringName() and not result.has(parsed):
			result.append(parsed)
	result.sort_custom(_string_name_less_than)
	return result


func _parse_rect(value: Variant) -> Rect2i:
	var values: Array = value as Array
	if values == null or values.size() != 4:
		return Rect2i()
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _parse_cell(value: Variant) -> Vector2i:
	var values: Array = value as Array
	if values == null or values.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(values[0]), int(values[1]))


func _cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * tile_size) + Vector2.ONE * float(tile_size) * 0.5


func _closest_point_in_rect(rect: Rect2, position: Vector2) -> Vector2:
	var maximum := rect.end - Vector2.ONE * POSITION_EPSILON
	return Vector2(
		clampf(position.x, rect.position.x, maximum.x),
		clampf(position.y, rect.position.y, maximum.y)
	)


func _set_configuration_error(message: String) -> void:
	_zones.clear()
	_declared_guard_zones.clear()
	_declared_guard_chase_zones.clear()
	_registered_guards.clear()
	_registered_guard_zones.clear()
	_active_alerts.clear()
	_validation_errors = PackedStringArray([message])
	_configured = false
	push_error(message)


func _add_validation_error(message: String) -> void:
	_validation_errors.append(message)


func _string_name_less_than(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
