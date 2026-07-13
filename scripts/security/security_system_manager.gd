class_name SecuritySystemManager
extends Node

signal cctv_network_changed(is_online: bool)
signal laser_network_changed(is_online: bool)
signal alert_level_changed(previous_level: AlertLevel, current_level: AlertLevel)
signal zone_alert_requested(
	zone_id: StringName,
	position: Vector2,
	source_id: StringName
)

enum AlertLevel {
	CLEAR,
	SUSPICIOUS,
	ALERTED,
	LOCKDOWN,
}

const ALERT_NAMES: Dictionary = {
	AlertLevel.CLEAR: &"CLEAR",
	AlertLevel.SUSPICIOUS: &"SUSPICIOUS",
	AlertLevel.ALERTED: &"ALERTED",
	AlertLevel.LOCKDOWN: &"LOCKDOWN",
}

@export_range(2.0, 120.0, 1.0) var alert_decay_seconds: float = 30.0

var cctv_online: bool = true
var laser_online: bool = true
var alert_level: AlertLevel = AlertLevel.CLEAR

var _zone_alerts: Dictionary[StringName, Dictionary] = {}
var _time_without_detection: float = 0.0


func disable_cctv_network() -> bool:
	if not cctv_online:
		return false
	cctv_online = false
	cctv_network_changed.emit(false)
	return true


func disable_laser_network() -> bool:
	if not laser_online:
		return false
	laser_online = false
	laser_network_changed.emit(false)
	return true


func raise_zone_alert(
	zone_id: StringName,
	position: Vector2,
	source_id: StringName,
	minimum_level: AlertLevel = AlertLevel.SUSPICIOUS
) -> void:
	if zone_id == StringName():
		push_warning("SecuritySystemManager ignored an alert with an empty zone ID")
		return
	_zone_alerts[zone_id] = {
		"position": position,
		"source_id": source_id,
		"level": minimum_level,
	}
	_time_without_detection = 0.0
	set_alert_level(maxi(alert_level, minimum_level) as AlertLevel)
	zone_alert_requested.emit(zone_id, position, source_id)


func raise_facility_alert(minimum_level: AlertLevel) -> void:
	_time_without_detection = 0.0
	set_alert_level(maxi(alert_level, minimum_level) as AlertLevel)


func set_alert_level(next_level: AlertLevel) -> void:
	var safe_level := clampi(next_level, AlertLevel.CLEAR, AlertLevel.LOCKDOWN) as AlertLevel
	if safe_level == alert_level:
		return
	var previous_level := alert_level
	alert_level = safe_level
	alert_level_changed.emit(previous_level, alert_level)


func advance_alert_decay(delta: float) -> void:
	if delta <= 0.0 or alert_level == AlertLevel.CLEAR or alert_level == AlertLevel.LOCKDOWN:
		return
	_time_without_detection += delta
	if _time_without_detection < alert_decay_seconds:
		return
	_time_without_detection = 0.0
	if alert_level == AlertLevel.ALERTED:
		set_alert_level(AlertLevel.SUSPICIOUS)
	else:
		_zone_alerts.clear()
		set_alert_level(AlertLevel.CLEAR)


func get_zone_alert(zone_id: StringName) -> Dictionary:
	return (_zone_alerts.get(zone_id, {}) as Dictionary).duplicate(true)


func has_zone_alert(zone_id: StringName) -> bool:
	return _zone_alerts.has(zone_id)


func get_alert_label() -> StringName:
	return StringName(ALERT_NAMES.get(alert_level, &"CLEAR"))


func reset_mission() -> void:
	cctv_online = true
	laser_online = true
	_zone_alerts.clear()
	_time_without_detection = 0.0
	set_alert_level(AlertLevel.CLEAR)
	cctv_network_changed.emit(true)
	laser_network_changed.emit(true)


func capture_recall_state() -> Dictionary:
	return {
		"cctv_online": cctv_online,
		"laser_online": laser_online,
		"alert_level": alert_level,
		"zone_alerts": _zone_alerts.duplicate(true),
		"time_without_detection": _time_without_detection,
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	var zones_variant: Variant = snapshot.get("zone_alerts", {})
	if not zones_variant is Dictionary:
		return false
	cctv_online = bool(snapshot.get("cctv_online", true))
	laser_online = bool(snapshot.get("laser_online", true))
	alert_level = clampi(
		int(snapshot.get("alert_level", AlertLevel.CLEAR)),
		AlertLevel.CLEAR,
		AlertLevel.LOCKDOWN
	) as AlertLevel
	_zone_alerts = (zones_variant as Dictionary).duplicate(true)
	_time_without_detection = maxf(0.0, float(snapshot.get("time_without_detection", 0.0)))
	cctv_network_changed.emit(cctv_online)
	laser_network_changed.emit(laser_online)
	alert_level_changed.emit(alert_level, alert_level)
	return true


func get_recall_state_id() -> StringName:
	return &"security_system"
