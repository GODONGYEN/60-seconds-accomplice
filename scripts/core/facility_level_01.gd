class_name FacilityLevel01
extends GameplayLevel

const EXPECTED_MAP_SIZE := Vector2i(26, 25)
const EXPECTED_WORLD_SIZE := Vector2i(832, 800)
const EXPECTED_LOOP_DURATION: float = 60.0

@export_range(160.0, 320.0, 8.0) var player_visibility_radius: float = 240.0
@export var player_camera_zoom: Vector2 = Vector2(2.0, 2.0)

@onready var facility_map: FacilityLevelMap = %FacilityMap
@onready var pressure_plate: PressurePlate = %PressurePlate
@onready var security_door: SecurityDoor = %SecurityDoor
@onready var laser_barrier: LaserBarrier = %LaserBarrier
@onready var security_terminal: SecurityTerminal = %SecurityTerminal
@onready var objective_item: ObjectiveItem = %ObjectiveItem
@onready var exit_zone: ExitZone = %ExitZone
@onready var security_camera: DecorativeSecurityCamera = %SecurityCamera
@onready var visibility_controller: WorldVisibilityController = %VisibilityController


func _ready() -> void:
	super._ready()
	pressure_plate.active_changed.connect(_on_plate_active_changed)
	security_door.open_state_changed.connect(_on_door_open_state_changed)
	security_terminal.activated.connect(_on_terminal_activated)
	laser_barrier.tripped.connect(_on_laser_tripped)
	objective_item.collected.connect(_on_objective_collected)
	exit_zone.exit_requested.connect(_on_exit_requested)
	exit_zone.feedback_requested.connect(_on_feedback_requested)
	visibility_controller.target_visibility_changed.connect(_on_target_visibility_changed)
	_register_static_visibility_targets()
	visibility_controller.hide_all_immediately()


func validate_level() -> bool:
	if not super.validate_level():
		return false
	if facility_map.get_map_size() != EXPECTED_MAP_SIZE:
		push_error("FacilityLevel01 map size differs from its 26x25 blueprint")
		return false
	if facility_map.get_world_size() != EXPECTED_WORLD_SIZE:
		push_error("FacilityLevel01 world size differs from its 832x800 blueprint")
		return false
	if not is_equal_approx(level_loop_duration_seconds, EXPECTED_LOOP_DURATION):
		push_error("FacilityLevel01 loop duration must be 60 seconds")
		return false
	if not facility_map.walls.collision_enabled or not facility_map.walls.occlusion_enabled:
		push_error("FacilityLevel01 Walls must enable collision and light occlusion")
		return false
	var required_positions: Array[Node2D] = [
		player_spawn,
		pressure_plate,
		security_door,
		laser_barrier,
		security_terminal,
		objective_item,
		exit_zone,
		security_camera,
	]
	for node: Node2D in required_positions:
		var cell := Vector2i(floor(node.global_position / FacilityLevelMap.TILE_SIZE))
		if not facility_map.is_walkable_cell(cell):
			push_error("FacilityLevel01 node '%s' is not on walkable floor" % node.name)
			return false
	return true


func get_loop_hint(loop_index: int) -> String:
	if loop_index <= 1:
		return "USE THE WALLS — DRAW THE CENTER GUARD WEST AND END ON THE VAULT PLATE"
	return "YOUR GHOST HOLDS THE VAULT — USE THE LASER ROOM ROUTE TO THE CORE"


func get_camera_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(facility_map.get_world_size()))


func spawn_player() -> PlayerController:
	var player := super.spawn_player()
	if player == null:
		return null
	player.configure_facility_view(
		get_camera_bounds(),
		player_camera_zoom,
		player_visibility_radius
	)
	visibility_controller.configure(player.get_visibility_probe())
	visibility_controller.set_enabled(false)
	refresh_visible_guard_status()
	return player


func spawn_ghost(recording: LoopRecording, source_loop_index: int) -> GhostPlayback:
	var ghost := super.spawn_ghost(recording, source_loop_index)
	if ghost != null:
		visibility_controller.register_target(ghost)
		visibility_controller.refresh_now()
	return ghost


func clear_runtime_actors() -> void:
	visibility_controller.set_enabled(false)
	visibility_controller.clear_runtime_targets()
	super.clear_runtime_actors()


func reset_objects_for_loop() -> void:
	visibility_controller.hide_all_immediately()
	super.reset_objects_for_loop()


func set_level_simulation_enabled(enabled: bool) -> void:
	super.set_level_simulation_enabled(enabled)
	if is_instance_valid(current_player):
		current_player.set_facility_visibility_enabled(enabled)
	visibility_controller.set_enabled(
		enabled and is_instance_valid(current_player)
	)
	if enabled:
		refresh_visible_guard_status()


func is_guard_information_visible(guard: GuardController) -> bool:
	return (
		is_instance_valid(visibility_controller)
		and visibility_controller.is_target_revealed(guard)
	)


func _register_static_visibility_targets() -> void:
	var targets: Array[Node2D] = [
		pressure_plate,
		security_door,
		laser_barrier,
		security_terminal,
		objective_item,
		exit_zone,
		security_camera,
	]
	for guard: GuardController in get_guards():
		targets.append(guard)
	for target: Node2D in targets:
		visibility_controller.register_target(target)


func _on_plate_active_changed(is_active: bool) -> void:
	security_door.set_open(is_active)
	if is_active:
		hint_changed.emit("VAULT PLATE ACTIVE — THE RED DOOR IS OPEN")


func _on_door_open_state_changed(is_open: bool) -> void:
	door_state_changed.emit(is_open)
	visibility_controller.refresh_now()


func _on_terminal_activated(_actor: Node) -> void:
	laser_barrier.set_active(false)
	hint_changed.emit("LASER GRID DISABLED — CROSS INTO THE CENTER CORRIDOR")


func _on_laser_tripped(player: PlayerController) -> void:
	if player != current_player:
		return
	hint_changed.emit("LASER TRIPPED — THIS TIMELINE WAS SAVED")
	player_captured.emit(player)


func _on_objective_collected(actor: Node) -> void:
	if actor != current_player:
		push_warning("Facility objective ignored collection from a non-live actor")
		return
	current_player.grant_objective()
	exit_zone.set_objective_available(true)
	objective_collected.emit()
	hint_changed.emit("TIME CORE SECURED — RETURN TO THE COURTYARD EXIT")


func _on_exit_requested(actor: Node) -> void:
	if actor == current_player:
		completion_requested.emit()


func _on_feedback_requested(message: String) -> void:
	hint_changed.emit(message)


func _on_target_visibility_changed(target: Node2D, _is_revealed: bool) -> void:
	if target is GuardController:
		refresh_visible_guard_status()
