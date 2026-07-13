class_name MissionBriefing
extends CanvasLayer

signal start_requested
signal back_requested

@onready var operation_label: Label = %OperationLabel
@onready var facility_label: Label = %FacilityLabel
@onready var target_label: Label = %TargetLabel
@onready var briefing_label: Label = %BriefingLabel
@onready var recall_label: Label = %RecallLabel
@onready var map_view: FacilityMapView = %FacilityMapView


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%StartButton.pressed.connect(func() -> void: start_requested.emit())
	%BackButton.pressed.connect(func() -> void: back_requested.emit())


func configure(definition: MissionDefinition, blueprint: Dictionary) -> void:
	if definition == null:
		return
	operation_label.text = "%s\n%s" % [definition.operation_name, definition.operation_name_ko]
	facility_label.text = "%s  //  %s" % [definition.facility_name, definition.facility_name_ko]
	target_label.text = "PRIMARY TARGET  //  %s  //  %s" % [
		definition.target_name,
		definition.target_name_ko,
	]
	briefing_label.text = (
		definition.briefing
		+ "\n\nSECURITY LAYERS\n"
		+ "CCTV NETWORK  •  LEVEL 2 DOORS  •  LASER CORRIDOR  •  VAULT AUTHORIZATION"
		+ "\n\nPREPARATION\n"
		+ "Acquire credentials, neutralize or avoid surveillance, shut down laser power, "
		+ "obtain biometric or server authorization, steal the Core, then extract."
	)
	recall_label.text = "CHRONO RECALL  %d CHARGES  //  %.0f SECOND REWIND" % [
		definition.recall_charges,
		definition.rewind_duration_seconds,
	]
	map_view.set_blueprint(blueprint)


func show_briefing() -> void:
	visible = true


func hide_briefing() -> void:
	visible = false
