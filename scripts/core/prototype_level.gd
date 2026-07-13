class_name PrototypeLevel
extends Node2D

signal objective_collected
signal completion_requested
signal hint_changed(message: String)
signal interaction_prompt_changed(message: String)
signal door_state_changed(is_open: bool)
signal player_captured(player: PlayerController)
signal guard_status_changed(state_name: StringName, suspicion: float, target_id: StringName)
signal guard_state_changed(state_name: StringName)

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GHOST_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")

@onready var player_spawn: Marker2D = %PlayerSpawn
@onready var player_container: Node2D = %PlayerContainer
@onready var ghost_container: Node2D = %GhostContainer
@onready var object_registry: ObjectRegistry = %ObjectRegistry
@onready var pressure_plate: PressurePlate = %PressurePlate
@onready var security_door: SecurityDoor = %SecurityDoor
@onready var objective_item: ObjectiveItem = %ObjectiveItem
@onready var exit_zone: ExitZone = %ExitZone
@onready var training_guard: GuardController = %TrainingGuard
@onready var guard_patrol_route: Node2D = %GuardPatrolRoute

var current_player: PlayerController = null
var _resettables: Array[Node] = []
var _is_initialized: bool = false
var _shown_player_detection_hint: bool = false
var _shown_ghost_detection_hint: bool = false


func _ready() -> void:
	pressure_plate.active_changed.connect(_on_plate_active_changed)
	security_door.open_state_changed.connect(_on_door_open_state_changed)
	objective_item.collected.connect(_on_objective_collected)
	exit_zone.exit_requested.connect(_on_exit_requested)
	exit_zone.feedback_requested.connect(_on_feedback_requested)
	training_guard.capture_requested.connect(_on_guard_capture_requested)
	training_guard.status_changed.connect(_on_guard_status_changed)
	training_guard.state_changed.connect(_on_guard_state_changed)
	_cache_resettables()
	_is_initialized = object_registry.rebuild(self)
	queue_redraw()


func validate_level() -> bool:
	if not _is_initialized:
		push_error("PrototypeLevel initialization failed: stable object registry is invalid")
		return false
	if player_spawn == null:
		push_error("PrototypeLevel requires a PlayerSpawn node")
		return false
	if PLAYER_SCENE == null or GHOST_SCENE == null:
		push_error("PrototypeLevel requires Player and Ghost scenes")
		return false
	if not training_guard.has_valid_patrol_route():
		push_error("PrototypeLevel requires at least two authored Guard patrol points")
		return false
	return object_registry.validate_registry()


func clear_runtime_actors() -> void:
	current_player = null
	for child: Node in player_container.get_children():
		child.free()
	for child: Node in ghost_container.get_children():
		child.free()


func reset_objects_for_loop() -> void:
	for resettable: Node in _resettables:
		if is_instance_valid(resettable) and resettable.has_method("reset_for_loop"):
			resettable.call("reset_for_loop")


func rebuild_and_validate_registry() -> bool:
	return object_registry.rebuild(self) and object_registry.validate_registry()


func spawn_player() -> PlayerController:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	if player == null:
		push_error("Player scene root must be PlayerController")
		return null
	player_container.add_child(player)
	player.initialize_at(player_spawn.global_position)
	player.interaction_prompt_changed.connect(_on_interaction_prompt_changed)
	current_player = player
	return player


func spawn_ghost(
	recording: LoopRecording,
	source_loop_index: int
) -> GhostPlayback:
	var ghost := GHOST_SCENE.instantiate() as GhostPlayback
	if ghost == null:
		push_error("Ghost scene root must be GhostPlayback")
		return null
	ghost_container.add_child(ghost)
	ghost.configure(recording, object_registry, source_loop_index)
	return ghost


func set_live_input_enabled(enabled: bool) -> void:
	if is_instance_valid(current_player):
		current_player.set_gameplay_input_enabled(enabled)


func set_level_simulation_enabled(enabled: bool) -> void:
	if is_instance_valid(training_guard):
		training_guard.set_simulation_enabled(enabled)


func get_registry() -> ObjectRegistry:
	return object_registry


func get_ghost_count() -> int:
	return ghost_container.get_child_count()


func _cache_resettables() -> void:
	_resettables.clear()
	for candidate: Node in get_tree().get_nodes_in_group("loop_resettable"):
		if candidate == self or is_ancestor_of(candidate):
			_resettables.append(candidate)


func _on_plate_active_changed(is_active: bool) -> void:
	security_door.set_open(is_active)
	if is_active:
		hint_changed.emit("PLATE ACTIVE — THE VAULT DOOR IS OPEN")


func _on_door_open_state_changed(is_open: bool) -> void:
	door_state_changed.emit(is_open)


func _on_objective_collected(actor: Node) -> void:
	if actor != current_player:
		push_warning("Objective ignored collection from a non-live actor")
		return
	current_player.grant_objective()
	exit_zone.set_objective_available(true)
	objective_collected.emit()
	hint_changed.emit("TIME CORE SECURED — REACH THE CYAN EXIT")


func _on_exit_requested(actor: Node) -> void:
	if actor != current_player:
		return
	completion_requested.emit()


func _on_feedback_requested(message: String) -> void:
	hint_changed.emit(message)


func _on_interaction_prompt_changed(message: String) -> void:
	interaction_prompt_changed.emit(message)


func _on_guard_capture_requested(player: PlayerController) -> void:
	if player != current_player:
		push_warning("Guard ignored capture request for a non-live Player")
		return
	hint_changed.emit("CAUGHT — THIS TIMELINE WAS SAVED")
	player_captured.emit(player)


func _on_guard_status_changed(
	state_name: StringName,
	suspicion: float,
	target_id: StringName
) -> void:
	guard_status_changed.emit(state_name, suspicion, target_id)
	if state_name != &"suspicious":
		return
	if target_id == PlayerController.DETECTION_ID and not _shown_player_detection_hint:
		_shown_player_detection_hint = true
		hint_changed.emit("SEEN — BREAK LINE OF SIGHT OR LEAD THE GUARD UP TOP")
	elif String(target_id).begins_with("ghost_") and not _shown_ghost_detection_hint:
		_shown_ghost_detection_hint = true
		hint_changed.emit("YOUR GHOST IS DISTRACTING THE GUARD — TAKE THE LOWER LANE")


func _on_guard_state_changed(
	_previous_state: GuardController.GuardState,
	current_state: GuardController.GuardState
) -> void:
	guard_state_changed.emit(StringName(GuardController.STATE_NAMES.get(current_state, &"unknown")))


func _draw() -> void:
	draw_rect(Rect2(160.0, 128.0, 960.0, 512.0), Color("4b6780"), false, 3.0)
	draw_dashed_line(
		pressure_plate.position + Vector2(52.0, 0.0),
		security_door.position - Vector2(28.0, 0.0),
		Color("ffd76a"),
		3.0,
		10.0
	)
	var patrol_points: Array[Vector2] = []
	for child: Node in guard_patrol_route.get_children():
		if child is Marker2D:
			patrol_points.append((child as Marker2D).position)
	if patrol_points.size() >= 2:
		draw_dashed_line(
			guard_patrol_route.position + patrol_points[0],
			guard_patrol_route.position + patrol_points[1],
			Color(1.0, 0.52, 0.2, 0.55),
			2.0,
			8.0
		)
