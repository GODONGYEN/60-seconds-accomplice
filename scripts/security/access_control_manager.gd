class_name AccessControlManager
extends Node

signal access_changed(previous_level: AccessLevel, current_level: AccessLevel)
signal access_denied(door_id: StringName, required_level: AccessLevel)
signal credential_changed(credential_id: StringName, owned: bool)

enum AccessLevel {
	PUBLIC,
	LEVEL_1,
	LEVEL_2,
	VAULT,
}

const ACCESS_NAMES: Dictionary = {
	AccessLevel.PUBLIC: &"PUBLIC",
	AccessLevel.LEVEL_1: &"LEVEL 1",
	AccessLevel.LEVEL_2: &"LEVEL 2",
	AccessLevel.VAULT: &"VAULT",
}

var current_level: AccessLevel = AccessLevel.PUBLIC
var _credentials: Dictionary[StringName, bool] = {}


func grant_access(level: AccessLevel, source_id: StringName) -> bool:
	if level < AccessLevel.PUBLIC or level > AccessLevel.VAULT:
		push_warning("AccessControlManager rejected invalid access level %d" % level)
		return false
	if source_id == StringName():
		push_warning("AccessControlManager requires a stable credential source ID")
		return false
	if bool(_credentials.get(source_id, false)):
		return false
	_credentials[source_id] = true
	credential_changed.emit(source_id, true)
	if level <= current_level:
		return true
	var previous_level := current_level
	current_level = level
	access_changed.emit(previous_level, current_level)
	return true


func can_access(required_level: AccessLevel) -> bool:
	return current_level >= required_level


func authorize(door_id: StringName, required_level: AccessLevel) -> bool:
	if can_access(required_level):
		return true
	access_denied.emit(door_id, required_level)
	return false


func has_credential(credential_id: StringName) -> bool:
	return bool(_credentials.get(credential_id, false))


func get_access_label() -> StringName:
	return StringName(ACCESS_NAMES.get(current_level, &"PUBLIC"))


func reset_mission() -> void:
	var previous_level := current_level
	var previous_credentials := _credentials.keys()
	_credentials.clear()
	current_level = AccessLevel.PUBLIC
	for credential_variant: Variant in previous_credentials:
		credential_changed.emit(StringName(str(credential_variant)), false)
	if previous_level != current_level:
		access_changed.emit(previous_level, current_level)


func capture_recall_state() -> Dictionary:
	return {
		"current_level": current_level,
		"credentials": _credentials.duplicate(true),
	}


func restore_recall_state(snapshot: Dictionary) -> bool:
	var credentials_variant: Variant = snapshot.get("credentials", {})
	if not credentials_variant is Dictionary:
		return false
	var previous_level := current_level
	current_level = clampi(
		int(snapshot.get("current_level", AccessLevel.PUBLIC)),
		AccessLevel.PUBLIC,
		AccessLevel.VAULT
	) as AccessLevel
	_credentials.clear()
	for credential_variant: Variant in (credentials_variant as Dictionary).keys():
		var credential_id := StringName(str(credential_variant))
		_credentials[credential_id] = bool((credentials_variant as Dictionary)[credential_variant])
	if previous_level != current_level:
		access_changed.emit(previous_level, current_level)
	return true


func get_recall_state_id() -> StringName:
	return &"access_control"
