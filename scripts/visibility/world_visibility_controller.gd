class_name WorldVisibilityController
extends Node

signal target_visibility_changed(target: Node2D, is_revealed: bool)

@export_range(0.02, 0.5, 0.01) var refresh_interval_seconds: float = 0.05

var _probe: PlayerVisibilityProbe = null
var _targets: Array[Node2D] = []
var _base_modulates: Dictionary[int, Color] = {}
var _revealed: Dictionary[int, bool] = {}
var _enabled: bool = false
var _refresh_accumulator: float = 0.0


func _ready() -> void:
	process_physics_priority = 300
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not _enabled:
		return
	_refresh_accumulator += maxf(0.0, delta)
	if _refresh_accumulator + 0.000001 < refresh_interval_seconds:
		return
	_refresh_accumulator = fmod(_refresh_accumulator, refresh_interval_seconds)
	refresh_now()


func configure(probe: PlayerVisibilityProbe) -> void:
	_probe = probe
	_enabled = probe != null and is_instance_valid(probe) and probe.is_query_enabled()
	_refresh_accumulator = refresh_interval_seconds
	if not _enabled:
		hide_all_immediately()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled and _probe != null and is_instance_valid(_probe)
	if not _enabled:
		hide_all_immediately()
	else:
		refresh_now()


func register_target(target: Node2D) -> void:
	if target == null or not is_instance_valid(target) or _targets.has(target):
		return
	_targets.append(target)
	var instance_id := target.get_instance_id()
	_base_modulates[instance_id] = target.modulate
	_revealed[instance_id] = false
	_apply_revealed(target, false, false)


func unregister_target(target: Node2D) -> void:
	if target == null:
		return
	_targets.erase(target)
	var instance_id := target.get_instance_id()
	_base_modulates.erase(instance_id)
	_revealed.erase(instance_id)


func clear_runtime_targets() -> void:
	for index: int in range(_targets.size() - 1, -1, -1):
		var target: Node2D = _targets[index]
		if not is_instance_valid(target) or target.is_in_group(&"ghost_actor"):
			if is_instance_valid(target):
				unregister_target(target)
			else:
				_targets.remove_at(index)
	_prune_invalid_targets()


func hide_all_immediately() -> void:
	_prune_invalid_targets()
	for target: Node2D in _targets:
		_apply_revealed(target, false)


func refresh_now() -> void:
	_prune_invalid_targets()
	for target: Node2D in _targets:
		var should_reveal := (
			_enabled
			and _probe != null
			and is_instance_valid(_probe)
			and _probe.is_actor_visible(target)
		)
		_apply_revealed(target, should_reveal)


func is_target_revealed(target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return bool(_revealed.get(target.get_instance_id(), false))


func get_tracked_target_count() -> int:
	_prune_invalid_targets()
	return _targets.size()


func _apply_revealed(target: Node2D, reveal: bool, emit_change: bool = true) -> void:
	if target == null or not is_instance_valid(target):
		return
	var instance_id := target.get_instance_id()
	var previous := bool(_revealed.get(instance_id, false))
	var base_color: Color = _base_modulates.get(instance_id, target.modulate) as Color
	var next_color := base_color
	next_color.a = base_color.a if reveal else 0.0
	target.modulate = next_color
	_revealed[instance_id] = reveal
	if emit_change and previous != reveal:
		target_visibility_changed.emit(target, reveal)


func _prune_invalid_targets() -> void:
	for index: int in range(_targets.size() - 1, -1, -1):
		var target: Node2D = _targets[index]
		if is_instance_valid(target):
			continue
		_targets.remove_at(index)
