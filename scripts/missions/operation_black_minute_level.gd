class_name OperationBlackMinuteLevel
extends Node2D

signal return_to_menu_requested

const TILE_SIZE: int = 32
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GUARD_SCENE: PackedScene = preload("res://scenes/enemies/guard.tscn")
const ACCESS_CARD_SCENE: PackedScene = preload("res://scenes/items/access_card.tscn")
const ACCESS_DOOR_SCENE: PackedScene = preload("res://scenes/objects/access_door.tscn")
const HACK_TERMINAL_SCENE: PackedScene = preload("res://scenes/objects/hack_terminal.tscn")
const SECURITY_CAMERA_SCENE: PackedScene = preload("res://scenes/security/security_camera.tscn")
const SECURITY_LASER_SCENE: PackedScene = preload("res://scenes/security/security_laser.tscn")
const CHRONOS_CORE_SCENE: PackedScene = preload("res://scenes/objects/chronos_core.tscn")
const EXTRACTION_SCENE: PackedScene = preload(
	"res://scenes/objects/mission_extraction_zone.tscn"
)

@onready var operation_map: OperationBlackMinuteMap = %OperationMap
@onready var actor_layer: Node2D = %ActorLayer
@onready var player_container: Node2D = %PlayerContainer
@onready var echo_container: Node2D = %EchoContainer
@onready var guard_container: Node2D = %GuardContainer
@onready var dynamic_objects: Node2D = %DynamicObjects
@onready var trigger_container: Node2D = %ProgressionTriggers
@onready var object_registry: ObjectRegistry = %ObjectRegistry
@onready var visibility_controller: WorldVisibilityController = %VisibilityController
@onready var mission_director: MissionDirector = %MissionDirector
@onready var access_control: AccessControlManager = %AccessControlManager
@onready var security_system: SecuritySystemManager = %SecuritySystemManager
@onready var guard_zone_manager: GuardZoneManager = %GuardZoneManager
@onready var patrol_scheduler: PatrolScheduler = %PatrolScheduler
@onready var chrono_recall: ChronoRecallManager = %ChronoRecallManager
@onready var hud: HeistHUD = %HeistHUD
@onready var map_overlay: FacilityMapOverlay = %FacilityMapOverlay

var player: PlayerController = null
var _blueprint: Dictionary = {}
var _guards: Array[GuardController] = []
var _cameras: Array[SecurityCamera] = []
var _lasers: Array[SecurityLaser] = []
var _doors: Dictionary[StringName, AccessDoor] = {}
var _terminals: Dictionary[StringName, HackTerminal] = {}
var _extraction: MissionExtractionZone = null
var _core: ChronosCore = null
var _maintenance_discovered: bool = false
var _infiltration_reported: bool = false
var _operation_ready: bool = false
var _capture_pending: bool = false
var _capture_recall_available: bool = false
var _pause_open: bool = false
var _map_update_accumulator: float = 0.0
var _tutorial_flags: Dictionary[StringName, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"recall_rewindable")
	_blueprint = operation_map.get_blueprint()
	if _blueprint.is_empty():
		push_error("Operation: Black Minute cannot start without its 64x42 blueprint")
		return
	if not guard_zone_manager.configure_from_blueprint(_blueprint):
		return
	if not patrol_scheduler.configure_from_blueprint(_blueprint):
		return
	_add_manager_rewind_contracts()
	_connect_manager_signals()
	_build_dynamic_mission()
	if not _validate_runtime_contracts():
		return
	_operation_ready = true
	reset_operation()


func _process(delta: float) -> void:
	if not _operation_ready or get_tree().paused:
		return
	security_system.advance_alert_decay(delta)
	_map_update_accumulator += maxf(0.0, delta)
	if _map_update_accumulator >= 0.1:
		_map_update_accumulator = fmod(_map_update_accumulator, 0.1)
		_sync_map_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed(&"open_map"):
		if not _capture_pending and not mission_director.is_completed():
			map_overlay.toggle_map()
		get_viewport().set_input_as_handled()
	elif _capture_pending and event.is_action_pressed(&"chrono_recall"):
		_resolve_capture_with_recall()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"pause"):
		if map_overlay.visible:
			map_overlay.close_map()
		elif _capture_pending or mission_director.is_completed():
			return
		else:
			_set_pause_open(not _pause_open)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if (
		what != NOTIFICATION_APPLICATION_FOCUS_OUT
		or not _operation_ready
		or _capture_pending
		or mission_director.is_completed()
		or map_overlay.visible
	):
		return
	_set_pause_open(true)


func reset_operation() -> bool:
	if not _operation_ready:
		return false
	_set_runtime_simulation(false)
	get_tree().paused = false
	_pause_open = false
	_capture_pending = false
	_capture_recall_available = false
	map_overlay.close_map()
	hud.hide_capture_choice()
	hud.hide_victory()
	chrono_recall.clear_echoes()
	patrol_scheduler.clear_runtime(false)
	guard_zone_manager.reset_for_mission()
	access_control.reset_mission()
	security_system.reset_mission()
	mission_director.reset_mission()
	_maintenance_discovered = false
	_infiltration_reported = false
	_tutorial_flags.clear()
	_reset_world_objects()
	player.initialize_at(_object_world_position(&"player_spawn"))
	player.configure_heist_controls(true)
	player.configure_facility_view(
		Rect2(Vector2.ZERO, Vector2(operation_map.get_world_size())),
		Vector2(2.0, 2.0),
		352.0
	)
	if not object_registry.rebuild(self):
		return false
	if not mission_director.begin_mission():
		return false
	chrono_recall.rewind_duration_seconds = (
		mission_director.mission_definition.rewind_duration_seconds
	)
	chrono_recall.maximum_charges = mission_director.mission_definition.recall_charges
	if not chrono_recall.configure(player, object_registry, echo_container, self):
		return false
	if not chrono_recall.begin_mission():
		return false
	visibility_controller.configure(player.get_visibility_probe())
	player.set_facility_visibility_enabled(true)
	visibility_controller.set_enabled(true)
	_set_runtime_simulation(true)
	_sync_all_ui()
	hud.show_toast(
		"PRIMARY OBJECTIVE  //  STEAL THE CHRONOS CORE\nOPEN THE TACTICAL MAP WITH M",
		4.0
	)
	return true


func get_guard_count() -> int:
	return _guards.size()


func get_camera_count() -> int:
	return _cameras.size()


func get_laser_count() -> int:
	return _lasers.size()


func get_player() -> PlayerController:
	return player


func is_pause_open() -> bool:
	return _pause_open


func get_blueprint() -> Dictionary:
	return _blueprint.duplicate(true)


func get_recall_state_id() -> StringName:
	return &"operation_black_minute_runtime"


func capture_recall_state() -> Dictionary:
	return {
		"maintenance_discovered": _maintenance_discovered,
		"infiltration_reported": _infiltration_reported,
		"tutorial_flags": _tutorial_flags.duplicate(true),
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	var tutorial_variant: Variant = snapshot.get("tutorial_flags", {})
	if not tutorial_variant is Dictionary:
		return false
	_maintenance_discovered = bool(snapshot.get("maintenance_discovered", false))
	_infiltration_reported = bool(snapshot.get("infiltration_reported", false))
	_tutorial_flags = (tutorial_variant as Dictionary).duplicate(true)
	_sync_all_ui()
	return true


func _add_manager_rewind_contracts() -> void:
	for manager: Node in [mission_director, access_control, security_system]:
		manager.add_to_group(&"recall_rewindable")


func _connect_manager_signals() -> void:
	mission_director.primary_objective_changed.connect(hud.set_primary_objective)
	mission_director.objectives_changed.connect(_on_objectives_changed)
	mission_director.objective_completed.connect(_on_objective_completed)
	mission_director.chronos_core_state_changed.connect(_on_core_state_changed)
	mission_director.capture_decision_requested.connect(hud.show_capture_choice)
	mission_director.mission_completed.connect(_on_mission_completed)
	access_control.access_changed.connect(_on_access_changed)
	access_control.access_denied.connect(_on_access_denied)
	security_system.cctv_network_changed.connect(_on_cctv_network_changed)
	security_system.laser_network_changed.connect(_on_laser_network_changed)
	security_system.alert_level_changed.connect(_on_alert_level_changed)
	security_system.zone_alert_requested.connect(_on_zone_alert_requested)
	chrono_recall.charges_changed.connect(hud.set_recall_charges)
	chrono_recall.recall_completed.connect(_on_recall_completed)
	chrono_recall.recall_rejected.connect(_on_recall_rejected)
	chrono_recall.echo_spawned.connect(_on_echo_spawned)
	hud.map_requested.connect(map_overlay.toggle_map)
	hud.recall_requested.connect(_request_manual_recall)
	hud.capture_recall_selected.connect(_resolve_capture_with_recall)
	hud.checkpoint_restart_selected.connect(reset_operation)
	hud.mission_restart_requested.connect(reset_operation)
	hud.menu_requested.connect(func() -> void: return_to_menu_requested.emit())
	hud.resume_requested.connect(func() -> void: _set_pause_open(false))
	map_overlay.opened.connect(_on_map_opened)
	map_overlay.closed.connect(_on_map_closed)


func _build_dynamic_mission() -> void:
	_spawn_player()
	_spawn_access_doors()
	_spawn_access_cards()
	_spawn_terminals()
	_spawn_security_cameras()
	_spawn_lasers()
	_spawn_core_and_extraction()
	_spawn_progression_triggers()
	_spawn_guards()
	map_overlay.configure(_blueprint)


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	if player == null:
		push_error("Operation mission requires a PlayerController scene root")
		return
	player_container.add_child(player)
	player.initialize_at(_object_world_position(&"player_spawn"))
	player.configure_heist_controls(true)
	player.interaction_recorded.connect(chrono_recall.record_interaction)
	player.chrono_recall_requested.connect(_request_manual_recall)
	player.map_requested.connect(map_overlay.toggle_map)
	player.interaction_prompt_changed.connect(hud.set_interaction_prompt)


func _spawn_access_doors() -> void:
	var portals_variant: Variant = _blueprint.get("dynamic_portals", [])
	if not portals_variant is Array:
		return
	for portal_variant: Variant in portals_variant as Array:
		if not portal_variant is Dictionary:
			continue
		var portal := portal_variant as Dictionary
		var door := ACCESS_DOOR_SCENE.instantiate() as AccessDoor
		if door == null:
			continue
		var door_id := StringName(str(portal.get("id", "")))
		var span := _json_rect(portal.get("span_rect", []))
		door.name = String(door_id)
		door.object_id = door_id
		door.required_access = _parse_access_level(String(portal.get("required_access", "PUBLIC")))
		door.starts_open = bool(portal.get("initially_open", false))
		door.position = _rect_world_center(span)
		if span.size.x > span.size.y:
			door.rotation = PI * 0.5
			door.scale.y = maxf(0.5, float(span.size.x) / 3.0)
		else:
			door.scale.y = maxf(0.5, float(span.size.y) / 3.0)
		var required_flags := _string_name_array(portal.get("required_flags_all", []))
		var condition := Callable()
		var denial_message := "SECURITY CONDITION NOT MET"
		if not required_flags.is_empty():
			condition = _check_required_flags.bind(required_flags)
			denial_message = _door_condition_message(required_flags)
			door.requires_vault_authorization = true
		dynamic_objects.add_child(door)
		door.configure(access_control, condition, denial_message)
		door.access_denied.connect(
			func(_level: AccessControlManager.AccessLevel) -> void:
				hud.show_toast(door.get_interaction_prompt(player), 2.0)
		)
		if door_id == &"door_reception_checkpoint_01":
			door.open_state_changed.connect(_on_reception_door_changed)
		_doors[door_id] = door


func _spawn_access_cards() -> void:
	for card_id: StringName in [&"keycard_level_1_01", &"keycard_level_2_01"]:
		var card := ACCESS_CARD_SCENE.instantiate() as AccessCard
		if card == null:
			continue
		card.name = String(card_id)
		card.object_id = card_id
		card.access_level = (
			AccessControlManager.AccessLevel.LEVEL_1
			if card_id == &"keycard_level_1_01"
			else AccessControlManager.AccessLevel.LEVEL_2
		)
		card.position = _object_world_position(card_id)
		dynamic_objects.add_child(card)
		card.collected.connect(_on_access_card_collected)


func _spawn_terminals() -> void:
	var security := _blueprint.get("security", {}) as Dictionary
	var cctv := security.get("cctv_network", {}) as Dictionary
	var laser := security.get("laser_network", {}) as Dictionary
	_spawn_terminal(cctv.get("terminal", {}) as Dictionary, &"disable_cctv")
	_spawn_terminal(laser.get("terminal", {}) as Dictionary, &"disable_lasers")
	var authorization := security.get("vault_authorization", {}) as Dictionary
	var sources_variant: Variant = authorization.get("sources", [])
	if sources_variant is Array:
		for source_variant: Variant in sources_variant as Array:
			if not source_variant is Dictionary:
				continue
			var source := source_variant as Dictionary
			var source_id := StringName(str(source.get("id", "")))
			var action := (
				&"server_override"
				if source_id == &"terminal_server_override_01"
				else &"biometric_authorization"
			)
			_spawn_terminal(source, action)
	var objects := _blueprint.get("objects", {}) as Dictionary
	for optional_id: StringName in [
		&"terminal_staff_intel_01",
		&"terminal_guard_distraction_01",
		&"terminal_security_map_01",
	]:
		var data := (objects.get(String(optional_id), {}) as Dictionary).duplicate(true)
		data["id"] = optional_id
		_spawn_terminal(data, optional_id)


func _spawn_terminal(data: Dictionary, action: StringName) -> void:
	if data.is_empty():
		return
	var terminal := HACK_TERMINAL_SCENE.instantiate() as HackTerminal
	if terminal == null:
		return
	var terminal_id := StringName(str(data.get("id", "")))
	terminal.name = String(terminal_id)
	terminal.object_id = terminal_id
	terminal.action_id = action
	terminal.hack_duration_seconds = maxf(
		0.5,
		float(data.get("interaction_seconds", 1.4))
	)
	terminal.echo_replay_allowed = not (
		action == &"server_override" or action == &"biometric_authorization"
	)
	terminal.position = _cell_world(_json_cell(data.get("position", [])))
	dynamic_objects.add_child(terminal)
	terminal.configure_access(
		access_control,
		_parse_access_level(String(data.get("required_access", "PUBLIC")))
	)
	terminal.hack_completed.connect(_on_terminal_completed)
	_terminals[terminal_id] = terminal


func _spawn_security_cameras() -> void:
	var security := _blueprint.get("security", {}) as Dictionary
	var cctv := security.get("cctv_network", {}) as Dictionary
	var camera_values: Variant = cctv.get("cameras", [])
	if not camera_values is Array:
		return
	for camera_variant: Variant in camera_values as Array:
		if not camera_variant is Dictionary:
			continue
		var data := camera_variant as Dictionary
		var camera := SECURITY_CAMERA_SCENE.instantiate() as SecurityCamera
		if camera == null:
			continue
		camera.object_id = StringName(str(data.get("id", "")))
		camera.zone_id = StringName(str(data.get("zone_id", "")))
		camera.position = _cell_world(_json_cell(data.get("position", [])))
		camera.initial_facing = Vector2.RIGHT.rotated(
			deg_to_rad(float(data.get("center_facing_degrees", 0.0)))
		)
		camera.sweep_half_angle_degrees = float(data.get("sweep_half_angle_degrees", 40.0))
		camera.sweep_speed_degrees = float(data.get("angular_speed_degrees_per_second", 20.0))
		camera.start_phase_seconds = float(data.get("start_phase_seconds", 0.0))
		camera.vision_distance = float(data.get("vision_distance", 224.0))
		camera.vision_half_angle_degrees = float(data.get("vision_half_angle_degrees", 30.0))
		dynamic_objects.add_child(camera)
		camera.configure(security_system)
		camera.threshold_reached.connect(_on_camera_threshold_reached)
		_cameras.append(camera)


func _spawn_lasers() -> void:
	var security := _blueprint.get("security", {}) as Dictionary
	var laser_network := security.get("laser_network", {}) as Dictionary
	var barriers_variant: Variant = laser_network.get("barriers", [])
	if not barriers_variant is Array:
		return
	for barrier_variant: Variant in barriers_variant as Array:
		if not barrier_variant is Dictionary:
			continue
		var data := barrier_variant as Dictionary
		var laser := SECURITY_LASER_SCENE.instantiate() as SecurityLaser
		if laser == null:
			continue
		laser.object_id = StringName(str(data.get("id", "")))
		laser.zone_id = &"zone_vault"
		laser.position = _cell_world(_json_cell(data.get("anchor", [])))
		var span := _json_rect(data.get("span_rect", []))
		laser.scale.y = maxf(1.0, float(span.size.y * TILE_SIZE) / 104.0)
		dynamic_objects.add_child(laser)
		laser.tripped.connect(_on_laser_tripped)
		_lasers.append(laser)


func _spawn_core_and_extraction() -> void:
	_core = CHRONOS_CORE_SCENE.instantiate() as ChronosCore
	if _core != null:
		_core.object_id = &"objective_chronos_core_01"
		var core_data := (
			_blueprint.get("objects", {}) as Dictionary
		).get("objective_chronos_core_01", {}) as Dictionary
		_core.interaction_duration_seconds = maxf(
			0.1,
			float(core_data.get("interaction_seconds", 1.2))
		)
		_core.position = _object_world_position(&"objective_chronos_core_01")
		dynamic_objects.add_child(_core)
		_core.configure(_can_collect_core)
		_core.stolen.connect(_on_core_stolen)
	_extraction = EXTRACTION_SCENE.instantiate() as MissionExtractionZone
	if _extraction != null:
		_extraction.object_id = &"extraction_yard_01"
		_extraction.position = _object_world_position(&"extraction_yard_01")
		dynamic_objects.add_child(_extraction)
		_extraction.extraction_requested.connect(_on_extraction_requested)
		_extraction.extraction_denied.connect(hud.show_toast)


func _spawn_progression_triggers() -> void:
	_create_progress_trigger(
		&"trigger_reception_entry",
		_cell_world(Vector2i(15, 33)),
		Vector2(80.0, 96.0),
		&"facility_entered"
	)
	_create_progress_trigger(
		&"trigger_vault_entry",
		_cell_world(Vector2i(59, 12)),
		Vector2(96.0, 96.0),
		&"vault_entered"
	)


func _create_progress_trigger(
	trigger_id: StringName,
	world_position: Vector2,
	shape_size: Vector2,
	event_id: StringName
) -> void:
	var area := Area2D.new()
	area.name = String(trigger_id)
	area.position = world_position
	area.collision_layer = 0
	area.collision_mask = 2
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = shape_size
	collision.shape = shape
	area.add_child(collision)
	trigger_container.add_child(area)
	area.body_entered.connect(_on_progress_trigger_entered.bind(event_id))


func _spawn_guards() -> void:
	var guards_variant: Variant = _blueprint.get("guards", [])
	if not guards_variant is Array:
		return
	for guard_variant: Variant in guards_variant as Array:
		if not guard_variant is Dictionary:
			continue
		var data := guard_variant as Dictionary
		var guard := GUARD_SCENE.instantiate() as GuardController
		if guard == null:
			continue
		guard.object_id = StringName(str(data.get("id", "")))
		guard.name = String(guard.object_id)
		guard.zone_id = StringName(str(data.get("zone_id", "")))
		guard.position = _cell_world(_json_cell(data.get("spawn", [])))
		guard.initial_facing = _json_direction(data.get("initial_facing", []))
		guard.patrol_speed = float(data.get("movement_speed", 42.0))
		guard.chase_speed = guard.patrol_speed * 1.8
		guard_container.add_child(guard)
		guard.add_to_group(&"recall_rewindable")
		guard.configure_patrol_pattern(
			_json_world_points(data.get("waypoints", [])),
			_json_float_array(data.get("waypoint_wait_seconds", [])),
			StringName(str(data.get("route_mode", "LOOP"))),
			float(data.get("start_phase_seconds", 0.0)),
			float(data.get("movement_speed", 42.0))
		)
		guard.reset_for_loop()
		guard.configure_mission_zone(guard_zone_manager, patrol_scheduler)
		guard.capture_requested.connect(_on_guard_capture_requested)
		guard.alert_raised.connect(_on_guard_alert_raised.bind(guard))
		_guards.append(guard)


func _validate_runtime_contracts() -> bool:
	var valid := true
	if player == null:
		push_error("Operation mission did not create its Player")
		valid = false
	if _guards.size() != 10:
		push_error("Operation mission requires exactly 10 Guards, got %d" % _guards.size())
		valid = false
	if _cameras.size() != 8 or _lasers.size() != 3:
		push_error(
			"Operation security contract requires 8 CCTV and 3 lasers, got %d/%d"
			% [_cameras.size(), _lasers.size()]
		)
		valid = false
	if _doors.size() < 12 or _terminals.size() < 6:
		push_error("Operation mission is missing access doors or functional terminals")
		valid = false
	if not guard_zone_manager.validate_registered_assignments(true):
		push_error("Operation mission Guard-zone assignments are incomplete")
		valid = false
	return valid


func _reset_world_objects() -> void:
	for candidate: Node in get_tree().get_nodes_in_group(&"mission_resettable"):
		if candidate != self and is_ancestor_of(candidate) and candidate.has_method(&"reset_mission"):
			candidate.call(&"reset_mission")
	for guard: GuardController in _guards:
		guard.reset_for_loop()
	for camera: SecurityCamera in _cameras:
		camera.set_physics_process(true)
	if _extraction != null:
		_extraction.set_active(false)


func _set_runtime_simulation(enabled: bool) -> void:
	if player != null:
		player.set_gameplay_input_enabled(enabled)
	for guard: GuardController in _guards:
		guard.set_simulation_enabled(enabled)
	for camera: SecurityCamera in _cameras:
		camera.set_physics_process(enabled)
	if chrono_recall.state != ChronoRecallManager.RecallState.UNCONFIGURED:
		chrono_recall.set_simulation_enabled(enabled)


func _request_manual_recall() -> void:
	if _capture_pending or map_overlay.visible or not mission_director.is_mission_active():
		return
	if chrono_recall.request_recall():
		hud.show_toast("CHRONO RECALL  //  ECHO CREATED", 2.0)


func _request_capture(source: StringName) -> void:
	if _capture_pending or not mission_director.is_mission_active():
		return
	# Availability must be sampled while the live branch is still running.
	# Disabling simulation intentionally makes ChronoRecallManager.can_recall() false.
	_capture_recall_available = chrono_recall.can_recall()
	_capture_pending = true
	_set_runtime_simulation(false)
	player.set_facility_visibility_enabled(false)
	# Capture is a modal mission decision. Pause the pausable gameplay branches so
	# in-progress terminal hacks and physics callbacks cannot mutate the world.
	get_tree().paused = true
	security_system.raise_facility_alert(SecuritySystemManager.AlertLevel.ALERTED)
	if not mission_director.request_capture_decision(_capture_recall_available):
		_capture_pending = false
		_capture_recall_available = false
		get_tree().paused = false
		player.set_facility_visibility_enabled(true)
		_set_runtime_simulation(true)
		return
	hud.show_toast("CAUGHT  //  %s" % String(source).to_upper(), 1.0)


func _resolve_capture_with_recall() -> void:
	if not _capture_pending or not _capture_recall_available:
		return
	chrono_recall.set_simulation_enabled(true)
	var succeeded := chrono_recall.request_recall()
	if not succeeded:
		chrono_recall.set_simulation_enabled(false)
		_capture_recall_available = false
		hud.show_capture_choice(false)
		return
	if _capture_pending:
		_finish_capture_resolution()


func _set_pause_open(open: bool) -> void:
	_pause_open = open
	get_tree().paused = open
	hud.show_pause(open)
	if not open:
		hud.show_toast("OPERATION RESUMED", 0.8)


func _on_map_opened() -> void:
	if _capture_pending or mission_director.is_completed():
		map_overlay.close_map()
		return
	_sync_map_status()
	get_tree().paused = true


func _on_map_closed() -> void:
	if not _pause_open and not _capture_pending and not mission_director.is_completed():
		get_tree().paused = false


func _on_access_card_collected(
	_actor: Node,
	level: AccessControlManager.AccessLevel,
	card_id: StringName
) -> void:
	if not access_control.grant_access(level, card_id):
		return
	mission_director.report_event(
		&"level_1_acquired"
		if level == AccessControlManager.AccessLevel.LEVEL_1
		else &"level_2_acquired"
	)
	hud.show_toast("%s ACCESS ACQUIRED" % access_control.get_access_label(), 2.0)


func _on_terminal_completed(action_id: StringName, actor: Node) -> void:
	match action_id:
		&"disable_cctv":
			security_system.disable_cctv_network()
			mission_director.report_event(&"cctv_disabled")
			hud.show_toast("CCTV NETWORK OFFLINE", 2.2)
		&"disable_lasers":
			security_system.disable_laser_network()
			mission_director.report_event(&"laser_disabled")
			hud.show_toast("LASER NETWORK OFFLINE", 2.2)
		&"server_override", &"biometric_authorization":
			var is_live_player := (
				actor != null
				and actor == player
				and actor.is_in_group(&"player_actor")
				and not actor.is_in_group(&"ghost_actor")
			)
			if not is_live_player:
				push_warning(
					"Operation rejected non-live credential terminal completion: %s"
					% action_id
				)
				return
			if not access_control.can_access(AccessControlManager.AccessLevel.LEVEL_2):
				hud.show_toast("LEVEL 2 ACCESS REQUIRED", 1.8)
				return
			if not mission_director.report_event(action_id):
				return
			access_control.grant_access(
				AccessControlManager.AccessLevel.VAULT,
				StringName("credential_%s" % action_id)
			)
			hud.show_toast("VAULT AUTHORIZATION GRANTED", 2.4)
		&"terminal_security_map_01":
			_maintenance_discovered = true
			hud.show_toast("MAINTENANCE PASSAGE ADDED TO MAP", 2.0)
		&"terminal_guard_distraction_01":
			security_system.raise_zone_alert(
				&"zone_cctv",
				_cell_world(Vector2i(5, 6)),
				action_id,
				SecuritySystemManager.AlertLevel.SUSPICIOUS
			)
			hud.show_toast("BREAK ROOM DISTRACTION ACTIVE", 1.8)
		&"terminal_staff_intel_01":
			hud.show_toast("INTEL: LEVEL 1 CARD IS IN THE LOCKER ROOM", 2.8)
	_sync_all_ui()


func _on_camera_threshold_reached(
	_camera_id: StringName,
	_zone_id: StringName,
	_actor_id: StringName,
	_last_seen: Vector2
) -> void:
	_show_tutorial_once(
		&"camera_alert",
		"CAMERA ALERT  //  NEARBY GUARDS ARE INVESTIGATING"
	)


func _on_laser_tripped(_actor: Node, zone_id: StringName) -> void:
	security_system.raise_zone_alert(
		zone_id,
		player.global_position,
		&"laser_contact",
		SecuritySystemManager.AlertLevel.ALERTED
	)
	_request_capture(&"laser_security")


func _on_guard_capture_requested(captured_player: PlayerController) -> void:
	if captured_player == player:
		_request_capture(&"security_guard")


func _on_guard_alert_raised(target_id: StringName, guard: GuardController) -> void:
	security_system.raise_zone_alert(
		guard.zone_id,
		guard.last_seen_position,
		target_id,
		SecuritySystemManager.AlertLevel.ALERTED
	)


func _on_zone_alert_requested(
	zone_id: StringName,
	position: Vector2,
	source_id: StringName
) -> void:
	guard_zone_manager.propagate_zone_alert(zone_id, position, source_id, true)
	_sync_security_ui()


func _on_reception_door_changed(is_open: bool) -> void:
	if is_open and not _infiltration_reported:
		_infiltration_reported = mission_director.report_event(&"facility_entered")
		_show_tutorial_once(
			&"guard_awareness",
			"AVOID VISION CONES  //  GUARDS ALSO NOTICE ACTORS AT CLOSE RANGE"
		)


func _on_progress_trigger_entered(body: Node2D, event_id: StringName) -> void:
	if body != player or not mission_director.is_mission_active():
		return
	if event_id == &"facility_entered":
		if _infiltration_reported:
			return
		_infiltration_reported = mission_director.report_event(event_id)
		_show_tutorial_once(
			&"guard_awareness",
			"AVOID VISION CONES  //  CLOSE PROXIMITY IS DETECTED IN 360°"
		)
	elif event_id == &"vault_entered":
		mission_director.report_event(event_id)


func _on_core_stolen(actor: Node) -> void:
	if actor != player or not mission_director.report_event(&"chronos_core_stolen"):
		return
	player.grant_objective()
	_extraction.set_active(true)
	security_system.raise_facility_alert(SecuritySystemManager.AlertLevel.LOCKDOWN)
	for door_id: StringName in [
		&"door_vault_extraction_01",
		&"door_extraction_yard_01",
	]:
		if _doors.has(door_id):
			_doors[door_id].unlock_and_open()
	hud.show_toast("CHRONOS CORE SECURED  //  RETURN TO EXTRACTION", 3.0)
	_sync_all_ui()


func _on_extraction_requested(actor: Node) -> void:
	if actor == player:
		mission_director.request_extraction()


func _on_mission_completed(_mission_id: StringName) -> void:
	_set_runtime_simulation(false)
	player.set_facility_visibility_enabled(true)
	get_tree().paused = false
	hud.show_victory(
		chrono_recall.maximum_charges - chrono_recall.remaining_charges
	)


func _on_objectives_changed(_objective_ids: Array[StringName]) -> void:
	var lines := mission_director.get_current_objective_lines()
	hud.set_objectives(lines)
	map_overlay.set_objectives(lines)


func _on_objective_completed(_objective_id: StringName, title: String) -> void:
	hud.show_toast("OBJECTIVE COMPLETE\n%s" % title.to_upper(), 1.8)


func _on_core_state_changed(is_carried: bool) -> void:
	if player != null and not is_carried:
		player.initialize_at(player.global_position)
	if _extraction != null:
		_extraction.set_active(is_carried)
	hud.set_core_carried(is_carried)
	_sync_map_status()


func _on_access_changed(
	_previous: AccessControlManager.AccessLevel,
	_current: AccessControlManager.AccessLevel
) -> void:
	hud.set_access(access_control.get_access_label())


func _on_access_denied(
	_door_id: StringName,
	required: AccessControlManager.AccessLevel
) -> void:
	hud.show_toast(
		"ACCESS DENIED  //  %s CARD REQUIRED"
		% AccessControlManager.ACCESS_NAMES.get(required, &"SECURITY"),
		2.0
	)


func _on_cctv_network_changed(is_online: bool) -> void:
	for camera: SecurityCamera in _cameras:
		camera.set_network_online(is_online)
	_sync_security_ui()


func _on_laser_network_changed(is_online: bool) -> void:
	for laser: SecurityLaser in _lasers:
		laser.set_active(is_online)
	_sync_security_ui()


func _on_alert_level_changed(
	_previous: SecuritySystemManager.AlertLevel,
	_current: SecuritySystemManager.AlertLevel
) -> void:
	_sync_security_ui()


func _on_recall_completed(
	_from_time: float,
	_to_time: float,
	_echo: GhostPlayback,
	succeeded: bool
) -> void:
	if succeeded:
		if _capture_pending:
			_finish_capture_resolution()
		_sync_all_ui()


func _on_recall_rejected(reason: String) -> void:
	hud.show_toast(reason.to_upper(), 1.6)


func _on_echo_spawned(echo: GhostPlayback, _sequence: int) -> void:
	visibility_controller.register_target(echo)
	hud.show_toast("ECHO DEPLOYED  //  SECURITY CAN SEE IT", 1.5)


func _finish_capture_resolution() -> void:
	_capture_pending = false
	_capture_recall_available = false
	hud.hide_capture_choice()
	mission_director.resume_after_capture_decision()
	player.set_facility_visibility_enabled(true)
	_set_runtime_simulation(true)
	get_tree().paused = false


func _sync_all_ui() -> void:
	hud.set_primary_objective(MissionDirector.PRIMARY_TITLE)
	hud.set_objectives(mission_director.get_current_objective_lines())
	hud.set_access(access_control.get_access_label())
	hud.set_recall_charges(chrono_recall.remaining_charges, chrono_recall.maximum_charges)
	hud.set_core_carried(mission_director.chronos_core_carried)
	_sync_security_ui()
	_sync_map_status()


func _sync_security_ui() -> void:
	hud.set_security(
		security_system.cctv_online,
		security_system.laser_online,
		security_system.get_alert_label()
	)
	map_overlay.set_security_status(
		security_system.cctv_online,
		security_system.laser_online
	)


func _sync_map_status() -> void:
	if player == null:
		return
	map_overlay.set_player_position(player.global_position)
	map_overlay.set_mission_status(
		mission_director.chronos_core_carried,
		_maintenance_discovered
	)


func _show_tutorial_once(flag: StringName, message: String) -> void:
	if bool(_tutorial_flags.get(flag, false)):
		return
	_tutorial_flags[flag] = true
	hud.show_toast(message, 3.0)


func _can_collect_core() -> bool:
	return (
		mission_director.is_mission_active()
		and access_control.current_level >= AccessControlManager.AccessLevel.VAULT
		and not security_system.laser_online
		and mission_director.has_vault_authorization()
	)


func _check_required_flags(required_flags: Array[StringName]) -> bool:
	for flag: StringName in required_flags:
		match flag:
			&"laser_network_offline":
				if security_system.laser_online:
					return false
			&"vault_authorized":
				if not mission_director.has_vault_authorization():
					return false
			&"maintenance_passage_discovered":
				if not _maintenance_discovered:
					return false
			&"chronos_core_stolen":
				if not mission_director.chronos_core_carried:
					return false
			_:
				return false
	return true


func _door_condition_message(flags: Array[StringName]) -> String:
	if flags.has(&"laser_network_offline") and security_system.laser_online:
		return "LASER NETWORK MUST BE DISABLED"
	if flags.has(&"vault_authorized"):
		return "VAULT AUTHORIZATION REQUIRED"
	if flags.has(&"maintenance_passage_discovered"):
		return "MAINTENANCE ROUTE NOT DISCOVERED"
	if flags.has(&"chronos_core_stolen"):
		return "EXTRACTION ROUTE LOCKED UNTIL CORE THEFT"
	return "SECURITY CONDITION NOT MET"


func _object_world_position(object_id: StringName) -> Vector2:
	var objects := _blueprint.get("objects", {}) as Dictionary
	var data := objects.get(String(object_id), {}) as Dictionary
	return _cell_world(_json_cell(data.get("position", [])))


static func _cell_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2.ONE * (TILE_SIZE * 0.5)


static func _rect_world_center(rect: Rect2i) -> Vector2:
	return Vector2(rect.position * TILE_SIZE) + Vector2(rect.size * TILE_SIZE) * 0.5


static func _json_cell(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int((value as Array)[0]), int((value as Array)[1]))


static func _json_rect(value: Variant) -> Rect2i:
	if not value is Array or (value as Array).size() != 4:
		return Rect2i()
	return Rect2i(
		int((value as Array)[0]),
		int((value as Array)[1]),
		int((value as Array)[2]),
		int((value as Array)[3])
	)


static func _json_direction(value: Variant) -> Vector2:
	var cell := _json_cell(value)
	var direction := Vector2(cell)
	return direction.normalized() if not direction.is_zero_approx() else Vector2.RIGHT


static func _json_world_points(value: Variant) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if value is Array:
		for point_variant: Variant in value as Array:
			result.append(_cell_world(_json_cell(point_variant)))
	return result


static func _json_float_array(value: Variant) -> Array[float]:
	var result: Array[float] = []
	if value is Array:
		for item: Variant in value as Array:
			result.append(maxf(0.0, float(item)))
	return result


static func _string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item: Variant in value as Array:
			result.append(StringName(str(item)))
	return result


static func _parse_access_level(value: String) -> AccessControlManager.AccessLevel:
	match value:
		"LEVEL_1":
			return AccessControlManager.AccessLevel.LEVEL_1
		"LEVEL_2":
			return AccessControlManager.AccessLevel.LEVEL_2
		"VAULT":
			return AccessControlManager.AccessLevel.VAULT
		_:
			return AccessControlManager.AccessLevel.PUBLIC
