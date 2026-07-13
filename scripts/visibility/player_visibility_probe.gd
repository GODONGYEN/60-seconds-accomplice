class_name PlayerVisibilityProbe
extends Node2D

const DEFAULT_VISIBILITY_BLOCKER_MASK: int = 64

@export_range(32.0, 640.0, 1.0) var visibility_radius: float = 256.0
@export_flags_2d_physics var blocker_collision_mask: int = DEFAULT_VISIBILITY_BLOCKER_MASK

var _query_enabled: bool = false


func set_query_enabled(enabled: bool) -> void:
	_query_enabled = enabled


func is_query_enabled() -> bool:
	return _query_enabled


func set_visibility_radius(radius: float) -> void:
	visibility_radius = maxf(1.0, radius)


func get_visibility_origin() -> Vector2:
	return global_position


func is_world_point_visible(world_position: Vector2) -> bool:
	return _is_world_point_visible_with_excludes(world_position, [])


func _is_world_point_visible_with_excludes(
	world_position: Vector2,
	additional_excludes: Array[RID]
) -> bool:
	if not _query_enabled or not is_inside_tree():
		return false
	if global_position.distance_squared_to(world_position) > visibility_radius * visibility_radius:
		return false
	var excludes := _get_owner_excludes()
	excludes.append_array(additional_excludes)
	return WorldLineOfSight2D.has_clear_line(
		get_world_2d().direct_space_state,
		global_position,
		world_position,
		blocker_collision_mask,
		excludes
	)


func is_actor_visible(actor: Node2D) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var sample_position := actor.global_position
	if actor.has_method(&"get_visibility_sample_position"):
		sample_position = actor.call(&"get_visibility_sample_position") as Vector2
	var target_excludes: Array[RID] = []
	var collision_target := actor as CollisionObject2D
	if collision_target != null:
		target_excludes.append(collision_target.get_rid())
	return _is_world_point_visible_with_excludes(sample_position, target_excludes)


func _get_owner_excludes() -> Array[RID]:
	var excludes: Array[RID] = []
	var owner_body := get_parent() as CollisionObject2D
	if owner_body == null and get_parent() != null:
		owner_body = get_parent().get_parent() as CollisionObject2D
	if owner_body != null:
		excludes.append(owner_body.get_rid())
	return excludes
