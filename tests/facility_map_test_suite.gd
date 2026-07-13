class_name FacilityMapTestSuite
extends Node

const FACILITY_LEVEL_SCENE: PackedScene = preload(
	"res://scenes/levels/facility_level_01.tscn"
)
const PROTOTYPE_LEVEL_SCENE: PackedScene = preload(
	"res://scenes/levels/prototype_level.tscn"
)
const TIMELINE_SCENE: PackedScene = preload(
	"res://scenes/main/timeline_manager.tscn"
)
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GHOST_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")
const SECURITY_DOOR_SCENE: PackedScene = preload(
	"res://scenes/objects/security_door.tscn"
)
const LASER_BARRIER_SCENE: PackedScene = preload(
	"res://scenes/objects/laser_barrier.tscn"
)
const SECURITY_TERMINAL_SCENE: PackedScene = preload(
	"res://scenes/objects/security_terminal.tscn"
)
const FACILITY_TILESET: TileSet = preload(
	"res://resources/tilesets/facility_tileset.tres"
)

const BLUEPRINT_PATH: String = "res://resources/maps/facility_level_01_blueprint.json"
const MAP_SIZE := Vector2i(26, 25)
const TILE_SIZE := Vector2i(32, 32)
const WORLD_SIZE := Vector2i(832, 800)
const EXPECTED_FLOOR_CELLS: int = 470
const EXPECTED_WALL_CELLS: int = 180
const EXPECTED_STATIC_VISIBILITY_TARGETS: int = 8

var _tree: SceneTree
var _expectation: Callable


func run(tree: SceneTree, expect: Callable) -> void:
	_tree = tree
	_expectation = expect
	print("[TEST] Facility 26x25 map, visibility, and reset systems")
	_test_blueprint_contract()
	_test_tileset_collision_and_occlusion()
	await _test_authored_level_contract()
	await _test_player_visibility_probe_and_door()
	await _test_visibility_controller_preserves_ai()
	await _test_laser_terminal_reset()
	await _test_level_durations_and_recording_rate()
	await _test_facility_two_loop_gameplay_acceptance()
	await _test_eight_ghost_ten_reset_stress()


func _test_blueprint_contract() -> void:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	_check(file != null, "facility blueprint JSON is available in the runtime project")
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	_check(parsed is Dictionary, "facility blueprint JSON parses as an object")
	if not parsed is Dictionary:
		return
	var blueprint := parsed as Dictionary
	_check(
		_json_vector(blueprint.get("size", [])) == Vector2i(26, 25)
		and int(blueprint.get("tile_size", 0)) == 32
		and _json_vector(blueprint.get("world_size", [])) == Vector2i(832, 800)
		and is_equal_approx(float(blueprint.get("loop_duration_seconds", 0.0)), 60.0),
		"blueprint fixes the map at 26x25, 32px tiles, 832x800, and 60 seconds"
	)
	var rooms: Dictionary = blueprint.get("rooms", {}) as Dictionary
	_check(
		rooms.size() == 10
		and _json_rect(rooms, "upper_left_control") == Rect2i(1, 1, 6, 5)
		and _json_rect(rooms, "lower_right_courtyard") == Rect2i(19, 17, 6, 7),
		"blueprint preserves all ten reference-derived room zones"
	)
	var dynamic_portals: Array = blueprint.get("dynamic_portals", []) as Array
	_check(
		dynamic_portals.size() == 2
		and _json_vector(dynamic_portals[0].get("anchor", [])) == Vector2i(7, 3)
		and bool(dynamic_portals[0].get("blocks_movement", false))
		and _json_vector(dynamic_portals[1].get("anchor", [])) == Vector2i(19, 11)
		and not bool(dynamic_portals[1].get("blocks_movement", true))
		and bool(dynamic_portals[1].get("triggers_loop_end", false)),
		"blueprint anchors the vault door and laser portal at stable cells"
	)
	var objects: Dictionary = blueprint.get("objects", {}) as Dictionary
	_check(
		_json_object_position(objects, "player_spawn") == Vector2i(24, 23)
		and _json_object_position(objects, "plate_vault_01") == Vector2i(4, 21)
		and _json_object_position(objects, "objective_core_01") == Vector2i(3, 3)
		and _json_object_position(objects, "exit_courtyard_01") == Vector2i(23, 21),
		"blueprint gameplay anchors match the intended two-loop route"
	)


func _test_tileset_collision_and_occlusion() -> void:
	_check(
		FACILITY_TILESET.tile_size == TILE_SIZE,
		"facility TileSet keeps the authored 32x32 logical grid"
	)
	_check(
		FACILITY_TILESET.get_physics_layers_count() == 1
		and FACILITY_TILESET.get_physics_layer_collision_layer(0) == 65,
		"solid tiles block gameplay collision and PlayerVisibility on layers 1 and 7"
	)
	_check(
		FACILITY_TILESET.get_occlusion_layers_count() == 1
		and FACILITY_TILESET.get_occlusion_layer_light_mask(0) == 1,
		"facility TileSet defines one matching light-occlusion layer"
	)
	var atlas := FACILITY_TILESET.get_source(0) as TileSetAtlasSource
	var floor_data: TileData = atlas.get_tile_data(FacilityLevelMap.BASE_FLOOR, 0)
	var wall_data: TileData = atlas.get_tile_data(FacilityLevelMap.WALL, 0)
	_check(
		floor_data != null
		and floor_data.get_collision_polygons_count(0) == 0
		and floor_data.get_occluder(0) == null,
		"floor tiles remain non-solid and do not cast wall shadows"
	)
	_check(
		wall_data != null
		and wall_data.get_collision_polygons_count(0) == 1
		and wall_data.get_occluder(0) != null,
		"wall tiles carry both a full-cell collision polygon and occluder"
	)


func _test_authored_level_contract() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var level := FACILITY_LEVEL_SCENE.instantiate() as FacilityLevel01
	fixture.add_child(level)
	await _wait_physics_frames(3)
	_check(level.validate_level(), "FacilityLevel01 validates its scene and stable registry")
	_check(
		level.facility_map.get_map_size() == MAP_SIZE
		and level.facility_map.get_world_size() == WORLD_SIZE,
		"runtime map reports the exact 26x25 and 832x800 contract"
	)
	_check(
		level.facility_map.get_floor_cell_count() == EXPECTED_FLOOR_CELLS
		and level.facility_map.get_wall_cell_count() == EXPECTED_WALL_CELLS
		and EXPECTED_FLOOR_CELLS + EXPECTED_WALL_CELLS == MAP_SIZE.x * MAP_SIZE.y,
		"floor and wall layers partition all 650 map cells without gaps"
	)
	var tile_layers: int = 0
	for child: Node in level.facility_map.get_children():
		if child is TileMapLayer:
			tile_layers += 1
	_check(tile_layers == 6, "FacilityMap owns six purpose-specific TileMapLayer nodes")
	_check(_has_closed_boundary(level.facility_map), "all outer boundary cells are solid walls")
	_check(
		_count_reachable_floor(level.facility_map, Vector2i(24, 23)) == EXPECTED_FLOOR_CELLS,
		"all authored floor and dynamic-portal cells are four-way reachable from spawn"
	)

	_check(
		level.player_spawn.global_position == FacilityLevelMap.cell_to_world(Vector2i(24, 23))
		and level.security_door.global_position == FacilityLevelMap.cell_to_world(Vector2i(7, 3))
		and level.laser_barrier.global_position == FacilityLevelMap.cell_to_world(Vector2i(19, 11))
		and level.objective_item.global_position == FacilityLevelMap.cell_to_world(Vector2i(3, 3)),
		"spawn, door, laser, and objective scene nodes match blueprint cell centers"
	)
	var registry := level.get_registry()
	var guard: GuardController = level.get_guards()[0]
	_check(
		registry.get_object(&"plate_vault_01") == level.pressure_plate
		and registry.get_object(&"door_vault_01") == level.security_door
		and registry.get_object(&"terminal_laser_01") == level.security_terminal
		and registry.get_object(&"guard_center_01") == guard,
		"puzzle objects and Guard resolve through stable IDs rather than node paths"
	)
	_check(
		guard.get_patrol_point_count() == 4 and guard.has_valid_patrol_route(),
		"center Guard resolves the four-point deterministic patrol route"
	)
	var patrol_cells: Array[Vector2i] = [
		Vector2i(14, 8), Vector2i(17, 8), Vector2i(17, 15), Vector2i(14, 15),
	]
	var patrol_avoids_props := true
	for patrol_cell: Vector2i in patrol_cells:
		patrol_avoids_props = (
			patrol_avoids_props
			and level.facility_map.is_walkable_cell(patrol_cell)
			and not level.facility_map.props_above_actors.get_used_cells().has(patrol_cell)
		)
	_check(patrol_avoids_props, "Guard patrol points are walkable and do not overlap tall props")
	_check(
		level.get_camera_bounds() == Rect2(Vector2.ZERO, Vector2(WORLD_SIZE)),
		"facility camera bounds match the map world rectangle"
	)
	_check(
		level.visibility_controller.get_tracked_target_count()
		== EXPECTED_STATIC_VISIBILITY_TARGETS,
		"visibility controller caches facility objects, decoration, and one Guard once"
	)

	var player: PlayerController = level.spawn_player()
	_check(
		player != null
		and player.global_position == FacilityLevelMap.cell_to_world(Vector2i(24, 23))
		and not player.get_visibility_probe().is_query_enabled()
		and not player.vision_light.enabled,
		"facility Player spawns correctly with visibility locked during reset assembly"
	)
	player.global_position = level.security_terminal.global_position
	await _wait_physics_frames(2)
	_check(
		player._find_nearest_interactable() == null,
		"reset-locked facility visibility cannot expose an interaction prompt"
	)
	level.set_level_simulation_enabled(true)
	await _wait_physics_frames(2)
	_check(
		player != null
		and player.get_visibility_probe().is_query_enabled()
		and is_equal_approx(player.get_visibility_probe().visibility_radius, 240.0),
		"facility simulation unlock enables the configured visibility probe"
	)
	_check(
		player.player_camera.enabled
		and player.player_camera.limit_left == 0
		and player.player_camera.limit_top == 0
		and player.player_camera.limit_right == WORLD_SIZE.x
		and player.player_camera.limit_bottom == WORLD_SIZE.y
		and player.player_camera.zoom == Vector2(2.0, 2.0),
		"facility Player camera uses the authored limits and integer zoom"
	)
	_check(
		player._find_nearest_interactable() == level.security_terminal,
		"unlocked same-room terminal becomes interactable through the visibility probe"
	)
	level.set_level_simulation_enabled(false)
	_check(
		player._find_nearest_interactable() == null and not player.vision_light.enabled,
		"victory/reset simulation lock hides prompts and disables the Player light"
	)
	await _cleanup_fixture(fixture)


func _test_player_visibility_probe_and_door() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var player := PLAYER_SCENE.instantiate() as PlayerController
	fixture.add_child(player)
	player.initialize_at(Vector2.ZERO)
	player.get_visibility_probe().set_visibility_radius(160.0)
	player.get_visibility_probe().set_query_enabled(true)
	var target := Node2D.new()
	target.position = Vector2(100.0, -18.0)
	fixture.add_child(target)
	await _wait_physics_frames(2)
	var probe: PlayerVisibilityProbe = player.get_visibility_probe()
	_check(probe.is_actor_visible(target), "clear same-room target is visible inside the radius")
	target.position = Vector2(170.0, -18.0)
	_check(not probe.is_actor_visible(target), "target beyond the visibility radius remains hidden")
	target.position = Vector2(100.0, -18.0)

	var wall := _spawn_visibility_wall(fixture, Vector2(50.0, -18.0))
	await _wait_physics_frames(2)
	_check(not probe.is_actor_visible(target), "PlayerVisibility wall mask blocks a target behind a wall")
	wall.queue_free()
	await _wait_physics_frames(2)
	_check(probe.is_actor_visible(target), "removing the visibility wall reveals the target again")

	var door := SECURITY_DOOR_SCENE.instantiate() as SecurityDoor
	door.position = Vector2(50.0, -18.0)
	fixture.add_child(door)
	await _wait_physics_frames(2)
	_check(
		probe.is_actor_visible(door),
		"closed door itself is visible from the near side while remaining a blocker"
	)
	_check(
		not probe.is_actor_visible(target)
		and not door.blocker.disabled
		and door.light_occluder.visible,
		"closed security door blocks visibility, collision, and light"
	)
	door.set_open(true)
	await _wait_physics_frames(2)
	_check(
		probe.is_actor_visible(target)
		and door.blocker.disabled
		and not door.light_occluder.visible,
		"open security door permits visibility and disables collision and occlusion"
	)
	door.reset_for_loop()
	await _wait_physics_frames(2)
	_check(
		not probe.is_actor_visible(target)
		and not door.blocker.disabled
		and door.light_occluder.visible,
		"door reset deterministically restores every closed-state blocker"
	)
	await _cleanup_fixture(fixture)


func _test_visibility_controller_preserves_ai() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var level := FACILITY_LEVEL_SCENE.instantiate() as FacilityLevel01
	fixture.add_child(level)
	await _wait_physics_frames(2)
	var guard: GuardController = level.get_guards()[0]
	_check(
		is_zero_approx(guard.modulate.a)
		and guard.is_simulation_enabled()
		and guard.is_physics_processing(),
		"hiding an unseen Guard changes presentation alpha without disabling Guard AI"
	)
	var player := level.spawn_player()
	level.set_level_simulation_enabled(true)
	await _wait_physics_frames(2)
	_check(
		not level.visibility_controller.is_target_revealed(guard)
		and is_zero_approx(guard.modulate.a)
		and guard.is_simulation_enabled(),
		"distant Guard stays hidden while its deterministic simulation continues"
	)
	player.global_position = guard.global_position + Vector2(-80.0, 18.0)
	level.visibility_controller.refresh_now()
	_check(
		level.visibility_controller.is_target_revealed(guard)
		and guard.modulate.a > 0.99,
		"moving the Player into clear range reveals the cached Guard actor"
	)
	player.global_position = level.player_spawn.global_position
	level.visibility_controller.refresh_now()
	_check(
		not level.visibility_controller.is_target_revealed(guard)
		and guard.is_simulation_enabled(),
		"leaving visibility range hides the Guard again without changing gameplay state"
	)
	await _cleanup_fixture(fixture)


func _test_laser_terminal_reset() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var laser := LASER_BARRIER_SCENE.instantiate() as LaserBarrier
	var terminal := SECURITY_TERMINAL_SCENE.instantiate() as SecurityTerminal
	var actor := Node2D.new()
	actor.add_to_group(&"player_actor")
	fixture.add_child(laser)
	fixture.add_child(terminal)
	fixture.add_child(actor)
	terminal.activated.connect(
		func(_activator: Node) -> void:
			laser.set_active(false)
	)
	await _wait_physics_frames(2)
	_check(
		laser.is_active and not laser.trigger_shape.disabled and not terminal.is_activated,
		"laser and terminal begin in their authored active/inactive states"
	)
	_check(terminal.interact(actor), "live Player can activate the laser terminal")
	await _wait_physics_frames(2)
	_check(
		terminal.is_activated and not laser.is_active and laser.trigger_shape.disabled,
		"terminal activation disables the laser collision trigger"
	)
	terminal.reset_for_loop()
	laser.reset_for_loop()
	await _wait_physics_frames(2)
	_check(
		not terminal.is_activated and laser.is_active and not laser.trigger_shape.disabled,
		"loop reset restores terminal and laser state without residue"
	)
	await _cleanup_fixture(fixture)


func _test_level_durations_and_recording_rate() -> void:
	var facility_fixture := Node2D.new()
	_tree.root.add_child(facility_fixture)
	var facility := FACILITY_LEVEL_SCENE.instantiate() as FacilityLevel01
	var facility_timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	facility_fixture.add_child(facility)
	facility_fixture.add_child(facility_timeline)
	await _wait_physics_frames(2)
	_check(
		facility_timeline.configure(facility)
		and is_equal_approx(facility_timeline.loop_duration_seconds, 60.0),
		"TimelineManager adopts FacilityLevel01's 60-second loop duration"
	)
	await _cleanup_fixture(facility_fixture)

	var prototype_fixture := Node2D.new()
	_tree.root.add_child(prototype_fixture)
	var prototype := PROTOTYPE_LEVEL_SCENE.instantiate() as PrototypeLevel
	var prototype_timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	prototype_fixture.add_child(prototype)
	prototype_fixture.add_child(prototype_timeline)
	await _wait_physics_frames(2)
	_check(
		prototype_timeline.configure(prototype)
		and is_equal_approx(prototype_timeline.loop_duration_seconds, 20.0),
		"prototype level retains its 20-second loop after common-level extraction"
	)
	await _cleanup_fixture(prototype_fixture)

	var recorder_fixture := Node2D.new()
	_tree.root.add_child(recorder_fixture)
	var actor := Node2D.new()
	var recorder := ActionRecorder.new()
	recorder_fixture.add_child(actor)
	recorder_fixture.add_child(recorder)
	recorder.sample_rate_hz = 20.0
	_check(recorder.begin_recording(actor, 60.0), "60-second facility recorder starts at 20 Hz")
	recorder.capture_until(60.0)
	var recording := recorder.finish_recording(60.0, 1)
	_check(
		recording.samples.size() == 1201
		and is_equal_approx(recording.samples.back().timestamp, 60.0),
		"60 seconds at 20 Hz records 1,200 intervals plus both endpoints"
	)
	await _cleanup_fixture(recorder_fixture)


func _test_facility_two_loop_gameplay_acceptance() -> void:
	print("[TEST] Facility two-loop acceptance (Guard simulation intentionally isolated)")
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var level := FACILITY_LEVEL_SCENE.instantiate() as FacilityLevel01
	var timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	timeline.capture_feedback_seconds = 0.0
	fixture.add_child(level)
	fixture.add_child(timeline)
	await _wait_physics_frames(4)
	_check(timeline.configure(level), "facility acceptance configures the common TimelineManager")
	_check(timeline.start_session(), "facility acceptance starts loop 1 at 60 seconds")

	# This acceptance isolates map/recording/puzzle integration from Guard capture timing.
	# Guard AI behavior and reset are covered independently by GuardAITestSuite and this
	# suite's visibility/reset checks; the live route below remains authored and chronological.
	timeline.set_physics_process(false)
	_disable_guards(level)
	var loop_one_player: PlayerController = level.current_player
	var wall_start := FacilityLevelMap.cell_to_world(Vector2i(1, 1))
	loop_one_player.global_position = wall_start
	await _wait_physics_frames(2)
	var wall_collision: KinematicCollision2D = loop_one_player.move_and_collide(Vector2(-40.0, 0.0))
	_check(
		wall_collision != null and loop_one_player.global_position.x >= 40.0,
		"live Player physics collides with the solid west boundary wall"
	)

	var route_cells: Array[Vector2i] = [
		Vector2i(24, 23),
		Vector2i(20, 21),
		Vector2i(18, 20),
		Vector2i(17, 20),
		Vector2i(12, 21),
		Vector2i(8, 21),
		Vector2i(7, 21),
		Vector2i(4, 21),
	]
	var route_is_walkable: bool = true
	for cell: Vector2i in route_cells:
		route_is_walkable = route_is_walkable and level.facility_map.is_walkable_cell(cell)
	_check(route_is_walkable, "loop 1 lure route uses only authored walkable cells")
	for index: int in range(route_cells.size()):
		loop_one_player.global_position = FacilityLevelMap.cell_to_world(route_cells[index])
		timeline._physics_process(0.25)
	# Finish just beyond the exact 20 Hz boundary so the final authored plate hold is
	# represented explicitly without exercising floating-point endpoint clamping noise.
	timeline._physics_process(0.01)
	await _wait_physics_frames(3)
	_check(
		level.pressure_plate.is_active
		and level.pressure_plate.get_occupant_count() == 1
		and level.security_door.is_open,
		"loop 1 live Player physically holds the vault plate and opens the door"
	)
	timeline.request_restart()
	await _wait_for_running_loop(timeline, 2, 12)
	timeline.set_physics_process(false)
	_disable_guards(level)
	_check(
		timeline.current_loop_index == 2
		and timeline.recordings.size() == 1
		and timeline.recordings[0].is_chronological()
		and is_equal_approx(timeline.recordings[0].duration, 2.01)
		and timeline.recordings[0].samples.back().position
		== FacilityLevelMap.cell_to_world(Vector2i(4, 21)),
		"manual restart saves the chronological authored route through the plate timestamp"
	)
	_check(
		level.get_ghost_count() == 1
		and not level.pressure_plate.is_active
		and not level.security_door.is_open,
		"loop 2 begins with one Ghost and freshly reset plate and door state"
	)

	# Advancing the absolute timeline to the final recorded sample leaves the Ghost on
	# the plate; Area2D overlap, rather than a direct test call, must open the vault.
	timeline._physics_process(2.01)
	await _wait_physics_frames(4)
	_check(
		level.pressure_plate.is_active
		and level.pressure_plate.get_occupant_count() == 1
		and level.security_door.is_open
		and level.security_door.blocker.disabled,
		"loop 1 Ghost physically replays onto the plate and opens the vault door"
	)

	var loop_two_player: PlayerController = level.current_player
	loop_two_player.global_position = level.security_terminal.global_position
	await _wait_physics_frames(3)
	_send_interact(loop_two_player)
	await _wait_physics_frames(2)
	_check(
		level.security_terminal.is_activated
		and not level.laser_barrier.is_active
		and level.laser_barrier.trigger_shape.disabled,
		"loop 2 current Player interaction disables the active laser barrier"
	)

	loop_two_player.global_position = FacilityLevelMap.cell_to_world(Vector2i(8, 3))
	await _wait_physics_frames(2)
	var door_collision: KinematicCollision2D = loop_two_player.move_and_collide(Vector2(-80.0, 0.0))
	_check(
		door_collision == null and loop_two_player.global_position.x < level.security_door.global_position.x,
		"current Player physically crosses the open vault portal without collision"
	)
	loop_two_player.global_position = level.objective_item.global_position
	await _wait_physics_frames(3)
	_send_interact(loop_two_player)
	await _wait_physics_frames(2)
	_check(
		level.objective_item.is_collected
		and loop_two_player.has_objective_item()
		and level.exit_zone.is_objective_available,
		"current Player collects the objective behind the Ghost-opened door"
	)
	loop_two_player.global_position = level.exit_zone.global_position
	await _wait_physics_frames(4)
	await _wait_process_frames(3)
	_check(timeline.is_victory(), "objective-bearing Player reaches the courtyard exit and wins")

	_check(timeline.reset_timeline(), "facility timeline resets cleanly after victory")
	timeline.set_physics_process(false)
	_disable_guards(level)
	await _wait_physics_frames(4)
	var reset_guard: GuardController = level.get_guards()[0]
	_check(
		not level.pressure_plate.is_active
		and level.pressure_plate.get_occupant_count() == 0
		and not level.security_door.is_open
		and not level.security_door.blocker.disabled
		and level.security_door.light_occluder.visible
		and level.laser_barrier.is_active
		and not level.laser_barrier.trigger_shape.disabled,
		"post-victory reset restores plate, door collision/occlusion, and laser state"
	)
	_check(
		not level.security_terminal.is_activated
		and not level.objective_item.is_collected
		and level.objective_item.visible
		and level.objective_item.monitorable
		and not level.exit_zone.is_objective_available,
		"post-victory reset restores terminal, objective, and inactive exit"
	)
	_check(
		reset_guard.state == GuardController.GuardState.IDLE
		and is_zero_approx(reset_guard.get_suspicion())
		and reset_guard.get_current_target_id() == StringName()
		and reset_guard.global_position == FacilityLevelMap.cell_to_world(Vector2i(14, 8)),
		"post-victory reset restores the Guard's authored idle state and spawn"
	)
	_check(
		is_equal_approx(timeline.loop_duration_seconds, 60.0)
		and timeline.current_loop_index == 1
		and timeline.recordings.is_empty()
		and level.get_ghost_count() == 0
		and level.visibility_controller.get_tracked_target_count()
		== EXPECTED_STATIC_VISIBILITY_TARGETS
		and level.current_player.get_visibility_probe().is_query_enabled(),
		"timeline reset keeps 60 seconds while clearing recordings, Ghosts, and runtime visibility targets"
	)
	_check(
		not level.visibility_controller.is_target_revealed(level.objective_item)
		and not level.visibility_controller.is_target_revealed(reset_guard),
		"reset visibility does not leak distant objective or Guard reveal state"
	)
	await _cleanup_fixture(fixture)


func _test_eight_ghost_ten_reset_stress() -> void:
	var fixture := Node2D.new()
	_tree.root.add_child(fixture)
	var level := FACILITY_LEVEL_SCENE.instantiate() as FacilityLevel01
	fixture.add_child(level)
	await _wait_physics_frames(2)
	var reset_is_stable: bool = true
	for reset_index: int in range(10):
		level.set_level_simulation_enabled(false)
		level.clear_runtime_actors()
		level.reset_objects_for_loop()
		if not level.rebuild_and_validate_registry():
			reset_is_stable = false
			break
		for loop_index: int in range(1, 9):
			var position := level.player_spawn.global_position + Vector2(-loop_index * 4.0, 0.0)
			var samples: Array[TransformSample] = [
				TransformSample.new(0.0, position, Vector2.LEFT, &"idle", Vector2.ZERO),
				TransformSample.new(1.0, position, Vector2.LEFT, &"idle", Vector2.ZERO),
			]
			var recording := LoopRecording.new(1.0, samples, [], loop_index)
			if level.spawn_ghost(recording, loop_index) == null:
				reset_is_stable = false
				break
		if not reset_is_stable:
			break
		if level.spawn_player() == null:
			reset_is_stable = false
			break
		level.set_level_simulation_enabled(true)
		level.visibility_controller.refresh_now()
		if (
			level.get_ghost_count() != 8
			or level.visibility_controller.get_tracked_target_count()
			!= EXPECTED_STATIC_VISIBILITY_TARGETS + 8
			or level.get_guards()[0].state != GuardController.GuardState.IDLE
		):
			reset_is_stable = false
			break
	_check(
		reset_is_stable,
		"one Guard, eight Ghosts, and ten deterministic reset cycles retain stable caches"
	)
	level.set_level_simulation_enabled(false)
	level.clear_runtime_actors()
	_check(
		level.get_ghost_count() == 0
		and level.visibility_controller.get_tracked_target_count()
		== EXPECTED_STATIC_VISIBILITY_TARGETS,
		"stress cleanup removes runtime Ghost targets without leaking static registrations"
	)
	await _cleanup_fixture(fixture)


func _has_closed_boundary(map: FacilityLevelMap) -> bool:
	for x: int in range(MAP_SIZE.x):
		if not map.is_wall_cell(Vector2i(x, 0)) or not map.is_wall_cell(Vector2i(x, MAP_SIZE.y - 1)):
			return false
	for y: int in range(MAP_SIZE.y):
		if not map.is_wall_cell(Vector2i(0, y)) or not map.is_wall_cell(Vector2i(MAP_SIZE.x - 1, y)):
			return false
	return true


func _count_reachable_floor(map: FacilityLevelMap, start: Vector2i) -> int:
	if not map.is_walkable_cell(start):
		return 0
	var frontier: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var cursor: int = 0
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := cell + offset
			if visited.has(neighbor) or not map.is_walkable_cell(neighbor):
				continue
			visited[neighbor] = true
			frontier.append(neighbor)
	return visited.size()


func _spawn_visibility_wall(parent: Node, position: Vector2) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.position = position
	wall.collision_layer = PlayerVisibilityProbe.DEFAULT_VISIBILITY_BLOCKER_MASK
	wall.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8.0, 96.0)
	shape.shape = rectangle
	wall.add_child(shape)
	parent.add_child(wall)
	return wall


func _json_rect(rooms: Dictionary, room_id: String) -> Rect2i:
	var room: Dictionary = rooms.get(room_id, {}) as Dictionary
	var values: Array = room.get("rect", []) as Array
	if values.size() != 4:
		return Rect2i()
	return Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))


func _json_object_position(objects: Dictionary, object_id: String) -> Vector2i:
	var object_data: Dictionary = objects.get(object_id, {}) as Dictionary
	return _json_vector(object_data.get("position", []))


func _json_vector(values_variant: Variant) -> Vector2i:
	var values: Array = values_variant as Array
	if values == null or values.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(values[0]), int(values[1]))


func _wait_physics_frames(count: int) -> void:
	for _frame: int in range(count):
		await _tree.physics_frame
		await _tree.process_frame


func _wait_process_frames(count: int) -> void:
	for _frame: int in range(count):
		await _tree.process_frame


func _wait_for_running_loop(
	timeline: TimelineManager,
	expected_loop_index: int,
	maximum_process_frames: int
) -> void:
	for _frame: int in range(maximum_process_frames):
		if timeline.current_loop_index == expected_loop_index and timeline.is_loop_running():
			return
		await _tree.process_frame


func _send_interact(player: PlayerController) -> void:
	var interaction := InputEventAction.new()
	interaction.action = &"interact"
	interaction.pressed = true
	player._unhandled_input(interaction)


func _disable_guards(level: GameplayLevel) -> void:
	for guard: GuardController in level.get_guards():
		guard.set_simulation_enabled(false)


func _cleanup_fixture(fixture: Node) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
	await _tree.process_frame
	await _tree.physics_frame


func _check(condition: bool, description: String) -> void:
	if _expectation.is_valid():
		_expectation.call(condition, description)
