extends RefCounted

## Owns the selected layer and deterministic click-cycling state. Scene/UI code
## reaches this through Global's selection API so selection invalidation and
## future observers have one canonical boundary.
signal changed(current: Object, previous: Object)

var current: Object = null
var _last_hits: Array = []
var _hit_index := 0


func select(sprite: Object, reset_cycle: bool = true) -> Object:
	var previous := current
	current = sprite if sprite == null or is_instance_valid(sprite) else null
	if reset_cycle:
		reset_click_cycle()
	if current != previous:
		changed.emit(current, previous)
	return previous


func clear() -> Object:
	return select(null)


func choose_from_hits(hits: Array, resolver: Callable) -> Object:
	if hits.is_empty():
		clear()
		return null

	if hits != _last_hits:
		_hit_index = 0
	else:
		_hit_index = (_hit_index + 1) % hits.size()

	var resolved: Variant = resolver.call(hits[_hit_index])
	select(resolved as Object, false)
	_last_hits = hits.duplicate()
	return current


func reset_click_cycle() -> void:
	_last_hits.clear()
	_hit_index = 0
