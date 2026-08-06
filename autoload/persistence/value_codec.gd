class_name PersistenceValueCodec
extends RefCounted

## Narrow conversions used at persistence boundaries. These helpers never
## return an unexpected Variant type, even when a save file is malformed.

static func bool_value(value: Variant, fallback: bool) -> bool:
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0
	if value is String:
		var normalized := String(value).strip_edges().to_lower()
		if normalized == "true" or normalized == "1":
			return true
		if normalized == "false" or normalized == "0":
			return false
	return fallback


static func int_value(value: Variant, fallback: int, minimum: int = -2147483648, maximum: int = 2147483647) -> int:
	var converted := fallback
	if value is int or value is float:
		converted = int(value)
	elif value is String and String(value).is_valid_int():
		converted = String(value).to_int()
	return clampi(converted, minimum, maximum)


static func float_value(value: Variant, fallback: float, minimum: float = -INF, maximum: float = INF) -> float:
	var converted := fallback
	if value is int or value is float:
		converted = float(value)
	elif value is String and String(value).is_valid_float():
		converted = String(value).to_float()
	if not is_finite(converted):
		converted = fallback
	return clampf(converted, minimum, maximum)


static func string_value(value: Variant, fallback: String = "", maximum_length: int = 4096) -> String:
	if not value is String:
		return fallback
	return String(value).substr(0, maximum_length)


static func vector2_value(value: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() == 2:
		return Vector2(
			float_value(value[0], fallback.x),
			float_value(value[1], fallback.y)
		)
	if value is String:
		var text := String(value).strip_edges()
		if (text.begins_with("Vector2(") or text.begins_with("Vector2i(")) and text.ends_with(")"):
			var parsed: Variant = str_to_var(text)
			if parsed is Vector2:
				return parsed
			if parsed is Vector2i:
				return Vector2(parsed)
	return fallback


static func vector2i_value(value: Variant, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if value is Vector2i:
		return value
	var parsed := vector2_value(value, Vector2(fallback))
	return Vector2i(roundi(parsed.x), roundi(parsed.y))


static func color_value(value: Variant, fallback: Color = Color.TRANSPARENT) -> Color:
	if value is Color:
		return value
	if value is Array and value.size() in [3, 4]:
		return Color(
			float_value(value[0], fallback.r, 0.0, 1.0),
			float_value(value[1], fallback.g, 0.0, 1.0),
			float_value(value[2], fallback.b, 0.0, 1.0),
			float_value(value[3], fallback.a, 0.0, 1.0) if value.size() == 4 else fallback.a
		)
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("Color(") and text.ends_with(")"):
			var parsed: Variant = str_to_var(text)
			if parsed is Color:
				return parsed
	return fallback


static func array_value(value: Variant, fallback: Array = []) -> Array:
	if value is Array:
		return value.duplicate(true)
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("[") and text.ends_with("]"):
			var parsed: Variant = str_to_var(text)
			if parsed is Array:
				return parsed
	return fallback.duplicate(true)


static func packed_vector2_array_value(value: Variant, fallback: PackedVector2Array = PackedVector2Array()) -> PackedVector2Array:
	if value is PackedVector2Array:
		return value
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("PackedVector2Array(") and text.ends_with(")"):
			var parsed: Variant = str_to_var(text)
			if parsed is PackedVector2Array:
				return parsed
	return fallback


static func packed_float32_array_value(value: Variant, fallback: PackedFloat32Array = PackedFloat32Array()) -> PackedFloat32Array:
	if value is PackedFloat32Array:
		return value
	if value is String:
		var text := String(value).strip_edges()
		if text.begins_with("PackedFloat32Array(") and text.ends_with(")"):
			var parsed: Variant = str_to_var(text)
			if parsed is PackedFloat32Array:
				return parsed
	return fallback
