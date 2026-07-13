class_name GuardZoneTestSuite
extends Node

const BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)

var _tree: SceneTree
var _expectation: Callable


class TestGuard:
	extends Node2D

	var guard_id: StringName
	var zone_id: StringName
	var alert_count: int = 0
	var last_alert_source: StringName = StringName()

	func _init(configured_guard_id: StringName, configured_zone_id: StringName) -> void:
		guard_id = configured_guard_id
		zone_id = configured_zone_id

	func get_object_id() -> StringName:
		return guard_id

	func get_zone_id() -> StringName:
		return zone_id

	func receive_zone_alert(
		_position: Vector2,
		source_id: StringName,
		_source_zone_id: StringName
	) -> void:
		alert_count += 1
		last_alert_source = source_id


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Operation Black Minute Guard zones")
	var blueprint := _load_blueprint()
	_check(not blueprint.is_empty(), "Guard-zone suite loads the operation blueprint")
	if blueprint.is_empty():
		return
	await _test_zone_contract(blueprint)
	_test_proximity_contract(blueprint)


func _test_zone_contract(blueprint: Dictionary) -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var manager := GuardZoneManager.new()
	fixture.add_child(manager)
	_check(
		manager.configure_from_blueprint(blueprint),
		"GuardZoneManager accepts the complete authored zone contract"
	)
	_check(
		manager.get_validation_errors().is_empty(),
		"Guard-zone blueprint has no assignment or adjacency errors"
	)
	_check(
		manager.get_zone_ids().size() == 7,
		"Operation Black Minute defines exactly seven bounded Guard zones"
	)
	_check(
		manager.get_zone_rect_cells(&"zone_outer_yard") == Rect2i(1, 28, 13, 13)
		and manager.get_zone_rect_cells(&"zone_vault") == Rect2i(52, 3, 11, 31),
		"outer-yard and vault zone rectangles match the blueprint"
	)
	var cctv_adjacent := manager.get_adjacent_zone_ids(&"zone_cctv")
	_check(
		cctv_adjacent == [&"zone_office", &"zone_research"],
		"CCTV alerts are bounded to the office and research neighbors"
	)

	var inside_outer := Vector2(160.0, 1088.0)
	_check(
		manager.clamp_to_chase_bounds(&"zone_outer_yard", inside_outer) == inside_outer,
		"a chase target already inside the home zone is not displaced"
	)
	var clamped := manager.clamp_to_chase_bounds(
		&"zone_outer_yard", Vector2(2000.0, 100.0)
	)
	_check(
		manager.is_position_in_zone(&"zone_outer_yard", clamped)
		or manager.is_position_in_zone(&"zone_reception", clamped),
		"an out-of-bounds chase target clamps to the home/adjacent zone union"
	)
	_check(
		not manager.is_position_in_zone(&"zone_vault", clamped),
		"outer-zone chase clamping cannot leak into the vault wing"
	)
	var reception_position := manager.get_zone_anchor_world(&"zone_reception")
	_check(
		manager.clamp_guard_to_chase_bounds(&"guard_yard_01", reception_position)
		== reception_position,
		"Guard-specific chase wiring permits an explicitly authored adjacent zone"
	)
	var yard_two_clamped := manager.clamp_guard_to_chase_bounds(
		&"guard_yard_02", reception_position
	)
	_check(
		manager.is_position_in_zone(&"zone_outer_yard", yard_two_clamped)
		and yard_two_clamped != reception_position,
		"Guard-specific chase wiring rejects adjacent zones omitted by that Guard"
	)

	var guards: Dictionary[StringName, TestGuard] = {}
	var registration_count: int = 0
	var guards_variant: Variant = blueprint.get("guards", [])
	if guards_variant is Array:
		for guard_variant: Variant in guards_variant as Array:
			if not guard_variant is Dictionary:
				continue
			var guard_data := guard_variant as Dictionary
			var guard_id := StringName(str(guard_data.get("id", "")))
			var zone_id := StringName(str(guard_data.get("zone_id", "")))
			var guard := TestGuard.new(guard_id, zone_id)
			fixture.add_child(guard)
			guards[guard_id] = guard
			if manager.register_guard(guard, zone_id):
				registration_count += 1
	_check(
		registration_count == 10,
		"all ten required Guards register against their declared zones"
	)
	_check(
		manager.get_registered_guard_ids().size() == 10
		and manager.validate_registered_assignments(true),
		"registered Guard assignments are complete and capacity-valid"
	)
	_check(
		manager.get_registered_guard_ids(&"zone_outer_yard").size() == 2
		and manager.get_registered_guard_ids(&"zone_research").size() == 2
		and manager.get_registered_guard_ids(&"zone_vault").size() == 2,
		"multi-Guard zones retain their authored density caps"
	)
	_check(
		manager.get_registered_guard_ids(&"zone_reception").size() == 1
		and manager.get_registered_guard_ids(&"zone_office").size() == 1
		and manager.get_registered_guard_ids(&"zone_cctv").size() == 1
		and manager.get_registered_guard_ids(&"zone_electrical").size() == 1,
		"single-Guard zones each contain exactly their assigned Guard"
	)

	var recipients := manager.propagate_zone_alert(
		&"zone_cctv", Vector2(640.0, 192.0), &"camera_cctv_01", true
	)
	_check(
		recipients.size() == 4
		and recipients.has("guard_cctv_01")
		and recipients.has("guard_office_01")
		and recipients.has("guard_server_01")
		and recipients.has("guard_research_01"),
		"CCTV-zone alert reaches only its own and adjacent-zone Guards"
	)
	_check(
		not recipients.has("guard_yard_01")
		and not recipients.has("guard_reception_01")
		and not recipients.has("guard_electrical_01")
		and not recipients.has("guard_vault_01"),
		"CCTV-zone alert does not become a facility-wide omniscient alert"
	)
	var recipient_callbacks_valid: bool = true
	for guard_id: StringName in guards:
		var guard: TestGuard = guards[guard_id]
		var should_receive := recipients.has(String(guard_id))
		recipient_callbacks_valid = (
			recipient_callbacks_valid
			and guard.alert_count == (1 if should_receive else 0)
			and (
				guard.last_alert_source == &"camera_cctv_01"
				if should_receive
				else guard.last_alert_source == StringName()
			)
		)
	_check(
		recipient_callbacks_valid,
		"zone alert dispatch invokes each selected Guard exactly once"
	)
	var local_only := manager.get_alert_recipient_ids(&"zone_cctv", false)
	_check(
		local_only == [&"guard_cctv_01"],
		"local-only alert selection excludes adjacent zones deterministically"
	)
	_check(
		manager.get_active_alert(&"zone_cctv").get("source_id") == &"camera_cctv_01",
		"GuardZoneManager retains the current zone-alert diagnostic state"
	)
	manager.reset_for_mission()
	_check(
		manager.get_active_alert(&"zone_cctv").is_empty()
		and manager.validate_registered_assignments(true),
		"mission reset clears alerts without discarding stable Guard assignments"
	)
	await _cleanup_fixture(fixture)


func _test_proximity_contract(blueprint: Dictionary) -> void:
	var defaults: Dictionary = blueprint.get("guard_perception_defaults", {}) as Dictionary
	var stationary := float(defaults.get("stationary_proximity_radius", 0.0))
	var walking := float(defaults.get("walking_proximity_radius", 0.0))
	var running := float(defaults.get("running_proximity_radius", 0.0))
	var contact := float(defaults.get("direct_contact_distance", 0.0))
	_check(
		contact > 0.0 and contact < stationary and stationary < walking and walking < running,
		"contact, stationary, walking, and running awareness radii increase monotonically"
	)
	var rear_near := Vector2.LEFT * (walking - 1.0)
	_check(
		not GuardPerception.is_point_in_view(
			Vector2.ZERO, rear_near, Vector2.RIGHT, 220.0, 38.0
		)
		and rear_near.length() < walking,
		"rear proximity is outside the cone while remaining inside walking awareness"
	)
	var rear_far := Vector2.LEFT * (running + 1.0)
	_check(
		not GuardPerception.is_point_in_view(
			Vector2.ZERO, rear_far, Vector2.RIGHT, 220.0, 38.0
		)
		and rear_far.length() > running,
		"a rear target beyond the running radius is rejected by both awareness ranges"
	)
	_check(
		bool(defaults.get("proximity_requires_clear_los", false))
		and bool(defaults.get("closed_doors_block_proximity", false)),
		"proximity awareness explicitly requires LOS and respects closed doors"
	)


func _load_blueprint() -> Dictionary:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _cleanup_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await _tree.process_frame
	await _tree.physics_frame


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)
