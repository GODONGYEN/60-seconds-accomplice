class_name OperationBlackMinuteRuntimeTestSuite
extends Node

const OPERATION_SCENE: PackedScene = preload(
	"res://scenes/levels/operation_black_minute.tscn"
)
const ENVIRONMENT_ART_TILESET: TileSet = preload(
	"res://resources/tilesets/facility_environment_art.tres"
)
const ENVIRONMENT_ART_ATLAS_PATH: String = (
	"res://assets/sprites/environment/facility_environment_atlas.png"
)
const ENVIRONMENT_CATALOG: GDScript = preload(
	"res://resources/environment/facility_environment_catalog.gd"
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
		ENVIRONMENT_ART_TILESET.tile_size == Vector2i(32, 32)
		and ENVIRONMENT_ART_TILESET.get_physics_layers_count() == 0
		and ENVIRONMENT_ART_TILESET.get_occlusion_layers_count() == 0,
		"environment art TileSet is a visual-only 32px overlay with no gameplay geometry"
	)
	var environment_atlas := ENVIRONMENT_ART_TILESET.get_source(0) as TileSetAtlasSource
	_check(
		environment_atlas != null
		and environment_atlas.texture != null
		and environment_atlas.texture.resource_path == ENVIRONMENT_ART_ATLAS_PATH,
		"environment art TileSet references only the committed runtime atlas"
	)
	_check(
		operation_map.floor.tile_set == ENVIRONMENT_ART_TILESET
		and operation_map.floor_details.tile_set == ENVIRONMENT_ART_TILESET
		and operation_map.wall_art.tile_set == ENVIRONMENT_ART_TILESET
		and operation_map.props_above.tile_set == ENVIRONMENT_ART_TILESET
		and operation_map.walls.tile_set != ENVIRONMENT_ART_TILESET,
		"visual layers use authored art while the original wall layer remains collision authority"
	)
	_check(
		operation_map.walls.collision_enabled
		and operation_map.walls.occlusion_enabled
		and is_zero_approx(operation_map.walls.self_modulate.a)
		and not operation_map.wall_art.collision_enabled
		and not operation_map.wall_art.occlusion_enabled,
		"hidden collision walls and visible wall art preserve exact movement and LOS boundaries"
	)
	_check(
		operation_map.get_semantic_solid_cell_count() == 64
		and operation_map.props_above.get_used_cells().size() == 64,
		"all sixteen blueprint solids receive collision-aligned semantic furniture art"
	)
	_check(
		operation_map.get_floor_detail_cell_count() >= 85
		and operation_map.get_floor_detail_cell_count() <= 140
		and operation_map.get_room_signature_count() == 35,
		"sparse floor variation plus at least two authored signatures dress every room"
	)
	var signatures_match_profiles := true
	for room_id: StringName in ENVIRONMENT_CATALOG.ROOM_ART:
		var room_rect := operation_map.get_room_rect(room_id)
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART[room_id]
		var signature_cells: Array = profile.get(&"signature_cells", [])
		var seen_signature_cells: Dictionary[Vector2i, bool] = {}
		if signature_cells.size() < 2:
			signatures_match_profiles = false
		for local_variant: Variant in signature_cells:
			var local_cell := local_variant as Vector2i
			seen_signature_cells[local_cell] = true
			signatures_match_profiles = (
				signatures_match_profiles
				and operation_map.floor_details.get_cell_atlas_coords(
					room_rect.position + local_cell
				) == ENVIRONMENT_CATALOG.ROOM_SIGNATURE_TILES[room_id]
			)
		if seen_signature_cells.size() != signature_cells.size():
			signatures_match_profiles = false
	_check(
		signatures_match_profiles,
		"every room places at least two unique signature cells from its own profile"
	)
	_check(
		operation_map.get_visible_wall_art_cell_count() > 0
		and operation_map.get_visible_wall_art_cell_count()
		< operation_map.walls.get_used_cells().size(),
		"visible reinforced walls stop at a two-cell depth ring while collision remains complete"
	)
	var visible_wall_cells_are_bounded := true
	for wall_cell: Vector2i in operation_map.wall_art.get_used_cells():
		var near_walkable := false
		for offset_x: int in range(-2, 3):
			for offset_y: int in range(-2, 3):
				var distance := absi(offset_x) + absi(offset_y)
				if distance >= 1 and distance <= 2:
					near_walkable = (
						near_walkable
						or operation_map.is_walkable_cell(
							wall_cell + Vector2i(offset_x, offset_y)
						)
					)
		visible_wall_cells_are_bounded = (
			visible_wall_cells_are_bounded
			and not operation_map.is_walkable_cell(wall_cell)
			and near_walkable
		)
	var boundary_walls_have_art := true
	for wall_cell: Vector2i in operation_map.walls.get_used_cells():
		var touches_walkable := false
		for direction: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			touches_walkable = (
				touches_walkable
				or operation_map.is_walkable_cell(wall_cell + direction)
			)
		if touches_walkable and operation_map.wall_art.get_cell_source_id(wall_cell) < 0:
			boundary_walls_have_art = false
	_check(
		visible_wall_cells_are_bounded and boundary_walls_have_art,
		"wall art covers every walkable boundary and never exceeds the two-cell depth contract"
	)
	var vault_signature_complete := true
	for local_y: int in range(3):
		for local_x: int in range(3):
			vault_signature_complete = (
				vault_signature_complete
				and operation_map.floor_details.get_cell_atlas_coords(
					Vector2i(57 + local_x, 7 + local_y)
				) == Vector2i(local_x + local_y * 3, 8)
			)
	_check(
		vault_signature_complete,
		"Chronos Vault receives a deterministic nine-tile signature circuit beneath the Core"
	)
	_check(
		operation_map.get_room_material_family(&"external_infiltration_yard") == &"yard"
		and operation_map.get_room_material_family(&"cctv_control_room") == &"systems"
		and operation_map.get_room_material_family(&"research_laboratory") == &"research"
		and operation_map.get_room_material_family(&"chronos_vault") == &"vault",
		"major mission zones resolve to distinct authored material families"
	)
	_test_environment_presentation(operation_map)
	_test_exact_door_geometry(operation)
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


func _test_environment_presentation(operation_map: OperationBlackMinuteMap) -> void:
	var presenter := operation_map.environment_presenter
	_check(
		presenter != null
		and presenter.get_room_profile_count() == 15
		and presenter.get_room_hero_cell_count() == 30
		and presenter.get_active_animation_count() == 15,
		"one pausable presenter supplies a two-tile hero, practical light, and deterministic motion to all 15 rooms"
	)
	var room_assets_match_profiles := true
	presenter.set_presentation_time_for_capture(0.0)
	var first_animation_tiles: Dictionary[StringName, Vector2i] = {}
	for room_id: StringName in ENVIRONMENT_CATALOG.ROOM_ART:
		var room_rect := operation_map.get_room_rect(room_id)
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART[room_id]
		var hero_origin: Vector2i = profile[&"hero_origin"]
		var hero_tiles: Array = ENVIRONMENT_CATALOG.ROOM_HERO_TILES[room_id]
		room_assets_match_profiles = (
			room_assets_match_profiles
			and presenter.hero_details.get_cell_atlas_coords(room_rect.position + hero_origin)
			== hero_tiles[0]
			and presenter.hero_details.get_cell_atlas_coords(
				room_rect.position + hero_origin + Vector2i.RIGHT
			) == hero_tiles[1]
		)
		var first_tile := presenter.get_room_animation_tile(room_id)
		first_animation_tiles[room_id] = first_tile
		room_assets_match_profiles = (
			room_assets_match_profiles
			and first_tile in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[room_id]
		)
	presenter.set_presentation_time_for_capture(1.0 / 6.0 + 0.001)
	for room_id: StringName in ENVIRONMENT_CATALOG.ROOM_ART:
		var next_tile := presenter.get_room_animation_tile(room_id)
		room_assets_match_profiles = (
			room_assets_match_profiles
			and next_tile in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[room_id]
			and next_tile != first_animation_tiles[room_id]
		)
	_check(
		room_assets_match_profiles,
		"every room uses its own visible hero and advances its own deterministic animation frame"
	)
	_check(
		presenter.find_children("*", "PointLight2D", true, false).is_empty(),
		"room practical lighting uses clipped painted pools without information-leaking lights"
	)
	var initial_cctv := presenter.get_room_animation_tile(&"cctv_control_room")
	_check(
		initial_cctv in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[&"cctv_control_room"],
		"online CCTV presentation begins on a deterministic monitor frame"
	)
	operation_map.set_security_visual_state(false, true, 0)
	_check(
		presenter.get_room_animation_tile(&"cctv_control_room")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"cctv_offline"],
		"CCTV shutdown replaces the moving feed with an explicit offline frame"
	)
	operation_map.set_security_visual_state(true, false, 0)
	_check(
		presenter.get_room_animation_tile(&"electrical_room")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"laser_offline"]
		and presenter.get_room_animation_tile(&"laser_corridor")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"laser_offline"],
		"laser shutdown synchronizes Electrical and corridor presentation"
	)
	operation_map.set_security_visual_state(true, true, 2)
	_check(
		presenter.get_room_animation_tile(&"security_office")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"security_alert"]
		and presenter.get_room_animation_tile(&"vault_antechamber")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"security_alert"],
		"facility alert drives matching non-color warning shapes in secure rooms"
	)
	operation_map.set_core_visual_state(true)
	_check(
		presenter.get_room_animation_tile(&"chronos_vault")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"vault_stolen"]
		and presenter.get_room_animation_tile(&"extraction_route")
		== ENVIRONMENT_CATALOG.STATE_TILES[&"extraction_active"],
		"Core theft shuts down the Vault circuit and activates extraction runway art"
	)
	presenter.set_presentation_time_for_capture(1.0)
	_check(
		presenter.get_presentation_tick() == 6,
		"environment presentation exposes a deterministic six-Hz capture clock"
	)
	operation_map.reset_environment_presentation()
	_check(
		presenter.get_presentation_tick() == 0
		and presenter.get_active_animation_count() == 15
		and presenter.get_room_animation_tile(&"cctv_control_room")
		in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[&"cctv_control_room"],
		"mission reset restores the initial environment phase and online state"
	)


func _test_exact_door_geometry(operation: OperationBlackMinuteLevel) -> void:
	var portal_geometry: Dictionary[StringName, Dictionary] = {}
	for portal_variant: Variant in operation.get_blueprint().get("dynamic_portals", []):
		var portal := portal_variant as Dictionary
		var span := portal.get("span_rect", []) as Array
		var length := float(maxi(int(span[2]), int(span[3])) * 32)
		portal_geometry[StringName(str(portal.get("id", "")))] = {
			"length": length,
			"rotation": PI * 0.5 if int(span[2]) > int(span[3]) else 0.0,
		}
	var validated_count := 0
	for child: Node in operation.get_node("DynamicObjects").get_children():
		if not child is AccessDoor:
			continue
		var door := child as AccessDoor
		var expected: Dictionary = portal_geometry.get(door.object_id, {})
		var expected_length: float = float(expected.get("length", 0.0))
		var blocker_size := door.get_blocker_size()
		var interaction_size := door.get_interaction_size()
		var occluder_size := door.get_occluder_size()
		if (
			expected_length > 0.0
			and door.scale.is_equal_approx(Vector2.ONE)
			and is_equal_approx(door.rotation, float(expected.get("rotation", -1.0)))
			and is_equal_approx(door.get_span_length_pixels(), expected_length)
			and blocker_size.is_equal_approx(Vector2(32.0, expected_length))
			and interaction_size.is_equal_approx(Vector2(58.0, expected_length + 16.0))
			and occluder_size.is_equal_approx(Vector2(32.0, expected_length))
		):
			validated_count += 1
	_check(
		validated_count == portal_geometry.size(),
		"every access door uses exact rotation, interaction, blocker, and occluder geometry"
	)


func _test_modal_pause_freeze(operation: OperationBlackMinuteLevel) -> void:
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var director: MissionDirector = operation.get_node("Systems/MissionDirector")
	var map_overlay: FacilityMapOverlay = operation.get_node("FacilityMapOverlay")
	var hud: HeistHUD = operation.get_node("HeistHUD")
	var player := operation.get_player()
	var terminal := registry.get_object(&"terminal_staff_intel_01") as HackTerminal
	var capture_recall_button := hud.get_node("%CaptureRecallButton") as Button
	var environment_presenter := operation.operation_map.environment_presenter

	_check(terminal.interact(player), "pause regression starts a real in-progress terminal hack")
	var map_pause_world_time := recall.get_world_time()
	var map_pause_hack_time := terminal.hack_elapsed
	var active_presentation_tick := environment_presenter.get_presentation_tick()
	await _tree.create_timer(0.20, true).timeout
	_check(
		environment_presenter.get_presentation_tick() > active_presentation_tick,
		"environment presentation advances on its fixed clock before pause"
	)
	map_pause_world_time = recall.get_world_time()
	map_pause_hack_time = terminal.hack_elapsed
	var map_pause_presentation_tick := environment_presenter.get_presentation_tick()
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
	await _tree.create_timer(0.20, true).timeout
	_check(
		is_equal_approx(recall.get_world_time(), map_pause_world_time)
		and is_equal_approx(terminal.hack_elapsed, map_pause_hack_time)
		and environment_presenter.get_presentation_tick() == map_pause_presentation_tick,
		"map pause advances neither Chrono history, terminal hack, nor environment phase"
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
		and operation.performance_tracker.get_capture_count() == 1
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
		and not hud.capture_panel.visible
		and operation.performance_tracker.get_capture_count() == 1,
		"Recall resolves capture while preserving the accepted capture in the attempt ledger"
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
	_check(
		not _tree.paused
		and operation.performance_tracker.get_capture_count() == 0,
		"checkpoint recovery releases pause and resets the Recall-persistent attempt ledger"
	)
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
	_check(
		operation.operation_map.environment_presenter.get_room_animation_tile(
			&"cctv_control_room"
		) == ENVIRONMENT_CATALOG.STATE_TILES[&"cctv_offline"],
		"live CCTV shutdown signal reaches the room presentation"
	)

	var lasers := registry.get_object(&"terminal_laser_network_01") as HackTerminal
	_check(
		lasers.interact(player) and lasers.complete_hack_immediately(),
		"Player completes the electrical-room laser shutdown"
	)
	_check(not security.laser_online, "electrical terminal disables all physical laser triggers")
	_check(
		operation.operation_map.environment_presenter.get_room_animation_tile(
			&"laser_corridor"
		) == ENVIRONMENT_CATALOG.STATE_TILES[&"laser_offline"],
		"live laser shutdown signal reaches the corridor presentation"
	)

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
	_check(
		operation.operation_map.environment_presenter.get_room_animation_tile(
			&"chronos_vault"
		) == ENVIRONMENT_CATALOG.STATE_TILES[&"vault_stolen"]
		and operation.operation_map.environment_presenter.get_room_animation_tile(
			&"extraction_route"
		) == ENVIRONMENT_CATALOG.STATE_TILES[&"extraction_active"],
		"live Core theft signal updates Vault and extraction presentation"
	)
	extraction.extraction_requested.emit(player)
	_check(director.is_completed(), "returning to extraction completes the heist")
	_check(
		recall.remaining_charges == recall.maximum_charges,
		"the complete authored heist route is solvable without Chrono Recall"
	)
	var result := operation.get_last_mission_result()
	_check(
		int(result.get("total_score", 0)) == 10_000
		and result.get("grade", StringName()) == &"S"
		and int(result.get("recalls_used", -1)) == 0,
		"clean no-Recall extraction earns the transparent 10,000-point S debrief"
	)
	_check(
		result.get("authorization_route", StringName()) == &"SERVER OVERRIDE"
		and bool(result.get("cctv_disabled", false))
		and bool(result.get("lasers_disabled", false)),
		"debrief reports the actual security route and final network state"
	)
	var hud: HeistHUD = operation.get_node("HeistHUD")
	await _tree.process_frame
	_check(
		hud.victory_panel.visible,
		"successful extraction presents the operation debrief modal"
	)
	_check(
		(hud.get_node("%VictoryGrade") as Label).text == "S"
		and (hud.get_node("%RecallValue") as Label).text == "0 / 3"
		and (hud.get_node("%RouteValue") as Label).text == "SERVER OVERRIDE",
		"debrief renders grade, Recall usage, and the selected authorization route"
	)
	var bonus_text := (hud.get_node("%BonusList") as Label).text
	var victory_card := hud.get_node("%VictoryCard") as Control
	_check(
		bonus_text.contains("SHADOW")
		and bonus_text.contains("TEMPORAL DISCIPLINE")
		and bonus_text.contains("BLACKOUT")
		and victory_card.size.x <= 1280.0
		and victory_card.size.y <= 720.0,
		"debrief lists named directives and remains inside the 1280x720 reference viewport"
	)


func _test_recall_and_echo(operation: OperationBlackMinuteLevel) -> void:
	_check(operation.reset_operation(), "mission checkpoint restart rebuilds a clean operation")
	_check(
		operation.operation_map.environment_presenter.get_room_animation_tile(
			&"cctv_control_room"
		) in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[&"cctv_control_room"]
		and operation.operation_map.environment_presenter.get_room_animation_tile(
			&"chronos_vault"
		) in ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES[&"chronos_vault"],
		"mission checkpoint reset restores online room presentation through production wiring"
	)
	_check(
		operation.get_last_mission_result().is_empty()
		and not operation.performance_tracker.is_finalized(),
		"replay starts a fresh mutable performance ledger without stale debrief data"
	)
	_disable_security_simulation(operation)
	var registry: ObjectRegistry = operation.get_node("Systems/ObjectRegistry")
	var recall: ChronoRecallManager = operation.get_node("Systems/ChronoRecallManager")
	var player := operation.get_player()
	var start_position := player.global_position
	var reception := registry.get_object(&"door_reception_checkpoint_01") as AccessDoor
	operation.performance_tracker.record_detection(player.get_detection_id())

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
	_check(
		operation.performance_tracker.get_live_player_detection_count() == 1,
		"Recall never erases a live-Player detection from the persistent attempt ledger"
	)
	var hud := operation.get_node("HeistHUD") as HeistHUD
	_check(
		(hud.get_node("%TimeLabel") as Label).text == "TIME\n00:10",
		"operation HUD displays the monotonic pause-safe mission clock after Recall"
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
	if echo != null:
		var guard := (
			operation.get_node("ActorLayer/GuardContainer").get_child(0)
			as GuardController
		)
		guard.last_seen_position = echo.global_position
		guard.alert_raised.emit(echo.get_detection_id())
	_check(
		operation.performance_tracker.get_echo_detection_count() == 1,
		"an actual Guard alert records the abandoned Echo as a Paradox Decoy candidate"
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
