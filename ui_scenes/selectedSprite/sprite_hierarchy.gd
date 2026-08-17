extends RefCounted


static func direct_children(sprite_nodes: Array, parent_id: Variant) -> Array:
	var result := []
	for sprite in sprite_nodes:
		if is_instance_valid(sprite) and sprite.parentId == parent_id:
			result.append(sprite)
	return result


static func descendants(sprite_nodes: Array, root_id: Variant) -> Array:
	var children_by_parent := {}
	for sprite in sprite_nodes:
		if not is_instance_valid(sprite) or sprite.parentId == null:
			continue
		if not children_by_parent.has(sprite.parentId):
			children_by_parent[sprite.parentId] = []
		children_by_parent[sprite.parentId].append(sprite)
	var result := []
	var visited := {root_id: true}
	var stack: Array = children_by_parent.get(root_id, []).duplicate()
	while not stack.is_empty():
		var current = stack.pop_back()
		if visited.has(current.id):
			continue
		visited[current.id] = true
		result.append(current)
		stack.append_array(children_by_parent.get(current.id, []))
	return result
