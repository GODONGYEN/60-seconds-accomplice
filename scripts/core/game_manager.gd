class_name GameManager
extends Node2D

@onready var level: GameplayLevel = %CurrentLevel
@onready var timeline: TimelineManager = %TimelineManager
@onready var hud: GameHUD = %HUD
@onready var audio_feedback: AudioFeedback = %AudioFeedback

var _is_paused: bool = false
var _muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_connect_gameplay_signals()
	_connect_ui_signals()
	if not timeline.configure(level):
		hud.set_hint("PROJECT INITIALIZATION FAILED — CHECK THE CONSOLE")
		return
	if not timeline.start_session():
		hud.set_hint("FAILED TO START THE FIRST TIMELINE")
		return
	_pause_game(true, false)
	hud.show_focus_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if timeline.is_victory():
			return
		if _is_paused:
			_resume_game()
		else:
			_pause_game(true, true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mute"):
		_toggle_mute()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_inside_tree():
		if timeline != null and not timeline.is_victory():
			_pause_game(true, false)
			hud.show_focus_overlay("FOCUS LOST — CLICK TO CONTINUE")


func _connect_gameplay_signals() -> void:
	timeline.loop_started.connect(_on_loop_started)
	timeline.loop_time_updated.connect(hud.update_time)
	timeline.level_completed.connect(_on_level_completed)
	timeline.capture_feedback_requested.connect(_on_capture_feedback_requested)
	timeline.ghost_capacity_reached.connect(_on_ghost_capacity_reached)
	timeline.timeline_error.connect(hud.set_hint)
	level.hint_changed.connect(hud.set_hint)
	level.interaction_prompt_changed.connect(hud.set_interaction_prompt)
	level.objective_collected.connect(_on_objective_collected)
	level.door_state_changed.connect(audio_feedback.play_door)
	level.guard_status_changed.connect(hud.update_guard_status)
	level.guard_state_changed.connect(_on_guard_state_changed)


func _connect_ui_signals() -> void:
	hud.resume_requested.connect(_resume_game)
	hud.restart_loop_requested.connect(_restart_loop_from_ui)
	hud.reset_timeline_requested.connect(_reset_timeline_from_ui)
	hud.fullscreen_requested.connect(_toggle_fullscreen)
	hud.volume_changed.connect(_set_volume)
	hud.mute_requested.connect(_toggle_mute)


func _on_loop_started(loop_index: int, ghost_count: int) -> void:
	hud.update_loop(loop_index, ghost_count)
	hud.set_hint(level.get_loop_hint(loop_index))
	hud.hide_victory()
	audio_feedback.play_loop_start()
	hud.update_guard_status(&"hidden", 0.0, StringName())
	level.refresh_visible_guard_status()


func _on_objective_collected() -> void:
	hud.set_objective_collected()
	audio_feedback.play_objective()


func _on_level_completed(loop_index: int, elapsed_seconds: float) -> void:
	_is_paused = false
	get_tree().paused = false
	hud.show_victory(loop_index, elapsed_seconds)
	audio_feedback.play_victory()


func _on_capture_feedback_requested(_loop_index: int, _elapsed_seconds: float) -> void:
	hud.show_capture_feedback()
	audio_feedback.play_capture()


func _on_guard_state_changed(state_name: StringName) -> void:
	if state_name == &"suspicious":
		audio_feedback.play_suspicion()
	elif state_name == &"chase":
		audio_feedback.play_alert()


func _on_ghost_capacity_reached(maximum_ghosts: int) -> void:
	hud.set_hint(
		"GHOST LIMIT %d REACHED — ESC > RESET ALL TIMELINES" % maximum_ghosts
	)


func _pause_game(value: bool, show_menu: bool) -> void:
	if timeline != null and timeline.is_victory():
		return
	_is_paused = value
	if level != null:
		level.set_live_input_enabled(not value and timeline.is_loop_running())
	get_tree().paused = value
	hud.set_pause_visible(value and show_menu)


func _resume_game() -> void:
	if timeline.is_victory():
		return
	_pause_game(false, false)
	hud.hide_focus_overlay()


func _restart_loop_from_ui() -> void:
	_resume_game()
	timeline.request_restart()


func _reset_timeline_from_ui() -> void:
	get_tree().paused = false
	_is_paused = false
	hud.set_pause_visible(false)
	hud.hide_focus_overlay()
	hud.hide_victory()
	timeline.reset_timeline()


func _toggle_fullscreen() -> void:
	var global_owner := _get_global_utility_input_owner()
	if global_owner != null:
		global_owner.call(&"toggle_global_fullscreen")
		return
	var current_mode := DisplayServer.window_get_mode()
	if current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _toggle_mute() -> void:
	var global_owner := _get_global_utility_input_owner()
	if global_owner != null:
		var muted: bool = bool(global_owner.call(&"toggle_global_mute"))
		hud.set_muted(muted)
		return
	_muted = not _muted
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, _muted)
	hud.set_muted(_muted)


func _set_volume(linear_volume: float) -> void:
	var master_bus := AudioServer.get_bus_index(&"Master")
	if master_bus < 0:
		return
	var safe_volume := clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_volume_db(
		master_bus,
		-80.0 if safe_volume <= 0.001 else linear_to_db(safe_volume)
	)


func _get_global_utility_input_owner() -> Node:
	var ancestor: Node = get_parent()
	while ancestor != null:
		if ancestor.has_method(&"owns_global_utility_input"):
			if bool(ancestor.call(&"owns_global_utility_input")):
				return ancestor
		ancestor = ancestor.get_parent()
	return null
