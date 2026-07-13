class_name AccessDoor
extends Interactable

signal open_state_changed(is_open: bool)
signal access_denied(required_level: AccessControlManager.AccessLevel)

const CLOSED_COLOR := Color("dc5268")
const OPEN_COLOR := Color("36e2c4")
const LOCKED_COLOR := Color("ffad42")

@export var required_access: AccessControlManager.AccessLevel = AccessControlManager.AccessLevel.PUBLIC
@export var requires_vault_authorization: bool = false
@export var starts_open: bool = false

@onready var blocker: CollisionShape2D = %Blocker
@onready var light_occluder: LightOccluder2D = %LightOccluder2D

var is_open: bool = false
var is_unlocked: bool = false

var _access_manager: AccessControlManager = null
var _authorization_check: Callable
var _authorization_denied_message: String = "VAULT AUTHORIZATION REQUIRED"


func _ready() -> void:
	super._ready()
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	_apply_state(starts_open, starts_open, true)


func configure(
	access_manager: AccessControlManager,
	authorization_check: Callable = Callable(),
	authorization_denied_message: String = "VAULT AUTHORIZATION REQUIRED"
) -> void:
	_access_manager = access_manager
	_authorization_check = authorization_check
	_authorization_denied_message = authorization_denied_message


func can_interact(actor: Node) -> bool:
	if actor == null or is_open:
		return false
	if actor.is_in_group(&"ghost_actor"):
		return is_unlocked
	if not actor.is_in_group(&"player_actor"):
		return false
	return _is_authorized(false)


func interact(actor: Node) -> bool:
	if actor == null or is_open:
		return false
	if actor.is_in_group(&"ghost_actor"):
		if not is_unlocked:
			return false
		_apply_state(true, true)
		return true
	if not _is_authorized(true):
		return false
	_apply_state(true, true)
	return true


func replay_event(event_type: StringName, actor: Node, payload: Dictionary) -> bool:
	if event_type != &"interact" or actor == null or not actor.is_in_group(&"ghost_actor"):
		return false
	if not bool(payload.get("authorized", false)):
		return false
	# The replayed event proves the abandoned timeline had authorization. It opens
	# the physical door but never grants credentials to the current Player.
	_apply_state(true, true)
	return true


func get_recording_payload(_actor: Node) -> Dictionary:
	return {
		"authorized": is_unlocked or is_open,
		"required_access": required_access,
	}


func get_interaction_prompt(actor: Node) -> String:
	if is_open:
		return "DOOR OPEN"
	if actor != null and actor.is_in_group(&"player_actor") and not _is_authorized(false):
		if _requires_extra_authorization() and not _has_extra_authorization():
			return _authorization_denied_message
		return "%s ACCESS REQUIRED" % AccessControlManager.ACCESS_NAMES.get(
			required_access,
			&"SECURITY"
		)
	return "E  OPEN SECURITY DOOR"


func close() -> void:
	_apply_state(false, is_unlocked)


func unlock_and_open() -> void:
	_apply_state(true, true)


func reset_mission() -> void:
	_apply_state(starts_open, starts_open, true)


func capture_recall_state() -> Dictionary:
	return {"is_open": is_open, "is_unlocked": is_unlocked}


func restore_recall_state(snapshot: Dictionary) -> bool:
	_apply_state(
		bool(snapshot.get("is_open", false)),
		bool(snapshot.get("is_unlocked", false)),
		true
	)
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _is_authorized(report_denial: bool) -> bool:
	var access_granted := (
		_access_manager != null
		and _access_manager.can_access(required_access)
	)
	var extra_authorization_granted := (
		not _requires_extra_authorization() or _has_extra_authorization()
	)
	if access_granted and extra_authorization_granted:
		return true
	if report_denial:
		if _access_manager != null:
			_access_manager.authorize(object_id, required_access)
		access_denied.emit(required_access)
	return false


func _requires_extra_authorization() -> bool:
	return requires_vault_authorization or _authorization_check.is_valid()


func _has_extra_authorization() -> bool:
	return _authorization_check.is_valid() and bool(_authorization_check.call())


func _apply_state(open_value: bool, unlocked_value: bool, force: bool = false) -> void:
	var changed := is_open != open_value
	is_open = open_value
	is_unlocked = unlocked_value
	blocker.set_deferred(&"disabled", is_open)
	light_occluder.visible = not is_open
	queue_redraw()
	if changed or force:
		open_state_changed.emit(is_open)


func _draw() -> void:
	var panel_color := OPEN_COLOR if is_open else (LOCKED_COLOR if is_unlocked else CLOSED_COLOR)
	draw_rect(Rect2(-16.0, -48.0, 32.0, 96.0), Color("26384c"), true)
	if is_open:
		draw_rect(Rect2(-16.0, -48.0, 7.0, 96.0), panel_color, true)
		draw_rect(Rect2(9.0, -48.0, 7.0, 96.0), panel_color, true)
	else:
		draw_rect(Rect2(-12.0, -43.0, 24.0, 86.0), panel_color, true)
		draw_string(ThemeDB.fallback_font, Vector2(-7.0, 5.0), "L%d" % required_access)
