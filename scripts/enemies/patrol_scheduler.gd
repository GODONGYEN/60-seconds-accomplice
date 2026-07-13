class_name PatrolScheduler
extends Node

signal reservation_denied(guard_id: StringName, target_cell: Vector2i, reason: StringName)
signal reservation_resolved(guard_id: StringName, target_cell: Vector2i, approved: bool)

const DEFAULT_BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)
const SIMULATION_EPSILON: float = 0.000001
const DEFAULT_SIMULATION_SECONDS: float = 180.0
const DEFAULT_FIXED_STEP_SECONDS: float = 0.1
const DEADLOCK_SECONDS: float = 5.0

@export_range(1, 256, 1) var tile_size: int = 32

var _guard_positions: Dictionary[StringName, Vector2] = {}
var _guard_cells: Dictionary[StringName, Vector2i] = {}
var _guard_blocked_seconds: Dictionary[StringName, float] = {}
var _declared_guard_ids: Dictionary[StringName, bool] = {}
var _chokes: Dictionary[StringName, Dictionary] = {}
var _tile_reservations: Dictionary[Vector2i, StringName] = {}
var _guard_reservations: Dictionary[StringName, Vector2i] = {}
var _pending_intents: Dictionary[StringName, Vector2i] = {}
var _approved_intents: Dictionary[StringName, bool] = {}
var _validation_errors: PackedStringArray = PackedStringArray()
var _configured: bool = false
var _minimum_declared_safe_window_seconds: float = 0.0
var _reservation_timeout_seconds: float = 4.0


static func build_route_phase_state(
	waypoints: Array[Vector2],
	waits: Array[float],
	route_mode: StringName,
	movement_speed: float,
	phase_seconds: float
) -> Dictionary:
	if waypoints.is_empty():
		return {}
	var normalized_waits: Array[float] = []
	for index: int in range(waypoints.size()):
		normalized_waits.append(maxf(0.0, waits[index]) if index < waits.size() else 0.0)
	var state: Dictionary = {
		"route_mode": route_mode if route_mode != StringName() else &"LOOP",
		"waypoints": waypoints.duplicate(),
		"waits": normalized_waits,
		"movement_speed": maxf(0.0, movement_speed),
		"position": waypoints[0],
		"waypoint_index": 0,
		"route_direction": 1,
		"wait_remaining": normalized_waits[0],
		"phase_counter": 0,
		"in_transit": false,
	}
	advance_route_state(state, maxf(0.0, phase_seconds))
	return state


static func advance_route_state(state: Dictionary, delta: float) -> void:
	var remaining := maxf(0.0, delta)
	var iterations: int = 0
	while remaining > SIMULATION_EPSILON and iterations < 128:
		iterations += 1
		var wait_remaining := maxf(0.0, float(state.get("wait_remaining", 0.0)))
		if wait_remaining > SIMULATION_EPSILON:
			var consumed := minf(wait_remaining, remaining)
			state["wait_remaining"] = wait_remaining - consumed
			state["in_transit"] = false
			remaining -= consumed
			continue
		var waypoints: Array = state.get("waypoints", []) as Array
		var waits: Array = state.get("waits", []) as Array
		var waypoint_index := int(state.get("waypoint_index", 0))
		var route_mode := StringName(state.get("route_mode", &"LOOP"))
		if waypoints.size() < 2 or route_mode == &"STATIONARY_ROTATION":
			state["phase_counter"] = int(state.get("phase_counter", 0)) + 1
			state["in_transit"] = false
			var stationary_wait := (
				float(waits[waypoint_index]) if waypoint_index < waits.size() else 0.5
			)
			if stationary_wait <= SIMULATION_EPSILON:
				remaining = 0.0
			else:
				state["wait_remaining"] = stationary_wait
			continue
		var direction := int(state.get("route_direction", 1))
		var next_and_direction := next_route_index(
			waypoint_index, direction, waypoints.size(), route_mode
		)
		var next_index := next_and_direction.x
		state["route_direction"] = next_and_direction.y
		state["in_transit"] = true
		var position: Vector2 = state.get("position", Vector2.ZERO) as Vector2
		var target: Vector2 = waypoints[next_index] as Vector2
		var to_target := target - position
		var distance := to_target.length()
		var speed := maxf(0.0, float(state.get("movement_speed", 0.0)))
		if distance <= SIMULATION_EPSILON:
			state["position"] = target
			state["waypoint_index"] = next_index
			state["phase_counter"] = int(state.get("phase_counter", 0)) + 1
			state["wait_remaining"] = (
				float(waits[next_index]) if next_index < waits.size() else 0.0
			)
			state["in_transit"] = false
			continue
		if speed <= SIMULATION_EPSILON:
			remaining = 0.0
			continue
		var travel_time := distance / speed
		if travel_time <= remaining + SIMULATION_EPSILON:
			state["position"] = target
			state["waypoint_index"] = next_index
			state["phase_counter"] = int(state.get("phase_counter", 0)) + 1
			state["wait_remaining"] = (
				float(waits[next_index]) if next_index < waits.size() else 0.0
			)
			state["in_transit"] = false
			remaining = maxf(0.0, remaining - travel_time)
		else:
			state["position"] = position + to_target.normalized() * speed * remaining
			remaining = 0.0


static func next_route_index(
	current_index: int,
	direction: int,
	waypoint_count: int,
	route_mode: StringName
) -> Vector2i:
	if waypoint_count <= 1:
		return Vector2i(0, 1)
	if route_mode == &"PING_PONG" or route_mode == &"SHORT_SWEEP":
		var next_direction := 1 if direction >= 0 else -1
		if current_index >= waypoint_count - 1:
			next_direction = -1
		elif current_index <= 0:
			next_direction = 1
		return Vector2i(current_index + next_direction, next_direction)
	return Vector2i((current_index + 1) % waypoint_count, 1)


func load_blueprint(path: String = DEFAULT_BLUEPRINT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_configuration_error("PatrolScheduler could not open blueprint '%s'" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_configuration_error("PatrolScheduler blueprint '%s' is not a JSON object" % path)
		return false
	return configure_from_blueprint(parsed as Dictionary)


func configure_from_blueprint(blueprint: Dictionary) -> bool:
	_chokes.clear()
	_declared_guard_ids.clear()
	_validation_errors = PackedStringArray()
	_configured = false
	_minimum_declared_safe_window_seconds = INF
	clear_runtime(true)

	var parsed_tile_size := int(blueprint.get("tile_size", 0))
	if parsed_tile_size <= 0:
		_add_validation_error("blueprint tile_size must be positive")
	else:
		tile_size = parsed_tile_size

	var scheduler_variant: Variant = blueprint.get("patrol_scheduler", {})
	if scheduler_variant is Dictionary:
		var scheduler := scheduler_variant as Dictionary
		if not bool(scheduler.get("deterministic", false)):
			_add_validation_error("patrol_scheduler.deterministic must be true")
		if bool(scheduler.get("randomness_allowed", true)):
			_add_validation_error("patrol_scheduler.randomness_allowed must be false")
		_reservation_timeout_seconds = maxf(
			0.1, float(scheduler.get("reservation_timeout_seconds", 4.0))
		)
	else:
		_add_validation_error("blueprint patrol_scheduler must be an object")

	var guards_variant: Variant = blueprint.get("guards", [])
	if not guards_variant is Array:
		_add_validation_error("blueprint guards must be an array")
	else:
		for guard_variant: Variant in guards_variant as Array:
			if not guard_variant is Dictionary:
				_add_validation_error("guards contains a non-object entry")
				continue
			var guard_id := StringName(str((guard_variant as Dictionary).get("id", "")))
			if guard_id == StringName():
				_add_validation_error("Guard definition has an empty id")
			elif _declared_guard_ids.has(guard_id):
				_add_validation_error("duplicate Guard id '%s'" % guard_id)
			else:
				_declared_guard_ids[guard_id] = true

	var chokes_variant: Variant = blueprint.get("choke_points", [])
	if not chokes_variant is Array:
		_add_validation_error("blueprint choke_points must be an array")
	else:
		for choke_variant: Variant in chokes_variant as Array:
			if choke_variant is Dictionary:
				_parse_choke(choke_variant as Dictionary)
			else:
				_add_validation_error("choke_points contains a non-object entry")
	if is_inf(_minimum_declared_safe_window_seconds):
		_minimum_declared_safe_window_seconds = 0.0

	_configured = _validation_errors.is_empty()
	if not _configured:
		for message: String in _validation_errors:
			push_error("PatrolScheduler: %s" % message)
	return _configured


func is_configured() -> bool:
	return _configured


func get_validation_errors() -> PackedStringArray:
	return _validation_errors.duplicate()


func get_minimum_declared_safe_window_seconds() -> float:
	return _minimum_declared_safe_window_seconds


func register_guard(guard_id: StringName, world_position: Vector2) -> bool:
	if guard_id == StringName():
		push_error("PatrolScheduler rejected an empty Guard ID")
		return false
	if not _declared_guard_ids.is_empty() and not _declared_guard_ids.has(guard_id):
		push_error("PatrolScheduler rejected undeclared Guard '%s'" % guard_id)
		return false
	_guard_positions[guard_id] = world_position
	_guard_cells[guard_id] = world_to_cell(world_position)
	_guard_blocked_seconds[guard_id] = 0.0
	return true


func unregister_guard(guard_id: StringName) -> bool:
	if not _guard_positions.has(guard_id):
		return false
	_guard_positions.erase(guard_id)
	_guard_cells.erase(guard_id)
	_guard_blocked_seconds.erase(guard_id)
	release_guard_reservation(guard_id)
	_pending_intents.erase(guard_id)
	_approved_intents.erase(guard_id)
	return true


func clear_runtime(clear_guards: bool = false) -> void:
	_tile_reservations.clear()
	_guard_reservations.clear()
	_pending_intents.clear()
	_approved_intents.clear()
	if clear_guards:
		_guard_positions.clear()
		_guard_cells.clear()
		_guard_blocked_seconds.clear()
	else:
		for guard_id: StringName in _guard_blocked_seconds:
			_guard_blocked_seconds[guard_id] = 0.0


func begin_reservation_tick() -> void:
	_tile_reservations.clear()
	_guard_reservations.clear()
	_pending_intents.clear()
	_approved_intents.clear()


func submit_move_intent(guard_id: StringName, target_world_position: Vector2) -> bool:
	if not _guard_positions.has(guard_id):
		return false
	_pending_intents[guard_id] = world_to_cell(target_world_position)
	return true


func resolve_move_intents() -> void:
	_tile_reservations.clear()
	_guard_reservations.clear()
	_approved_intents.clear()
	var guard_ids: Array[StringName] = []
	guard_ids.assign(_pending_intents.keys())
	guard_ids.sort_custom(_string_name_less_than)
	for guard_id: StringName in guard_ids:
		var target_cell: Vector2i = _pending_intents[guard_id]
		var approved := request_tile_reservation(guard_id, target_cell)
		_approved_intents[guard_id] = approved
		reservation_resolved.emit(guard_id, target_cell, approved)


func is_move_intent_approved(guard_id: StringName) -> bool:
	return bool(_approved_intents.get(guard_id, false))


func request_world_reservation(
	guard_id: StringName,
	target_world_position: Vector2,
	blocked_delta: float = 0.0
) -> bool:
	return request_tile_reservation(
		guard_id, world_to_cell(target_world_position), blocked_delta
	)


func request_tile_reservation(
	guard_id: StringName,
	target_cell: Vector2i,
	blocked_delta: float = 0.0
) -> bool:
	if not _guard_cells.has(guard_id):
		reservation_denied.emit(guard_id, target_cell, &"unregistered_guard")
		return false
	var occupant := _get_guard_at_cell(target_cell, guard_id)
	if occupant != StringName():
		_note_guard_blocked(guard_id, blocked_delta)
		reservation_denied.emit(guard_id, target_cell, &"occupied_tile")
		return false
	var existing_owner: StringName = _tile_reservations.get(target_cell, StringName())
	if existing_owner != StringName() and existing_owner != guard_id:
		_note_guard_blocked(guard_id, blocked_delta)
		reservation_denied.emit(guard_id, target_cell, &"reserved_tile")
		return false
	var current_cell: Vector2i = _guard_cells[guard_id]
	var target_choke := get_choke_id_at_cell(target_cell)
	var current_choke := get_choke_id_at_cell(current_cell)
	if target_choke != StringName() and target_choke != current_choke:
		var owners := _get_runtime_choke_owners(target_choke)
		if owners.size() >= get_choke_capacity(target_choke):
			_note_guard_blocked(guard_id, blocked_delta)
			reservation_denied.emit(guard_id, target_cell, &"choke_at_capacity")
			return false
	release_guard_reservation(guard_id)
	_tile_reservations[target_cell] = guard_id
	_guard_reservations[guard_id] = target_cell
	_guard_blocked_seconds[guard_id] = 0.0
	return true


func commit_guard_position(guard_id: StringName, world_position: Vector2) -> bool:
	if not _guard_positions.has(guard_id):
		return false
	_guard_positions[guard_id] = world_position
	_guard_cells[guard_id] = world_to_cell(world_position)
	_guard_blocked_seconds[guard_id] = 0.0
	return true


func release_guard_reservation(guard_id: StringName) -> void:
	if not _guard_reservations.has(guard_id):
		return
	var reserved_cell: Vector2i = _guard_reservations[guard_id]
	if _tile_reservations.get(reserved_cell, StringName()) == guard_id:
		_tile_reservations.erase(reserved_cell)
	_guard_reservations.erase(guard_id)


func get_guard_blocked_seconds(guard_id: StringName) -> float:
	return float(_guard_blocked_seconds.get(guard_id, 0.0))


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floor(world_position / float(tile_size)))


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * tile_size) + Vector2.ONE * float(tile_size) * 0.5


func get_choke_id_at_cell(cell: Vector2i) -> StringName:
	var choke_ids: Array[StringName] = []
	choke_ids.assign(_chokes.keys())
	choke_ids.sort_custom(_string_name_less_than)
	for choke_id: StringName in choke_ids:
		var choke: Dictionary = _chokes[choke_id]
		var rect: Rect2i = choke.get("rect", Rect2i()) as Rect2i
		if rect.has_point(cell):
			return choke_id
	return StringName()


func get_choke_capacity(choke_id: StringName) -> int:
	var choke: Dictionary = _chokes.get(choke_id, {}) as Dictionary
	return int(choke.get("capacity", 0))


func run_patrol_simulation(
	blueprint: Dictionary,
	duration_seconds: float = DEFAULT_SIMULATION_SECONDS,
	fixed_step_seconds: float = DEFAULT_FIXED_STEP_SECONDS
) -> Dictionary:
	var configuration_succeeded := configure_from_blueprint(blueprint)
	var safe_duration := maxf(0.0, duration_seconds)
	var safe_step := maxf(0.001, fixed_step_seconds)
	if not configuration_succeeded or safe_duration <= 0.0:
		return _failed_simulation_report(safe_duration, safe_step)
	var first := _simulate_once(blueprint, safe_duration, safe_step)
	var second := _simulate_once(blueprint, safe_duration, safe_step)
	var deterministic := (
		String(first.get("trace_digest", ""))
		== String(second.get("trace_digest", ""))
	)
	first["repeat_trace_digest"] = second.get("trace_digest", "")
	first["deterministic"] = deterministic
	var contract: Dictionary = blueprint.get("validation_contract", {}) as Dictionary
	var required_guard_count := int(contract.get("required_guard_count", 0))
	var maximum_overlaps := int(contract.get("maximum_guard_overlap_count", 0))
	var maximum_choke_violations := int(
		contract.get("maximum_choke_capacity_violations", 0)
	)
	var maximum_zone_violations := int(contract.get("maximum_zone_violations", 0))
	var maximum_deadlocks := int(contract.get("maximum_deadlocks", 0))
	var has_declared_window_contract := contract.has(
		"minimum_declared_safe_window_seconds"
	)
	var minimum_declared_safe_window := float(
		contract.get("minimum_declared_safe_window_seconds", 0.0)
	)
	first["valid"] = (
		deterministic
		and has_declared_window_contract
		and int(first.get("guard_count", 0)) == required_guard_count
		and int(first.get("guard_overlap_count", -1)) <= maximum_overlaps
		and int(first.get("choke_capacity_violations", -1))
			<= maximum_choke_violations
		and int(first.get("zone_violations", -1)) <= maximum_zone_violations
		and int(first.get("deadlocks", -1)) <= maximum_deadlocks
		and float(first.get("minimum_declared_safe_window_seconds", 0.0))
			+ SIMULATION_EPSILON >= minimum_declared_safe_window
	)
	return first


func run_default_patrol_simulation() -> Dictionary:
	var file := FileAccess.open(DEFAULT_BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		_set_configuration_error(
			"PatrolScheduler could not open blueprint '%s'" % DEFAULT_BLUEPRINT_PATH
		)
		return _failed_simulation_report(
			DEFAULT_SIMULATION_SECONDS, DEFAULT_FIXED_STEP_SECONDS
		)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_configuration_error("PatrolScheduler default blueprint is not a JSON object")
		return _failed_simulation_report(
			DEFAULT_SIMULATION_SECONDS, DEFAULT_FIXED_STEP_SECONDS
		)
	return run_patrol_simulation(parsed as Dictionary)


func _simulate_once(
	blueprint: Dictionary,
	duration_seconds: float,
	fixed_step_seconds: float
) -> Dictionary:
	var errors: Array[String] = []
	var states := _build_simulation_states(blueprint, errors)
	var zone_rects := _build_zone_rects(blueprint, errors)
	var guard_ids: Array[StringName] = []
	guard_ids.assign(states.keys())
	guard_ids.sort_custom(_string_name_less_than)
	var tick_count := int(ceil(duration_seconds / fixed_step_seconds))
	var overlap_count: int = 0
	var choke_capacity_violations: int = 0
	var zone_violations: int = 0
	var deadlocks: int = 0
	var max_blockage_seconds: float = 0.0
	var choke_open_tracking := _build_choke_open_tracking()
	var hash_context := HashingContext.new()
	var hash_error := hash_context.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		errors.append("could not initialize SHA-256 trace hashing")

	for tick_index: int in range(tick_count):
		var step_seconds := minf(
			fixed_step_seconds,
			maxf(0.0, duration_seconds - float(tick_index) * fixed_step_seconds)
		)
		var proposals: Dictionary[StringName, Dictionary] = {}
		for guard_id: StringName in guard_ids:
			var proposed: Dictionary = (states[guard_id] as Dictionary).duplicate(true)
			advance_route_state(proposed, step_seconds)
			proposals[guard_id] = proposed
		_apply_simulation_proposals(states, proposals, guard_ids, step_seconds)

		for guard_id: StringName in guard_ids:
			var state: Dictionary = states[guard_id]
			var blocked_seconds := float(state.get("blocked_seconds", 0.0))
			max_blockage_seconds = maxf(max_blockage_seconds, blocked_seconds)
			if (
				blocked_seconds + SIMULATION_EPSILON >= DEADLOCK_SECONDS
				and not bool(state.get("deadlock_reported", false))
			):
				state["deadlock_reported"] = true
				deadlocks += 1
		overlap_count += _count_simulation_overlaps(states, guard_ids)
		choke_capacity_violations += _count_simulation_choke_violations(states)
		_update_choke_open_tracking(choke_open_tracking, states, step_seconds)
		zone_violations += _count_simulation_zone_violations(states, zone_rects)
		if hash_error == OK:
			_update_trace_hash(hash_context, tick_index, states, guard_ids)

	var digest := ""
	if hash_error == OK:
		digest = hash_context.finish().hex_encode()
	var choke_open_report := _build_choke_open_report(choke_open_tracking)
	return {
		"duration_seconds": duration_seconds,
		"fixed_step_seconds": fixed_step_seconds,
		"tick_count": tick_count,
		"guard_count": states.size(),
		"guard_overlap_count": overlap_count,
		"choke_capacity_violations": choke_capacity_violations,
		"zone_violations": zone_violations,
		"deadlocks": deadlocks,
		"max_blockage_seconds": max_blockage_seconds,
		"minimum_declared_safe_window_seconds": _minimum_declared_safe_window_seconds,
		"simulated_choke_open_opportunities": choke_open_report.get("opportunities", {}),
		"minimum_simulated_capacity_open_seconds": float(
			choke_open_report.get("minimum_longest_open_seconds", 0.0)
		),
		"trace_digest": digest,
		"errors": PackedStringArray(errors),
	}


func _build_simulation_states(
	blueprint: Dictionary,
	errors: Array[String]
) -> Dictionary[StringName, Dictionary]:
	var states: Dictionary[StringName, Dictionary] = {}
	var guards_variant: Variant = blueprint.get("guards", [])
	if not guards_variant is Array:
		errors.append("blueprint guards must be an array")
		return states
	for guard_variant: Variant in guards_variant as Array:
		if not guard_variant is Dictionary:
			continue
		var guard_data := guard_variant as Dictionary
		var guard_id := StringName(str(guard_data.get("id", "")))
		var waypoints := _parse_world_waypoints(guard_data.get("waypoints", []))
		if guard_id == StringName() or waypoints.is_empty():
			errors.append("simulation Guard requires an id and at least one waypoint")
			continue
		var waits := _parse_waits(
			guard_data.get("waypoint_wait_seconds", []), waypoints.size()
		)
		var state := build_route_phase_state(
			waypoints,
			waits,
			StringName(str(guard_data.get("route_mode", "LOOP"))),
			maxf(0.0, float(guard_data.get("movement_speed", 0.0))),
			maxf(0.0, float(guard_data.get("start_phase_seconds", 0.0)))
		)
		state.merge({
			"guard_id": guard_id,
			"zone_id": StringName(str(guard_data.get("zone_id", ""))),
			"blocked_seconds": 0.0,
			"deadlock_reported": false,
		}, true)
		states[guard_id] = state
	return states


func _build_zone_rects(
	blueprint: Dictionary,
	errors: Array[String]
) -> Dictionary[StringName, Rect2]:
	var rects: Dictionary[StringName, Rect2] = {}
	var zones_variant: Variant = blueprint.get("guard_zones", [])
	if not zones_variant is Array:
		errors.append("blueprint guard_zones must be an array")
		return rects
	for zone_variant: Variant in zones_variant as Array:
		if not zone_variant is Dictionary:
			continue
		var zone_data := zone_variant as Dictionary
		var zone_id := StringName(str(zone_data.get("id", "")))
		var rect_cells := _parse_rect(zone_data.get("allowed_rect", []))
		if zone_id == StringName() or rect_cells.size.x <= 0 or rect_cells.size.y <= 0:
			errors.append("simulation guard zone requires a valid id and allowed_rect")
			continue
		rects[zone_id] = Rect2(
			Vector2(rect_cells.position * tile_size),
			Vector2(rect_cells.size * tile_size)
		)
	return rects


func _apply_simulation_proposals(
	states: Dictionary[StringName, Dictionary],
	proposals: Dictionary[StringName, Dictionary],
	guard_ids: Array[StringName],
	step_seconds: float
) -> void:
	var occupied: Dictionary[Vector2i, StringName] = {}
	var choke_counts: Dictionary[StringName, int] = {}
	for guard_id: StringName in guard_ids:
		var state: Dictionary = states[guard_id]
		var cell := world_to_cell(state.get("position", Vector2.ZERO) as Vector2)
		if not occupied.has(cell):
			occupied[cell] = guard_id
		var choke_id := get_choke_id_at_cell(cell)
		if choke_id != StringName():
			choke_counts[choke_id] = int(choke_counts.get(choke_id, 0)) + 1

	var reserved_targets: Dictionary[Vector2i, StringName] = {}
	for guard_id: StringName in guard_ids:
		var state: Dictionary = states[guard_id]
		var proposal: Dictionary = proposals[guard_id]
		var current_position: Vector2 = state.get("position", Vector2.ZERO) as Vector2
		var target_position: Vector2 = proposal.get("position", current_position) as Vector2
		var current_cell := world_to_cell(current_position)
		var target_cell := world_to_cell(target_position)
		var approved := true
		var occupant: StringName = occupied.get(target_cell, StringName())
		if target_cell != current_cell and occupant != StringName() and occupant != guard_id:
			approved = false
		var reservation_owner: StringName = reserved_targets.get(target_cell, StringName())
		if reservation_owner != StringName() and reservation_owner != guard_id:
			approved = false
		var current_choke := get_choke_id_at_cell(current_cell)
		var target_choke := get_choke_id_at_cell(target_cell)
		if target_choke != StringName() and target_choke != current_choke:
			if int(choke_counts.get(target_choke, 0)) >= get_choke_capacity(target_choke):
				approved = false
		if approved:
			occupied.erase(current_cell)
			occupied[target_cell] = guard_id
			reserved_targets[target_cell] = guard_id
			if current_choke != target_choke:
				if current_choke != StringName():
					choke_counts[current_choke] = maxi(
						0, int(choke_counts.get(current_choke, 0)) - 1
					)
				if target_choke != StringName():
					choke_counts[target_choke] = int(choke_counts.get(target_choke, 0)) + 1
			proposal["blocked_seconds"] = 0.0
			proposal["deadlock_reported"] = bool(state.get("deadlock_reported", false))
			states[guard_id] = proposal
		else:
			state["blocked_seconds"] = float(state.get("blocked_seconds", 0.0)) + step_seconds


func _count_simulation_overlaps(
	states: Dictionary[StringName, Dictionary],
	guard_ids: Array[StringName]
) -> int:
	var count: int = 0
	for left_index: int in range(guard_ids.size()):
		var left: Dictionary = states[guard_ids[left_index]]
		var left_cell := world_to_cell(left.get("position", Vector2.ZERO) as Vector2)
		for right_index: int in range(left_index + 1, guard_ids.size()):
			var right: Dictionary = states[guard_ids[right_index]]
			var right_cell := world_to_cell(right.get("position", Vector2.ZERO) as Vector2)
			if left_cell == right_cell:
				count += 1
	return count


func _count_simulation_choke_violations(
	states: Dictionary[StringName, Dictionary]
) -> int:
	var counts: Dictionary[StringName, int] = {}
	for guard_id: StringName in states:
		var state: Dictionary = states[guard_id]
		var choke_id := get_choke_id_at_cell(
			world_to_cell(state.get("position", Vector2.ZERO) as Vector2)
		)
		if choke_id != StringName():
			counts[choke_id] = int(counts.get(choke_id, 0)) + 1
	var violations: int = 0
	for choke_id: StringName in counts:
		if counts[choke_id] > get_choke_capacity(choke_id):
			violations += 1
	return violations


func _count_simulation_zone_violations(
	states: Dictionary[StringName, Dictionary],
	zone_rects: Dictionary[StringName, Rect2]
) -> int:
	var violations: int = 0
	for guard_id: StringName in states:
		var state: Dictionary = states[guard_id]
		var zone_id := StringName(state.get("zone_id", StringName()))
		if not zone_rects.has(zone_id):
			violations += 1
			continue
		var position: Vector2 = state.get("position", Vector2.ZERO) as Vector2
		if not zone_rects[zone_id].has_point(position):
			violations += 1
	return violations


func _build_choke_open_tracking() -> Dictionary[StringName, Dictionary]:
	var tracking: Dictionary[StringName, Dictionary] = {}
	for choke_id: StringName in _sorted_choke_ids():
		tracking[choke_id] = {
			"current_open_seconds": 0.0,
			"longest_open_seconds": 0.0,
			"opportunity_count": 0,
		}
	return tracking


func _update_choke_open_tracking(
	tracking: Dictionary[StringName, Dictionary],
	states: Dictionary[StringName, Dictionary],
	step_seconds: float
) -> void:
	var occupancy: Dictionary[StringName, int] = {}
	for guard_id: StringName in states:
		var state: Dictionary = states[guard_id]
		var choke_id := get_choke_id_at_cell(
			world_to_cell(state.get("position", Vector2.ZERO) as Vector2)
		)
		if choke_id != StringName():
			occupancy[choke_id] = int(occupancy.get(choke_id, 0)) + 1
	for choke_id: StringName in _sorted_choke_ids():
		var state: Dictionary = tracking[choke_id]
		var capacity_available := (
			int(occupancy.get(choke_id, 0)) < get_choke_capacity(choke_id)
		)
		if not capacity_available:
			state["current_open_seconds"] = 0.0
			continue
		if float(state.get("current_open_seconds", 0.0)) <= SIMULATION_EPSILON:
			state["opportunity_count"] = int(state.get("opportunity_count", 0)) + 1
		var current := float(state.get("current_open_seconds", 0.0)) + step_seconds
		state["current_open_seconds"] = current
		state["longest_open_seconds"] = maxf(
			float(state.get("longest_open_seconds", 0.0)), current
		)


func _build_choke_open_report(
	tracking: Dictionary[StringName, Dictionary]
) -> Dictionary:
	var opportunities: Dictionary[StringName, Dictionary] = {}
	var minimum_longest := INF
	for choke_id: StringName in _sorted_choke_ids():
		var state: Dictionary = tracking.get(choke_id, {}) as Dictionary
		var longest := float(state.get("longest_open_seconds", 0.0))
		minimum_longest = minf(minimum_longest, longest)
		opportunities[choke_id] = {
			"opportunity_count": int(state.get("opportunity_count", 0)),
			"longest_capacity_open_seconds": longest,
		}
	return {
		"opportunities": opportunities,
		"minimum_longest_open_seconds": (
			0.0 if is_inf(minimum_longest) else minimum_longest
		),
	}


func _sorted_choke_ids() -> Array[StringName]:
	var choke_ids: Array[StringName] = []
	choke_ids.assign(_chokes.keys())
	choke_ids.sort_custom(_string_name_less_than)
	return choke_ids


func _update_trace_hash(
	context: HashingContext,
	tick_index: int,
	states: Dictionary[StringName, Dictionary],
	guard_ids: Array[StringName]
) -> void:
	context.update(("%d|" % tick_index).to_utf8_buffer())
	for guard_id: StringName in guard_ids:
		var state: Dictionary = states[guard_id]
		var position: Vector2 = state.get("position", Vector2.ZERO) as Vector2
		var trace_entry := "%s:%s,%s:%d:%d;" % [
			guard_id,
			String.num(position.x, 3),
			String.num(position.y, 3),
			int(state.get("waypoint_index", 0)),
			int(state.get("phase_counter", 0)),
		]
		context.update(trace_entry.to_utf8_buffer())


func _parse_choke(source: Dictionary) -> void:
	var choke_id := StringName(str(source.get("id", "")))
	if choke_id == StringName():
		_add_validation_error("choke point has an empty id")
		return
	if _chokes.has(choke_id):
		_add_validation_error("duplicate choke point id '%s'" % choke_id)
		return
	var rect := _parse_rect(source.get("rect", []))
	var capacity := int(source.get("capacity", 0))
	if rect.size.x <= 0 or rect.size.y <= 0:
		_add_validation_error("choke '%s' has an invalid rect" % choke_id)
	if capacity <= 0:
		_add_validation_error("choke '%s' capacity must be positive" % choke_id)
	var safe_windows: Array[Dictionary] = []
	var windows_variant: Variant = source.get("safe_windows", [])
	if windows_variant is Array:
		for window_variant: Variant in windows_variant as Array:
			if not window_variant is Dictionary:
				_add_validation_error("choke '%s' has a non-object safe window" % choke_id)
				continue
			var window := window_variant as Dictionary
			var duration := float(window.get("duration_seconds", 0.0))
			if duration <= 0.0:
				_add_validation_error("choke '%s' has a non-positive safe window" % choke_id)
				continue
			_minimum_declared_safe_window_seconds = minf(
				_minimum_declared_safe_window_seconds, duration
			)
			safe_windows.append(window.duplicate(true))
	else:
		_add_validation_error("choke '%s' safe_windows must be an array" % choke_id)
	_chokes[choke_id] = {
		"rect": rect,
		"capacity": capacity,
		"safe_windows": safe_windows,
		"cycle_seconds": maxf(0.0, float(source.get("cycle_seconds", 0.0))),
	}


func _parse_world_waypoints(value: Variant) -> Array[Vector2]:
	var waypoints: Array[Vector2] = []
	if not value is Array:
		return waypoints
	for cell_variant: Variant in value as Array:
		var values: Array = cell_variant as Array
		if values == null or values.size() != 2:
			continue
		waypoints.append(cell_to_world(Vector2i(int(values[0]), int(values[1]))))
	return waypoints


func _parse_waits(value: Variant, required_count: int) -> Array[float]:
	var waits: Array[float] = []
	if value is Array:
		for wait_variant: Variant in value as Array:
			waits.append(maxf(0.0, float(wait_variant)))
	while waits.size() < required_count:
		waits.append(0.0)
	if waits.size() > required_count:
		waits.resize(required_count)
	return waits


func _parse_rect(value: Variant) -> Rect2i:
	var values: Array = value as Array
	if values == null or values.size() != 4:
		return Rect2i()
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _get_guard_at_cell(cell: Vector2i, excluded_guard_id: StringName) -> StringName:
	var guard_ids: Array[StringName] = []
	guard_ids.assign(_guard_cells.keys())
	guard_ids.sort_custom(_string_name_less_than)
	for guard_id: StringName in guard_ids:
		if guard_id != excluded_guard_id and _guard_cells[guard_id] == cell:
			return guard_id
	return StringName()


func _get_runtime_choke_owners(choke_id: StringName) -> Array[StringName]:
	var owners: Array[StringName] = []
	for guard_id: StringName in _guard_cells:
		if get_choke_id_at_cell(_guard_cells[guard_id]) == choke_id:
			owners.append(guard_id)
	for guard_id: StringName in _guard_reservations:
		if (
			get_choke_id_at_cell(_guard_reservations[guard_id]) == choke_id
			and not owners.has(guard_id)
		):
			owners.append(guard_id)
	owners.sort_custom(_string_name_less_than)
	return owners


func _note_guard_blocked(guard_id: StringName, delta: float) -> void:
	_guard_blocked_seconds[guard_id] = (
		float(_guard_blocked_seconds.get(guard_id, 0.0)) + maxf(0.0, delta)
	)


func _failed_simulation_report(duration_seconds: float, fixed_step_seconds: float) -> Dictionary:
	return {
		"duration_seconds": duration_seconds,
		"fixed_step_seconds": fixed_step_seconds,
		"tick_count": 0,
		"guard_count": 0,
		"guard_overlap_count": 0,
		"choke_capacity_violations": 0,
		"zone_violations": 0,
		"deadlocks": 0,
		"max_blockage_seconds": 0.0,
		"minimum_declared_safe_window_seconds": 0.0,
		"simulated_choke_open_opportunities": {},
		"minimum_simulated_capacity_open_seconds": 0.0,
		"trace_digest": "",
		"repeat_trace_digest": "",
		"deterministic": false,
		"valid": false,
		"errors": _validation_errors.duplicate(),
	}


func _set_configuration_error(message: String) -> void:
	_chokes.clear()
	_declared_guard_ids.clear()
	_validation_errors = PackedStringArray([message])
	_configured = false
	clear_runtime(true)
	push_error(message)


func _add_validation_error(message: String) -> void:
	_validation_errors.append(message)


func _string_name_less_than(left: StringName, right: StringName) -> bool:
	return String(left) < String(right)
