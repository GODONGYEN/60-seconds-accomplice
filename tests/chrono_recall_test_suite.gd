class_name ChronoRecallTestSuite
extends Node

const FLOAT_EPSILON: float = 0.001
const PHYSICS_STEP: float = 1.0 / 60.0

var _tree: SceneTree
var _expectation: Callable
var _assertion_count: int = 0


class RecallActor:
	extends CharacterBody2D

	var facing_angle: float = 0.0
	var inventory_marker: int = 0

	func get_facing_angle() -> float:
		return facing_angle

	func get_animation_state() -> StringName:
		return &"moving" if velocity.length_squared() > 0.01 else &"idle"

	func get_recorded_velocity() -> Vector2:
		return velocity

	func capture_recall_state() -> Dictionary:
		return {
			"position": global_position,
			"facing_angle": facing_angle,
			"inventory_marker": inventory_marker,
		}

	func restore_recall_state(snapshot: Dictionary) -> bool:
		var position_value: Variant = snapshot.get("position", global_position)
		if typeof(position_value) != TYPE_VECTOR2:
			return false
		global_position = position_value
		facing_angle = float(snapshot.get("facing_angle", 0.0))
		inventory_marker = int(snapshot.get("inventory_marker", 0))
		velocity = Vector2.ZERO
		return true

	func get_recall_state_id() -> StringName:
		return &"test_player"


class RewindableValue:
	extends Node

	var rewind_id: StringName
	var value: int = 0
	var restore_log: Array[StringName]

	func _init(p_rewind_id: StringName, p_restore_log: Array[StringName]) -> void:
		rewind_id = p_rewind_id
		restore_log = p_restore_log
		name = String(p_rewind_id)

	func capture_recall_state() -> Dictionary:
		return {"value": value}

	func restore_recall_state(snapshot: Dictionary) -> bool:
		value = int(snapshot.get("value", -1))
		restore_log.append(rewind_id)
		return value >= 0

	func get_recall_state_id() -> StringName:
		return rewind_id

	func get_recall_restore_phase() -> int:
		return RewindStateRegistry.RestorePhase.WORLD


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	_assertion_count = 0
	print("[TEST] Chrono Recall bounded history and transactional restore")
	_test_history_ring_and_segment()
	_test_registry_restore_order()
	await _test_manager_recall_and_echo_cap()


func get_assertion_count() -> int:
	return _assertion_count


func _test_history_ring_and_segment() -> void:
	var actor := RecallActor.new()
	var history := RecallHistory.new()
	_check(history.configure(20.0, 10.0), "Recall history accepts the authored 20 Hz / 10 second contract")
	_check(history.begin_branch(actor, 0.0), "Recall history begins from a live actor state")

	for tick: int in range(660):
		var world_time: float = float(tick + 1) * PHYSICS_STEP
		actor.velocity = Vector2(10.0, 0.0)
		actor.position.x = world_time * 10.0
		history.capture_until(world_time)
	_check(
		history.record_event(11.0, &"test_terminal", &"interact", {"authorized": true}),
		"successful interaction data enters the bounded branch chronologically"
	)
	for tick: int in range(60):
		var world_time: float = 11.0 + float(tick + 1) * PHYSICS_STEP
		actor.position.x = world_time * 10.0
		history.capture_until(world_time)

	_check(
		history.get_sample_count() <= 202,
		"20 Hz history retains no more than one interpolation sample beyond its 10 second window"
	)
	_check(
		history.get_available_duration() <= 10.0 + FLOAT_EPSILON,
		"logical Recall history never exposes more than 10 seconds"
	)
	var segment := history.build_segment(2.0, 12.0, 1)
	_check(
		is_equal_approx(segment.duration, 10.0) and segment.is_chronological(),
		"abandoned history builds a chronological 10 second LoopRecording"
	)
	_check(
		not segment.samples.is_empty()
		and absf(segment.samples[0].position.x - 20.0) <= FLOAT_EPSILON
		and absf(segment.samples.back().position.x - 120.0) <= FLOAT_EPSILON,
		"segment boundary samples interpolate the exact start and current Player transforms"
	)
	_check(
		segment.events.size() == 1
		and absf(segment.events[0].timestamp - 9.0) <= FLOAT_EPSILON
		and bool(segment.events[0].payload.get("authorized", false)),
		"segment events are normalized to Echo-local time without losing their payload"
	)
	actor.free()


func _test_registry_restore_order() -> void:
	var restore_log: Array[StringName] = []
	var late := RewindableValue.new(&"z_world", restore_log)
	var early := RewindableValue.new(&"a_world", restore_log)
	late.value = 90
	early.value = 10
	var registry := RewindStateRegistry.new()
	_check(
		registry.register_recallable(late) and registry.register_recallable(early),
		"state registry accepts the mission capture_recall_state contract"
	)
	_check(
		registry.get_registered_ids() == [&"a_world", &"z_world"],
		"rewindables are ordered deterministically by restore phase and stable ID"
	)
	var snapshot: Dictionary = registry.capture_snapshot(4.0)
	_check(
		bool(snapshot.get("valid", false)) and registry.can_restore_snapshot(snapshot),
		"registry snapshot is immutable-data-only and restorable"
	)
	early.value = 111
	late.value = 999
	_check(registry.restore_snapshot(snapshot), "registry restores the complete snapshot transaction")
	_check(
		early.value == 10 and late.value == 90 and restore_log == [&"a_world", &"z_world"],
		"world values restore in deterministic stable-ID order"
	)
	early.free()
	late.free()


func _test_manager_recall_and_echo_cap() -> void:
	var defaults := ChronoRecallManager.new()
	_check(
		defaults.maximum_charges == 3
		and defaults.maximum_echoes == 3
		and is_equal_approx(defaults.rewind_duration_seconds, 10.0),
		"Chrono Recall defaults to 3 persistent charges, 3 Echoes, and 10 seconds"
	)
	defaults.free()

	var fixture := Node2D.new()
	fixture.name = "ChronoRecallTestFixture"
	_tree.root.add_child(fixture)
	var actor := RecallActor.new()
	var restore_log: Array[StringName] = []
	var world_state := RewindableValue.new(&"test_world", restore_log)
	var echo_parent := Node2D.new()
	var object_registry := ObjectRegistry.new()
	var manager := ChronoRecallManager.new()
	manager.automatic_physics_processing = false
	manager.maximum_charges = 4
	manager.maximum_echoes = 3
	fixture.add_child(actor)
	fixture.add_child(world_state)
	fixture.add_child(echo_parent)
	fixture.add_child(object_registry)
	fixture.add_child(manager)
	await _tree.process_frame

	_check(
		manager.configure(actor, object_registry, echo_parent, fixture),
		"Chrono manager discovers Player and world recall contracts once during configuration"
	)
	_check(manager.begin_mission(), "Chrono manager starts a monotonic mission branch")
	_simulate_branch(manager, actor, world_state, 630)
	var before_recall_time: float = manager.get_world_time()
	var expected_world_snapshot_value: int = world_state.value
	_check(
		manager.get_world_snapshot_count() <= 201
		and manager.get_history().call(&"get_sample_count") <= 202,
		"manager bounds both world and Player histories at 20 Hz for 10 seconds"
	)
	_check(manager.request_recall(), "manual Recall restores the oldest valid 10 second snapshot")
	_check(
		manager.remaining_charges == 3
		and is_equal_approx(manager.get_world_time(), before_recall_time),
		"Recall consumes one persistent charge without rewinding the world clock"
	)
	_check(
		actor.position.x < 6.0
		and actor.inventory_marker < expected_world_snapshot_value
		and world_state.value < expected_world_snapshot_value,
		"Recall restores Player transform, Player inventory state, and registered world state"
	)
	_check(
		manager.get_echo_count() == 1
		and manager.get_echoes()[0].get_detection_id() == &"echo_001",
		"abandoned movement becomes a single detectable Echo with an Echo-stable ID"
	)

	for _recall_index: int in range(3):
		_simulate_branch(manager, actor, world_state, 60)
		_check(manager.request_recall(), "subsequent Recall starts from the current history branch")
	_check(
		manager.remaining_charges == 0 and not manager.can_recall(),
		"all four configured charges remain consumed across restored snapshots"
	)
	var echoes: Array[GhostPlayback] = manager.get_echoes()
	_check(
		echoes.size() == 3
		and echoes[0].get_detection_id() == &"echo_002"
		and echoes[2].get_detection_id() == &"echo_004",
		"fourth Echo safely evicts the oldest and preserves the newest three in order"
	)
	await _cleanup_fixture(fixture)


func _simulate_branch(
	manager: ChronoRecallManager,
	actor: RecallActor,
	world_state: RewindableValue,
	tick_count: int
) -> void:
	for _tick: int in range(tick_count):
		actor.velocity = Vector2(10.0, 0.0)
		actor.position.x += 10.0 * PHYSICS_STEP
		actor.facing_angle = 0.0
		actor.inventory_marker += 1
		world_state.value += 1
		manager.advance(PHYSICS_STEP)


func _cleanup_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.process_frame


func _check(condition: bool, description: String) -> void:
	_assertion_count += 1
	if _expectation.is_valid():
		_expectation.call(condition, description)
