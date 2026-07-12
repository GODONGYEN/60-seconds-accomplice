extends SceneTree

const SAMPLE_RATE_HZ: float = 20.0
const LOOP_DURATION_SECONDS: float = 20.0
const EXPECTED_SAMPLE_COUNT: int = 401
const FLOAT_EPSILON: float = 0.0001

const GHOST_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/prototype_level.tscn")
const TIMELINE_SCENE: PackedScene = preload("res://scenes/main/timeline_manager.tscn")
const PRESSURE_PLATE_SCENE: PackedScene = preload("res://scenes/objects/pressure_plate.tscn")
const SECURITY_DOOR_SCENE: PackedScene = preload("res://scenes/objects/security_door.tscn")
const OBJECTIVE_ITEM_SCENE: PackedScene = preload("res://scenes/objects/objective_item.tscn")
const EXIT_ZONE_SCENE: PackedScene = preload("res://scenes/objects/exit_zone.tscn")

var _assertion_count: int = 0
var _failure_count: int = 0


class ReplayTarget:
	extends Node

	var received_orders: Array[int] = []

	func replay_event(_event_type: StringName, _actor: Node, payload: Dictionary) -> bool:
		received_orders.append(int(payload.get("order", -1)))
		return true


func _initialize() -> void:
	call_deferred(&"_run_all_tests")


func _run_all_tests() -> void:
	print("[TEST] Starting headless gameplay system tests")
	_test_required_input_actions()
	_test_recording_sampling_and_timestamps()
	_test_recording_deep_copy_isolation()
	await _test_ghost_interpolation_boundaries()
	await _test_discrete_event_order_and_exactly_once()
	await _test_registry_validation_and_missing_target()
	await _test_resettable_gameplay_objects()
	await _test_pause_restart_and_victory_priority()
	await _test_full_level_acceptance_flow()

	if _failure_count == 0:
		print("[TEST] PASS: %d assertions" % _assertion_count)
		quit(0)
		return
	push_error("[TEST] FAIL: %d of %d assertions failed" % [_failure_count, _assertion_count])
	quit(1)


func _test_required_input_actions() -> void:
	print("[TEST] Required Input Map actions")
	var required_actions: Array[StringName] = [
		&"move_up",
		&"move_down",
		&"move_left",
		&"move_right",
		&"interact",
		&"restart_loop",
		&"pause",
	]
	for action: StringName in required_actions:
		_expect(InputMap.has_action(action), "Input Map contains '%s'" % action)


func _test_recording_sampling_and_timestamps() -> void:
	print("[TEST] Recording sampling and timestamp invariants")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var actor := Node2D.new()
	var recorder := ActionRecorder.new()
	recorder.sample_rate_hz = SAMPLE_RATE_HZ
	fixture.add_child(actor)
	fixture.add_child(recorder)

	_expect(
		recorder.begin_recording(actor, LOOP_DURATION_SECONDS),
		"recorder starts with a valid actor and duration"
	)
	for step: int in range(1, 201):
		var timestamp: float = float(step) * 0.1
		actor.global_position = Vector2(timestamp * 10.0, timestamp * -2.0)
		recorder.capture_until(timestamp)
	var recording: LoopRecording = recorder.finish_recording(LOOP_DURATION_SECONDS, 1)

	_expect(
		recording.samples.size() == EXPECTED_SAMPLE_COUNT,
		"20 seconds at 20 Hz produces 400 intervals plus the initial sample"
	)
	_expect(
		_is_equal(recording.samples.front().timestamp, 0.0),
		"recording begins at timestamp zero"
	)
	_expect(
		_is_equal(recording.samples.back().timestamp, LOOP_DURATION_SECONDS),
		"recording includes the loop-duration endpoint"
	)
	_expect(recording.is_chronological(), "recording reports chronological data")

	var timestamps_are_monotonic: bool = true
	var timestamps_are_in_bounds: bool = true
	for index: int in range(recording.samples.size()):
		var sample: TransformSample = recording.samples[index]
		if sample.timestamp < -FLOAT_EPSILON or sample.timestamp > LOOP_DURATION_SECONDS + FLOAT_EPSILON:
			timestamps_are_in_bounds = false
		if index > 0 and sample.timestamp + FLOAT_EPSILON < recording.samples[index - 1].timestamp:
			timestamps_are_monotonic = false
	_expect(timestamps_are_monotonic, "sample timestamps never decrease")
	_expect(timestamps_are_in_bounds, "sample timestamps stay within the loop duration")
	fixture.free()


func _test_recording_deep_copy_isolation() -> void:
	print("[TEST] Recording deep-copy isolation")
	var source_sample := TransformSample.new(0.25, Vector2(4.0, 8.0), Vector2.UP)
	var source_payload: Dictionary = {
		"nested": {"value": 7},
		"items": [1, 2, 3],
	}
	var source_event := RecordedEvent.new(0.25, &"objective_core_01", &"interact", source_payload)
	var source_samples: Array[TransformSample] = [source_sample]
	var source_events: Array[RecordedEvent] = [source_event]
	var recording := LoopRecording.new(1.0, source_samples, source_events, 1)

	source_sample.position = Vector2(99.0, 99.0)
	var source_nested: Dictionary = source_event.payload["nested"]
	source_nested["value"] = 99
	_expect(
		recording.samples[0].position == Vector2(4.0, 8.0),
		"recording samples do not share source objects"
	)
	var recorded_nested: Dictionary = recording.events[0].payload["nested"]
	_expect(
		int(recorded_nested["value"]) == 7,
		"recording event payload does not share nested source data"
	)

	var duplicate := recording.duplicate_recording()
	duplicate.samples[0].position = Vector2(-5.0, -5.0)
	var duplicate_nested: Dictionary = duplicate.events[0].payload["nested"]
	duplicate_nested["value"] = 42
	_expect(
		recording.samples[0].position == Vector2(4.0, 8.0),
		"duplicated recording has independent sample objects"
	)
	recorded_nested = recording.events[0].payload["nested"]
	_expect(
		int(recorded_nested["value"]) == 7,
		"duplicated recording has independent nested event payloads"
	)


func _test_ghost_interpolation_boundaries() -> void:
	print("[TEST] Ghost interpolation boundaries")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	fixture.add_child(ghost)
	var samples: Array[TransformSample] = [
		TransformSample.new(0.0, Vector2.ZERO, Vector2.RIGHT),
		TransformSample.new(1.0, Vector2(100.0, 40.0), Vector2.DOWN),
	]
	var recording := LoopRecording.new(2.0, samples, [], 1)

	_expect(ghost.configure(recording, null, 1), "Ghost accepts a valid recording")
	ghost.advance_to(0.0)
	_expect(ghost.global_position.is_equal_approx(Vector2.ZERO), "playback starts at the first sample")
	ghost.advance_to(0.5)
	_expect(
		ghost.global_position.is_equal_approx(Vector2(50.0, 20.0)),
		"playback interpolates by timeline timestamp"
	)
	ghost.advance_to(1.0)
	_expect(
		ghost.global_position.is_equal_approx(Vector2(100.0, 40.0)),
		"playback reaches the final sample exactly"
	)
	ghost.advance_to(9.0)
	_expect(
		ghost.global_position.is_equal_approx(Vector2(100.0, 40.0)),
		"playback holds the final sample after the recorded path ends"
	)

	ghost.global_position = Vector2(17.0, 23.0)
	var empty_recording := LoopRecording.new(1.0, [], [], 2)
	_expect(ghost.configure(empty_recording, null, 2), "Ghost accepts an empty recording safely")
	ghost.advance_to(1.0)
	_expect(
		ghost.global_position.is_equal_approx(Vector2(17.0, 23.0)),
		"empty playback leaves the Ghost transform unchanged"
	)
	_expect(ghost.is_playback_complete(), "empty playback reaches completion without a crash")
	fixture.free()
	await process_frame


func _test_discrete_event_order_and_exactly_once() -> void:
	print("[TEST] Discrete event ordering and exactly-once dispatch")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var registry := ObjectRegistry.new()
	var target := ReplayTarget.new()
	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	fixture.add_child(registry)
	fixture.add_child(target)
	fixture.add_child(ghost)
	_expect(registry.register_object(&"test_target", target), "event target registers by stable ID")

	var events: Array[RecordedEvent] = [
		RecordedEvent.new(0.5, &"test_target", &"first", {"order": 1}),
		RecordedEvent.new(0.5, &"test_target", &"second", {"order": 2}),
		RecordedEvent.new(0.75, &"test_target", &"third", {"order": 3}),
	]
	var recording := LoopRecording.new(1.0, [], events, 1)
	_expect(recording.events[0].sequence < recording.events[1].sequence, "equal-time events retain source ordering")
	ghost.configure(recording, registry, 1)
	ghost.advance_to(0.49)
	_expect(target.received_orders.is_empty(), "events do not dispatch before their timestamp")
	ghost.advance_to(0.5)
	_expect(target.received_orders == [1, 2], "equal-time events dispatch in stable order")
	ghost.advance_to(0.6)
	ghost.advance_to(0.8)
	ghost.advance_to(1.0)
	_expect(target.received_orders == [1, 2, 3], "each discrete event dispatches exactly once")
	fixture.free()
	await process_frame


func _test_registry_validation_and_missing_target() -> void:
	print("[TEST] Stable object registry guards and missing replay targets")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var registry := ObjectRegistry.new()
	var original := Node.new()
	var duplicate := Node.new()
	fixture.add_child(registry)
	fixture.add_child(original)
	fixture.add_child(duplicate)

	_expect(
		not registry.register_object(StringName(), original),
		"registry rejects an empty stable object ID"
	)
	_expect(registry.register_object(&"stable_test_01", original), "registry accepts a unique stable object ID")
	_expect(
		not registry.register_object(&"stable_test_01", duplicate),
		"registry rejects a duplicate stable object ID"
	)
	_expect(
		registry.get_object(&"stable_test_01") == original,
		"duplicate registration does not replace the original object"
	)
	_expect(registry.get_object(&"missing_target") == null, "missing stable ID lookup returns null safely")

	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	fixture.add_child(ghost)
	var missing_events: Array[RecordedEvent] = [
		RecordedEvent.new(0.0, &"missing_target", &"interact"),
	]
	ghost.configure(LoopRecording.new(0.0, [], missing_events, 3), registry, 3)
	ghost.advance_to(0.0)
	_expect(ghost.is_playback_complete(), "missing replay target is skipped and playback advances")
	fixture.free()
	await process_frame


func _test_resettable_gameplay_objects() -> void:
	print("[TEST] Resettable puzzle-object state")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var plate := PRESSURE_PLATE_SCENE.instantiate() as PressurePlate
	var door := SECURITY_DOOR_SCENE.instantiate() as SecurityDoor
	var objective := OBJECTIVE_ITEM_SCENE.instantiate() as ObjectiveItem
	var exit_zone := EXIT_ZONE_SCENE.instantiate() as ExitZone
	var actor := Node2D.new()
	actor.add_to_group(&"player_actor")
	fixture.add_child(plate)
	fixture.add_child(door)
	fixture.add_child(objective)
	fixture.add_child(exit_zone)
	fixture.add_child(actor)

	plate.body_entered.emit(actor)
	_expect(plate.is_active and plate.get_occupant_count() == 1, "pressure plate tracks occupying actors")
	plate.reset_for_loop()
	_expect(not plate.is_active and plate.get_occupant_count() == 0, "pressure plate reset clears occupancy")

	door.set_open(true)
	await process_frame
	_expect(door.is_open and door.blocker.disabled, "door opens and disables its blocker")
	door.reset_for_loop()
	await process_frame
	_expect(not door.is_open and not door.blocker.disabled, "door reset restores the closed blocker")

	_expect(objective.interact(actor), "live-player actor can collect the objective")
	await process_frame
	_expect(
		objective.is_collected and not objective.visible and not objective.monitorable,
		"objective collection applies its consumed state"
	)
	objective.reset_for_loop()
	await process_frame
	_expect(
		not objective.is_collected
		and objective.visible
		and objective.monitorable
		and not objective.collision_shape.disabled,
		"objective reset restores visibility, monitoring, and collision"
	)

	exit_zone.set_objective_available(true)
	_expect(exit_zone.is_objective_available, "exit becomes active after objective collection")
	exit_zone.reset_for_loop()
	_expect(not exit_zone.is_objective_available, "exit reset removes objective availability")
	fixture.free()
	await process_frame


func _test_pause_restart_and_victory_priority() -> void:
	print("[TEST] Timeline pause, restart coalescing, and victory priority")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	var timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	fixture.add_child(level)
	fixture.add_child(timeline)
	await process_frame

	_expect(timeline.configure(level), "TimelineManager configures against the tutorial level")
	_expect(timeline.start_session(), "TimelineManager starts the first loop")
	timeline._physics_process(0.25)
	var elapsed_before_pause: float = timeline.elapsed_time
	paused = true
	for _frame: int in range(3):
		await physics_frame
		await process_frame
	_expect(
		_is_equal(timeline.elapsed_time, elapsed_before_pause),
		"timeline clock does not advance while the SceneTree is paused"
	)
	paused = false

	timeline.request_restart()
	timeline.request_restart()
	await _wait_process_frames(2)
	_expect(timeline.is_loop_running(), "coalesced restart returns the timeline to RUNNING")
	_expect(timeline.current_loop_index == 2, "two immediate restart requests advance only one loop")
	_expect(timeline.recordings.size() == 1, "two immediate restart requests store only one recording")

	timeline.request_loop_end(TimelineManager.REASON_TIMEOUT)
	timeline.complete_level()
	await _wait_process_frames(2)
	_expect(timeline.is_victory(), "victory supersedes a pending timeout transition")
	_expect(timeline.recordings.size() == 1, "victory-timeout race does not save a timeout recording")
	fixture.free()
	await process_frame


func _test_full_level_acceptance_flow() -> void:
	print("[TEST] Full tutorial-level acceptance flow")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	var timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	fixture.add_child(level)
	fixture.add_child(timeline)
	await _wait_physics_frames(6)

	# Keep the clock deterministic: physics frames update real overlap signals, while
	# this test advances recording/playback only through explicit absolute timestamps.
	timeline.loop_started.connect(_disable_timeline_processing.bind(timeline))
	_expect(timeline.configure(level), "acceptance fixture configures the full level")
	_expect(timeline.start_session(), "acceptance fixture starts loop 1")
	_expect(not timeline.is_physics_processing(), "acceptance clock is under explicit test control")

	var loop_one_player: PlayerController = level.current_player
	_expect(
		timeline.process_physics_priority > loop_one_player.process_physics_priority,
		"Timeline sampling runs after live Player physics in each tick"
	)
	_expect(
		is_instance_valid(loop_one_player)
		and loop_one_player.global_position.is_equal_approx(level.player_spawn.global_position),
		"loop 1 Player begins at the authored spawn"
	)
	loop_one_player.global_position = level.pressure_plate.global_position
	await _wait_physics_frames(10)
	_expect(
		level.pressure_plate.is_active and level.security_door.is_open,
		"loop 1 live Player physically activates the plate and opens the door"
	)
	_expect(level.security_door.blocker.disabled, "open door disables its physical blocker")

	_advance_timeline_to(timeline, 1.0)
	_advance_timeline_to(timeline, 3.0)
	_expect(_is_equal(timeline.elapsed_time, 3.0), "loop 1 recording reaches the explicit restart time")
	timeline.request_restart()
	await _wait_for_loop(timeline, 2)
	_expect(timeline.is_loop_running(), "restart starts loop 2")
	_expect(timeline.recordings.size() == 1 and level.get_ghost_count() == 1, "loop 2 spawns one Ghost from loop 1")
	_expect(
		not level.pressure_plate.is_active
		and not level.security_door.is_open
		and not level.objective_item.is_collected
		and not level.exit_zone.is_objective_available,
		"loop restart restores all puzzle objects before replay"
	)
	_expect(
		is_instance_valid(level.current_player)
		and level.current_player.global_position.is_equal_approx(level.player_spawn.global_position),
		"loop restart replaces the live Player at the spawn"
	)

	_advance_timeline_to(timeline, 0.5)
	await _wait_physics_frames(2)
	_expect(
		not level.pressure_plate.is_active and not level.security_door.is_open,
		"loop 2 door remains closed before the Ghost reaches the plate"
	)
	_advance_timeline_to(timeline, 1.0)
	await _wait_physics_frames(10)
	_expect(_is_equal(timeline.elapsed_time, 1.0), "Ghost playback uses the loop 2 absolute clock")
	_expect(
		level.pressure_plate.is_active and level.security_door.is_open,
		"recorded Ghost physically activates the plate and opens the door in loop 2"
	)

	var loop_two_player: PlayerController = level.current_player
	loop_two_player.global_position = level.objective_item.global_position
	await _wait_physics_frames(10)
	var interact_input := InputEventAction.new()
	interact_input.action = &"interact"
	interact_input.pressed = true
	loop_two_player._unhandled_input(interact_input)
	await process_frame
	_expect(
		level.objective_item.is_collected
		and loop_two_player.has_objective_item()
		and level.exit_zone.is_objective_available,
		"loop 2 Player interaction collects the objective and activates the exit"
	)
	_expect(
		timeline.action_recorder.get_pending_event_count() == 1,
		"successful objective interaction is captured as a discrete event"
	)

	loop_two_player.global_position = level.exit_zone.global_position
	await _wait_physics_frames(10)
	await _wait_process_frames(2)
	_expect(timeline.is_victory(), "live Player entering the active exit completes the level")

	_expect(timeline.reset_timeline(), "timeline can reset cleanly after victory")
	await _wait_physics_frames(2)
	_expect(
		timeline.current_loop_index == 1
		and timeline.recordings.is_empty()
		and level.get_ghost_count() == 0,
		"full timeline reset removes recordings and runtime Ghosts"
	)
	_expect(
		not level.pressure_plate.is_active
		and not level.security_door.is_open
		and not level.security_door.blocker.disabled
		and not level.objective_item.is_collected
		and level.objective_item.visible
		and not level.exit_zone.is_objective_available,
		"full timeline reset restores plate, door, objective, and exit initial state"
	)
	_expect(
		timeline.is_loop_running()
		and is_instance_valid(level.current_player)
		and level.current_player.global_position.is_equal_approx(level.player_spawn.global_position),
		"full timeline reset starts a fresh controllable loop at the Player spawn"
	)
	fixture.free()
	await process_frame


func _disable_timeline_processing(
		_loop_index: int,
		_ghost_count: int,
		timeline: TimelineManager
) -> void:
	timeline.set_physics_process(false)


func _advance_timeline_to(timeline: TimelineManager, target_time: float) -> void:
	var delta: float = maxf(0.0, target_time - timeline.elapsed_time)
	timeline._physics_process(delta)


func _wait_for_loop(timeline: TimelineManager, expected_loop_index: int) -> void:
	for _frame: int in range(5):
		if timeline.current_loop_index == expected_loop_index and timeline.is_loop_running():
			return
		await process_frame


func _wait_physics_frames(count: int) -> void:
	for _frame: int in range(count):
		await physics_frame
		await process_frame


func _wait_process_frames(count: int) -> void:
	for _frame: int in range(count):
		await process_frame


func _expect(condition: bool, description: String) -> void:
	_assertion_count += 1
	if condition:
		print("  PASS: %s" % description)
		return
	_failure_count += 1
	push_error("  FAIL: %s" % description)


func _is_equal(left: float, right: float) -> bool:
	return absf(left - right) <= FLOAT_EPSILON
