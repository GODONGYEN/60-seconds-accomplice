class_name FacilityMapView
extends Control

const TILE_SIZE: float = 32.0
const MAP_SIZE := Vector2(64.0, 42.0)
const OBJECTIVE_TARGETS: Dictionary = {
	&"infiltrate_facility": {
		&"room_id": &"reception_checkpoint",
		&"label": "TARGET // ENTRY",
		&"color": Color("55e5ee"),
	},
	&"acquire_level_1_access": {
		&"room_id": &"locker_room",
		&"label": "TARGET // L1 CARD",
		&"color": Color("55e5ee"),
	},
	&"disable_cctv_network": {
		&"room_id": &"cctv_control_room",
		&"label": "OPTION // CCTV",
		&"color": Color("65cfe9"),
	},
	&"disable_laser_network": {
		&"room_id": &"electrical_room",
		&"label": "TARGET // LASERS",
		&"color": Color("ffae45"),
	},
	&"acquire_level_2_access": {
		&"room_id": &"security_office",
		&"label": "TARGET // L2 CARD",
		&"color": Color("ffae45"),
	},
	&"biometric_sample_acquired": {
		&"room_id": &"research_laboratory",
		&"label": "OPTION // BIOMETRIC",
		&"color": Color("c889ff"),
	},
	&"server_override_completed": {
		&"room_id": &"server_room",
		&"label": "OPTION // OVERRIDE",
		&"color": Color("c889ff"),
	},
	&"vault_authorized": {
		&"room_id": &"vault_antechamber",
		&"label": "TARGET // VAULT AUTH",
		&"color": Color("c889ff"),
	},
	&"enter_chronos_vault": {
		&"room_id": &"chronos_vault",
		&"label": "TARGET // VAULT",
		&"color": Color("c889ff"),
	},
	&"steal_chronos_core": {
		&"room_id": &"chronos_vault",
		&"label": "TARGET // CORE",
		&"color": Color("d59aff"),
	},
	&"return_to_extraction": {
		&"room_id": &"external_infiltration_yard",
		&"label": "TARGET // EXTRACT",
		&"color": Color("55e5a5"),
	},
}

var _blueprint: Dictionary = {}
var _player_world_position: Vector2 = Vector2(-1.0, -1.0)
var _cctv_online: bool = true
var _laser_online: bool = true
var _core_carried: bool = false
var _maintenance_discovered: bool = false
var _active_objective_ids: Array[StringName] = []


func set_blueprint(blueprint: Dictionary) -> void:
	_blueprint = blueprint.duplicate(true)
	queue_redraw()


func load_blueprint(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return false
	set_blueprint(parsed as Dictionary)
	return true


func set_player_world_position(world_position: Vector2) -> void:
	_player_world_position = world_position
	queue_redraw()


func set_security_status(cctv_online: bool, laser_online: bool) -> void:
	_cctv_online = cctv_online
	_laser_online = laser_online
	queue_redraw()


func set_mission_status(core_carried: bool, maintenance_discovered: bool = false) -> void:
	_core_carried = core_carried
	_maintenance_discovered = maintenance_discovered
	queue_redraw()


func set_active_objectives(objective_ids: Array[StringName]) -> void:
	_active_objective_ids.clear()
	for objective_id: StringName in objective_ids:
		if OBJECTIVE_TARGETS.has(objective_id) and objective_id not in _active_objective_ids:
			_active_objective_ids.append(objective_id)
	queue_redraw()


func get_target_room_ids() -> Array[StringName]:
	var target_room_ids: Array[StringName] = []
	for objective_id: StringName in _active_objective_ids:
		var target := OBJECTIVE_TARGETS.get(objective_id, {}) as Dictionary
		var room_id := StringName(target.get(&"room_id", StringName()))
		if room_id != StringName() and room_id not in target_room_ids:
			target_room_ids.append(room_id)
	return target_room_ids


func is_maintenance_discovered() -> bool:
	return _maintenance_discovered


func _draw() -> void:
	var drawing_rect := Rect2(Vector2.ZERO, size)
	draw_rect(drawing_rect, Color(0.008, 0.022, 0.038, 0.98), true)
	if _blueprint.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(16.0, 28.0), "MAP DATA UNAVAILABLE")
		return
	var scale_factor := minf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)
	var map_pixel_size := MAP_SIZE * scale_factor
	var origin := (size - map_pixel_size) * 0.5
	_draw_grid(origin, scale_factor, map_pixel_size)
	_draw_rooms(origin, scale_factor)
	_draw_target_rooms(origin, scale_factor)
	_draw_doors(origin, scale_factor)
	_draw_security(origin, scale_factor)
	_draw_mission_markers(origin, scale_factor)
	_draw_player(origin, scale_factor)


func _draw_grid(origin: Vector2, scale_factor: float, map_pixel_size: Vector2) -> void:
	draw_rect(Rect2(origin, map_pixel_size), Color(0.035, 0.075, 0.105, 0.92), true)
	for x: int in range(0, 65, 4):
		var px := origin.x + float(x) * scale_factor
		draw_line(Vector2(px, origin.y), Vector2(px, origin.y + map_pixel_size.y), Color(0.1, 0.25, 0.3, 0.2))
	for y: int in range(0, 43, 4):
		var py := origin.y + float(y) * scale_factor
		draw_line(Vector2(origin.x, py), Vector2(origin.x + map_pixel_size.x, py), Color(0.1, 0.25, 0.3, 0.2))


func _draw_rooms(origin: Vector2, scale_factor: float) -> void:
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		return
	var rooms := rooms_variant as Dictionary
	var room_keys := rooms.keys()
	room_keys.sort()
	for room_key: Variant in room_keys:
		var room_id := String(room_key)
		var room_data := rooms[room_key] as Dictionary
		if room_id == "maintenance_passage" and not _maintenance_discovered:
			continue
		var cell_rect := _json_rect(room_data.get("rect", []))
		var room_rect := Rect2(
			origin + Vector2(cell_rect.position) * scale_factor,
			Vector2(cell_rect.size) * scale_factor
		)
		var access := String(room_data.get("minimum_access", "PUBLIC"))
		var fill := _access_color(access)
		draw_rect(room_rect, Color(fill, 0.2), true)
		draw_rect(room_rect, Color(fill, 0.76), false, 1.5)
		if scale_factor >= 8.0:
			var label := String(
				room_data.get("map_label", room_data.get("display_name", room_id))
			).to_upper()
			draw_string(
				ThemeDB.fallback_font,
				room_rect.position + Vector2(5.0, 15.0),
				label,
				HORIZONTAL_ALIGNMENT_LEFT,
				room_rect.size.x - 8.0,
				10,
				Color(0.75, 0.9, 0.95, 0.9)
			)


func _draw_doors(origin: Vector2, scale_factor: float) -> void:
	var portals_variant: Variant = _blueprint.get("dynamic_portals", [])
	if not portals_variant is Array:
		return
	for portal_variant: Variant in portals_variant as Array:
		if not portal_variant is Dictionary:
			continue
		var portal := portal_variant as Dictionary
		if bool(portal.get("initially_hidden", false)) and not _maintenance_discovered:
			continue
		var anchor := _json_vector(portal.get("anchor", []))
		var point := origin + (Vector2(anchor) + Vector2.ONE * 0.5) * scale_factor
		var access := String(portal.get("required_access", "PUBLIC"))
		var color := _access_color(access)
		draw_rect(Rect2(point - Vector2.ONE * 3.0, Vector2.ONE * 6.0), color, true)


func _draw_target_rooms(origin: Vector2, scale_factor: float) -> void:
	var rooms_variant: Variant = _blueprint.get("rooms", {})
	if not rooms_variant is Dictionary:
		return
	var rooms := rooms_variant as Dictionary
	for objective_id: StringName in _active_objective_ids:
		var target := OBJECTIVE_TARGETS.get(objective_id, {}) as Dictionary
		var room_id := StringName(target.get(&"room_id", StringName()))
		if room_id == StringName() or not rooms.has(String(room_id)):
			continue
		if room_id == &"maintenance_passage" and not _maintenance_discovered:
			continue
		var room_data := rooms[String(room_id)] as Dictionary
		var cell_rect := _json_rect(room_data.get("rect", []))
		var room_rect := Rect2(
			origin + Vector2(cell_rect.position) * scale_factor,
			Vector2(cell_rect.size) * scale_factor
		).grow(2.0)
		var color: Color = target.get(&"color", Color("f8e36b"))
		var label := String(target.get(&"label", "TARGET"))
		draw_rect(room_rect, Color(color, 0.1), true)
		draw_rect(room_rect, color, false, 2.5)
		_draw_target_corners(room_rect, color)
		var center := room_rect.get_center()
		draw_line(center + Vector2(-5.0, 0.0), center + Vector2(5.0, 0.0), color, 1.5)
		draw_line(center + Vector2(0.0, -5.0), center + Vector2(0.0, 5.0), color, 1.5)
		if scale_factor >= 7.0:
			var label_width := maxf(82.0, minf(138.0, room_rect.size.x + 32.0))
			var label_rect := Rect2(
				Vector2(room_rect.position.x, room_rect.position.y - 17.0),
				Vector2(label_width, 16.0)
			)
			draw_rect(label_rect, Color("07131f"), true)
			draw_rect(label_rect, color, false, 1.0)
			draw_string(
				ThemeDB.fallback_font,
				label_rect.position + Vector2(4.0, 12.0),
				label,
				HORIZONTAL_ALIGNMENT_LEFT,
				label_rect.size.x - 8.0,
				9,
				Color("f2ffff")
			)


func _draw_target_corners(room_rect: Rect2, color: Color) -> void:
	const CORNER_LENGTH: float = 9.0
	var left := room_rect.position.x
	var top := room_rect.position.y
	var right := room_rect.end.x
	var bottom := room_rect.end.y
	for segment: PackedVector2Array in [
		PackedVector2Array([Vector2(left, top + CORNER_LENGTH), Vector2(left, top), Vector2(left + CORNER_LENGTH, top)]),
		PackedVector2Array([Vector2(right - CORNER_LENGTH, top), Vector2(right, top), Vector2(right, top + CORNER_LENGTH)]),
		PackedVector2Array([Vector2(left, bottom - CORNER_LENGTH), Vector2(left, bottom), Vector2(left + CORNER_LENGTH, bottom)]),
		PackedVector2Array([Vector2(right - CORNER_LENGTH, bottom), Vector2(right, bottom), Vector2(right, bottom - CORNER_LENGTH)]),
	]:
		draw_polyline(segment, color, 3.5)


func _draw_security(origin: Vector2, scale_factor: float) -> void:
	var security_variant: Variant = _blueprint.get("security", {})
	if not security_variant is Dictionary:
		return
	var security := security_variant as Dictionary
	var cctv := security.get("cctv_network", {}) as Dictionary
	var cameras_variant: Variant = cctv.get("cameras", [])
	if cameras_variant is Array:
		for camera_variant: Variant in cameras_variant as Array:
			if not camera_variant is Dictionary:
				continue
			var cell := _json_vector((camera_variant as Dictionary).get("position", []))
			var point := origin + (Vector2(cell) + Vector2.ONE * 0.5) * scale_factor
			var color := Color("5debe0") if _cctv_online else Color("526b70")
			draw_circle(point, 3.5, color)
			draw_line(point, point + Vector2.RIGHT * 7.0, color, 2.0)
	var laser := security.get("laser_network", {}) as Dictionary
	var barriers_variant: Variant = laser.get("barriers", [])
	if barriers_variant is Array:
		for barrier_variant: Variant in barriers_variant as Array:
			if not barrier_variant is Dictionary:
				continue
			var cell := _json_vector((barrier_variant as Dictionary).get("anchor", []))
			var point := origin + (Vector2(cell) + Vector2.ONE * 0.5) * scale_factor
			var color := Color("ff465e") if _laser_online else Color("4b6c6c")
			draw_line(point + Vector2(0.0, -8.0), point + Vector2(0.0, 8.0), color, 3.0)


func _draw_mission_markers(origin: Vector2, scale_factor: float) -> void:
	var objects_variant: Variant = _blueprint.get("objects", {})
	if not objects_variant is Dictionary:
		return
	var objects := objects_variant as Dictionary
	var spawn := _object_cell(objects, "player_spawn")
	var extraction := _object_cell(objects, "extraction_yard_01")
	var core := _object_cell(objects, "objective_chronos_core_01")
	_draw_marker(origin, scale_factor, spawn, Color("54e7ef"), "IN")
	_draw_marker(origin, scale_factor, extraction, Color("55e5a5"), "EX")
	_draw_marker(
		origin,
		scale_factor,
		core,
		Color("55e5a5") if _core_carried else Color("c68bff"),
		"CORE"
	)


func _draw_player(origin: Vector2, scale_factor: float) -> void:
	if _player_world_position.x < 0.0:
		return
	var cell_position := _player_world_position / TILE_SIZE
	var point := origin + cell_position * scale_factor
	draw_circle(point, 5.5, Color("efffff"))
	draw_circle(point, 3.2, Color("38e7ef"))


func _draw_marker(
	origin: Vector2,
	scale_factor: float,
	cell: Vector2i,
	color: Color,
	label: String
) -> void:
	if cell.x < 0:
		return
	var point := origin + (Vector2(cell) + Vector2.ONE * 0.5) * scale_factor
	draw_circle(point, 6.0, Color(color, 0.3))
	draw_arc(point, 6.0, 0.0, TAU, 16, color, 2.0)
	if scale_factor >= 8.0:
		draw_string(ThemeDB.fallback_font, point + Vector2(8.0, 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, color)


func _access_color(access: String) -> Color:
	match access:
		"LEVEL_1":
			return Color("47cbdc")
		"LEVEL_2":
			return Color("f2a746")
		"VAULT":
			return Color("bd7cff")
		_:
			return Color("61798d")


func _object_cell(objects: Dictionary, object_id: String) -> Vector2i:
	var object_variant: Variant = objects.get(object_id, {})
	if not object_variant is Dictionary:
		return Vector2i(-1, -1)
	return _json_vector((object_variant as Dictionary).get("position", []))


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
