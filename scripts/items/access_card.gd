class_name AccessCard
extends Interactable

signal collected(actor: Node, access_level: AccessControlManager.AccessLevel, card_id: StringName)

const LEVEL_COLORS: Dictionary = {
	AccessControlManager.AccessLevel.LEVEL_1: Color("52d8eb"),
	AccessControlManager.AccessLevel.LEVEL_2: Color("ffae45"),
	AccessControlManager.AccessLevel.VAULT: Color("c889ff"),
}
const LEVEL_BADGES: Dictionary = {
	AccessControlManager.AccessLevel.LEVEL_1: "L1",
	AccessControlManager.AccessLevel.LEVEL_2: "L2",
	AccessControlManager.AccessLevel.VAULT: "V",
}
const BEACON_TOP: float = -48.0
const BEACON_BOTTOM: float = -25.0
const PULSE_SPEED: float = 2.2

@export var access_level: AccessControlManager.AccessLevel = AccessControlManager.AccessLevel.LEVEL_1

@onready var collision_shape: CollisionShape2D = %CollisionShape2D

var is_collected: bool = false
var _pulse_time: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"mission_resettable")
	add_to_group(&"recall_rewindable")
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse_time = fmod(_pulse_time + maxf(0.0, delta) * PULSE_SPEED, TAU)
	queue_redraw()


func can_interact(actor: Node) -> bool:
	return not is_collected and actor != null and actor.is_in_group(&"player_actor")


func interact(actor: Node) -> bool:
	if not can_interact(actor):
		return false
	is_collected = true
	visible = false
	monitorable = false
	collision_shape.set_deferred(&"disabled", true)
	collected.emit(actor, access_level, object_id)
	return true


func get_interaction_prompt(_actor: Node) -> String:
	return "E  TAKE %s ACCESS CARD" % AccessControlManager.ACCESS_NAMES.get(
		access_level,
		&"SECURITY"
	)


func get_access_badge_text() -> String:
	return String(LEVEL_BADGES.get(access_level, "SEC"))


func get_access_accent_color() -> Color:
	return LEVEL_COLORS.get(access_level, Color.WHITE) as Color


func get_beacon_extent() -> Rect2:
	return Rect2(-22.0, BEACON_TOP, 44.0, 64.0)


func reset_mission() -> void:
	_pulse_time = 0.0
	_apply_collected(false)


func capture_recall_state() -> Dictionary:
	return {"is_collected": is_collected}


func restore_recall_state(snapshot: Dictionary) -> bool:
	_apply_collected(bool(snapshot.get("is_collected", false)))
	return true


func get_recall_state_id() -> StringName:
	return object_id


func _apply_collected(value: bool) -> void:
	is_collected = value
	visible = not value
	monitorable = not value
	set_process(not value)
	collision_shape.set_deferred(&"disabled", value)
	queue_redraw()


func _draw() -> void:
	var accent := get_access_accent_color()
	var pulse := 0.5 + sin(_pulse_time) * 0.5
	var badge := get_access_badge_text()

	# The elevated beacon remains readable when the Player stands directly on the card.
	draw_line(
		Vector2(0.0, BEACON_BOTTOM),
		Vector2(0.0, -17.0),
		Color(accent, 0.5 + pulse * 0.35),
		2.0
	)
	draw_arc(
		Vector2(0.0, -34.0),
		8.0 + pulse * 2.5,
		0.0,
		TAU,
		20,
		Color(accent, 0.3 + pulse * 0.35),
		2.0
	)
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(0.0, BEACON_BOTTOM),
			Vector2(-7.0, -34.0),
			Vector2(7.0, -34.0),
		]),
		accent
	)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-9.0, BEACON_TOP + 9.0),
		badge,
		HORIZONTAL_ALIGNMENT_CENTER,
		18.0,
		13,
		Color("f4ffff")
	)

	# Card body: access tier is communicated by text, color, and a notched silhouette.
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-20.0, -12.0),
			Vector2(14.0, -12.0),
			Vector2(20.0, -6.0),
			Vector2(20.0, 12.0),
			Vector2(-20.0, 12.0),
		]),
		Color("0a1725")
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(-20.0, -12.0),
			Vector2(14.0, -12.0),
			Vector2(20.0, -6.0),
			Vector2(20.0, 12.0),
			Vector2(-20.0, 12.0),
			Vector2(-20.0, -12.0),
		]),
		accent,
		2.0
	)
	draw_rect(Rect2(-16.0, -8.0, 32.0, 16.0), Color(accent, 0.2), true)
	draw_rect(Rect2(-16.0, 8.0, 32.0, 3.0), accent, true)
	draw_circle(Vector2(-11.0, 0.0), 3.5, accent)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-4.0, 5.0),
		badge,
		HORIZONTAL_ALIGNMENT_CENTER,
		17.0,
		13,
		Color("f4ffff")
	)

	# Brackets provide a non-color pickup affordance at two or more tile distances.
	var bracket_color := Color(accent, 0.55 + pulse * 0.35)
	draw_polyline(
		PackedVector2Array([
			Vector2(-25.0, -14.0), Vector2(-25.0, -19.0), Vector2(-17.0, -19.0),
		]),
		bracket_color,
		2.0
	)
	draw_polyline(
		PackedVector2Array([
			Vector2(25.0, 14.0), Vector2(25.0, 19.0), Vector2(17.0, 19.0),
		]),
		bracket_color,
		2.0
	)
