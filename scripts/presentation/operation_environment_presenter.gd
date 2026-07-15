class_name OperationEnvironmentPresenter
extends Node2D

const ENVIRONMENT_CATALOG: GDScript = preload(
	"res://resources/environment/facility_environment_catalog.gd"
)
const TILE_SIZE: int = 32
const SOURCE_ID: int = 0
const PRESENTATION_TICK_SECONDS: float = 1.0 / 6.0
const ALERTED_LEVEL: int = 2

@onready var hero_details: TileMapLayer = %HeroDetails
@onready var animated_details: TileMapLayer = %AnimatedDetails

var _blueprint: Dictionary = {}
var _room_rects: Dictionary[StringName, Rect2i] = {}
var _tick_accumulator: float = 0.0
var _presentation_tick: int = 0
var _cctv_online: bool = true
var _laser_online: bool = true
var _alert_level: int = 0
var _core_carried: bool = false
var _extraction_active: bool = false
var _configured: bool = false


func _ready() -> void:
	set_process(false)


func configure(blueprint: Dictionary, environment_tileset: TileSet) -> bool:
	if blueprint.is_empty() or environment_tileset == null:
		push_error("OperationEnvironmentPresenter requires a blueprint and visual TileSet")
		return false
	_blueprint = blueprint.duplicate(true)
	hero_details.tile_set = environment_tileset
	hero_details.collision_enabled = false
	hero_details.occlusion_enabled = false
	animated_details.tile_set = environment_tileset
	animated_details.collision_enabled = false
	animated_details.occlusion_enabled = false
	if not _cache_room_rects():
		return false
	_configured = true
	_place_room_heroes()
	reset_environment_presentation()
	set_process(true)
	queue_redraw()
	return true


func _process(delta: float) -> void:
	if not _configured or delta <= 0.0:
		return
	_tick_accumulator += delta
	var advanced := false
	while _tick_accumulator >= PRESENTATION_TICK_SECONDS:
		_tick_accumulator -= PRESENTATION_TICK_SECONDS
		_presentation_tick += 1
		advanced = true
	if advanced:
		_refresh_animation_tiles()


func reset_environment_presentation() -> void:
	_tick_accumulator = 0.0
	_presentation_tick = 0
	_cctv_online = true
	_laser_online = true
	_alert_level = 0
	_core_carried = false
	_extraction_active = false
	if _configured:
		_refresh_animation_tiles()
		queue_redraw()


func set_security_visual_state(
	cctv_online: bool,
	laser_online: bool,
	alert_level: int
) -> void:
	_cctv_online = cctv_online
	_laser_online = laser_online
	_alert_level = maxi(0, alert_level)
	if _configured:
		_refresh_animation_tiles()


func set_core_visual_state(is_carried: bool) -> void:
	_core_carried = is_carried
	_extraction_active = is_carried
	if _configured:
		_refresh_animation_tiles()


func set_extraction_visual_state(is_active: bool) -> void:
	_extraction_active = is_active
	if _configured:
		_refresh_animation_tiles()


func set_presentation_time_for_capture(seconds: float) -> void:
	_tick_accumulator = 0.0
	_presentation_tick = maxi(0, floori(maxf(0.0, seconds) / PRESENTATION_TICK_SECONDS))
	if _configured:
		_refresh_animation_tiles()


func get_room_profile_count() -> int:
	return _room_rects.size()


func get_active_animation_count() -> int:
	return animated_details.get_used_cells().size() if _configured else 0


func get_room_hero_cell_count() -> int:
	return hero_details.get_used_cells().size() if _configured else 0


func get_presentation_tick() -> int:
	return _presentation_tick


func get_room_animation_tile(room_id: StringName) -> Vector2i:
	if not _room_rects.has(room_id):
		return Vector2i(-1, -1)
	var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART.get(room_id, {})
	var local_cell: Vector2i = profile.get(&"animation_cell", Vector2i(-1, -1))
	if local_cell == Vector2i(-1, -1):
		return Vector2i(-1, -1)
	return animated_details.get_cell_atlas_coords(_room_rects[room_id].position + local_cell)


func _cache_room_rects() -> bool:
	_room_rects.clear()
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		push_error("OperationEnvironmentPresenter blueprint is missing rooms")
		return false
	for room_id: StringName in ENVIRONMENT_CATALOG.ROOM_ART:
		var room_variant: Variant = (rooms_variant as Dictionary).get(String(room_id), {})
		if not room_variant is Dictionary:
			push_error("OperationEnvironmentPresenter is missing room '%s'" % room_id)
			return false
		var rect_variant: Variant = (room_variant as Dictionary).get("rect", [])
		if not rect_variant is Array or (rect_variant as Array).size() != 4:
			push_error("OperationEnvironmentPresenter room '%s' has an invalid rect" % room_id)
			return false
		var values := rect_variant as Array
		var rect := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
		if rect.size.x <= 0 or rect.size.y <= 0:
			push_error("OperationEnvironmentPresenter room '%s' has an empty rect" % room_id)
			return false
		_room_rects[room_id] = rect
	return _room_rects.size() == ENVIRONMENT_CATALOG.ROOM_ART.size()


func _refresh_animation_tiles() -> void:
	animated_details.clear()
	for room_id: StringName in _room_rects:
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART.get(room_id, {})
		var local_cell: Vector2i = profile.get(&"animation_cell", Vector2i(-1, -1))
		if local_cell == Vector2i(-1, -1):
			continue
		var tile := _animation_tile_for(room_id)
		if tile == Vector2i(-1, -1):
			continue
		animated_details.set_cell(
			_room_rects[room_id].position + local_cell,
			SOURCE_ID,
			tile
		)
	animated_details.update_internals()


func _place_room_heroes() -> void:
	hero_details.clear()
	for room_id: StringName in _room_rects:
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART.get(room_id, {})
		var local_origin: Vector2i = profile.get(&"hero_origin", Vector2i(-1, -1))
		var tiles: Array = ENVIRONMENT_CATALOG.ROOM_HERO_TILES.get(room_id, [])
		if local_origin == Vector2i(-1, -1) or tiles.size() != 2:
			push_warning("Operation environment skipped malformed hero profile '%s'" % room_id)
			continue
		for segment: int in range(2):
			hero_details.set_cell(
				_room_rects[room_id].position + local_origin + Vector2i(segment, 0),
				SOURCE_ID,
				tiles[segment]
			)
	hero_details.update_internals()


func _animation_tile_for(room_id: StringName) -> Vector2i:
	if room_id == &"cctv_control_room" and not _cctv_online:
		return ENVIRONMENT_CATALOG.STATE_TILES[&"cctv_offline"]
	if room_id in [&"electrical_room", &"laser_corridor"] and not _laser_online:
		return ENVIRONMENT_CATALOG.STATE_TILES[&"laser_offline"]
	if room_id in [&"security_office", &"vault_antechamber"] and _alert_level >= ALERTED_LEVEL:
		return ENVIRONMENT_CATALOG.STATE_TILES[&"security_alert"]
	if room_id == &"chronos_vault" and _core_carried:
		return ENVIRONMENT_CATALOG.STATE_TILES[&"vault_stolen"]
	if room_id == &"extraction_route" and _extraction_active:
		return ENVIRONMENT_CATALOG.STATE_TILES[&"extraction_active"]
	var frames: Array = ENVIRONMENT_CATALOG.ROOM_ANIMATION_TILES.get(room_id, [])
	if frames.is_empty():
		return Vector2i(-1, -1)
	var stable_phase: int = int(ENVIRONMENT_CATALOG.ROOM_SEEDS.get(room_id, 0)) % frames.size()
	return frames[(_presentation_tick + stable_phase) % frames.size()]


func _draw() -> void:
	if not _configured:
		return
	for room_id: StringName in _room_rects:
		var profile: Dictionary = ENVIRONMENT_CATALOG.ROOM_ART.get(room_id, {})
		var main_color: Color = profile.get(&"light_main", Color.WHITE)
		var secondary_color: Color = profile.get(&"light_secondary", Color.WHITE)
		var room_rect := _room_rects[room_id]
		var room_world_rect := Rect2(
			Vector2(room_rect.position * TILE_SIZE),
			Vector2(room_rect.size * TILE_SIZE)
		)
		var inner_rect := room_world_rect.grow(-8.0)
		draw_rect(inner_rect, Color(main_color, 0.014), true)
		var anchors: Array = profile.get(&"light_anchors", [])
		for anchor_index: int in range(anchors.size()):
			var local_cell: Vector2i = anchors[anchor_index]
			var center := Vector2((room_rect.position + local_cell) * TILE_SIZE)
			center += Vector2.ONE * (TILE_SIZE * 0.5)
			_draw_room_light_pool(
				center,
				inner_rect,
				main_color,
				secondary_color,
				anchor_index
			)


func _draw_room_light_pool(
	center: Vector2,
	clip_rect: Rect2,
	main_color: Color,
	secondary_color: Color,
	anchor_index: int
) -> void:
	var outer_radius_x := minf(96.0, clip_rect.size.x * 0.28)
	var outer_radius_y := minf(64.0, clip_rect.size.y * 0.24)
	var outer := PackedVector2Array([
		_clamp_to_rect(Vector2(center.x - outer_radius_x * 0.45, center.y - outer_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x + outer_radius_x * 0.45, center.y - outer_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x + outer_radius_x, center.y - outer_radius_y * 0.42), clip_rect),
		_clamp_to_rect(Vector2(center.x + outer_radius_x, center.y + outer_radius_y * 0.42), clip_rect),
		_clamp_to_rect(Vector2(center.x + outer_radius_x * 0.45, center.y + outer_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x - outer_radius_x * 0.45, center.y + outer_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x - outer_radius_x, center.y + outer_radius_y * 0.42), clip_rect),
		_clamp_to_rect(Vector2(center.x - outer_radius_x, center.y - outer_radius_y * 0.42), clip_rect),
	])
	draw_colored_polygon(outer, Color(main_color, 0.042))
	var inner_radius_x := outer_radius_x * 0.55
	var inner_radius_y := outer_radius_y * 0.52
	var inner := PackedVector2Array([
		_clamp_to_rect(Vector2(center.x, center.y - inner_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x + inner_radius_x, center.y), clip_rect),
		_clamp_to_rect(Vector2(center.x, center.y + inner_radius_y), clip_rect),
		_clamp_to_rect(Vector2(center.x - inner_radius_x, center.y), clip_rect),
	])
	draw_colored_polygon(inner, Color(main_color, 0.062))
	var fixture_y := maxf(clip_rect.position.y + 5.0, center.y - outer_radius_y + 4.0)
	draw_rect(Rect2(center.x - 14.0, fixture_y, 28.0, 3.0), Color(main_color, 0.62), true)
	draw_line(
		Vector2(center.x - 9.0, fixture_y + 4.0),
		Vector2(center.x + 9.0, fixture_y + 4.0),
		Color(secondary_color, 0.42),
		1.0,
		false
	)
	var glint_x := center.x - 21.0 if anchor_index % 2 == 0 else center.x + 21.0
	draw_rect(Rect2(glint_x, center.y + inner_radius_y - 2.0, 2.0, 2.0), Color(secondary_color, 0.32), true)


static func _clamp_to_rect(point: Vector2, bounds: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y)
	)
