extends RefCounted

const Capture = preload("res://main_scenes/controllers/capture_controller.gd")
const ViewportCoordinator = preload("res://main_scenes/controllers/viewport_controller.gd")
const SaveCoordinator = preload("res://main_scenes/controllers/save_controller.gd")


func run(t) -> void:
	_test_capture_format_contract(t)
	_test_ffmpeg_argument_contract(t)
	_test_viewport_zoom_contract(t)
	_test_session_recovery_contract(t)
	_test_save_image_encoding_contract(t)
	_test_main_decomposition_contract(t)


func _test_capture_format_contract(t) -> void:
	t.assert_equal(Capture.extension_for_format("webm"), ".webm", "WebM capture extension is stable")
	t.assert_equal(Capture.extension_for_format("apng"), ".apng", "APNG capture extension is stable")
	t.assert_equal(Capture.extension_for_format("gif"), ".gif", "GIF capture extension is stable")
	t.assert_equal(Capture.extension_for_format("invalid"), ".webm", "unknown capture formats retain the WebM fallback")


func _test_ffmpeg_argument_contract(t) -> void:
	var webm: Array[String] = Capture.ffmpeg_arguments("frames.raw", Vector2i(800, 600), "out.webm", "progress.log", 30)
	t.assert_true(webm.has("rawvideo"), "capture declares raw-video input")
	t.assert_true(webm.has("800x600"), "capture passes exact frame dimensions")
	t.assert_true(webm.has("30"), "capture passes the configured frame rate")
	t.assert_true(webm.has("libvpx-vp9"), "WebM capture retains VP9 encoding")
	t.assert_true(webm.has("yuva420p"), "WebM capture retains alpha output")
	t.assert_equal(webm[-1], "out.webm", "FFmpeg output path remains the final argument")

	var apng: Array[String] = Capture.ffmpeg_arguments("frames.raw", Vector2i(10, 20), "out.apng", "progress.log", 15)
	t.assert_true(apng.has("apng"), "APNG capture selects the APNG encoder")
	t.assert_true(apng.has("rgba"), "APNG capture preserves RGBA pixels")
	var gif: Array[String] = Capture.ffmpeg_arguments("frames.raw", Vector2i(10, 20), "out.gif", "progress.log", 15)
	t.assert_true(gif.has("-filter_complex"), "GIF capture creates a transparency-aware palette")
	t.assert_true(String(gif[gif.find("-filter_complex") + 1]).contains("palettegen"), "GIF capture retains palette generation")


func _test_viewport_zoom_contract(t) -> void:
	t.assert_equal(ViewportCoordinator.next_zoom_percent(100, 1), 110, "viewport zoom increases in ten-percent steps")
	t.assert_equal(ViewportCoordinator.next_zoom_percent(100, -1), 90, "viewport zoom decreases in ten-percent steps")
	t.assert_equal(ViewportCoordinator.next_zoom_percent(400, 1), 400, "viewport zoom respects the maximum")
	t.assert_equal(ViewportCoordinator.next_zoom_percent(10, -1), 10, "viewport zoom respects the minimum")
	t.assert_equal(ViewportCoordinator.next_zoom_percent(100, 0), 100, "zero direction leaves viewport zoom unchanged")


func _test_session_recovery_contract(t) -> void:
	t.assert_false(SaveCoordinator.should_recover(false, false, 0, 0), "missing session files never prompt recovery")
	t.assert_true(SaveCoordinator.should_recover(true, false, 10, 0), "a session recovers when the avatar is missing")
	t.assert_true(SaveCoordinator.should_recover(true, true, 20, 10), "a newer session recovers over an older avatar")
	t.assert_false(SaveCoordinator.should_recover(true, true, 10, 20), "an older session does not replace a newer avatar")
	t.assert_false(SaveCoordinator.should_recover(true, true, 10, 10), "equal timestamps do not prompt recovery")


func _test_save_image_encoding_contract(t) -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 0.25, 0.5, 0.75))
	var entry := {"_image_ref": image}
	SaveCoordinator._encode_entry_images(entry)
	t.assert_false(entry.has("_image_ref"), "save workers release live image references after encoding")
	t.assert_true(entry.has("imageData"), "save workers produce the compatibility imageData field")
	var decoded := Image.new()
	var decode_error := decoded.load_png_from_buffer(Marshalls.base64_to_raw(entry["imageData"]))
	t.assert_equal(decode_error, OK, "worker-encoded sprite images remain valid PNG data")
	t.assert_equal(decoded.get_size(), Vector2i(2, 2), "worker-encoded sprite images preserve dimensions")


func _test_main_decomposition_contract(t) -> void:
	var main_source := FileAccess.get_file_as_string(_source_root().path_join("main_scenes/main.gd"))
	var capture_source := FileAccess.get_file_as_string("res://main_scenes/controllers/capture_controller.gd")
	var viewport_source := FileAccess.get_file_as_string("res://main_scenes/controllers/viewport_controller.gd")
	t.assert_true(main_source.contains("CaptureControllerScene"), "main owns the extracted capture coordinator")
	t.assert_true(main_source.contains("ViewportControllerScene"), "main owns the extracted viewport coordinator")
	t.assert_true(main_source.contains("SaveControllerScene"), "main owns the extracted avatar-save coordinator")
	t.assert_true(main_source.contains("capture_controller.on_capture_released()"), "main keeps the stable capture release interface")
	t.assert_false(main_source.contains("func _encode_worker"), "FFmpeg worker implementation no longer lives in main")
	t.assert_false(main_source.contains("frames.raw"), "raw recording storage no longer lives in main")
	t.assert_true(capture_source.contains("func _exit_tree"), "capture controller owns explicit shutdown")
	t.assert_true(capture_source.contains("wait_to_finish"), "capture shutdown joins its worker")
	t.assert_true(capture_source.contains("_cleanup_recording_temp"), "capture controller owns temporary-file cleanup")
	t.assert_true(capture_source.contains("_on_screenshot_dialog_canceled"), "canceling screenshot save releases the pending image")
	t.assert_false(capture_source.contains("Global."), "capture controller receives shared state through its setup boundary")
	t.assert_false(viewport_source.contains("Global."), "viewport controller receives shared state through its setup boundary")
	t.assert_false(main_source.contains("func _update_resize_state"), "viewport resize bookkeeping no longer lives in main")
	t.assert_false(main_source.contains("func _session_save_worker"), "session worker implementation no longer lives in main")
	t.assert_false(main_source.contains("var saveDialog"), "save-dialog ownership no longer lives in main")
	t.assert_true(main_source.count("\n") < 2100, "main decomposition keeps the coordinator below the Phase 3 size ceiling")


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
