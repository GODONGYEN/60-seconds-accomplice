class_name ChronoRecallManager
extends Node

signal charges_changed(remaining: int, maximum: int)
signal availability_changed(is_available: bool)
signal world_time_updated(world_time: float)
signal recall_started(from_world_time: float, to_world_time: float)
signal recall_restore_committed(to_world_time: float)
signal recall_completed(
	from_world_time: float,
	to_world_time: float,
	echo: GhostPlayback,
	succeeded: bool
)
signal recall_rejected(reason: String)
signal echo_spawned(echo: GhostPlayback, echo_sequence: int)
signal echo_removed(echo_sequence: int)
signal snapshot_failed(message: String)

const DEFAULT_ECHO_SCENE: PackedScene = preload("res://scenes/ghost/ghost.tscn")
const RECALL_HISTORY_SCRIPT: GDScript = preload("res://scripts/recording/recall_history.gd")
const REWIND_STATE_REGISTRY_SCRIPT: GDScript = preload(
	"res://scripts/recording/rewind_state_registry.gd"
)
const TIMESTAMP_EPSILON: float = 0.000001
const MAX_ACTOR_STATE_DEPTH: int = 16

enum RecallState {
	UNCONFIGURED,
	READY,
	RUNNING,
	RESTORING,
}

@export_range(1.0, 30.0, 0.5) var rewind_duration_seconds: float = 10.0
@export_range(1.0, 60.0, 1.0) var recording_frequency_hz: float = 20.0
@export_range(1, 10, 1) var maximum_charges: int = 3
@export_range(1, 3, 1) var maximum_echoes: int = 3
@export var automatic_physics_processing: bool = true
@export var echo_scene: PackedScene = DEFAULT_ECHO_SCENE

var remaining_charges: int = 3
var state: RecallState = RecallState.UNCONFIGURED

var _actor: Node2D = null
var _object_registry: ObjectRegistry = null
var _echo_parent: Node = null
var _history: RefCounted = RECALL_HISTORY_SCRIPT.new()
var _state_registry: RefCounted = REWIND_STATE_REGISTRY_SCRIPT.new()
var _world_snapshots: Array[Dictionary] = []
var _echoes: Array[GhostPlayback] = []
var _echo_spawn_times: Dictionary[int, float] = {}
var _echo_sequences: Dictionary[int, int] = {}
var _world_time: float = 0.0
var _world_snapshot_interval: float = 0.05
var _next_world_snapshot_time: float = 0.0
var _next_echo_sequence: int = 1
var _simulation_enabled: bool = false
var _last_availability: bool = false


func _ready() -> void:
	process_physics_priority = 110
	set_physics_process(false)
	_state_registry.snapshot_failed.connect(_on_registry_snapshot_failed)


func _exit_tree() -> void:
	clear_echoes()


func configure(
	actor: Node2D,
	object_registry: ObjectRegistry,
	echo_parent: Node,
	rewindable_root: Node = null,
	rewindable_group: StringName = &"recall_rewindable"
) -> bool:
	if actor == null or not is_instance_valid(actor):
		return _reject_configuration("ChronoRecallManager requires a valid Player actor.")
	if object_registry == null or not is_instance_valid(object_registry):
		return _reject_configuration("ChronoRecallManager requires a valid ObjectRegistry.")
	if echo_parent == null or not is_instance_valid(echo_parent):
		return _reject_configuration("ChronoRecallManager requires a valid Echo parent.")
	if rewind_duration_seconds <= 0.0 or recording_frequency_hz <= 0.0:
		return _reject_configuration("Chrono Recall duration and frequency must be positive.")
	if maximum_charges <= 0 or maximum_echoes <= 0:
		return _reject_configuration("Chrono Recall charges and Echo cap must be positive.")
	if echo_scene == null:
		return _reject_configuration("ChronoRecallManager requires an Echo scene.")
	if not _history.configure(recording_frequency_hz, rewind_duration_seconds):
		return false

	_actor = actor
	_object_registry = object_registry
	_echo_parent = echo_parent
	_world_snapshot_interval = 1.0 / recording_frequency_hz
	_state_registry.clear()
	if rewindable_root != null:
		if not _state_registry.rebuild_from_group(rewindable_root, rewindable_group):
			return _reject_configuration("Chrono Recall rewindable registry is invalid.")
		if not _state_registry.register_contracts_under(rewindable_root):
			return _reject_configuration("Chrono Recall state contract discovery failed.")
	if (
		_actor.has_method(&"capture_recall_state")
		or _actor.has_method(&"capture_rewind_state")
	):
		if not _state_registry.has_rewindable_node(_actor):
			if not _state_registry.register_rewindable(_actor):
				return _reject_configuration("Chrono Recall could not register the Player state.")
	state = RecallState.READY
	set_physics_process(false)
	return true


func begin_mission(start_world_time: float = 0.0) -> bool:
	if state == RecallState.UNCONFIGURED:
		return _reject("Chrono Recall cannot start before configure().")
	if start_world_time < 0.0:
		return _reject("Chrono Recall world time cannot be negative.")
	if _actor == null or not is_instance_valid(_actor):
		return _reject("Chrono Recall Player actor is no longer valid.")
	if not _state_registry.validate_registry():
		return _reject("Chrono Recall cannot start with an invalid rewindable registry.")
	clear_echoes()
	_world_time = start_world_time
	remaining_charges = maximum_charges
	_next_echo_sequence = 1
	_world_snapshots.clear()
	if not _history.begin_branch(_actor, _world_time):
		return false
	_capture_world_snapshot(_world_time)
	_next_world_snapshot_time = _world_time + _world_snapshot_interval
	state = RecallState.RUNNING
	_simulation_enabled = true
	set_physics_process(automatic_physics_processing)
	charges_changed.emit(remaining_charges, maximum_charges)
	world_time_updated.emit(_world_time)
	_emit_availability_if_changed(true)
	return true


func set_simulation_enabled(enabled: bool) -> void:
	_simulation_enabled = enabled
	set_physics_process(
		automatic_physics_processing
		and enabled
		and state == RecallState.RUNNING
	)
	_emit_availability_if_changed(true)


func is_simulation_enabled() -> bool:
	return _simulation_enabled


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if state != RecallState.RUNNING or not _simulation_enabled or delta <= 0.0:
		return
	_world_time += maxf(0.0, delta)
	_history.capture_until(_world_time)
	_capture_world_snapshots_until(_world_time)
	_advance_echoes()
	world_time_updated.emit(_world_time)
	_emit_availability_if_changed()


func record_interaction(
	target_id: StringName,
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	if state != RecallState.RUNNING or not _simulation_enabled:
		return false
	return _history.record_event(_world_time, target_id, event_type, payload)


func record_interaction_at(
	world_time: float,
	target_id: StringName,
	event_type: StringName,
	payload: Dictionary = {}
) -> bool:
	if state != RecallState.RUNNING or not _simulation_enabled:
		return false
	if world_time > _world_time + TIMESTAMP_EPSILON:
		return _reject("Chrono Recall cannot record an interaction from the future.")
	if world_time + TIMESTAMP_EPSILON < _history.get_newest_time():
		return _reject("Chrono Recall cannot append an interaction out of time order.")
	return _history.record_event(world_time, target_id, event_type, payload)


func request_recall() -> bool:
	if not can_recall():
		if state != RecallState.RUNNING:
			return _reject("Chrono Recall is not currently running.")
		if remaining_charges <= 0:
			return _reject("No Chrono Recall charges remain.")
		return _reject("Not enough recent history is available to Recall.")

	_history.capture_until(_world_time)
	var target_snapshot: Dictionary = _select_target_snapshot()
	if target_snapshot.is_empty():
		return _reject("Chrono Recall could not find a restorable world snapshot.")
	if not bool(target_snapshot.get("valid", false)):
		return _reject("Chrono Recall selected an invalid mission snapshot.")
	var registry_snapshot: Dictionary = target_snapshot.get("registry", {})
	if not _state_registry.can_restore_snapshot(registry_snapshot):
		return _reject("Chrono Recall snapshot no longer matches the mission world.")

	var from_world_time: float = _world_time
	var to_world_time: float = float(target_snapshot.get("timestamp", _world_time))
	var echo_sequence: int = _next_echo_sequence
	var recording: LoopRecording = _history.build_segment(
		to_world_time,
		from_world_time,
		echo_sequence
	)
	if recording.samples.is_empty() or recording.duration <= TIMESTAMP_EPSILON:
		return _reject("Chrono Recall history does not contain a playable segment.")

	state = RecallState.RESTORING
	set_physics_process(false)
	remaining_charges -= 1
	charges_changed.emit(remaining_charges, maximum_charges)
	_emit_availability_if_changed(true)
	recall_started.emit(from_world_time, to_world_time)

	var restored: bool = _state_registry.restore_snapshot(registry_snapshot)
	if restored:
		_restore_actor_state(target_snapshot.get("actor", {}))
		recall_restore_committed.emit(to_world_time)
	var echo: GhostPlayback = null
	if restored:
		echo = _spawn_echo(recording, echo_sequence)
		if echo == null:
			restored = false

	# World time deliberately remains monotonic. A Recall starts a new bounded
	# branch at the current clock, so a later Recall cannot cross this branch.
	_world_snapshots.clear()
	if not _history.begin_branch(_actor, _world_time):
		restored = false
	_capture_world_snapshot(_world_time)
	_next_world_snapshot_time = _world_time + _world_snapshot_interval
	state = RecallState.RUNNING
	set_physics_process(automatic_physics_processing and _simulation_enabled)
	recall_completed.emit(from_world_time, to_world_time, echo, restored)
	_emit_availability_if_changed(true)
	return restored


func restart_branch_from_current_state() -> bool:
	if state == RecallState.UNCONFIGURED or _actor == null or not is_instance_valid(_actor):
		return false
	_world_snapshots.clear()
	if not _history.begin_branch(_actor, _world_time):
		return false
	_capture_world_snapshot(_world_time)
	_next_world_snapshot_time = _world_time + _world_snapshot_interval
	_emit_availability_if_changed(true)
	return true


func register_rewindable(node: Node) -> bool:
	var registered: bool = _state_registry.register_rewindable(node)
	if registered and state == RecallState.RUNNING:
		restart_branch_from_current_state()
	return registered


func unregister_rewindable(rewind_id: StringName, expected_node: Node = null) -> bool:
	var unregistered: bool = _state_registry.unregister_rewindable(rewind_id, expected_node)
	if unregistered and state == RecallState.RUNNING:
		restart_branch_from_current_state()
	return unregistered


func can_recall() -> bool:
	return (
		state == RecallState.RUNNING
		and _simulation_enabled
		and remaining_charges > 0
		and _history.get_available_duration() + TIMESTAMP_EPSILON >= _world_snapshot_interval
		and not _world_snapshots.is_empty()
	)


func get_world_time() -> float:
	return _world_time


func get_history() -> RefCounted:
	return _history


func get_state_registry() -> RefCounted:
	return _state_registry


func get_world_snapshot_count() -> int:
	return _world_snapshots.size()


func get_echo_count() -> int:
	_prune_invalid_echoes()
	return _echoes.size()


func get_echoes() -> Array[GhostPlayback]:
	_prune_invalid_echoes()
	return _echoes.duplicate()


func clear_echoes() -> void:
	for echo: GhostPlayback in _echoes:
		_remove_echo_node(echo, false)
	_echoes.clear()
	_echo_spawn_times.clear()
	_echo_sequences.clear()


func _capture_world_snapshots_until(target_world_time: float) -> void:
	while _next_world_snapshot_time <= target_world_time + TIMESTAMP_EPSILON:
		_capture_world_snapshot(_next_world_snapshot_time)
		_next_world_snapshot_time += _world_snapshot_interval
	var cutoff: float = target_world_time - rewind_duration_seconds
	while (
		_world_snapshots.size() > 1
		and float(_world_snapshots[0].get("timestamp", 0.0)) < cutoff - TIMESTAMP_EPSILON
	):
		_world_snapshots.remove_at(0)


func _capture_world_snapshot(timestamp: float) -> void:
	var registry_snapshot: Dictionary = _state_registry.capture_snapshot(timestamp)
	var actor_state: Dictionary = _capture_actor_state()
	var snapshot: Dictionary = {
		"timestamp": timestamp,
		"registry": registry_snapshot,
		"actor": actor_state,
		"valid": (
			bool(registry_snapshot.get("valid", false))
			and bool(actor_state.get("valid", false))
		),
	}
	_world_snapshots.append(snapshot)
	if not bool(snapshot["valid"]):
		snapshot_failed.emit("Chrono Recall captured an invalid mission snapshot.")


func _select_target_snapshot() -> Dictionary:
	if _world_snapshots.is_empty():
		return {}
	var desired_time: float = maxf(
		_history.get_branch_start_time(),
		_world_time - rewind_duration_seconds
	)
	var selected: Dictionary = _world_snapshots[0]
	for snapshot: Dictionary in _world_snapshots:
		var snapshot_time: float = float(snapshot.get("timestamp", 0.0))
		if snapshot_time > desired_time + TIMESTAMP_EPSILON:
			break
		selected = snapshot
	return selected


func _capture_actor_state() -> Dictionary:
	if _actor == null or not is_instance_valid(_actor):
		return {}
	var actor_state: Dictionary = {
		"position": _actor.global_position,
		"rotation": _actor.global_rotation,
		"valid": true,
	}
	if _actor is CharacterBody2D:
		actor_state["velocity"] = (_actor as CharacterBody2D).velocity
	if _actor.has_method(&"capture_chrono_actor_state"):
		var extended_state: Variant = _actor.call(&"capture_chrono_actor_state")
		if typeof(extended_state) == TYPE_DICTIONARY:
			var typed_extended_state: Dictionary = extended_state
			if _contains_object_reference(typed_extended_state):
				actor_state["valid"] = false
				snapshot_failed.emit(
					"Chrono Recall Player state contains an Object reference."
				)
			else:
				actor_state["extended"] = typed_extended_state.duplicate(true)
	return actor_state


func _restore_actor_state(actor_state_value: Variant) -> void:
	if _actor == null or not is_instance_valid(_actor):
		return
	if typeof(actor_state_value) != TYPE_DICTIONARY:
		return
	var actor_state: Dictionary = actor_state_value
	var position_value: Variant = actor_state.get("position", _actor.global_position)
	if typeof(position_value) == TYPE_VECTOR2:
		_actor.global_position = position_value
	var rotation_value: Variant = actor_state.get("rotation", _actor.global_rotation)
	if typeof(rotation_value) == TYPE_FLOAT or typeof(rotation_value) == TYPE_INT:
		_actor.global_rotation = float(rotation_value)
	if _actor is CharacterBody2D:
		var velocity_value: Variant = actor_state.get("velocity", Vector2.ZERO)
		if typeof(velocity_value) == TYPE_VECTOR2:
			(_actor as CharacterBody2D).velocity = velocity_value
	if _actor.has_method(&"restore_chrono_actor_state"):
		var extended_value: Variant = actor_state.get("extended", {})
		if typeof(extended_value) == TYPE_DICTIONARY:
			_actor.call(
				&"restore_chrono_actor_state",
				(extended_value as Dictionary).duplicate(true)
			)


func _spawn_echo(recording: LoopRecording, sequence: int) -> GhostPlayback:
	if echo_scene == null or _echo_parent == null or not is_instance_valid(_echo_parent):
		return null
	_prune_invalid_echoes()
	while _echoes.size() >= maximum_echoes:
		_remove_oldest_echo()
	var echo := echo_scene.instantiate() as GhostPlayback
	if echo == null:
		push_error("Chrono Recall Echo scene root must be GhostPlayback.")
		return null
	_echo_parent.add_child(echo)
	var configured: bool = (
		echo.configure_echo_segment(recording, _object_registry, sequence)
		if echo.has_method(&"configure_echo_segment")
		else echo.configure(recording, _object_registry, sequence)
	)
	if not configured:
		_echo_parent.remove_child(echo)
		echo.queue_free()
		return null
	echo.reset_playback()
	echo.advance_to(0.0)
	_echoes.append(echo)
	_echo_spawn_times[echo.get_instance_id()] = _world_time
	_echo_sequences[echo.get_instance_id()] = sequence
	_next_echo_sequence = sequence + 1
	echo_spawned.emit(echo, sequence)
	return echo


func _advance_echoes() -> void:
	_prune_invalid_echoes()
	for echo: GhostPlayback in _echoes:
		var spawn_time: float = _echo_spawn_times.get(echo.get_instance_id(), _world_time)
		echo.advance_to(maxf(0.0, _world_time - spawn_time))


func _remove_oldest_echo() -> void:
	if _echoes.is_empty():
		return
	var oldest: GhostPlayback = _echoes.pop_front()
	_remove_echo_node(oldest, true)


func _remove_echo_node(echo: GhostPlayback, emit_removal: bool) -> void:
	if echo == null or not is_instance_valid(echo):
		return
	var instance_id: int = echo.get_instance_id()
	var sequence: int = _echo_sequences.get(instance_id, 0)
	_echo_spawn_times.erase(instance_id)
	_echo_sequences.erase(instance_id)
	echo.collision_layer = 0
	echo.visible = false
	echo.queue_free()
	if emit_removal:
		echo_removed.emit(sequence)


func _prune_invalid_echoes() -> void:
	for index: int in range(_echoes.size() - 1, -1, -1):
		var echo: GhostPlayback = _echoes[index]
		if is_instance_valid(echo):
			continue
		_echoes.remove_at(index)
	var live_ids: Dictionary[int, bool] = {}
	for echo: GhostPlayback in _echoes:
		live_ids[echo.get_instance_id()] = true
	for instance_id: int in _echo_spawn_times.keys():
		if not live_ids.has(instance_id):
			_echo_spawn_times.erase(instance_id)
			_echo_sequences.erase(instance_id)


func _emit_availability_if_changed(force: bool = false) -> void:
	var available: bool = can_recall()
	if not force and available == _last_availability:
		return
	_last_availability = available
	availability_changed.emit(available)


func _reject(message: String) -> bool:
	recall_rejected.emit(message)
	return false


func _reject_configuration(message: String) -> bool:
	push_error(message)
	state = RecallState.UNCONFIGURED
	set_physics_process(false)
	return false


func _on_registry_snapshot_failed(message: String) -> void:
	snapshot_failed.emit(message)


static func _contains_object_reference(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_ACTOR_STATE_DEPTH:
		return true
	match typeof(value):
		TYPE_OBJECT:
			return value != null
		TYPE_ARRAY:
			var array_values: Array = value
			for item: Variant in array_values:
				if _contains_object_reference(item, depth + 1):
					return true
		TYPE_DICTIONARY:
			var dictionary_values: Dictionary = value
			for key: Variant in dictionary_values:
				if _contains_object_reference(key, depth + 1):
					return true
				if _contains_object_reference(dictionary_values[key], depth + 1):
					return true
	return false
