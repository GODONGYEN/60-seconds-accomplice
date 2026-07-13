class_name MissionDefinition
extends Resource

@export var mission_id: StringName = &"operation_black_minute"
@export var operation_name: String = "OPERATION: BLACK MINUTE"
@export var operation_name_ko: String = "작전명: 검은 1분"
@export var facility_name: String = "HELIX TEMPORAL RESEARCH FACILITY"
@export var facility_name_ko: String = "헬릭스 시간 연구시설"
@export var target_name: String = "CHRONOS CORE"
@export var target_name_ko: String = "크로노스 코어"
@export_multiline var briefing: String = (
	"Infiltrate the Helix temporal research facility. Neutralize its security layers, "
	+ "steal the Chronos Core from the deep vault, and return to extraction."
)
@export_range(0, 8, 1) var recall_charges: int = 3
@export_range(1.0, 20.0, 0.5) var rewind_duration_seconds: float = 10.0
@export var blueprint_path: String = "res://resources/maps/operation_black_minute_blueprint.json"


func validate() -> bool:
	if mission_id == StringName():
		push_error("MissionDefinition requires a non-empty mission_id")
		return false
	if (
		operation_name.is_empty()
		or operation_name_ko.is_empty()
		or facility_name.is_empty()
		or facility_name_ko.is_empty()
		or target_name.is_empty()
		or target_name_ko.is_empty()
	):
		push_error("MissionDefinition '%s' is missing briefing identity" % mission_id)
		return false
	if recall_charges < 0 or rewind_duration_seconds <= 0.0:
		push_error("MissionDefinition '%s' has invalid Recall settings" % mission_id)
		return false
	return FileAccess.file_exists(blueprint_path)
