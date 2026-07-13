class_name GuardAITestSuite
extends Node

const GUARD_SCENE: PackedScene = preload("res://scenes/enemies/guard.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GHOST_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/prototype_level.tscn")
const SECURITY_DOOR_SCENE: PackedScene = preload("res://scenes/objects/security_door.tscn")

const PHYSICS_STEP: float = 1.0 / 60.0
const FLOAT_EPSILON: float = 0.0001

var _tree: SceneTree
var _expectation: Callable


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Guard stealth AI systems")
	_test_view_cone_math()
	await _test_authored_level_contract()
	await _test_line_of_sight_and_door()
	await _test_state_machine_and_target_loss()
	await _test_suspicion_and_target_priority()
	await _test_capture_and_reset()
	await _test_visual_feedback()
	await _test_eight_ghost_target_stress()


func _test_view_cone_math() -> void:
	_check(
		GuardPerception.is_point_in_view(
			Vector2.ZERO, Vector2(219.0, 0.0), Vector2.RIGHT, 220.0, 38.0
		),
		"FOV accepts a target inside its distance and angle"
	)
	_check(
		not GuardPerception.is_point_in_view(
			Vector2.ZERO, Vector2(221.0, 0.0), Vector2.RIGHT, 220.0, 38.0
		),
		"FOV rejects a target outside its distance"
	)
	_check(
		GuardPerception.is_point_in_view(
			Vector2.ZERO,
			Vector2.RIGHT.rotated(deg_to_rad(37.0)) * 160.0,
			Vector2.RIGHT,
			220.0,
			38.0
		),
		"FOV accepts a target just inside the authored half-angle"
	)
	_check(
		not GuardPerception.is_point_in_view(
			Vector2.ZERO,
			Vector2.RIGHT.rotated(deg_to_rad(39.0)) * 160.0,
			Vector2.RIGHT,
			220.0,
			38.0
		),
		"FOV rejects a target just outside the authored half-angle"
	)
	_check(
		GuardPerception.is_point_in_view(
			Vector2.ZERO, Vector2(80.0, 0.0), Vector2.ZERO, 220.0, 38.0
		),
		"FOV uses a deterministic right-facing fallback for a zero facing vector"
	)


func _test_authored_level_contract() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	fixture.add_child(level)
	await _wait_physics_frames(3)
	var guard: GuardController = level.training_guard
	guard.set_simulation_enabled(false)
	_check(level.validate_level(), "tutorial level validates with its authored Guard route")
	_check(
		guard.has_valid_patrol_route() and guard.get_patrol_point_count() == 2,
		"tutorial Guard has exactly two deterministic patrol points"
	)
	_check(
		guard.collision_layer == 32 and guard.collision_mask == 1,
		"Guard collides with world geometry on its dedicated layer"
	)
	_check(
		not GuardPerception.is_point_in_view(
			guard.get_perception().global_position,
			level.player_spawn.global_position + GuardPerception.TARGET_HEIGHT_OFFSET,
			guard.get_facing_direction(),
			guard.get_perception().vision_distance,
			guard.get_perception().vision_half_angle_degrees
		),
		"authored Player spawn begins outside the Guard's initial cone"
	)
	level.reset_objects_for_loop()
	_check(
		not guard.is_simulation_enabled()
		and not guard.get_perception().is_detection_enabled(),
		"loop reset preserves the outer simulation lock and clears perception"
	)
	await _cleanup_fixture(fixture)


func _test_line_of_sight_and_door() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	var player := _spawn_player(fixture, Vector2(100.0, 0.0))
	await _wait_physics_frames(3)
	var perception: GuardPerception = guard.get_perception()
	_check(
		perception.is_target_visible(player, Vector2.RIGHT),
		"Player inside the clear cone is visible"
	)
	_check(
		not perception.is_target_visible(player, Vector2.LEFT),
		"Player outside the facing angle is not visible"
	)

	var wall := _spawn_wall(fixture, Vector2(50.0, -18.0))
	await _wait_physics_frames(2)
	_check(
		not perception.has_clear_line_of_sight(player),
		"world collision blocks Guard line of sight"
	)
	wall.queue_free()
	await _wait_physics_frames(2)
	_check(perception.has_clear_line_of_sight(player), "removing the wall restores line of sight")

	var door := SECURITY_DOOR_SCENE.instantiate() as SecurityDoor
	door.position = Vector2(50.0, -18.0)
	fixture.add_child(door)
	await _wait_physics_frames(2)
	_check(
		not perception.has_clear_line_of_sight(player),
		"closed security door blocks Guard line of sight"
	)
	door.set_open(true)
	await _wait_physics_frames(2)
	_check(
		door.blocker.disabled and perception.has_clear_line_of_sight(player),
		"open security door disables collision and permits line of sight"
	)
	door.set_open(false)
	await _wait_physics_frames(2)
	_check(
		not door.blocker.disabled and not perception.has_clear_line_of_sight(player),
		"closing the door restores collision and line-of-sight blocking"
	)
	await _cleanup_fixture(fixture)


func _test_state_machine_and_target_loss() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	guard.idle_duration = 0.05
	guard.patrol_speed = 200.0
	guard.suspicion_gain_per_second = 4.0
	guard.lose_target_delay = 0.05
	guard.search_duration = 0.15
	guard.perception_update_interval = 0.01

	var transitions: Array[int] = []
	guard.state_changed.connect(
		func(_previous: GuardController.GuardState, current: GuardController.GuardState) -> void:
			transitions.append(current)
	)
	guard.advance_ai(0.06)
	_check(
		guard.state == GuardController.GuardState.PATROL and guard.get_patrol_index() == 1,
		"IDLE advances to the next deterministic patrol waypoint"
	)
	var patrol_start := guard.global_position
	for _step: int in range(180):
		guard.advance_ai(PHYSICS_STEP)
		if guard.state == GuardController.GuardState.IDLE:
			break
	_check(
		guard.state == GuardController.GuardState.IDLE
		and guard.global_position.distance_to(patrol_start) > 40.0,
		"PATROL reaches its waypoint without oscillating"
	)
	var transition_count := transitions.size()
	guard.transition_to(guard.state)
	_check(
		transitions.size() == transition_count,
		"re-entering the current Guard state is a safe no-op"
	)
	var state_before_invalid: GuardController.GuardState = guard.state
	guard.transition_to(999)
	_check(
		guard.state == state_before_invalid and transitions.size() == transition_count,
		"invalid Guard state transition is rejected without corrupting the machine"
	)

	var player_position := guard.global_position + Vector2(100.0, 0.0)
	var player := _spawn_player(fixture, player_position)
	await _wait_physics_frames(3)
	guard.advance_ai(0.1)
	_check(
		guard.state == GuardController.GuardState.SUSPICIOUS
		and guard.get_current_target_id() == PlayerController.DETECTION_ID,
		"seeing the Player transitions the Guard to SUSPICIOUS"
	)
	for _step: int in range(6):
		guard.advance_ai(0.05)
		if guard.state == GuardController.GuardState.CHASE:
			break
	_check(
		guard.state == GuardController.GuardState.CHASE
		and _approximately_equal(guard.get_suspicion(), 1.0),
		"suspicion threshold transitions the Guard to CHASE"
	)

	player.queue_free()
	await _wait_physics_frames(2)
	guard.advance_ai(guard.lose_target_delay + 0.01)
	_check(
		guard.state == GuardController.GuardState.SEARCH
		and guard.get_current_target_id() == StringName(),
		"losing a freed target safely transitions CHASE to SEARCH"
	)
	for _step: int in range(240):
		guard.advance_ai(PHYSICS_STEP)
		if guard.state == GuardController.GuardState.RETURN:
			break
	_check(
		guard.state == GuardController.GuardState.RETURN,
		"deterministic search timeout transitions to RETURN"
	)
	for _step: int in range(180):
		guard.advance_ai(PHYSICS_STEP)
		if guard.state == GuardController.GuardState.IDLE:
			break
	_check(
		guard.state == GuardController.GuardState.IDLE,
		"RETURN reaches the nearest patrol point and resumes IDLE"
	)
	await _cleanup_fixture(fixture)


func _test_suspicion_and_target_priority() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	guard.idle_duration = 5.0
	guard.perception_update_interval = 0.01
	guard.suspicion_gain_per_second = 1.0
	guard.suspicion_loss_per_second = 0.5
	var ghost := _spawn_ghost(fixture, Vector2(80.0, 0.0), 2, 10.0)
	await _wait_physics_frames(3)
	guard.advance_ai(0.25)
	var suspicion_while_visible := guard.get_suspicion()
	_check(
		guard.get_current_target_id() == &"ghost_002" and suspicion_while_visible > 0.0,
		"Guard detects a live Ghost and accumulates suspicion"
	)
	ghost.global_position = Vector2(-80.0, 0.0)
	guard.advance_ai(0.1)
	_check(
		guard.get_suspicion() < suspicion_while_visible,
		"suspicion decreases when the current target leaves the cone"
	)
	ghost.global_position = Vector2(80.0, 0.0)
	guard.advance_ai(0.1)
	var player := _spawn_player(fixture, Vector2(100.0, 0.0))
	await _wait_physics_frames(3)
	guard.advance_ai(0.05)
	_check(
		guard.get_current_target_id() == PlayerController.DETECTION_ID,
		"visible live Player deterministically takes priority over a Ghost"
	)
	_check(
		guard.get_suspicion() <= 0.05 + FLOAT_EPSILON,
		"switching targets does not leak the Ghost's suspicion into the Player"
	)
	player.global_position = Vector2(-100.0, 0.0)
	ghost.global_position = Vector2(-80.0, 0.0)
	guard.suspicion = 0.01
	guard.advance_ai(1.0)
	_check(
		guard.get_suspicion() >= 0.0 and guard.get_suspicion() <= 1.0,
		"suspicion remains clamped to the inclusive 0..1 range"
	)
	await _cleanup_fixture(fixture)


func _test_capture_and_reset() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	guard.idle_duration = 5.0
	guard.perception_update_interval = 0.01
	guard.suspicion_gain_per_second = 10.0
	guard.capture_hold_time = 0.2
	var player := _spawn_player(fixture, Vector2(10.0, 0.0))
	await _wait_physics_frames(3)
	var capture_counter := {"value": 0}
	guard.capture_requested.connect(
		func(_player: PlayerController) -> void:
			capture_counter["value"] = int(capture_counter["value"]) + 1
	)
	guard.advance_ai(0.05)
	guard.advance_ai(0.05)
	_check(guard.state == GuardController.GuardState.CHASE, "nearby Player can trigger CHASE")
	guard.advance_ai(0.14)
	_check(
		int(capture_counter["value"]) == 0,
		"capture does not fire before its hold duration"
	)
	guard.advance_ai(0.02)
	guard.advance_ai(0.5)
	_check(
		int(capture_counter["value"]) == 1,
		"capture fires exactly once after the hold duration"
	)

	guard.reset_for_loop()
	guard.set_physics_process(false)
	player.global_position = Vector2(40.0, 0.0)
	guard.advance_ai(0.01)
	await _wait_physics_frames(2)
	guard.advance_ai(0.05)
	guard.advance_ai(0.05)
	guard.advance_ai(0.2)
	_check(
		int(capture_counter["value"]) == 1 and _approximately_equal(guard.get_capture_timer(), 0.0),
		"CHASE does not capture a Player outside capture distance"
	)

	guard.reset_for_loop()
	guard.set_physics_process(false)
	player.global_position = Vector2(10.0, 0.0)
	guard.advance_ai(0.01)
	await _wait_physics_frames(2)
	guard.advance_ai(0.05)
	guard.advance_ai(0.05)
	var wall := _spawn_wall(fixture, Vector2(5.0, -18.0))
	await _wait_physics_frames(2)
	guard.advance_ai(0.3)
	_check(
		int(capture_counter["value"]) == 1
		and _approximately_equal(guard.get_capture_timer(), 0.0),
		"world collision prevents capture through a wall"
	)

	guard.set_simulation_enabled(false)
	guard.global_position += Vector2(33.0, 17.0)
	guard.suspicion = 0.8
	guard.reset_for_loop()
	_check(
		not guard.is_simulation_enabled()
		and guard.state == GuardController.GuardState.IDLE
		and _approximately_equal(guard.get_suspicion(), 0.0)
		and guard.get_current_target_id() == StringName()
		and _approximately_equal(guard.get_capture_timer(), 0.0),
		"reset clears Guard state while preserving the Timeline simulation lock"
	)
	_check(
		guard.get_visual().get_current_animation() == &"idle_right"
		and not guard.get_visual().is_alerted()
		and guard.get_visual().get_indicator_text() == "?",
		"reset restores the authored facing idle and neutral indicator"
	)
	await _cleanup_fixture(fixture)


func _test_visual_feedback() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	var visual: GuardVisual = guard.get_visual()
	visual.update_state(Vector2.RIGHT, Vector2.RIGHT * 20.0, &"patrol", 0.0)
	_check(visual.get_current_animation() == &"walk_right", "patrol motion selects walk_right")
	visual.update_state(Vector2.LEFT, Vector2.ZERO, &"suspicious", 0.5)
	_check(
		visual.get_current_animation() == &"alert_left"
		and visual.get_indicator_text() == "?"
		and not visual.is_alerted(),
		"SUSPICIOUS uses directional alert animation and a question-mark indicator"
	)
	visual.update_state(Vector2.UP, Vector2.ZERO, &"chase", 1.0)
	_check(
		visual.get_current_animation() == &"alert_up"
		and visual.get_indicator_text() == "!"
		and visual.is_alerted(),
		"CHASE uses directional alert animation and a distinct exclamation indicator"
	)
	_check(
		visual.get_vision_polygon().size() == GuardVisual.CONE_SEGMENTS + 2,
		"vision cone geometry is generated once from the configured perception values"
	)
	await _cleanup_fixture(fixture)


func _test_eight_ghost_target_stress() -> void:
	var context: Dictionary = await _create_guard_fixture(Vector2.RIGHT)
	var fixture := context["fixture"] as Node2D
	var guard := context["guard"] as GuardController
	guard.idle_duration = 5.0
	guard.perception_update_interval = 0.01
	var ghosts: Array[GhostPlayback] = []
	for loop_index: int in range(8, 0, -1):
		ghosts.push_front(
			_spawn_ghost(
				fixture,
				Vector2(70.0 + float(loop_index) * 4.0, float(loop_index - 4) * 3.0),
				loop_index,
				10.0
			)
		)
	var player := _spawn_player(fixture, Vector2(60.0, 0.0))
	await _wait_physics_frames(4)
	var perception: GuardPerception = guard.get_perception()
	var visible_targets := perception.get_visible_targets(Vector2.RIGHT)
	_check(
		perception.get_candidate_count() == 9 and visible_targets.size() == 9,
		"one Guard caches one Player and eight Ghost candidates without scene-tree scans"
	)
	_check(
		not visible_targets.is_empty()
		and visible_targets[0] == player,
		"Player remains first priority under the eight-Ghost stress fixture"
	)
	player.global_position = Vector2(-80.0, 0.0)
	var deterministic_target := StringName()
	var selection_stable := true
	for _iteration: int in range(120):
		visible_targets = perception.get_visible_targets(Vector2.RIGHT)
		if visible_targets.is_empty():
			selection_stable = false
			break
		var target := visible_targets[0] as Node2D
		var target_id := StringName(target.call(&"get_detection_id"))
		if deterministic_target == StringName():
			deterministic_target = target_id
		elif target_id != deterministic_target:
			selection_stable = false
			break
	_check(
		selection_stable and deterministic_target == &"ghost_001",
		"Ghost target selection remains stable and ID-sorted across repeated queries"
	)
	ghosts[0].advance_to(10.0)
	visible_targets = perception.get_visible_targets(Vector2.RIGHT)
	_check(
		is_instance_valid(ghosts[0])
		and not ghosts[0].is_detectable_by_guard()
		and not visible_targets.is_empty()
		and StringName(visible_targets[0].call(&"get_detection_id")) == &"ghost_002",
		"completed Ghost remains in the scene but the next live Ghost becomes the target"
	)
	await _cleanup_fixture(fixture)


func _create_guard_fixture(facing: Vector2) -> Dictionary:
	var fixture := Node2D.new()
	fixture.name = "GuardAITestFixture"
	_tree.root.add_child(fixture)
	var route := Node2D.new()
	route.name = "PatrolRoute"
	fixture.add_child(route)
	var point_one := Marker2D.new()
	point_one.position = Vector2.ZERO
	route.add_child(point_one)
	var point_two := Marker2D.new()
	point_two.position = Vector2(96.0, 0.0)
	route.add_child(point_two)
	var guard := GUARD_SCENE.instantiate() as GuardController
	guard.initial_facing = facing
	guard.patrol_route_path = NodePath("../PatrolRoute")
	guard.reset_perception_grace = 0.0
	guard.position = Vector2.ZERO
	fixture.add_child(guard)
	guard.set_physics_process(false)
	guard.advance_ai(0.001)
	guard.set_physics_process(false)
	await _wait_physics_frames(2)
	return {"fixture": fixture, "guard": guard}


func _spawn_player(parent: Node, position: Vector2) -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	parent.add_child(player)
	player.initialize_at(position)
	player.set_physics_process(false)
	return player


func _spawn_ghost(
	parent: Node,
	position: Vector2,
	loop_index: int,
	duration: float
) -> GhostPlayback:
	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	parent.add_child(ghost)
	var samples: Array[TransformSample] = [
		TransformSample.new(0.0, position, Vector2.RIGHT, &"idle", Vector2.ZERO),
		TransformSample.new(duration, position, Vector2.RIGHT, &"idle", Vector2.ZERO),
	]
	var events: Array[RecordedEvent] = []
	ghost.configure(LoopRecording.new(duration, samples, events, loop_index), null, loop_index)
	return ghost


func _spawn_wall(parent: Node, position: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = position
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 80.0)
	collision_shape.shape = rectangle
	wall.add_child(collision_shape)
	parent.add_child(wall)
	return wall


func _wait_physics_frames(count: int) -> void:
	for _frame: int in range(count):
		await _tree.physics_frame
		await _tree.process_frame


func _cleanup_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await _tree.process_frame
	await _tree.physics_frame


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)


func _approximately_equal(left: float, right: float) -> bool:
	return absf(left - right) <= FLOAT_EPSILON
