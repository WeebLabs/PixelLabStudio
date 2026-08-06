class_name AvatarSaveSchema
extends RefCounted

const ValueCodec = preload("res://autoload/persistence/value_codec.gd")

const CURRENT_VERSION := 1
const MAX_SPRITES := 10000
const MAX_EMBEDDED_IMAGE_CHARS := 384 * 1024 * 1024


static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("Avatar save must be a JSON object.")
	var source: Dictionary = value
	var version := ValueCodec.int_value(source.get("_schemaVersion", 0), 0, 0, 2147483647)
	if version > CURRENT_VERSION:
		return _failure("This avatar uses save schema %d, but this build supports up to %d." % [version, CURRENT_VERSION])

	var result: Dictionary = {}
	var sprite_count := 0
	var identifiers: Dictionary = {}
	for raw_key in source:
		var key := str(raw_key)
		if key.begins_with("_"):
			continue
		var raw_entry: Variant = source[raw_key]
		if not raw_entry is Dictionary:
			return _failure("Avatar entry '%s' must be an object." % key)
		var normalized_entry := _normalize_sprite(raw_entry, key)
		if not normalized_entry["ok"]:
			return normalized_entry
		var entry: Dictionary = normalized_entry["value"]
		var identifier: int = entry["identification"]
		if identifiers.has(identifier):
			return _failure("Avatar entries '%s' and '%s' use the same identification value." % [identifiers[identifier], key])
		identifiers[identifier] = key
		result[key] = entry
		sprite_count += 1
		if sprite_count > MAX_SPRITES:
			return _failure("Avatar contains more than %d sprite layers." % MAX_SPRITES)

	if sprite_count == 0:
		return _failure("Avatar contains no sprite layers.")
	var hierarchy_error := _validate_hierarchy(result)
	if not hierarchy_error.is_empty():
		return _failure(hierarchy_error)

	result["_schemaVersion"] = CURRENT_VERSION
	result["_eyeTrackingGloballyEnabled"] = ValueCodec.bool_value(source.get("_eyeTrackingGloballyEnabled", true), true)
	if source.get("_light") is Dictionary:
		result["_light"] = _normalize_light(source["_light"])
	if source.has("_ndiCropRect"):
		var crop: Variant = _normalize_crop(source["_ndiCropRect"])
		if crop != null:
			result["_ndiCropRect"] = crop
			result["_ndiRulerY"] = crop[3]
	elif source.has("_ndiRulerY"):
		result["_ndiRulerY"] = ValueCodec.float_value(source["_ndiRulerY"], 200.0, -100000.0, 100000.0)

	# Preserve metadata owned by newer optional integrations. Known metadata is
	# overwritten above with its validated representation.
	for raw_key in source:
		var key := str(raw_key)
		if key.begins_with("_") and not result.has(key):
			result[key] = source[raw_key]

	return {
		"ok": true,
		"value": result,
		"error": "",
		"source_version": version,
		"migrated": version != CURRENT_VERSION,
		"sprite_count": sprite_count,
	}


static func _normalize_sprite(value: Dictionary, key: String) -> Dictionary:
	if ValueCodec.string_value(value.get("type", "sprite"), "sprite", 32) != "sprite":
		return _failure("Avatar entry '%s' has an unsupported type." % key)
	var path := ValueCodec.string_value(value.get("path"), "", 32768)
	if path.is_empty():
		return _failure("Avatar entry '%s' has no image path." % key)
	if not value.has("identification") or not _is_integer_compatible(value["identification"]):
		return _failure("Avatar entry '%s' has no valid identification value." % key)
	var identifier := ValueCodec.int_value(value["identification"], 0)

	var entry: Dictionary = value.duplicate(true)
	entry["type"] = "sprite"
	entry["path"] = path
	entry["identification"] = identifier
	entry["parentId"] = null if value.get("parentId") == null else ValueCodec.int_value(value.get("parentId"), 0)
	entry["pos"] = var_to_str(ValueCodec.vector2_value(value.get("pos"), Vector2.ZERO))
	entry["offset"] = var_to_str(ValueCodec.vector2_value(value.get("offset"), Vector2.ZERO))
	entry["zindex"] = ValueCodec.int_value(value.get("zindex"), 0, -4096, 4096)
	entry["drag"] = ValueCodec.float_value(value.get("drag"), 0.0, -10000.0, 10000.0)
	entry["xFrq"] = ValueCodec.float_value(value.get("xFrq"), 0.0, -10000.0, 10000.0)
	entry["xAmp"] = ValueCodec.float_value(value.get("xAmp"), 0.0, -100000.0, 100000.0)
	entry["yFrq"] = ValueCodec.float_value(value.get("yFrq"), 0.0, -10000.0, 10000.0)
	entry["yAmp"] = ValueCodec.float_value(value.get("yAmp"), 0.0, -100000.0, 100000.0)
	entry["rotDrag"] = ValueCodec.float_value(value.get("rotDrag"), 0.0, -10000.0, 10000.0)
	entry["showTalk"] = ValueCodec.int_value(value.get("showTalk"), 0, 0, 2)
	entry["showBlink"] = ValueCodec.int_value(value.get("showBlink"), 0, 0, 2)
	entry["rLimitMin"] = ValueCodec.float_value(value.get("rLimitMin"), -180.0, -36000.0, 36000.0)
	entry["rLimitMax"] = ValueCodec.float_value(value.get("rLimitMax"), 180.0, -36000.0, 36000.0)
	if entry["rLimitMin"] > entry["rLimitMax"]:
		var previous_min: float = entry["rLimitMin"]
		entry["rLimitMin"] = entry["rLimitMax"]
		entry["rLimitMax"] = previous_min
	entry["costumeLayers"] = var_to_str(_normalize_costume_layers(ValueCodec.array_value(value.get("costumeLayers"), [])))
	entry["stretchAmount"] = ValueCodec.float_value(value.get("stretchAmount"), 0.0, -1000.0, 1000.0)
	entry["ignoreBounce"] = ValueCodec.bool_value(value.get("ignoreBounce"), false)
	entry["staticElement"] = ValueCodec.bool_value(value.get("staticElement"), false)
	entry["frames"] = ValueCodec.int_value(value.get("frames"), 1, 1, 100000)
	entry["animSpeed"] = ValueCodec.float_value(value.get("animSpeed"), 0.0, 0.0, 100000.0)
	entry["clipped"] = ValueCodec.bool_value(value.get("clipped"), false)
	entry["toggle"] = ValueCodec.string_value(value.get("toggle"), "null", 256)
	entry["eyeTrack"] = ValueCodec.bool_value(value.get("eyeTrack"), false)
	entry["eyeTrackDistance"] = ValueCodec.float_value(value.get("eyeTrackDistance"), 20.0, -100000.0, 100000.0)
	entry["eyeTrackSpeed"] = ValueCodec.float_value(value.get("eyeTrackSpeed"), 0.15, 0.0, 1000.0)
	entry["eyeTrackInvert"] = ValueCodec.bool_value(value.get("eyeTrackInvert"), false)
	entry["eyeTrackMode"] = ValueCodec.int_value(value.get("eyeTrackMode"), 0, 0, 1)
	entry["eyeTrackTargetId"] = null if value.get("eyeTrackTargetId") == null else ValueCodec.int_value(value.get("eyeTrackTargetId"), 0)
	entry["eyeTrackType"] = ValueCodec.int_value(value.get("eyeTrackType"), 0, 0, 1)
	entry["eyeTrackForward"] = ValueCodec.int_value(value.get("eyeTrackForward"), 0, -1, 1)
	entry["ndiRefLayer"] = ValueCodec.bool_value(value.get("ndiRefLayer"), false)
	entry["wiggleEnabled"] = ValueCodec.bool_value(value.get("wiggleEnabled"), false)
	entry["wigglePath"] = var_to_str(ValueCodec.packed_vector2_array_value(value.get("wigglePath")))
	entry["wigglePathWidths"] = var_to_str(ValueCodec.packed_float32_array_value(value.get("wigglePathWidths")))
	entry["wiggleThickness"] = ValueCodec.float_value(value.get("wiggleThickness"), 1.0, 0.01, 100.0)
	entry["wiggleSegments"] = ValueCodec.int_value(value.get("wiggleSegments"), 12, 2, 256)
	entry["wiggleStiffness"] = ValueCodec.float_value(value.get("wiggleStiffness"), 20.0, 0.0, 10000.0)
	entry["wiggleDamping"] = ValueCodec.float_value(value.get("wiggleDamping"), 5.0, 0.0, 10000.0)
	entry["wiggleWeight"] = ValueCodec.float_value(value.get("wiggleWeight"), 0.0, -10000.0, 10000.0)
	entry["wiggleMaxBend"] = ValueCodec.float_value(value.get("wiggleMaxBend"), 25.0, 0.0, 180.0)
	entry["wiggleBendFocus"] = ValueCodec.float_value(value.get("wiggleBendFocus"), 0.4, 0.0, 1000.0)
	entry["wiggleShapeReturn"] = ValueCodec.float_value(value.get("wiggleShapeReturn"), 0.0, 0.0, 1000.0)
	entry["wiggleWagEnabled"] = ValueCodec.bool_value(value.get("wiggleWagEnabled"), true)
	entry["wiggleWagAmount"] = ValueCodec.float_value(value.get("wiggleWagAmount"), 15.0, -36000.0, 36000.0)
	entry["wiggleWagSpeed"] = ValueCodec.float_value(value.get("wiggleWagSpeed"), 0.12, -1000.0, 1000.0)
	entry["wiggleReactivity"] = ValueCodec.float_value(value.get("wiggleReactivity"), 1.0, 0.0, 1000.0)
	entry["wiggleMotionIntensity"] = ValueCodec.float_value(value.get("wiggleMotionIntensity"), 1.0, 0.0, 1000.0)
	entry["wiggleChildrenFollow"] = ValueCodec.bool_value(value.get("wiggleChildrenFollow"), false)
	entry["blendMode"] = ValueCodec.int_value(value.get("blendMode"), 0, 0, 13)
	entry["opacity"] = ValueCodec.float_value(value.get("opacity"), 1.0, 0.0, 1.0)
	entry["normalPath"] = ValueCodec.string_value(value.get("normalPath"), "", 32768)
	if value.has("animClips"):
		entry["animClips"] = var_to_str(ValueCodec.array_value(value["animClips"], []))

	for image_key in ["imageData", "normalImageData"]:
		if value.has(image_key):
			if not value[image_key] is String:
				return _failure("Avatar entry '%s' has invalid %s." % [key, image_key])
			if String(value[image_key]).length() > MAX_EMBEDDED_IMAGE_CHARS:
				return _failure("Avatar entry '%s' contains an image larger than the supported limit." % key)

	return {"ok": true, "value": entry, "error": ""}


static func _normalize_costume_layers(value: Array) -> Array:
	var result: Array[int] = []
	for index in range(10):
		result.append(ValueCodec.int_value(value[index] if index < value.size() else 1, 1, 0, 2))
	return result


static func _normalize_light(value: Dictionary) -> Dictionary:
	return {
		"pos": var_to_str(ValueCodec.vector2_value(value.get("pos"), Vector2.ZERO)),
		"energy": ValueCodec.float_value(value.get("energy"), 1.0, 0.0, 64.0),
		"color": var_to_str(ValueCodec.color_value(value.get("color"), Color.WHITE)),
		"range": ValueCodec.float_value(value.get("range"), 300.0, 1.0, 100000.0),
		"enabled": ValueCodec.bool_value(value.get("enabled"), true),
	}


static func _validate_hierarchy(sprites: Dictionary) -> String:
	var by_identifier: Dictionary = {}
	for key in sprites:
		var entry: Dictionary = sprites[key]
		by_identifier[entry["identification"]] = entry

	for key in sprites:
		var entry: Dictionary = sprites[key]
		var parent_id: Variant = entry["parentId"]
		if parent_id != null and not by_identifier.has(parent_id):
			entry["parentId"] = null
			continue
		var visited: Dictionary = {}
		var current_id: Variant = entry["identification"]
		while current_id != null and by_identifier.has(current_id):
			if visited.has(current_id):
				return "Avatar hierarchy contains a parent cycle involving sprite %s." % current_id
			visited[current_id] = true
			current_id = by_identifier[current_id]["parentId"]
	return ""


static func _normalize_crop(value: Variant) -> Variant:
	if not value is Array or value.size() != 4:
		return null
	var crop := [
		ValueCodec.float_value(value[0], 0.0, -100000.0, 100000.0),
		ValueCodec.float_value(value[1], 0.0, -100000.0, 100000.0),
		ValueCodec.float_value(value[2], 0.0, -100000.0, 100000.0),
		ValueCodec.float_value(value[3], 0.0, -100000.0, 100000.0),
	]
	if crop[2] - crop[0] < 1.0 or crop[3] - crop[1] < 1.0:
		return null
	return crop


static func _is_integer_compatible(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		return is_finite(value) and value == floorf(value)
	return value is String and String(value).is_valid_int()


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "value": null, "error": message}
