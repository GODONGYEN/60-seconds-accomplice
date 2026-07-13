class_name GameHUD
extends CanvasLayer

signal resume_requested
signal restart_loop_requested
signal reset_timeline_requested
signal fullscreen_requested
signal volume_changed(linear_volume: float)
signal mute_requested

@onready var timer_label: Label = %TimerLabel
@onready var loop_label: Label = %LoopLabel
@onready var ghost_label: Label = %GhostLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var hint_label: Label = %HintLabel
@onready var interaction_label: Label = %InteractionLabel
@onready var pause_panel: Control = %PausePanel
@onready var victory_panel: Control = %VictoryPanel
@onready var victory_summary: Label = %VictorySummary
@onready var focus_overlay: Control = %FocusOverlay
@onready var volume_slider: HSlider = %VolumeSlider
@onready var mute_button: Button = %MuteButton
@onready var guard_status_label: Label = %GuardStatusLabel
@onready var guard_suspicion_meter: ProgressBar = %GuardSuspicionMeter
@onready var capture_panel: Control = %CapturePanel

var _muted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%ResumeButton.pressed.connect(func() -> void: resume_requested.emit())
	%RestartButton.pressed.connect(func() -> void: restart_loop_requested.emit())
	%ResetTimelineButton.pressed.connect(func() -> void: reset_timeline_requested.emit())
	%FullscreenButton.pressed.connect(func() -> void: fullscreen_requested.emit())
	%VictoryResetButton.pressed.connect(func() -> void: reset_timeline_requested.emit())
	%FocusButton.pressed.connect(_on_focus_button_pressed)
	mute_button.pressed.connect(func() -> void: mute_requested.emit())
	volume_slider.value_changed.connect(_on_volume_value_changed)
	pause_panel.visible = false
	victory_panel.visible = false
	focus_overlay.visible = true
	capture_panel.visible = false
	update_guard_status(&"hidden", 0.0, StringName())
	set_interaction_prompt("")


func update_loop(loop_index: int, ghost_count: int) -> void:
	loop_label.text = "TIMELINE  %02d" % loop_index
	ghost_label.text = "GHOSTS  %d / 8" % ghost_count
	objective_label.text = "OBJECTIVE  FIND THE TIME CORE"
	objective_label.modulate = Color("a9b5c7")
	capture_panel.visible = false


func update_time(remaining_seconds: float) -> void:
	var safe_time := maxf(0.0, remaining_seconds)
	timer_label.text = "%05.2f" % safe_time
	if safe_time <= 5.0:
		timer_label.modulate = Color("ff6a78")
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.045
		timer_label.scale = Vector2.ONE * pulse
	else:
		timer_label.modulate = Color("f3f7ff")
		timer_label.scale = Vector2.ONE


func set_hint(message: String) -> void:
	hint_label.text = message


func set_interaction_prompt(message: String) -> void:
	interaction_label.text = message
	interaction_label.visible = not message.is_empty()


func set_objective_collected() -> void:
	objective_label.text = "OBJECTIVE  TIME CORE SECURED"
	objective_label.modulate = Color("47e1a8")


func update_guard_status(
	state_name: StringName,
	suspicion: float,
	target_id: StringName
) -> void:
	guard_suspicion_meter.value = clampf(suspicion, 0.0, 1.0) * 100.0
	guard_suspicion_meter.visible = state_name != &"hidden"
	match state_name:
		&"hidden":
			guard_status_label.text = "GUARD  —  OUT OF SIGHT"
			guard_status_label.modulate = Color("718094")
		&"suspicious":
			guard_status_label.text = "GUARD  ? SUSPICIOUS"
			guard_status_label.modulate = Color("ffad4d")
		&"chase":
			guard_status_label.text = "GUARD  ! CHASING"
			guard_status_label.modulate = Color("ff5264")
		&"search":
			guard_status_label.text = "GUARD  ? SEARCHING"
			guard_status_label.modulate = Color("ffc163")
		_:
			guard_status_label.text = "GUARD  PATROLLING"
			guard_status_label.modulate = Color("8bdbe8")
	if not target_id.is_empty() and String(target_id).begins_with("ghost_"):
		guard_status_label.text += "  •  GHOST"


func show_capture_feedback() -> void:
	capture_panel.visible = true
	set_interaction_prompt("")


func set_pause_visible(value: bool) -> void:
	pause_panel.visible = value


func show_focus_overlay(message: String = "CLICK THE GAME TO START THE TIMELINE") -> void:
	%FocusMessage.text = message
	focus_overlay.visible = true


func hide_focus_overlay() -> void:
	focus_overlay.visible = false


func show_victory(loop_index: int, elapsed_seconds: float) -> void:
	victory_summary.text = "TIMELINE %02d  •  %.2fs\nPerfect synchronization with your past self." % [
		loop_index,
		elapsed_seconds,
	]
	victory_panel.visible = true
	pause_panel.visible = false
	focus_overlay.visible = false
	capture_panel.visible = false
	set_interaction_prompt("")


func hide_victory() -> void:
	victory_panel.visible = false
	capture_panel.visible = false


func set_muted(value: bool) -> void:
	_muted = value
	mute_button.text = "UNMUTE (M)" if _muted else "MUTE (M)"


func _on_focus_button_pressed() -> void:
	hide_focus_overlay()
	resume_requested.emit()


func _on_volume_value_changed(value: float) -> void:
	volume_changed.emit(clampf(value / 100.0, 0.0, 1.0))
