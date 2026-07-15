extends SceneTree

const OPERATION_SCENE: PackedScene = preload(
	"res://scenes/levels/operation_black_minute.tscn"
)
const DEFAULT_OUTPUT_DIRECTORY: String = "/tmp/60sa-environment-captures"
const DEFAULT_SIZE := Vector2i(1280, 720)
const WORLD_SIZE := Vector2(2048.0, 1344.0)
const ROOM_TARGETS: Dictionary[String, Vector2] = {
	"yard": Vector2(208.0, 1104.0),
	"reception": Vector2(608.0, 1040.0),
	"staff": Vector2(608.0, 624.0),
	"locker": Vector2(208.0, 608.0),
	"security": Vector2(1024.0, 1040.0),
	"cctv": Vector2(608.0, 256.0),
	"electrical": Vector2(1024.0, 624.0),
	"server": Vector2(1024.0, 256.0),
	"research": Vector2(1472.0, 272.0),
	"guard_break": Vector2(208.0, 256.0),
	"laser": Vector2(1472.0, 592.0),
	"vault_antechamber": Vector2(1888.0, 640.0),
	"vault": Vector2(1872.0, 272.0),
	"maintenance": Vector2(1472.0, 896.0),
	"extraction": Vector2(1648.0, 1200.0),
}

var _output_directory: String = DEFAULT_OUTPUT_DIRECTORY
var _capture_size: Vector2i = DEFAULT_SIZE
var _capture_mode: StringName = &"gameplay_initial"
var _presentation_time: float = 0.5


func _initialize() -> void:
	_parse_arguments()
	call_deferred(&"_capture")


func _parse_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			_output_directory = argument.trim_prefix("--output-dir=")
		elif argument.begins_with("--size="):
			var parts := argument.trim_prefix("--size=").split("x")
			if parts.size() == 2:
				var parsed := Vector2i(int(parts[0]), int(parts[1]))
				if parsed.x >= 640 and parsed.y >= 480:
					_capture_size = parsed
		elif argument.begins_with("--mode="):
			var requested_mode := StringName(argument.trim_prefix("--mode="))
			if requested_mode in [&"art_clean", &"gameplay_initial", &"gameplay_late"]:
				_capture_mode = requested_mode
		elif argument.begins_with("--presentation-time="):
			_presentation_time = maxf(
				0.0,
				float(argument.trim_prefix("--presentation-time="))
			)


func _capture() -> void:
	if DirAccess.make_dir_recursive_absolute(_output_directory) != OK:
		push_error("Cannot create screenshot directory: %s" % _output_directory)
		quit(2)
		return
	root.size = _capture_size
	var operation := OPERATION_SCENE.instantiate() as OperationBlackMinuteLevel
	if operation == null:
		push_error("Environment capture scene has the wrong root type")
		quit(2)
		return
	root.add_child(operation)
	await process_frame
	await physics_frame
	await process_frame
	var player: PlayerController = operation.get_player()
	if player == null:
		push_error("Environment capture could not find the operation Player")
		await _quit_capture_failure(operation)
		return
	operation.hud.reset_presentation()
	_prepare_capture_mode(operation)
	operation.process_mode = Node.PROCESS_MODE_DISABLED
	operation.operation_map.environment_presenter.set_presentation_time_for_capture(
		_presentation_time
	)
	for room_name: String in ROOM_TARGETS:
		player.global_position = _nearest_walkable_position(
			operation.operation_map,
			ROOM_TARGETS[room_name]
		)
		await process_frame
		await process_frame
		_clear_capture_modals(operation)
		if not _save_viewport("operation_%s_%s_%dx%d.png" % [
			_capture_mode, room_name, _capture_size.x, _capture_size.y,
		]):
			await _quit_capture_failure(operation)
			return
	if not await _capture_overview(operation, player):
		await _quit_capture_failure(operation)
		return
	print("[environment-capture] wrote %d %s room views and one overview to %s" % [
		ROOM_TARGETS.size(), _capture_mode, _output_directory,
	])
	quit()


func _quit_capture_failure(operation: Node) -> void:
	operation.queue_free()
	await process_frame
	quit(2)


func _capture_overview(
	operation: OperationBlackMinuteLevel,
	player: PlayerController
) -> bool:
	operation.hud.visible = false
	operation.map_overlay.visible = false
	operation.get_node(^"CanvasModulate").color = Color.WHITE
	operation.get_node(^"ActorLayer").visible = false
	operation.get_node(^"DynamicObjects").visible = false
	operation.get_node(^"ProgressionTriggers").visible = false
	player.global_position = WORLD_SIZE * 0.5
	var fit_scale := minf(
		float(_capture_size.x - 48) / WORLD_SIZE.x,
		float(_capture_size.y - 48) / WORLD_SIZE.y
	)
	player.player_camera.zoom = Vector2.ONE * fit_scale
	await process_frame
	await process_frame
	return _save_viewport(
		"operation_%s_overview_%dx%d.png" % [
			_capture_mode, _capture_size.x, _capture_size.y,
		]
	)


func _prepare_capture_mode(operation: OperationBlackMinuteLevel) -> void:
	if _capture_mode == &"gameplay_late":
		var security := operation.get_node(^"Systems/SecuritySystemManager") as SecuritySystemManager
		security.disable_cctv_network()
		security.disable_laser_network()
		security.raise_facility_alert(SecuritySystemManager.AlertLevel.LOCKDOWN)
		operation.operation_map.set_core_visual_state(true)
		operation.operation_map.set_extraction_visual_state(true)
		for child: Node in operation.dynamic_objects.get_children():
			if child is AccessDoor:
				(child as AccessDoor).unlock_and_open()
	elif _capture_mode == &"art_clean":
		operation.hud.visible = false
		operation.map_overlay.visible = false
		operation.actor_layer.visible = false
		operation.dynamic_objects.visible = false
		operation.trigger_container.visible = false
		operation.operation_map.room_labels.visible = false


func _clear_capture_modals(operation: OperationBlackMinuteLevel) -> void:
	# Native screenshot runs can lose application focus while the renderer is in
	# the background. Focus safety must remain enabled in production, so evidence
	# capture clears only its presentation modal immediately before each frame.
	paused = false
	operation.hud.show_pause(false)
	operation.hud.hide_capture_choice()
	operation.hud.hide_victory()


func _nearest_walkable_position(
	operation_map: OperationBlackMinuteMap,
	requested_world_position: Vector2
) -> Vector2:
	var requested_cell := Vector2i(
		(requested_world_position / float(OperationBlackMinuteMap.TILE_SIZE)).floor()
	)
	if operation_map.is_walkable_cell(requested_cell):
		return OperationBlackMinuteMap.cell_to_world(requested_cell)
	for radius: int in range(1, 12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) != radius and absi(y) != radius:
					continue
				var candidate := requested_cell + Vector2i(x, y)
				if operation_map.is_walkable_cell(candidate):
					return OperationBlackMinuteMap.cell_to_world(candidate)
	push_error("Environment capture could not find a walkable cell near %s" % requested_cell)
	return requested_world_position


func _save_viewport(file_name: String) -> bool:
	if DisplayServer.get_name() == "headless":
		push_error("Environment capture requires a non-headless rendering backend")
		return false
	var texture := root.get_texture()
	if texture == null:
		push_error("Environment capture requires a non-headless rendering backend")
		return false
	var image := texture.get_image()
	if image == null:
		push_error("Environment capture could not read the rendered viewport image")
		return false
	if image.get_size() != _capture_size:
		push_error(
			"Environment capture size mismatch: requested %s, rendered %s"
			% [_capture_size, image.get_size()]
		)
		return false
	var error := image.save_png(_output_directory.path_join(file_name))
	if error != OK:
		push_error("Failed to save environment capture '%s': %s" % [file_name, error_string(error)])
		return false
	return true
