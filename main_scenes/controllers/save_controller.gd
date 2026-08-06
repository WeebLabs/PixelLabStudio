class_name AvatarSaveController
extends Node

const JsonStore = preload("res://autoload/persistence/json_file_store.gd")
const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")

const SESSION_SAVE_PATH := "user://session.pngtp"
const SESSION_AUTO_SAVE_INTERVAL := 60.0

var save_dialog: FileDialog = null
var load_dialog: FileDialog = null

var _main: Node2D = null
var _global: Node = null
var _saving: Node = null
var _undo_manager: Node = null

var _save_thread: Thread = null
var _save_progress := 0.0
var _save_progress_dialog: Node2D = null

var _session_dirty := false
var _session_timer := 0.0
var _session_thread: Thread = null
var _session_recovery_dialog: Node2D = null


func setup(main_node: Node2D, global_service: Node, saving_service: Node, undo_service: Node) -> void:
	_main = main_node
	_global = global_service
	_saving = saving_service
	_undo_manager = undo_service
	_create_file_dialogs()
	if not _undo_manager.is_connected("state_saved", mark_dirty):
		_undo_manager.connect("state_saved", mark_dirty)


func _exit_tree() -> void:
	shutdown()


func shutdown() -> void:
	_join_thread("save")
	_join_thread("session")
	if is_instance_valid(_save_progress_dialog):
		_save_progress_dialog.queue_free()
		_save_progress_dialog = null


func process_frame(delta: float) -> void:
	if _save_thread != null and _save_progress_dialog != null:
		_save_progress_dialog.get_node("ProgressBar").value = _save_progress
		_save_progress_dialog.position = _main.get_viewport().get_visible_rect().size * 0.5

	if _session_thread != null and not _session_thread.is_alive():
		_join_thread("session")
	if _save_thread != null or _session_thread != null:
		return
	if not _main.saveLoaded or not _session_dirty:
		return
	_session_timer += delta
	if _session_timer < SESSION_AUTO_SAVE_INTERVAL:
		return
	_session_timer = 0.0
	_session_dirty = false
	var data: Dictionary = _main._build_avatar_save_data()
	_session_thread = Thread.new()
	_session_thread.start(_session_save_worker.bind(data))


func startup_restore() -> void:
	var last_avatar_path := String(_saving.settings.get("lastAvatar", ""))
	if _has_recoverable_session(last_avatar_path):
		_show_session_recovery_dialog(last_avatar_path)
	elif not last_avatar_path.is_empty():
		_main._on_load_dialog_file_selected(last_avatar_path)


func show_save_dialog() -> void:
	save_dialog.popup_file_dialog()


func show_load_dialog() -> void:
	load_dialog.popup_file_dialog()


func is_dialog_open() -> bool:
	return (
		(save_dialog != null and save_dialog.visible)
		or (load_dialog != null and load_dialog.visible)
		or is_instance_valid(_save_progress_dialog)
		or is_instance_valid(_session_recovery_dialog)
	)


func mark_dirty() -> void:
	_session_dirty = true


func discard_session_file() -> void:
	if not FileAccess.file_exists(SESSION_SAVE_PATH):
		return
	var directory := DirAccess.open("user://")
	if directory != null:
		directory.remove(SESSION_SAVE_PATH.get_file())


func _create_file_dialogs() -> void:
	var user_dir := OS.get_user_data_dir()

	save_dialog = FileDialog.new()
	save_dialog.title = "Save Avatar"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.filters = PackedStringArray(["*.save;PNGTuberPlus Avatar"])
	save_dialog.use_native_dialog = true
	save_dialog.current_dir = user_dir
	save_dialog.file_selected.connect(_on_save_file_selected)
	_main.add_child(save_dialog)

	load_dialog = FileDialog.new()
	load_dialog.title = "Load Avatar"
	load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	load_dialog.access = FileDialog.ACCESS_FILESYSTEM
	load_dialog.filters = PackedStringArray(["*.save;PNGTuberPlus Avatar"])
	load_dialog.use_native_dialog = true
	load_dialog.current_dir = user_dir
	load_dialog.file_selected.connect(_main._on_load_dialog_file_selected)
	_main.add_child(load_dialog)


func _on_save_file_selected(path: String) -> void:
	_join_thread("save")
	_join_thread("session")
	var data: Dictionary = _main._build_avatar_save_data()
	_save_progress = 0.0
	_save_progress_dialog = _main._create_progress_dialog("Saving avatar...")
	_save_thread = Thread.new()
	_save_thread.start(_save_worker.bind(data, path))


func _save_worker(data: Dictionary, path: String) -> void:
	var total := data.size()
	var done := 0
	for id in data:
		_encode_entry_images(data[id])
		done += 1
		_save_progress = float(done) / float(total)
	var schema_result := AvatarSave.normalize(data)
	if not schema_result["ok"]:
		call_deferred("_on_save_finished", path, data, schema_result)
		return
	var normalized_data: Dictionary = schema_result["value"]
	var write_result := JsonStore.write_document_atomic(path, normalized_data)
	call_deferred("_on_save_finished", path, normalized_data, write_result)


func _on_save_finished(path: String, data: Dictionary, result: Dictionary) -> void:
	_join_thread("save")
	if is_instance_valid(_save_progress_dialog):
		_save_progress_dialog.queue_free()
		_save_progress_dialog = null
	if not result["ok"]:
		_global.pushUpdate("Save failed: " + result["error"])
		_session_dirty = true
		return
	_saving.data = data
	_saving.settings["lastAvatar"] = path
	if not _saving.write_settings(_saving.settingsPath):
		_global.pushUpdate(_saving.last_error)
	_global.pushUpdate("Save complete: " + path.get_file())
	_show_save_confirmation(path.get_file())
	discard_session_file()
	_session_dirty = false
	_session_timer = 0.0


func _session_save_worker(data: Dictionary) -> void:
	for id in data:
		_encode_entry_images(data[id])
	var schema_result := AvatarSave.normalize(data)
	if not schema_result["ok"]:
		call_deferred("_on_session_save_failed", schema_result["error"])
		return
	var write_result := JsonStore.write_document_atomic(SESSION_SAVE_PATH, schema_result["value"])
	if not write_result["ok"]:
		call_deferred("_on_session_save_failed", write_result["error"])


func _on_session_save_failed(message: String) -> void:
	_session_dirty = true
	push_warning("Session auto-save failed: " + message)


func _has_recoverable_session(last_avatar_path: String) -> bool:
	var session_exists := FileAccess.file_exists(SESSION_SAVE_PATH)
	var avatar_exists := not last_avatar_path.is_empty() and FileAccess.file_exists(last_avatar_path)
	var session_modified := FileAccess.get_modified_time(SESSION_SAVE_PATH) if session_exists else 0
	var avatar_modified := FileAccess.get_modified_time(last_avatar_path) if avatar_exists else 0
	return should_recover(session_exists, avatar_exists, session_modified, avatar_modified)


func _show_session_recovery_dialog(last_avatar_path: String) -> void:
	var dialog := Node2D.new()
	dialog.z_index = 100
	dialog.position = _main.get_viewport().get_visible_rect().size * 0.5

	var blocker := ColorRect.new()
	blocker.position = Vector2(-5000, -5000)
	blocker.size = Vector2(10000, 10000)
	blocker.color = Color(0, 0, 0, 0.35)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(blocker)

	var background := ColorRect.new()
	background.position = Vector2(-220, -75)
	background.size = Vector2(440, 150)
	background.color = Color(0.13, 0.13, 0.15, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(background)

	var title := Label.new()
	title.position = Vector2(-210, -62)
	title.size = Vector2(420, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Recover unsaved session?"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(title)

	var body := Label.new()
	body.position = Vector2(-210, -35)
	body.size = Vector2(420, 60)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = "A more recent in-progress session was found. Restore it, or discard and load your last saved avatar?"
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(body)

	var restore_button := Button.new()
	restore_button.text = "Restore"
	restore_button.position = Vector2(-180, 38)
	restore_button.size = Vector2(160, 28)
	restore_button.pressed.connect(func(): _on_session_recovery_choice(true, last_avatar_path))
	dialog.add_child(restore_button)

	var discard_button := Button.new()
	discard_button.text = "Discard"
	discard_button.position = Vector2(20, 38)
	discard_button.size = Vector2(160, 28)
	discard_button.pressed.connect(func(): _on_session_recovery_choice(false, last_avatar_path))
	dialog.add_child(discard_button)

	_main.get_node("UILayer").add_child(dialog)
	_session_recovery_dialog = dialog


func _on_session_recovery_choice(restore: bool, last_avatar_path: String) -> void:
	if is_instance_valid(_session_recovery_dialog):
		_session_recovery_dialog.queue_free()
		_session_recovery_dialog = null
	if restore:
		_main._on_load_dialog_file_selected(SESSION_SAVE_PATH)
	else:
		discard_session_file()
		if not last_avatar_path.is_empty() and FileAccess.file_exists(last_avatar_path):
			_main._on_load_dialog_file_selected(last_avatar_path)


func _show_save_confirmation(filename: String) -> void:
	var dialog := Node2D.new()
	dialog.z_index = 100
	dialog.position = _main.get_viewport().get_visible_rect().size * 0.5

	var background := ColorRect.new()
	background.position = Vector2(-200, -32)
	background.size = Vector2(400, 64)
	background.color = Color(0.13, 0.16, 0.13, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			dialog.queue_free()
	)
	dialog.add_child(background)

	var label := Label.new()
	label.position = Vector2(-190, -22)
	label.size = Vector2(380, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "✓ Saved: " + filename
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(label)
	_main.get_node("UILayer").add_child(dialog)

	var tween := dialog.create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(dialog, "modulate:a", 0.0, 0.5)
	tween.tween_callback(dialog.queue_free)


func _join_thread(kind: String) -> void:
	if kind == "save" and _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null
	elif kind == "session" and _session_thread != null:
		_session_thread.wait_to_finish()
		_session_thread = null


static func _encode_entry_images(entry: Variant) -> void:
	if not entry is Dictionary:
		return
	if entry.has("_image_ref"):
		var image: Image = entry["_image_ref"]
		entry["imageData"] = Marshalls.raw_to_base64(image.save_png_to_buffer())
		entry.erase("_image_ref")
	if entry.has("_normal_image_ref"):
		var normal_image: Image = entry["_normal_image_ref"]
		entry["normalImageData"] = Marshalls.raw_to_base64(normal_image.save_png_to_buffer())
		entry.erase("_normal_image_ref")


static func should_recover(session_exists: bool, avatar_exists: bool, session_modified: int, avatar_modified: int) -> bool:
	return session_exists and (not avatar_exists or session_modified > avatar_modified)
