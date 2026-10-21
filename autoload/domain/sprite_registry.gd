class_name SpriteRegistry
extends RefCounted

## Canonical live sprite index for enumeration and hot runtime lookups. Sprite
## nodes retain the `saved` group for scene/debugging compatibility, while
## consumers avoid repeated group-array construction and O(layer²) ID scans.
var _by_id: Dictionary = {}
var _ordered: Array = []
var _eye_target_ids: Dictionary = {}
var _eye_target_cache_frame := -1

func register(sprite: Object) -> void:
	if sprite == null:
		return
	var sprite_id: Variant = sprite.get("id")
	var previous: Variant = _by_id.get(sprite_id)
	if previous != null and previous != sprite:
		_ordered.erase(previous)
	_by_id[sprite_id] = sprite
	if not _ordered.has(sprite):
		_ordered.append(sprite)
	_eye_target_cache_frame = -1

func unregister(sprite: Object) -> void:
	if sprite == null:
		return
	var sprite_id: Variant = sprite.get("id")
	if _by_id.get(sprite_id) == sprite:
		_by_id.erase(sprite_id)
	_ordered.erase(sprite)
	_eye_target_cache_frame = -1

# Put `sprite` immediately after `anchor` in enumeration order. The layer list
# breaks ties on this order, so a duplicate placed here lands beside the layer it
# was copied from instead of at the bottom of everything sharing its z.
func place_after(sprite: Object, anchor: Object) -> void:
	if sprite == null or anchor == null or sprite == anchor:
		return
	if not _ordered.has(anchor):
		return
	_ordered.erase(sprite)
	_ordered.insert(_ordered.find(anchor) + 1, sprite)
	_eye_target_cache_frame = -1


func clear() -> void:
	_by_id.clear()
	_ordered.clear()
	_eye_target_ids.clear()
	_eye_target_cache_frame = -1

func by_id(sprite_id: Variant) -> Object:
	var sprite: Variant = _by_id.get(sprite_id)
	if sprite != null and is_instance_valid(sprite):
		return sprite
	if sprite != null:
		_by_id.erase(sprite_id)
		_ordered.erase(sprite)
	return null

func all() -> Array:
	_prune_invalid()
	return _ordered.duplicate()

func size() -> int:
	_prune_invalid()
	return _ordered.size()

func maximum_z(fallback: int = -1) -> int:
	var result := fallback
	for sprite in _ordered:
		if is_instance_valid(sprite):
			result = maxi(result, int(sprite.get("z")))
	return result

func is_eye_target(sprite_id: Variant) -> bool:
	var frame := Engine.get_process_frames()
	if frame != _eye_target_cache_frame:
		_rebuild_eye_targets(frame)
	return _eye_target_ids.has(sprite_id)

func rebuild_eye_targets() -> void:
	_rebuild_eye_targets(Engine.get_process_frames())

func _rebuild_eye_targets(frame: int) -> void:
	_eye_target_ids.clear()
	for sprite in _ordered:
		if not is_instance_valid(sprite):
			continue
		if int(sprite.get("eyeTrackMode")) == 1:
			var target_id: Variant = sprite.get("eyeTrackTargetId")
			if target_id != null:
				_eye_target_ids[target_id] = true
	_eye_target_cache_frame = frame

func _prune_invalid() -> void:
	for index in range(_ordered.size() - 1, -1, -1):
		var sprite: Variant = _ordered[index]
		if is_instance_valid(sprite):
			continue
		_ordered.remove_at(index)
	for sprite_id in _by_id.keys():
		if not is_instance_valid(_by_id[sprite_id]):
			_by_id.erase(sprite_id)
