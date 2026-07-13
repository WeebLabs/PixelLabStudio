class_name HotkeyBinding
extends RefCounted

const MODIFIER_ORDER: Array[String] = ["Ctrl", "Alt", "Shift", "Meta"]


static func from_pressed(pressed_keys: Array, newly_pressed_keys: Array) -> String:
	var primary_keys: Array[String] = []
	for key in newly_pressed_keys:
		var normalized := normalize_key_name(str(key))
		if normalized != "" and not is_modifier(normalized) and not primary_keys.has(normalized):
			primary_keys.append(normalized)

	if primary_keys.size() != 1:
		return ""

	var parts: Array[String] = []
	var normalized_pressed := _normalized_key_set(pressed_keys)
	for modifier in MODIFIER_ORDER:
		if normalized_pressed.has(modifier):
			parts.append(modifier)
	parts.append(primary_keys[0])
	return "+".join(parts)


static func canonicalize(binding: String) -> String:
	var raw := binding.strip_edges()
	if raw == "" or raw.to_lower() == "null":
		return ""

	var modifiers: Dictionary = {}
	var primary_keys: Array[String] = []
	for part in raw.split("+", false):
		var normalized := normalize_key_name(part)
		if normalized == "":
			continue
		if is_modifier(normalized):
			modifiers[normalized] = true
		elif not primary_keys.has(normalized):
			primary_keys.append(normalized)

	if primary_keys.size() != 1:
		return ""

	var parts: Array[String] = []
	for modifier in MODIFIER_ORDER:
		if modifiers.has(modifier):
			parts.append(modifier)
	parts.append(primary_keys[0])
	return "+".join(parts)


static func is_active(binding: String, pressed_keys: Array) -> bool:
	var canonical := canonicalize(binding)
	if canonical == "":
		return false

	var parts := canonical.split("+", false)
	var primary := parts[parts.size() - 1]
	var required_modifiers: Dictionary = {}
	for i in range(parts.size() - 1):
		required_modifiers[parts[i]] = true

	var pressed := _normalized_key_set(pressed_keys)
	if not pressed.has(primary):
		return false

	for modifier in MODIFIER_ORDER:
		if pressed.has(modifier) != required_modifiers.has(modifier):
			return false
	return true


static func normalize_key_name(key: String) -> String:
	var trimmed := key.strip_edges()
	var compact := trimmed.to_lower().replace(" ", "").replace("_", "")
	match compact:
		"ctrl", "control", "lctrl", "rctrl", "leftctrl", "rightctrl", "leftcontrol", "rightcontrol":
			return "Ctrl"
		"alt", "lalt", "ralt", "leftalt", "rightalt":
			return "Alt"
		"shift", "lshift", "rshift", "leftshift", "rightshift":
			return "Shift"
		"meta", "lmeta", "rmeta", "leftmeta", "rightmeta", "super", "win", "windows", "command", "cmd":
			return "Meta"
		_:
			return trimmed


static func is_modifier(key: String) -> bool:
	return MODIFIER_ORDER.has(normalize_key_name(key))


static func _normalized_key_set(keys: Array) -> Dictionary:
	var normalized: Dictionary = {}
	for key in keys:
		var name := normalize_key_name(str(key))
		if name != "":
			normalized[name] = true
	return normalized
