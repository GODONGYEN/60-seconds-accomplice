class_name HeistSystemsTestSuite
extends Node

const MISSION_DEFINITION: MissionDefinition = preload(
	"res://resources/missions/operation_black_minute.tres"
)
const ACCESS_DOOR_SCENE: PackedScene = preload("res://scenes/objects/access_door.tscn")
const HACK_TERMINAL_SCENE: PackedScene = preload("res://scenes/objects/hack_terminal.tscn")
const SECURITY_CAMERA_SCENE: PackedScene = preload(
	"res://scenes/security/security_camera.tscn"
)
const SECURITY_LASER_SCENE: PackedScene = preload(
	"res://scenes/security/security_laser.tscn"
)
const FLOAT_EPSILON: float = 0.0001

var _tree: SceneTree
var _expectation: Callable
var _assertion_count: int = 0


class SecurityActor:
	extends CharacterBody2D

	var actor_id: StringName = &"player_live"

	func get_detection_id() -> StringName:
		return actor_id

	func is_detectable_by_guard() -> bool:
		return true


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	_assertion_count = 0
	print("[TEST] Heist objective, access, CCTV, laser, and alert systems")
	await _test_objective_progression_and_or_authorization()
	await _test_access_levels_and_rewind()
	await _test_terminal_actor_and_access_contract()
	await _test_security_detection_and_reset()


func get_assertion_count() -> int:
	return _assertion_count


func _test_objective_progression_and_or_authorization() -> void:
	var fixture := Node.new()
	_tree.root.add_child(fixture)
	var director := MissionDirector.new()
	director.mission_definition = MISSION_DEFINITION
	fixture.add_child(director)
	await _tree.process_frame
	_check(director.begin_mission(), "Operation Black Minute begins only from a valid mission definition")
	_check(
		director.objective_graph.get_state(MissionDirector.OBJECTIVE_INFILTRATE)
		== ObjectiveGraph.ObjectiveState.ACTIVE
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_LEVEL_1)
		== ObjectiveGraph.ObjectiveState.LOCKED,
		"briefing completion activates infiltration while later objectives remain locked"
	)
	_check(
		not director.report_event(&"chronos_core_stolen")
		and not director.chronos_core_carried,
		"Chronos Core theft cannot complete before its prerequisite chain"
	)
	_check(
		director.report_event(&"level_1_acquired")
		and director.has_latched_event(&"level_1_acquired")
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_LEVEL_1)
		== ObjectiveGraph.ObjectiveState.LOCKED,
		"early Level 1 pickup is retained as a pending world fact instead of being lost"
	)
	var pending_access_snapshot := director.capture_recall_state()
	_check(
		director.report_event(&"facility_entered")
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_INFILTRATE)
		== ObjectiveGraph.ObjectiveState.COMPLETED
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_LEVEL_1)
		== ObjectiveGraph.ObjectiveState.COMPLETED,
		"infiltration reconciles the already acquired Level 1 card without a soft-lock"
	)
	_check(
		director.restore_recall_state(pending_access_snapshot)
		and director.has_latched_event(&"level_1_acquired")
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_LEVEL_1)
		== ObjectiveGraph.ObjectiveState.LOCKED
		and director.report_event(&"facility_entered")
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_LEVEL_1)
		== ObjectiveGraph.ObjectiveState.COMPLETED,
		"Recall restores and deterministically reconciles the pending event ledger"
	)
	_check(
		director.objective_graph.get_state(MissionDirector.OBJECTIVE_SERVER_OVERRIDE)
		== ObjectiveGraph.ObjectiveState.LOCKED
		and director.report_event(&"server_override")
		and director.has_latched_event(&"server_override")
		and not director.has_vault_authorization(),
		"early Server override is retained but cannot authorize the vault before Level 2"
	)
	var post_level_one_ids := director.get_current_objective_ids()
	_check(
		post_level_one_ids.size() == 3
		and post_level_one_ids[0] == MissionDirector.OBJECTIVE_LASERS
		and post_level_one_ids[1] == MissionDirector.OBJECTIVE_LEVEL_2
		and post_level_one_ids[2] == MissionDirector.OBJECTIVE_CCTV,
		"required objectives stay ahead of the optional CCTV route in the bounded HUD list"
	)
	_check(
		director.report_event(&"laser_disabled")
		and director.report_event(&"level_2_acquired"),
		"laser shutdown and Level 2 access reconcile the pending authorization chain"
	)
	_check(
		director.has_vault_authorization()
		and director.get_vault_authorization_route() == &"SERVER OVERRIDE"
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_BIOMETRIC)
		== ObjectiveGraph.ObjectiveState.FAILED,
		"pending Server override satisfies the OR and closes the unused biometric branch"
	)
	_check(
		director.report_event(&"vault_entered"),
		"laser, Level 2, and authorization prerequisites unlock the Chronos Vault"
	)
	var before_core: Dictionary = director.capture_recall_state()
	_check(
		director.report_event(&"chronos_core_stolen")
		and director.chronos_core_carried,
		"Core interaction completes the theft objective and enables extraction state"
	)
	_check(
		director.restore_recall_state(before_core)
		and not director.chronos_core_carried
		and director.objective_graph.get_state(MissionDirector.OBJECTIVE_CORE)
		!= ObjectiveGraph.ObjectiveState.COMPLETED,
		"Recall restores objective graph and Core ownership without duplicating completion"
	)
	_check(
		director.report_event(&"chronos_core_stolen")
		and director.request_extraction()
		and director.is_completed(),
		"restored mission can steal the Core once and complete extraction"
	)
	await _cleanup_fixture(fixture)


func _test_access_levels_and_rewind() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var access := AccessControlManager.new()
	fixture.add_child(access)
	var player := _spawn_actor(fixture, &"player_live", &"player_actor")
	var level_one := ACCESS_DOOR_SCENE.instantiate() as AccessDoor
	level_one.object_id = &"door_level_1_test"
	level_one.required_access = AccessControlManager.AccessLevel.LEVEL_1
	fixture.add_child(level_one)
	var level_two := ACCESS_DOOR_SCENE.instantiate() as AccessDoor
	level_two.object_id = &"door_level_2_test"
	level_two.required_access = AccessControlManager.AccessLevel.LEVEL_2
	fixture.add_child(level_two)
	await _tree.process_frame
	level_one.configure(access)
	level_two.configure(access)

	var denial_count: Array[int] = [0]
	access.access_denied.connect(
		func(_door_id: StringName, _required: AccessControlManager.AccessLevel) -> void:
			denial_count[0] += 1
	)
	var door_denial_count: Array[int] = [0]
	var door_denial_reason: Array[String] = [""]
	level_one.access_denied.connect(
		func(
			_door_id: StringName,
			_required: AccessControlManager.AccessLevel,
			reason: String
		) -> void:
			door_denial_count[0] += 1
			door_denial_reason[0] = reason
	)
	_check(
		not access.authorize(level_one.object_id, AccessControlManager.AccessLevel.LEVEL_1)
		and denial_count[0] == 1,
		"PUBLIC access receives explicit denial at a Level 1 door"
	)
	_check(
		not level_one.interact(player)
		and denial_count[0] == 1
		and door_denial_count[0] == 1
		and door_denial_reason[0] == "LEVEL 1 CARD REQUIRED",
		"door interaction emits one reason-bearing denial without duplicating the manager path"
	)
	_check(
		access.grant_access(AccessControlManager.AccessLevel.LEVEL_1, &"card_level_1")
		and access.can_access(AccessControlManager.AccessLevel.LEVEL_1)
		and not access.can_access(AccessControlManager.AccessLevel.LEVEL_2),
		"Level 1 card grants Level 1 but never escalates to Level 2"
	)
	_check(level_one.interact(player), "authorized Player opens a Level 1 door")
	var access_snapshot: Dictionary = access.capture_recall_state()
	var level_one_snapshot: Dictionary = level_one.capture_recall_state()
	var level_two_snapshot: Dictionary = level_two.capture_recall_state()
	_check(
		access.grant_access(AccessControlManager.AccessLevel.LEVEL_2, &"card_level_2")
		and level_two.interact(player),
		"Level 2 card permits the corresponding security door"
	)
	_check(
		access.restore_recall_state(access_snapshot)
		and level_one.restore_recall_state(level_one_snapshot)
		and level_two.restore_recall_state(level_two_snapshot),
		"access inventory and both door states accept a transactional rewind snapshot"
	)
	_check(
		access.current_level == AccessControlManager.AccessLevel.LEVEL_1
		and access.has_credential(&"card_level_1")
		and not access.has_credential(&"card_level_2")
		and level_one.is_open
		and not level_two.is_open,
		"rewind removes later credentials and restores each physical door independently"
	)

	var echo := _spawn_actor(fixture, &"echo_test", &"ghost_actor")
	_check(
		not level_two.replay_event(&"interact", echo, {"authorized": false})
		and not access.has_credential(&"card_level_2"),
		"Echo cannot manufacture a missing keycard through replay"
	)
	level_two.set_discovered(false)
	_check(
		not level_two.replay_event(&"interact", echo, {"authorized": true})
		and not level_two.is_open,
		"Echo cannot replay an authorized interaction against a door hidden in the restored branch"
	)
	level_two.set_discovered(true)
	_check(
		level_two.replay_event(&"interact", echo, {"authorized": true})
		and level_two.is_open
		and not access.has_credential(&"card_level_2"),
		"authorized abandoned interaction may open a door without mutating live inventory"
	)
	await _cleanup_fixture(fixture)


func _test_terminal_actor_and_access_contract() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var access := AccessControlManager.new()
	fixture.add_child(access)
	var player := _spawn_actor(fixture, &"player_terminal", &"player_actor")
	var echo := _spawn_actor(fixture, &"echo_terminal", &"ghost_actor")

	var authorization := HACK_TERMINAL_SCENE.instantiate() as HackTerminal
	authorization.object_id = &"terminal_authorization_test"
	authorization.action_id = &"server_override"
	authorization.echo_replay_allowed = false
	fixture.add_child(authorization)
	authorization.configure_access(access, AccessControlManager.AccessLevel.LEVEL_2)
	await _tree.process_frame
	_check(
		not authorization.can_interact(player)
		and authorization.get_interaction_prompt(player)
		== "LEVEL 2 ACCESS REQUIRED  //  VAULT OVERRIDE"
		and authorization.get_action_label() == "VAULT OVERRIDE",
		"credential terminal names its action while enforcing Level 2 live access"
	)
	_check(
		not authorization.can_interact(echo),
		"Echo cannot complete a credential-granting authorization terminal"
	)
	_check(
		access.grant_access(AccessControlManager.AccessLevel.LEVEL_2, &"card_level_2")
		and authorization.interact(player)
		and authorization.complete_hack_immediately(),
		"Level 2 live Player can complete the credential terminal"
	)

	var distraction := HACK_TERMINAL_SCENE.instantiate() as HackTerminal
	distraction.object_id = &"terminal_distraction_test"
	distraction.action_id = &"terminal_guard_distraction_01"
	distraction.echo_replay_allowed = true
	fixture.add_child(distraction)
	distraction.configure_access(access, AccessControlManager.AccessLevel.PUBLIC)
	var completed_actor: Array[Node] = []
	distraction.hack_completed.connect(
		func(_action_id: StringName, actor: Node) -> void:
			completed_actor.append(actor)
	)
	_check(
		distraction.interact(echo)
		and distraction.complete_hack_immediately()
		and completed_actor.size() == 1
		and completed_actor[0] == echo,
		"Echo retains explicitly permitted deterministic distraction-terminal replay"
	)
	distraction.reset_mission()
	_check(
		distraction.interact(player),
		"Recall boundary regression starts a live incomplete terminal transaction"
	)
	distraction.call(&"_process", distraction.hack_duration_seconds * 0.5)
	var active_hack_snapshot := distraction.capture_recall_state()
	distraction.complete_hack_immediately()
	_check(
		distraction.restore_recall_state(active_hack_snapshot)
		and not distraction.is_completed
		and is_zero_approx(distraction.hack_elapsed)
		and distraction.can_interact(player)
		and not distraction.is_processing(),
		"Recall restores a mid-hack snapshot to a clean interactable boundary with no stranded owner"
	)
	var laser_terminal := HACK_TERMINAL_SCENE.instantiate() as HackTerminal
	laser_terminal.action_id = &"disable_lasers"
	fixture.add_child(laser_terminal)
	_check(
		laser_terminal.get_action_label() == "LASER GRID"
		and laser_terminal.get_action_code() == "LZR"
		and laser_terminal.get_action_color() != authorization.get_action_color()
		and laser_terminal.get_action_label() != distraction.get_action_label(),
		"terminal function is distinguishable by label, code, and color before interaction"
	)
	await _cleanup_fixture(fixture)


func _test_security_detection_and_reset() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var security := SecuritySystemManager.new()
	security.alert_decay_seconds = 2.0
	fixture.add_child(security)
	var camera := SECURITY_CAMERA_SCENE.instantiate() as SecurityCamera
	camera.position = Vector2.ZERO
	camera.sweep_speed_degrees = 0.0
	camera.detection_gain_per_second = 5.0
	camera.update_interval = 0.05
	fixture.add_child(camera)
	var laser := SECURITY_LASER_SCENE.instantiate() as SecurityLaser
	laser.position = Vector2(260.0, 0.0)
	fixture.add_child(laser)
	var player := _spawn_actor(fixture, &"player_live", &"player_actor")
	player.position = Vector2(100.0, 18.0)
	await _wait_physics_frames(2)
	camera.set_physics_process(false)
	camera.configure(security)
	security.laser_network_changed.connect(laser.set_active)

	_check(
		camera.is_target_visible(player),
		"online CCTV sees a detectable Player inside its clear authored cone"
	)
	var wall := _spawn_wall(fixture, Vector2(50.0, 0.0))
	await _wait_physics_frames(2)
	_check(not camera.is_target_visible(player), "world collision blocks CCTV line of sight")
	wall.queue_free()
	await _wait_physics_frames(2)

	var initial_security: Dictionary = security.capture_recall_state()
	var initial_camera: Dictionary = camera.capture_recall_state()
	var initial_laser: Dictionary = laser.capture_recall_state()
	camera._on_body_entered(player)
	camera.advance_camera(0.25)
	_check(
		camera.get_detection(&"player_live") >= 1.0
		and security.alert_level == SecuritySystemManager.AlertLevel.ALERTED
		and security.has_zone_alert(camera.zone_id),
		"CCTV detection threshold raises an alert only in its authored security zone"
	)
	_check(
		security.disable_cctv_network()
		and not camera.network_online
		and not camera.is_target_visible(player),
		"CCTV network shutdown immediately stops camera detection"
	)
	_check(
		security.disable_laser_network() and not laser.is_active,
		"laser network shutdown disables the physical beam trigger"
	)
	_check(
		security.restore_recall_state(initial_security)
		and camera.restore_recall_state(initial_camera)
		and laser.restore_recall_state(initial_laser),
		"security manager, CCTV sweep, and laser state restore from Recall data"
	)
	_check(
		security.cctv_online
		and security.laser_online
		and security.alert_level == SecuritySystemManager.AlertLevel.CLEAR
		and not security.has_zone_alert(camera.zone_id)
		and camera.network_online
		and laser.is_active,
		"restored security state is online, clear, and free of stale zone alerts"
	)

	camera.reset_mission()
	camera.advance_camera(0.75)
	var deterministic_angle: float = camera.get_facing_angle()
	camera.reset_mission()
	camera.advance_camera(0.75)
	_check(
		absf(camera.get_facing_angle() - deterministic_angle) <= FLOAT_EPSILON,
		"CCTV sweep repeats deterministically from its authored reset phase"
	)
	camera.sweep_half_angle_degrees = 38.0
	camera.sweep_speed_degrees = 20.0
	camera.start_phase_seconds = 3.0
	camera.reset_mission()
	_check(
		absf(camera.get_facing_angle() - deg_to_rad(16.0)) <= FLOAT_EPSILON
		and camera.sweep_direction < 0.0,
		"CCTV start phase advances the sweep itself instead of only staggering detection"
	)

	var trip_count: Array[int] = [0]
	laser.tripped.connect(
		func(_actor: Node, _zone_id: StringName) -> void:
			trip_count[0] += 1
	)
	laser._on_body_entered(player)
	var echo := _spawn_actor(fixture, &"echo_security", &"ghost_actor")
	laser._on_body_entered(echo)
	_check(
		trip_count[0] == 1,
		"active laser trips the live Player while temporal Echo remains non-physical"
	)

	security.raise_zone_alert(
		&"research_wing",
		Vector2(320.0, 160.0),
		&"camera_research_01",
		SecuritySystemManager.AlertLevel.ALERTED
	)
	security.advance_alert_decay(2.0)
	_check(
		security.alert_level == SecuritySystemManager.AlertLevel.SUSPICIOUS,
		"facility alert deterministically decays from ALERTED to SUSPICIOUS"
	)
	security.advance_alert_decay(2.0)
	_check(
		security.alert_level == SecuritySystemManager.AlertLevel.CLEAR
		and not security.has_zone_alert(&"research_wing"),
		"second decay window clears localized suspicion and stale zone data"
	)
	security.disable_cctv_network()
	security.disable_laser_network()
	security.raise_facility_alert(SecuritySystemManager.AlertLevel.LOCKDOWN)
	security.reset_mission()
	_check(
		security.cctv_online
		and security.laser_online
		and security.alert_level == SecuritySystemManager.AlertLevel.CLEAR,
		"mission reset restores both networks and CLEAR alert state"
	)
	await _cleanup_fixture(fixture)


func _spawn_actor(parent: Node, actor_id: StringName, group_name: StringName) -> SecurityActor:
	var actor := SecurityActor.new()
	actor.actor_id = actor_id
	actor.collision_layer = 2 if group_name == &"player_actor" else 4
	actor.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(18.0, 12.0)
	shape.shape = rectangle
	actor.add_child(shape)
	parent.add_child(actor)
	actor.add_to_group(&"detectable_actor")
	actor.add_to_group(group_name)
	return actor


func _spawn_wall(parent: Node, position: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = position
	wall.collision_layer = 1
	wall.collision_mask = 0
	var collision_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 96.0)
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
	await _tree.process_frame


func _check(condition: bool, description: String) -> void:
	_assertion_count += 1
	if _expectation.is_valid():
		_expectation.call(condition, description)
