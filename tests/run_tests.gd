extends SceneTree

const SAMPLE_RATE_HZ: float = 20.0
const LOOP_DURATION_SECONDS: float = 20.0
const EXPECTED_SAMPLE_COUNT: int = 401
const FLOAT_EPSILON: float = 0.0001

const GHOST_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GUARD_SCENE: PackedScene = preload("res://scenes/enemies/guard.tscn")
const LEVEL_SCENE: PackedScene = preload("res://scenes/levels/prototype_level.tscn")
const TIMELINE_SCENE: PackedScene = preload("res://scenes/main/timeline_manager.tscn")
const PRESSURE_PLATE_SCENE: PackedScene = preload("res://scenes/objects/pressure_plate.tscn")
const SECURITY_DOOR_SCENE: PackedScene = preload("res://scenes/objects/security_door.tscn")
const OBJECTIVE_ITEM_SCENE: PackedScene = preload("res://scenes/objects/objective_item.tscn")
const EXIT_ZONE_SCENE: PackedScene = preload("res://scenes/objects/exit_zone.tscn")
const PLAYER_SPRITE_FRAMES: SpriteFrames = preload(
	"res://resources/characters/player_sprite_frames.tres"
)
const GUARD_SPRITE_FRAMES: SpriteFrames = preload(
	"res://resources/characters/guard_sprite_frames.tres"
)
const FACILITY_TILESET: TileSet = preload("res://resources/tilesets/facility_tileset.tres")

const CHARACTER_FRAME_SIZE: Vector2 = Vector2(48.0, 64.0)
const FACILITY_TILE_SIZE: Vector2i = Vector2i(32, 32)
const FACILITY_MAP_SIZE: Vector2i = Vector2i(30, 16)
const EXPECTED_FLOOR_CELL_COUNT: int = 480
const PLAYER_ATLAS_PATH: String = "res://assets/sprites/characters/player_atlas.png"
const GUARD_ATLAS_PATH: String = "res://assets/sprites/characters/guard_atlas.png"
const FACILITY_ATLAS_PATH: String = "res://assets/sprites/environment/facility_tileset.png"
const PLAYER_ANIMATION_NAMES: Array[StringName] = [
	&"idle_down",
	&"idle_left",
	&"idle_right",
	&"idle_up",
	&"walk_down",
	&"walk_left",
	&"walk_right",
	&"walk_up",
	&"interact_down",
	&"interact_left",
	&"interact_right",
	&"interact_up",
]
const GUARD_ANIMATION_NAMES: Array[StringName] = [
	&"idle_down",
	&"idle_left",
	&"idle_right",
	&"idle_up",
	&"walk_down",
	&"walk_left",
	&"walk_right",
	&"walk_up",
	&"alert_down",
	&"alert_left",
	&"alert_right",
	&"alert_up",
]

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
	_test_character_sprite_frame_resources()
	await _test_player_visual_states()
	await _test_ghost_visual_replay()
	await _test_guard_visual_states_and_reset()
	await _test_guard_ai_systems()
	await _test_facility_tileset_and_map()
	await _test_facility_level_01_systems()
	_test_recording_sampling_and_timestamps()
	_test_recording_deep_copy_isolation()
	await _test_ghost_interpolation_boundaries()
	await _test_discrete_event_order_and_exactly_once()
	await _test_registry_validation_and_missing_target()
	await _test_resettable_gameplay_objects()
	await _test_pause_restart_and_victory_priority()
	await _test_capture_timeline_protocol()
	await _test_two_loop_stealth_distraction_acceptance()
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


func _test_character_sprite_frame_resources() -> void:
	print("[TEST] Character SpriteFrames resources")
	_test_sprite_frames_contract(
		PLAYER_SPRITE_FRAMES,
		PLAYER_ANIMATION_NAMES,
		PLAYER_ATLAS_PATH,
		"Player"
	)
	_test_sprite_frames_contract(
		GUARD_SPRITE_FRAMES,
		GUARD_ANIMATION_NAMES,
		GUARD_ATLAS_PATH,
		"Guard"
	)


func _test_sprite_frames_contract(
	sprite_frames: SpriteFrames,
	expected_animations: Array[StringName],
	expected_atlas_path: String,
	actor_label: String
) -> void:
	var actual_animation_names: PackedStringArray = sprite_frames.get_animation_names()
	_expect(
		actual_animation_names.size() == expected_animations.size(),
		"%s SpriteFrames contains exactly the required 12 animations" % actor_label
	)
	for animation_name: StringName in expected_animations:
		var has_animation: bool = sprite_frames.has_animation(animation_name)
		_expect(
			has_animation,
			"%s SpriteFrames contains '%s'" % [actor_label, animation_name]
		)
		if not has_animation:
			continue
		_expect(
			sprite_frames.get_animation_speed(animation_name) > 0.0,
			"%s animation '%s' has a positive FPS" % [actor_label, animation_name]
		)
		var frame_count: int = sprite_frames.get_frame_count(animation_name)
		_expect(
			frame_count > 0,
			"%s animation '%s' contains at least one frame" % [actor_label, animation_name]
		)
		for frame_index: int in range(frame_count):
			var frame_texture: Texture2D = sprite_frames.get_frame_texture(
				animation_name,
				frame_index
			)
			var is_atlas_texture: bool = frame_texture is AtlasTexture
			_expect(
				is_atlas_texture,
				"%s animation '%s' frame %d uses an AtlasTexture"
				% [actor_label, animation_name, frame_index]
			)
			if not is_atlas_texture:
				continue
			var atlas_texture := frame_texture as AtlasTexture
			_expect(
				atlas_texture.region.size == CHARACTER_FRAME_SIZE,
				"%s animation '%s' frame %d has a 48x64 region"
				% [actor_label, animation_name, frame_index]
			)
			var runtime_path: String = ""
			if atlas_texture.atlas != null:
				runtime_path = atlas_texture.atlas.resource_path
			_expect(
				runtime_path == expected_atlas_path,
				"%s animation '%s' frame %d references only the runtime atlas"
				% [actor_label, animation_name, frame_index]
			)


func _test_player_visual_states() -> void:
	print("[TEST] Player four-direction visual states")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var player := PLAYER_SCENE.instantiate() as PlayerController
	_expect(player != null, "Player scene instantiates as PlayerController")
	if player == null:
		fixture.free()
		await process_frame
		return
	fixture.add_child(player)
	player.set_physics_process(false)
	var visual: PlayerVisual = player.get_visual()
	var directions: Array[Vector2] = [
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2.UP,
	]
	var direction_names: Array[String] = ["down", "left", "right", "up"]
	for index: int in range(directions.size()):
		var direction: Vector2 = directions[index]
		var direction_name: String = direction_names[index]
		var idle_animation := StringName("idle_%s" % direction_name)
		var walk_animation := StringName("walk_%s" % direction_name)
		var interact_animation := StringName("interact_%s" % direction_name)
		visual.reset_visual(direction)
		visual.update_motion(direction, Vector2.ZERO, &"idle")
		_expect(
			visual.get_current_animation() == idle_animation,
			"Player selects %s while stationary" % idle_animation
		)
		visual.update_motion(direction, direction * 20.0, &"moving")
		_expect(
			visual.get_current_animation() == walk_animation,
			"Player selects %s while moving" % walk_animation
		)
		visual.play_interaction()
		_expect(
			visual.get_current_animation() == interact_animation and visual.is_interacting(),
			"Player selects %s during interaction" % interact_animation
		)
		visual.animated_sprite.animation_finished.emit()
		_expect(
			visual.get_current_animation() == walk_animation and not visual.is_interacting(),
			"Player returns to %s after interaction" % walk_animation
		)
		visual.reset_visual(direction)
		_expect(
			visual.get_current_animation() == idle_animation
			and visual.animated_sprite.frame == 0
			and not visual.is_interacting(),
			"Player visual reset restores %s at frame zero" % idle_animation
		)
	_expect(
		not visual.objective_indicator.visible,
		"Player visual reset hides the objective indicator"
	)
	var restart_count := {"value": 0}
	player.restart_requested.connect(
		func() -> void:
			restart_count["value"] = int(restart_count["value"]) + 1
	)
	player.set_gameplay_input_enabled(true)
	var repeated_restart := InputEventKey.new()
	repeated_restart.physical_keycode = KEY_R
	repeated_restart.pressed = true
	repeated_restart.echo = true
	player._unhandled_input(repeated_restart)
	_expect(
		int(restart_count["value"]) == 0,
		"Player ignores browser key-repeat restart events"
	)
	fixture.free()
	await process_frame


func _test_ghost_visual_replay() -> void:
	print("[TEST] Ghost shared visual replay state")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var registry := ObjectRegistry.new()
	var target := ReplayTarget.new()
	var player := PLAYER_SCENE.instantiate() as PlayerController
	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	fixture.add_child(registry)
	fixture.add_child(target)
	fixture.add_child(player)
	fixture.add_child(ghost)
	player.set_physics_process(false)
	_expect(
		registry.register_object(&"ghost_visual_target", target),
		"Ghost visual event target registers by stable ID"
	)
	var player_visual: PlayerVisual = player.get_visual()
	var ghost_visual: PlayerVisual = ghost.get_visual()
	_expect(
		ghost_visual.get_sprite_frames() == player_visual.get_sprite_frames()
		and ghost_visual.get_sprite_frames() == PLAYER_SPRITE_FRAMES,
		"Ghost reuses the exact Player SpriteFrames resource"
	)
	_expect(
		_is_equal(ghost_visual.modulate.a, 0.52),
		"Ghost visual uses the authored 0.52 alpha"
	)

	var samples: Array[TransformSample] = [
		TransformSample.new(0.0, Vector2.ZERO, Vector2.DOWN, &"idle", Vector2.ZERO),
		TransformSample.new(
			1.0,
			Vector2(40.0, 0.0),
			Vector2.RIGHT,
			&"moving",
			Vector2(40.0, 0.0)
		),
		TransformSample.new(2.0, Vector2(40.0, -20.0), Vector2.UP, &"idle", Vector2.ZERO),
	]
	var events: Array[RecordedEvent] = [
		RecordedEvent.new(1.5, &"ghost_visual_target", &"interact", {"order": 1}),
	]
	var recording := LoopRecording.new(2.0, samples, events, 1)
	_expect(ghost.configure(recording, registry, 1), "Ghost accepts visual replay samples")
	ghost.advance_to(0.0)
	_expect(
		ghost_visual.get_current_animation() == &"idle_down",
		"Ghost begins with the recorded down-facing idle"
	)
	ghost.advance_to(1.0)
	_expect(
		ghost_visual.get_current_animation() == &"walk_right",
		"Ghost uses recorded velocity and facing for walk_right"
	)
	_expect(
		_is_equal(ghost_visual.rotation, 0.0),
		"Ghost VisualRoot stays unrotated while facing right"
	)
	ghost.advance_to(1.5)
	_expect(
		ghost_visual.get_current_animation() == &"interact_right"
		and ghost_visual.is_interacting(),
		"Ghost interaction event triggers the directional interaction visual"
	)
	ghost_visual.animated_sprite.animation_finished.emit()
	_expect(
		ghost_visual.get_current_animation() == &"idle_right"
		and not ghost_visual.is_interacting(),
		"Ghost returns from interaction to its recorded motion state"
	)
	ghost.advance_to(2.0)
	_expect(
		ghost_visual.get_current_animation() == &"idle_up",
		"Ghost ends with the recorded up-facing idle"
	)
	_expect(
		_is_equal(ghost_visual.rotation, 0.0),
		"Ghost VisualRoot never rotates with recorded facing"
	)
	ghost.reset_playback()
	_expect(
		_is_equal(ghost.playback_time, 0.0)
		and ghost_visual.get_current_animation() == &"idle_down"
		and ghost_visual.animated_sprite.frame == 0
		and not ghost_visual.is_interacting(),
		"Ghost reset rewinds playback and restores its initial visual frame"
	)
	fixture.free()
	await process_frame


func _test_guard_visual_states_and_reset() -> void:
	print("[TEST] Guard four-direction visual states and reset")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var guard := GUARD_SCENE.instantiate() as GuardController
	_expect(guard != null, "Guard scene instantiates as GuardController")
	if guard == null:
		fixture.free()
		await process_frame
		return
	fixture.add_child(guard)
	guard.set_physics_process(false)
	var visual: GuardVisual = guard.get_visual()
	var directions: Array[Vector2] = [
		Vector2.DOWN,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2.UP,
	]
	var direction_names: Array[String] = ["down", "left", "right", "up"]
	for index: int in range(directions.size()):
		var direction: Vector2 = directions[index]
		var direction_name: String = direction_names[index]
		var idle_animation := StringName("idle_%s" % direction_name)
		var walk_animation := StringName("walk_%s" % direction_name)
		var alert_animation := StringName("alert_%s" % direction_name)
		visual.update_state(direction, Vector2.ZERO, &"idle", 0.0)
		_expect(
			visual.get_current_animation() == idle_animation,
			"Guard selects %s while stationary" % idle_animation
		)
		visual.update_state(direction, direction * 20.0, &"patrol", 0.0)
		_expect(
			visual.get_current_animation() == walk_animation,
			"Guard selects %s while patrolling" % walk_animation
		)
		visual.update_state(direction, Vector2.ZERO, &"chase", 1.0)
		_expect(
			visual.get_current_animation() == alert_animation
			and visual.is_alerted()
			and visual.alert_indicator.visible,
			"Guard selects %s and shows a non-color alert indicator" % alert_animation
		)

	var initial_position: Vector2 = guard.position
	guard.position += Vector2(25.0, 12.0)
	guard.velocity = Vector2.RIGHT * 20.0
	guard.transition_to(GuardController.GuardState.CHASE)
	guard.reset_for_loop()
	_expect(
		guard.state == GuardController.GuardState.IDLE
		and guard.position.is_equal_approx(initial_position)
		and guard.velocity.is_zero_approx(),
		"Guard reset restores idle state, position, and zero velocity"
	)
	_expect(
		visual.get_current_animation() == &"idle_right"
		and visual.animated_sprite.frame == 0
		and not visual.is_alerted()
		and not visual.alert_indicator.visible,
		"Guard reset restores authored facing idle and hides alert feedback"
	)
	fixture.free()
	await process_frame


func _test_guard_ai_systems() -> void:
	var suite := GuardAITestSuite.new()
	root.add_child(suite)
	await suite.run(self, Callable(self, &"_expect"))
	suite.free()
	await process_frame


func _test_facility_level_01_systems() -> void:
	var suite := FacilityMapTestSuite.new()
	root.add_child(suite)
	await suite.run(self, Callable(self, &"_expect"))
	suite.free()
	await process_frame


func _test_facility_tileset_and_map() -> void:
	print("[TEST] Facility TileSet and 30x16 tutorial map")
	_expect(FACILITY_TILESET.tile_size == FACILITY_TILE_SIZE, "Facility TileSet uses 32x32 tiles")
	_expect(
		FACILITY_TILESET.get_physics_layers_count() > 0,
		"Facility TileSet defines a physics layer for solid tiles"
	)
	var atlas_source := FACILITY_TILESET.get_source(0) as TileSetAtlasSource
	_expect(atlas_source != null, "Facility TileSet contains its atlas source")
	if atlas_source != null:
		var atlas_path: String = ""
		if atlas_source.texture != null:
			atlas_path = atlas_source.texture.resource_path
		_expect(
			atlas_path == FACILITY_ATLAS_PATH,
			"Facility TileSet references only the runtime atlas"
		)
		var floor_data: TileData = atlas_source.get_tile_data(Vector2i(7, 3), 0)
		_expect(floor_data != null, "Facility TileSet contains the runtime floor tile")
		if floor_data != null:
			_expect(
				floor_data.get_collision_polygons_count(0) == 0,
				"Facility floor tile has no collision polygon"
			)
		var wall_data: TileData = atlas_source.get_tile_data(Vector2i(0, 2), 0)
		_expect(wall_data != null, "Facility TileSet contains the runtime wall tile")
		if wall_data != null:
			_expect(
				wall_data.get_collision_polygons_count(0) > 0,
				"Facility wall tile has collision geometry"
			)

	var fixture := Node2D.new()
	root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	fixture.add_child(level)
	await process_frame
	var facility_map := level.get_node_or_null(^"FacilityMap") as FacilityMapPresenter
	_expect(facility_map != null, "Tutorial level contains the FacilityMap presenter")
	if facility_map == null:
		fixture.free()
		await process_frame
		return
	_expect(facility_map.get_map_size() == FACILITY_MAP_SIZE, "FacilityMap is exactly 30x16 tiles")
	_expect(
		facility_map.get_used_floor_cell_count() == EXPECTED_FLOOR_CELL_COUNT,
		"FacilityMap fills all 480 floor cells"
	)
	_expect(
		facility_map.floor_tiles.get_used_rect().size == FACILITY_MAP_SIZE,
		"Facility floor used rectangle matches the authored map size"
	)

	var map_pixel_size := Vector2(FACILITY_MAP_SIZE * FACILITY_TILE_SIZE)
	var map_bounds := Rect2(facility_map.global_position, map_pixel_size)
	var core_objects: Array[Node2D] = [
		level.player_spawn,
		level.pressure_plate,
		level.security_door,
		level.objective_item,
		level.exit_zone,
	]
	for core_object: Node2D in core_objects:
		_expect(
			map_bounds.has_point(core_object.global_position),
			"Tutorial core object '%s' stays inside FacilityMap bounds" % core_object.name
		)

	var divider_top_shape := level.get_node_or_null(
		^"Environment/DividerTop/CollisionShape2D"
	) as CollisionShape2D
	var divider_bottom_shape := level.get_node_or_null(
		^"Environment/DividerBottom/CollisionShape2D"
	) as CollisionShape2D
	var door_shape: CollisionShape2D = level.security_door.blocker
	var divider_top_rectangle := (
		divider_top_shape.shape as RectangleShape2D if divider_top_shape != null else null
	)
	var divider_bottom_rectangle := (
		divider_bottom_shape.shape as RectangleShape2D if divider_bottom_shape != null else null
	)
	var door_rectangle := door_shape.shape as RectangleShape2D if door_shape != null else null
	_expect(
		divider_top_rectangle != null
		and divider_bottom_rectangle != null
		and door_rectangle != null,
		"Tutorial divider and security door use inspectable rectangle collision shapes"
	)
	if (
		divider_top_rectangle != null
		and divider_bottom_rectangle != null
		and door_rectangle != null
	):
		var top_divider_end: float = (
			divider_top_shape.global_position.y + divider_top_rectangle.size.y * 0.5
		)
		var door_start: float = door_shape.global_position.y - door_rectangle.size.y * 0.5
		var door_end: float = door_shape.global_position.y + door_rectangle.size.y * 0.5
		var bottom_divider_start: float = (
			divider_bottom_shape.global_position.y - divider_bottom_rectangle.size.y * 0.5
		)
		_expect(
			absf(divider_top_shape.global_position.x - door_shape.global_position.x)
			<= FLOAT_EPSILON
			and absf(divider_bottom_shape.global_position.x - door_shape.global_position.x)
			<= FLOAT_EPSILON
			and door_rectangle.size.x >= divider_top_rectangle.size.x
			and door_rectangle.size.x >= divider_bottom_rectangle.size.x
			and door_start <= top_divider_end + FLOAT_EPSILON
			and door_end + FLOAT_EPSILON >= bottom_divider_start,
			"Closed door collision seals the divider without side or vertical gaps"
		)

	var floor_before: PackedStringArray = _capture_tile_layer(facility_map.floor_tiles)
	var details_before: PackedStringArray = _capture_tile_layer(facility_map.detail_tiles)
	var walls_before: PackedStringArray = _capture_tile_layer(facility_map.wall_art_tiles)
	level.reset_objects_for_loop()
	await process_frame
	_expect(
		floor_before == _capture_tile_layer(facility_map.floor_tiles)
		and details_before == _capture_tile_layer(facility_map.detail_tiles)
		and walls_before == _capture_tile_layer(facility_map.wall_art_tiles),
		"Loop reset leaves all authored FacilityMap tile layers unchanged"
	)
	fixture.free()
	await process_frame


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
	var endpoint_drift_recording := LoopRecording.new(
		1.0,
		[TransformSample.new(1.0 + LoopRecording.TIMESTAMP_EPSILON * 0.5)],
		[],
		1
	)
	_expect(
		_is_equal(endpoint_drift_recording.samples[0].timestamp, 1.0),
		"sub-epsilon endpoint drift clamps silently to the recording duration"
	)
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

	var moving_terminal_samples: Array[TransformSample] = [
		TransformSample.new(
			0.0,
			Vector2.ZERO,
			Vector2.RIGHT,
			&"moving",
			Vector2(30.0, 0.0)
		),
		TransformSample.new(
			1.0,
			Vector2(-24.0, 12.0),
			Vector2.LEFT,
			&"moving",
			Vector2(-30.0, 0.0)
		),
	]
	var moving_terminal_recording := LoopRecording.new(1.0, moving_terminal_samples, [], 2)
	ghost.configure(moving_terminal_recording, null, 2)
	ghost.advance_to(1.0)
	ghost.advance_to(9.0)
	_expect(
		ghost.global_position.is_equal_approx(Vector2(-24.0, 12.0))
		and ghost.playback_velocity.is_zero_approx()
		and ghost.get_visual().get_current_animation() == &"idle_left",
		"moving terminal samples hold their final position with zero velocity and directional idle"
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
	var guard := GUARD_SCENE.instantiate() as GuardController
	var actor := Node2D.new()
	actor.add_to_group(&"player_actor")
	fixture.add_child(plate)
	fixture.add_child(door)
	fixture.add_child(objective)
	fixture.add_child(exit_zone)
	fixture.add_child(guard)
	fixture.add_child(actor)
	guard.set_simulation_enabled(false)

	plate.body_entered.emit(actor)
	_expect(plate.is_active and plate.get_occupant_count() == 1, "pressure plate tracks occupying actors")
	plate.reset_for_loop()
	_expect(not plate.is_active and plate.get_occupant_count() == 0, "pressure plate reset clears occupancy")

	door.set_open(true)
	_expect(
		not door.is_open and not door.blocker.disabled and door.light_occluder.visible,
		"door keeps collision, LOS, and light state coherent until its deferred commit"
	)
	await process_frame
	_expect(door.is_open and door.blocker.disabled, "door opens and disables its blocker")
	door.reset_for_loop()
	await process_frame
	_expect(not door.is_open and not door.blocker.disabled, "door reset restores the closed blocker")
	door.set_open(true)
	await _wait_physics_frames(2)
	guard.global_position = door.global_position
	await _wait_physics_frames(2)
	door.set_open(false)
	await _wait_physics_frames(2)
	_expect(
		door.is_open and door.blocker.disabled,
		"door defers closing while the Guard occupies its clearance"
	)
	guard.global_position = door.global_position + Vector2(120.0, 0.0)
	await _wait_physics_frames(3)
	_expect(
		not door.is_open and not door.blocker.disabled,
		"door closes after the Guard leaves its clearance"
	)

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
	_expect(
		not level.training_guard.is_simulation_enabled(),
		"victory freezes Guard AI simulation with the timeline"
	)
	fixture.free()
	await process_frame


func _test_capture_timeline_protocol() -> void:
	print("[TEST] Capture recording, priority, and stale-transition protocol")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	var timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	timeline.capture_feedback_seconds = 0.0
	fixture.add_child(level)
	fixture.add_child(timeline)
	await process_frame
	var ended_reasons: Array[StringName] = []
	timeline.loop_ended.connect(
		func(_loop_index: int, reason: StringName) -> void:
			ended_reasons.append(reason)
	)
	_expect(timeline.configure(level), "capture fixture configures the tutorial level")
	_expect(timeline.start_session(), "capture fixture starts loop 1")
	timeline._physics_process(0.35)
	var captured_player: PlayerController = level.current_player
	level.player_captured.emit(captured_player)
	timeline.request_loop_end(TimelineManager.REASON_TIMEOUT)
	timeline.request_loop_end(TimelineManager.REASON_RESTART)
	await _wait_process_frames(2)
	_expect(
		timeline.current_loop_index == 2
		and timeline.is_loop_running()
		and timeline.recordings.size() == 1
		and level.get_ghost_count() == 1,
		"captured loop is saved once and spawns one Ghost in the next loop"
	)
	_expect(
		ended_reasons == [TimelineManager.REASON_CAPTURED],
		"captured reason beats simultaneous restart and timeout requests"
	)
	_expect(
		_is_equal(timeline.recordings[0].duration, 0.35),
		"capture finalizes the recording at the capture timestamp"
	)

	level.player_captured.emit(level.current_player)
	timeline.complete_level()
	await _wait_process_frames(2)
	_expect(timeline.is_victory(), "victory supersedes a pending capture")
	_expect(
		timeline.recordings.size() == 1
		and ended_reasons.back() == TimelineManager.REASON_VICTORY,
		"victory-capture race commits one reason and does not save a capture recording"
	)

	_expect(timeline.reset_timeline(), "capture fixture resets after victory")
	level.player_captured.emit(level.current_player)
	_expect(timeline.reset_timeline(), "full reset invalidates a pending capture callback")
	await _wait_process_frames(2)
	_expect(
		timeline.current_loop_index == 1
		and timeline.is_loop_running()
		and timeline.recordings.is_empty()
		and level.get_ghost_count() == 0,
		"stale capture callback cannot end a newly reset timeline"
	)
	fixture.free()
	await process_frame


func _test_two_loop_stealth_distraction_acceptance() -> void:
	print("[TEST] Two-loop Ghost distraction stealth acceptance")
	var fixture := Node2D.new()
	root.add_child(fixture)
	var level := LEVEL_SCENE.instantiate() as PrototypeLevel
	var timeline := TIMELINE_SCENE.instantiate() as TimelineManager
	timeline.capture_feedback_seconds = 0.0
	fixture.add_child(level)
	fixture.add_child(timeline)
	await _wait_physics_frames(3)
	var ended_reasons: Array[StringName] = []
	timeline.loop_ended.connect(
		func(_loop_index: int, reason: StringName) -> void:
			ended_reasons.append(reason)
	)
	_expect(timeline.configure(level), "stealth acceptance fixture configures")
	_expect(timeline.start_session(), "stealth acceptance starts loop 1")

	var loop_one_player: PlayerController = level.current_player
	await _move_player_realtime_until(
		timeline,
		loop_one_player,
		level.pressure_plate.global_position,
		0.7
	)
	await _wait_physics_frames(3)
	await _wait_timeline_until(timeline, 2.5)
	_expect(
		level.pressure_plate.is_active and level.security_door.is_open,
		"loop 1 records a usable plate-hold window"
	)
	await _move_player_realtime_until(timeline, loop_one_player, Vector2(548.0, 240.0), 3.35)
	await _wait_for_loop_physics(timeline, 2, 180)
	_expect(
		timeline.recordings.size() == 1
		and level.get_ghost_count() == 1
		and timeline.recordings[0].duration > 3.35
		and timeline.recordings[0].duration < 6.0
		and ended_reasons == [TimelineManager.REASON_CAPTURED],
		"default-tuned moving Guard captures and saves the physical upper-corridor lure"
	)

	var loop_two_player: PlayerController = level.current_player
	await _move_player_realtime_until(
		timeline,
		loop_two_player,
		level.pressure_plate.global_position,
		0.7
	)
	await _wait_physics_frames(3)
	await _move_player_realtime_until(timeline, loop_two_player, Vector2(704.0, 376.0), 1.9)
	_expect(
		loop_two_player.global_position.x > 680.0
		and level.pressure_plate.is_active
		and level.security_door.is_open,
		"loop 2 Player physically crosses while the Ghost repeats the plate hold"
	)
	await _move_player_realtime_until(timeline, loop_two_player, Vector2(736.0, 520.0), 2.7)
	for _frame: int in range(120):
		if level.training_guard.get_current_target_id() == &"ghost_001":
			break
		await physics_frame
		await process_frame
	_expect(
		level.training_guard.get_current_target_id() == &"ghost_001"
		and (
			level.training_guard.state == GuardController.GuardState.SUSPICIOUS
			or level.training_guard.state == GuardController.GuardState.CHASE
		),
		"moving Guard visibly acquires the replaying Ghost as its distraction target"
	)
	_expect(
		loop_two_player.global_position.y > 480.0,
		"live Player remains available on the lower vault lane during the distraction"
	)

	await _move_player_realtime_until(
		timeline,
		loop_two_player,
		level.objective_item.global_position,
		timeline.elapsed_time + 0.6
	)
	await _wait_physics_frames(3)
	var interact_input := InputEventAction.new()
	interact_input.action = &"interact"
	interact_input.pressed = true
	loop_two_player._unhandled_input(interact_input)
	await process_frame
	_expect(
		level.objective_item.is_collected and loop_two_player.has_objective_item(),
		"lower-lane Player collects the objective while the Ghost distracts the Guard"
	)
	await _move_player_realtime_until(
		timeline,
		loop_two_player,
		level.exit_zone.global_position,
		timeline.elapsed_time + 0.9
	)
	await _wait_physics_frames(5)
	await _wait_process_frames(2)
	_expect(
		timeline.is_victory(),
		"two-loop stealth route preserves objective, exit, and victory behavior"
	)
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
		and level.current_player.global_position.is_equal_approx(level.player_spawn.global_position)
		and level.training_guard.is_simulation_enabled(),
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


func _move_player_realtime_until(
	timeline: TimelineManager,
	player: PlayerController,
	target_position: Vector2,
	target_time: float
) -> void:
	player.set_physics_process(false)
	while (
		timeline.is_loop_running()
		and timeline.elapsed_time + FLOAT_EPSILON < target_time
	):
		var to_target := target_position - player.global_position
		if to_target.length() > 0.5:
			var motion := to_target.normalized() * minf(
				player.move_speed / 60.0,
				to_target.length()
			)
			player.velocity = motion * 60.0
			player.move_and_collide(motion)
		else:
			player.velocity = Vector2.ZERO
		await physics_frame
		await process_frame
	player.velocity = Vector2.ZERO


func _wait_timeline_until(timeline: TimelineManager, target_time: float) -> void:
	for _frame: int in range(600):
		if not timeline.is_loop_running() or timeline.elapsed_time >= target_time:
			return
		await physics_frame
		await process_frame


func _wait_for_loop_physics(
	timeline: TimelineManager,
	expected_loop_index: int,
	maximum_frames: int
) -> void:
	for _frame: int in range(maximum_frames):
		if timeline.current_loop_index == expected_loop_index and timeline.is_loop_running():
			return
		await physics_frame
		await process_frame


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


func _capture_tile_layer(layer: TileMapLayer) -> PackedStringArray:
	var captured := PackedStringArray()
	for cell: Vector2i in layer.get_used_cells():
		var atlas_coords: Vector2i = layer.get_cell_atlas_coords(cell)
		captured.append(
			"%d,%d:%d:%d,%d:%d"
			% [
				cell.x,
				cell.y,
				layer.get_cell_source_id(cell),
				atlas_coords.x,
				atlas_coords.y,
				layer.get_cell_alternative_tile(cell),
			]
		)
	captured.sort()
	return captured


func _expect(condition: bool, description: String) -> void:
	_assertion_count += 1
	if condition:
		print("  PASS: %s" % description)
		return
	_failure_count += 1
	push_error("  FAIL: %s" % description)


func _is_equal(left: float, right: float) -> bool:
	return absf(left - right) <= FLOAT_EPSILON
