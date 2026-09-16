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
	var sprites: Array = _global.sprite_nodes()
	if sort_by_z:
		# Sort by z, breaking ties on registry order so the result is STABLE.
		# Godot's sort is not stable, and rigs routinely leave many layers on the
		# same z (20 of 54 on a real avatar), so a bare `a.z > b.z` reshuffled
		# those layers on every rebuild: delete a layer and the list came back in
		# a different order, with a different row at the top. Registry order is
		# insertion order, which does not move when a layer is removed.
		var registry_order := {}
		for index in sprites.size():
			registry_order[sprites[index]] = index
		sprites.sort_custom(func(a, b):
			if a.z != b.z:
				return a.z > b.z
			return registry_order[a] < registry_order[b]
		)

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


func refresh_hierarchy(pending_scroll_target = null) -> void:
	var rows := _container.get_children()
	if rows.is_empty():
		return
	var sprite_to_row := {}
	for row in rows:
		row.childrenTags = []
		row.parentTag = null
		row.indent = 0
		row.collapsed = false
		row._collapse_btn.text = ""
		row._collapse_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	await _consume_pending_scroll(pending_scroll_target)


# Drop one layer's row in place, for deletion. Rebuilding the list would work,
# but it throws away the scroll position and sends the user back to the top of a
# long list every time they delete something. The remaining rows are untouched,
# so the deleted row simply disappears from where it was.
#
# The delete command unlinks the layer's children first, so their rows become
# roots here.
func remove_sprite_row(sprite, filter_text := "") -> void:
	var removed = null
	for row in _container.get_children():
		if row.sprite == sprite:
			removed = row
			break
	if removed == null:
		return

	for child_row in removed.childrenTags:
		child_row.parentTag = null
		child_row.parent = null
	var parent_row = removed.parentTag
	if parent_row != null:
		parent_row.childrenTags.erase(removed)
		if parent_row.childrenTags.is_empty():
			parent_row._collapse_btn.text = ""
			parent_row._collapse_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent_row.collapsed = false

	# Out of the container before the reorder, since queue_free() leaves it in
	# place until the end of the frame.
	_container.remove_child(removed)
	removed.queue_free()

	_apply_order_and_indentation(_flatten(_container.get_children()))
	if filter_text.is_empty():
		apply_collapse_visibility()
	else:
		filter(filter_text)


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
		if not row.childrenTags.is_empty():
			row._collapse_btn.text = "▼"
			row._collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP
			row.updateIndent()


func _consume_pending_scroll(target) -> void:
	if target == null:
		return
	await _owner.get_tree().process_frame
	scroll_to_sprite(target)
