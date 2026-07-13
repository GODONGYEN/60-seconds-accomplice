class_name MissionSolvabilityValidator
extends RefCounted

const REQUIRED_MAP_SIZE := Vector2i(64, 42)
const MINIMUM_ROOM_COUNT: int = 12
const REQUIRED_GUARD_COUNT: int = 10
const REQUIRED_CAMERA_COUNT: int = 8
const REQUIRED_LASER_COUNT: int = 3
const MINIMUM_SAFE_WINDOW_SECONDS: float = 3.0

var _errors: Array[String] = []
var _statistics: Dictionary = {}
var _map_size: Vector2i = Vector2i.ZERO
var _walkable_cells: Dictionary = {}


func validate(blueprint: Dictionary) -> Dictionary:
	_errors.clear()
	_statistics.clear()
	_walkable_cells.clear()
	_map_size = _json_vector(blueprint.get("size", []))
	_validate_dimensions_and_counts(blueprint)
	_validate_stable_ids(blueprint)
	_validate_geometry_and_walkability(blueprint)
	_validate_room_graph(blueprint)
	_validate_access_progression(blueprint)
	_validate_solution_declarations(blueprint)
	_validate_choke_windows(blueprint)
	_statistics["walkable_cell_count"] = _walkable_cells.size()
	return {
		"is_valid": _errors.is_empty(),
		"errors": _errors.duplicate(),
		"statistics": _statistics.duplicate(true),
	}


func _validate_dimensions_and_counts(blueprint: Dictionary) -> void:
	var rooms: Dictionary = _dictionary(blueprint.get("rooms", {}))
	var guards: Array = _array(blueprint.get("guards", []))
	var security: Dictionary = _dictionary(blueprint.get("security", {}))
	var cctv: Dictionary = _dictionary(security.get("cctv_network", {}))
	var laser: Dictionary = _dictionary(security.get("laser_network", {}))
	var cameras: Array = _array(cctv.get("cameras", []))
	var barriers: Array = _array(laser.get("barriers", []))
	_statistics.merge(
		{
			"map_size": _map_size,
			"room_count": rooms.size(),
			"guard_count": guards.size(),
			"camera_count": cameras.size(),
			"laser_count": barriers.size(),
		},
		true
	)
	_require(
		_map_size == REQUIRED_MAP_SIZE,
		"MAP_SIZE: expected 64x42, got %dx%d" % [_map_size.x, _map_size.y]
	)
	_require(
		rooms.size() >= MINIMUM_ROOM_COUNT,
		"ROOM_COUNT: expected at least %d rooms, got %d"
		% [MINIMUM_ROOM_COUNT, rooms.size()]
	)
	_require(
		guards.size() == REQUIRED_GUARD_COUNT,
		"GUARD_COUNT: expected %d guards, got %d"
		% [REQUIRED_GUARD_COUNT, guards.size()]
	)
	_require(
		cameras.size() == REQUIRED_CAMERA_COUNT,
		"CAMERA_COUNT: expected %d CCTV cameras, got %d"
		% [REQUIRED_CAMERA_COUNT, cameras.size()]
	)
	_require(
		barriers.size() == REQUIRED_LASER_COUNT,
		"LASER_COUNT: expected %d laser barriers, got %d"
		% [REQUIRED_LASER_COUNT, barriers.size()]
	)
	_require(int(blueprint.get("tile_size", 0)) == 32, "TILE_SIZE: expected 32 pixels")
	_require(
		_json_vector(blueprint.get("world_size", [])) == REQUIRED_MAP_SIZE * 32,
		"WORLD_SIZE: world dimensions must equal map size times tile size"
	)


func _validate_stable_ids(blueprint: Dictionary) -> void:
	var seen: Dictionary = {}
	_register_dictionary_keys(_dictionary(blueprint.get("rooms", {})), "room", seen)
	_register_entry_ids(_array(blueprint.get("connectors", [])), "connector", seen)
	_register_entry_ids(_array(blueprint.get("dynamic_portals", [])), "portal", seen)
	_register_dictionary_keys(_dictionary(blueprint.get("objects", {})), "object", seen)
	_register_entry_ids(_array(blueprint.get("guards", [])), "guard", seen)
	_register_entry_ids(_array(blueprint.get("guard_zones", [])), "guard zone", seen)
	_register_entry_ids(_array(blueprint.get("choke_points", [])), "choke point", seen)
	_register_entry_ids(
		_array(blueprint.get("internal_solid_rects", [])), "internal solid", seen
	)
	var security: Dictionary = _dictionary(blueprint.get("security", {}))
	var cctv: Dictionary = _dictionary(security.get("cctv_network", {}))
	var laser: Dictionary = _dictionary(security.get("laser_network", {}))
	var authorization: Dictionary = _dictionary(security.get("vault_authorization", {}))
	_register_entry(cctv, "CCTV network", seen)
	_register_entry(_dictionary(cctv.get("terminal", {})), "CCTV terminal", seen)
	_register_entry_ids(_array(cctv.get("cameras", [])), "CCTV camera", seen)
	_register_entry(laser, "laser network", seen)
	_register_entry(_dictionary(laser.get("terminal", {})), "laser terminal", seen)
	_register_entry_ids(_array(laser.get("barriers", [])), "laser barrier", seen)
	_register_entry_ids(
		_array(authorization.get("sources", [])), "vault authorization source", seen
	)
	var objectives: Dictionary = _dictionary(blueprint.get("objectives", {}))
	_register_dictionary_keys(_dictionary(objectives.get("nodes", {})), "objective", seen)
	for choke_value: Variant in _array(blueprint.get("choke_points", [])):
		var choke: Dictionary = _dictionary(choke_value)
		_register_entry_ids(
			_array(choke.get("safe_windows", [])),
			"safe window for %s" % String(choke.get("id", "unknown")),
			seen
		)
	_statistics["stable_id_count"] = seen.size()


func _validate_geometry_and_walkability(blueprint: Dictionary) -> void:
	if _map_size.x <= 0 or _map_size.y <= 0:
		return
	var rooms: Dictionary = _dictionary(blueprint.get("rooms", {}))
	for room_id_value: Variant in rooms:
		var room_id := String(room_id_value)
		var room: Dictionary = _dictionary(rooms[room_id_value])
		var rect := _validate_rect(room.get("rect", []), "room '%s'" % room_id)
		_add_walkable_rect(rect)
	for connector_value: Variant in _array(blueprint.get("connectors", [])):
		var connector: Dictionary = _dictionary(connector_value)
		var rect := _validate_rect(
			connector.get("rect", []),
			"connector '%s'" % String(connector.get("id", ""))
		)
		_add_walkable_rect(rect)
	for portal_value: Variant in _array(blueprint.get("dynamic_portals", [])):
		var portal: Dictionary = _dictionary(portal_value)
		var rect := _validate_rect(
			portal.get("span_rect", []),
			"portal '%s'" % String(portal.get("id", ""))
		)
		_add_walkable_rect(rect)
		_validate_position(
			portal.get("anchor", []),
			"portal '%s' anchor" % String(portal.get("id", "")),
			false
		)
	for solid_value: Variant in _array(blueprint.get("internal_solid_rects", [])):
		var solid: Dictionary = _dictionary(solid_value)
		var rect := _validate_rect(
			solid.get("rect", []),
			"internal solid '%s'" % String(solid.get("id", ""))
		)
		for x: int in range(rect.position.x, rect.end.x):
			for y: int in range(rect.position.y, rect.end.y):
				_walkable_cells.erase(Vector2i(x, y))
	_validate_position_dictionary(_dictionary(blueprint.get("objects", {})), "object")
	for guard_value: Variant in _array(blueprint.get("guards", [])):
		var guard: Dictionary = _dictionary(guard_value)
		var guard_id := String(guard.get("id", ""))
		_validate_position(guard.get("spawn", []), "guard '%s' spawn" % guard_id)
		for waypoint_index: int in range(_array(guard.get("waypoints", [])).size()):
			_validate_position(
				_array(guard.get("waypoints", []))[waypoint_index],
				"guard '%s' waypoint %d" % [guard_id, waypoint_index]
			)
	var security: Dictionary = _dictionary(blueprint.get("security", {}))
	var cctv: Dictionary = _dictionary(security.get("cctv_network", {}))
	var laser: Dictionary = _dictionary(security.get("laser_network", {}))
	var authorization: Dictionary = _dictionary(security.get("vault_authorization", {}))
	_validate_position_entry(_dictionary(cctv.get("terminal", {})), "CCTV terminal")
	for camera_value: Variant in _array(cctv.get("cameras", [])):
		_validate_position_entry(_dictionary(camera_value), "CCTV camera")
	_validate_position_entry(_dictionary(laser.get("terminal", {})), "laser terminal")
	for barrier_value: Variant in _array(laser.get("barriers", [])):
		var barrier: Dictionary = _dictionary(barrier_value)
		_validate_position(
			barrier.get("anchor", []),
			"laser barrier '%s'" % String(barrier.get("id", ""))
		)
		_validate_rect(
			barrier.get("span_rect", []),
			"laser barrier '%s' span" % String(barrier.get("id", ""))
		)
	for source_value: Variant in _array(authorization.get("sources", [])):
		_validate_position_entry(_dictionary(source_value), "vault authorization source")
	for choke_value: Variant in _array(blueprint.get("choke_points", [])):
		var choke: Dictionary = _dictionary(choke_value)
		_validate_rect(
			choke.get("rect", []),
			"choke point '%s'" % String(choke.get("id", ""))
		)


func _validate_room_graph(blueprint: Dictionary) -> void:
	var rooms: Dictionary = _dictionary(blueprint.get("rooms", {}))
	var graph: Dictionary = {}
	for room_id: Variant in rooms:
		graph[String(room_id)] = []
	for connector_value: Variant in _array(blueprint.get("connectors", [])):
		_add_room_links(_dictionary(connector_value), graph, rooms, "connector")
	for portal_value: Variant in _array(blueprint.get("dynamic_portals", [])):
		_add_room_links(_dictionary(portal_value), graph, rooms, "portal")
	var objects: Dictionary = _dictionary(blueprint.get("objects", {}))
	var spawn: Dictionary = _dictionary(objects.get("player_spawn", {}))
	var spawn_zone := String(spawn.get("zone_id", ""))
	_require(graph.has(spawn_zone), "ROOM_GRAPH: player spawn references unknown room '%s'" % spawn_zone)
	if not graph.has(spawn_zone):
		return
	var reachable: Dictionary = _collect_reachable_rooms(spawn_zone, graph)
	_statistics["reachable_room_count"] = reachable.size()
	_require(
		reachable.size() == rooms.size(),
		"ROOM_GRAPH: only %d of %d rooms are reachable from spawn"
		% [reachable.size(), rooms.size()]
	)
	_validate_zone_dictionary(objects, rooms, reachable, "object")
	var security: Dictionary = _dictionary(blueprint.get("security", {}))
	var cctv: Dictionary = _dictionary(security.get("cctv_network", {}))
	var laser: Dictionary = _dictionary(security.get("laser_network", {}))
	var authorization: Dictionary = _dictionary(security.get("vault_authorization", {}))
	_validate_zone_entry(_dictionary(cctv.get("terminal", {})), rooms, reachable, "CCTV terminal")
	_validate_zone_entry(_dictionary(laser.get("terminal", {})), rooms, reachable, "laser terminal")
	for source_value: Variant in _array(authorization.get("sources", [])):
		_validate_zone_entry(
			_dictionary(source_value), rooms, reachable, "vault authorization source"
		)
	_validate_guard_zone_references(blueprint, cctv)
	var solvability: Dictionary = _dictionary(blueprint.get("solvability", {}))
	for step_value: Variant in _array(solvability.get("mandatory_room_path", [])):
		var alternatives := String(step_value).split("|", false)
		var has_reachable_alternative := false
		for alternative: String in alternatives:
			has_reachable_alternative = has_reachable_alternative or reachable.has(alternative)
		_require(
			has_reachable_alternative,
			"ROOM_GRAPH: mandatory route step '%s' has no reachable declared room" % step_value
		)


func _validate_guard_zone_references(blueprint: Dictionary, cctv: Dictionary) -> void:
	var zones: Dictionary = {}
	for zone_value: Variant in _array(blueprint.get("guard_zones", [])):
		var zone: Dictionary = _dictionary(zone_value)
		var zone_id := String(zone.get("id", ""))
		zones[zone_id] = zone
		_validate_rect(zone.get("allowed_rect", []), "guard zone '%s'" % zone_id)
		_validate_position(zone.get("anchor", []), "guard zone '%s' anchor" % zone_id)
	for zone_id_value: Variant in zones:
		var zone_id := String(zone_id_value)
		var zone: Dictionary = _dictionary(zones[zone_id_value])
		for adjacent_value: Variant in _array(zone.get("adjacent_chase_zones", [])):
			var adjacent := String(adjacent_value)
			_require(
				zones.has(adjacent),
				"GUARD_ZONE: '%s' references unknown adjacent zone '%s'" % [zone_id, adjacent]
			)
	var guard_ids: Dictionary = {}
	for guard_value: Variant in _array(blueprint.get("guards", [])):
		var guard: Dictionary = _dictionary(guard_value)
		var guard_id := String(guard.get("id", ""))
		var zone_id := String(guard.get("zone_id", ""))
		guard_ids[guard_id] = true
		_require(
			zones.has(zone_id),
			"GUARD_ZONE: guard '%s' references unknown zone '%s'" % [guard_id, zone_id]
		)
		for allowed_value: Variant in _array(guard.get("allowed_chase_zones", [])):
			_require(
				zones.has(String(allowed_value)),
				"GUARD_ZONE: guard '%s' has unknown chase zone '%s'"
				% [guard_id, String(allowed_value)]
			)
	for zone_id_value: Variant in zones:
		var zone: Dictionary = _dictionary(zones[zone_id_value])
		for guard_id_value: Variant in _array(zone.get("assigned_guards", [])):
			_require(
				guard_ids.has(String(guard_id_value)),
				"GUARD_ZONE: zone '%s' assigns unknown guard '%s'"
				% [String(zone_id_value), String(guard_id_value)]
			)
	for camera_value: Variant in _array(cctv.get("cameras", [])):
		var camera: Dictionary = _dictionary(camera_value)
		var camera_id := String(camera.get("id", ""))
		var camera_zone := String(camera.get("zone_id", ""))
		_require(
			zones.has(camera_zone),
			"GUARD_ZONE: CCTV camera '%s' references unknown zone '%s'"
			% [camera_id, camera_zone]
		)


func _validate_access_progression(blueprint: Dictionary) -> void:
	var access_control: Dictionary = _dictionary(blueprint.get("access_control", {}))
	var access_ranks: Dictionary = {}
	for level_value: Variant in _array(access_control.get("levels", [])):
		var level: Dictionary = _dictionary(level_value)
		var level_id := String(level.get("id", ""))
		_require(not level_id.is_empty(), "ACCESS: access level ID cannot be empty")
		_require(not access_ranks.has(level_id), "ACCESS: duplicate access level '%s'" % level_id)
		access_ranks[level_id] = int(level.get("rank", -1))
	for required_level: String in ["PUBLIC", "LEVEL_1", "LEVEL_2", "VAULT"]:
		_require(access_ranks.has(required_level), "ACCESS: missing level '%s'" % required_level)
	var rooms: Dictionary = _dictionary(blueprint.get("rooms", {}))
	var objects: Dictionary = _dictionary(blueprint.get("objects", {}))
	for card_value: Variant in _array(access_control.get("physical_cards", [])):
		var card_id := String(card_value)
		var card: Dictionary = _dictionary(objects.get(card_id, {}))
		_require(not card.is_empty(), "ACCESS: physical card '%s' is not declared" % card_id)
		if card.is_empty():
			continue
		var granted := String(card.get("grants_access", ""))
		var room_id := String(card.get("zone_id", ""))
		var room: Dictionary = _dictionary(rooms.get(room_id, {}))
		var room_access := String(room.get("minimum_access", ""))
		_require(
			_rank_for(room_access, access_ranks) < _rank_for(granted, access_ranks),
			"ACCESS_CYCLE: card '%s' is behind its own '%s' access level" % [card_id, granted]
		)
	var security: Dictionary = _dictionary(blueprint.get("security", {}))
	var authorization: Dictionary = _dictionary(security.get("vault_authorization", {}))
	var sources: Array = _array(authorization.get("sources", []))
	var declared_source_ids: Array = _array(access_control.get("vault_credential_sources_any", []))
	_require(
		String(authorization.get("completion_logic", "")) == "ANY",
		"VAULT_AUTH: completion logic must allow either source"
	)
	_require(sources.size() >= 2, "VAULT_AUTH: at least two authorization sources are required")
	for source_value: Variant in sources:
		var source: Dictionary = _dictionary(source_value)
		var source_id := String(source.get("id", ""))
		_require(
			declared_source_ids.has(source_id),
			"VAULT_AUTH: source '%s' is absent from access control declaration" % source_id
		)
		var source_access := String(source.get("required_access", ""))
		_require(
			_rank_for(source_access, access_ranks) < _rank_for("VAULT", access_ranks),
			"ACCESS_CYCLE: vault authorization source '%s' requires VAULT" % source_id
		)
	var laser: Dictionary = _dictionary(security.get("laser_network", {}))
	var laser_terminal: Dictionary = _dictionary(laser.get("terminal", {}))
	_require(
		String(laser_terminal.get("zone_id", "")) != "laser_corridor",
		"ACCESS_CYCLE: laser shutdown terminal cannot be behind the active laser corridor"
	)
	_validate_objective_dag(_dictionary(blueprint.get("objectives", {})))
	var has_vault_door := false
	for portal_value: Variant in _array(blueprint.get("dynamic_portals", [])):
		var portal: Dictionary = _dictionary(portal_value)
		var required_access := String(portal.get("required_access", ""))
		_require(
			access_ranks.has(required_access),
			"ACCESS: portal '%s' uses unknown access '%s'"
			% [String(portal.get("id", "")), required_access]
		)
		if String(portal.get("id", "")) == "door_vault_authorization_01":
			has_vault_door = true
			_require(
				required_access == "VAULT"
				and _array(portal.get("required_flags_all", [])).has("vault_authorized"),
				"VAULT_AUTH: vault door must require VAULT and vault_authorized"
			)
	_require(has_vault_door, "VAULT_AUTH: required vault authorization door is missing")


func _validate_objective_dag(objectives: Dictionary) -> void:
	var nodes: Dictionary = _dictionary(objectives.get("nodes", {}))
	var order: Array = _array(objectives.get("topological_order", []))
	var order_index: Dictionary = {}
	for index: int in range(order.size()):
		var objective_id := String(order[index])
		_require(
			nodes.has(objective_id),
			"OBJECTIVE_DAG: topological order references unknown '%s'" % objective_id
		)
		_require(
			not order_index.has(objective_id),
			"OBJECTIVE_DAG: duplicate topological entry '%s'" % objective_id
		)
		order_index[objective_id] = index
	_require(
		order_index.size() == nodes.size(),
		"OBJECTIVE_DAG: topological order must contain every objective exactly once"
	)
	for node_id_value: Variant in nodes:
		var node_id := String(node_id_value)
		var node: Dictionary = _dictionary(nodes[node_id_value])
		for prerequisite_value: Variant in _array(node.get("prerequisites_all", [])):
			var prerequisite := String(prerequisite_value)
			_require(
				nodes.has(prerequisite),
				"OBJECTIVE_DAG: '%s' references unknown prerequisite '%s'"
				% [node_id, prerequisite]
			)
			if order_index.has(node_id) and order_index.has(prerequisite):
				_require(
					int(order_index[prerequisite]) < int(order_index[node_id]),
					"OBJECTIVE_DAG: circular or reversed edge '%s' -> '%s'"
					% [prerequisite, node_id]
				)


func _validate_solution_declarations(blueprint: Dictionary) -> void:
	var solvability: Dictionary = _dictionary(blueprint.get("solvability", {}))
	var no_recall: Array = _array(solvability.get("no_recall_solution", []))
	var required_milestone_groups: Array[String] = [
		"facility_infiltrated",
		"access_level_1_acquired",
		"laser_network_offline",
		"access_level_2_acquired",
		"vault_door_open",
		"chronos_core_stolen",
		"mission_extracted",
	]
	var no_recall_text := "|".join(PackedStringArray(no_recall))
	for milestone: String in required_milestone_groups:
		_require(
			no_recall_text.contains(milestone),
			"NO_RECALL_ROUTE: missing required milestone '%s'" % milestone
		)
	_require(
		no_recall_text.contains("cctv_network_offline")
		or no_recall_text.contains("cctv_safe_route_confirmed"),
		"NO_RECALL_ROUTE: CCTV needs a declared disable-or-bypass step"
	)
	_require(
		no_recall_text.contains("biometric_sample_acquired")
		or no_recall_text.contains("server_override_completed"),
		"NO_RECALL_ROUTE: one vault authorization source must be declared"
	)
	var recall_assisted := String(solvability.get("recall_assisted_solution", "")).strip_edges()
	_require(
		not recall_assisted.is_empty()
		and recall_assisted.to_lower().contains("echo")
		and recall_assisted.to_lower().contains("acyclic"),
		"RECALL_ROUTE: declaration must describe Echo use and preserve acyclic progression"
	)
	var mission_rules: Dictionary = _dictionary(blueprint.get("mission_rules", {}))
	_require(
		not bool(mission_rules.get("recall_required_for_completion", true)),
		"NO_RECALL_ROUTE: mission rules must not require Recall for completion"
	)
	var contract: Dictionary = _dictionary(blueprint.get("validation_contract", {}))
	_require(
		bool(contract.get("requires_no_recall_solution", false))
		and bool(contract.get("requires_recall_assisted_solution", false)),
		"SOLUTION_CONTRACT: both no-Recall and Recall-assisted routes must be required"
	)


func _validate_choke_windows(blueprint: Dictionary) -> void:
	var choke_points: Array = _array(blueprint.get("choke_points", []))
	_require(not choke_points.is_empty(), "CHOKE_WINDOW: at least one choke point is required")
	var declared_minimum := INF
	for choke_value: Variant in choke_points:
		var choke: Dictionary = _dictionary(choke_value)
		var choke_id := String(choke.get("id", ""))
		var cycle_seconds := float(choke.get("cycle_seconds", 0.0))
		var windows: Array = _array(choke.get("safe_windows", []))
		_require(cycle_seconds > 0.0, "CHOKE_WINDOW: '%s' needs a positive cycle" % choke_id)
		_require(not windows.is_empty(), "CHOKE_WINDOW: '%s' has no safe window" % choke_id)
		for window_value: Variant in windows:
			var window: Dictionary = _dictionary(window_value)
			var duration := float(window.get("duration_seconds", 0.0))
			var start := float(window.get("start_seconds", -1.0))
			declared_minimum = minf(declared_minimum, duration)
			_require(
				duration >= MINIMUM_SAFE_WINDOW_SECONDS,
				"CHOKE_WINDOW: '%s' window '%s' is %.2fs; minimum is %.2fs"
				% [choke_id, String(window.get("id", "")), duration, MINIMUM_SAFE_WINDOW_SECONDS]
			)
			_require(
				start >= 0.0 and start + duration <= cycle_seconds,
				"CHOKE_WINDOW: '%s' window '%s' lies outside its cycle"
				% [choke_id, String(window.get("id", ""))]
			)
	_statistics["choke_count"] = choke_points.size()
	_statistics["minimum_declared_safe_window_seconds"] = (
		0.0 if is_inf(declared_minimum) else declared_minimum
	)


func _register_dictionary_keys(entries: Dictionary, context: String, seen: Dictionary) -> void:
	for id_value: Variant in entries:
		_register_id(String(id_value), context, seen)


func _register_entry_ids(entries: Array, context: String, seen: Dictionary) -> void:
	for entry_value: Variant in entries:
		_register_entry(_dictionary(entry_value), context, seen)


func _register_entry(entry: Dictionary, context: String, seen: Dictionary) -> void:
	_register_id(String(entry.get("id", "")), context, seen)


func _register_id(id: String, context: String, seen: Dictionary) -> void:
	var stable_id := id.strip_edges()
	_require(not stable_id.is_empty(), "STABLE_ID: %s has an empty ID" % context)
	if stable_id.is_empty():
		return
	_require(
		not seen.has(stable_id),
		"STABLE_ID: duplicate '%s' in %s (first used by %s)"
		% [stable_id, context, String(seen.get(stable_id, "unknown"))]
	)
	if not seen.has(stable_id):
		seen[stable_id] = context


func _validate_rect(value: Variant, context: String) -> Rect2i:
	var values: Array = _array(value)
	if values.size() != 4:
		_require(false, "BOUNDS: %s requires [x, y, width, height]" % context)
		return Rect2i()
	var rect := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
	_require(rect.size.x > 0 and rect.size.y > 0, "BOUNDS: %s has non-positive size" % context)
	_require(
		_rect_is_in_bounds(rect),
		"BOUNDS: %s rect %s exceeds map %s" % [context, rect, _map_size]
	)
	return rect


func _rect_is_in_bounds(rect: Rect2i) -> bool:
	return (
		rect.position.x >= 0
		and rect.position.y >= 0
		and rect.end.x <= _map_size.x
		and rect.end.y <= _map_size.y
	)


func _add_walkable_rect(rect: Rect2i) -> void:
	if not _rect_is_in_bounds(rect) or rect.size.x <= 0 or rect.size.y <= 0:
		return
	for x: int in range(rect.position.x, rect.end.x):
		for y: int in range(rect.position.y, rect.end.y):
			_walkable_cells[Vector2i(x, y)] = true


func _validate_position_dictionary(entries: Dictionary, context: String) -> void:
	for id_value: Variant in entries:
		var entry: Dictionary = _dictionary(entries[id_value])
		_validate_position(entry.get("position", []), "%s '%s'" % [context, id_value])


func _validate_position_entry(entry: Dictionary, context: String) -> void:
	_validate_position(
		entry.get("position", []),
		"%s '%s'" % [context, String(entry.get("id", ""))]
	)


func _validate_position(value: Variant, context: String, require_walkable: bool = true) -> void:
	var cell := _json_vector(value)
	var in_bounds := cell.x >= 0 and cell.y >= 0 and cell.x < _map_size.x and cell.y < _map_size.y
	_require(in_bounds, "BOUNDS: %s at %s is outside the map" % [context, cell])
	if in_bounds and require_walkable:
		_require(
			_walkable_cells.has(cell),
			"WALKABILITY: %s at %s is not on declared walkable floor" % [context, cell]
		)


func _add_room_links(
	entry: Dictionary,
	graph: Dictionary,
	rooms: Dictionary,
	context: String
) -> void:
	var entry_id := String(entry.get("id", ""))
	var connections: Array = _array(entry.get("connects", []))
	_require(
		connections.size() >= 2,
		"ROOM_GRAPH: %s '%s' must connect at least two rooms" % [context, entry_id]
	)
	for room_value: Variant in connections:
		var room_id := String(room_value)
		_require(
			rooms.has(room_id),
			"ROOM_GRAPH: %s '%s' references unknown room '%s'"
			% [context, entry_id, room_id]
		)
	for left_index: int in range(connections.size()):
		var left := String(connections[left_index])
		if not graph.has(left):
			continue
		for right_index: int in range(left_index + 1, connections.size()):
			var right := String(connections[right_index])
			if not graph.has(right):
				continue
			var left_edges: Array = _array(graph[left])
			var right_edges: Array = _array(graph[right])
			if not left_edges.has(right):
				left_edges.append(right)
			if not right_edges.has(left):
				right_edges.append(left)


func _collect_reachable_rooms(start: String, graph: Dictionary) -> Dictionary:
	var reachable: Dictionary = {start: true}
	var queue: Array[String] = [start]
	var cursor: int = 0
	while cursor < queue.size():
		var current: String = queue[cursor]
		cursor += 1
		for neighbor_value: Variant in _array(graph.get(current, [])):
			var neighbor := String(neighbor_value)
			if reachable.has(neighbor):
				continue
			reachable[neighbor] = true
			queue.append(neighbor)
	return reachable


func _validate_zone_dictionary(
	entries: Dictionary,
	rooms: Dictionary,
	reachable: Dictionary,
	context: String
) -> void:
	for id_value: Variant in entries:
		_validate_zone_entry(
			_dictionary(entries[id_value]), rooms, reachable, "%s '%s'" % [context, id_value]
		)


func _validate_zone_entry(
	entry: Dictionary,
	rooms: Dictionary,
	reachable: Dictionary,
	context: String
) -> void:
	var zone_id := String(entry.get("zone_id", ""))
	var entry_id := String(entry.get("id", ""))
	var label := context if entry_id.is_empty() else "%s '%s'" % [context, entry_id]
	_require(not zone_id.is_empty(), "ROOM_GRAPH: %s has no zone_id" % label)
	_require(rooms.has(zone_id), "ROOM_GRAPH: %s references unknown room '%s'" % [label, zone_id])
	_require(reachable.has(zone_id), "ROOM_GRAPH: %s room '%s' is unreachable" % [label, zone_id])


func _rank_for(level_id: String, access_ranks: Dictionary) -> int:
	_require(access_ranks.has(level_id), "ACCESS: unknown access level '%s'" % level_id)
	return int(access_ranks.get(level_id, -1))


func _json_vector(value: Variant) -> Vector2i:
	var values: Array = _array(value)
	if values.size() < 2:
		return Vector2i(-1, -1)
	return Vector2i(int(values[0]), int(values[1]))


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []


func _require(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
