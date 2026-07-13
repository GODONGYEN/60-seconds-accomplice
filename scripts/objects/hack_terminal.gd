class_name HackTerminal
extends Interactable

signal hack_started(action_id: StringName, actor: Node)
signal hack_progressed(action_id: StringName, normalized_progress: float)
signal hack_completed(action_id: StringName, actor: Node)

@export var action_id: StringName = &"disable_cctv"
@export_range(0.1, 10.0, 0.1) var hack_duration_seconds: float = 3.0
@export var echo_replay_allowed: bool = true
@export var required_access: AccessControlManager.AccessLevel = (
	AccessControlManager.AccessLevel.PUBLIC
)

var is_completed: bool = false
var hack_elapsed: float = 0.0

var _hacking_actor: Node = null
var _access_manager: AccessControlManager = null


func _ready() -> void:
	super._ready()
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	if is_completed or _hacking_actor == null or not is_instance_valid(_hacking_actor):
		_cancel_hack()
		return
	hack_elapsed = minf(hack_duration_seconds, hack_elapsed + maxf(0.0, delta))
	hack_progressed.emit(action_id, hack_elapsed / hack_duration_seconds)
	queue_redraw()
	if hack_elapsed >= hack_duration_seconds:
		_complete_hack()


func configure_access(
	access_manager: AccessControlManager,
	access_level: AccessControlManager.AccessLevel
) -> void:
	_access_manager = access_manager
	required_access = access_level


func can_interact(actor: Node) -> bool:
	if is_completed or _hacking_actor != null or actor == null:
		return false
	if actor.is_in_group(&"player_actor"):
		return _has_required_access()
	return echo_replay_allowed and actor.is_in_group(&"ghost_actor")


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	_hacking_actor = actor
	hack_elapsed = 0.0
	if actor.has_method(&"set_gameplay_input_enabled"):
		actor.call(&"set_gameplay_input_enabled", false)
	set_process(true)
	hack_started.emit(action_id, actor)
	queue_redraw()
	return true


func complete_hack_immediately() -> bool:
	if is_completed or _hacking_actor == null:
		return false
	hack_elapsed = hack_duration_seconds
	_complete_hack()
	return true


func get_interaction_prompt(actor: Node) -> String:
	if is_completed:
		return "%s COMPLETE" % String(action_id).to_upper().replace("_", " ")
	if _hacking_actor != null:
		return "HACKING  %d%%" % roundi(100.0 * hack_elapsed / hack_duration_seconds)
	if actor != null and actor.is_in_group(&"player_actor") and not _has_required_access():
		return "%s ACCESS REQUIRED" % AccessControlManager.ACCESS_NAMES.get(
			required_access,
			&"SECURITY"
		)
	return "E  HACK  %.1fs" % hack_duration_seconds


func reset_mission() -> void:
	_cancel_hack()
	is_completed = false
	hack_elapsed = 0.0
	queue_redraw()


func capture_recall_state() -> Dictionary:
	return {
		"is_completed": is_completed,
		"hack_elapsed": hack_elapsed,
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	_cancel_hack()
	is_completed = bool(snapshot.get("is_completed", false))
	hack_elapsed = clampf(
		float(snapshot.get("hack_elapsed", 0.0)),
		0.0,
		hack_duration_seconds
	)
	queue_redraw()
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _has_required_access() -> bool:
	if _access_manager == null:
		return required_access == AccessControlManager.AccessLevel.PUBLIC
	return _access_manager.can_access(required_access)


func _complete_hack() -> void:
	var actor := _hacking_actor
	is_completed = true
	_hacking_actor = null
	set_process(false)
	if actor != null and is_instance_valid(actor) and actor.has_method(&"set_gameplay_input_enabled"):
		actor.call(&"set_gameplay_input_enabled", true)
	hack_progressed.emit(action_id, 1.0)
	hack_completed.emit(action_id, actor)
	queue_redraw()


func _cancel_hack() -> void:
	if _hacking_actor != null and is_instance_valid(_hacking_actor):
		if _hacking_actor.has_method(&"set_gameplay_input_enabled"):
			_hacking_actor.call(&"set_gameplay_input_enabled", true)
	_hacking_actor = null
	set_process(false)


func _draw() -> void:
	var accent := Color("4ce9dc") if is_completed else Color("ffb34d")
	draw_rect(Rect2(-20.0, -24.0, 40.0, 48.0), Color("13253a"), true)
	draw_rect(Rect2(-15.0, -18.0, 30.0, 22.0), Color(accent, 0.22), true)
	var progress := 1.0 if is_completed else hack_elapsed / hack_duration_seconds
	draw_rect(Rect2(-14.0, 11.0, 28.0, 5.0), Color("07131f"), true)
	draw_rect(Rect2(-14.0, 11.0, 28.0 * progress, 5.0), accent, true)
