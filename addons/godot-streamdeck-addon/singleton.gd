extends Node

const Protocol = preload("res://addons/godot-streamdeck-addon/protocol.gd")

const ButtonAction = {
	EMIT_SIGNAL = "games.boyne.godot.emitsignal",
	SWITCH_SCENE = "games.boyne.godot.switchscene",
	RELOAD_SCENE = "games.boyne.godot.reloadscene",
}

const ButtonEvent = {
	KEY_UP = "keyUp",
	KEY_DOWN = "keyDown",
}

signal on_key_up
signal on_key_down

const PLUGIN_NAME := "games.boyne.godot.sdPlugin"

var _socket := WebSocketPeer.new()
var _config := ConfigFile.new()

func _ready() -> void:
	set_process(false)
	if not bool(Saving.settings.get("useStreamDeck", false)):
		return
	if not _load_config(_get_config_path()):
		push_warning("Stream Deck bridge configuration was not found or is invalid.")
		return
	var connect_error := _socket.connect_to_url(_get_websocket_url())
	if connect_error != OK:
		push_warning("Could not connect to the Stream Deck bridge (error %d)." % connect_error)
		return
	set_process(true)

func _exit_tree() -> void:
	set_process(false)
	if _socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_socket.close(1000, "Application shutdown")
		_socket.poll()

func _process(_delta: float) -> void:
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while _socket.get_available_packet_count() > 0:
				_handle_packet(_socket.get_packet())
		WebSocketPeer.STATE_CLOSED:
			set_process(false)

func _handle_packet(raw_packet: PackedByteArray) -> void:
	var packet := Protocol.normalize_packet(JSON.parse_string(raw_packet.get_string_from_utf8()))
	if packet.is_empty():
		return
	var settings: Dictionary = packet["settings"]
	match packet["action"]:
		ButtonAction.EMIT_SIGNAL:
			var signal_input := str(settings.get("signalInput", ""))
			if packet["event"] == ButtonEvent.KEY_UP:
				on_key_up.emit(signal_input)
			else:
				on_key_down.emit(signal_input)
		ButtonAction.SWITCH_SCENE:
			var scene_path := Protocol.safe_scene_path(settings.get("scenePath", ""))
			if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
				get_tree().change_scene_to_file(scene_path)
		ButtonAction.RELOAD_SCENE:
			get_tree().reload_current_scene()

func _get_websocket_url() -> String:
	return Protocol.websocket_url(_config.get_value("bridge", "port", 8080))

func _get_config_path() -> String:
	match OS.get_name():
		"Windows":
			return "%s/Elgato/StreamDeck/Plugins/%s/plugin.ini" % [OS.get_config_dir(), PLUGIN_NAME]
		"macOS":
			return "%s/com.elgato.StreamDeck/Plugins/%s/plugin.ini" % [OS.get_config_dir(), PLUGIN_NAME]
	return ""

func _load_config(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	if _config.load(path) != OK:
		return false
	return Protocol.valid_port(_config.get_value("bridge", "port", 8080))
