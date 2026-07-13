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

@export var mission_definition: MissionDefinition

var state: MissionState = MissionState.BRIEFING
var objective_graph: ObjectiveGraph = ObjectiveGraph.new()
var chronos_core_carried: bool = false

var _completion_emitted: bool = false


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
	if not objective_graph.complete_objective(objective_id):
		return false
	if objective_id == OBJECTIVE_BIOMETRIC or objective_id == OBJECTIVE_SERVER_OVERRIDE:
		if objective_graph.get_state(OBJECTIVE_VAULT_AUTH) == ObjectiveGraph.ObjectiveState.AVAILABLE:
			objective_graph.complete_objective(OBJECTIVE_VAULT_AUTH)
	if objective_id == OBJECTIVE_CORE:
		chronos_core_carried = true
		chronos_core_state_changed.emit(true)
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
	return objective_graph.get_actionable_objectives(3)


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


func capture_recall_state() -> Dictionary:
	return {
		"mission_state": state,
		"chronos_core_carried": chronos_core_carried,
		"objective_graph": objective_graph.capture_state(),
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
	for objective_id: StringName in objective_graph.get_actionable_objectives(3):
		if objective_graph.get_state(objective_id) == ObjectiveGraph.ObjectiveState.AVAILABLE:
			objective_graph.activate_objective(objective_id)


func _on_objective_state_changed(
	objective_id: StringName,
	_previous_state: ObjectiveGraph.ObjectiveState,
	current_state: ObjectiveGraph.ObjectiveState
) -> void:
	if current_state == ObjectiveGraph.ObjectiveState.COMPLETED:
		objective_completed.emit(objective_id, objective_graph.get_title(objective_id))
