class_name MissionPerformanceTestSuite
extends Node

var _expectation: Callable
var _assertion_count: int = 0


func run(_tree: SceneTree, expect: Callable) -> void:
	_expectation = expect
	_assertion_count = 0
	print("[TEST] Mission performance scoring and immutable results")
	_test_clean_timeline_and_echo_distraction()
	_test_grade_bands_without_time_pressure()
	_test_reset_detection_contract_and_clamping()
	_test_idempotent_deep_copy()


func get_assertion_count() -> int:
	return _assertion_count


func _test_clean_timeline_and_echo_distraction() -> void:
	var clean_tracker := MissionPerformanceTracker.new()
	var clean_result := clean_tracker.finalize_result(
		&"operation_black_minute", 299.9, 0, 3, true, true, &"biometric"
	)
	_check(
		int(clean_result.get("total_score", 0)) == 10_000
		and clean_result.get("grade", StringName()) == &"S",
		"an unseen no-Recall CCTV blackout earns the transparent 10,000-point S result"
	)
	_check(
		int(clean_result.get("base_score", 0)) == 5_000
		and int(clean_result.get("bonus_score", 0)) == 5_000,
		"result exposes its fixed extraction score and positive-only bonus subtotal"
	)
	var clean_bonuses: Array = clean_result.get("bonuses", []) as Array
	_check(
		clean_bonuses.size() == 5
		and (clean_bonuses[0] as Dictionary).get("id", StringName()) == &"shadow"
		and (clean_bonuses[4] as Dictionary).get("id", StringName()) == &"cctv_blackout",
		"score breakdown keeps a stable presentation order from SHADOW through BLACKOUT"
	)
	_check(
		bool((clean_bonuses[1] as Dictionary).get("awarded", false))
		and not bool((clean_bonuses[2] as Dictionary).get("awarded", true)),
		"Temporal Discipline and Paradox Decoy are mutually exclusive on a clean timeline"
	)

	var echo_tracker := MissionPerformanceTracker.new()
	_check(
		echo_tracker.record_detection(&"echo_02")
		and echo_tracker.get_echo_detection_count() == 1,
		"an exact echo_ prefix is classified as a temporal distraction detection"
	)
	var echo_result := echo_tracker.finalize_result(
		&"operation_black_minute", 900.0, 2, 3, true, true, &"server_override"
	)
	_check(
		int(echo_result.get("total_score", 0)) == 10_000
		and echo_result.get("grade", StringName()) == &"S",
		"an unseen run with a detected Echo earns the same S ceiling without a speed requirement"
	)
	_check(
		int(echo_result.get("echo_detections", 0)) == 1
		and echo_result.get("authorization_route", StringName()) == &"server_override",
		"Echo use and the alternate authorization route remain explicit debrief metrics"
	)


func _test_grade_bands_without_time_pressure() -> void:
	var grade_a_tracker := MissionPerformanceTracker.new()
	var grade_a := grade_a_tracker.finalize_result(
		&"operation_black_minute", 1000.0, 1, 3, true, true, &"biometric"
	)
	_check(
		int(grade_a.get("total_score", 0)) == 8_500
		and grade_a.get("grade", StringName()) == &"A",
		"an unseen safe Recall without an observed Echo earns grade A"
	)

	var grade_b_tracker := MissionPerformanceTracker.new()
	grade_b_tracker.record_detection(&"player_live")
	grade_b_tracker.record_detection(&"echo_01")
	grade_b_tracker.record_capture()
	var grade_b := grade_b_tracker.finalize_result(
		&"operation_black_minute", 60.0, 1, 3, false, true, &"server_override"
	)
	_check(
		int(grade_b.get("total_score", 0)) == 6_500
		and grade_b.get("grade", StringName()) == &"B",
		"a captured detected run with a real Echo distraction lands exactly on grade B"
	)

	var grade_c_tracker := MissionPerformanceTracker.new()
	grade_c_tracker.record_detection(&"player_live")
	grade_c_tracker.record_capture()
	var grade_c := grade_c_tracker.finalize_result(
		&"operation_black_minute", 1.0, 1, 3, false, false, &"biometric"
	)
	_check(
		int(grade_c.get("total_score", 0)) == 5_000
		and grade_c.get("grade", StringName()) == &"C",
		"a detected captured Recall with no useful Echo receives only extraction score and grade C"
	)

	var slow_tracker := MissionPerformanceTracker.new()
	var slow := slow_tracker.finalize_result(
		&"operation_black_minute", 10_000.0, 0, 3, true, true, &"biometric"
	)
	_check(
		int(slow.get("total_score", 0)) == 10_000
		and is_equal_approx(float(slow.get("elapsed_seconds", 0.0)), 10_000.0),
		"elapsed time is retained as a stat but never pressures or changes the score"
	)


func _test_reset_detection_contract_and_clamping() -> void:
	var tracker := MissionPerformanceTracker.new()
	tracker.record_alert_raised()
	tracker.record_capture()
	tracker.record_detection(&"player_live")
	tracker.record_detection(&"echo_branch_a")
	_check(
		not tracker.record_detection(&"Player")
		and not tracker.record_detection(&"ghost_01"),
		"detection classification never guesses from display names or non-Echo prefixes"
	)
	tracker.begin_mission()
	_check(
		tracker.get_alert_count() == 0
		and tracker.get_capture_count() == 0
		and tracker.get_live_player_detection_count() == 0
		and tracker.get_echo_detection_count() == 0
		and not tracker.is_finalized(),
		"begin_mission clears all counters and finalization state"
	)
	var result := tracker.finalize_result(
		&"operation_black_minute", -12.0, -2, -3, false, false, &"biometric"
	)
	_check(
		is_zero_approx(float(result.get("elapsed_seconds", -1.0)))
		and int(result.get("recalls_used", -1)) == 0
		and int(result.get("maximum_recalls", -1)) == 0
		and int(result.get("recalls_remaining", -1)) == 0,
		"negative duration and Recall inputs clamp independently to safe nonnegative metrics"
	)
	var over_limit_result := MissionPerformanceTracker.new().finalize_result(
		&"operation_black_minute", 10.0, 9, 3, false, false, &"biometric"
	)
	_check(
		int(over_limit_result.get("recalls_used", -1)) == 3
		and int(over_limit_result.get("maximum_recalls", -1)) == 3
		and int(over_limit_result.get("recalls_remaining", -1)) == 0,
		"Recall usage clamps to its declared maximum instead of exposing contradictory metrics"
	)
	_check(
		result.get("mission_id", StringName()) == &"operation_black_minute"
		and result.get("authorization_route", StringName()) == &"biometric"
		and not bool(result.get("lasers_disabled", true)),
		"mission, route, and laser state remain unchanged presentation metrics"
	)


func _test_idempotent_deep_copy() -> void:
	var tracker := MissionPerformanceTracker.new()
	tracker.record_alert_raised()
	tracker.record_detection(&"echo_01")
	var first := tracker.finalize_result(
		&"operation_black_minute", 320.0, 1, 3, true, true, &"biometric"
	)
	_check(
		tracker.is_finalized()
		and not tracker.record_alert_raised()
		and not tracker.record_capture()
		and not tracker.record_detection(&"player_live"),
		"finalized performance state rejects every late mutable event"
	)
	var first_bonuses: Array = first.get("bonuses", []) as Array
	(first_bonuses[0] as Dictionary)["label"] = "MUTATED"
	first_bonuses.append({"id": &"injected", "points": 999_999})
	first["total_score"] = -1

	var second := tracker.finalize_result(
		&"different_mission", 0.0, 0, 99, false, false, &"server_override"
	)
	var second_bonuses: Array = second.get("bonuses", []) as Array
	_check(
		second.get("mission_id", StringName()) == &"operation_black_minute"
		and int(second.get("total_score", 0)) == 10_000,
		"repeat finalization is idempotent and ignores conflicting replacement inputs"
	)
	_check(
		second_bonuses.size() == 5
		and (second_bonuses[0] as Dictionary).get("label", "") == "SHADOW",
		"returned results are recursive deep copies whose nested bonus data cannot poison the cache"
	)
	_check(
		int(second.get("live_player_detections", -1)) == 0
		and int(second.get("echo_detections", 0)) == 1
		and int(second.get("alert_count", 0)) == 1,
		"post-finalize writes leave detection and alert metrics immutable"
	)


func _check(condition: bool, message: String) -> void:
	_assertion_count += 1
	_expectation.call(condition, message)
