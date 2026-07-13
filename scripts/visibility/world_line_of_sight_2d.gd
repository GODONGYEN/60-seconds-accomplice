class_name WorldLineOfSight2D
extends RefCounted

const MAX_OPEN_DOOR_PASSES: int = 4


static func has_clear_line(
	space_state: PhysicsDirectSpaceState2D,
	from_position: Vector2,
	to_position: Vector2,
	collision_mask: int,
	excluded_rids: Array[RID] = []
) -> bool:
	if space_state == null or collision_mask <= 0:
		return false
	var ray_excludes: Array[RID] = excluded_rids.duplicate()
	for _pass_index: int in range(MAX_OPEN_DOOR_PASSES):
		var query := PhysicsRayQueryParameters2D.create(
			from_position,
			to_position,
			collision_mask,
			ray_excludes
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider: Object = hit.get("collider") as Object
		if collider is SecurityDoor and (collider as SecurityDoor).is_open:
			var collider_rid: RID = hit.get("rid", RID())
			if collider_rid.is_valid():
				ray_excludes.append(collider_rid)
				continue
		return false
	return false
