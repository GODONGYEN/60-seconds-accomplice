class_name PatrolSchedulerTestSuite
extends Node

const BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)
const EXPECTED_TRACE_HEX_LENGTH: int = 64
const FLOAT_EPSILON: float = 0.0001

var _tree: SceneTree
var _expectation: Callable


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Operation Black Minute Patrol scheduler")
	var blueprint := _load_blueprint()
	_check(not blueprint.is_empty(), "Patrol suite loads the operation blueprint")
	if blueprint.is_empty():
		return
	await _test_runtime_reservations(blueprint)
	await _test_virtual_patrol_simulation(blueprint)


func _test_runtime_reservations(blueprint: Dictionary) -> void:
	var fixture := Node.new()
	_tree.root.add_child(fixture)
	var scheduler := PatrolScheduler.new()
	fixture.add_child(scheduler)
	_check(
		scheduler.configure_from_blueprint(blueprint),
		"PatrolScheduler accepts deterministic route and choke data"
	)
	_check(
		scheduler.get_validation_errors().is_empty(),
		"Patrol scheduler blueprint has no duplicate or invalid declarations"
	)
	_check(
		scheduler.get_choke_id_at_cell(Vector2i(12, 33)) == &"choke_yard_reception"
		and scheduler.get_choke_capacity(&"choke_yard_reception") == 1,
		"yard/reception connector resolves to its authored narrow capacity"
	)
	_check(
		scheduler.get_choke_id_at_cell(Vector2i(20, 38)) == &"choke_extraction_yard"
		and scheduler.get_choke_capacity(&"choke_extraction_yard") == 2,
		"wide extraction connector resolves to its authored capacity of two"
	)
	_check(
		_is_equal(scheduler.get_minimum_declared_safe_window_seconds(), 3.5),
		"shortest declared mandatory safe window is exactly 3.5 seconds"
	)
	var yard_two_data: Dictionary = {}
	for guard_variant: Variant in blueprint.get("guards", []) as Array:
		if (
			guard_variant is Dictionary
			and StringName(str((guard_variant as Dictionary).get("id", "")))
			== &"guard_yard_02"
		):
			yard_two_data = guard_variant as Dictionary
			break
	var yard_two_points: Array[Vector2] = []
	for cell_variant: Variant in yard_two_data.get("waypoints", []) as Array:
		yard_two_points.append(scheduler.cell_to_world(_parse_cell(cell_variant)))
	var yard_two_waits: Array[float] = []
	for wait_variant: Variant in yard_two_data.get("waypoint_wait_seconds", []) as Array:
		yard_two_waits.append(float(wait_variant))
	var yard_two_phase := PatrolScheduler.build_route_phase_state(
		yard_two_points,
		yard_two_waits,
		StringName(str(yard_two_data.get("route_mode", "LOOP"))),
		float(yard_two_data.get("movement_speed", 0.0)),
		float(yard_two_data.get("start_phase_seconds", 0.0))
	)
	_check(
		yard_two_phase.get("position", Vector2.ZERO) == scheduler.cell_to_world(Vector2i(10, 39))
		and int(yard_two_phase.get("waypoint_index", -1)) == 1
		and _is_equal(float(yard_two_phase.get("wait_remaining", 0.0)), 7.9)
		and not bool(yard_two_phase.get("in_transit", true)),
		"shared phase evaluator applies the authored 7.5-second offset and east-waypoint onboarding wait"
	)

	var registered_count: int = 0
	var guards_variant: Variant = blueprint.get("guards", [])
	if guards_variant is Array:
		for guard_variant: Variant in guards_variant as Array:
			if not guard_variant is Dictionary:
				continue
			var guard_data := guard_variant as Dictionary
			var guard_id := StringName(str(guard_data.get("id", "")))
			var spawn := _parse_cell(guard_data.get("spawn", []))
			if scheduler.register_guard(guard_id, scheduler.cell_to_world(spawn)):
				registered_count += 1
	_check(
		registered_count == 10,
		"all ten declared Guards register with stable scheduler IDs"
	)

	var shared_target := scheduler.cell_to_world(Vector2i(30, 25))
	scheduler.begin_reservation_tick()
	_check(
		scheduler.submit_move_intent(&"guard_yard_02", shared_target)
		and scheduler.submit_move_intent(&"guard_yard_01", shared_target),
		"two Guards can submit competing intents before resolution"
	)
	scheduler.resolve_move_intents()
	_check(
		scheduler.is_move_intent_approved(&"guard_yard_01")
		and not scheduler.is_move_intent_approved(&"guard_yard_02"),
		"lower stable Guard ID deterministically wins a shared tile reservation"
	)

	scheduler.begin_reservation_tick()
	_check(
		scheduler.submit_move_intent(
			&"guard_yard_01", scheduler.cell_to_world(Vector2i(12, 32))
		)
		and scheduler.submit_move_intent(
			&"guard_yard_02", scheduler.cell_to_world(Vector2i(13, 34))
		),
		"two Guards can request different cells in one narrow choke"
	)
	scheduler.resolve_move_intents()
	_check(
		scheduler.is_move_intent_approved(&"guard_yard_01")
		and not scheduler.is_move_intent_approved(&"guard_yard_02"),
		"narrow choke capacity permits exactly one stable-ID winner"
	)
	_check(
		scheduler.commit_guard_position(
			&"guard_yard_01", scheduler.cell_to_world(Vector2i(12, 32))
		),
		"approved reservation commits the Guard's authoritative position"
	)
	scheduler.begin_reservation_tick()
	_check(
		not scheduler.request_tile_reservation(
			&"guard_yard_02", Vector2i(13, 34), 0.25
		)
		and _is_equal(scheduler.get_guard_blocked_seconds(&"guard_yard_02"), 0.25),
		"occupied choke denial accumulates delta-based blocked time"
	)
	await _cleanup_fixture(fixture)


func _test_virtual_patrol_simulation(blueprint: Dictionary) -> void:
	var fixture := Node.new()
	_tree.root.add_child(fixture)
	var scheduler := PatrolScheduler.new()
	fixture.add_child(scheduler)
	var report := scheduler.run_patrol_simulation(blueprint, 180.0, 0.1)
	_check(bool(report.get("valid", false)), "180-second patrol report satisfies its contract")
	_check(
		_is_equal(float(report.get("duration_seconds", 0.0)), 180.0)
		and _is_equal(float(report.get("fixed_step_seconds", 0.0)), 0.1)
		and int(report.get("tick_count", 0)) == 1800,
		"patrol validation advances exactly 180 virtual seconds in 1,800 fixed steps"
	)
	_check(
		int(report.get("guard_count", 0)) == 10,
		"patrol validation simulates all ten mission Guards"
	)
	_check(
		int(report.get("guard_overlap_count", -1)) == 0,
		"180-second patrol trace contains zero same-tile Guard overlaps"
	)
	_check(
		int(report.get("choke_capacity_violations", -1)) == 0,
		"180-second patrol trace contains zero choke capacity violations"
	)
	_check(
		int(report.get("zone_violations", -1)) == 0,
		"all Guard samples remain inside their assigned patrol zones"
	)
	_check(
		int(report.get("deadlocks", -1)) == 0
		and _is_equal(float(report.get("max_blockage_seconds", -1.0)), 0.0),
		"deterministic routes have zero deadlocks and zero measured blockage"
	)
	_check(
		_is_equal(
			float(report.get("minimum_declared_safe_window_seconds", 0.0)), 3.5
		)
		and float(report.get("minimum_declared_safe_window_seconds", 0.0)) >= 3.0,
		"every mandatory corridor declares at least the required three-second safe window"
	)
	var opportunities_variant: Variant = report.get(
		"simulated_choke_open_opportunities", {}
	)
	var observed_opportunity_count: int = 0
	if opportunities_variant is Dictionary:
		for opportunity_variant: Variant in (opportunities_variant as Dictionary).values():
			if opportunity_variant is Dictionary:
				observed_opportunity_count += int(
					(opportunity_variant as Dictionary).get("opportunity_count", 0)
				)
	_check(
		opportunities_variant is Dictionary
		and (opportunities_variant as Dictionary).size() == 15
		and observed_opportunity_count == 26
		and _is_equal(
			float(report.get("minimum_simulated_capacity_open_seconds", 0.0)),
			15.4
		),
		"simulation separately measures 26 capacity openings with a 15.4-second minimum longest interval"
	)
	var trace_digest := String(report.get("trace_digest", ""))
	var repeat_digest := String(report.get("repeat_trace_digest", ""))
	_check(
		bool(report.get("deterministic", false))
		and trace_digest == repeat_digest,
		"two independent fixed-step runs produce the same patrol trace"
	)
	_check(
		trace_digest.length() == EXPECTED_TRACE_HEX_LENGTH
		and trace_digest.is_valid_hex_number(false),
		"patrol trace is represented by a valid SHA-256 hexadecimal digest"
	)
	var errors_variant: Variant = report.get("errors", PackedStringArray())
	_check(
		errors_variant is PackedStringArray
		and (errors_variant as PackedStringArray).is_empty(),
		"patrol report completes without simulation diagnostics"
	)
	await _cleanup_fixture(fixture)


func _load_blueprint() -> Dictionary:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _parse_cell(value: Variant) -> Vector2i:
	var values: Array = value as Array
	if values == null or values.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(values[0]), int(values[1]))


func _cleanup_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await _tree.process_frame
	await _tree.physics_frame


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)


func _is_equal(left: float, right: float) -> bool:
	return absf(left - right) <= FLOAT_EPSILON
