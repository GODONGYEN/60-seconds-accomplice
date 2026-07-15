class_name OperationBlackMinuteMap
extends Node2D

const BLUEPRINT_PATH: String = "res://resources/maps/operation_black_minute_blueprint.json"
const FACILITY_TILESET: TileSet = preload("res://resources/tilesets/facility_tileset.tres")
const ENVIRONMENT_ART_TILESET: TileSet = preload(
	"res://resources/tilesets/facility_environment_art.tres"
)
const ENVIRONMENT_CATALOG: GDScript = preload(
	"res://resources/environment/facility_environment_catalog.gd"
)
const SOURCE_ID: int = 0
const TILE_SIZE: int = 32
const MAP_SIZE := Vector2i(64, 42)
const WORLD_SIZE := Vector2i(2048, 1344)

const COLLISION_WALL := Vector2i(0, 2)
const COLLISION_WALL_CORNER := Vector2i(1, 2)
const VAULT_RING_ORIGIN := Vector2i(57, 7)

@onready var floor: TileMapLayer = %Floor
@onready var floor_details: TileMapLayer = %FloorDetails
@onready var walls: TileMapLayer = %Walls
@onready var wall_art: TileMapLayer = %WallArt
@onready var props_below: TileMapLayer = %PropsBelow
@onready var props_above: TileMapLayer = %PropsAbove
@onready var environment_presenter: OperationEnvironmentPresenter = %EnvironmentPresenter
@onready var room_labels: Node2D = %RoomLabels
@onready var observation_windows: Node2D = %ObservationWindows

var _blueprint: Dictionary = {}
var _walkable_cells: Dictionary[Vector2i, bool] = {}
var _room_by_cell: Dictionary[Vector2i, StringName] = {}
var _solid_cells: Dictionary[Vector2i, bool] = {}
var _semantic_solid_cell_count: int = 0
var _room_signature_cell_count: int = 0


func _ready() -> void:
	if not load_blueprint():
		return
	rebuild_map()
	if not environment_presenter.configure(_blueprint, ENVIRONMENT_ART_TILESET):
		push_error("OperationBlackMinuteMap could not configure environment presentation")


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
	for layer: TileMapLayer in [floor, floor_details, walls, wall_art, props_below, props_above]:
		layer.clear()
	for y: int in range(MAP_SIZE.y):
		for x: int in range(MAP_SIZE.x):
			var cell := Vector2i(x, y)
			if is_walkable_cell(cell):
				floor.set_cell(cell, SOURCE_ID, _select_floor_tile(cell))
				_place_room_floor_detail(cell)
			else:
				walls.set_cell(cell, SOURCE_ID, _select_collision_wall_tile(cell))
				var wall_tile := _select_wall_art_tile(cell)
				if wall_tile != Vector2i(-1, -1):
					wall_art.set_cell(cell, SOURCE_ID, wall_tile)
	_place_semantic_solids()
	_place_room_signatures()
	_place_signature_floor_details()
	_build_room_labels()
	_build_observation_windows()
	for layer: TileMapLayer in [floor, floor_details, walls, wall_art, props_below, props_above]:
		layer.update_internals()


func get_blueprint() -> Dictionary:
	return _blueprint.duplicate(true)


func get_map_size() -> Vector2i:
	return MAP_SIZE


func get_world_size() -> Vector2i:
	return WORLD_SIZE


func get_environment_art_tileset() -> TileSet:
	return ENVIRONMENT_ART_TILESET


func get_room_material_family(room_id: StringName) -> StringName:
	return ENVIRONMENT_CATALOG.ROOM_FAMILIES.get(room_id, &"neutral")


func get_semantic_solid_cell_count() -> int:
	return _semantic_solid_cell_count


func get_floor_detail_cell_count() -> int:
	return floor_details.get_used_cells().size()


func get_room_signature_count() -> int:
	return _room_signature_cell_count


func get_visible_wall_art_cell_count() -> int:
	return wall_art.get_used_cells().size()


func reset_environment_presentation() -> void:
	environment_presenter.reset_environment_presentation()


func set_security_visual_state(
	cctv_online: bool,
	laser_online: bool,
	alert_level: int
) -> void:
	environment_presenter.set_security_visual_state(cctv_online, laser_online, alert_level)


func set_core_visual_state(is_carried: bool) -> void:
	environment_presenter.set_core_visual_state(is_carried)


func set_extraction_visual_state(is_active: bool) -> void:
	environment_presenter.set_extraction_visual_state(is_active)


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
	walls.tile_set = FACILITY_TILESET
	for layer: TileMapLayer in [floor, floor_details, wall_art, props_below, props_above]:
		layer.tile_set = ENVIRONMENT_ART_TILESET
	floor.collision_enabled = false
	floor.occlusion_enabled = false
	floor_details.collision_enabled = false
	floor_details.occlusion_enabled = false
	walls.collision_enabled = true
	walls.occlusion_enabled = true
	wall_art.collision_enabled = false
	wall_art.occlusion_enabled = false
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
	if room_id == StringName():
		return
	var family := get_room_material_family(room_id)
	if not ENVIRONMENT_CATALOG.DETAIL_TILES.has(family):
		return
	var seed: int = ENVIRONMENT_CATALOG.ROOM_SEEDS.get(room_id, 0)
	var value := _stable_cell_hash(cell, seed)
	if value % 17 != 0:
		return
	var variants: Array = ENVIRONMENT_CATALOG.DETAIL_TILES[family]
	var variant_index := int(value / 17) % variants.size()
	floor_details.set_cell(cell, SOURCE_ID, variants[variant_index])


func _select_floor_tile(cell: Vector2i) -> Vector2i:
	var room_id := get_room_at_cell(cell)
	var family := get_room_material_family(room_id)
	var variants: Array = ENVIRONMENT_CATALOG.FLOOR_TILES[family]
	var seed: int = ENVIRONMENT_CATALOG.ROOM_SEEDS.get(room_id, 163)
	var value := _stable_cell_hash(cell, seed)
	var variant_index := 1 if value % 11 == 0 else 0
	return variants[variant_index]


func _place_room_signatures() -> void:
	_room_signature_cell_count = 0
	for room_id: StringName in ENVIRONMENT_CATALOG.ROOM_ART:
		var room_rect := get_room_rect(room_id)
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART[room_id]
		var atlas_coordinates: Vector2i = ENVIRONMENT_CATALOG.ROOM_SIGNATURE_TILES.get(
			room_id,
			Vector2i(-1, -1)
		)
		if room_rect.size == Vector2i.ZERO or atlas_coordinates == Vector2i(-1, -1):
			push_warning("Operation environment skipped invalid signature profile '%s'" % room_id)
			continue
		var local_cells: Array = profile.get(&"signature_cells", [])
		for local_variant: Variant in local_cells:
			if not local_variant is Vector2i:
				push_warning("Operation environment room '%s' has a malformed signature cell" % room_id)
				continue
			var cell := room_rect.position + (local_variant as Vector2i)
			if not is_walkable_cell(cell):
				push_warning(
					"Operation environment room '%s' skipped blocked signature cell %s"
					% [room_id, cell]
				)
				continue
			floor_details.set_cell(cell, SOURCE_ID, atlas_coordinates)
			_room_signature_cell_count += 1


func _place_signature_floor_details() -> void:
	for local_y: int in range(3):
		for local_x: int in range(3):
			var cell := VAULT_RING_ORIGIN + Vector2i(local_x, local_y)
			if not is_walkable_cell(cell):
				push_warning("Chronos Vault signature art skipped non-walkable cell %s" % cell)
				continue
			floor_details.set_cell(
				cell,
				SOURCE_ID,
				ENVIRONMENT_CATALOG.VAULT_RING_TILES[Vector2i(local_x, local_y)]
			)


func _place_semantic_solids() -> void:
	_semantic_solid_cell_count = 0
	var solids_variant: Variant = _blueprint.get("internal_solid_rects", [])
	if not solids_variant is Array:
		return
	for solid_variant: Variant in solids_variant as Array:
		if not solid_variant is Dictionary:
			continue
		var solid := solid_variant as Dictionary
		var solid_id := StringName(str(solid.get("id", "")))
		var motif: StringName = ENVIRONMENT_CATALOG.SEMANTIC_SOLIDS.get(
			solid_id, StringName()
		)
		var rect := _json_rect(solid.get("rect", []))
		if motif == StringName():
			push_warning("Operation environment has no semantic art for solid '%s'" % solid_id)
			continue
		for cell: Vector2i in _cells_in_rect(rect):
			var local := cell - rect.position
			var atlas_coordinates := _semantic_tile_for(motif, local, rect.size)
			if atlas_coordinates == Vector2i(-1, -1):
				push_warning("Operation environment cannot map solid '%s' at local cell %s" % [solid_id, local])
				continue
			props_above.set_cell(cell, SOURCE_ID, atlas_coordinates)
			_semantic_solid_cell_count += 1


func _semantic_tile_for(motif: StringName, local: Vector2i, size: Vector2i) -> Vector2i:
	var tiles: Array = ENVIRONMENT_CATALOG.MOTIF_TILES.get(motif, [])
	if tiles.is_empty():
		return Vector2i(-1, -1)
	match motif:
		&"reception_desk":
			return tiles[clampi(local.x, 0, 2)]
		&"locker_bank":
			if local.x == 0:
				return tiles[0]
			if local.x == size.x - 1:
				return tiles[2]
			return tiles[1]
		&"office_desk":
			return tiles[clampi(local.x, 0, 1)]
		&"break_table":
			return tiles[clampi(local.x, 0, 1)]
		&"cctv_monitor_bank":
			return tiles[clampi(local.x, 0, 1) + clampi(local.y, 0, 1) * 2]
		&"security_desk":
			return tiles[clampi(local.x, 0, 3)]
		&"electrical_cabinet":
			return tiles[_vertical_segment(local.y, size.y)]
		&"server_rack":
			return tiles[_vertical_segment(local.y, size.y)]
		&"research_bench":
			return tiles[clampi(local.x, 0, 2)]
		&"maintenance_machine":
			var segment := _vertical_segment(local.y, size.y)
			return tiles[segment * 2 + clampi(local.x, 0, 1)]
	return Vector2i(-1, -1)


func _vertical_segment(local_y: int, height: int) -> int:
	if local_y == 0:
		return 0
	if local_y == height - 1:
		return 2
	return 1


func _build_room_labels() -> void:
	for child: Node in room_labels.get_children():
		child.queue_free()
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		return
	var plaque_material := CanvasItemMaterial.new()
	plaque_material.light_mode = CanvasItemMaterial.LIGHT_MODE_LIGHT_ONLY
	for room_key: Variant in (rooms_variant as Dictionary).keys():
		var room_data := (rooms_variant as Dictionary)[room_key] as Dictionary
		var rect := _json_rect(room_data.get("rect", []))
		var plaque := PanelContainer.new()
		plaque.name = "RoomPlaque_%s" % String(room_key)
		plaque.material = plaque_material
		plaque.position = Vector2(rect.position * TILE_SIZE) + Vector2(
			7.0,
			float(rect.size.y * TILE_SIZE - 24)
		)
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plaque_style := StyleBoxFlat.new()
		plaque_style.bg_color = Color(0.015, 0.045, 0.07, 0.82)
		plaque_style.border_color = Color(0.16, 0.58, 0.67, 0.72)
		plaque_style.set_border_width_all(1)
		plaque_style.corner_radius_top_left = 2
		plaque_style.corner_radius_top_right = 2
		plaque_style.corner_radius_bottom_left = 2
		plaque_style.corner_radius_bottom_right = 2
		plaque_style.content_margin_left = 5.0
		plaque_style.content_margin_right = 5.0
		plaque_style.content_margin_top = 2.0
		plaque_style.content_margin_bottom = 2.0
		plaque.add_theme_stylebox_override("panel", plaque_style)
		var label := Label.new()
		label.text = String(room_data.get("display_name", str(room_key))).to_upper()
		label.use_parent_material = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color(0.64, 0.92, 0.96, 0.92))
		label.add_theme_color_override("font_outline_color", Color(0.005, 0.02, 0.035, 1.0))
		label.add_theme_constant_override("outline_size", 2)
		plaque.add_child(label)
		room_labels.add_child(plaque)


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
		var half_size := shape.size * 0.5
		var glass := Polygon2D.new()
		glass.polygon = PackedVector2Array([
			-half_size,
			Vector2(half_size.x, -half_size.y),
			half_size,
			Vector2(-half_size.x, half_size.y),
		])
		glass.color = Color(0.05, 0.22, 0.29, 0.78)
		body.add_child(glass)
		var frame := Line2D.new()
		frame.width = 5.0
		frame.default_color = Color(0.22, 0.55, 0.66, 0.92)
		frame.antialiased = false
		frame.points = PackedVector2Array([
			-half_size,
			Vector2(half_size.x, -half_size.y),
			half_size,
			Vector2(-half_size.x, half_size.y),
			-half_size,
		])
		body.add_child(frame)
		var reflection := Line2D.new()
		reflection.width = 2.0
		reflection.default_color = Color(0.42, 0.88, 0.94, 0.42)
		reflection.antialiased = false
		reflection.points = PackedVector2Array([
			Vector2(-half_size.x + 7.0, -half_size.y + 8.0),
			Vector2(half_size.x - 7.0, half_size.y - 8.0),
		])
		body.add_child(reflection)
		var mullion := Line2D.new()
		mullion.width = 3.0
		mullion.default_color = Color(0.09, 0.19, 0.26, 0.96)
		mullion.antialiased = false
		mullion.points = (
			PackedVector2Array([Vector2(0.0, -half_size.y), Vector2(0.0, half_size.y)])
			if shape.size.x >= shape.size.y
			else PackedVector2Array([Vector2(-half_size.x, 0.0), Vector2(half_size.x, 0.0)])
		)
		body.add_child(mullion)
		observation_windows.add_child(body)


func _select_collision_wall_tile(cell: Vector2i) -> Vector2i:
	var adjacent_floor_count := 0
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if is_walkable_cell(cell + offset):
			adjacent_floor_count += 1
	return COLLISION_WALL_CORNER if adjacent_floor_count >= 2 else COLLISION_WALL


func _select_wall_art_tile(cell: Vector2i) -> Vector2i:
	var mask := 0
	if is_walkable_cell(cell + Vector2i.UP):
		mask |= 1
	if is_walkable_cell(cell + Vector2i.RIGHT):
		mask |= 2
	if is_walkable_cell(cell + Vector2i.DOWN):
		mask |= 4
	if is_walkable_cell(cell + Vector2i.LEFT):
		mask |= 8
	if mask != 0:
		var variant := 1 if _stable_cell_hash(cell, 211) % 13 == 0 else 0
		return Vector2i(mask, 2 + variant)
	if _is_within_wall_depth_ring(cell):
		var deep_variant := _stable_cell_hash(cell, 307) % ENVIRONMENT_CATALOG.DEEP_WALL_TILES.size()
		return ENVIRONMENT_CATALOG.DEEP_WALL_TILES[deep_variant]
	return Vector2i(-1, -1)


func _is_within_wall_depth_ring(cell: Vector2i) -> bool:
	for offset_x: int in range(-2, 3):
		for offset_y: int in range(-2, 3):
			var manhattan_distance := absi(offset_x) + absi(offset_y)
			if manhattan_distance == 0 or manhattan_distance > 2:
				continue
			if is_walkable_cell(cell + Vector2i(offset_x, offset_y)):
				return true
	return false


static func _stable_cell_hash(cell: Vector2i, seed: int) -> int:
	var value: int = (cell.x * 73856093) ^ (cell.y * 19349663) ^ (seed * 83492791)
	return absi(value)


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
