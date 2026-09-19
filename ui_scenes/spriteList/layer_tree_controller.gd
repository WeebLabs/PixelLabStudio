extends RefCounted

var _owner: Node2D
var _container: VBoxContainer
var _scroll_container: ScrollContainer
var _global: Node
var _row_script: GDScript
var _saved_collapse_states: Dictionary = {}
var _update_generation := 0
# A link waiting for the list to be rebuilt around it; see prepare_link_framing.
var _pending_link: Dictionary = {}
# Hierarchy re-orders whose scroll is not settled on the new layout yet. A count,
# not a flag, so one refresh settling does not clear another still in flight.
var _layout_settling := 0


func setup(owner: Node2D, container: VBoxContainer, scroll_container: ScrollContainer, global: Node, row_script: GDScript) -> void:
	_owner = owner
	_container = container
	_scroll_container = scroll_container
	_global = global
	_row_script = row_script


func scroll_to_selected() -> void:
	# Rows re-ordered this frame still report last frame's positions, so following
	# the selection now chases where its row USED to be. Undoing an unlink
	# scrolled the list to the bottom that way, where the unlinked row had been.
	# The refresh settles the scroll a frame later instead.
	if _layout_settling > 0:
		return
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


func update_data(sort_by_z := true) -> void:
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
	await _consume_pending_link()


# Re-read the tree after a link or unlink, keeping the rows themselves. Each
# row's collapsed flag is carried over (`_apply_order_and_indentation` clears it
# for a row that has no children left), and visibility is re-derived at the end,
# so a layer linked into a collapsed group is hidden with the rest of that group
# rather than left showing inside it.
#
# It used to clear every collapsed flag here and never touch visibility, which
# left the two out of step: a collapsed parent came back claiming to be expanded
# while its children stayed hidden.
func refresh_hierarchy() -> void:
	var rows := _container.get_children()
	if rows.is_empty():
		return
	var view_anchor := _capture_view_anchor(rows)
	_layout_settling += 1
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
	# Row positions are only re-laid out on the next frame.
	await _owner.get_tree().process_frame
	_layout_settling -= 1
	if not _pending_link.is_empty():
		_apply_pending_link()
	else:
		_restore_view_anchor(view_anchor)


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


# How the list follows a link depends on where the parent was picked.
#
# Picked in the list, the user had already scrolled to that parent, so the list
# keeps the parent row where it was on screen. Holding the raw scroll offset is
# not enough: the child's row leaves its old place, and when that place was above
# the view every visible row shifts up by one.
#
# Picked on the canvas, the list was last framed on the child, from the click
# that selected it, and the child has just moved out from under that frame. The
# list brings the child and its new parent into view together.
#
# Call before the rows are re-ordered, since the parent's on-screen place is read
# from the layout the user was looking at.
func prepare_link_framing(child, parent, parent_picked_on_canvas: bool) -> void:
	var parent_row = row_for(parent)
	_pending_link = {
		"child": child,
		"parent": parent,
		"frame_both": parent_picked_on_canvas,
		"anchor": parent_row.position.y - _scroll_container.scroll_vertical if parent_row != null else null,
	}


func _consume_pending_link() -> void:
	if _pending_link.is_empty():
		return
	# Row positions are only re-laid out on the next frame.
	await _owner.get_tree().process_frame
	_apply_pending_link()


func _apply_pending_link() -> void:
	var link := _pending_link
	_pending_link = {}
	if link.is_empty() or not (is_instance_valid(link.child) and is_instance_valid(link.parent)):
		return
	if link.frame_both:
		_frame_link(link.child, link.parent)
	elif link.anchor != null:
		_hold_row_at(link.parent, link.anchor)


# Everything else that re-orders the tree (unlink, undo, redo) keeps the list
# where the user was reading it. The anchor is the topmost visible row that is
# not itself moving: a row whose parent changed moves, and so does every row
# under it, so neither can hold the view. Anchoring on one of those would follow
# the moved layer, and holding the raw scroll offset would let the rows in view
# shift whenever a moved row leaves or arrives above them.
#
# Captured before the rows are re-ordered. `row.parent` still holds the parent
# from the last layout, and the sprite already carries the new one.
func _capture_view_anchor(rows: Array) -> Array:
	var moved := {}
	for row in rows:
		if is_instance_valid(row.sprite) and row.parent != row.sprite.parentSprite:
			moved[row] = true
	var top := float(_scroll_container.scroll_vertical)
	var bottom := top + _scroll_container.size.y
	var anchor := []
	for row in rows:
		if not row.visible or not is_instance_valid(row.sprite):
			continue
		if row.position.y + row.size.y <= top or row.position.y >= bottom:
			continue
		if _row_moves(row, moved):
			continue
		anchor.append({"sprite": row.sprite, "offset": row.position.y - top})
	return anchor


func _row_moves(row, moved: Dictionary) -> bool:
	var visited := {}
	var current = row
	while current != null and not visited.has(current):
		if moved.has(current):
			return true
		visited[current] = true
		current = current.parentTag
	return false


func _restore_view_anchor(anchor: Array) -> void:
	for entry in anchor:
		if not is_instance_valid(entry.sprite):
			continue
		var row = row_for(entry.sprite)
		if row != null and row.visible:
			_hold_row_at(entry.sprite, entry.offset)
			return


func _hold_row_at(sprite, offset_in_view: float) -> void:
	var row = row_for(sprite)
	if row == null:
		return
	_scroll_container.scroll_vertical = int(round(row.position.y - offset_in_view))


# Centre the parent and the child together. When they do not fit, the child
# wins: it is the layer that moved, and the parent is kept as close above it as
# the view allows. A child hidden in a collapsed parent has no row to show, so
# the parent is centred on its own.
func _frame_link(child, parent) -> void:
	var parent_row = row_for(parent)
	if parent_row == null:
		return
	var view := _scroll_container.size.y
	var top: float = parent_row.position.y
	var bottom: float = top + parent_row.size.y
	var child_row = row_for(child)
	if child_row != null and child_row.visible:
		bottom = child_row.position.y + child_row.size.y
	var scroll: float
	if bottom - top <= view:
		scroll = (top + bottom - view) * 0.5
	else:
		scroll = bottom - view
	_scroll_container.scroll_vertical = int(round(maxf(0.0, scroll)))
