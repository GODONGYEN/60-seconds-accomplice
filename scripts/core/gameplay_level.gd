class_name GameplayLevel
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

@export_range(1.0, 120.0, 1.0) var level_loop_duration_seconds: float = 20.0

@onready var player_spawn: Marker2D = %PlayerSpawn
@onready var player_container: Node2D = %PlayerContainer
@onready var ghost_container: Node2D = %GhostContainer
@onready var object_registry: ObjectRegistry = %ObjectRegistry

var current_player: PlayerController = null

var _resettables: Array[Node] = []
var _guards: Array[GuardController] = []
var _is_initialized: bool = false


func _ready() -> void:
	_cache_runtime_contracts()
	_connect_guard_signals()
	_is_initialized = object_registry.rebuild(self)


func validate_level() -> bool:
	if not _is_initialized:
		push_error("%s initialization failed: stable object registry is invalid" % name)
		return false
	if level_loop_duration_seconds <= 0.0:
		push_error("%s loop duration must be greater than zero" % name)
		return false
	if player_spawn == null:
		push_error("%s requires a PlayerSpawn node" % name)
		return false
	if PLAYER_SCENE == null or GHOST_SCENE == null:
		push_error("%s requires Player and Ghost scenes" % name)
		return false
	if _guards.is_empty():
		push_error("%s requires at least one Guard" % name)
		return false
	for guard: GuardController in _guards:
		if not guard.has_valid_patrol_route():
			push_error(
				"%s Guard '%s' requires at least two authored patrol points"
				% [name, guard.get_object_id()]
			)
			return false
	return object_registry.validate_registry()


func get_loop_duration_seconds() -> float:
	return level_loop_duration_seconds


func get_loop_hint(loop_index: int) -> String:
	return "BUILD A ROUTE FOR YOUR GHOST" if loop_index <= 1 else "WORK WITH YOUR GHOST"


func clear_runtime_actors() -> void:
	current_player = null
	for child: Node in player_container.get_children():
		child.free()
	for child: Node in ghost_container.get_children():
		child.free()


func reset_objects_for_loop() -> void:
	for resettable: Node in _resettables:
		if is_instance_valid(resettable) and resettable.has_method(&"reset_for_loop"):
			resettable.call(&"reset_for_loop")


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


func spawn_ghost(recording: LoopRecording, source_loop_index: int) -> GhostPlayback:
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
	for guard: GuardController in _guards:
		if is_instance_valid(guard):
			guard.set_simulation_enabled(enabled)


func get_registry() -> ObjectRegistry:
	return object_registry


func get_ghost_count() -> int:
	return ghost_container.get_child_count()


func get_guards() -> Array[GuardController]:
	return _guards.duplicate()


func is_guard_information_visible(_guard: GuardController) -> bool:
	return true


func refresh_visible_guard_status() -> void:
	var visible_guards: Array[GuardController] = []
	for guard: GuardController in _guards:
		if is_instance_valid(guard) and is_guard_information_visible(guard):
			visible_guards.append(guard)
	visible_guards.sort_custom(
		func(left: GuardController, right: GuardController) -> bool:
			return String(left.get_object_id()) < String(right.get_object_id())
	)
	if visible_guards.is_empty():
		guard_status_changed.emit(&"hidden", 0.0, StringName())
		return
	var guard: GuardController = visible_guards[0]
	guard_status_changed.emit(
		guard.get_state_name(),
		guard.suspicion,
		guard.get_current_target_id()
	)


func _cache_runtime_contracts() -> void:
	_resettables.clear()
	_guards.clear()
	for candidate: Node in get_tree().get_nodes_in_group(&"loop_resettable"):
		if candidate == self or is_ancestor_of(candidate):
			_resettables.append(candidate)
	for candidate: Node in get_tree().get_nodes_in_group(&"guard_actor"):
		if candidate is GuardController and is_ancestor_of(candidate):
			_guards.append(candidate as GuardController)
	_guards.sort_custom(
		func(left: GuardController, right: GuardController) -> bool:
			return String(left.get_object_id()) < String(right.get_object_id())
	)


func _connect_guard_signals() -> void:
	for guard: GuardController in _guards:
		if not guard.capture_requested.is_connected(_on_guard_capture_requested):
			guard.capture_requested.connect(_on_guard_capture_requested)
		var status_callback := _on_guard_status_changed.bind(guard)
		if not guard.status_changed.is_connected(status_callback):
			guard.status_changed.connect(status_callback)
		var state_callback := _on_guard_state_changed.bind(guard)
		if not guard.state_changed.is_connected(state_callback):
			guard.state_changed.connect(state_callback)


func _on_interaction_prompt_changed(message: String) -> void:
	interaction_prompt_changed.emit(message)


func _on_guard_capture_requested(player: PlayerController) -> void:
	if player != current_player:
		push_warning("%s ignored capture request for a non-live Player" % name)
		return
	hint_changed.emit("CAUGHT — THIS TIMELINE WAS SAVED")
	player_captured.emit(player)


func _on_guard_status_changed(
	state_name: StringName,
	suspicion: float,
	target_id: StringName,
	guard: GuardController
) -> void:
	if not is_guard_information_visible(guard):
		return
	guard_status_changed.emit(state_name, suspicion, target_id)


func _on_guard_state_changed(
	_previous_state: GuardController.GuardState,
	current_state: GuardController.GuardState,
	guard: GuardController
) -> void:
	if not is_guard_information_visible(guard):
		return
	guard_state_changed.emit(StringName(GuardController.STATE_NAMES.get(current_state, &"unknown")))
