class_name MainMenu
extends CanvasLayer

signal new_operation_requested
signal prototype_requested
signal facility_regression_requested

@onready var info_panel: PanelContainer = %InfoPanel
@onready var info_title: Label = %InfoTitle
@onready var info_body: Label = %InfoBody


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	%NewOperationButton.pressed.connect(func() -> void: new_operation_requested.emit())
	%BlackMinuteButton.pressed.connect(func() -> void: new_operation_requested.emit())
	%PrototypeButton.pressed.connect(func() -> void: prototype_requested.emit())
	%FacilityButton.pressed.connect(func() -> void: facility_regression_requested.emit())
	%HowButton.pressed.connect(_show_how_to_play)
	%SettingsButton.pressed.connect(_show_settings)
	%CreditsButton.pressed.connect(_show_credits)
	%CloseInfoButton.pressed.connect(func() -> void: info_panel.visible = false)
	info_panel.visible = false


func show_menu() -> void:
	visible = true


func hide_menu() -> void:
	visible = false
	info_panel.visible = false


func _show_how_to_play() -> void:
	_show_info(
		"HOW TO PLAY",
		"Plan the route. Observe deterministic patrols. Acquire access cards. "
		+ "Disable or avoid CCTV and lasers. Press M or Tab for the tactical map. "
		+ "Press Q to spend one of three 10-second Chrono Recall charges and leave an Echo."
	)


func _show_settings() -> void:
	_show_info(
		"SETTINGS",
		"ESC pauses. F11 toggles fullscreen. V mutes audio. Important states use text and shape as well as color."
	)


func _show_credits() -> void:
	_show_info(
		"CREDITS",
		"Designed and built as an open Godot 4.7 project. Project-authored code and visuals are distributed under the repository licenses."
	)


func _show_info(title: String, body: String) -> void:
	info_title.text = title
	info_body.text = body
	info_panel.visible = true
