extends RefCounted

var _owner: Node2D
var _container: VBoxContainer
var _scroll_container: ScrollContainer
var _global: Node
var _row_script: GDScript
var _saved_collapse_states: Dictionary = {}
var _update_generation := 0


func setup(owner: Node2D, container: VBoxContainer, scroll_container: ScrollContainer, global: Node, row_script: GDScript) -> void:
	_owner = owner
	_container = container
	_scroll_container = scroll_container
	_global = global
	_row_script = row_script


func scroll_to_selected() -> void:
	scroll_to_sprite(_global.heldSprite, true)


func scroll_to_sprite(target_sprite, ensure_visible := false) -> void:
	if target_sprite == null:
		return
	for row in _container.get_children():
		if row.sprite != target_sprite:
			continue
		if ensure_visible:
			_scroll_container.ensure_control_visible(row)
		else:
			_scroll_container.scroll_vertical = int(row.position.y)
		return


func update_data(sort_by_z := true, pending_scroll_target = null) -> void:
	_saved_collapse_states.clear()
	for row in _container.get_children():
		if is_instance_valid(row.sprite) and row.collapsed:
			_saved_collapse_states[row.sprite.id] = true
	clear()
	_update_generation += 1
	var generation := _update_generation
	await _owner.get_tree().process_frame
	if generation != _update_generation:
		return
	var sprites := _sorted_sprites(sort_by_z)

	var parented_rows := []
	var rows := []
	var sprite_to_row := {}
	for sprite in sprites:
		var row = _row_script.new()
		row.spritePath = sprite.path
		row.sprite = sprite
		row.parent = sprite.parentSprite
		if row.parent == null and sprite.parentId != null:
			row.parent = _global.sprite_by_id(sprite.parentId)
		if row.parent != null:
			parented_rows.append(row)
		rows.append(row)
		sprite_to_row[sprite] = row
		_container.add_child(row)

	for child in parented_rows:
		var parent_row = sprite_to_row.get(child.parent)
		if parent_row != null:
			child.parentTag = parent_row
			parent_row.childrenTags.append(child)
	var ordered := _flatten(rows)
	_apply_order_and_indentation(ordered)
	for row in ordered:
		if _saved_collapse_states.has(row.sprite.id):
			row.collapsed = true
			row._collapse_btn.text = "▶"
			row._set_descendants_visible(false)
	await _consume_pending_scroll(pending_scroll_target)


# Re-read the tree after a link or unlink, keeping the rows themselves. Each
# row's collapsed flag is carried over (`_apply_order_and_indentation` clears it
# for a row that has no children left), and visibility is re-derived at the end,
# so a layer linked into a collapsed group is hidden with the rest of that group
# rather than left showing inside it.
#
# It used to clear every collapsed flag here and never touch visibility, which
# left the two out of step: a collapsed parent came back claiming to be expanded
# while its children stayed hidden.
func refresh_hierarchy(pending_scroll_target = null) -> void:
	var rows := _container.get_children()
	if rows.is_empty():
		return
	var sprite_to_row := {}
	for row in rows:
		row.childrenTags = []
		row.parentTag = null
		row.indent = 0
		row.parent = row.sprite.parentSprite
		sprite_to_row[row.sprite] = row
	for row in rows:
		if row.parent == null:
			continue
		var parent_row = sprite_to_row.get(row.parent)
		if parent_row != null:
			row.parentTag = parent_row
			parent_row.childrenTags.append(row)
	var ordered := _flatten(rows)
	_apply_order_and_indentation(ordered)
	apply_collapse_visibility()
	await _consume_pending_scroll(pending_scroll_target)


# Live layers in list order: by z, breaking ties on registry order so the result
# is STABLE. Godot's sort is not stable, and rigs routinely leave many layers on
# the same z (20 of 54 on a real avatar), so a bare `a.z > b.z` reshuffled those
# layers whenever the input array changed: delete a layer and the list came back
# in a different order, with a different row at the top. Registry order is
# insertion order, which does not move when a layer is removed.
func _sorted_sprites(sort_by_z: bool) -> Array:
	var sprites: Array = _global.sprite_nodes()
	sprites = sprites.filter(func(sprite): return not sprite.is_queued_for_deletion())
	if not sort_by_z:
		return sprites
	var registry_order := {}
	for index in sprites.size():
		registry_order[sprites[index]] = index
	sprites.sort_custom(func(a, b):
		if a.z != b.z:
			return a.z > b.z
		return registry_order[a] < registry_order[b]
	)
	return sprites


# Bring the existing rows into line with the live layers: drop rows whose layer
# is gone, add rows for layers that have appeared, then re-flatten and re-indent.
# Deleting, duplicating and undoing all go through here rather than update_data(),
# because a rebuild clears every row and builds the list again a frame later,
# which blanks the panel and throws away both the scroll position and which
# groups the user had collapsed.
func sync_rows(sort_by_z := true) -> void:
	var sprites := _sorted_sprites(sort_by_z)
	var row_for := {}
	for row in _container.get_children():
		if is_instance_valid(row.sprite) and not row.sprite.is_queued_for_deletion():
			row_for[row.sprite] = row
			continue
		_container.remove_child(row)
		row.queue_free()

	var rows := []
	for sprite in sprites:
		var row = row_for.get(sprite)
		if row == null:
			row = _row_script.new()
			row.spritePath = sprite.path
			row.sprite = sprite
			_container.add_child(row)
		rows.append(row)

	var sprite_to_row := {}
	for row in rows:
		row.childrenTags = []
		row.parentTag = null
		row.parent = row.sprite.parentSprite
		if row.parent == null and row.sprite.parentId != null:
			row.parent = _global.sprite_by_id(row.sprite.parentId)
		sprite_to_row[row.sprite] = row
	for row in rows:
		var parent_row = sprite_to_row.get(row.parent) if row.parent != null else null
		if parent_row == null:
			continue
		row.parentTag = parent_row
		parent_row.childrenTags.append(row)

	_apply_order_and_indentation(_flatten(rows))
	apply_collapse_visibility()


# Show every row whose ancestors are all expanded. Used after the tree changes
# shape without a rebuild: a row that was hidden under a collapsed parent has to
# reappear once that parent is gone.
func apply_collapse_visibility() -> void:
	for row in _container.get_children():
		var shown := true
		var ancestor = row.parentTag
		while ancestor != null:
			if ancestor.collapsed:
				shown = false
				break
			ancestor = ancestor.parentTag
		row.visible = shown


func clear() -> void:
	for row in _container.get_children():
		row.queue_free()


func filter(text: String) -> void:
	var query := text.to_lower()
	if query.is_empty():
		for row in _container.get_children():
			row.visible = true
		for row in _container.get_children():
			if row.collapsed:
				row._set_descendants_visible(false)
		return
	for row in _container.get_children():
		row.visible = false
	for row in _container.get_children():
		if not row._name_label.text.to_lower().begins_with(query):
			continue
		row.visible = true
		var ancestor = row.parentTag
		while ancestor != null:
			ancestor.visible = true
			ancestor = ancestor.parentTag


# The layers from `a` to `b` inclusive, in the order the list shows them, for a
# shift-click range pick. Rows hidden by a collapsed parent or the filter are
# left out: the user is picking what they can see.
func layers_between(a, b) -> Array:
	var visible_rows := []
	for row in _container.get_children():
		if row.visible and is_instance_valid(row.sprite):
			visible_rows.append(row)
	var first := -1
	var last := -1
	for index in visible_rows.size():
		var sprite = visible_rows[index].sprite
		if sprite == a:
			first = index
		if sprite == b:
			last = index
	if first == -1 or last == -1:
		return [b]
	if first > last:
		var swap := first
		first = last
		last = swap
	var picked := []
	for index in range(first, last + 1):
		picked.append(visible_rows[index].sprite)
	# The active layer leads the selection, so the range starts from the one the
	# user shift-clicked away from.
	if picked.size() > 1 and picked[0] != a:
		picked.reverse()
	return picked


func refresh_names() -> void:
	for row in _container.get_children():
		row.refreshName()


# The row showing this layer, or null while the list does not have one (a layer
# filtered out of the list, or one deleted since the caller looked it up).
func row_for(sprite) -> Node:
	for row in _container.get_children():
		if row.sprite == sprite:
			return row
	return null


func update_all_visible() -> void:
	for row in _container.get_children():
		row.updateVis()


func _flatten(rows: Array) -> Array:
	var roots := []
	for row in rows:
		if row.parentTag == null:
			roots.append(row)
	var ordered := []
	var stack := []
	for index in range(roots.size() - 1, -1, -1):
		stack.append(roots[index])
	while not stack.is_empty():
		var row = stack.pop_back()
		ordered.append(row)
		for index in range(row.childrenTags.size() - 1, -1, -1):
			stack.append(row.childrenTags[index])
	return ordered


func _apply_order_and_indentation(rows: Array) -> void:
	for index in rows.size():
		_container.move_child(rows[index], index)
	for row in rows:
		row.indent = 0
		var ancestor = row.parentTag
		var visited := {}
		while ancestor != null and not visited.has(ancestor):
			visited[ancestor] = true
			row.indent += 1
			ancestor = ancestor.parentTag
		if row.childrenTags.is_empty():
			row._collapse_btn.text = ""
			row._collapse_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.collapsed = false
		else:
			row._collapse_btn.text = "▶" if row.collapsed else "▼"
			row._collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		# Every row, not just the ones with children. updateIndent() is what
		# actually widens the indent spacer, so while it was called only for
		# parents, a child layer rendered flush against the left edge and nothing
		# below a parent looked like it belonged to it.
		row.updateIndent(_row_width())


# What one row has to work with: the scroll area minus its vertical scrollbar,
# which appears as soon as the list is longer than the panel.
func _row_width() -> float:
	if _scroll_container == null:
		return -1.0
	var width := _scroll_container.size.x
	var bar := _scroll_container.get_v_scroll_bar()
	if bar != null and bar.visible:
		width -= bar.size.x
	return width


# How much wider the panel has to be for the deepest row to show its full
# indentation, or 0 when it already fits. The panel is wider than one row by its
# own padding and the scrollbar, so that difference is carried across.
func extra_width_for_full_indent(panel_width: float) -> float:
	var row_width := _row_width()
	if row_width <= 0.0:
		return 0.0
	var needed := 0.0
	for row in _container.get_children():
		needed = maxf(needed, row.requiredWidth())
	return maxf(0.0, needed - row_width) if needed > row_width else 0.0


# Re-clamp the indentation after the sidebar is resized, since the budget each
# row has to spend on depth moved with it.
func reflow() -> void:
	var width := _row_width()
	for row in _container.get_children():
		row.updateIndent(width)


func _consume_pending_scroll(target) -> void:
	if target == null:
		return
	await _owner.get_tree().process_frame
	scroll_to_sprite(target)
