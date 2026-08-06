class_name JsonFileStore
extends RefCounted

## JSON persistence with bounded reads, structured errors, and recoverable
## same-directory writes. A stale .bak is accepted only when the primary file
## is absent or invalid.

const DEFAULT_MAX_BYTES := 512 * 1024 * 1024


static func read_document(path: String, expected_type: int = TYPE_DICTIONARY, maximum_bytes: int = DEFAULT_MAX_BYTES) -> Dictionary:
	if path.is_empty():
		return _failure(ERR_INVALID_PARAMETER, "The file path is empty.")

	var primary := _read_path(path, expected_type, maximum_bytes)
	if primary["ok"]:
		return primary

	var backup_path := path + ".bak"
	if FileAccess.file_exists(backup_path):
		var backup := _read_path(backup_path, expected_type, maximum_bytes)
		if backup["ok"]:
			backup["recovered_from"] = backup_path
			backup["warning"] = "Recovered from the previous complete write because %s" % primary["error"]
			return backup
	return primary


static func write_document_atomic(path: String, value: Variant) -> Dictionary:
	if path.is_empty():
		return _failure(ERR_INVALID_PARAMETER, "The file path is empty.")

	var json := JSON.stringify(value)
	if json.is_empty() and value != "":
		return _failure(ERR_INVALID_DATA, "The value could not be encoded as JSON.")

	var directory_path := path.get_base_dir()
	if not directory_path.is_empty():
		var absolute_directory := ProjectSettings.globalize_path(directory_path)
		var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			return _failure(mkdir_error, "Could not create the destination directory: %s" % error_string(mkdir_error))

	var temporary_path := path + ".tmp"
	var backup_path := path + ".bak"
	_remove_if_present(temporary_path)

	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return _failure(open_error, "Could not open the temporary save file: %s" % error_string(open_error))
	file.store_string(json + "\n")
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		_remove_if_present(temporary_path)
		return _failure(write_error, "Could not finish writing the temporary save file: %s" % error_string(write_error))

	var temporary_absolute := ProjectSettings.globalize_path(temporary_path)
	var destination_absolute := ProjectSettings.globalize_path(path)
	var replace_error := DirAccess.rename_absolute(temporary_absolute, destination_absolute)
	if replace_error == OK:
		_remove_if_present(backup_path)
		return {"ok": true, "code": OK, "error": ""}

	# Some platforms do not replace an existing destination via rename. Keep
	# the previous complete file as a backup until the new file is in place.
	if not FileAccess.file_exists(path):
		_remove_if_present(temporary_path)
		return _failure(replace_error, "Could not move the completed save into place: %s" % error_string(replace_error))

	_remove_if_present(backup_path)
	var backup_absolute := ProjectSettings.globalize_path(backup_path)
	var backup_error := DirAccess.rename_absolute(destination_absolute, backup_absolute)
	if backup_error != OK:
		_remove_if_present(temporary_path)
		return _failure(backup_error, "Could not protect the previous save before replacement: %s" % error_string(backup_error))

	replace_error = DirAccess.rename_absolute(temporary_absolute, destination_absolute)
	if replace_error != OK:
		DirAccess.rename_absolute(backup_absolute, destination_absolute)
		_remove_if_present(temporary_path)
		return _failure(replace_error, "Could not move the completed save into place: %s" % error_string(replace_error))

	_remove_if_present(backup_path)
	return {"ok": true, "code": OK, "error": ""}


static func _read_path(path: String, expected_type: int, maximum_bytes: int) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure(ERR_FILE_NOT_FOUND, "File not found: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error := FileAccess.get_open_error()
		return _failure(open_error, "Could not open %s: %s" % [path, error_string(open_error)])
	var length := file.get_length()
	if length > maximum_bytes:
		file.close()
		return _failure(ERR_OUT_OF_MEMORY, "File is too large (%d bytes; limit is %d)." % [length, maximum_bytes])
	var source := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK:
		return _failure(read_error, "Could not read %s: %s" % [path, error_string(read_error)])

	var parser := JSON.new()
	var parse_error := parser.parse(source)
	if parse_error != OK:
		return _failure(
			parse_error,
			"Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
	var value: Variant = parser.data
	if expected_type != TYPE_NIL and typeof(value) != expected_type:
		return _failure(ERR_INVALID_DATA, "Expected %s JSON, found %s." % [type_string(expected_type), type_string(typeof(value))])
	return {"ok": true, "value": value, "code": OK, "error": ""}


static func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _failure(code: int, message: String) -> Dictionary:
	return {"ok": false, "value": null, "code": code, "error": message}
