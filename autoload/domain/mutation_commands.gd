extends RefCounted

# The single canonical path for user-initiated mutations that belong in undo
# history. Production code never opens a history transaction directly; it calls
# one of the commands below, and the command owns the before/after snapshot
# boundary exactly once.
#
# Command kinds:
#   set_layer_property   — discrete single-property edit (toggle, dropdown, spinbox)
#   drag_layer_property  — continuous single-property edit (slider drag, held key)
#   set_layer_field      — discrete edit of one entry inside a structured field
#   structural           — hierarchy, add/remove, costume, import, image replacement
#   drag                 — continuous multi-field gesture (canvas drag, path editing)
#
# Every command returns true when it captured a change. Commands that find
# nothing to do abort the transaction, so an aborted command leaves no dead
# history entry for the user to undo through.

const SpriteState = preload("res://autoload/domain/sprite_state.gd")

# The history sink is resolved at runtime rather than by naming the UndoManager
# autoload directly, so the command layer stays loadable — and unit-testable
# with an injected recorder — in workspaces that register no singletons. With no
# sink resolved the commands still apply their mutation, just without history.
static var _history_override: Object = null


static func set_history_sink(sink: Object) -> void:
	_history_override = sink


static func _history() -> Object:
	if _history_override != null:
		return _history_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/UndoManager")
	return null


# Runtime property names that undo actually snapshots, plus the scene-owned
# properties SpriteState captures under different save keys. A command that
# names anything outside this set is a programming error: the write would not
# survive undo or a save round-trip.
static func persistent_properties() -> Dictionary:
	var names := {}
	for save_key in SpriteState.SIMPLE_FIELDS:
		names[SpriteState.SIMPLE_FIELDS[save_key]] = true
	for save_key in SpriteState.STRUCTURED_FIELDS:
		names[SpriteState.STRUCTURED_FIELDS[save_key]] = true
	names["position"] = true
	names["offset"] = true
	names["parentId"] = true
	return names


static func is_persistent_property(property: String) -> bool:
	return persistent_properties().has(property)


# Discrete single-property edit. Skips unchanged writes so re-selecting the
# current dropdown entry or re-clicking a settled toggle adds no history.
static func set_layer_property(sprite: Object, property: String, value: Variant) -> bool:
	return _write_property(sprite, property, value, "")


# Continuous single-property edit. All calls sharing a gesture key collapse into
# one history entry; the gesture ends on mouse release or when the edit target
# changes, so consecutive drags of different controls stay separate entries.
static func drag_layer_property(sprite: Object, property: String, value: Variant, gesture: String) -> bool:
	return _write_property(sprite, property, value, _gesture_key(sprite, property, gesture))


# Edit of one key inside a structured field (an animation clip entry, one
# costume slot). The field is re-assigned so the sprite setter still runs. Pass
# a gesture to collapse a continuous edit of that key into one history entry.
static func set_layer_field(
	sprite: Object, property: String, index: int, key: Variant, value: Variant, gesture: String = ""
) -> bool:
	if not _is_live(sprite) or not _validate(property):
		return false
	var collection: Variant = sprite.get(property)
	if not (collection is Array) or index < 0 or index >= collection.size():
		return false
	var entry: Variant = collection[index]
	if entry is Dictionary and _same_value(entry.get(key), value):
		return false
	var key_gesture := ""
	if not gesture.is_empty():
		key_gesture = _gesture_key(sprite, "%s[%d].%s" % [property, index, str(key)], gesture)
	var history := _history()
	if history != null:
		history.begin(key_gesture)
	collection[index][key] = value
	sprite.set(property, collection)
	if history != null:
		history.commit()
	return true


# Structural or multi-field edit. The body performs the mutation and returns
# false when it turned out to be a no-op, which discards the history entry.
static func structural(body: Callable) -> bool:
	return _run(body, "")


# Continuous multi-field gesture (canvas drag, ribbon path editing). Every call
# sharing the gesture key folds into the entry opened by the first one.
static func drag(gesture: String, body: Callable) -> bool:
	return _run(body, gesture)


# Capture the pre-state for a bulk operation that cannot run inside a Callable
# because it awaits across frames (avatar load, PSD import, replacement review).
# Call it once the operation is certain to proceed, so a cancelled or failed
# operation leaves no dead history entry behind.
static func capture_bulk() -> void:
	var history := _history()
	if history == null:
		return
	history.begin()
	history.commit()


# End a continuous gesture that finished outside a mouse release (a held-key
# burst stopping). Name the gesture so an unrelated drag still in flight is not
# cut short by a per-frame poll.
static func end_gesture(gesture: String = "") -> void:
	var history := _history()
	if history != null:
		history.end_gesture(gesture)


static func _run(body: Callable, gesture: String) -> bool:
	var history := _history()
	if history == null:
		var bare: Variant = body.call()
		return not (bare is bool and not bare)
	history.begin(gesture)
	var result: Variant = body.call()
	if result is bool and not result:
		history.abort()
		return false
	history.commit()
	return true


static func _write_property(sprite: Object, property: String, value: Variant, gesture: String) -> bool:
	if not _is_live(sprite) or not _validate(property):
		return false
	var targets := _edit_targets(sprite)
	var pending := []
	for target in targets:
		if _is_live(target) and not _same_value(target.get(property), value):
			pending.append(target)
	if pending.is_empty():
		return false
	var history := _history()
	if history != null:
		history.begin(gesture)
	for target in pending:
		target.set(property, value)
	if history != null:
		history.commit()
	return true


# Who an edit lands on. Editing the active layer while several are selected
# edits all of them, as one history entry: that is what selecting several layers
# in the list is for, and it matches every other layers panel. An edit aimed at
# some OTHER layer (an eye-track target being assigned, a restore) is left alone.
static func _edit_targets(sprite: Object) -> Array:
	var global := _global()
	if global == null or sprite != global.get("heldSprite"):
		return [sprite]
	var selected: Variant = global.call("selected_sprites")
	if selected is Array and selected.size() > 1:
		return selected
	return [sprite]


static func _global() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/Global")
	return null


# Gesture keys are scoped to the layer and property so dragging one slider,
# selecting another layer, and dragging the same slider again are two entries.
static func _gesture_key(sprite: Object, property: String, gesture: String) -> String:
	return "%s#%s#%s" % [gesture, str(sprite.get("id")), property]


static func _is_live(sprite: Object) -> bool:
	return sprite != null and is_instance_valid(sprite)


static func _validate(property: String) -> bool:
	if is_persistent_property(property):
		return true
	push_error("MutationCommands: '%s' is not a persistent layer property" % property)
	return false


# Whether two property values count as the same edit. Public because the panels
# ask the same question of a multi-layer selection when they decide whether to
# show a number or a mixed-value dash.
static func values_match(a: Variant, b: Variant) -> bool:
	return _same_value(a, b)


# Arrays and dictionaries are compared by value: callers routinely hand back a
# mutated duplicate of the current collection, and identity comparison would
# read every one of those as unchanged.
static func _same_value(current: Variant, value: Variant) -> bool:
	if current is Array or current is Dictionary:
		return current == value
	if current is PackedVector2Array or current is PackedFloat32Array:
		return current == value
	if current is float and value is float:
		return is_equal_approx(current, value)
	return current == value
