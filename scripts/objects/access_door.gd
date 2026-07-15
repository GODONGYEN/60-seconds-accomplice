class_name AccessDoor
extends Interactable

signal open_state_changed(is_open: bool)
signal access_denied(required_level: AccessControlManager.AccessLevel)

const CLOSED_COLOR := Color("dc5268")
const OPEN_COLOR := Color("36e2c4")
const LOCKED_COLOR := Color("ffad42")
const FRAME_DARK := Color("07111d")
const FRAME_MID := Color("122638")
const FRAME_LIGHT := Color("33556d")
const ACCESS_COLORS: Dictionary = {
	AccessControlManager.AccessLevel.PUBLIC: Color("30dde3"),
	AccessControlManager.AccessLevel.LEVEL_1: Color("e6a83a"),
	AccessControlManager.AccessLevel.LEVEL_2: Color("d9565f"),
	AccessControlManager.AccessLevel.VAULT: Color("a77bff"),
}

@export var required_access: AccessControlManager.AccessLevel = AccessControlManager.AccessLevel.PUBLIC
@export var requires_vault_authorization: bool = false
@export var starts_open: bool = false
@export_range(32.0, 192.0, 32.0) var span_length_pixels: float = 96.0

@onready var interaction_shape: CollisionShape2D = %InteractionShape
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
	_configure_geometry()
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


func configure_span_length(length_pixels: float) -> void:
	span_length_pixels = clampf(roundf(length_pixels), 32.0, 192.0)
	if is_node_ready():
		_configure_geometry()
		queue_redraw()


func get_span_length_pixels() -> float:
	return span_length_pixels


func get_blocker_size() -> Vector2:
	var rectangle := blocker.shape as RectangleShape2D
	return rectangle.size if rectangle != null else Vector2.ZERO


func get_interaction_size() -> Vector2:
	var rectangle := interaction_shape.shape as RectangleShape2D
	return rectangle.size if rectangle != null else Vector2.ZERO


func get_occluder_size() -> Vector2:
	if light_occluder.occluder == null:
		return Vector2.ZERO
	var polygon := light_occluder.occluder.polygon
	if polygon.is_empty():
		return Vector2.ZERO
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	return bounds.size


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


func _configure_geometry() -> void:
	var interaction_rectangle := RectangleShape2D.new()
	interaction_rectangle.size = Vector2(58.0, span_length_pixels + 16.0)
	interaction_shape.shape = interaction_rectangle
	var blocker_rectangle := RectangleShape2D.new()
	blocker_rectangle.size = Vector2(32.0, span_length_pixels)
	blocker.shape = blocker_rectangle
	var occluder := OccluderPolygon2D.new()
	var half_length := span_length_pixels * 0.5
	occluder.polygon = PackedVector2Array([
		Vector2(-16.0, -half_length),
		Vector2(16.0, -half_length),
		Vector2(16.0, half_length),
		Vector2(-16.0, half_length),
	])
	light_occluder.occluder = occluder


func _draw() -> void:
	var half_length := span_length_pixels * 0.5
	var access_color: Color = ACCESS_COLORS.get(required_access, CLOSED_COLOR)
	var panel_color := OPEN_COLOR if is_open else (Color("5ccb96") if is_unlocked else access_color)
	var outer_rect := Rect2(-20.0, -half_length - 4.0, 40.0, span_length_pixels + 8.0)
	draw_rect(outer_rect, FRAME_DARK, true)
	draw_rect(Rect2(-18.0, -half_length - 2.0, 36.0, span_length_pixels + 4.0), FRAME_MID, true)
	draw_line(
		Vector2(-17.0, -half_length - 1.0),
		Vector2(17.0, -half_length - 1.0),
		FRAME_LIGHT,
		2.0,
		false
	)
	draw_line(
		Vector2(-17.0, half_length + 1.0),
		Vector2(17.0, half_length + 1.0),
		Color(FRAME_DARK, 0.95),
		2.0,
		false
	)
	if is_open:
		draw_rect(Rect2(-16.0, -half_length, 6.0, span_length_pixels), FRAME_LIGHT, true)
		draw_rect(Rect2(10.0, -half_length, 6.0, span_length_pixels), FRAME_LIGHT, true)
		draw_rect(Rect2(-14.0, -half_length + 3.0, 2.0, span_length_pixels - 6.0), panel_color, true)
		draw_rect(Rect2(12.0, -half_length + 3.0, 2.0, span_length_pixels - 6.0), panel_color, true)
		draw_line(Vector2(-8.0, -half_length), Vector2(8.0, -half_length), panel_color, 2.0, false)
		draw_line(Vector2(-8.0, half_length), Vector2(8.0, half_length), panel_color, 2.0, false)
	else:
		draw_rect(Rect2(-15.0, -half_length + 2.0, 30.0, span_length_pixels - 4.0), FRAME_DARK, true)
		draw_rect(Rect2(-12.0, -half_length + 4.0, 24.0, span_length_pixels - 8.0), Color(panel_color, 0.72), true)
		draw_line(Vector2(0.0, -half_length + 5.0), Vector2(0.0, half_length - 5.0), FRAME_DARK, 2.0, false)
		for segment_y: int in range(int(-half_length + 18.0), int(half_length - 5.0), 24):
			draw_line(Vector2(-10.0, segment_y), Vector2(10.0, segment_y), Color(FRAME_LIGHT, 0.62), 1.0, false)
		for stripe_y: int in range(int(-half_length + 9.0), int(half_length - 8.0), 16):
			draw_line(Vector2(-11.0, stripe_y + 6.0), Vector2(-5.0, stripe_y), Color(access_color, 0.9), 2.0, false)
			draw_line(Vector2(5.0, stripe_y + 6.0), Vector2(11.0, stripe_y), Color(access_color, 0.9), 2.0, false)
		var rank_bar_count := int(required_access) + 1
		var rank_width := float(rank_bar_count * 4 - 1)
		for rank_index: int in range(rank_bar_count):
			draw_rect(
				Rect2(-rank_width * 0.5 + rank_index * 4.0, -2.0, 3.0, 7.0),
				Color("f2d58a") if requires_vault_authorization else access_color,
				true
			)
		if requires_vault_authorization:
			draw_polyline(
				PackedVector2Array([
					Vector2(0.0, -12.0),
					Vector2(6.0, -6.0),
					Vector2(0.0, 0.0),
					Vector2(-6.0, -6.0),
					Vector2(0.0, -12.0),
				]),
				Color("a77bff"),
				2.0,
				false
			)
