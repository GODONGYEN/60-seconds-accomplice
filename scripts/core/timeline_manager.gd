class_name TimelineManager
extends Node

signal loop_started(loop_index: int, ghost_count: int)
signal loop_time_updated(remaining_seconds: float)
signal loop_ended(loop_index: int, reason: StringName)
signal recording_completed(recording: LoopRecording)
signal ghost_spawned(source_loop_index: int)
signal ghost_capacity_reached(maximum_ghosts: int)
signal level_completed(loop_index: int, elapsed_seconds: float)
signal timeline_error(message: String)

const REASON_TIMEOUT: StringName = &"timeout"
const REASON_RESTART: StringName = &"restart"
const REASON_VICTORY: StringName = &"victory"

enum RunState {
	IDLE,
	RUNNING,
	TRANSITION_PENDING,
	RESETTING,
	VICTORY,
}

@export_range(1.0, 120.0, 1.0) var loop_duration_seconds: float = 20.0
@export_range(1.0, 60.0, 1.0) var recording_frequency_hz: float = 20.0
@export_range(1, 8, 1) var max_ghosts: int = 8

@onready var action_recorder: ActionRecorder = %ActionRecorder

var current_loop_index: int = 0
var elapsed_time: float = 0.0
var run_state: RunState = RunState.IDLE
var recordings: Array[LoopRecording] = []

var _level: PrototypeLevel = null
var _active_ghosts: Array[GhostPlayback] = []
var _pending_reason: StringName = StringName()
var _ghost_cap_warning_emitted: bool = false


func _ready() -> void:
	process_physics_priority = 100
	set_physics_process(false)


func configure(level: PrototypeLevel) -> bool:
	if level == null or not is_instance_valid(level):
		_fail("TimelineManager requires a valid PrototypeLevel")
		return false
	if loop_duration_seconds <= 0.0:
		_fail("TimelineManager loop duration must be greater than zero")
		return false
	if recording_frequency_hz <= 0.0:
		_fail("TimelineManager recording frequency must be greater than zero")
		return false
	if max_ghosts <= 0:
		_fail("TimelineManager max_ghosts must be greater than zero")
		return false
	if not level.validate_level():
		_fail("TimelineManager refused to start an invalid level")
		return false

	_level = level
	action_recorder.sample_rate_hz = recording_frequency_hz
	if not _level.completion_requested.is_connected(complete_level):
		_level.completion_requested.connect(complete_level)
	return true


func start_session() -> bool:
	if _level == null:
		_fail("TimelineManager.start_session() called before configure()")
		return false
	recordings.clear()
	current_loop_index = 1
	_pending_reason = StringName()
	_ghost_cap_warning_emitted = false
	return _start_loop()


func request_restart() -> void:
	request_loop_end(REASON_RESTART)


func request_loop_end(reason: StringName) -> void:
	if run_state != RunState.RUNNING and run_state != RunState.TRANSITION_PENDING:
		return
	if reason == StringName():
		push_warning("TimelineManager ignored loop end request with an empty reason")
		return
	if run_state == RunState.TRANSITION_PENDING:
		if _reason_priority(reason) > _reason_priority(_pending_reason):
			_pending_reason = reason
		return

	_pending_reason = reason
	run_state = RunState.TRANSITION_PENDING
	_level.set_live_input_enabled(false)
	call_deferred(&"_commit_transition")


func complete_level() -> void:
	request_loop_end(REASON_VICTORY)


func reset_timeline() -> bool:
	if _level == null:
		return false
	_level.set_live_input_enabled(false)
	action_recorder.cancel_recording()
	recordings.clear()
	_active_ghosts.clear()
	_pending_reason = StringName()
	_ghost_cap_warning_emitted = false
	current_loop_index = 1
	run_state = RunState.RESETTING
	return _start_loop()


func get_remaining_time() -> float:
	return maxf(0.0, loop_duration_seconds - elapsed_time)


func get_active_ghost_count() -> int:
	return _active_ghosts.size()


func is_loop_running() -> bool:
	return run_state == RunState.RUNNING


func is_victory() -> bool:
	return run_state == RunState.VICTORY


func _physics_process(delta: float) -> void:
	if run_state != RunState.RUNNING:
		return
	elapsed_time = minf(loop_duration_seconds, elapsed_time + maxf(0.0, delta))
	action_recorder.capture_until(elapsed_time)
	for ghost: GhostPlayback in _active_ghosts:
		if is_instance_valid(ghost):
			ghost.advance_to(elapsed_time)
	loop_time_updated.emit(get_remaining_time())
	if elapsed_time >= loop_duration_seconds:
		request_loop_end(REASON_TIMEOUT)


func _start_loop() -> bool:
	run_state = RunState.RESETTING
	set_physics_process(false)
	_level.set_live_input_enabled(false)
	action_recorder.cancel_recording()
	_level.clear_runtime_actors()
	_level.reset_objects_for_loop()
	if not _level.rebuild_and_validate_registry():
		_fail("Stable object registry validation failed during loop reset")
		return false

	_active_ghosts.clear()
	for recording: LoopRecording in recordings:
		var ghost := _level.spawn_ghost(recording, recording.loop_index)
		if ghost == null:
			_fail("Failed to spawn Ghost for loop %d" % recording.loop_index)
			return false
		_active_ghosts.append(ghost)
		ghost_spawned.emit(recording.loop_index)

	var player := _level.spawn_player()
	if player == null:
		_fail("Failed to spawn the live Player")
		return false
	player.restart_requested.connect(request_restart)
	player.interaction_recorded.connect(_on_interaction_recorded)

	elapsed_time = 0.0
	if not action_recorder.begin_recording(player, loop_duration_seconds):
		_fail("ActionRecorder failed to begin loop %d" % current_loop_index)
		return false
	for ghost: GhostPlayback in _active_ghosts:
		ghost.reset_playback()
		ghost.advance_to(0.0)

	_pending_reason = StringName()
	run_state = RunState.RUNNING
	set_physics_process(true)
	_level.set_live_input_enabled(true)
	loop_started.emit(current_loop_index, _active_ghosts.size())
	loop_time_updated.emit(loop_duration_seconds)
	print(
		"[Timeline] Loop %d started with %d Ghost(s)"
		% [current_loop_index, _active_ghosts.size()]
	)
	return true


func _commit_transition() -> void:
	if run_state != RunState.TRANSITION_PENDING:
		return
	var reason := _pending_reason
	set_physics_process(false)
	_level.set_live_input_enabled(false)

	if reason == REASON_VICTORY:
		action_recorder.cancel_recording()
		run_state = RunState.VICTORY
		loop_ended.emit(current_loop_index, reason)
		level_completed.emit(current_loop_index, elapsed_time)
		print("[Timeline] Level completed on loop %d at %.2fs" % [current_loop_index, elapsed_time])
		return

	var completed_recording := action_recorder.finish_recording(
		elapsed_time,
		current_loop_index
	)
	if not completed_recording.is_chronological():
		_fail("Loop %d produced a non-chronological recording" % current_loop_index)
		return
	if recordings.size() < max_ghosts:
		var immutable_copy := completed_recording.duplicate_recording()
		recordings.append(immutable_copy)
		recording_completed.emit(immutable_copy)
	elif not _ghost_cap_warning_emitted:
		_ghost_cap_warning_emitted = true
		push_warning(
			"[Timeline] Ghost cap %d reached on loop %d; the new recording was not retained."
			% [max_ghosts, current_loop_index]
		)

	loop_ended.emit(current_loop_index, reason)
	print("[Timeline] Loop %d ended: %s" % [current_loop_index, reason])
	current_loop_index += 1
	run_state = RunState.RESETTING
	var next_loop_started := _start_loop()
	if next_loop_started and recordings.size() >= max_ghosts:
		# loop_started updates onboarding first; this notice must remain the last HUD hint.
		ghost_capacity_reached.emit(max_ghosts)


func _on_interaction_recorded(
	target_object_id: StringName,
	event_type: StringName,
	payload: Dictionary
) -> void:
	if run_state != RunState.RUNNING:
		return
	action_recorder.record_interaction(
		elapsed_time,
		target_object_id,
		event_type,
		payload
	)


func _fail(message: String) -> void:
	push_error(message)
	run_state = RunState.IDLE
	set_physics_process(false)
	if _level != null:
		_level.set_live_input_enabled(false)
	timeline_error.emit(message)


func _reason_priority(reason: StringName) -> int:
	match reason:
		REASON_VICTORY:
			return 3
		REASON_RESTART:
			return 2
		REASON_TIMEOUT:
			return 1
		_:
			return 0
