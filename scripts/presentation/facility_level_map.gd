class_name FacilityLevelMap
extends Node2D

const FACILITY_TILESET: TileSet = preload("res://resources/tilesets/facility_tileset.tres")

const SOURCE_ID: int = 0
const TILE_SIZE: int = 32
const MAP_SIZE: Vector2i = Vector2i(26, 25)
const WORLD_SIZE: Vector2i = MAP_SIZE * TILE_SIZE

const BASE_FLOOR: Vector2i = Vector2i(7, 3)
const WALL: Vector2i = Vector2i(0, 2)
const WALL_CORNER: Vector2i = Vector2i(1, 2)
const FLOOR_VARIANTS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(4, 0),
]
const WARNING_LIGHT: Vector2i = Vector2i(4, 3)
const PLANT: Vector2i = Vector2i(7, 2)
const METAL_CRATE: Vector2i = Vector2i(3, 2)
const TERMINAL: Vector2i = Vector2i(4, 2)
const SERVER: Vector2i = Vector2i(5, 2)
const WOOD_CRATE: Vector2i = Vector2i(6, 2)

const ROOM_RECTS: Dictionary = {
	&"upper_left_control": Rect2i(1, 1, 6, 5),
	&"upper_central_corridor": Rect2i(8, 1, 8, 6),
	&"upper_right_control": Rect2i(17, 1, 8, 5),
	&"west_service_corridor": Rect2i(1, 7, 2, 10),
	&"middle_left_enclosed": Rect2i(4, 8, 8, 7),
	&"center_security_corridor": Rect2i(13, 7, 6, 11),
	&"right_laser_room": Rect2i(20, 8, 5, 8),
	&"lower_left_utility": Rect2i(1, 18, 6, 6),
	&"lower_operations": Rect2i(8, 19, 10, 5),
	&"lower_right_courtyard": Rect2i(19, 17, 6, 7),
}

const CONNECTOR_RECTS: Array[Rect2i] = [
	Rect2i(3, 6, 5, 2),
	Rect2i(3, 11, 1, 2),
	Rect2i(12, 10, 1, 3),
	Rect2i(5, 15, 2, 3),
	Rect2i(14, 18, 3, 1),
	Rect2i(7, 20, 1, 3),
	Rect2i(18, 19, 1, 2),
	Rect2i(21, 16, 3, 1),
	Rect2i(16, 3, 1, 2),
]

const DYNAMIC_PORTAL_RECTS: Dictionary = {
	&"door_vault_01": Rect2i(7, 1, 1, 5),
	&"laser_right_01": Rect2i(19, 10, 1, 3),
}

const FLOOR_DETAIL_CELLS: Array[Vector2i] = [
	Vector2i(2, 4), Vector2i(5, 4),
	Vector2i(9, 2), Vector2i(12, 5), Vector2i(15, 2),
	Vector2i(18, 4), Vector2i(22, 4),
	Vector2i(5, 9), Vector2i(8, 13), Vector2i(11, 9),
	Vector2i(14, 9), Vector2i(17, 12), Vector2i(15, 16),
	Vector2i(21, 9), Vector2i(23, 14),
	Vector2i(2, 19), Vector2i(5, 22),
	Vector2i(9, 22), Vector2i(14, 20), Vector2i(16, 22),
	Vector2i(20, 19), Vector2i(23, 18),
]

const WALL_DETAIL_CELLS: Array[Vector2i] = [
	Vector2i(2, 6),
	Vector2i(3, 15),
	Vector2i(12, 15),
	Vector2i(19, 16),
	Vector2i(7, 19),
	Vector2i(18, 18),
]

const PROPS_BELOW_CELLS: Array[Vector2i] = [
	Vector2i(6, 4),
	Vector2i(23, 4),
	Vector2i(10, 13),
	Vector2i(24, 14),
	Vector2i(20, 22),
	Vector2i(24, 18),
]

const PROPS_ABOVE_CELLS: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(5, 2),
	Vector2i(19, 2), Vector2i(21, 2), Vector2i(23, 2),
	Vector2i(6, 10), Vector2i(6, 12), Vector2i(10, 10),
	Vector2i(18, 8), Vector2i(18, 14),
	Vector2i(23, 9),
	Vector2i(10, 20), Vector2i(11, 20), Vector2i(12, 20),
]

const PROPS_ABOVE_TILES: Array[Vector2i] = [
	TERMINAL, SERVER,
	TERMINAL, SERVER, TERMINAL,
	WOOD_CRATE, METAL_CRATE, TERMINAL,
	METAL_CRATE, WOOD_CRATE,
	SERVER,
	METAL_CRATE, WOOD_CRATE, TERMINAL,
]

@onready var floor: TileMapLayer = %Floor
@onready var floor_details: TileMapLayer = %FloorDetails
@onready var walls: TileMapLayer = %Walls
@onready var wall_details: TileMapLayer = %WallDetails
@onready var props_below_actors: TileMapLayer = %PropsBelowActors
@onready var props_above_actors: TileMapLayer = %PropsAboveActors


func _ready() -> void:
	rebuild_map()


func rebuild_map() -> void:
	_configure_layers()
	_clear_layers()
	_place_floor_and_walls()
	_place_floor_details()
	_place_wall_details()
	_place_props()
	_update_layers()


func get_map_size() -> Vector2i:
	return MAP_SIZE


func get_world_size() -> Vector2i:
	return WORLD_SIZE


func get_room_rect(room_id: StringName) -> Rect2i:
	var room_rect: Variant = ROOM_RECTS.get(room_id, Rect2i())
	return room_rect as Rect2i


func get_dynamic_portal_rect(object_id: StringName) -> Rect2i:
	var portal_rect: Variant = DYNAMIC_PORTAL_RECTS.get(object_id, Rect2i())
	return portal_rect as Rect2i


func is_walkable_cell(cell: Vector2i) -> bool:
	if not is_cell_inside_map(cell):
		return false
	if _is_cell_in_room(cell) or _is_cell_in_rects(cell, CONNECTOR_RECTS):
		return true
	return _is_cell_in_dynamic_portal(cell)


func is_wall_cell(cell: Vector2i) -> bool:
	return is_cell_inside_map(cell) and not is_walkable_cell(cell)


func get_floor_cell_count() -> int:
	return floor.get_used_cells().size()


func get_wall_cell_count() -> int:
	return walls.get_used_cells().size()


static func is_cell_inside_map(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < MAP_SIZE.x and cell.y < MAP_SIZE.y


static func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2.ONE * (TILE_SIZE * 0.5)


func _configure_layers() -> void:
	var all_layers: Array[TileMapLayer] = [
		floor,
		floor_details,
		walls,
		wall_details,
		props_below_actors,
		props_above_actors,
	]
	for layer: TileMapLayer in all_layers:
		layer.tile_set = FACILITY_TILESET
	floor.collision_enabled = false
	floor.occlusion_enabled = false
	floor_details.collision_enabled = false
	floor_details.occlusion_enabled = false
	walls.collision_enabled = true
	walls.occlusion_enabled = true
	wall_details.collision_enabled = false
	wall_details.occlusion_enabled = false
	props_below_actors.collision_enabled = false
	props_below_actors.occlusion_enabled = false
	props_above_actors.collision_enabled = false
	props_above_actors.occlusion_enabled = false


func _clear_layers() -> void:
	floor.clear()
	floor_details.clear()
	walls.clear()
	wall_details.clear()
	props_below_actors.clear()
	props_above_actors.clear()


func _place_floor_and_walls() -> void:
	for y: int in range(MAP_SIZE.y):
		for x: int in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			if is_walkable_cell(cell):
				floor.set_cell(cell, SOURCE_ID, BASE_FLOOR)
			else:
				walls.set_cell(cell, SOURCE_ID, _select_wall_tile(cell))


func _place_floor_details() -> void:
	for index: int in range(FLOOR_DETAIL_CELLS.size()):
		var cell: Vector2i = FLOOR_DETAIL_CELLS[index]
		if not is_walkable_cell(cell):
			push_warning("FacilityLevelMap skipped floor detail on wall cell %s" % cell)
			continue
		floor_details.set_cell(
			cell,
			SOURCE_ID,
			FLOOR_VARIANTS[index % FLOOR_VARIANTS.size()]
		)


func _place_wall_details() -> void:
	for cell: Vector2i in WALL_DETAIL_CELLS:
		if not is_wall_cell(cell):
			push_warning("FacilityLevelMap skipped wall detail on floor cell %s" % cell)
			continue
		wall_details.set_cell(cell, SOURCE_ID, WARNING_LIGHT)


func _place_props() -> void:
	for cell: Vector2i in PROPS_BELOW_CELLS:
		if is_walkable_cell(cell):
			props_below_actors.set_cell(cell, SOURCE_ID, PLANT)
	for index: int in range(PROPS_ABOVE_CELLS.size()):
		var cell: Vector2i = PROPS_ABOVE_CELLS[index]
		if not is_walkable_cell(cell):
			push_warning("FacilityLevelMap skipped prop on wall cell %s" % cell)
			continue
		props_above_actors.set_cell(cell, SOURCE_ID, PROPS_ABOVE_TILES[index])


func _update_layers() -> void:
	floor.update_internals()
	floor_details.update_internals()
	walls.update_internals()
	wall_details.update_internals()
	props_below_actors.update_internals()
	props_above_actors.update_internals()


func _is_cell_in_room(cell: Vector2i) -> bool:
	for room_rect: Rect2i in ROOM_RECTS.values():
		if room_rect.has_point(cell):
			return true
	return false


func _is_cell_in_dynamic_portal(cell: Vector2i) -> bool:
	for portal_rect: Rect2i in DYNAMIC_PORTAL_RECTS.values():
		if portal_rect.has_point(cell):
			return true
	return false


func _is_cell_in_rects(cell: Vector2i, rects: Array[Rect2i]) -> bool:
	for rect: Rect2i in rects:
		if rect.has_point(cell):
			return true
	return false


func _select_wall_tile(cell: Vector2i) -> Vector2i:
	var boundary_corner := (
		(cell.x == 0 or cell.x == MAP_SIZE.x - 1)
		and (cell.y == 0 or cell.y == MAP_SIZE.y - 1)
	)
	if boundary_corner:
		return WALL_CORNER
	var adjacent_floor_count: int = 0
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if is_walkable_cell(cell + offset):
			adjacent_floor_count += 1
	return WALL_CORNER if adjacent_floor_count >= 2 else WALL
