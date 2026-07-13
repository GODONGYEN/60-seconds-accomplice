class_name HeistHUD
extends CanvasLayer

signal map_requested
signal recall_requested
signal capture_recall_selected
signal checkpoint_restart_selected
signal mission_restart_requested
signal menu_requested
signal resume_requested

@onready var primary_label: Label = %PrimaryLabel
@onready var current_label: Label = %CurrentLabel
@onready var security_label: Label = %SecurityLabel
@onready var access_label: Label = %AccessLabel
@onready var recall_label: Label = %RecallLabel
@onready var prompt_label: Label = %PromptLabel
@onready var toast_label: Label = %ToastLabel
@onready var capture_panel: Control = %CapturePanel
@onready var victory_panel: Control = %VictoryPanel

var _toast_serial: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%MapButton.pressed.connect(func() -> void: map_requested.emit())
	%RecallButton.pressed.connect(func() -> void: recall_requested.emit())
	%CaptureRecallButton.pressed.connect(func() -> void: capture_recall_selected.emit())
	%CheckpointButton.pressed.connect(func() -> void: checkpoint_restart_selected.emit())
	%RestartButton.pressed.connect(func() -> void: mission_restart_requested.emit())
	%MenuButton.pressed.connect(func() -> void: menu_requested.emit())
	%ResumeButton.pressed.connect(func() -> void: resume_requested.emit())
	%PauseMenuButton.pressed.connect(func() -> void: menu_requested.emit())
	capture_panel.visible = false
	victory_panel.visible = false
	%PausePanel.visible = false
	toast_label.visible = false
	set_interaction_prompt("")


func set_primary_objective(title: String) -> void:
	primary_label.text = "PRIMARY\n%s" % title


func set_objectives(lines: PackedStringArray) -> void:
	current_label.text = "CURRENT\n• " + "\n• ".join(lines)


func set_security(
	cctv_online: bool,
	laser_online: bool,
	alert_label: StringName
) -> void:
	security_label.text = "SECURITY\nCCTV %s  •  LASERS %s\nALERT  %s" % [
		"ONLINE" if cctv_online else "OFFLINE",
		"ONLINE" if laser_online else "OFFLINE",
		alert_label,
	]


func set_access(access_name: StringName) -> void:
	access_label.text = "ACCESS\n%s" % access_name


func set_recall_charges(remaining: int, maximum: int) -> void:
	var label_text := "RECALL  Q\n%d / %d" % [remaining, maximum]
	recall_label.text = label_text
	%RecallButton.text = label_text
	%RecallButton.disabled = remaining <= 0


func set_core_carried(value: bool) -> void:
	%CoreLabel.text = "CORE\nSECURED" if value else "CORE\nNOT ACQUIRED"
	%CoreLabel.modulate = Color("55e5a5") if value else Color("b894e8")


func set_interaction_prompt(message: String) -> void:
	prompt_label.text = message
	prompt_label.visible = not message.is_empty()


func show_toast(message: String, duration: float = 2.2) -> void:
	_toast_serial += 1
	var serial := _toast_serial
	toast_label.text = message
	toast_label.visible = true
	_hide_toast_later(serial, duration)


func show_capture_choice(can_recall: bool) -> void:
	capture_panel.visible = true
	%CaptureRecallButton.visible = can_recall
	%CaptureMessage.text = (
		"CHRONO RECALL CAN RESTORE THE LAST 10 SECONDS.\nTHE ABANDONED ROUTE WILL REMAIN AS AN ECHO."
		if can_recall
		else "RECALL IS NOT YET AVAILABLE. RESTART FROM THE INFILTRATION CHECKPOINT."
	)


func hide_capture_choice() -> void:
	capture_panel.visible = false


func show_victory(recalls_used: int) -> void:
	victory_panel.visible = true
	%VictorySummary.text = (
		"CHRONOS CORE EXTRACTED\nRECALLS USED  %d\n\nHELIX NEVER SAW THE WHOLE PLAN."
		% recalls_used
	)


func hide_victory() -> void:
	victory_panel.visible = false


func show_pause(value: bool) -> void:
	%PausePanel.visible = value


func _hide_toast_later(serial: int, duration: float) -> void:
	await get_tree().create_timer(maxf(0.1, duration), true).timeout
	if serial == _toast_serial:
		toast_label.visible = false
