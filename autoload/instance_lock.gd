extends Node

## Single-instance guard and launch-file handoff.
##
## Windows starts a fresh process for every double-clicked .pixlab file. The
## first instance listens on a loopback TCP port (OS-assigned, recorded in
## PORT_FILE). A later instance connects, sends its file path, waits for the
## acknowledgement and terminates itself, all from _init(), before the other
## autoloads or the main scene run, so the duplicate never loads an avatar or
## writes settings over the running instance's on exit.
##
## Must stay FIRST in the [autoload] list for that reason.

signal file_requested(path: String)

const SaveController = preload("res://main_scenes/controllers/save_controller.gd")

# Same list as Saving.ISOLATED_SESSION_FLAGS (test_release_contract keeps them
# equal). Not preloaded from saving.gd: that script names other autoloads, which
# the isolated unit-test workspace does not register.
const ISOLATED_SESSION_FLAGS := ["--release-smoke", "--avatar-integration-test"]
const PORT_FILE := "user://instance.port"
# The handshake guards against a stale port file now owned by another process.
const HELLO := "PIXLAB1"
const ACK := "OK"
const CONNECT_TIMEOUT_MS := 500
const PEER_TIMEOUT_MS := 2000

## Avatar passed on this process's command line ("" if none). The save
## controller loads it at startup in place of the recovery / lastAvatar restore.
var launch_file := ""

var _server: TCPServer = null
var _port := 0
var _peers: Array[Dictionary] = []


func _init() -> void:
	launch_file = find_avatar_arg(OS.get_cmdline_args())
	# Editor runs (F5) must never hand off to, or be blocked by, an installed
	# copy that happens to be open; automated runs stay fully isolated.
	if OS.has_feature("editor") or OS.has_feature("web") or _is_isolated_session():
		return
	if _hand_off_to_running_instance():
		OS.kill(OS.get_process_id())
		return
	_start_server()


static func find_avatar_arg(arguments: PackedStringArray) -> String:
	for argument in arguments:
		if argument.begins_with("-"):
			continue
		if SaveController.is_avatar_path(argument) and FileAccess.file_exists(argument):
			return argument.replace("\\", "/")
	return ""


static func _is_isolated_session() -> bool:
	var arguments := OS.get_cmdline_user_args()
	for flag in ISOLATED_SESSION_FLAGS:
		if arguments.has(flag):
			return true
	return false


func _hand_off_to_running_instance() -> bool:
	if not FileAccess.file_exists(PORT_FILE):
		return false
	var port := FileAccess.get_file_as_string(PORT_FILE).strip_edges().to_int()
	if port <= 0:
		return false
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	var sent := false
	var reply := ""
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		if status == StreamPeerTCP.STATUS_CONNECTED:
			if not sent:
				# An empty path still tells the running instance to come forward.
				peer.put_data((HELLO + " " + launch_file + "\n").to_utf8_buffer())
				sent = true
			var available := peer.get_available_bytes()
			if available > 0:
				reply += peer.get_utf8_string(available)
				if reply.strip_edges() == ACK:
					peer.disconnect_from_host()
					return true
		OS.delay_msec(5)
	peer.disconnect_from_host()
	return false


func _start_server() -> void:
	_server = TCPServer.new()
	if _server.listen(0, "127.0.0.1") != OK:
		_server = null
		return
	_port = _server.get_local_port()
	var file := FileAccess.open(PORT_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(str(_port))
		file.close()


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "buffer": "", "since": Time.get_ticks_msec()})
	for index in range(_peers.size() - 1, -1, -1):
		var entry := _peers[index]
		var peer: StreamPeerTCP = entry["peer"]
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			entry["buffer"] += peer.get_utf8_string(available)
		var newline := String(entry["buffer"]).find("\n")
		if newline != -1:
			var line := String(entry["buffer"]).substr(0, newline)
			if line.begins_with(HELLO):
				peer.put_data((ACK + "\n").to_utf8_buffer())
				_bring_to_front()
				var path := line.substr(HELLO.length()).strip_edges()
				if not path.is_empty():
					file_requested.emit(path.replace("\\", "/"))
			peer.disconnect_from_host()
			_peers.remove_at(index)
		elif peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - int(entry["since"]) > PEER_TIMEOUT_MS:
			peer.disconnect_from_host()
			_peers.remove_at(index)


func _bring_to_front() -> void:
	var window_id := DisplayServer.MAIN_WINDOW_ID
	if DisplayServer.window_get_mode(window_id) == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, window_id)
	DisplayServer.window_move_to_foreground(window_id)


func _exit_tree() -> void:
	if _server == null:
		return
	_server.stop()
	# Only remove the port file while it is still ours; a newer instance may
	# have claimed it after a crash left this one's behind.
	if FileAccess.get_file_as_string(PORT_FILE).strip_edges().to_int() == _port:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PORT_FILE))
