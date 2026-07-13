class_name OperationBlackMinutePhysicalAcceptanceTestSuite
extends Node

const OPERATION_SCENE: PackedScene = preload(
	"res://scenes/levels/operation_black_minute.tscn"
)
const TILE_SIZE: int = 32
const MOTION_STEP: float = 8.0
const CARD_LEVEL_1_CELL := Vector2i(6, 19)
const CARD_LEVEL_2_CELL := Vector2i(32, 32)
const CCTV_TERMINAL_CELL := Vector2i(18, 7)
const LASER_TERMINAL_CELL := Vector2i(32, 19)
const SERVER_TERMINAL_CELL := Vector2i(32, 7)
const CORE_CELL := Vector2i(58, 8)

var _tree: SceneTree
var _expectation: Callable


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Operation: Black Minute physical scene acceptance")
	var operation := OPERATION_SCENE.instantiate() as OperationBlackMinuteLevel
	_check(operation != null, "physical acceptance instantiates the production operation scene")
	if operation == null:
		return
	_tree.root.add_child(operation)
	await _settle_physics()
	_disable_detection_threats(operation)
	var player := operation.get_player()
	# The test drives the real CharacterBody2D through PhysicsBody2D motion calls.
	# Keep its physics callback alive so PhysicsServer overlap state stays current,
	# while disabling only gameplay input between deterministic path steps.
	player.set_gameplay_input_enabled(false)
	await _test_physical_no_recall_route(operation)
	_tree.paused = false
	operation.queue_free()
	await _settle_physics()


func _test_physical_no_recall_route(operation: OperationBlackMinuteLevel) -> void:
	var operation_map: OperationBlackMinuteMap = operation.get_node("OperationMap")
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var director: MissionDirector = operation.get_node("Systems/MissionDirector")
	var access: AccessControlManager = operation.get_node("Systems/AccessControlManager")
	var security: SecuritySystemManager = operation.get_node("Systems/SecuritySystemManager")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var player := operation.get_player()

	_check(
		await _walk_to_cell(operation, Vector2i(7, 40), "yard south wall approach"),
		"Player physically reaches a walkable exterior-yard boundary cell"
	)
	_check(
		player.test_move(player.global_transform, Vector2.DOWN * float(TILE_SIZE)),
		"production TileMap wall collision blocks movement out of the 64x42 facility"
	)
	_check(
		await _walk_to_cell(operation, Vector2i(12, 33), "reception gate exterior"),
		"collision-respecting traversal reaches the reception gate from spawn"
	)

	var reception := registry.get_object(&"door_reception_checkpoint_01") as AccessDoor
	_check(
		reception != null and not reception.is_open,
		"the production reception gate starts physically closed"
	)
	_check(
		_crossing_is_blocked(player, Vector2i(14, 33)),
		"the closed reception blocker prevents crossing its authored portal span"
	)
	_check(
		_is_in_interaction_range(player, reception) and reception.interact(player),
		"Player opens the PUBLIC reception gate from physical interaction range"
	)
	await _settle_physics()
	_check(
		not _crossing_is_blocked(player, Vector2i(14, 33)),
		"opening the reception gate removes the same production collision blocker"
	)
	_check(
		await _walk_to_cell(operation, Vector2i(24, 33), "Level 1 security door west"),
		"Player traverses the opened reception gate into the checkpoint"
	)
	_check(
		director.objective_graph.get_state(MissionDirector.OBJECTIVE_INFILTRATE)
		== ObjectiveGraph.ObjectiveState.COMPLETED,
		"physical reception traversal advances the infiltration objective"
	)

	var security_door := registry.get_object(&"door_security_l1_01") as AccessDoor
	_check(
		security_door != null
		and _is_in_interaction_range(player, security_door)
		and not security_door.interact(player),
		"Level 1 security door rejects the physically present PUBLIC Player"
	)
	_check(
		_crossing_is_blocked(player, Vector2i(26, 33)),
		"access denial leaves the Level 1 door's physical blocker enabled"
	)

	_check(
		await _walk_to_cell(operation, CARD_LEVEL_1_CELL, "locker-room Level 1 card"),
		"Player physically reaches the authored locker-room card cell"
	)
	_check(
		operation_map.get_room_at_cell(CARD_LEVEL_1_CELL) == &"locker_room",
		"Level 1 card is reached inside the authored Locker Room"
	)
	var level_one := registry.get_object(&"keycard_level_1_01") as AccessCard
	_check(
		level_one != null
		and _is_in_interaction_range(player, level_one)
		and level_one.interact(player),
		"production AccessCard grants Level 1 only after physical arrival"
	)
	_check(
		access.current_level == AccessControlManager.AccessLevel.LEVEL_1,
		"Level 1 card signal updates the live AccessControlManager"
	)

	_check(
		await _walk_to_cell(operation, Vector2i(24, 33), "Level 1 security door return"),
		"Player physically returns from the locker room to the gated security route"
	)
	_check(
		security_door.interact(player),
		"the same production Level 1 door accepts the acquired credential"
	)
	await _settle_physics()
	_check(
		not _crossing_is_blocked(player, Vector2i(26, 33)),
		"credentialed opening disables the Level 1 door blocker"
	)

	_check(
		await _walk_to_cell(operation, CARD_LEVEL_2_CELL, "security-office Level 2 card"),
		"Player physically crosses the opened Level 1 gate into Security"
	)
	_check(
		operation_map.get_room_at_cell(CARD_LEVEL_2_CELL) == &"security_office",
		"Level 2 card is reached inside the authored Security Office"
	)
	var level_two := registry.get_object(&"keycard_level_2_01") as AccessCard
	_check(
		level_two != null
		and _is_in_interaction_range(player, level_two)
		and level_two.interact(player),
		"production AccessCard grants Level 2 after physical traversal"
	)
	_check(
		access.current_level == AccessControlManager.AccessLevel.LEVEL_2,
		"Level 2 progression is owned by the live access manager"
	)

	_check(
		await _complete_terminal_at(
			operation,
			&"terminal_laser_network_01",
			LASER_TERMINAL_CELL,
			"electrical-room laser shutdown"
		),
		"Player physically reaches and completes the laser-network terminal"
	)
	_check(
		operation_map.get_room_at_cell(LASER_TERMINAL_CELL) == &"electrical_room"
		and not security.laser_online,
		"electrical-room production node disables all physical laser barriers"
	)

	_check(
		await _open_door_from_cell(
			operation,
			&"door_server_l2_01",
			Vector2i(32, 14),
			Vector2i(32, 12),
			"electrical-to-server Level 2 door"
		),
		"Level 2 credential opens and physically traverses the Server Room gate"
	)
	_check(
		await _complete_terminal_at(
			operation,
			&"terminal_server_override_01",
			SERVER_TERMINAL_CELL,
			"server-room vault authorization"
		),
		"Player physically reaches and completes a real vault-authorization source"
	)
	_check(
		operation_map.get_room_at_cell(SERVER_TERMINAL_CELL) == &"server_room"
		and director.has_vault_authorization()
		and access.current_level == AccessControlManager.AccessLevel.VAULT,
		"Server override advances the objective graph and grants vault credentials"
	)

	_check(
		await _open_door_from_cell(
			operation,
			&"door_server_cctv_l2_01",
			Vector2i(26, 7),
			Vector2i(24, 7),
			"server-to-CCTV Level 2 door"
		),
		"Player physically traverses the Server-to-CCTV access door"
	)
	_check(
		await _complete_terminal_at(
			operation,
			&"terminal_cctv_network_01",
			CCTV_TERMINAL_CELL,
			"CCTV control terminal"
		),
		"Player physically reaches and completes the CCTV-network terminal"
	)
	_check(
		operation_map.get_room_at_cell(CCTV_TERMINAL_CELL) == &"cctv_control_room"
		and not security.cctv_online,
		"CCTV Control Room production node takes the camera network offline"
	)

	_check(
		await _open_door_from_cell(
			operation,
			&"door_vault_ante_l2_01",
			Vector2i(52, 19),
			Vector2i(54, 19),
			"laser-corridor vault antechamber door"
		),
		"laser shutdown and Level 2 access permit physical antechamber traversal"
	)
	_check(
		await _open_door_from_cell(
			operation,
			&"door_vault_authorization_01",
			Vector2i(59, 15),
			Vector2i(59, 13),
			"authorized Chronos Vault door"
		),
		"vault authorization physically opens the deep-vault portal"
	)
	_check(
		await _walk_to_cell(operation, CORE_CELL, "Chronos Core landmark"),
		"Player physically traverses from the yard to the deep Chronos Vault"
	)
	await _settle_physics()
	_check(
		operation_map.get_room_at_cell(CORE_CELL) == &"chronos_vault"
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_ENTER_VAULT)
		== ObjectiveGraph.ObjectiveState.COMPLETED,
		"crossing the physical vault-entry trigger unlocks the Core objective"
	)
	var core := registry.get_object(&"objective_chronos_core_01") as ChronosCore
	_check(
		core != null
		and _is_in_interaction_range(player, core)
		and core.interact(player),
		"Player begins the production Core acquisition from physical interaction range"
	)
	if core != null:
		core.advance_collection(core.interaction_duration_seconds)
	player.set_gameplay_input_enabled(false)
	await _settle_physics()
	_check(
		core != null
		and core.is_stolen
		and director.chronos_core_carried
		and player.has_objective_item(),
		"the authored acquisition duration completes Core theft and Player carry state"
	)

	var extraction := registry.get_object(&"extraction_yard_01") as MissionExtractionZone
	_check(
		extraction != null and extraction.is_active,
		"Core theft activates the production extraction Area2D"
	)
	_check(
		await _walk_to_cell(operation, Vector2i(6, 39), "extraction stand-off cell"),
		"auto-opened extraction portals provide a collision-respecting return route"
	)
	_check(
		not extraction.overlaps_body(player),
		"Player reaches a stable cell outside the extraction trigger before entry"
	)
	_check(
		await _drive_into_extraction(player, director),
		"Input Map movement physically enters the active extraction trigger"
	)
	await _settle_physics()
	_check(
		extraction.overlaps_body(player),
		"production extraction Area2D observes the physically entered Player body"
	)
	_check(
		operation_map.get_room_at_cell(_world_to_cell(player.global_position))
		== &"external_infiltration_yard",
		"physical extraction ends in the authored external infiltration yard"
	)
	_check(
		director.is_completed(),
		"physical entry into the active extraction Area2D completes the mission"
	)
	_check(
		recall.remaining_charges == recall.maximum_charges
		and recall.get_echo_count() == 0,
		"the production-scene physical route completes without Chrono Recall or Echoes"
	)


func _drive_into_extraction(
	player: PlayerController,
	director: MissionDirector
) -> bool:
	player.set_gameplay_input_enabled(true)
	Input.action_press(&"move_left")
	for _physics_step: int in range(20):
		await _tree.physics_frame
		await _tree.process_frame
		if director.is_completed():
			break
	Input.action_release(&"move_left")
	player.set_gameplay_input_enabled(false)
	return director.is_completed()


func _complete_terminal_at(
	operation: OperationBlackMinuteLevel,
	terminal_id: StringName,
	target_cell: Vector2i,
	label: String
) -> bool:
	if not await _walk_to_cell(operation, target_cell, label):
		return false
	await _settle_physics()
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var terminal := registry.get_object(terminal_id) as HackTerminal
	var player := operation.get_player()
	if terminal == null or not _is_in_interaction_range(player, terminal):
		return false
	if not terminal.interact(player):
		return false
	# The terminal's production completion method emits the same progression signal
	# as its elapsed-time process. Timing behavior is covered separately; this suite
	# keeps its contract focused on physical reachability and mission wiring.
	if not terminal.complete_hack_immediately():
		return false
	player.set_gameplay_input_enabled(false)
	await _tree.process_frame
	return terminal.is_completed


func _open_door_from_cell(
	operation: OperationBlackMinuteLevel,
	door_id: StringName,
	approach_cell: Vector2i,
	cross_cell: Vector2i,
	label: String
) -> bool:
	if not await _walk_to_cell(operation, approach_cell, "%s approach" % label):
		return false
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var door := registry.get_object(door_id) as AccessDoor
	var player := operation.get_player()
	if door == null or not _is_in_interaction_range(player, door):
		return false
	if not door.is_open and not door.interact(player):
		return false
	await _settle_physics()
	if _crossing_is_blocked(player, cross_cell):
		return false
	return await _walk_to_cell(operation, cross_cell, "%s crossing" % label)


func _walk_to_cell(
	operation: OperationBlackMinuteLevel,
	target_cell: Vector2i,
	label: String
) -> bool:
	var operation_map: OperationBlackMinuteMap = operation.get_node("OperationMap")
	var player := operation.get_player()
	var start_cell := _world_to_cell(player.global_position)
	var path := _find_path(operation, start_cell, target_cell)
	if path.is_empty():
		push_warning(
			"Physical acceptance found no open-door path from %s to %s (%s)"
			% [start_cell, target_cell, label]
		)
		return false
	for path_index: int in range(1, path.size()):
		var step_target := OperationBlackMinuteMap.cell_to_world(path[path_index])
		while player.global_position.distance_to(step_target) > 0.05:
			var remaining := step_target - player.global_position
			var motion := remaining.limit_length(MOTION_STEP)
			var collision := player.move_and_collide(motion)
			if collision != null:
				push_warning(
					"Physical acceptance collision on %s at cell %s against %s"
					% [label, path[path_index], collision.get_collider()]
				)
				return false
	if player.global_position.distance_to(
		OperationBlackMinuteMap.cell_to_world(target_cell)
	) > 0.1:
		return false
	if not operation_map.is_walkable_cell(target_cell):
		return false
	# Await both sides of a physics step so Area2D body-entered triggers observe the
	# final cell before the next route starts moving the body again.
	await _settle_physics()
	return true


func _find_path(
	operation: OperationBlackMinuteLevel,
	start_cell: Vector2i,
	target_cell: Vector2i
) -> Array[Vector2i]:
	var operation_map: OperationBlackMinuteMap = operation.get_node("OperationMap")
	if not operation_map.is_walkable_cell(start_cell):
		return []
	if not operation_map.is_walkable_cell(target_cell):
		return []
	var blocked := _closed_door_cells(operation)
	blocked.erase(start_cell)
	blocked.erase(target_cell)
	var frontier: Array[Vector2i] = [start_cell]
	var cursor: int = 0
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var visited: Dictionary[Vector2i, bool] = {start_cell: true}
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
		Vector2i.UP,
	]
	while cursor < frontier.size():
		var current := frontier[cursor]
		cursor += 1
		if current == target_cell:
			break
		for direction: Vector2i in directions:
			var next := current + direction
			if visited.has(next):
				continue
			if not operation_map.is_walkable_cell(next) or blocked.has(next):
				continue
			visited[next] = true
			came_from[next] = current
			frontier.append(next)
	if not visited.has(target_cell):
		return []
	var reversed_path: Array[Vector2i] = [target_cell]
	var step := target_cell
	while step != start_cell:
		step = came_from[step]
		reversed_path.append(step)
	reversed_path.reverse()
	return reversed_path


func _closed_door_cells(operation: OperationBlackMinuteLevel) -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var portals_variant: Variant = operation.get_blueprint().get("dynamic_portals", [])
	if not portals_variant is Array:
		return result
	for portal_variant: Variant in portals_variant as Array:
		if not portal_variant is Dictionary:
			continue
		var portal := portal_variant as Dictionary
		var door_id := StringName(str(portal.get("id", "")))
		var door := registry.get_object(door_id) as AccessDoor
		if door == null or door.is_open:
			continue
		var rect := _json_rect(portal.get("span_rect", []))
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				result[Vector2i(x, y)] = true
	return result


func _crossing_is_blocked(player: PlayerController, target_cell: Vector2i) -> bool:
	var target_world := OperationBlackMinuteMap.cell_to_world(target_cell)
	return player.test_move(player.global_transform, target_world - player.global_position)


func _is_in_interaction_range(player: PlayerController, target: Node2D) -> bool:
	if target == null:
		return false
	return player.global_position.distance_to(target.global_position) <= 64.0


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(TILE_SIZE)),
		floori(world_position.y / float(TILE_SIZE))
	)


func _json_rect(value: Variant) -> Rect2i:
	if not value is Array or (value as Array).size() != 4:
		return Rect2i()
	return Rect2i(
		int((value as Array)[0]),
		int((value as Array)[1]),
		int((value as Array)[2]),
		int((value as Array)[3])
	)


func _disable_detection_threats(operation: OperationBlackMinuteLevel) -> void:
	for guard: GuardController in operation.get_node("ActorLayer/GuardContainer").get_children():
		guard.set_simulation_enabled(false)
	for camera: SecurityCamera in operation.get_tree().get_nodes_in_group(&"security_camera"):
		if operation.is_ancestor_of(camera):
			camera.set_physics_process(false)


func _settle_physics() -> void:
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.process_frame


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)
