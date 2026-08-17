extends RefCounted

## Pure name/shape matching for PSD and folder replacement reviews. Keeping the
## decision separate from dialogs and scene mutation makes duplicate names,
## unmatched layers, and orphan calculation deterministic and testable.


static func sprite_name(sprite_path: String) -> String:
	if sprite_path.begins_with("psd://"):
		return sprite_path.substr(6)
	if sprite_path.begins_with("animated://"):
		return sprite_path.substr(11)
	var filename := sprite_path.get_file()
	var extension := filename.get_extension()
	if not extension.is_empty():
		filename = filename.substr(0, filename.length() - extension.length() - 1)
	return filename


static func items_from_psd(layers: Array, canvas_size: Vector2) -> Array:
	var by_name := {}
	for layer in layers:
		if layer.width <= 0 or layer.height <= 0 or layer.image == null:
			continue
		by_name[String(layer.name).to_lower()] = layer
	var items: Array = []
	var canvas_center := canvas_size * 0.5
	for normalized_name in by_name:
		var layer = by_name[normalized_name]
		var layer_center := Vector2(
			(layer.left + layer.right) * 0.5,
			(layer.top + layer.bottom) * 0.5,
		)
		items.append({"name": layer.name, "image": layer.image, "position": layer_center - canvas_center})
	return items


static func match_items(sprites: Array, items: Array) -> Dictionary:
	var sprites_by_name := {}
	for sprite in sprites:
		var normalized_name := sprite_name(sprite.path).to_lower()
		if not sprites_by_name.has(normalized_name):
			sprites_by_name[normalized_name] = []
		sprites_by_name[normalized_name].append(sprite)

	var matched: Array = []
	var matched_sprite_ids := {}
	var matched_item_names := {}
	for item in items:
		var normalized_name := String(item["name"]).to_lower()
		if not sprites_by_name.has(normalized_name):
			continue
		for sprite in sprites_by_name[normalized_name]:
			matched.append({"sprite": sprite, "name": item["name"], "image": item["image"]})
			matched_sprite_ids[sprite.get_instance_id()] = true
		matched_item_names[normalized_name] = true

	var new_items: Array = []
	for item in items:
		if not matched_item_names.has(String(item["name"]).to_lower()):
			new_items.append(item)
	var orphaned: Array = []
	for sprite in sprites:
		if not matched_sprite_ids.has(sprite.get_instance_id()):
			orphaned.append(sprite)
	return {"matched": matched, "new_items": new_items, "orphaned": orphaned}
