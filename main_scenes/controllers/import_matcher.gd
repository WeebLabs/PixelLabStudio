extends RefCounted

## Pure name/shape matching for PSD and folder replacement reviews. Keeping the
## decision separate from dialogs and scene mutation makes duplicate names,
## unmatched layers, and orphan calculation deterministic and testable.


# Normal maps pair onto a diffuse layer by name suffix rather than importing as
# layers of their own. The import dialog hides them the same way; both paths ask
# here so the rule has one definition.
const NORMAL_SUFFIX := "_nrml"


static func is_normal_layer(layer_name: String) -> bool:
	return layer_name.to_lower().ends_with(NORMAL_SUFFIX)


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
		# Without this a replace PSD's normal maps arrive as ordinary layers and
		# are added to the rig as visible artwork.
		if is_normal_layer(String(layer.name)):
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


# The name the user gave this layer, or "" when it still carries the one it was
# imported under. Sprites that predate the field, and the test doubles, report
# nothing here.
static func renamed_match_name(sprite) -> String:
	var renamed: Variant = sprite.get("layerName")
	if renamed is String:
		return (renamed as String).strip_edges().to_lower()
	return ""


static func source_match_name(sprite) -> String:
	return sprite_name(sprite.path).to_lower()


# Matching runs in two rounds: every layer's own name first, then the name it was
# imported under. Renaming a layer therefore costs it nothing, since the second
# round still finds it by its source name, and renaming a layer to a source
# layer's new name re-points it there, which is the only way to follow an artist
# who renames a layer in the PSD. A layer claimed in the first round is not
# offered again in the second.
static func match_items(sprites: Array, items: Array) -> Dictionary:
	var by_renamed := {}
	var by_source := {}
	for sprite in sprites:
		var renamed := renamed_match_name(sprite)
		if not renamed.is_empty():
			if not by_renamed.has(renamed):
				by_renamed[renamed] = []
			by_renamed[renamed].append(sprite)
		var original := source_match_name(sprite)
		if not by_source.has(original):
			by_source[original] = []
		by_source[original].append(sprite)

	var matched: Array = []
	var matched_sprite_ids := {}
	var matched_item_names := {}
	for round_names in [by_renamed, by_source]:
		for item in items:
			var normalized_name := String(item["name"]).to_lower()
			if not round_names.has(normalized_name):
				continue
			for sprite in round_names[normalized_name]:
				if matched_sprite_ids.has(sprite.get_instance_id()):
					continue
				matched.append({
					"sprite": sprite,
					"name": item["name"],
					"image": item["image"],
					# Carried for legacy full-canvas rigs, where the replacement's
					# placement inside the source canvas is what re-anchors the layer.
					"position": item.get("position", Vector2.ZERO),
				})
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
