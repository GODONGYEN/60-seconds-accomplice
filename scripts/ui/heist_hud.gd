class_name HeistHUD
extends CanvasLayer

signal map_requested
signal recall_requested
signal capture_recall_selected
signal checkpoint_restart_selected
signal mission_restart_requested
signal menu_requested
signal resume_requested

const COLOR_INFO := Color("72dce4")
const COLOR_OBJECTIVE := Color("62f3d1")
const COLOR_ACCESS := Color("74c9ff")
const COLOR_SECURITY := Color("75e1b5")
const COLOR_RECALL := Color("68bfff")
const COLOR_DANGER := Color("ff5964")
const COLOR_CORE := Color("c18cff")

@onready var primary_label: Label = %PrimaryLabel
@onready var current_label: Label = %CurrentLabel
@onready var security_label: Label = %SecurityLabel
@onready var access_label: Label = %AccessLabel
@onready var recall_label: Label = %RecallLabel
@onready var time_label: Label = %TimeLabel
@onready var prompt_label: Label = %PromptLabel
@onready var toast_label: Label = %ToastLabel
@onready var cue_card: PanelContainer = %CueCard
@onready var cue_title: Label = %CueTitle
@onready var cue_wash: ColorRect = %CueWash
@onready var capture_panel: Control = %CapturePanel
@onready var victory_panel: Control = %VictoryPanel
@onready var victory_card: PanelContainer = %VictoryCard

var _toast_serial: int = 0
var _cue_tween: Tween = null
var _debrief_tween: Tween = null
var _cue_style: StyleBoxFlat = null


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
	var base_style := cue_card.get_theme_stylebox("panel")
	if base_style is StyleBoxFlat:
		_cue_style = (base_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		cue_card.add_theme_stylebox_override("panel", _cue_style)
	reset_presentation()
	set_interaction_prompt("")
	call_deferred(&"_refresh_pivots")


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


func set_mission_time(seconds: float) -> void:
	var whole_seconds := maxi(0, floori(seconds))
	var minutes := whole_seconds / 60
	var remainder := whole_seconds % 60
	time_label.text = "TIME\n%02d:%02d" % [minutes, remainder]


func set_core_carried(value: bool) -> void:
	%CoreLabel.text = "CORE\nSECURED" if value else "CORE\nNOT ACQUIRED"
	%CoreLabel.modulate = Color("55e5a5") if value else Color("b894e8")


func set_interaction_prompt(message: String) -> void:
	prompt_label.text = message
	prompt_label.visible = not message.is_empty()


func show_toast(message: String, duration: float = 2.2) -> void:
	_show_cue("MISSION UPDATE", message, COLOR_INFO, duration)


func show_objective_cue(title: String) -> void:
	_show_cue("OBJECTIVE COMPLETE", title.to_upper(), COLOR_OBJECTIVE, 2.0)


func show_access_cue(access_name: String) -> void:
	_show_cue("ACCESS ACQUIRED", access_name.to_upper(), COLOR_ACCESS, 1.9)


func show_security_cue(message: String) -> void:
	_show_cue("SECURITY OVERRIDE", message.to_upper(), COLOR_SECURITY, 2.1)


func show_recall_cue(message: String = "ECHO ACTIVE") -> void:
	_show_cue("CHRONO RECALL", message.to_upper(), COLOR_RECALL, 2.0)


func show_danger_cue(title: String, detail: String = "") -> void:
	_show_cue(title.to_upper(), detail.to_upper(), COLOR_DANGER, 1.45)


func show_core_cue() -> void:
	_show_cue(
		"CHRONOS CORE SECURED",
		"RETURN TO EXTRACTION  //  LOCKDOWN ACTIVE",
		COLOR_CORE,
		2.8
	)


func show_capture_choice(can_recall: bool) -> void:
	_show_exclusive_modal(capture_panel)
	%CaptureRecallButton.visible = can_recall
	%CaptureMessage.text = (
		"CHRONO RECALL CAN RESTORE THE LAST 10 SECONDS.\nTHE ABANDONED ROUTE WILL REMAIN AS AN ECHO."
		if can_recall
		else "RECALL IS NOT YET AVAILABLE. RESTART FROM THE INFILTRATION CHECKPOINT."
	)
	if can_recall:
		%CaptureRecallButton.grab_focus.call_deferred()
	else:
		%CheckpointButton.grab_focus.call_deferred()


func hide_capture_choice() -> void:
	capture_panel.visible = false


func show_victory(result: Dictionary) -> void:
	_show_exclusive_modal(victory_panel)
	_kill_debrief_tween()
	var grade := String(result.get("grade", "C")).to_upper()
	var score := clampi(int(result.get("total_score", result.get("score", 0))), 0, 10000)
	var elapsed_seconds := maxf(0.0, float(result.get("elapsed_seconds", 0.0)))
	var recalls_used := maxi(0, int(result.get("recalls_used", 0)))
	var maximum_recalls := maxi(recalls_used, int(result.get("maximum_recalls", 0)))
	var live_detections := maxi(0, int(result.get("live_player_detections", 0)))
	var echo_detections := maxi(0, int(result.get("echo_detections", 0)))
	var capture_count := maxi(0, int(result.get("capture_count", result.get("captures", 0))))
	var route := String(result.get("authorization_route", "UNKNOWN")).to_upper()

	%VictoryGrade.text = grade
	%VictoryGrade.modulate = _grade_color(grade)
	%VictoryScore.text = "0 / 10000"
	%ElapsedValue.text = _format_duration_precise(elapsed_seconds)
	%RecallValue.text = "%d / %d" % [recalls_used, maximum_recalls]
	%DetectionValue.text = "%d LIVE  •  %d ECHO" % [live_detections, echo_detections]
	%CaptureValue.text = str(capture_count)
	%RouteValue.text = route
	%BonusList.text = _format_bonuses(result.get("bonuses", []))
	%VictoryDirective.text = _directive_for_grade(grade)

	victory_card.modulate.a = 0.0
	victory_card.scale = Vector2(0.97, 0.97)
	_debrief_tween = create_tween()
	_debrief_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_debrief_tween.set_parallel(true)
	_debrief_tween.tween_property(victory_card, "modulate:a", 1.0, 0.24)
	_debrief_tween.tween_property(victory_card, "scale", Vector2.ONE, 0.34).set_trans(
		Tween.TRANS_QUINT
	).set_ease(Tween.EASE_OUT)
	_debrief_tween.tween_method(_set_score_display, 0.0, float(score), 0.85).set_trans(
		Tween.TRANS_QUINT
	).set_ease(Tween.EASE_OUT)
	%RestartButton.grab_focus.call_deferred()


func hide_victory() -> void:
	_kill_debrief_tween()
	victory_panel.visible = false


func show_pause(value: bool) -> void:
	if value:
		_show_exclusive_modal(%PausePanel)
		%ResumeButton.grab_focus.call_deferred()
	else:
		%PausePanel.visible = false


func reset_presentation() -> void:
	_toast_serial += 1
	_kill_cue_tween()
	_kill_debrief_tween()
	toast_label.visible = false
	toast_label.text = ""
	cue_card.visible = false
	cue_wash.visible = false
	cue_card.modulate = Color.WHITE
	cue_card.scale = Vector2.ONE
	cue_wash.modulate = Color.WHITE
	capture_panel.visible = false
	victory_panel.visible = false
	%PausePanel.visible = false
	set_mission_time(0.0)
	set_core_carried(false)
	set_interaction_prompt("")


func _show_cue(title: String, message: String, accent: Color, duration: float) -> void:
	_toast_serial += 1
	_kill_cue_tween()
	cue_title.text = title
	toast_label.text = message
	toast_label.visible = not message.is_empty()
	if _cue_style != null:
		_cue_style.border_color = accent
	cue_title.add_theme_color_override("font_color", accent)
	cue_wash.color = Color(accent.r, accent.g, accent.b, 0.10)
	cue_wash.modulate.a = 0.0
	cue_wash.visible = true
	cue_card.modulate.a = 0.0
	cue_card.scale = Vector2(0.96, 0.96)
	cue_card.visible = true
	_refresh_pivots()

	_cue_tween = create_tween()
	_cue_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_cue_tween.set_parallel(false)
	var intro := _cue_tween.set_parallel(true)
	intro.tween_property(cue_card, "modulate:a", 1.0, 0.14)
	intro.tween_property(cue_card, "scale", Vector2.ONE, 0.22).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	intro.tween_property(cue_wash, "modulate:a", 1.0, 0.12)
	_cue_tween.chain().tween_interval(maxf(0.2, duration - 0.38))
	var outro := _cue_tween.chain().set_parallel(true)
	outro.tween_property(cue_card, "modulate:a", 0.0, 0.24)
	outro.tween_property(cue_card, "scale", Vector2(1.015, 1.015), 0.24)
	outro.tween_property(cue_wash, "modulate:a", 0.0, 0.28)
	_cue_tween.chain().tween_callback(_hide_cue)


func _show_exclusive_modal(panel: Control) -> void:
	if panel != victory_panel and victory_panel.visible:
		_kill_debrief_tween()
	for modal: Control in [capture_panel, victory_panel, %PausePanel]:
		modal.visible = modal == panel


func _hide_cue() -> void:
	cue_card.visible = false
	cue_wash.visible = false


func _kill_cue_tween() -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = null


func _kill_debrief_tween() -> void:
	if _debrief_tween != null and _debrief_tween.is_valid():
		_debrief_tween.kill()
	_debrief_tween = null


func _set_score_display(value: float) -> void:
	%VictoryScore.text = "%d / 10000" % roundi(value)


func _format_bonuses(value: Variant) -> String:
	if not value is Array or (value as Array).is_empty():
		return "—  BASE OPERATION SCORE"
	var lines := PackedStringArray()
	for entry: Variant in value as Array:
		if not entry is Dictionary:
			continue
		var bonus := entry as Dictionary
		var awarded := bool(bonus.get("awarded", false))
		var label := String(bonus.get("label", bonus.get("id", "BONUS"))).to_upper()
		var points := maxi(0, int(bonus.get("points", 0)))
		lines.append("%s  %s  +%d" % ["◆" if awarded else "◇", label, points if awarded else 0])
	return "\n".join(lines) if not lines.is_empty() else "—  BASE OPERATION SCORE"


func _format_duration_precise(seconds: float) -> String:
	var whole_seconds := maxi(0, floori(seconds))
	var minutes := whole_seconds / 60
	var remainder := whole_seconds % 60
	var tenths := clampi(floori(fmod(seconds, 1.0) * 10.0), 0, 9)
	return "%02d:%02d.%d" % [minutes, remainder, tenths]


func _grade_color(grade: String) -> Color:
	match grade:
		"S":
			return Color("62f3d1")
		"A":
			return Color("74c9ff")
		"B":
			return Color("e6c76a")
		_:
			return Color("ff8b65")


func _directive_for_grade(grade: String) -> String:
	match grade:
		"S":
			return "DIRECTIVE // TEMPORAL HEIST MASTERED. TRY THE OTHER TIMELINE STYLE."
		"A":
			return "DIRECTIVE // EXCELLENT. COMPLETE ONE MORE DIRECTIVE FOR MASTERY."
		"B":
			return "DIRECTIVE // ROUTE SECURED. USE ECHOES WITH GREATER PRECISION."
		_:
			return "DIRECTIVE // THE CORE IS OURS. REPLAY, ADAPT, IMPROVE."


func _refresh_pivots() -> void:
	cue_card.pivot_offset = cue_card.size * 0.5
	victory_card.pivot_offset = victory_card.size * 0.5
