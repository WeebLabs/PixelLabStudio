extends RefCounted

# Pure key/device decoding. Every guard that decides whether a key press turns
# into a command lives here as data, so the rules are stated once and can be
# tested without an engine, a scene, or a device.
#
# Callers hand in a snapshot (which actions fired, which keys arrived, what the
# application guards currently are) and get back the ordered commands to run.
# Nothing here polls Input, touches the scene, or mutates state.

# Foreground actions polled each frame. Guards:
#   selection    — needs a held layer
#   edit_mode    — edit page only
#   control      — the control modifier must be held
#   text_focus   — suppressed while a text field has focus
#   file_dialog  — suppressed while a native file dialog is open
const FOREGROUND := {
	"zDown": {
		"command": "layer_depth_down",
		"selection": true, "text_focus": true,
	},
	"zUp": {
		"command": "layer_depth_up",
		"selection": true, "text_focus": true,
	},
	"unlink": {
		"command": "unlink_layer",
		"text_focus": true, "file_dialog": true,
	},
	"refresh": {
		"command": "refresh_avatar",
		"text_focus": true, "file_dialog": true,
	},
	"saveImages": {
		"command": "save_images",
		"control": true, "text_focus": true, "file_dialog": true,
	},
	"undo": {
		"command": "undo",
		"control": true, "text_focus": true, "file_dialog": true,
	},
	"redo": {
		"command": "redo",
		"control": true, "text_focus": true, "file_dialog": true,
	},
	"screenshot": {
		"command": "screenshot_press",
		"control": true, "text_focus": true, "file_dialog": true,
	},
	"reparent": {
		"command": "toggle_reparent_mode",
		"selection": true, "edit_mode": true, "text_focus": true,
	},
}

# Deterministic dispatch order. Dictionary iteration order is insertion order in
# GDScript, but naming the order explicitly keeps it independent of edits above.
const FOREGROUND_ORDER := [
	"zDown", "zUp", "reparent", "unlink", "refresh",
	"saveImages", "undo", "redo", "screenshot",
]


# `fired` maps action name -> whether it was just pressed this frame.
# `guards` keys: has_selection, edit_mode, control_held, text_focus, file_dialog_open.
static func decode_foreground(fired: Dictionary, guards: Dictionary) -> Array:
	var commands: Array = []
	for action in FOREGROUND_ORDER:
		if not fired.get(action, false):
			continue
		if _blocked(FOREGROUND[action], guards):
			continue
		commands.append(FOREGROUND[action]["command"])
	return commands


static func _blocked(rule: Dictionary, guards: Dictionary) -> bool:
	if rule.get("selection", false) and not guards.get("has_selection", false):
		return true
	if rule.get("edit_mode", false) and not guards.get("edit_mode", false):
		return true
	if rule.get("control", false) and not guards.get("control_held", false):
		return true
	if rule.get("text_focus", false) and guards.get("text_focus", false):
		return true
	if rule.get("file_dialog", false) and guards.get("file_dialog_open", false):
		return true
	return false


# Background key capture (the OS-level hook that keeps working while the window
# is unfocused). One decoder covers all four things a background key can mean.
#
# `keys` are keycode strings. `guards` keys:
#   z_editor_active, file_dialog_open, text_focus,
#   awaiting_animation_bind, awaiting_costume_index (-1 when not binding),
#   costume_keys (Array of bound key strings), settings_has_mouse.
#
# Returns an ordered list of {"command": ..., ...} dictionaries.
static func decode_background(keys: Array, guards: Dictionary) -> Array:
	var commands: Array = []
	if guards.get("z_editor_active", false) or guards.get("file_dialog_open", false):
		return commands
	if keys.is_empty():
		return [{"command": "capture_emptied"}]

	# An armed animation bind swallows the key: it is a binding, not a trigger.
	if guards.get("awaiting_animation_bind", false):
		return [{"command": "bind_animation_key", "key": keys[0]}]

	var awaiting_costume: int = int(guards.get("awaiting_costume_index", -1))
	if awaiting_costume >= 0:
		# Mouse button 1 is not a usable costume key unless the settings page
		# has explicitly opted into mouse capture.
		if keys[0] == "Keycode1" and not guards.get("settings_has_mouse", false):
			return [{"command": "capture_rejected"}]
		commands.append({
			"command": "bind_costume_key", "index": awaiting_costume, "key": keys[0],
		})

	var costume_keys: Array = guards.get("costume_keys", [])
	for key in keys:
		var index: int = costume_keys.find(key)
		if index >= 0:
			commands.append({"command": "change_costume", "costume": index + 1})

	# Animation triggers are suppressed while binding a costume key or typing.
	if awaiting_costume < 0 and not guards.get("text_focus", false):
		for key in keys:
			commands.append({"command": "trigger_animation_key", "key": key})

	return commands


# The visibility-toggle capture path: a separate background hook that only ever
# arms or reports a binding.
static func decode_visibility_capture(keys: Array, guards: Dictionary) -> Dictionary:
	if guards.get("z_editor_active", false) or guards.get("file_dialog_open", false):
		return {"command": "ignore"}
	if keys.is_empty():
		return {"command": "visibility_capture_armed"}
	return {"command": "visibility_keys_captured", "keys": keys}


# Stream Deck (and any other device sending a costume id as a string).
static func decode_device_costume(costume_id: String, costume_count: int = 10) -> Dictionary:
	if not costume_id.is_valid_int():
		return {"command": "ignore"}
	var requested := costume_id.to_int()
	if requested < 1 or requested > costume_count:
		return {"command": "ignore"}
	return {"command": "change_costume", "costume": requested}
