class_name PrototypeLevel
extends GameplayLevel

@onready var pressure_plate: PressurePlate = %PressurePlate
@onready var security_door: SecurityDoor = %SecurityDoor
@onready var objective_item: ObjectiveItem = %ObjectiveItem
@onready var exit_zone: ExitZone = %ExitZone
@onready var training_guard: GuardController = %TrainingGuard
@onready var guard_patrol_route: Node2D = %GuardPatrolRoute

var _shown_player_detection_hint: bool = false
var _shown_ghost_detection_hint: bool = false


func _ready() -> void:
	super._ready()
	pressure_plate.active_changed.connect(_on_plate_active_changed)
	security_door.open_state_changed.connect(_on_door_open_state_changed)
	objective_item.collected.connect(_on_objective_collected)
	exit_zone.exit_requested.connect(_on_exit_requested)
	exit_zone.feedback_requested.connect(_on_feedback_requested)
	guard_status_changed.connect(_on_visible_guard_status_for_hints)
	queue_redraw()


func validate_level() -> bool:
	return super.validate_level()


func get_loop_hint(loop_index: int) -> String:
	if loop_index <= 1:
		return "HOLD THE PLATE BRIEFLY, THEN DRAW THE GUARD INTO THE UPPER CORRIDOR"
	return "CROSS WHILE YOUR GHOST OPENS THE DOOR AND DISTRACTS THE GUARD"


func _on_plate_active_changed(is_active: bool) -> void:
	security_door.set_open(is_active)
	if is_active:
		hint_changed.emit("PLATE ACTIVE — THE VAULT DOOR IS OPEN")


func _on_door_open_state_changed(is_open: bool) -> void:
	door_state_changed.emit(is_open)


func _on_objective_collected(actor: Node) -> void:
	if actor != current_player:
		push_warning("Objective ignored collection from a non-live actor")
		return
	current_player.grant_objective()
	exit_zone.set_objective_available(true)
	objective_collected.emit()
	hint_changed.emit("TIME CORE SECURED — REACH THE CYAN EXIT")


func _on_exit_requested(actor: Node) -> void:
	if actor != current_player:
		return
	completion_requested.emit()


func _on_feedback_requested(message: String) -> void:
	hint_changed.emit(message)


func _on_visible_guard_status_for_hints(
	state_name: StringName,
	suspicion: float,
	target_id: StringName
) -> void:
	if state_name != &"suspicious":
		return
	if target_id == PlayerController.DETECTION_ID and not _shown_player_detection_hint:
		_shown_player_detection_hint = true
		hint_changed.emit("SEEN — BREAK LINE OF SIGHT OR LEAD THE GUARD UP TOP")
	elif String(target_id).begins_with("ghost_") and not _shown_ghost_detection_hint:
		_shown_ghost_detection_hint = true
		hint_changed.emit("YOUR GHOST IS DISTRACTING THE GUARD — TAKE THE LOWER LANE")
func _draw() -> void:
	draw_rect(Rect2(160.0, 128.0, 960.0, 512.0), Color("4b6780"), false, 3.0)
	draw_dashed_line(
		pressure_plate.position + Vector2(52.0, 0.0),
		security_door.position - Vector2(28.0, 0.0),
		Color("ffd76a"),
		3.0,
		10.0
	)
	var patrol_points: Array[Vector2] = []
	for child: Node in guard_patrol_route.get_children():
		if child is Marker2D:
			patrol_points.append((child as Marker2D).position)
	if patrol_points.size() >= 2:
		draw_dashed_line(
			guard_patrol_route.position + patrol_points[0],
			guard_patrol_route.position + patrol_points[1],
			Color(1.0, 0.52, 0.2, 0.55),
			2.0,
			8.0
		)
