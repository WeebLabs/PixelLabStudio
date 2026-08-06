class_name CaptureController
extends Node

const HOLD_TO_RECORD_MS := 1000

var _main: Node2D = null
var _global: Node = null
var _saving: Node = null
var _screenshot_dialog: FileDialog = null
var _screenshot_image: Image = null

var _recording := false
var _recording_viewport: SubViewport = null
var _recording_camera: Camera2D = null
var _recording_file: FileAccess = null
var _recording_temp_path := ""
var _recording_frame_count := 0
var _recording_timer := 0.0
var _recording_size := Vector2i.ZERO
var _record_dialog: FileDialog = null

var _encode_thread: Thread = null
var _encoding := false
var _encode_progress := 0.0
var _encode_progress_dialog: Node2D = null
var _encode_progress_path := ""
var _encode_total_frames := 0


func setup(main_node: Node2D, global_service: Node, saving_service: Node) -> void:
	_main = main_node
	_global = global_service
	_saving = saving_service
	set_process(true)


func _exit_tree() -> void:
	_recording = false
	if _recording_file != null:
		_recording_file.close()
		_recording_file = null
	if is_instance_valid(_recording_viewport):
		_recording_viewport.queue_free()
		_recording_viewport = null
		_recording_camera = null
	if _encode_thread != null and _encode_thread.is_started():
		_encode_thread.wait_to_finish()
		_encode_thread = null
	_encoding = false
	_cleanup_recording_temp()


func _process(delta: float) -> void:
	if not is_instance_valid(_main):
		return
	if not _recording and not _encoding and _global._screenshot_key_held and _global._screenshot_press_time > 0:
		if Time.get_ticks_msec() - _global._screenshot_press_time >= HOLD_TO_RECORD_MS:
			_start_recording()

	if _recording:
		_recording_timer += delta
		var interval := 1.0 / float(_saving.settings.get("recordingFPS", 30))
		while _recording_timer >= interval:
			_capture_recording_frame()
			_recording_timer -= interval

	if _encoding:
		_poll_encode_progress()
		if _encode_thread != null and not _encode_thread.is_alive():
			_encode_thread.wait_to_finish()
			_encode_thread = null
			_encoding = false
			if _encode_progress_dialog != null:
				_encode_progress_dialog.queue_free()
				_encode_progress_dialog = null
			_cleanup_recording_temp()


func on_capture_pressed() -> void:
	# Hold timing belongs to Global's input router so release is still observed
	# if Ctrl is released before the capture key.
	pass


func on_capture_released() -> void:
	if _recording:
		_stop_recording()
	elif _global._screenshot_press_time > 0:
		take_screenshot()


func take_screenshot() -> void:
	if _screenshot_image != null or not is_instance_valid(_main):
		return
	var ndi_manager: Node = _main.ndi_manager
	if ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_viewport != null:
		_screenshot_image = ndi_manager.ndi_viewport.get_texture().get_image()
	else:
		var viewport := _main.get_viewport()
		var screenshot_viewport := SubViewport.new()
		screenshot_viewport.transparent_bg = true
		screenshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		screenshot_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		screenshot_viewport.size = Vector2i(viewport.get_visible_rect().size)
		screenshot_viewport.world_2d = viewport.world_2d
		screenshot_viewport.canvas_cull_mask = 1
		screenshot_viewport.gui_disable_input = true
		screenshot_viewport.handle_input_locally = false
		_main.add_child(screenshot_viewport)

		var screenshot_camera := Camera2D.new()
		screenshot_camera.position = _main.camera.position
		screenshot_camera.zoom = _main.camera.zoom
		screenshot_viewport.add_child(screenshot_camera)
		screenshot_camera.make_current()
		await RenderingServer.frame_post_draw
		if not is_instance_valid(screenshot_viewport):
			return
		_screenshot_image = screenshot_viewport.get_texture().get_image()
		screenshot_viewport.queue_free()

	if _screenshot_dialog == null:
		_create_screenshot_dialog()
	_screenshot_dialog.current_file = "screenshot_%s.png" % _timestamp()
	_screenshot_dialog.popup_centered(Vector2i(600, 400))


func is_recording() -> bool:
	return _recording


func is_encoding() -> bool:
	return _encoding


func is_dialog_open() -> bool:
	return (
		(_screenshot_dialog != null and _screenshot_dialog.visible)
		or (_record_dialog != null and _record_dialog.visible)
		or _encode_progress_dialog != null
	)


func _create_screenshot_dialog() -> void:
	_screenshot_dialog = FileDialog.new()
	_screenshot_dialog.title = "Save Screenshot"
	_screenshot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_screenshot_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_screenshot_dialog.filters = PackedStringArray(["*.png;PNG Image"])
	_screenshot_dialog.use_native_dialog = true
	_screenshot_dialog.file_selected.connect(_on_screenshot_dialog_file_selected)
	_screenshot_dialog.canceled.connect(_on_screenshot_dialog_canceled)
	_main.add_child(_screenshot_dialog)


func _on_screenshot_dialog_file_selected(path: String) -> void:
	if _screenshot_image == null:
		return
	if not path.ends_with(".png"):
		path += ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := _screenshot_image.save_png(path)
	_global.pushUpdate("Screenshot saved: " + path.get_file() if error == OK else "Failed to save screenshot.")
	_screenshot_image = null


func _on_screenshot_dialog_canceled() -> void:
	_screenshot_image = null


func _start_recording() -> void:
	if _recording or _encoding:
		return
	if _find_ffmpeg().is_empty():
		_global.pushUpdate("FFmpeg not found. Install FFmpeg to record video.")
		return

	_recording = true
	_recording_timer = 0.0
	_recording_frame_count = 0
	var ndi_manager: Node = _main.ndi_manager
	var use_ndi: bool = ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_viewport != null
	_recording_size = ndi_manager.ndi_viewport.size if use_ndi else Vector2i(_main.get_viewport().get_visible_rect().size)

	var temp_dir := OS.get_cache_dir().path_join("pngtuber_recording")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_recording_temp_path = temp_dir.path_join("frames.raw")
	_recording_file = FileAccess.open(_recording_temp_path, FileAccess.WRITE)
	if _recording_file == null:
		_recording = false
		_global.pushUpdate("Could not create the temporary recording file.")
		_cleanup_recording_temp()
		return

	_recording_viewport = SubViewport.new()
	_recording_viewport.transparent_bg = true
	_recording_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_recording_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_recording_viewport.size = _recording_size
	_recording_viewport.world_2d = _main.get_viewport().world_2d
	_recording_viewport.canvas_cull_mask = 1
	_recording_viewport.gui_disable_input = true
	_recording_viewport.handle_input_locally = false
	_main.add_child(_recording_viewport)

	_recording_camera = Camera2D.new()
	_recording_viewport.add_child(_recording_camera)
	if use_ndi:
		_recording_camera.position = ndi_manager.ndi_camera.position
		_recording_camera.zoom = ndi_manager.ndi_camera.zoom
	else:
		_recording_camera.position = _main.camera.position
		_recording_camera.zoom = _main.camera.zoom
	_recording_camera.make_current()
	_global.pushUpdate("Recording...")


func _stop_recording() -> void:
	if not _recording:
		return
	_recording = false
	if _recording_file != null:
		_recording_file.close()
		_recording_file = null
	if _recording_viewport != null:
		_recording_viewport.queue_free()
		_recording_viewport = null
		_recording_camera = null

	if _recording_frame_count == 0:
		_global.pushUpdate("No frames captured.")
		_cleanup_recording_temp()
		return

	_global.pushUpdate("Encoding... (%d frames)" % _recording_frame_count)
	if _record_dialog == null:
		_create_record_dialog()
	var format := String(_saving.settings.get("recordingFormat", "webm"))
	_record_dialog.filters = PackedStringArray([_recording_filter(format)])
	_record_dialog.current_file = "recording_%s%s" % [_timestamp(), extension_for_format(format)]
	_record_dialog.popup_centered(Vector2i(600, 400))


func _capture_recording_frame() -> void:
	if _recording_viewport == null or _recording_file == null:
		return
	var ndi_manager: Node = _main.ndi_manager
	if ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_camera != null:
		_recording_camera.position = ndi_manager.ndi_camera.position
		_recording_camera.zoom = ndi_manager.ndi_camera.zoom
	else:
		_recording_camera.position = _main.camera.position
		_recording_camera.zoom = _main.camera.zoom
	var image := _recording_viewport.get_texture().get_image()
	if image != null:
		_recording_file.store_buffer(image.get_data())
		_recording_frame_count += 1


func _create_record_dialog() -> void:
	_record_dialog = FileDialog.new()
	_record_dialog.title = "Save Recording"
	_record_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_record_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_record_dialog.filters = PackedStringArray(["*.webm;WebM Video"])
	_record_dialog.use_native_dialog = true
	_record_dialog.file_selected.connect(_on_record_dialog_file_selected)
	_record_dialog.canceled.connect(_on_record_dialog_canceled)
	_main.add_child(_record_dialog)


func _on_record_dialog_file_selected(path: String) -> void:
	var format := String(_saving.settings.get("recordingFormat", "webm"))
	var extension := extension_for_format(format)
	if not path.ends_with(extension):
		path += extension
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_encoding = true
	_encode_progress = 0.0
	_encode_total_frames = _recording_frame_count
	var temp_dir := OS.get_cache_dir().path_join("pngtuber_recording")
	_encode_progress_path = temp_dir.path_join("ffmpeg_progress.log")
	if FileAccess.file_exists(_encode_progress_path):
		DirAccess.remove_absolute(_encode_progress_path)
	_encode_progress_dialog = _main._create_progress_dialog("Encoding video...")
	_encode_thread = Thread.new()
	var fps := int(_saving.settings.get("recordingFPS", 30))
	_encode_thread.start(_encode_worker.bind(_recording_temp_path, _recording_size, path, _encode_progress_path, fps))


func _poll_encode_progress() -> void:
	if _encode_progress_dialog == null:
		return
	if not _encode_progress_path.is_empty() and FileAccess.file_exists(_encode_progress_path):
		var file := FileAccess.open(_encode_progress_path, FileAccess.READ)
		if file != null:
			var lines := file.get_as_text().split("\n")
			file.close()
			for index in range(lines.size() - 1, -1, -1):
				if lines[index].begins_with("frame="):
					var frame_text := lines[index].substr(6).strip_edges()
					if frame_text.is_valid_int() and _encode_total_frames > 0:
						_encode_progress = clampf(float(frame_text.to_int()) / float(_encode_total_frames), 0.0, 1.0)
					break
	_encode_progress_dialog.get_node("ProgressBar").value = _encode_progress
	_encode_progress_dialog.position = _main.get_viewport().get_visible_rect().size * 0.5


func _encode_worker(raw_path: String, size: Vector2i, output_path: String, progress_path: String, fps: int) -> void:
	var ffmpeg := _find_ffmpeg()
	if ffmpeg.is_empty():
		call_deferred("_on_encode_done", false)
		return
	var output: Array = []
	var exit_code := OS.execute(ffmpeg, ffmpeg_arguments(raw_path, size, output_path, progress_path, fps), output)
	call_deferred("_on_encode_done", exit_code == 0)


func _on_encode_done(success: bool) -> void:
	_global.pushUpdate("Recording saved!" if success else "FFmpeg encoding failed.")


func _on_record_dialog_canceled() -> void:
	_cleanup_recording_temp()
	_global.pushUpdate("Recording discarded.")


func _cleanup_recording_temp() -> void:
	if not _recording_temp_path.is_empty() and FileAccess.file_exists(_recording_temp_path):
		DirAccess.remove_absolute(_recording_temp_path)
	if not _encode_progress_path.is_empty() and FileAccess.file_exists(_encode_progress_path):
		DirAccess.remove_absolute(_encode_progress_path)
	_recording_temp_path = ""
	_encode_progress_path = ""
	_recording_frame_count = 0


func _find_ffmpeg() -> String:
	var common_paths: Array[String] = []
	if OS.get_name() == "Windows":
		common_paths = [
			OS.get_executable_path().get_base_dir().path_join("ffmpeg.exe"),
			OS.get_environment("ProgramFiles").path_join("ffmpeg/bin/ffmpeg.exe"),
			OS.get_environment("LOCALAPPDATA").path_join("Microsoft/WinGet/Links/ffmpeg.exe"),
			"C:/ffmpeg/bin/ffmpeg.exe",
		]
	else:
		common_paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
	for path in common_paths:
		if FileAccess.file_exists(path):
			return path
	var output: Array = []
	var command := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(command, ["ffmpeg"], output) == 0 and not output.is_empty():
		return String(output[0]).strip_edges()
	return ""


static func extension_for_format(format: String) -> String:
	return {"webm": ".webm", "apng": ".apng", "gif": ".gif"}.get(format, ".webm")


static func ffmpeg_arguments(raw_path: String, size: Vector2i, output_path: String, progress_path: String, fps: int) -> Array[String]:
	var arguments: Array[String] = [
		"-y", "-f", "rawvideo", "-pix_fmt", "rgba",
		"-s", "%dx%d" % [size.x, size.y], "-r", str(fps), "-i", raw_path,
	]
	if output_path.ends_with(".apng"):
		arguments.append_array(["-c:v", "apng", "-pix_fmt", "rgba", "-plays", "0"])
	elif output_path.ends_with(".gif"):
		arguments.append_array([
			"-filter_complex",
			"split[s0][s1];[s0]palettegen=reserve_transparent=1[p];[s1][p]paletteuse=alpha_threshold=128",
			"-loop", "0",
		])
	else:
		arguments.append_array(["-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-auto-alt-ref", "0", "-crf", "30", "-b:v", "0"])
	arguments.append_array(["-progress", progress_path, output_path])
	return arguments


static func _recording_filter(format: String) -> String:
	return {
		"webm": "*.webm;WebM Video",
		"apng": "*.apng;Animated PNG",
		"gif": "*.gif;GIF Image",
	}.get(format, "*.webm;WebM Video")


static func _timestamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
