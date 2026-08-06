class_name StreamDeckProtocol
extends RefCounted

const KEY_UP := "keyUp"
const KEY_DOWN := "keyDown"
const ALLOWED_EVENTS := [KEY_UP, KEY_DOWN]
const ALLOWED_ACTIONS := [
	"games.boyne.godot.emitsignal",
	"games.boyne.godot.switchscene",
	"games.boyne.godot.reloadscene",
]

static func valid_port(value: Variant) -> bool:
	var text := str(value)
	if not text.is_valid_int():
		return false
	var port := int(text)
	return port >= 1 and port <= 65535

static func websocket_url(value: Variant) -> String:
	var port := int(str(value)) if valid_port(value) else 8080
	return "ws://127.0.0.1:%d/ws" % port

static func normalize_packet(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {}
	var packet: Dictionary = value
	var event := str(packet.get("event", ""))
	var action := str(packet.get("action", ""))
	if event not in ALLOWED_EVENTS or action not in ALLOWED_ACTIONS:
		return {}
	var payload: Variant = packet.get("payload")
	if not payload is Dictionary:
		return {}
	var settings: Variant = payload.get("settings")
	if not settings is Dictionary:
		return {}
	return {"event": event, "action": action, "settings": settings}

static func safe_scene_path(value: Variant) -> String:
	var path := str(value).strip_edges()
	if not path.begins_with("res://"):
		return ""
	if path.get_extension().to_lower() not in ["tscn", "scn"]:
		return ""
	return path
