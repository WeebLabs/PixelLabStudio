class_name SpriteState
extends RefCounted

const ValueCodec = preload("res://autoload/persistence/value_codec.gd")

# Save-file keys are intentionally kept separate from runtime property names.
# This table is the single compatibility map used by manual saves, avatar
# loads, undo snapshots/restores, and sprite duplication.
const SIMPLE_FIELDS := {
	"zindex": "z",
	"drag": "dragSpeed",
	"xFrq": "xFrq",
	"xAmp": "xAmp",
	"yFrq": "yFrq",
	"yAmp": "yAmp",
	"rotDrag": "rdragStr",
	"showTalk": "showOnTalk",
	"showBlink": "showOnBlink",
	"rLimitMin": "rLimitMin",
	"rLimitMax": "rLimitMax",
	"stretchAmount": "stretchAmount",
	"ignoreBounce": "ignoreBounce",
	"staticElement": "staticElement",
	"frames": "frames",
	"animSpeed": "animSpeed",
	"clipped": "clipped",
	"toggle": "toggle",
	"eyeTrack": "eyeTrack",
	"eyeTrackDistance": "eyeTrackDistance",
	"eyeTrackSpeed": "eyeTrackSpeed",
	"eyeTrackInvert": "eyeTrackInvert",
	"eyeTrackMode": "eyeTrackMode",
	"eyeTrackTargetId": "eyeTrackTargetId",
	"eyeTrackType": "eyeTrackType",
	"eyeTrackForward": "eyeTrackForward",
	"ndiRefLayer": "ndiRefLayer",
	"wiggleEnabled": "wiggleEnabled",
	"wiggleThickness": "wiggleThickness",
	"wiggleSegments": "wiggleSegments",
	"wiggleStiffness": "wiggleStiffness",
	"wiggleDamping": "wiggleDamping",
	"wiggleWeight": "wiggleWeight",
	"wiggleMaxBend": "wiggleMaxBend",
	"wiggleBendFocus": "wiggleBendFocus",
	"wiggleShapeReturn": "wiggleShapeReturn",
	"wiggleWagEnabled": "wiggleWagEnabled",
	"wiggleWagAmount": "wiggleWagAmount",
	"wiggleWagSpeed": "wiggleWagSpeed",
	"wiggleReactivity": "wiggleReactivity",
	"wiggleMotionIntensity": "wiggleMotionIntensity",
	"wiggleChildrenFollow": "wiggleChildrenFollow",
	"blendMode": "blendMode",
	"opacity": "opacity",
	"normalPath": "normalPath",
}

const STRUCTURED_FIELDS := {
	"costumeLayers": "costumeLayers",
	"wigglePath": "wigglePath",
	"wigglePathWidths": "wigglePathWidths",
	"animClips": "animClips",
}


static func capture_properties(sprite: Object, serialize_structured: bool) -> Dictionary:
	var data := {
		"type": "sprite",
		"path": sprite.get("path"),
		"identification": sprite.get("id"),
		"parentId": sprite.get("parentId"),
		"pos": var_to_str(sprite.get("position")),
		"offset": var_to_str(sprite.get("offset")),
	}
	for save_key in SIMPLE_FIELDS:
		data[save_key] = sprite.get(SIMPLE_FIELDS[save_key])
	for save_key in STRUCTURED_FIELDS:
		data[save_key] = encode_structured(save_key, sprite.get(STRUCTURED_FIELDS[save_key]), serialize_structured)
	return data


static func capture_save(sprite: Object) -> Dictionary:
	var data := capture_properties(sprite, true)
	data["_image_ref"] = sprite.get("imageData")
	var normal_image: Variant = sprite.get("normalImageData")
	if normal_image != null:
		data["_normal_image_ref"] = normal_image
	return data


static func capture_snapshot(sprite: Object, image: Image, normal_image: Image = null) -> Dictionary:
	var data := capture_properties(sprite, false)
	data["imageData"] = image
	if normal_image != null:
		data["normalImageData"] = normal_image
	return data


static func apply_before_ready(sprite: Object, data: Dictionary) -> void:
	sprite.set("path", data.get("path", ""))
	sprite.set("id", data.get("identification", 0))
	sprite.set("parentId", data.get("parentId"))
	_apply_value_fields(sprite, data)


static func _apply_value_fields(sprite: Object, data: Dictionary) -> void:
	sprite.set("offset", ValueCodec.vector2_value(data.get("offset"), Vector2.ZERO))
	for save_key in SIMPLE_FIELDS:
		if data.has(save_key):
			sprite.set(SIMPLE_FIELDS[save_key], clone_value(data[save_key]))
	for save_key in STRUCTURED_FIELDS:
		if data.has(save_key):
			sprite.set(STRUCTURED_FIELDS[save_key], decode_structured(save_key, data[save_key]))


static func apply_existing(sprite: Object, data: Dictionary) -> void:
	var previous_frames := int(sprite.get("frames"))
	_apply_value_fields(sprite, data)
	sprite.set("position", ValueCodec.vector2_value(data.get("pos"), Vector2.ZERO))
	sprite.get("sprite").offset = sprite.get("offset")
	sprite.get("grabArea").position = (sprite.get("size") * -0.5) + sprite.get("offset")
	sprite.call("setZIndex")
	if int(sprite.get("frames")) != previous_frames:
		sprite.call("changeFrames")
	sprite.call("setClip", bool(sprite.get("clipped")))
	sprite.call("setWiggle", bool(sprite.get("wiggleEnabled")))
	sprite.call("applyBlendMode")

	var normal_image: Variant = data.get("normalImageData")
	if normal_image is Image:
		if sprite.get("normalImageData") != normal_image:
			sprite.call("setNormalMap", normal_image, data.get("normalPath", ""))
	elif sprite.call("hasNormalMap"):
		sprite.call("clearNormalMap")


static func prepare_snapshot_images(sprite: Object, data: Dictionary) -> void:
	if data.get("imageData") is Image:
		sprite.set("loadedImage", data["imageData"])
	if data.get("normalImageData") is Image:
		sprite.set("loadedNormalImage", data["normalImageData"])
		sprite.set("normalPath", data.get("normalPath", ""))


static func copy_for_duplicate(source: Object, target: Object) -> void:
	target.set("path", source.get("path"))
	target.set("offset", source.get("offset"))
	for property_name in SIMPLE_FIELDS.values():
		target.set(property_name, clone_value(source.get(property_name)))
	for property_name in STRUCTURED_FIELDS.values():
		target.set(property_name, clone_value(source.get(property_name)))
	var source_image: Image = source.get("imageData")
	if source_image != null:
		target.set("loadedImage", source_image.duplicate())
	var source_normal: Image = source.get("normalImageData")
	if source_normal != null:
		target.set("loadedNormalImage", source_normal.duplicate())
		target.set("normalPath", source.get("normalPath"))


static func encode_structured(_save_key: String, value: Variant, serialize: bool) -> Variant:
	var cloned: Variant = clone_value(value)
	if serialize:
		return var_to_str(cloned)
	return cloned


static func decode_structured(save_key: String, value: Variant) -> Variant:
	match save_key:
		"costumeLayers":
			return normalize_costume_layers(ValueCodec.array_value(value, []))
		"wigglePath":
			return ValueCodec.packed_vector2_array_value(value)
		"wigglePathWidths":
			return ValueCodec.packed_float32_array_value(value)
		"animClips":
			return ValueCodec.array_value(value, []).duplicate(true)
	return clone_value(value)


static func normalize_costume_layers(value: Array) -> Array:
	var result := value.duplicate()
	if result.size() > 10:
		result.resize(10)
	while result.size() < 10:
		result.append(1)
	return result


static func clone_value(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	if value is PackedVector2Array or value is PackedFloat32Array:
		return value.duplicate()
	return value


static func persistent_keys() -> Array[String]:
	var keys: Array[String] = ["type", "path", "identification", "parentId", "pos", "offset"]
	for key in SIMPLE_FIELDS:
		keys.append(key)
	for key in STRUCTURED_FIELDS:
		keys.append(key)
	return keys
