class_name ImportController
extends Node

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const PSDParserScript = preload("res://autoload/psd_parser.gd")
const APNGParserScript = preload("res://autoload/apng_parser.gd")
const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")
const ImportMatcher = preload("res://main_scenes/controllers/import_matcher.gd")
const LegacyCompat = preload("res://autoload/domain/legacy_canvas_compat.gd")
const LegacyReplacePrompt = preload("res://ui_scenes/psdImport/legacy_replace_prompt.gd")

var _main: Node2D
var _global: Node
var _undo: Node
var _avatar: Node
var _sprite_scene: PackedScene


func setup(main: Node2D, global: Node, undo: Node, avatar: Node, sprite_scene: PackedScene) -> void:
	_main = main
	_global = global
	_undo = undo
	_avatar = avatar
	_sprite_scene = sprite_scene


func process_frame(delta: float) -> void:
	_process_psd_thread(delta)
	_process_import_thread(delta)
	_process_anim_thread(delta)


func shutdown() -> void:
	if _psd_parser != null:
		_psd_parser.cancel()
	if _anim_parser != null and _anim_parser.has_method("cancel"):
		_anim_parser.cancel()
	for worker in [_psd_thread, _anim_thread]:
		if worker != null and worker.is_started():
			worker.wait_to_finish()
	if _import_group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_import_group_id)
		_import_group_id = -1
	_psd_thread = null
	_anim_thread = null
	_psd_parser = null
	_anim_parser = null
	_anim_queue.clear()


func is_import_dialog_open() -> bool:
	return _import_dialog != null and _import_dialog.visible


func is_replace_dialog_open() -> bool:
	if _layer_replace_dialog != null and _layer_replace_dialog.visible:
		return true
	return _replace_dialog != null and _replace_dialog.visible


func has_single_replace_dialog() -> bool:
	return _single_replace_dialog != null


func import_psd_file(path: String) -> void:
	_on_psd_dialog_file_selected(path)


func apply_psd_selection(selected_layers: Array, canvas_size: Vector2, normal_layers: Dictionary = {}) -> void:
	_on_psd_import_confirmed(selected_layers, canvas_size, normal_layers)


func cancel_psd_import() -> void:
	_on_psd_import_cancelled()


func show_import_dialog() -> void:
	open_import_dialog()


func show_replace_dialog() -> void:
	open_replace_dialog()


func apply_replace_review(matched: Array, new_items: Array, orphaned: Array, canvas_size: Vector2, remove_orphans: bool) -> void:
	_on_replace_confirmed(matched, new_items, orphaned, canvas_size, remove_orphans)


func cancel_replace_review() -> void:
	_on_replace_cancelled()


var _psd_parser = null
var _psd_thread: Thread = null
var _psd_result = null
var _psd_progress_dialog: ModalDialogUI = null
var _psd_replace_mode: bool = false

# Worker-pool sprite preparation (post-PSD-import)
var _import_group_id := -1
var _import_layers: Array = []
var _import_canvas_size: Vector2 = Vector2.ZERO
var _import_results: Array = []
var _import_normal_layers: Dictionary = {}
var _import_progress_dialog2: ModalDialogUI = null

var _anim_parser = null
var _anim_thread: Thread = null
var _anim_result = null
var _anim_progress_dialog: ModalDialogUI = null
var _anim_replace_mode: bool = false
var _anim_import_name: String = ""
var _anim_queue: Array = []

func _on_psd_dialog_file_selected(path):
	_begin_psd_parse(path, false)

func _begin_psd_parse(path: String, replace_mode: bool) -> void:
	if _psd_thread != null:
		_global.notify_user("A PSD import is already running.")
		return
	_psd_replace_mode = replace_mode
	_psd_parser = PSDParserScript.new()
	_psd_result = null

	# Show progress bar
	_psd_progress_dialog = _main._create_progress_dialog("Loading PSD...")

	# Run parser in a thread
	_psd_thread = Thread.new()
	var start_error := _psd_thread.start(func(): return _psd_parser.parse(path))
	if start_error != OK:
		_psd_thread = null
		_psd_parser = null
		_psd_progress_dialog.queue_free()
		_psd_progress_dialog = null
		_psd_replace_mode = false
		_global.notify_user("Could not start the PSD import worker.")
		_global.epicFail(start_error)

func _process_psd_thread(_delta):
	if _psd_thread == null or _psd_parser == null:
		return
	if _psd_progress_dialog == null:
		return

	# Update progress bar
	_psd_progress_dialog.set_progress(_psd_parser.progress)
	_psd_progress_dialog.set_title(_psd_parser.status_text)

	# Check if thread is done
	if !_psd_thread.is_alive():
		_psd_result = _psd_thread.wait_to_finish()
		_psd_thread = null

		# Remove progress dialog
		_psd_progress_dialog.queue_free()
		_psd_progress_dialog = null

		var result = _psd_result
		_psd_result = null
		_psd_parser = null

		if result.error != "":
			_psd_replace_mode = false
			if result.error != "Import cancelled.":
				_global.notify_user("PSD Error: " + result.error)
				_global.epicFail(ERR_INVALID_DATA)
			return

		if _psd_replace_mode:
			_psd_replace_mode = false
			_show_replace_review_from_psd(result)
		else:
			_main.psdImportDialog.setup(result)
			_main.psdImportDialog.visible = true

func _on_psd_import_confirmed(selected_layers: Array, canvas_size: Vector2, normal_layers: Dictionary = {}):
	_import_layers = selected_layers
	_import_canvas_size = canvas_size
	_import_normal_layers = normal_layers
	_import_results = []
	_import_results.resize(selected_layers.size())
	if selected_layers.is_empty():
		_import_layers = []
		_import_normal_layers = {}
		_global.notify_user("No PSD layers were selected.")
		return

	# Show progress dialog for sprite creation phase
	_import_progress_dialog2 = _main._create_progress_dialog("Processing sprites...")

	# Use the bounded engine pool instead of creating one OS thread per layer.
	_import_group_id = WorkerThreadPool.add_group_task(
		_precompute_import_layer, selected_layers.size(), -1, false, "PSD layer preparation"
	)
	if _import_group_id < 0:
		_import_progress_dialog2.queue_free()
		_import_progress_dialog2 = null
		_global.notify_user("Could not start the PSD processing worker.")
		_global.epicFail(ERR_CANT_CREATE)

func _precompute_import_layer(index: int) -> void:
	var image: Image = _import_layers[index].image
	var premultiplied := image.duplicate()
	premultiplied.premultiply_alpha()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image)
	_import_results[index] = {
		"pma_image": premultiplied,
		"polygons": bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()), 4.0),
	}

func _process_import_thread(_delta):
	if _import_group_id < 0:
		return

	# Update progress
	var count = _import_layers.size()
	if count > 0 and _import_progress_dialog2 != null:
		var completed := WorkerThreadPool.get_group_processed_element_count(_import_group_id)
		_import_progress_dialog2.set_progress(float(completed) / count)
		_import_progress_dialog2.set_title("Processing sprites... " + str(completed) + "/" + str(count))

	if WorkerThreadPool.is_group_task_completed(_import_group_id):
		WorkerThreadPool.wait_for_group_task_completion(_import_group_id)
		_import_group_id = -1

		if _import_progress_dialog2 != null:
			_import_progress_dialog2.queue_free()
			_import_progress_dialog2 = null

		_finalize_psd_import()

func _finalize_psd_import():
	MutationCommands.capture_bulk()
	var canvas_center = _import_canvas_size * 0.5
	var layer_z = _avatar.next_z_index()
	var count = _import_layers.size()

	for i in range(count):
		var layer = _import_layers[i]
		var result = _import_results[i]

		var id: int = int(_avatar.next_sprite_id())

		var sprite = _sprite_scene.instantiate()
		sprite.loadedImage = layer.image
		sprite.path = "psd://" + layer.name
		sprite.id = id
		sprite._prebuilt_pma_image = result["pma_image"]
		sprite._prebuilt_polygons = result["polygons"]
		sprite.z = layer_z

		var layer_center = Vector2(
			(layer.left + layer.right) * 0.5,
			(layer.top + layer.bottom) * 0.5
		)
		# Check for matching normal map layer
		var layer_base = layer.name.to_lower()
		if _import_normal_layers.has(layer_base):
			var nrml_layer = _import_normal_layers[layer_base]
			sprite.loadedNormalImage = nrml_layer.image
			sprite.normalPath = "psd://" + nrml_layer.name

		_main.origin.add_child(sprite)
		sprite.position = layer_center - canvas_center
		sprite.setZIndex()
		layer_z += 1

	_global.spriteList.updateData(true)
	_global.notify_user("Imported " + str(count) + " layers from PSD.")

	_import_layers = []
	_import_results = []
	_import_normal_layers = {}

	_save_post_import_snapshot()

func _on_psd_import_cancelled():
	if _psd_parser != null:
		_psd_parser.cancel()
	_global.notify_user("PSD import cancelled.")

func _save_post_import_snapshot():
	# Wait for the imported sprite instances' _ready() reparent timers (0.1s) to settle.
	await get_tree().create_timer(0.2).timeout
	MutationCommands.capture_bulk()

# --- Animated GIF/APNG Import ---

func _start_animated_import(path: String, is_replace: bool):
	if _anim_thread != null:
		_anim_queue.append({"path": path, "replace": is_replace})
		return

	_anim_replace_mode = is_replace
	_anim_result = null
	_anim_import_name = path.get_file().get_basename()

	_anim_parser = APNGParserScript.new()

	_anim_progress_dialog = _main._create_progress_dialog("Loading animated image...")

	_anim_thread = Thread.new()
	var start_error := _anim_thread.start(func(): return _anim_parser.parse(path))
	if start_error != OK:
		_anim_thread = null
		_anim_parser = null
		_anim_progress_dialog.queue_free()
		_anim_progress_dialog = null
		_global.notify_user("Could not start the animated-image worker.")
		_global.epicFail(start_error)
		_process_anim_queue()

func _process_anim_thread(_delta):
	if _anim_thread == null or _anim_parser == null:
		return
	if _anim_progress_dialog == null:
		return

	_anim_progress_dialog.set_progress(_anim_parser.progress)
	_anim_progress_dialog.set_title(_anim_parser.status_text)

	if !_anim_thread.is_alive():
		_anim_result = _anim_thread.wait_to_finish()
		_anim_thread = null

		_anim_progress_dialog.queue_free()
		_anim_progress_dialog = null

		var result = _anim_result
		_anim_result = null
		_anim_parser = null

		if result.error != "":
			if result.error != "Import cancelled.":
				_global.notify_user("Import Error: " + result.error)
				_global.epicFail(ERR_INVALID_DATA)
			_process_anim_queue()
			return

		_finish_animated_import(result)
		_process_anim_queue()

func _process_anim_queue():
	if _anim_queue.size() > 0:
		var next = _anim_queue.pop_front()
		_start_animated_import(next["path"], next["replace"])

func _finish_animated_import(result):
	var frame_count = result.frames.size()
	var w = result.width
	var h = result.height

	# Cap frame count if sprite sheet would exceed max texture size
	var max_width = 16384
	if w * frame_count > max_width:
		frame_count = max_width / w
		_global.notify_user("Warning: Capped to " + str(frame_count) + " frames (texture size limit)")

	# Single-frame: import as static sprite
	if frame_count <= 1:
		if _anim_replace_mode:
			_replace_with_animated(result.frames[0].image, 1, 0)
		else:
			_add_animated_sprite(result.frames[0].image, 1, 0)
		return

	# Build horizontal sprite sheet
	var sheet = Image.create(w * frame_count, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in range(frame_count):
		sheet.blit_rect(result.frames[i].image, Rect2i(0, 0, w, h), Vector2i(w * i, 0))

	# Calculate animation speed from average delay
	var total_delay: float = 0.0
	for i in range(frame_count):
		total_delay += result.frames[i].delay_ms
	var avg_delay_ms = total_delay / float(frame_count)
	var fps = 1000.0 / avg_delay_ms
	var anim_speed = int(round(fps * 6.0))
	if anim_speed <= 0:
		anim_speed = 60

	if _anim_replace_mode:
		_replace_with_animated(sheet, frame_count, anim_speed)
	else:
		_add_animated_sprite(sheet, frame_count, anim_speed)

func _add_animated_sprite(sheet: Image, frame_count: int, anim_speed: int):
	MutationCommands.capture_bulk()

	var id: int = int(_avatar.next_sprite_id())

	var sprite = _sprite_scene.instantiate()
	sprite.loadedImage = sheet
	sprite.path = "animated://" + _anim_import_name
	sprite.id = id
	sprite.frames = frame_count
	sprite.animSpeed = anim_speed
	sprite.z = _avatar.next_z_index()
	_main.origin.add_child(sprite)
	sprite.position = Vector2.ZERO

	_global.spriteList.updateData()
	_global.notify_user("Imported animated sprite (" + str(frame_count) + " frames)")

func _replace_with_animated(sheet: Image, frame_count: int, anim_speed: int):
	if _global.heldSprite == null:
		return

	MutationCommands.capture_bulk()

	_global.heldSprite.imageData = sheet
	var pma = sheet.duplicate()
	pma.premultiply_alpha()
	var texture = ImageTexture.create_from_image(pma)
	_global.heldSprite.tex = texture
	_global.heldSprite.sprite.texture = texture
	_global.heldSprite.path = "animated://import"
	_global.heldSprite.frames = frame_count
	_global.heldSprite.animSpeed = anim_speed
	_global.heldSprite.changeFrames()
	_global.heldSprite.remadePolygon = false
	_global.heldSprite.remakePolygon()

	_undo.invalidate_image(_global.heldSprite.id)
	_global.spriteList.updateData()
	_global.notify_user("Replaced with animated sprite (" + str(frame_count) + " frames)")

# --- Unified Import Dialog ---

var _import_dialog: FileDialog = null

func _create_import_dialog():
	_import_dialog = FileDialog.new()
	_import_dialog.title = "Import"
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.png;PNG Files", "*.psd;PSD Files"])
	_import_dialog.use_native_dialog = true
	_import_dialog.files_selected.connect(_on_import_files_selected)
	_main.add_child(_import_dialog)

func open_import_dialog():
	if _import_dialog == null:
		_create_import_dialog()
	_import_dialog.popup_centered(Vector2i(600, 400))

func _on_import_files_selected(paths: PackedStringArray):
	if paths.size() == 0:
		return

	var psd_paths: Array = []
	var png_paths: Array = []
	for p in paths:
		match p.get_extension().to_lower():
			"psd": psd_paths.append(p)
			"png": png_paths.append(p)

	if psd_paths.size() > 0 and png_paths.size() > 0:
		_global.notify_user("Cannot mix PSD and PNG files. Select one type.")
		return
	if psd_paths.size() > 1:
		_global.notify_user("Select only one PSD file at a time.")
		return

	if psd_paths.size() == 1:
		_on_psd_dialog_file_selected(psd_paths[0])
	else:
		_import_png_files(png_paths)

func _import_png_files(paths: Array):
	MutationCommands.capture_bulk()

	# Separate normal maps from diffuse files
	var diffuse_paths = []
	var normal_map = {}  # base_name (lower) -> normal_path
	for path in paths:
		var filename = path.get_file().get_basename()
		if filename.to_lower().ends_with("_nrml"):
			var base = filename.substr(0, filename.length() - 5)
			normal_map[base.to_lower()] = path
		else:
			diffuse_paths.append(path)

	var count = 0
	for path in diffuse_paths:
		if path.get_extension().to_lower() == "png" and APNGParserScript.is_apng(path):
			_start_animated_import(path, false)
		else:
			var id: int = int(_avatar.next_sprite_id())
			var sprite = _sprite_scene.instantiate()
			sprite.path = path
			sprite.id = id
			sprite.z = _avatar.next_z_index()

			# Check for matching normal map
			var diffuse_base = path.get_file().get_basename().to_lower()
			if normal_map.has(diffuse_base):
				var nrml_img = Image.new()
				if nrml_img.load(normal_map[diffuse_base]) == OK:
					sprite.loadedNormalImage = nrml_img
					sprite.normalPath = normal_map[diffuse_base]
				normal_map.erase(diffuse_base)

			_main.origin.add_child(sprite)
			sprite.position = Vector2.ZERO
		count += 1

	# Import remaining unmatched normals: try to pair with existing sprites
	for base in normal_map:
		var matched = false
		for spr in _global.sprite_nodes():
			var spr_base = spr.path.get_file().get_basename().to_lower()
			if spr_base == base:
				var nrml_img = Image.new()
				if nrml_img.load(normal_map[base]) == OK:
					spr.setNormalMap(nrml_img, normal_map[base])
					_undo.invalidate_normal(spr.id)
				matched = true
				break
		if !matched:
			_global.notify_user("No match for normal: " + normal_map[base].get_file())

	_global.spriteList.updateData()
	_main.ndi_mark_dirty()
	if count == 1:
		_global.notify_user("Added new sprite.")
	elif count > 1:
		_global.notify_user("Imported " + str(count) + " sprites.")
	_save_post_import_snapshot()


var _replace_dialog: FileDialog = null
# Non-zero only while a legacy full-canvas replacement is awaiting confirmation:
# the canvas size those layers were authored against.
var _replace_legacy_canvas: Vector2 = Vector2.ZERO
var _legacy_prompt: ModalDialogUI = null

# Replace one layer's artwork, from the layer's own context menu. The whole-rig
# Replace takes a PSD or a folder and matches layers by name; this one is aimed
# at a layer the user has already picked, so it offers image files only and hands
# straight to the single-image path. That path names and acts on the held layer,
# so the target is selected before the dialog opens.
func replace_layer(sprite) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	_global.select_sprite(sprite)
	if _global.spriteEdit != null:
		_global.spriteEdit.setImage()
	if _layer_replace_dialog == null:
		_layer_replace_dialog = FileDialog.new()
		_layer_replace_dialog.title = "Replace layer image"
		_layer_replace_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_layer_replace_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_layer_replace_dialog.filters = PackedStringArray(["*.png;PNG Files"])
		_layer_replace_dialog.use_native_dialog = true
		_layer_replace_dialog.file_selected.connect(_handle_replace_single_png)
		_main.add_child(_layer_replace_dialog)
	_layer_replace_dialog.popup_centered(Vector2i(600, 400))


func _create_replace_dialog():
	_replace_dialog = FileDialog.new()
	_replace_dialog.title = "Replace"
	_replace_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_replace_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_replace_dialog.filters = PackedStringArray(["*.psd;PSD Files", "*.png;PNG Files"])
	_replace_dialog.use_native_dialog = true
	_replace_dialog.file_selected.connect(_on_replace_file_selected)
	_main.add_child(_replace_dialog)

func open_replace_dialog():
	if _replace_dialog == null:
		_create_replace_dialog()
	_replace_dialog.popup_centered(Vector2i(600, 400))

func _on_replace_file_selected(path: String):
	if path.get_extension().to_lower() == "psd":
		_handle_replace_from_psd(path)
	elif path.get_extension().to_lower() == "png":
		_handle_replace_single_png(path)
	else:
		_global.notify_user("Unsupported file type: " + path.get_extension())

func _handle_replace_from_psd(path: String):
	_begin_psd_parse(path, true)

# Rigs imported before PSD support carry one full-canvas image per layer, and
# cropped PSD layers cannot replace those in place without recalculating where
# each one sat in the canvas. Detect that shape before the review dialog opens,
# because the answer changes what the replacement does to every matched layer.
func _show_replace_review_from_psd(psd_result):
	_close_legacy_prompt()
	var canvas_size := Vector2(psd_result.width, psd_result.height)
	var verdict := LegacyCompat.evaluate(_global.sprite_nodes(), canvas_size)

	if verdict["mismatch"]:
		_legacy_prompt = LegacyReplacePrompt.show_canvas_mismatch(
			_main.get_node("UILayer"), verdict["canvas"], canvas_size, _close_legacy_prompt
		)
		_global.notify_user("Replace cancelled: the PSD canvas does not match this avatar.")
		return

	if verdict["legacy"]:
		var rig_canvas: Vector2 = verdict["canvas"]
		_legacy_prompt = LegacyReplacePrompt.show_compat_prompt(
			_main.get_node("UILayer"),
			rig_canvas,
			canvas_size,
			int(verdict["layers"]),
			func(choice: String): _on_legacy_compat_choice(choice, psd_result, canvas_size, rig_canvas),
		)
		return

	_open_replace_review(psd_result, canvas_size, Vector2.ZERO)


func _on_legacy_compat_choice(choice: String, psd_result, canvas_size: Vector2, rig_canvas: Vector2) -> void:
	_close_legacy_prompt()
	match choice:
		LegacyReplacePrompt.CHOICE_COMPAT:
			_open_replace_review(psd_result, canvas_size, rig_canvas)
		LegacyReplacePrompt.CHOICE_PLAIN:
			_open_replace_review(psd_result, canvas_size, Vector2.ZERO)
		_:
			_global.notify_user("Replace cancelled.")


func _close_legacy_prompt() -> void:
	if is_instance_valid(_legacy_prompt):
		_legacy_prompt.queue_free()
	_legacy_prompt = null


func _open_replace_review(psd_result, canvas_size: Vector2, legacy_canvas: Vector2) -> void:
	_replace_legacy_canvas = legacy_canvas
	var items := ImportMatcher.items_from_psd(psd_result.layers, canvas_size)
	var review := ImportMatcher.match_items(_global.sprite_nodes(), items)
	_main.replaceReviewDialog.setup(review["matched"], review["new_items"], review["orphaned"], canvas_size)
	_main.replaceReviewDialog.visible = true

func _handle_replace_from_folder(folder_path: String):
	var items: Array = []
	var dir = DirAccess.open(folder_path)
	if dir == null:
		_global.notify_user("Cannot open folder: " + folder_path)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if !dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			var full_path = folder_path.path_join(file_name)
			var img = Image.new()
			if img.load(full_path) == OK:
				var name = file_name.substr(0, file_name.length() - file_name.get_extension().length() - 1)
				items.append({"name": name, "image": img, "position": Vector2.ZERO})
		file_name = dir.get_next()
	dir.list_dir_end()

	if items.size() == 0:
		_global.notify_user("No PNG files found in folder.")
		return

	_show_replace_review_from_items(items, Vector2.ZERO)

func _show_replace_review_from_items(items: Array, canvas_size: Vector2):
	_replace_legacy_canvas = Vector2.ZERO
	var review := ImportMatcher.match_items(_global.sprite_nodes(), items)
	_main.replaceReviewDialog.setup(review["matched"], review["new_items"], review["orphaned"], canvas_size)
	_main.replaceReviewDialog.visible = true

func _handle_replace_single_png(path: String):
	if _global.heldSprite == null:
		_global.notify_user("Select a sprite first to replace with a single PNG.")
		return

	# Check for APNG
	if APNGParserScript.is_apng(path):
		_start_animated_import(path, true)
		return

	# Show simple confirmation dialog
	# The prompt names the layer the way the layer list does, so a renamed layer
	# is recognisable in it.
	var sprite_name = _global.heldSprite.displayName()
	var file_name = path.get_file()
	_show_single_replace_confirm(path, sprite_name, file_name)

var _layer_replace_dialog: FileDialog = null
var _single_replace_dialog: Node2D = null
var _single_replace_path: String = ""
# The prompt names one layer, so it has to act on that layer. Reading the live
# selection when the button is pressed replaced whatever happened to be held by
# then, which is not what the user was asked to confirm.
var _single_replace_target = null

func _show_single_replace_confirm(path: String, sprite_name: String, file_name: String):
	_single_replace_path = path
	_single_replace_target = _global.heldSprite

	_single_replace_dialog = Node2D.new()
	_single_replace_dialog.z_index = 4095
	_single_replace_dialog.visibility_layer = 2
	_single_replace_dialog.position = _main.camera.position

	var blocker = Area2D.new()
	blocker.add_to_group("canvas_input_blocker")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	blocker.add_child(col)
	_single_replace_dialog.add_child(blocker)

	var bg = ColorRect.new()
	bg.position = Vector2(-180, -60)
	bg.size = Vector2(360, 120)
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_single_replace_dialog.add_child(bg)

	var label = Label.new()
	label.position = Vector2(-170, -50)
	label.size = Vector2(340, 48)
	label.text = "Replace \"" + sprite_name + "\" with \"" + file_name + "\"?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	_single_replace_dialog.add_child(label)

	var buttons = HBoxContainer.new()
	buttons.position = Vector2(-100, 10)
	buttons.size = Vector2(200, 40)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_single_replace_dialog.add_child(buttons)

	var replaceBtn = Button.new()
	replaceBtn.text = "Replace"
	replaceBtn.custom_minimum_size = Vector2(80, 32)
	replaceBtn.pressed.connect(_on_single_replace_confirmed)
	buttons.add_child(replaceBtn)

	var cancelBtn = Button.new()
	cancelBtn.text = "Cancel"
	cancelBtn.custom_minimum_size = Vector2(80, 32)
	cancelBtn.pressed.connect(_on_single_replace_cancelled)
	buttons.add_child(cancelBtn)

	_main.add_child(_single_replace_dialog)

func _on_single_replace_confirmed():
	if _single_replace_dialog != null:
		_single_replace_dialog.queue_free()
		_single_replace_dialog = null

	var target = _single_replace_target
	_single_replace_target = null
	if target == null or not is_instance_valid(target):
		_global.notify_user("The layer to replace is no longer in the rig.")
		return

	var path = _single_replace_path
	MutationCommands.capture_bulk()
	target.replaceSprite(path)
	_undo.invalidate_image(target.id)
	_global.spriteList.updateData()
	_global.notify_user("Replaced sprite with: " + path.get_file())

func _on_single_replace_cancelled():
	if _single_replace_dialog != null:
		_single_replace_dialog.queue_free()
		_single_replace_dialog = null
	_single_replace_target = null
	_global.notify_user("Replace cancelled.")

# --- Replace Review Dialog Handlers ---

func _on_replace_confirmed(matched: Array, new_items: Array, orphaned_sprites: Array, _canvas_size: Vector2, remove_orphans: bool):
	var legacy_canvas := _replace_legacy_canvas
	_replace_legacy_canvas = Vector2.ZERO
	# Every row can be unticked now. With nothing left to do, a replacement would
	# only record an empty history step.
	if matched.is_empty() and new_items.is_empty() and not (remove_orphans and not orphaned_sprites.is_empty()):
		_global.notify_user("Nothing selected to replace.")
		return
	var result: Dictionary = _avatar.apply_replacement(matched, new_items, orphaned_sprites, remove_orphans, legacy_canvas)
	var message := "Replaced " + str(result["replaced"]) + " layers"
	if result["added"] > 0:
		message += ", added " + str(result["added"]) + " new"
	if result["removed"] > 0:
		message += ", removed " + str(result["removed"]) + " orphaned"
	message += "."
	if legacy_canvas != Vector2.ZERO:
		message += " Placed against the original " + str(int(legacy_canvas.x)) + " x " + str(int(legacy_canvas.y)) + " canvas."
	_global.notify_user(message)

func _on_replace_cancelled():
	_replace_legacy_canvas = Vector2.ZERO
	_global.notify_user("Replace cancelled.")
