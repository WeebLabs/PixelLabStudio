extends RefCounted

## Owns the selected layer and click-cycling down a stack of overlapping layers.
## Scene/UI code reaches this through Global's selection API so selection
## invalidation and future observers have one canonical boundary.
signal changed(current: Object, previous: Object)

var current: Object = null


func select(sprite: Object, reset_cycle: bool = true) -> Object:
	var previous := current
	current = sprite if sprite == null or is_instance_valid(sprite) else null
	if current != previous:
		changed.emit(current, previous)
	return previous


func clear() -> Object:
	return select(null)


# Pick one layer out of a click's candidates, which arrive ordered top-first.
# Clicking a stack selects its top layer; clicking again steps to the next layer
# down, and past the bottom it wraps back to the top.
#
# The step is anchored to the layer that is actually selected, not to a stored
# index into the previous click's candidate array. The avatar is in constant
# motion (bounce, wobble, animation clips), so the same screen point resolves to
# a slightly different candidate list from one click to the next: measured at a
# human click rate over a moving rig, the list changed on 10 of 12 clicks. An
# index keyed on that list reset to the top almost every click, which is what
# made cycling look broken and made a click on the already-selected top layer
# look like it had not registered at all.
func choose_from_hits(hits: Array, resolver: Callable) -> Object:
	if hits.is_empty():
		clear()
		return null

	var candidates := []
	for hit in hits:
		var resolved: Variant = resolver.call(hit)
		if resolved != null and is_instance_valid(resolved) and not candidates.has(resolved):
			candidates.append(resolved)
	if candidates.is_empty():
		clear()
		return null

	var index := 0
	if current != null:
		var held := candidates.find(current)
		if held != -1:
			index = (held + 1) % candidates.size()

	select(candidates[index] as Object, false)
	return current


# Kept for callers that used to drop stored cycle state. Cycling now reads the
# held layer, so there is no separate state to reset.
func reset_click_cycle() -> void:
	pass
