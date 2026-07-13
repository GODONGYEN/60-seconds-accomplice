class_name OperationBlackMinuteMap
extends Node2D

const BLUEPRINT_PATH: String = "res://resources/maps/operation_black_minute_blueprint.json"
const FACILITY_TILESET: TileSet = preload("res://resources/tilesets/facility_tileset.tres")
const SOURCE_ID: int = 0
const TILE_SIZE: int = 32
const MAP_SIZE := Vector2i(64, 42)
const WORLD_SIZE := Vector2i(2048, 1344)

const BASE_FLOOR := Vector2i(7, 3)
const FLOOR_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(4, 0),
]
const WALL := Vector2i(0, 2)
const WALL_CORNER := Vector2i(1, 2)
const TERMINAL := Vector2i(4, 2)
const SERVER := Vector2i(5, 2)
const METAL_CRATE := Vector2i(3, 2)
const PLANT := Vector2i(7, 2)

@onready var floor: TileMapLayer = %Floor
@onready var floor_details: TileMapLayer = %FloorDetails
@onready var walls: TileMapLayer = %Walls
@onready var props_below: TileMapLayer = %PropsBelow
@onready var props_above: TileMapLayer = %PropsAbove
@onready var room_labels: Node2D = %RoomLabels
@onready var observation_windows: Node2D = %ObservationWindows

var _blueprint: Dictionary = {}
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _room_by_cell: Dictionary[Vector2i, StringName] = {}
var _solid_cells: Dictionary[Vector2i, bool] = {}


func _ready() -> void:
	if not load_blueprint():
		return
	rebuild_map()


func load_blueprint() -> bool:
	var file := FileAccess.open(BLUEPRINT_PATH, FileAccess.READ)
	if file == null:
		push_error("OperationBlackMinuteMap cannot open %s" % BLUEPRINT_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("OperationBlackMinuteMap blueprint must parse as a Dictionary")
		return false
	_blueprint = (parsed as Dictionary).duplicate(true)
	if _json_vector(_blueprint.get("size", [])) != MAP_SIZE:
		push_error("OperationBlackMinuteMap blueprint must be exactly 64x42")
		return false
	_build_topology_cache()
	return true


func rebuild_map() -> void:
	_configure_layers()
	for layer: TileMapLayer in [floor, floor_details, walls, props_below, props_above]:
		layer.clear()
	for y: int in range(MAP_SIZE.y):
		for x: int in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			if is_walkable_cell(cell):
				floor.set_cell(cell, SOURCE_ID, BASE_FLOOR)
				_place_room_floor_detail(cell)
			else:
				walls.set_cell(cell, SOURCE_ID, _select_wall_tile(cell))
	_place_functional_props()
	_build_room_labels()
	_build_observation_windows()
	for layer: TileMapLayer in [floor, floor_details, walls, props_below, props_above]:
		layer.update_internals()


func get_blueprint() -> Dictionary:
	return _blueprint.duplicate(true)


func get_map_size() -> Vector2i:
	return MAP_SIZE


func get_world_size() -> Vector2i:
	return WORLD_SIZE


func is_walkable_cell(cell: Vector2i) -> bool:
	return bool(_walkable_cells.get(cell, false)) and not bool(_solid_cells.get(cell, false))


func is_wall_cell(cell: Vector2i) -> bool:
	return is_cell_in_bounds(cell) and not is_walkable_cell(cell)


func get_room_at_cell(cell: Vector2i) -> StringName:
	return _room_by_cell.get(cell, StringName())


func get_room_rect(room_id: StringName) -> Rect2i:
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		return Rect2i()
	var room_variant: Variant = (rooms_variant as Dictionary).get(String(room_id), {})
	if not room_variant is Dictionary:
		return Rect2i()
	return _json_rect((room_variant as Dictionary).get("rect", []))


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2.ONE * (TILE_SIZE * 0.5)


static func is_cell_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_SIZE.x and cell.y < MAP_SIZE.y


func _configure_layers() -> void:
	for layer: TileMapLayer in [floor, floor_details, walls, props_below, props_above]:
		layer.tile_set = FACILITY_TILESET
	floor.collision_enabled = false
	floor.occlusion_enabled = false
	floor_details.collision_enabled = false
	floor_details.occlusion_enabled = false
	walls.collision_enabled = true
	walls.occlusion_enabled = true
	props_below.collision_enabled = false
	props_below.occlusion_enabled = false
	props_above.collision_enabled = false
	props_above.occlusion_enabled = false


func _build_topology_cache() -> void:
	_walkable_cells.clear()
	_room_by_cell.clear()
	_solid_cells.clear()
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if rooms_variant is Dictionary:
		for room_key: Variant in (rooms_variant as Dictionary).keys():
			var room_id := StringName(str(room_key))
			var room_data := (rooms_variant as Dictionary)[room_key] as Dictionary
			var rect := _json_rect(room_data.get("rect", []))
			_mark_rect_walkable(rect, room_id)
	for collection_name: String in ["connectors", "dynamic_portals"]:
		var collection_variant: Variant = _blueprint.get(collection_name, [])
		if not collection_variant is Array:
			continue
		for entry_variant: Variant in collection_variant as Array:
			if not entry_variant is Dictionary:
				continue
			var entry := entry_variant as Dictionary
			var rect_key := "span_rect" if collection_name == "dynamic_portals" else "rect"
			_mark_rect_walkable(_json_rect(entry.get(rect_key, [])), StringName())
	var solids_variant: Variant = _blueprint.get("internal_solid_rects", [])
	if solids_variant is Array:
		for solid_variant: Variant in solids_variant as Array:
			if not solid_variant is Dictionary:
				continue
			for cell: Vector2i in _cells_in_rect(_json_rect((solid_variant as Dictionary).get("rect", []))):
				_solid_cells[cell] = true


func _mark_rect_walkable(rect: Rect2i, room_id: StringName) -> void:
	for cell: Vector2i in _cells_in_rect(rect):
		if not is_cell_in_bounds(cell):
			continue
		_walkable_cells[cell] = true
		if room_id != StringName():
			_room_by_cell[cell] = room_id


func _place_room_floor_detail(cell: Vector2i) -> void:
	var room_id := get_room_at_cell(cell)
	if room_id == StringName() or (cell.x + cell.y) % 3 != 0:
		return
	var variant_index: int = absi(String(room_id).hash()) % FLOOR_VARIANTS.size()
	floor_details.set_cell(cell, SOURCE_ID, FLOOR_VARIANTS[variant_index])


func _place_functional_props() -> void:
	var placements: Dictionary = {
		&"cctv_control_room": [TERMINAL, SERVER, SERVER],
		&"electrical_room": [TERMINAL, METAL_CRATE, METAL_CRATE],
		&"server_room": [SERVER, SERVER, SERVER],
		&"research_laboratory": [TERMINAL, METAL_CRATE, PLANT],
		&"security_office": [TERMINAL, METAL_CRATE, PLANT],
		&"guard_break_room": [METAL_CRATE, PLANT],
		&"staff_office": [TERMINAL, PLANT],
	}
	for room_variant: Variant in placements.keys():
		var room_id := StringName(str(room_variant))
		var rect := get_room_rect(room_id)
		var tiles: Array = placements[room_variant] as Array
		for index: int in range(tiles.size()):
			var cell := rect.position + Vector2i(1 + index * 2, 1)
			if is_walkable_cell(cell):
				var atlas_coordinates: Vector2i = tiles[index]
				props_above.set_cell(cell, SOURCE_ID, atlas_coordinates)


func _build_room_labels() -> void:
	for child: Node in room_labels.get_children():
		child.queue_free()
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		return
	for room_key: Variant in (rooms_variant as Dictionary).keys():
		var room_data := (rooms_variant as Dictionary)[room_key] as Dictionary
		var rect := _json_rect(room_data.get("rect", []))
		var label := Label.new()
		label.text = String(room_data.get("display_name", str(room_key))).to_upper()
		label.position = Vector2(rect.position * TILE_SIZE) + Vector2(10.0, 7.0)
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color(0.42, 0.75, 0.82, 0.68))
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.05, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		room_labels.add_child(label)


func _build_observation_windows() -> void:
	for child: Node in observation_windows.get_children():
		child.queue_free()
	var windows_variant: Variant = _blueprint.get("observation_windows", [])
	if not windows_variant is Array:
		return
	for window_variant: Variant in windows_variant as Array:
		if not window_variant is Dictionary:
			continue
		var window_data := window_variant as Dictionary
		var rect := _json_rect(window_data.get("rect", []))
		var body := StaticBody2D.new()
		body.name = String(window_data.get("id", "ObservationWindow"))
		body.collision_layer = 1
		body.collision_mask = 0
		var shape_node := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(rect.size * TILE_SIZE)
		shape_node.shape = shape
		body.position = Vector2(rect.position * TILE_SIZE) + shape.size * 0.5
		body.add_child(shape_node)
		var line := Line2D.new()
		line.width = 4.0
		line.default_color = Color(0.25, 0.9, 1.0, 0.55)
		line.points = PackedVector2Array([
			-shape.size * 0.5,
			Vector2(shape.size.x * 0.5, -shape.size.y * 0.5),
			shape.size * 0.5,
			Vector2(-shape.size.x * 0.5, shape.size.y * 0.5),
			-shape.size * 0.5,
		])
		body.add_child(line)
		observation_windows.add_child(body)


func _select_wall_tile(cell: Vector2i) -> Vector2i:
	var adjacent_floor_count := 0
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if is_walkable_cell(cell + offset):
			adjacent_floor_count += 1
	return WALL_CORNER if adjacent_floor_count >= 2 else WALL


func _cells_in_rect(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			result.append(Vector2i(x, y))
	return result


func _json_vector(value: Variant) -> Vector2i:
	if not value is Array or (value as Array).size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int((value as Array)[0]), int((value as Array)[1]))


func _json_rect(value: Variant) -> Rect2i:
	if not value is Array or (value as Array).size() != 4:
		return Rect2i()
	return Rect2i(
		int((value as Array)[0]),
		int((value as Array)[1]),
		int((value as Array)[2]),
		int((value as Array)[3])
	)
