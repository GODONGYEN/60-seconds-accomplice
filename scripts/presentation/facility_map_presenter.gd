class_name FacilityMapPresenter
extends Node2D

const SOURCE_ID: int = 0
const MAP_SIZE: Vector2i = Vector2i(30, 16)
const BASE_FLOOR: Vector2i = Vector2i(7, 3)
const WALL: Vector2i = Vector2i(0, 2)
const WALL_CORNER: Vector2i = Vector2i(1, 2)
const FLOOR_DETAILS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(4, 0),
]
const DOOR_COLUMN: int = 15
const DOOR_FIRST_OPEN_ROW: int = 5
const DOOR_LAST_OPEN_ROW: int = 9

@onready var floor_tiles: TileMapLayer = %FloorTiles
@onready var detail_tiles: TileMapLayer = %DetailTiles
@onready var wall_art_tiles: TileMapLayer = %WallArtTiles


func _ready() -> void:
	rebuild_map_art()


func rebuild_map_art() -> void:
	floor_tiles.clear()
	detail_tiles.clear()
	wall_art_tiles.clear()
	for y: int in range(MAP_SIZE.y):
		for x: int in range(MAP_SIZE.x):
			floor_tiles.set_cell(Vector2i(x, y), SOURCE_ID, BASE_FLOOR)
	_place_sparse_source_panels()
	_place_wall_art()
	_place_reference_props()
	floor_tiles.update_internals()
	detail_tiles.update_internals()
	wall_art_tiles.update_internals()


func get_map_size() -> Vector2i:
	return MAP_SIZE


func get_used_floor_cell_count() -> int:
	return floor_tiles.get_used_cells().size()


func _place_sparse_source_panels() -> void:
	var detail_index: int = 0
	for y: int in range(2, MAP_SIZE.y - 2, 3):
		for x: int in range(2, MAP_SIZE.x - 2, 4):
			if x == DOOR_COLUMN or x == DOOR_COLUMN - 1:
				continue
			detail_tiles.set_cell(
				Vector2i(x, y),
				SOURCE_ID,
				FLOOR_DETAILS[detail_index % FLOOR_DETAILS.size()]
			)
			detail_index += 1


func _place_wall_art() -> void:
	for x: int in range(MAP_SIZE.x):
		var top_coord := WALL_CORNER if x == 0 or x == MAP_SIZE.x - 1 else WALL
		wall_art_tiles.set_cell(Vector2i(x, 0), SOURCE_ID, top_coord)
		wall_art_tiles.set_cell(Vector2i(x, MAP_SIZE.y - 1), SOURCE_ID, top_coord)
	for y: int in range(1, MAP_SIZE.y - 1):
		wall_art_tiles.set_cell(Vector2i(0, y), SOURCE_ID, WALL_CORNER)
		wall_art_tiles.set_cell(Vector2i(MAP_SIZE.x - 1, y), SOURCE_ID, WALL_CORNER)
		if y < DOOR_FIRST_OPEN_ROW or y > DOOR_LAST_OPEN_ROW:
			wall_art_tiles.set_cell(Vector2i(DOOR_COLUMN, y), SOURCE_ID, WALL)


func _place_reference_props() -> void:
	# These are non-colliding art props; interactive objects remain separate scenes.
	detail_tiles.set_cell(Vector2i(23, 2), SOURCE_ID, Vector2i(4, 2))
	detail_tiles.set_cell(Vector2i(25, 2), SOURCE_ID, Vector2i(5, 2))
	detail_tiles.set_cell(Vector2i(27, 3), SOURCE_ID, Vector2i(7, 2))
