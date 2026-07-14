extends SceneTree

const OPERATION_SCENE: PackedScene = preload(
	"res://scenes/levels/operation_black_minute.tscn"
)
const DEFAULT_OUTPUT_DIRECTORY: String = "/tmp/60sa-environment-captures"
const DEFAULT_SIZE := Vector2i(1280, 720)
const WORLD_SIZE := Vector2(2048.0, 1344.0)
const ROOM_TARGETS: Dictionary[String, Vector2] = {
	"yard": Vector2(240.0, 1232.0),
	"reception": Vector2(624.0, 1040.0),
	"cctv": Vector2(624.0, 272.0),
	"server": Vector2(1040.0, 272.0),
	"electrical": Vector2(1040.0, 624.0),
	"research": Vector2(1488.0, 272.0),
	"laser": Vector2(1488.0, 592.0),
	"vault": Vector2(1872.0, 272.0),
}

var _output_directory: String = DEFAULT_OUTPUT_DIRECTORY
var _capture_size: Vector2i = DEFAULT_SIZE


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
		quit(2)
		return
	operation.hud.reset_presentation()
	operation.process_mode = Node.PROCESS_MODE_DISABLED
	for room_name: String in ROOM_TARGETS:
		player.global_position = ROOM_TARGETS[room_name]
		await process_frame
		await process_frame
		_save_viewport("operation_%s_%dx%d.png" % [
			room_name, _capture_size.x, _capture_size.y,
		])
	await _capture_overview(operation, player)
	print("[environment-capture] wrote %d room views and one overview to %s" % [
		ROOM_TARGETS.size(), _output_directory,
	])
	quit()


func _capture_overview(
	operation: OperationBlackMinuteLevel,
	player: PlayerController
) -> void:
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
	_save_viewport("operation_overview_%dx%d.png" % [_capture_size.x, _capture_size.y])


func _save_viewport(file_name: String) -> void:
	var texture := root.get_texture()
	if texture == null:
		push_error("Environment capture requires a non-headless rendering backend")
		quit(2)
		return
	var error := texture.get_image().save_png(_output_directory.path_join(file_name))
	if error != OK:
		push_error("Failed to save environment capture '%s': %s" % [file_name, error_string(error)])
