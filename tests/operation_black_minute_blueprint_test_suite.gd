class_name OperationBlackMinuteBlueprintTestSuite
extends Node

const BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)
const VALIDATOR_SCRIPT: Script = preload(
	"res://scripts/missions/mission_solvability_validator.gd"
)

var _expectation: Callable
var _blueprint: Dictionary = {}


func run(_tree: SceneTree, expect: Callable) -> void:
	_expectation = expect
	print("[TEST] Operation: Black Minute blueprint solvability")
	_blueprint = _load_blueprint()
	_check(not _blueprint.is_empty(), "operation blueprint parses for solvability tests")
	if _blueprint.is_empty():
		return
	_test_valid_blueprint_contract()
	_test_dimension_regression_is_rejected()
	_test_duplicate_stable_id_is_rejected()
	_test_unwalkable_required_object_is_rejected()
	_test_circular_objective_progression_is_rejected()
	_test_short_choke_window_is_rejected()
	_test_missing_authorization_source_is_rejected()


func _test_valid_blueprint_contract() -> void:
	var report := _validate(_blueprint)
	var stats: Dictionary = report.get("statistics", {}) as Dictionary
	_check(bool(report.get("is_valid", false)), "production blueprint passes all solvability contracts")
	_check(
		stats.get("map_size", Vector2i.ZERO) == Vector2i(64, 42)
		and int(stats.get("room_count", 0)) >= 12,
		"production blueprint is 64x42 with at least twelve authored rooms"
	)
	_check(
		int(stats.get("guard_count", 0)) == 10
		and int(stats.get("camera_count", 0)) == 8
		and int(stats.get("laser_count", 0)) == 3,
		"production blueprint fixes ten Guards, eight CCTV cameras, and three lasers"
	)
	_check(
		int(stats.get("reachable_room_count", 0)) == int(stats.get("room_count", -1)),
		"every room and required object zone is reachable in the declared room graph"
	)
	_check(
		float(stats.get("minimum_declared_safe_window_seconds", 0.0)) >= 3.0,
		"every declared patrol choke exposes a safe window of at least three seconds"
	)


func _test_dimension_regression_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	changed["size"] = [63, 42]
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "MAP_SIZE"),
		"validator rejects map dimension drift from 64x42"
	)


func _test_duplicate_stable_id_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	var guards: Array = changed.get("guards", []) as Array
	(guards[1] as Dictionary)["id"] = String((guards[0] as Dictionary).get("id", ""))
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "STABLE_ID"),
		"validator rejects duplicate stable object IDs"
	)


func _test_unwalkable_required_object_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	var objects: Dictionary = changed.get("objects", {}) as Dictionary
	(objects["objective_chronos_core_01"] as Dictionary)["position"] = [0, 0]
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "WALKABILITY"),
		"validator rejects a required objective placed on non-walkable wall space"
	)


func _test_circular_objective_progression_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	var objectives: Dictionary = changed.get("objectives", {}) as Dictionary
	var nodes: Dictionary = objectives.get("nodes", {}) as Dictionary
	(nodes["objective_infiltrate"] as Dictionary)["prerequisites_all"] = ["objective_extract"]
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "OBJECTIVE_DAG"),
		"validator rejects a circular access/objective dependency"
	)


func _test_short_choke_window_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	var chokes: Array = changed.get("choke_points", []) as Array
	var first_choke: Dictionary = chokes[0] as Dictionary
	var windows: Array = first_choke.get("safe_windows", []) as Array
	(windows[0] as Dictionary)["duration_seconds"] = 2.99
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "CHOKE_WINDOW"),
		"validator rejects patrol choke windows shorter than three seconds"
	)


func _test_missing_authorization_source_is_rejected() -> void:
	var changed := _blueprint.duplicate(true)
	var security: Dictionary = changed.get("security", {}) as Dictionary
	var authorization: Dictionary = security.get("vault_authorization", {}) as Dictionary
	var sources: Array = authorization.get("sources", []) as Array
	authorization["sources"] = [sources[0]]
	var report := _validate(changed)
	_check(
		not bool(report.get("is_valid", true)) and _has_error(report, "VAULT_AUTH"),
		"validator requires both declared vault authorization sources"
	)


func _validate(blueprint: Dictionary) -> Dictionary:
	var validator: RefCounted = VALIDATOR_SCRIPT.new()
	return validator.call(&"validate", blueprint) as Dictionary


func _load_blueprint() -> Dictionary:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _has_error(report: Dictionary, code: String) -> bool:
	for error_value: Variant in report.get("errors", []):
		if String(error_value).contains(code):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_expectation.call(condition, message)
