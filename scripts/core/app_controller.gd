class_name AppController
extends Node

signal mode_changed(mode: GameMode.Mode)
signal session_started(mode: GameMode.Mode, session: Node)
signal launch_failed(mode: GameMode.Mode, message: String)

const DEFAULT_OPERATION_SCENE_PATH: String = (
	"res://scenes/levels/operation_black_minute.tscn"
)

@export var operation_scene: PackedScene
@export var prototype_scene: PackedScene
@export var facility_regression_scene: PackedScene
@export var mission_definition: MissionDefinition
@export_file("*.tscn") var operation_scene_path: String = DEFAULT_OPERATION_SCENE_PATH

@onready var session_container: Node = %SessionContainer
@onready var main_menu: MainMenu = %MainMenu
@onready var mission_briefing: MissionBriefing = %MissionBriefing

var current_mode: GameMode.Mode = GameMode.Mode.MAIN_MENU
var current_session: Node = null
var _blueprint: Dictionary = {}
var _is_launching: bool = false
var _muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		_muted = AudioServer.is_bus_mute(master_bus)
	_connect_navigation_signals()
	_load_briefing_data()
	var requested_mode: GameMode.Mode = GameMode.requested_from_command_line()
	if requested_mode == GameMode.Mode.PROTOTYPE_LOOP:
		launch_mode(GameMode.Mode.PROTOTYPE_LOOP)
	elif requested_mode == GameMode.Mode.FACILITY_REGRESSION:
		launch_mode(GameMode.Mode.FACILITY_REGRESSION)
	else:
		show_main_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed(&"toggle_fullscreen"):
		toggle_global_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_mute"):
		toggle_global_mute()
		get_viewport().set_input_as_handled()


func show_main_menu() -> void:
	if _is_launching:
		return
	_unload_current_session()
	get_tree().paused = false
	current_mode = GameMode.Mode.MAIN_MENU
	mission_briefing.hide_briefing()
	main_menu.show_menu()
	mode_changed.emit(current_mode)


func show_operation_briefing() -> void:
	if _is_launching:
		return
	_unload_current_session()
	get_tree().paused = false
	main_menu.hide_menu()
	mission_briefing.configure(mission_definition, _blueprint)
	mission_briefing.show_briefing()


func launch_mode(mode: GameMode.Mode) -> bool:
	if _is_launching:
		return false
	var packed_scene: PackedScene = _get_scene_for_mode(mode)
	if packed_scene == null:
		var message := "No PackedScene configured for %s" % GameMode.get_display_name(mode)
		push_error(message)
		launch_failed.emit(mode, message)
		return false
	_is_launching = true
	_unload_current_session()
	get_tree().paused = false
	main_menu.hide_menu()
	mission_briefing.hide_briefing()
	var next_session: Node = packed_scene.instantiate()
	if next_session == null:
		_is_launching = false
		var message := "Failed to instantiate %s" % GameMode.get_display_name(mode)
		push_error(message)
		launch_failed.emit(mode, message)
		return false
	current_session = next_session
	current_mode = mode
	_connect_session_navigation(next_session)
	session_container.add_child(next_session)
	_is_launching = false
	mode_changed.emit(current_mode)
	session_started.emit(current_mode, current_session)
	return true


func get_current_session() -> Node:
	return current_session


func owns_global_utility_input() -> bool:
	return true


func toggle_global_fullscreen() -> void:
	var current_window_mode := DisplayServer.window_get_mode()
	if current_window_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func toggle_global_mute() -> bool:
	_muted = not _muted
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, _muted)
	return _muted


func is_global_muted() -> bool:
	return _muted


func _connect_navigation_signals() -> void:
	main_menu.new_operation_requested.connect(show_operation_briefing)
	main_menu.prototype_requested.connect(
		func() -> void: launch_mode(GameMode.Mode.PROTOTYPE_LOOP)
	)
	main_menu.facility_regression_requested.connect(
		func() -> void: launch_mode(GameMode.Mode.FACILITY_REGRESSION)
	)
	mission_briefing.start_requested.connect(
		func() -> void: launch_mode(GameMode.Mode.OPERATION_BLACK_MINUTE)
	)
	mission_briefing.back_requested.connect(show_main_menu)


func _connect_session_navigation(session: Node) -> void:
	if session.has_signal(&"return_to_menu_requested"):
		session.connect(&"return_to_menu_requested", show_main_menu)


func _get_scene_for_mode(mode: GameMode.Mode) -> PackedScene:
	match mode:
		GameMode.Mode.OPERATION_BLACK_MINUTE:
			if operation_scene != null:
				return operation_scene
			return _load_operation_scene_fallback()
		GameMode.Mode.PROTOTYPE_LOOP:
			return prototype_scene
		GameMode.Mode.FACILITY_REGRESSION:
			return facility_regression_scene
		_:
			return null


func _load_operation_scene_fallback() -> PackedScene:
	if operation_scene_path.is_empty() or not ResourceLoader.exists(operation_scene_path, "PackedScene"):
		return null
	return ResourceLoader.load(operation_scene_path, "PackedScene") as PackedScene


func _load_briefing_data() -> void:
	_blueprint.clear()
	if mission_definition == null:
		push_error("AppController requires a MissionDefinition resource")
		return
	if not mission_definition.validate():
		push_error("MissionDefinition '%s' failed validation" % mission_definition.mission_id)
		return
	var file := FileAccess.open(mission_definition.blueprint_path, FileAccess.READ)
	if file == null:
		push_error(
			"Could not open mission blueprint '%s': error %s"
			% [mission_definition.blueprint_path, FileAccess.get_open_error()]
		)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is not Dictionary:
		push_error("Mission blueprint root must be a Dictionary")
		return
	_blueprint = parsed as Dictionary
	mission_briefing.configure(mission_definition, _blueprint)


func _unload_current_session() -> void:
	if not is_instance_valid(current_session):
		current_session = null
		return
	var current_parent: Node = current_session.get_parent()
	if current_parent != null:
		current_parent.remove_child(current_session)
	current_session.queue_free()
	current_session = null
