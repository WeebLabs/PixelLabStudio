extends Node

signal persistence_error(message: String)

const JsonStore = preload("res://autoload/persistence/json_file_store.gd")
const Settings = preload("res://autoload/persistence/settings_schema.gd")
const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")

const SETTINGS_MAX_BYTES := 4 * 1024 * 1024
const ISOLATED_SESSION_FLAGS := ["--release-smoke", "--avatar-integration-test"]

var data: Dictionary = {}
var settings: Dictionary = Settings.defaults()
var settingsPath := "user://settings.pngtp"
var last_error := ""
var _persist_settings_on_exit := true


func _ready() -> void:
	if is_isolated_session():
		begin_isolated_session()
	else:
		load_settings(settingsPath)


func _exit_tree() -> void:
	if _persist_settings_on_exit:
		write_settings(settingsPath)


func begin_isolated_session() -> void:
	## Automated production-scene launches must not read from or write to the
	## developer's real settings. Saving is the first stateful autoload, so this
	## runs before Global or any scene controller can consume persisted state.
	settings = Settings.defaults()
	last_error = ""
	_persist_settings_on_exit = false


func is_isolated_session() -> bool:
	var arguments := OS.get_cmdline_user_args()
	for flag in ISOLATED_SESSION_FLAGS:
		if arguments.has(flag):
			return true
	return false


func load_settings(path: String = settingsPath) -> bool:
	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"):
		settings = Settings.defaults()
		last_error = ""
		return true
	var read_result := JsonStore.read_document(path, TYPE_DICTIONARY, SETTINGS_MAX_BYTES)
	if not read_result["ok"]:
		_record_error("Could not load settings: %s" % read_result["error"])
		return false
	var schema_result := Settings.normalize(read_result["value"])
	if not schema_result["ok"]:
		_record_error("Could not load settings: %s" % schema_result["error"])
		return false
	settings = schema_result["value"]
	last_error = ""
	if read_result.has("warning"):
		push_warning(read_result["warning"])
	return true


func read_save(path: String) -> Variant:
	var raw_value: Variant
	if path == "default":
		raw_value = DefaultAvatarData.data
	else:
		var read_result := JsonStore.read_document(path)
		if not read_result["ok"]:
			_record_error("Could not load avatar: %s" % read_result["error"])
			return null
		raw_value = read_result["value"]
		if read_result.has("warning"):
			push_warning(read_result["warning"])

	var schema_result := AvatarSave.normalize(raw_value)
	if not schema_result["ok"]:
		_record_error("Could not load avatar: %s" % schema_result["error"])
		return null
	last_error = ""
	return schema_result["value"]


func write_save(path: String) -> bool:
	var schema_result := AvatarSave.normalize(data)
	if not schema_result["ok"]:
		_record_error("Could not save avatar: %s" % schema_result["error"])
		return false
	var normalized_data: Dictionary = schema_result["value"]
	var write_result := JsonStore.write_document_atomic(path, normalized_data)
	if not write_result["ok"]:
		_record_error("Could not save avatar: %s" % write_result["error"])
		return false
	data = normalized_data
	last_error = ""
	return true


func write_settings(path: String = settingsPath) -> bool:
	var schema_result := Settings.normalize(settings)
	if not schema_result["ok"]:
		_record_error("Could not save settings: %s" % schema_result["error"])
		return false
	var normalized_settings: Dictionary = schema_result["value"]
	var write_result := JsonStore.write_document_atomic(path, normalized_settings)
	if not write_result["ok"]:
		_record_error("Could not save settings: %s" % write_result["error"])
		return false
	settings = normalized_settings
	last_error = ""
	return true





func _record_error(message: String) -> void:
	last_error = message
	push_warning(message)
	persistence_error.emit(message)
