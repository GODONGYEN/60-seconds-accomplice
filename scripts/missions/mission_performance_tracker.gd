class_name MissionPerformanceTracker
extends RefCounted

const BASE_SCORE: int = 5_000
const SHADOW_POINTS: int = 2_000
const TEMPORAL_DISCIPLINE_POINTS: int = 1_500
const PARADOX_DECOY_POINTS: int = 1_500
const ZERO_CAPTURE_POINTS: int = 1_000
const CCTV_BLACKOUT_POINTS: int = 500

const GRADE_S_MINIMUM: int = 9_500
const GRADE_A_MINIMUM: int = 8_000
const GRADE_B_MINIMUM: int = 6_500

var _alert_count: int = 0
var _capture_count: int = 0
var _live_player_detections: int = 0
var _echo_detections: int = 0
var _finalized: bool = false
var _final_result: Dictionary = {}


func _init() -> void:
	begin_mission()


func begin_mission() -> void:
	_alert_count = 0
	_capture_count = 0
	_live_player_detections = 0
	_echo_detections = 0
	_finalized = false
	_final_result.clear()


func record_alert_raised() -> bool:
	if _finalized:
		return false
	_alert_count += 1
	return true


func record_capture() -> bool:
	if _finalized:
		return false
	_capture_count += 1
	return true


func record_detection(actor_id: StringName) -> bool:
	if _finalized:
		return false
	if actor_id == &"player_live":
		_live_player_detections += 1
		return true
	if String(actor_id).begins_with("echo_"):
		_echo_detections += 1
		return true
	return false


func is_finalized() -> bool:
	return _finalized


func get_alert_count() -> int:
	return _alert_count


func get_capture_count() -> int:
	return _capture_count


func get_live_player_detection_count() -> int:
	return _live_player_detections


func get_echo_detection_count() -> int:
	return _echo_detections


func finalize_result(
	mission_id: StringName,
	elapsed_seconds: float,
	recalls_used: int,
	maximum_recalls: int,
	cctv_disabled: bool,
	lasers_disabled: bool,
	authorization_route: StringName
) -> Dictionary:
	if _finalized:
		return _final_result.duplicate(true)

	var safe_elapsed_seconds := maxf(0.0, elapsed_seconds)
	var safe_maximum_recalls := maxi(0, maximum_recalls)
	var safe_recalls_used := clampi(recalls_used, 0, safe_maximum_recalls)
	var bonuses: Array[Dictionary] = []
	bonuses.append(
		_make_bonus(
			&"shadow",
			"SHADOW",
			_live_player_detections == 0,
			SHADOW_POINTS if _live_player_detections == 0 else 0
		)
	)
	bonuses.append(
		_make_bonus(
			&"temporal_discipline",
			"TEMPORAL DISCIPLINE",
			safe_recalls_used == 0,
			TEMPORAL_DISCIPLINE_POINTS if safe_recalls_used == 0 else 0
		)
	)
	bonuses.append(
		_make_bonus(
			&"paradox_decoy",
			"PARADOX DECOY",
			safe_recalls_used > 0 and _echo_detections > 0,
			PARADOX_DECOY_POINTS if safe_recalls_used > 0 and _echo_detections > 0 else 0
		)
	)
	bonuses.append(
		_make_bonus(
			&"untouchable",
			"UNTOUCHABLE",
			_capture_count == 0,
			ZERO_CAPTURE_POINTS if _capture_count == 0 else 0
		)
	)
	bonuses.append(
		_make_bonus(
			&"cctv_blackout",
			"BLACKOUT",
			cctv_disabled,
			CCTV_BLACKOUT_POINTS if cctv_disabled else 0
		)
	)

	var bonus_score: int = 0
	for bonus: Dictionary in bonuses:
		bonus_score += int(bonus.get("points", 0))
	var total_score := BASE_SCORE + bonus_score
	_final_result = {
		"mission_id": mission_id,
		"elapsed_seconds": safe_elapsed_seconds,
		"recalls_used": safe_recalls_used,
		"maximum_recalls": safe_maximum_recalls,
		"recalls_remaining": maxi(0, safe_maximum_recalls - safe_recalls_used),
		"alert_count": _alert_count,
		"capture_count": _capture_count,
		"live_player_detections": _live_player_detections,
		"echo_detections": _echo_detections,
		"cctv_disabled": cctv_disabled,
		"lasers_disabled": lasers_disabled,
		"authorization_route": authorization_route,
		"base_score": BASE_SCORE,
		"bonus_score": bonus_score,
		"total_score": total_score,
		"grade": _get_grade(total_score),
		"bonuses": bonuses,
	}
	_finalized = true
	return _final_result.duplicate(true)


func _make_bonus(
	id: StringName,
	label: String,
	awarded: bool,
	points: int
) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"awarded": awarded,
		"points": maxi(0, points),
	}


func _get_grade(total_score: int) -> StringName:
	if total_score >= GRADE_S_MINIMUM:
		return &"S"
	if total_score >= GRADE_A_MINIMUM:
		return &"A"
	if total_score >= GRADE_B_MINIMUM:
		return &"B"
	return &"C"
