extends Node

signal persistence_error(message: String)

const JsonStore = preload("res://autoload/persistence/json_file_store.gd")
const Settings = preload("res://autoload/persistence/settings_schema.gd")
const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")

const SETTINGS_MAX_BYTES := 4 * 1024 * 1024

var key := "creature"
var data: Dictionary = {}
var settings: Dictionary = Settings.defaults()
var settingsPath := "user://settings.pngtp"
var last_error := ""


func _ready() -> void:
	load_settings(settingsPath)


func _exit_tree() -> void:
	write_settings(settingsPath)


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
	elif OS.has_feature("web"):
		var script := "window.localStorage.getItem(%s);" % JSON.stringify(key)
		var json_text: Variant = JavaScriptBridge.eval(script)
		if not json_text is String or String(json_text).is_empty():
			_record_error("No browser avatar save was found.")
			return null
		var parser := JSON.new()
		var parse_error := parser.parse(json_text)
		if parse_error != OK:
			_record_error("Invalid avatar JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
			return null
		raw_value = parser.data
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
	if OS.has_feature("web"):
		var script := "window.localStorage.setItem(%s, %s);" % [JSON.stringify(key), JSON.stringify(JSON.stringify(normalized_data))]
		JavaScriptBridge.eval(script)
		data = normalized_data
		last_error = ""
		return true
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


func clearSave() -> bool:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.localStorage.removeItem(%s);" % JSON.stringify(key))
	else:
		var save_path := "user://%s.save" % key
		if FileAccess.file_exists(save_path):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
			if remove_error != OK:
				_record_error("Could not remove the browser-compatible avatar save: %s" % error_string(remove_error))
				return false
	data = {}
	last_error = ""
	return true


func open_site(url: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s);" % JSON.stringify(url))
	else:
		print("Could not open site %s without a web build" % url)


func switchToSite(url: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, \"_parent\");" % JSON.stringify(url))
	else:
		print("Could not switch to site %s without a web build" % url)


func _record_error(message: String) -> void:
	last_error = message
	push_warning(message)
	persistence_error.emit(message)
