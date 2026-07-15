class_name FacilityMapOverlay
extends CanvasLayer

signal opened
signal closed

@onready var map_view: FacilityMapView = %FacilityMapView
@onready var objective_label: Label = %ObjectiveLabel


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%CloseButton.pressed.connect(close_map)


func configure(blueprint: Dictionary) -> void:
	map_view.set_blueprint(blueprint)


func toggle_map() -> void:
	if visible:
		close_map()
	else:
		open_map()


func open_map() -> void:
	if visible:
		return
	visible = true
	opened.emit()


func close_map() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func set_player_position(world_position: Vector2) -> void:
	map_view.set_player_world_position(world_position)


func set_security_status(cctv_online: bool, laser_online: bool) -> void:
	map_view.set_security_status(cctv_online, laser_online)


func set_mission_status(core_carried: bool, maintenance_discovered: bool = false) -> void:
	map_view.set_mission_status(core_carried, maintenance_discovered)


func set_objectives(
	lines: PackedStringArray,
	objective_ids: Array[StringName] = []
) -> void:
	objective_label.text = (
		"CURRENT OBJECTIVES\n• " + "\n• ".join(lines)
		if not lines.is_empty()
		else "CURRENT OBJECTIVES\n• Awaiting mission data"
	)
	map_view.set_active_objectives(objective_ids)
