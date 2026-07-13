class_name OperationBlackMinuteRuntimeTestSuite
extends Node

const OPERATION_SCENE: PackedScene = preload(
	"res://scenes/levels/operation_black_minute.tscn"
)
const STEP_SECONDS: float = 0.05

var _tree: SceneTree
var _expectation: Callable


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Operation: Black Minute runtime acceptance")
	var operation := OPERATION_SCENE.instantiate() as OperationBlackMinuteLevel
	_check(operation != null, "operation scene instantiates as the heist mission controller")
	if operation == null:
		return
	_tree.root.add_child(operation)
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.process_frame
	await _test_runtime_contract(operation)
	await _test_modal_pause_freeze(operation)
	await _test_no_recall_solution(operation)
	await _test_recall_and_echo(operation)
	operation.queue_free()
	await _tree.process_frame
	await _tree.physics_frame
	await _tree.process_frame


func _test_runtime_contract(operation: OperationBlackMinuteLevel) -> void:
	var operation_map: OperationBlackMinuteMap = operation.get_node("OperationMap")
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	_check(
		operation_map.get_map_size() == Vector2i(64, 42)
		and operation_map.get_world_size() == Vector2i(2048, 1344),
		"runtime mission builds the authored 64x42 facility instead of scaling the prototype"
	)
	_check(
		operation.get_guard_count() == 10
		and operation.get_camera_count() == 8
		and operation.get_laser_count() == 3,
		"runtime mission creates ten Guards, eight CCTV cameras, and three physical lasers"
	)
	_check(
		registry.last_rebuild_succeeded() and registry.get_registered_count() >= 40,
		"all dynamic heist objects rebuild into the stable-ID registry"
	)
	for required_id: StringName in [
		&"keycard_level_1_01",
		&"keycard_level_2_01",
		&"terminal_cctv_network_01",
		&"terminal_laser_network_01",
		&"terminal_server_override_01",
		&"objective_chronos_core_01",
		&"extraction_yard_01",
	]:
		_check(registry.has_object(required_id), "runtime registry contains '%s'" % required_id)
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	_check(
		recall.remaining_charges == 3
		and recall.maximum_echoes == 3
		and is_equal_approx(recall.rewind_duration_seconds, 10.0),
		"formal mission starts with three bounded ten-second Recall charges"
	)
	var server_terminal := registry.get_object(&"terminal_server_override_01") as HackTerminal
	var biometric_terminal := (
		registry.get_object(&"terminal_research_biometric_01") as HackTerminal
	)
	var distraction_terminal := (
		registry.get_object(&"terminal_guard_distraction_01") as HackTerminal
	)
	_check(
		server_terminal.required_access == AccessControlManager.AccessLevel.LEVEL_2
		and biometric_terminal.required_access == AccessControlManager.AccessLevel.LEVEL_2
		and not server_terminal.echo_replay_allowed
		and not biometric_terminal.echo_replay_allowed
		and not server_terminal.can_interact(operation.get_player())
		and not biometric_terminal.can_interact(operation.get_player())
		and distraction_terminal.echo_replay_allowed,
		"both credential terminals require a Level 2 live Player while preserving Echo distraction"
	)
	_disable_security_simulation(operation)
	var phased_guard := registry.get_object(&"guard_yard_02") as GuardController
	if phased_guard != null:
		phased_guard.reset_for_loop()
	_check(
		phased_guard != null
		and phased_guard.global_position.is_equal_approx(Vector2(336.0, 1264.0))
		and phased_guard.get_patrol_index() == 1
		and phased_guard.state == GuardController.GuardState.IDLE
		and phased_guard.get_facing_direction().dot(Vector2.RIGHT) >= 0.999,
		"runtime Guard starts 7.5 seconds into the shared phased patrol and faces away during the authored onboarding wait"
	)
	var phased_camera := registry.get_object(&"camera_staff_01") as SecurityCamera
	if phased_camera != null:
		phased_camera.reset_mission()
	_check(
		phased_camera != null
		and absf(
			wrapf(
				phased_camera.get_facing_angle() - deg_to_rad(196.0),
				-PI,
				PI
			)
		) <= 0.0001
		and phased_camera.sweep_direction < 0.0,
		"runtime CCTV applies its authored three-second phase to the deterministic sweep"
	)
	await _tree.process_frame


func _test_modal_pause_freeze(operation: OperationBlackMinuteLevel) -> void:
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var director: MissionDirector = operation.get_node("Systems/MissionDirector")
	var map_overlay: FacilityMapOverlay = operation.get_node("FacilityMapOverlay")
	var hud: HeistHUD = operation.get_node("HeistHUD")
	var player := operation.get_player()
	var terminal := registry.get_object(&"terminal_staff_intel_01") as HackTerminal
	var capture_recall_button := hud.get_node("%CaptureRecallButton") as Button

	_check(terminal.interact(player), "pause regression starts a real in-progress terminal hack")
	var map_pause_world_time := recall.get_world_time()
	var map_pause_hack_time := terminal.hack_elapsed
	map_overlay.open_map()
	_check(
		_tree.paused
		and operation.can_process()
		and hud.can_process()
		and map_overlay.can_process()
		and not player.can_process()
		and not terminal.can_process()
		and not recall.can_process(),
		"map pause keeps modal controls alive while every gameplay branch is pausable"
	)
	await _tree.create_timer(0.08, true).timeout
	_check(
		is_equal_approx(recall.get_world_time(), map_pause_world_time)
		and is_equal_approx(terminal.hack_elapsed, map_pause_hack_time),
		"map pause advances neither Chrono history nor an in-progress terminal hack"
	)
	map_overlay.close_map()
	terminal.reset_mission()

	_check(terminal.interact(player), "focus-loss regression starts a real terminal hack")
	var focus_world_time := recall.get_world_time()
	var focus_hack_time := terminal.hack_elapsed
	operation.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(
		_tree.paused
		and operation.is_pause_open()
		and not player.can_process()
		and not terminal.can_process()
		and not recall.can_process(),
		"operation focus loss enters the same safe modal pause as an explicit pause"
	)
	await _tree.create_timer(0.08, true).timeout
	_check(
		is_equal_approx(recall.get_world_time(), focus_world_time)
		and is_equal_approx(terminal.hack_elapsed, focus_hack_time),
		"unfocused operation advances neither Recall history nor active hacks"
	)
	hud.resume_requested.emit()
	_check(not _tree.paused and not operation.is_pause_open(), "focus pause resumes explicitly")
	terminal.reset_mission()

	_check(terminal.interact(player), "capture regression starts a second terminal hack")
	recall.advance(0.1)
	_check(recall.can_recall(), "capture regression prepares an available Recall branch")
	var charges_before_capture := recall.remaining_charges
	var capture_world_time := recall.get_world_time()
	var capture_hack_time := terminal.hack_elapsed
	operation.call(&"_request_capture", &"test_guard")
	_check(
		_tree.paused
		and director.state == MissionDirector.MissionState.CAPTURE_DECISION
		and not terminal.can_process()
		and hud.can_process()
		and capture_recall_button.visible,
		"capture decision preserves pre-freeze Recall availability in the modal UI"
	)
	await _tree.create_timer(0.08, true).timeout
	_check(
		is_equal_approx(recall.get_world_time(), capture_world_time)
		and is_equal_approx(terminal.hack_elapsed, capture_hack_time)
		and not terminal.is_completed,
		"capture choice cannot complete a hack or mutate the recorded world behind the modal"
	)
	operation.call(&"_resolve_capture_with_recall")
	_check(
		recall.remaining_charges == charges_before_capture - 1
		and director.is_mission_active()
		and not _tree.paused
		and not hud.capture_panel.visible,
		"Q and the visible Recall choice resolve capture through the same available branch"
	)
	_check(operation.reset_operation(), "Recall recovery permits a clean checkpoint restart")
	var charges_without_history := recall.remaining_charges
	operation.call(&"_request_capture", &"test_guard_no_history")
	_check(
		_tree.paused and not capture_recall_button.visible,
		"capture UI hides Recall when the fresh branch has no recorded history"
	)
	operation.call(&"_resolve_capture_with_recall")
	_check(
		recall.remaining_charges == charges_without_history
		and director.state == MissionDirector.MissionState.CAPTURE_DECISION
		and _tree.paused,
		"Q cannot bypass the unavailable Recall state shown by the capture UI"
	)
	_check(operation.reset_operation(), "checkpoint recovery exits capture pause into a clean mission")
	_check(not _tree.paused, "checkpoint recovery releases the modal SceneTree pause")
	_disable_security_simulation(operation)


func _test_no_recall_solution(operation: OperationBlackMinuteLevel) -> void:
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var director: MissionDirector = operation.get_node("Systems/MissionDirector")
	var access: AccessControlManager = operation.get_node("Systems/AccessControlManager")
	var security: SecuritySystemManager = operation.get_node("Systems/SecuritySystemManager")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var player := operation.get_player()

	var reception := registry.get_object(&"door_reception_checkpoint_01") as AccessDoor
	_check(reception.interact(player), "PUBLIC reception door opens through the interaction contract")
	_check(
		director.objective_graph.get_state(MissionDirector.OBJECTIVE_INFILTRATE)
		== ObjectiveGraph.ObjectiveState.COMPLETED,
		"entering reception completes the first objective and exposes access progression"
	)

	var level_one := registry.get_object(&"keycard_level_1_01") as AccessCard
	_check(level_one.interact(player), "Player physically collects the locker-room Level 1 card")
	_check(
		access.current_level == AccessControlManager.AccessLevel.LEVEL_1,
		"Level 1 card updates only the live mission inventory"
	)

	var cctv := registry.get_object(&"terminal_cctv_network_01") as HackTerminal
	_check(
		cctv.interact(player) and cctv.complete_hack_immediately(),
		"Player completes the vulnerable CCTV terminal interaction"
	)
	_check(not security.cctv_online, "CCTV terminal takes the eight-camera network offline")

	var lasers := registry.get_object(&"terminal_laser_network_01") as HackTerminal
	_check(
		lasers.interact(player) and lasers.complete_hack_immediately(),
		"Player completes the electrical-room laser shutdown"
	)
	_check(not security.laser_online, "electrical terminal disables all physical laser triggers")

	var level_two := registry.get_object(&"keycard_level_2_01") as AccessCard
	_check(level_two.interact(player), "Player physically collects Level 2 access in Security")
	_check(
		access.current_level == AccessControlManager.AccessLevel.LEVEL_2,
		"Level 2 access opens research and server routes without granting the vault itself"
	)

	var server := registry.get_object(&"terminal_server_override_01") as HackTerminal
	_check(
		server.interact(player) and server.complete_hack_immediately(),
		"alternate Server Room override completes through a real terminal"
	)
	_check(
		director.has_vault_authorization()
		and access.current_level == AccessControlManager.AccessLevel.VAULT,
		"server override satisfies the biometric/server OR and grants vault credentials"
	)

	var vault_door := registry.get_object(&"door_vault_authorization_01") as AccessDoor
	_check(vault_door.interact(player), "authorized Player opens the laser-safe Chronos Vault door")
	_check(
		director.report_event(&"vault_entered"),
		"vault entry cannot complete until laser, Level 2, and authorization prerequisites are met"
	)
	var core := registry.get_object(&"objective_chronos_core_01") as ChronosCore
	_check(
		is_equal_approx(core.interaction_duration_seconds, 1.2)
		and core.interact(player)
		and not core.is_stolen,
		"Player begins the blueprint-authored 1.2-second Core acquisition"
	)
	core.advance_collection(core.interaction_duration_seconds * 0.5)
	_check(
		not core.is_stolen and not director.chronos_core_carried,
		"partial Core acquisition cannot complete theft early"
	)
	core.advance_collection(core.interaction_duration_seconds * 0.5)
	_check(
		core.is_stolen and director.chronos_core_carried and player.has_objective_item(),
		"full Core acquisition updates mission state and the Player carry indicator"
	)
	var extraction := registry.get_object(&"extraction_yard_01") as MissionExtractionZone
	_check(extraction.is_active, "Core theft activates the external extraction zone")
	extraction.extraction_requested.emit(player)
	_check(director.is_completed(), "returning to extraction completes the heist")
	_check(
		recall.remaining_charges == recall.maximum_charges,
		"the complete authored heist route is solvable without Chrono Recall"
	)
	await _tree.process_frame


func _test_recall_and_echo(operation: OperationBlackMinuteLevel) -> void:
	_check(operation.reset_operation(), "mission checkpoint restart rebuilds a clean operation")
	_disable_security_simulation(operation)
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var player := operation.get_player()
	var start_position := player.global_position
	var reception := registry.get_object(&"door_reception_checkpoint_01") as AccessDoor

	for tick: int in range(202):
		player.global_position = start_position + Vector2(float(tick) * 1.5, 0.0)
		if tick == 100:
			_check(reception.interact(player), "abandoned branch records a late physical door opening")
		recall.advance(STEP_SECONDS)
	var monotonic_time := recall.get_world_time()
	_check(reception.is_open, "world state is changed before the Recall transaction")
	_check(recall.request_recall(), "Q-style Recall restores the oldest valid ten-second snapshot")
	_check(
		player.global_position.distance_to(start_position) < 8.0,
		"Recall restores Player transform near the branch start"
	)
	_check(not reception.is_open, "Recall transaction restores the earlier closed-door state")
	_check(
		recall.remaining_charges == 2 and recall.get_echo_count() == 1,
		"Recall consumes one persistent charge and creates exactly one Echo"
	)
	_check(
		is_equal_approx(recall.get_world_time(), monotonic_time),
		"Recall never rewinds the mission's monotonic security clock"
	)
	var echoes := recall.get_echoes()
	var echo: GhostPlayback = echoes[0] if not echoes.is_empty() else null
	_check(
		echo != null
		and echo.is_in_group(&"ghost_actor")
		and echo.is_detectable_by_guard()
		and String(echo.get_detection_id()).begins_with("echo_"),
		"abandoned movement becomes a Guard/CCTV-detectable Echo, not a second inventory owner"
	)
	await _tree.process_frame


func _disable_security_simulation(operation: OperationBlackMinuteLevel) -> void:
	for guard: GuardController in operation.get_node("ActorLayer/GuardContainer").get_children():
		guard.set_simulation_enabled(false)
	for camera: SecurityCamera in operation.get_tree().get_nodes_in_group(&"security_camera"):
		if operation.is_ancestor_of(camera):
			camera.set_physics_process(false)


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)
