extends RefCounted

const ImportBudget = preload("res://autoload/import/import_limits.gd")
const APNG = preload("res://autoload/apng_parser.gd")
const PSD = preload("res://autoload/psd_parser.gd")
const StreamDeck = preload("res://addons/godot-streamdeck-addon/protocol.gd")
const NDIGeometry = preload("res://ndi/ndi_output_geometry.gd")

func run(t) -> void:
	_test_import_budgets(t)
	_test_malformed_imports(t)
	_test_streamdeck_protocol(t)
	_test_ndi_geometry(t)
	_test_integration_lifecycles(t)

func _test_import_budgets(t) -> void:
	t.assert_true(ImportBudget.section_fits(8, 12, 20), "binary section may end exactly at its boundary")
	t.assert_false(ImportBudget.section_fits(8, 13, 20), "binary section cannot cross its boundary")
	t.assert_false(ImportBudget.section_fits(-1, 1, 20), "negative binary offsets are rejected")
	t.assert_true(ImportBudget.dimensions_valid(16384, 4096), "supported maximum-width image remains valid")
	t.assert_false(ImportBudget.dimensions_valid(16385, 1), "overwide images are rejected")
	t.assert_false(ImportBudget.decoded_images_fit(4096, 4096, 100), "decoded animation memory is budgeted across every frame")
	t.assert_false(ImportBudget.count_valid(ImportBudget.MAX_LAYERS + 1, ImportBudget.MAX_LAYERS), "layer count has a hard upper bound")

func _test_malformed_imports(t) -> void:
	var path := "user://malformed-import.bin"
	var bytes := PackedByteArray(APNG.PNG_SIGNATURE)
	bytes.append_array(PackedByteArray([0x7f, 0xff, 0xff, 0xff]))
	bytes.append_array("IHDR".to_ascii_buffer())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	t.assert_false(APNG.is_apng(path), "APNG detection rejects an oversized truncated chunk without seeking past EOF")
	var apng_result = APNG.new().parse(path)
	t.assert_true(not apng_result.error.is_empty(), "APNG parsing reports malformed chunk data instead of indexing it")

	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer("8BPS".to_ascii_buffer())
	file.close()
	var psd_result = PSD.new().parse(path)
	t.assert_true(not psd_result.error.is_empty(), "PSD parsing rejects a truncated header before reading fields")
	var psd_parser := PSD.new()
	t.assert_true(psd_parser._packbits_rows_valid(PackedByteArray([0, 2]), PackedByteArray([254, 7]), 3, 1), "PSD PackBits validation accepts an exact scanline")
	t.assert_false(psd_parser._packbits_rows_valid(PackedByteArray([0, 2]), PackedByteArray([255, 7]), 3, 1), "PSD PackBits validation rejects a scanline that decodes short")

	var source_image := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	source_image.fill(Color(0.25, 0.5, 0.75, 1.0))
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(_one_frame_apng(source_image))
	file.close()
	var valid_result = APNG.new().parse(path)
	t.assert_equal(valid_result.error, "", "bounded APNG parser accepts a valid one-frame animation")
	t.assert_equal(valid_result.frames.size(), 1, "valid APNG frame count is preserved")
	t.assert_equal(valid_result.frames[0].image.get_size(), Vector2i(4, 3), "valid APNG frame dimensions are preserved")
	t.assert_approx(valid_result.frames[0].image.get_pixel(0, 0).b, 0.75, 0.01, "valid APNG pixel data is decoded")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _one_frame_apng(image: Image) -> PackedByteArray:
	var png := image.save_png_to_buffer()
	var ihdr := PackedByteArray()
	var idat := PackedByteArray()
	var position := 8
	while position + 12 <= png.size():
		var length := _u32_at(png, position)
		var chunk_type := png.slice(position + 4, position + 8).get_string_from_ascii()
		var data := png.slice(position + 8, position + 8 + length)
		if chunk_type == "IHDR":
			ihdr = data
		elif chunk_type == "IDAT":
			idat.append_array(data)
		position += length + 12

	var parser := APNG.new()
	parser._init_crc_table()
	var result := PackedByteArray(APNG.PNG_SIGNATURE)
	result.append_array(parser._make_chunk("IHDR", ihdr))
	result.append_array(parser._make_chunk("acTL", PackedByteArray([0, 0, 0, 1, 0, 0, 0, 0])))
	var control := PackedByteArray([0, 0, 0, 0])
	_append_u32(control, image.get_width())
	_append_u32(control, image.get_height())
	_append_u32(control, 0)
	_append_u32(control, 0)
	control.append_array(PackedByteArray([0, 1, 0, 10, 0, 0]))
	result.append_array(parser._make_chunk("fcTL", control))
	result.append_array(parser._make_chunk("IDAT", idat))
	result.append_array(parser._make_chunk("IEND", PackedByteArray()))
	return result

func _append_u32(buffer: PackedByteArray, value: int) -> void:
	buffer.append((value >> 24) & 0xff)
	buffer.append((value >> 16) & 0xff)
	buffer.append((value >> 8) & 0xff)
	buffer.append(value & 0xff)

func _u32_at(buffer: PackedByteArray, position: int) -> int:
	return (buffer[position] << 24) | (buffer[position + 1] << 16) \
		| (buffer[position + 2] << 8) | buffer[position + 3]

func _test_streamdeck_protocol(t) -> void:
	t.assert_true(StreamDeck.valid_port("8080"), "Stream Deck bridge accepts a valid port")
	t.assert_false(StreamDeck.valid_port("not-a-port"), "Stream Deck bridge rejects nonnumeric ports")
	t.assert_false(StreamDeck.valid_port(70000), "Stream Deck bridge rejects ports outside TCP range")
	t.assert_equal(StreamDeck.websocket_url(1234), "ws://127.0.0.1:1234/ws", "Stream Deck URL includes the websocket scheme")
	t.assert_equal(StreamDeck.websocket_url("bad"), "ws://127.0.0.1:8080/ws", "invalid Stream Deck ports use the safe default")
	var packet := StreamDeck.normalize_packet({
		"event": "keyDown",
		"action": "games.boyne.godot.emitsignal",
		"payload": {"settings": {"signalInput": "wave"}},
	})
	t.assert_equal(packet["settings"]["signalInput"], "wave", "valid Stream Deck packets expose normalized settings")
	t.assert_true(StreamDeck.normalize_packet({"event": "keyDown"}).is_empty(), "partial Stream Deck packets are ignored safely")
	t.assert_true(StreamDeck.normalize_packet("bad json").is_empty(), "non-object Stream Deck messages are ignored safely")
	t.assert_equal(StreamDeck.safe_scene_path("user://outside.tscn"), "", "Stream Deck cannot switch to external scene paths")
	t.assert_equal(StreamDeck.safe_scene_path("res://main_scenes/main.tscn"), "res://main_scenes/main.tscn", "project scene paths are accepted")

func _test_ndi_geometry(t) -> void:
	t.assert_equal(NDIGeometry.normalize_edges([10, 20, 5, 30]), NDIGeometry.DEFAULT_EDGES, "inverted NDI crop rectangles use safe geometry")
	var automatic := NDIGeometry.calculate([0.0, 0.0, 100.0, 200.0], "auto", 512, 1, 1)
	t.assert_equal(automatic["viewport_size"], Vector2i(512, 1024), "automatic NDI output preserves crop aspect ratio")
	t.assert_approx(automatic["zoom"], 5.12, 0.001, "automatic NDI zoom fits the entire crop")
	var manual := NDIGeometry.calculate([0.0, 0.0, 100.0, 200.0], "manual", 512, 10, 9000)
	t.assert_equal(manual["viewport_size"], Vector2i(64, 8192), "manual NDI output is clamped to supported dimensions")
	t.assert_approx(manual["zoom"], 0.64, 0.001, "manual NDI zoom uses the limiting output axis")

func _test_integration_lifecycles(t) -> void:
	var source_root := _source_root()
	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var ndi_source := FileAccess.get_file_as_string(source_root.path_join("ndi/ndi_output_manager.gd"))
	var streamdeck_source := FileAccess.get_file_as_string(source_root.path_join("addons/godot-streamdeck-addon/singleton.gd"))
	t.assert_true(main_source.contains("_shutdown_import_workers()"), "main explicitly shuts down import workers")
	t.assert_true(main_source.contains("worker.wait_to_finish()"), "main joins import workers before scene teardown")
	t.assert_true(ndi_source.contains("size_changed.disconnect"), "NDI manager disconnects its root viewport signal")
	t.assert_true(ndi_source.contains("_destroy_ndi_pipeline(true)"), "NDI manager performs deterministic shutdown cleanup")
	t.assert_true(ndi_source.contains("if immediate:\n\t\tndi_viewport = null"), "NDI shutdown leaves scene-owned containers to recursive teardown")
	t.assert_true(ndi_source.contains("add_child(crop_box)"), "NDI manager owns the crop-box lifecycle")
	t.assert_true(streamdeck_source.contains("_socket.close"), "Stream Deck websocket closes during shutdown")
	t.assert_true(streamdeck_source.contains("set_process(false)"), "disabled or disconnected Stream Deck integration stops polling")

func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
