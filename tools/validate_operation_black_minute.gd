extends SceneTree

const BLUEPRINT_PATH: String = (
	"res://resources/maps/operation_black_minute_blueprint.json"
)
const VALIDATOR_SCRIPT: Script = preload(
	"res://scripts/missions/mission_solvability_validator.gd"
)
const PATROL_SCHEDULER_SCRIPT: Script = preload(
	"res://scripts/enemies/patrol_scheduler.gd"
)


func _initialize() -> void:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		push_error("[MISSION VALIDATION] Cannot open %s" % BLUEPRINT_PATH)
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("[MISSION VALIDATION] Blueprint root is not a JSON object")
		quit(1)
		return
	var validator: RefCounted = VALIDATOR_SCRIPT.new()
	var report: Dictionary = validator.call(&"validate", parsed as Dictionary)
	var statistics: Dictionary = report.get("statistics", {}) as Dictionary
	if not bool(report.get("is_valid", false)):
		for error_value: Variant in report.get("errors", []):
			push_error("[MISSION VALIDATION] %s" % String(error_value))
		push_error(
			"[MISSION VALIDATION] FAIL: %d contract violations"
			% (report.get("errors", []) as Array).size()
		)
		quit(1)
		return
	var map_size: Vector2i = statistics.get("map_size", Vector2i.ZERO)
	var summary_format := (
		"[MISSION VALIDATION] PASS: %dx%d, %d rooms, %d guards, "
		+ "%d CCTV, %d lasers, %d reachable rooms, %.1fs minimum declared safe window"
	)
	print(
		summary_format
		% [
			map_size.x,
			map_size.y,
			int(statistics.get("room_count", 0)),
			int(statistics.get("guard_count", 0)),
			int(statistics.get("camera_count", 0)),
			int(statistics.get("laser_count", 0)),
			int(statistics.get("reachable_room_count", 0)),
			float(statistics.get("minimum_declared_safe_window_seconds", 0.0)),
		]
	)
	var scheduler := PATROL_SCHEDULER_SCRIPT.new() as PatrolScheduler
	root.add_child(scheduler)
	var contract: Dictionary = (
		(parsed as Dictionary).get("validation_contract", {}) as Dictionary
	)
	var duration := float(contract.get("patrol_simulation_seconds", 180.0))
	var patrol_report := scheduler.run_patrol_simulation(
		parsed as Dictionary, duration, 0.1
	)
	if not bool(patrol_report.get("valid", false)):
		push_error(
			"[PATROL VALIDATION] FAIL: overlaps=%d choke=%d zone=%d deadlocks=%d"
			% [
				int(patrol_report.get("guard_overlap_count", -1)),
				int(patrol_report.get("choke_capacity_violations", -1)),
				int(patrol_report.get("zone_violations", -1)),
				int(patrol_report.get("deadlocks", -1)),
			]
		)
		quit(1)
		return
	_print_patrol_report(patrol_report)
	quit(0)


func _print_patrol_report(report: Dictionary) -> void:
	var opportunities: Dictionary = report.get("simulated_choke_open_opportunities", {})
	var choke_ids: Array[String] = []
	for choke_variant: Variant in opportunities:
		choke_ids.append(String(choke_variant))
	choke_ids.sort()
	var opportunity_count: int = 0
	for choke_id: String in choke_ids:
		var entry: Dictionary = opportunities.get(StringName(choke_id), {})
		var count := int(entry.get("opportunity_count", 0))
		opportunity_count += count
		print(
			"[PATROL CAPACITY] %s: opportunities=%d longest=%.1fs"
			% [
				choke_id,
				count,
				float(entry.get("longest_capacity_open_seconds", 0.0)),
			]
		)
	var summary := (
		"[PATROL VALIDATION] PASS: %.1fs/%d ticks, %d chokes, "
		+ "%d capacity-open opportunities, %.1fs minimum longest capacity-open interval"
	)
	print(
		summary
		% [
			float(report.get("duration_seconds", 0.0)),
			int(report.get("tick_count", 0)),
			choke_ids.size(),
			opportunity_count,
			float(report.get("minimum_simulated_capacity_open_seconds", 0.0)),
		]
	)
