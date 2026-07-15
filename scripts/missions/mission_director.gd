class_name MissionDirector
extends Node

signal mission_started(mission_id: StringName)
signal mission_completed(mission_id: StringName)
signal mission_reset
signal primary_objective_changed(title: String)
signal objectives_changed(objective_ids: Array[StringName])
signal objective_completed(objective_id: StringName, title: String)
signal chronos_core_state_changed(is_carried: bool)
signal capture_decision_requested(can_recall: bool)

enum MissionState {
	BRIEFING,
	ACTIVE,
	CAPTURE_DECISION,
	COMPLETED,
}

const PRIMARY_TITLE: String = "STEAL THE CHRONOS CORE"
const OBJECTIVE_INFILTRATE: StringName = &"infiltrate_facility"
const OBJECTIVE_LEVEL_1: StringName = &"acquire_level_1_access"
const OBJECTIVE_CCTV: StringName = &"disable_cctv_network"
const OBJECTIVE_LASERS: StringName = &"disable_laser_network"
const OBJECTIVE_LEVEL_2: StringName = &"acquire_level_2_access"
const OBJECTIVE_BIOMETRIC: StringName = &"biometric_sample_acquired"
const OBJECTIVE_SERVER_OVERRIDE: StringName = &"server_override_completed"
const OBJECTIVE_VAULT_AUTH: StringName = &"vault_authorized"
const OBJECTIVE_ENTER_VAULT: StringName = &"enter_chronos_vault"
const OBJECTIVE_CORE: StringName = &"steal_chronos_core"
const OBJECTIVE_EXTRACT: StringName = &"return_to_extraction"

# These events describe one-shot world facts whose source can be consumed before its
# authored objective becomes available (for example, an early card pickup or Echo hack).
# Acquisition order is retained so simultaneous authorization branches resolve the
# same way after Recall and on every deterministic replay.
const LATCHABLE_EVENTS: Array[StringName] = [
	&"level_1_acquired",
	&"cctv_disabled",
	&"laser_disabled",
	&"level_2_acquired",
	&"biometric_authorization",
	&"server_override",
	&"vault_entered",
]

@export var mission_definition: MissionDefinition

var state: MissionState = MissionState.BRIEFING
var objective_graph: ObjectiveGraph = ObjectiveGraph.new()
var chronos_core_carried: bool = false

var _completion_emitted: bool = false
var _latched_events: Array[StringName] = []


func _ready() -> void:
	_build_objective_graph()
	objective_graph.objective_state_changed.connect(_on_objective_state_changed)
	reset_mission()


func begin_mission() -> bool:
	if mission_definition == null or not mission_definition.validate():
		push_error("MissionDirector cannot begin without a valid MissionDefinition")
		return false
	if not objective_graph.validate():
		return false
	state = MissionState.ACTIVE
	_completion_emitted = false
	_activate_actionable_objectives()
	primary_objective_changed.emit(PRIMARY_TITLE)
	objectives_changed.emit(get_current_objective_ids())
	mission_started.emit(mission_definition.mission_id)
	return true


func reset_mission() -> void:
	state = MissionState.BRIEFING
	chronos_core_carried = false
	_completion_emitted = false
	_latched_events.clear()
	objective_graph.initialize()
	chronos_core_state_changed.emit(false)
	mission_reset.emit()


func report_event(event_id: StringName) -> bool:
	if state != MissionState.ACTIVE:
		return false
	var objective_id := _objective_for_event(event_id)
	if objective_id == StringName():
		push_warning("MissionDirector ignored unknown event '%s'" % event_id)
		return false
	var current_state := objective_graph.get_state(objective_id)
	if (
		current_state == ObjectiveGraph.ObjectiveState.COMPLETED
		or current_state == ObjectiveGraph.ObjectiveState.FAILED
	):
		return false
	var is_latchable := _is_latchable_event(event_id)
	if is_latchable and not _latched_events.has(event_id):
		_latched_events.append(event_id)
	if not is_latchable and not _complete_objective(objective_id):
		# Chronos Core theft intentionally remains strict: reaching it before the
		# prerequisite chain never creates a deferred win condition.
		return false
	_reconcile_latched_events()
	_activate_actionable_objectives()
	objectives_changed.emit(get_current_objective_ids())
	return true


func request_extraction() -> bool:
	if not chronos_core_carried or state != MissionState.ACTIVE:
		return false
	if objective_graph.get_state(OBJECTIVE_EXTRACT) != ObjectiveGraph.ObjectiveState.COMPLETED:
		if not objective_graph.complete_objective(OBJECTIVE_EXTRACT):
			return false
	state = MissionState.COMPLETED
	if not _completion_emitted:
		_completion_emitted = true
		mission_completed.emit(mission_definition.mission_id)
	return true


func request_capture_decision(can_recall: bool) -> bool:
	if state != MissionState.ACTIVE:
		return false
	state = MissionState.CAPTURE_DECISION
	capture_decision_requested.emit(can_recall)
	return true


func resume_after_capture_decision() -> void:
	if state == MissionState.CAPTURE_DECISION:
		state = MissionState.ACTIVE


func get_current_objective_ids() -> Array[StringName]:
	var required: Array[StringName] = []
	var optional: Array[StringName] = []
	for objective_id: StringName in objective_graph.get_objective_ids():
		var objective_state := objective_graph.get_state(objective_id)
		if (
			objective_state != ObjectiveGraph.ObjectiveState.AVAILABLE
			and objective_state != ObjectiveGraph.ObjectiveState.ACTIVE
		):
			continue
		if objective_graph.is_optional(objective_id):
			optional.append(objective_id)
		else:
			required.append(objective_id)
	var result: Array[StringName] = []
	for objective_id: StringName in required:
		result.append(objective_id)
		if result.size() == 3:
			return result
	for objective_id: StringName in optional:
		result.append(objective_id)
		if result.size() == 3:
			break
	return result


func get_current_objective_lines() -> PackedStringArray:
	var result := PackedStringArray()
	for objective_id: StringName in get_current_objective_ids():
		result.append(objective_graph.get_title(objective_id))
	return result


func is_mission_active() -> bool:
	return state == MissionState.ACTIVE


func is_completed() -> bool:
	return state == MissionState.COMPLETED


func has_vault_authorization() -> bool:
	return (
		objective_graph.get_state(OBJECTIVE_VAULT_AUTH)
		== ObjectiveGraph.ObjectiveState.COMPLETED
	)


func get_vault_authorization_route() -> StringName:
	var used_biometric := (
		objective_graph.get_state(OBJECTIVE_BIOMETRIC)
		== ObjectiveGraph.ObjectiveState.COMPLETED
	)
	var used_server := (
		objective_graph.get_state(OBJECTIVE_SERVER_OVERRIDE)
		== ObjectiveGraph.ObjectiveState.COMPLETED
	)
	if used_biometric and used_server:
		return &"BIOMETRIC + SERVER"
	if used_biometric:
		return &"BIOMETRIC"
	if used_server:
		return &"SERVER OVERRIDE"
	return &"UNCONFIRMED"


func has_latched_event(event_id: StringName) -> bool:
	return _latched_events.has(event_id)


func get_latched_events() -> Array[StringName]:
	return _latched_events.duplicate()


func capture_recall_state() -> Dictionary:
	return {
		"mission_state": state,
		"chronos_core_carried": chronos_core_carried,
		"objective_graph": objective_graph.capture_state(),
		"latched_events": _latched_events.duplicate(),
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	if not snapshot.has("objective_graph"):
		return false
	state = clampi(
		int(snapshot.get("mission_state", MissionState.ACTIVE)),
		MissionState.BRIEFING,
		MissionState.COMPLETED
	) as MissionState
	# Recall can undo the Core theft, but never emits mission completion while restoring.
	_completion_emitted = state == MissionState.COMPLETED
	chronos_core_carried = bool(snapshot.get("chronos_core_carried", false))
	var restored := objective_graph.restore_state(snapshot.get("objective_graph", {}) as Dictionary)
	if restored:
		restored = _restore_latched_events(snapshot.get("latched_events", []))
	if restored and state == MissionState.ACTIVE:
		_reconcile_latched_events()
		_activate_actionable_objectives()
	chronos_core_state_changed.emit(chronos_core_carried)
	objectives_changed.emit(get_current_objective_ids())
	return restored


func get_recall_state_id() -> StringName:
	return &"mission_director"


func _build_objective_graph() -> void:
	objective_graph.add_objective(OBJECTIVE_INFILTRATE, "Enter the reception checkpoint")
	objective_graph.add_objective(
		OBJECTIVE_LEVEL_1,
		"Find a Level 1 access card in the locker room",
		[OBJECTIVE_INFILTRATE]
	)
	objective_graph.add_objective(
		OBJECTIVE_CCTV,
		"Disable CCTV from the control room (optional)",
		[OBJECTIVE_LEVEL_1],
		[],
		true
	)
	objective_graph.add_objective(
		OBJECTIVE_LASERS,
		"Shut down laser power in the electrical room",
		[OBJECTIVE_LEVEL_1]
	)
	objective_graph.add_objective(
		OBJECTIVE_LEVEL_2,
		"Acquire Level 2 access from the security office",
		[OBJECTIVE_LEVEL_1]
	)
	objective_graph.add_objective(
		OBJECTIVE_BIOMETRIC,
		"Acquire biometric authorization in the research lab",
		[OBJECTIVE_LEVEL_2],
		[],
		true
	)
	objective_graph.add_objective(
		OBJECTIVE_SERVER_OVERRIDE,
		"Generate temporary vault authorization in the server room",
		[OBJECTIVE_LEVEL_2],
		[],
		true
	)
	objective_graph.add_objective(
		OBJECTIVE_VAULT_AUTH,
		"Obtain vault authorization",
		[],
		[OBJECTIVE_BIOMETRIC, OBJECTIVE_SERVER_OVERRIDE]
	)
	objective_graph.add_objective(
		OBJECTIVE_ENTER_VAULT,
		"Enter the Chronos Vault",
		[OBJECTIVE_LASERS, OBJECTIVE_LEVEL_2, OBJECTIVE_VAULT_AUTH]
	)
	objective_graph.add_objective(
		OBJECTIVE_CORE,
		"Steal the Chronos Core",
		[OBJECTIVE_ENTER_VAULT]
	)
	objective_graph.add_objective(
		OBJECTIVE_EXTRACT,
		"Return to the external extraction point",
		[OBJECTIVE_CORE]
	)


func _objective_for_event(event_id: StringName) -> StringName:
	match event_id:
		&"facility_entered":
			return OBJECTIVE_INFILTRATE
		&"level_1_acquired":
			return OBJECTIVE_LEVEL_1
		&"cctv_disabled":
			return OBJECTIVE_CCTV
		&"laser_disabled":
			return OBJECTIVE_LASERS
		&"level_2_acquired":
			return OBJECTIVE_LEVEL_2
		&"biometric_authorization":
			return OBJECTIVE_BIOMETRIC
		&"server_override":
			return OBJECTIVE_SERVER_OVERRIDE
		&"vault_entered":
			return OBJECTIVE_ENTER_VAULT
		&"chronos_core_stolen":
			return OBJECTIVE_CORE
		_:
			return StringName()


func _activate_actionable_objectives() -> void:
	objective_graph.refresh_availability()
	for objective_id: StringName in get_current_objective_ids():
		if objective_graph.get_state(objective_id) == ObjectiveGraph.ObjectiveState.AVAILABLE:
			objective_graph.activate_objective(objective_id)


func _is_latchable_event(event_id: StringName) -> bool:
	return LATCHABLE_EVENTS.has(event_id)


func _complete_objective(objective_id: StringName) -> bool:
	if not objective_graph.complete_objective(objective_id):
		return false
	if objective_id == OBJECTIVE_BIOMETRIC or objective_id == OBJECTIVE_SERVER_OVERRIDE:
		_resolve_authorization_branch(objective_id)
	if objective_id == OBJECTIVE_CORE:
		chronos_core_carried = true
		chronos_core_state_changed.emit(true)
	return true


func _resolve_authorization_branch(completed_source: StringName) -> void:
	var unused_source := (
		OBJECTIVE_SERVER_OVERRIDE
		if completed_source == OBJECTIVE_BIOMETRIC
		else OBJECTIVE_BIOMETRIC
	)
	objective_graph.fail_objective(unused_source)
	var authorization_state := objective_graph.get_state(OBJECTIVE_VAULT_AUTH)
	if (
		authorization_state == ObjectiveGraph.ObjectiveState.AVAILABLE
		or authorization_state == ObjectiveGraph.ObjectiveState.ACTIVE
	):
		objective_graph.complete_objective(OBJECTIVE_VAULT_AUTH)


func _reconcile_latched_events() -> bool:
	var completed_any := false
	var made_progress := true
	while made_progress:
		made_progress = false
		objective_graph.refresh_availability()
		for event_id: StringName in _latched_events:
			var objective_id := _objective_for_event(event_id)
			var objective_state := objective_graph.get_state(objective_id)
			if (
				objective_state != ObjectiveGraph.ObjectiveState.AVAILABLE
				and objective_state != ObjectiveGraph.ObjectiveState.ACTIVE
			):
				continue
			if _complete_objective(objective_id):
				made_progress = true
				completed_any = true
	return completed_any


func _restore_latched_events(events_variant: Variant) -> bool:
	if not events_variant is Array:
		push_warning("MissionDirector rejected Recall state with invalid latched events")
		return false
	var restored_events: Array[StringName] = []
	for event_variant: Variant in events_variant as Array:
		var event_id := StringName(str(event_variant))
		if not _is_latchable_event(event_id):
			push_warning(
				"MissionDirector rejected unknown latched event '%s' during Recall" % event_id
			)
			return false
		if not restored_events.has(event_id):
			restored_events.append(event_id)
	_latched_events = restored_events
	return true


func _on_objective_state_changed(
	objective_id: StringName,
	_previous_state: ObjectiveGraph.ObjectiveState,
	current_state: ObjectiveGraph.ObjectiveState
) -> void:
	if current_state == ObjectiveGraph.ObjectiveState.COMPLETED:
		objective_completed.emit(objective_id, objective_graph.get_title(objective_id))
