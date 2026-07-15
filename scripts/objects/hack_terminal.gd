class_name HackTerminal
extends Interactable

signal hack_started(action_id: StringName, actor: Node)
signal hack_progressed(action_id: StringName, normalized_progress: float)
signal hack_completed(action_id: StringName, actor: Node)

const ACTION_PRESENTATION: Dictionary = {
	&"disable_cctv": {
		&"label": "CCTV NETWORK",
		&"code": "CAM",
		&"color": Color("55e5ee"),
	},
	&"disable_lasers": {
		&"label": "LASER GRID",
		&"code": "LZR",
		&"color": Color("ff9f43"),
	},
	&"server_override": {
		&"label": "VAULT OVERRIDE",
		&"code": "SVR",
		&"color": Color("b98cff"),
	},
	&"biometric_authorization": {
		&"label": "BIOMETRIC",
		&"code": "BIO",
		&"color": Color("d98cff"),
	},
	&"terminal_staff_intel_01": {
		&"label": "LOCKER INTEL",
		&"code": "DOC",
		&"color": Color("58d6ee"),
	},
	&"terminal_guard_distraction_01": {
		&"label": "DECOY BEACON",
		&"code": "DEC",
		&"color": Color("ffb34d"),
	},
	&"terminal_security_map_01": {
		&"label": "FACILITY MAP",
		&"code": "MAP",
		&"color": Color("61e3a5"),
	},
}
const DEFAULT_PRESENTATION: Dictionary = {
	&"label": "SECURITY SYSTEM",
	&"code": "SYS",
	&"color": Color("ffb34d"),
}

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
	var action_label := get_action_label()
	if is_completed:
		return "%s  COMPLETE" % action_label
	if _hacking_actor != null:
		return "%s  %d%%" % [
			action_label,
			roundi(100.0 * hack_elapsed / hack_duration_seconds),
		]
	if actor != null and actor.is_in_group(&"player_actor") and not _has_required_access():
		return "%s ACCESS REQUIRED  //  %s" % [
			AccessControlManager.ACCESS_NAMES.get(required_access, &"SECURITY"),
			action_label,
		]
	return "E  HACK %s  %.1fs" % [action_label, hack_duration_seconds]


func get_action_label() -> String:
	var presentation := _get_action_presentation()
	if presentation == DEFAULT_PRESENTATION and action_id != StringName():
		return String(action_id).to_upper().replace("_", " ")
	return String(presentation.get(&"label", "SECURITY SYSTEM"))


func get_action_code() -> String:
	return String(_get_action_presentation().get(&"code", "SYS"))


func get_action_color() -> Color:
	return _get_action_presentation().get(&"color", Color("ffb34d"))


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
	var snapshot_elapsed := clampf(
		float(snapshot.get("hack_elapsed", 0.0)),
		0.0,
		hack_duration_seconds
	)
	# Hack ownership is a live Node reference and is intentionally absent from a
	# Recall snapshot. Treat an incomplete hack as an uncommitted transaction and
	# restore it to an interactable 0% boundary instead of leaving inert progress
	# that neither the Player nor an Echo can own.
	hack_elapsed = snapshot_elapsed if is_completed else 0.0
	queue_redraw()
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _has_required_access() -> bool:
	if _access_manager == null:
		return required_access == AccessControlManager.AccessLevel.PUBLIC
	return _access_manager.can_access(required_access)


func _get_action_presentation() -> Dictionary:
	return ACTION_PRESENTATION.get(action_id, DEFAULT_PRESENTATION) as Dictionary


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
	var action_color := get_action_color()
	var accent := Color("4ce9a2") if is_completed else action_color
	draw_rect(Rect2(-21.0, -25.0, 42.0, 50.0), Color("071420"), true)
	draw_rect(Rect2(-20.0, -24.0, 40.0, 48.0), Color("13253a"), true)
	draw_rect(Rect2(-16.0, -19.0, 32.0, 24.0), Color(action_color, 0.18), true)
	draw_rect(Rect2(-16.0, -19.0, 32.0, 24.0), action_color, false, 1.5)
	_draw_action_glyph(action_id, action_color)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-15.0, 20.0),
		get_action_code(),
		HORIZONTAL_ALIGNMENT_CENTER,
		30.0,
		9,
		Color(action_color, 0.92)
	)
	var progress := 1.0 if is_completed else hack_elapsed / hack_duration_seconds
	draw_rect(Rect2(-14.0, 11.0, 28.0, 5.0), Color("07131f"), true)
	draw_rect(Rect2(-14.0, 11.0, 28.0 * progress, 5.0), accent, true)
	if is_completed:
		draw_line(Vector2(8.0, -10.0), Vector2(11.0, -6.0), accent, 2.0)
		draw_line(Vector2(11.0, -6.0), Vector2(16.0, -14.0), accent, 2.0)


func _draw_action_glyph(kind: StringName, color: Color) -> void:
	match kind:
		&"disable_cctv":
			draw_rect(Rect2(-10.0, -15.0, 20.0, 12.0), color, false, 2.0)
			draw_circle(Vector2(0.0, -9.0), 3.0, color)
			draw_line(Vector2(-4.0, 0.0), Vector2(4.0, 0.0), color, 2.0)
		&"disable_lasers":
			draw_polyline(
				PackedVector2Array([
					Vector2(-9.0, -5.0), Vector2(-3.0, -15.0),
					Vector2(0.0, -9.0), Vector2(7.0, -18.0),
					Vector2(3.0, -6.0), Vector2(10.0, -6.0),
				]),
				color,
				2.5
			)
		&"server_override":
			for y_offset: float in [-15.0, -10.0, -5.0]:
				draw_rect(Rect2(-10.0, y_offset, 20.0, 3.0), color, false, 1.5)
				draw_circle(Vector2(7.0, y_offset + 1.5), 1.0, color)
		&"biometric_authorization":
			draw_arc(Vector2(0.0, -10.0), 8.0, -2.8, -0.3, 12, color, 2.0)
			draw_arc(Vector2(0.0, -10.0), 4.0, -2.8, -0.3, 10, color, 1.5)
			draw_line(Vector2(-6.0, -3.0), Vector2(6.0, -3.0), color, 1.5)
		&"terminal_staff_intel_01":
			draw_rect(Rect2(-8.0, -17.0, 16.0, 15.0), color, false, 1.5)
			draw_line(Vector2(-5.0, -12.0), Vector2(5.0, -12.0), color, 1.5)
			draw_line(Vector2(-5.0, -8.0), Vector2(3.0, -8.0), color, 1.5)
		&"terminal_guard_distraction_01":
			draw_circle(Vector2(0.0, -8.0), 2.5, color)
			draw_arc(Vector2(0.0, -8.0), 7.0, -1.0, 1.0, 10, color, 1.5)
			draw_arc(Vector2(0.0, -8.0), 11.0, -0.8, 0.8, 10, color, 1.5)
		&"terminal_security_map_01":
			draw_rect(Rect2(-10.0, -17.0, 20.0, 15.0), color, false, 1.5)
			draw_line(Vector2(-3.0, -17.0), Vector2(-3.0, -2.0), color, 1.0)
			draw_line(Vector2(4.0, -17.0), Vector2(4.0, -2.0), color, 1.0)
			draw_line(Vector2(-10.0, -10.0), Vector2(10.0, -10.0), color, 1.0)
		_:
			draw_rect(Rect2(-9.0, -16.0, 18.0, 13.0), color, false, 1.5)
			draw_line(Vector2(-5.0, -11.0), Vector2(5.0, -11.0), color, 1.5)
			draw_line(Vector2(-5.0, -7.0), Vector2(2.0, -7.0), color, 1.5)
