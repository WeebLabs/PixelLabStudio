extends RefCounted

## Owns the selected layer and click-cycling down a stack of overlapping layers.
## Scene/UI code reaches this through Global's selection API so selection
## invalidation and future observers have one canonical boundary.
signal changed(current: Object, previous: Object)

## The active layer. Everything that edits one layer (both sidebars, the canvas,
## the keyboard) reads this, so it stays a single object.
var current: Object = null

## Layers selected alongside the active one, for the operations that can act on
## several at once (duplicate, delete). Always excludes `current`, so the whole
## selection is `current` followed by these, in the order they were picked.
var extras: Array = []


func selection() -> Array:
	var all := []
	if current != null and is_instance_valid(current):
		all.append(current)
	for sprite in extras:
		if is_instance_valid(sprite):
			all.append(sprite)
	return all


func is_selected(sprite: Object) -> bool:
	return sprite != null and (sprite == current or extras.has(sprite))


# Select one layer, dropping any multi-selection: an ordinary click replaces the
# selection rather than adding to it.
func select(sprite: Object, reset_cycle: bool = true) -> Object:
	var had_extras := not extras.is_empty()
	extras.clear()
	var previous := current
	current = sprite if sprite == null or is_instance_valid(sprite) else null
	if current != previous or had_extras:
		changed.emit(current, previous)
	return previous


# Add or remove one layer from the selection, for a modifier-click. Removing the
# active layer promotes the next one, so there is always an active layer while
# anything is selected.
func toggle(sprite: Object) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var previous := current
	if sprite == current:
		current = extras.pop_front() if not extras.is_empty() else null
	elif extras.has(sprite):
		extras.erase(sprite)
	elif current == null:
		current = sprite
	else:
		extras.append(sprite)
	changed.emit(current, previous)


# Replace the selection with `sprites`, the first of which becomes active. Used
# for a range pick, where the caller knows the list order.
func select_many(sprites: Array) -> void:
	var previous := current
	extras.clear()
	current = null
	for sprite in sprites:
		if sprite == null or not is_instance_valid(sprite):
			continue
		if current == null:
			current = sprite
		elif sprite != current:
			extras.append(sprite)
	changed.emit(current, previous)


# Drop a layer that is going away, without disturbing the rest of the selection.
func forget(sprite: Object) -> void:
	if extras.has(sprite):
		extras.erase(sprite)
		changed.emit(current, current)
	elif sprite == current:
		var previous := current
		current = extras.pop_front() if not extras.is_empty() else null
		changed.emit(current, previous)


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
