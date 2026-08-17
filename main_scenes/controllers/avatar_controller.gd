class_name AvatarController
extends Node

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")
const ValueCodec = preload("res://autoload/persistence/value_codec.gd")
const SpriteState = preload("res://autoload/domain/sprite_state.gd")
const SaveCoordinator = preload("res://main_scenes/controllers/save_controller.gd")
const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

var _main: Node2D
var _global: Node
var _saving: Node
var _undo: Node
var _sprite_scene: PackedScene
var _sprite_id_random := RandomNumberGenerator.new()

var _load_keys: Array = []
var _load_data_ref: Variant = null
var _load_results: Array = []
var _load_group_id := -1


func setup(main: Node2D, global: Node, saving: Node, undo: Node, sprite_scene: PackedScene) -> void:
	_main = main
	_global = global
	_saving = saving
	_undo = undo
	_sprite_scene = sprite_scene
	_sprite_id_random.randomize()
	if not _undo.state_restored.is_connected(on_state_restored):
		_undo.state_restored.connect(on_state_restored)


# UndoManager restores sprite state and then hands the scene consequences back
# here, so history carries no UI knowledge. Order matters: rebuild the scene,
# re-derive costume visibility, then refresh the sidebars.
func on_state_restored(scope: Dictionary) -> void:
	if not is_instance_valid(_main):
		return
	if scope.get("full_rebuild", false):
		_main._create_light_gizmo()
	_main.apply_light_snapshot(scope.get("light"))
	if scope.get("full_rebuild", false):
		change_costume(_main.costume)
		_global.spriteList.updateData()
		_main.onWindowSizeChange()
		return
	if scope.get("structure_changed", false):
		_global.spriteList.updateData()
	elif scope.get("hierarchy_changed", false):
		_global.spriteList.refreshHierarchy()
	if _global.heldSprite != null:
		_global.spriteEdit.setImage()


func shutdown() -> void:
	if _load_group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_load_group_id)
		_load_group_id = -1
	_load_keys.clear()
	_load_data_ref = null
	_load_results.clear()


func next_z_index() -> int:
	return _global.maximum_sprite_z() + 1


func next_sprite_id() -> int:
	var candidate := _sprite_id_random.randi()
	while _global.sprite_by_id(candidate) != null:
		candidate = _sprite_id_random.randi()
	return candidate


func add_image(path: String) -> void:
	MutationCommands.capture_bulk()
	var sprite = _sprite_scene.instantiate()
	sprite.path = path
	sprite.id = next_sprite_id()
	sprite.z = next_z_index()
	_main.origin.add_child(sprite)
	sprite.position = Vector2.ZERO
	_global.spriteList.updateData()
	_main.ndi_mark_dirty()
	_global.notify_user("Added new sprite.")


func add_image_from_data(image: Image, layer_name: String, canvas_position: Vector2):
	var sprite = _sprite_scene.instantiate()
	sprite.loadedImage = image
	sprite.path = "psd://" + layer_name
	sprite.id = next_sprite_id()
	_main.origin.add_child(sprite)
	sprite.position = canvas_position
	return sprite


func duplicate_selected() -> void:
	var source = _global.heldSprite
	if source == null:
		return
	MutationCommands.capture_bulk()
	var sprite = _sprite_scene.instantiate()
	SpriteState.copy_for_duplicate(source, sprite)
	sprite.id = next_sprite_id()
	# `_ready()` decides whether to start its legacy delayed-reparent coroutine
	# during add_child(), so this flag must be set before the node enters the tree.
	# The command reparents synchronously below.
	sprite._skip_ready_reparent = source.parentId != null and source.parentSprite != null
	_main.origin.add_child(sprite)
	if source.parentId != null and source.parentSprite != null:
		var new_parent = source.parentSprite
		sprite.reparent(new_parent.sprite, false)
		sprite.parentId = source.parentId
		sprite.parentSprite = new_parent
		sprite.position = source.position
	else:
		sprite.position = source.position
	_global.select_sprite(sprite)
	_global.spriteList.updateData()
	_global.notify_user("Duplicated sprite.")


func apply_replacement(matched: Array, new_items: Array, orphaned: Array, remove_orphans: bool) -> Dictionary:
	MutationCommands.capture_bulk()
	var replaced := 0
	var added := 0
	var removed := 0
	for entry in matched:
		entry["sprite"].replaceSpriteFromData(entry["image"], entry["name"])
		_undo.invalidate_image(entry["sprite"].id)
		replaced += 1
	for item in new_items:
		add_image_from_data(item["image"], item["name"], item["position"])
		added += 1
	if remove_orphans:
		for sprite in orphaned:
			if not is_instance_valid(sprite):
				continue
			if _global.heldSprite == sprite:
				_global.clear_selection()
			sprite.queue_free()
			removed += 1
	_global.spriteList.updateData()
	_main.ndi_mark_dirty()
	return {"replaced": replaced, "added": added, "removed": removed}


func change_costume(new_costume: int) -> void:
	_main.costume = new_costume
	_global.clear_selection()
	for sprite in _global.sprite_nodes():
		sprite.applyCostumeVisibility()
	_global.spriteEdit.layerSelected()
	_main.spriteList.updateAllVisible()
	if _main.bounceOnCostumeChange:
		_main.onSpeak()
	_main.ndi_mark_dirty()
	_global.notify_user("Change costume: " + str(new_costume))


func change_costume_from_device(costume_id: String) -> void:
	if not costume_id.is_valid_int():
		return
	var requested := costume_id.to_int()
	if requested >= 1 and requested <= 10:
		change_costume(requested)


func clear_avatar() -> void:
	MutationCommands.capture_bulk()
	_global.clear_selection()
	_main.origin.queue_free()
	var new_origin := Node2D.new()
	_main.get_node("OriginMotion").add_child(new_origin)
	_main.origin = new_origin
	_global.spriteList.updateData()
	_main.onWindowSizeChange()
	_main.ndi_mark_dirty()
	_global.notify_user("Cleared avatar.")


func reset_avatar() -> void:
	var path: Variant = _saving.settings["lastAvatar"]
	if path == null or String(path).is_empty():
		_global.notify_user("No avatar to reset.")
		return
	await load_avatar(String(path))
	_global.notify_user("Reset avatar to last saved state.")


func load_avatar(path: String) -> bool:
	var data: Variant = _saving.read_save(path)
	if data == null:
		_global.notify_user(_saving.last_error)
		return false
	MutationCommands.capture_bulk()

	_global.clear_selection()
	_main.origin.visible = false
	_main.origin.queue_free()
	var new_origin := Node2D.new()
	new_origin.position = _main.get_viewport().get_visible_rect().size * 0.5
	new_origin.visible = false
	new_origin.modulate = Color(0, 0, 0, 0)
	_main.get_node("OriginMotion").add_child(new_origin)
	_main.origin = new_origin

	_load_keys = []
	for key in data:
		var entry: Variant = data[key]
		if entry is Dictionary and entry.get("type") == "sprite":
			_load_keys.append(key)
	var load_total := _load_keys.size()
	_load_data_ref = data
	_load_results = []
	_load_results.resize(load_total)

	var load_dialog: ModalDialogUI = null
	if load_total > 0:
		_load_group_id = WorkerThreadPool.add_group_task(_load_worker_decode, load_total, -1, false, "Avatar load")
		if _load_group_id < 0:
			_global.notify_user("Avatar worker pool unavailable; using synchronous image setup.")
			for index in range(load_total):
				_load_worker_decode(index)
		var load_started := Time.get_ticks_msec()
		var last_bar_update := load_started
		while _load_group_id >= 0 and not WorkerThreadPool.is_group_task_completed(_load_group_id):
			await get_tree().process_frame
			var now := Time.get_ticks_msec()
			if load_dialog == null and now - load_started >= 200:
				load_dialog = _create_progress_dialog("Loading avatar...")
			if load_dialog != null and now - last_bar_update >= 100:
				last_bar_update = now
				var done := WorkerThreadPool.get_group_processed_element_count(_load_group_id)
				load_dialog.set_progress(float(done) / float(load_total))
		if _load_group_id >= 0:
			WorkerThreadPool.wait_for_group_task_completion(_load_group_id)
			_load_group_id = -1
		if load_dialog != null:
			load_dialog.set_progress(1.0)

	for index in range(load_total):
		var item = _load_keys[index]
		var sprite = _sprite_scene.instantiate()
		SpriteState.apply_before_ready(sprite, data[item])
		var result: Variant = _load_results[index] if index < _load_results.size() else null
		if result != null and result.get("ok", false):
			sprite.loadedImage = result["image"]
			sprite._prebuilt_pma_image = result["pma_image"]
			sprite._prebuilt_polygons = result["polygons"]
			if result.has("normal_image"):
				sprite.loadedNormalImage = result["normal_image"]
		else:
			if data[item].has("imageData"):
				sprite.loadedImageData = data[item]["imageData"]
			if data[item].has("normalImageData"):
				sprite.loadedNormalData = data[item]["normalImageData"]
		sprite._skip_ready_reparent = true
		_main.origin.add_child(sprite)
		sprite.position = ValueCodec.vector2_value(data[item]["pos"])
		sprite.set_process(false)

	_load_keys.clear()
	_load_data_ref = null
	_load_results.clear()

	for sprite in _global.sprite_nodes():
		if sprite.parentId != null:
			var parent_sprite = _global.sprite_by_id(sprite.parentId)
			if parent_sprite != null:
				sprite.reparent(parent_sprite.sprite, false)
				sprite.parentSprite = parent_sprite
				sprite.set_owner(parent_sprite.sprite)
				sprite._force_drag_snap = true
			else:
				sprite.parentId = null
				sprite.parentSprite = null
		if sprite.frames > 1:
			sprite.remakePolygon()
		sprite.set_process(true)

	_main._create_light_gizmo()
	if data.has("_light"):
		_main._apply_light_data(data["_light"])
	_global.eyeTrackingGloballyEnabled = bool(data.get("_eyeTrackingGloballyEnabled", true))
	_restore_crop(data)
	change_costume(1)
	if path != SaveCoordinator.SESSION_SAVE_PATH and not _saving.is_isolated_session():
		_saving.settings["lastAvatar"] = path
		_saving.write_settings(_saving.settingsPath)
	await _global.spriteList.updateData()
	_main.onWindowSizeChange()
	_assign_default_ndi_reference()
	if _main.ndi_manager != null:
		_main.ndi_manager.recalculate_now()
	if load_dialog != null:
		load_dialog.queue_free()
	_global.notify_user("Loaded avatar at: " + path)
	_main.origin.visible = true
	var fade := _main.create_tween()
	fade.tween_property(_main.origin, "modulate", Color(1, 1, 1, 1), 0.3)
	return true


func build_save_data() -> Dictionary:
	var data := {}
	var index := 0
	for child in _global.sprite_nodes():
		if child.type == "sprite":
			data[index] = SpriteState.capture_save(child)
			index += 1
	if _main._light_gizmo != null:
		data["_light"] = {
			"pos": var_to_str(_main._light_gizmo.position),
			"energy": _main._light_gizmo.light_energy,
			"color": var_to_str(_main._light_gizmo.light_color),
			"range": _main._light_gizmo.light_range,
			"enabled": _main._light_gizmo.light_enabled,
		}
	data["_eyeTrackingGloballyEnabled"] = _global.eyeTrackingGloballyEnabled
	data["_schemaVersion"] = AvatarSave.CURRENT_VERSION
	var crop: Array = _saving.settings.get("ndiCropRect", [-500.0, -800.0, 500.0, 200.0])
	data["_ndiCropRect"] = crop
	data["_ndiRulerY"] = float(crop[3])
	return data


func _load_worker_decode(index: int) -> void:
	var key = _load_keys[index]
	var item_data: Dictionary = _load_data_ref[key]
	var image := Image.new()
	var has_image := false
	if item_data.has("path") and image.load(item_data["path"]) == OK:
		has_image = true
	if not has_image and item_data.has("imageData"):
		has_image = image.load_png_from_buffer(Marshalls.base64_to_raw(item_data["imageData"])) == OK
	var result := {"ok": has_image}
	if has_image:
		var premultiplied := image.duplicate()
		premultiplied.premultiply_alpha()
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(image)
		result["image"] = image
		result["pma_image"] = premultiplied
		result["polygons"] = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()), 4.0)
		if item_data.has("normalImageData"):
			var normal := Image.new()
			if normal.load_png_from_buffer(Marshalls.base64_to_raw(item_data["normalImageData"])) == OK:
				result["normal_image"] = normal
	_load_results[index] = result


func _restore_crop(data: Dictionary) -> void:
	if data.has("_ndiCropRect"):
		var crop: Variant = data["_ndiCropRect"]
		if crop is Array and crop.size() == 4:
			_saving.settings["ndiCropRect"] = [float(crop[0]), float(crop[1]), float(crop[2]), float(crop[3])]
	elif data.has("_ndiRulerY"):
		var bottom := float(data["_ndiRulerY"])
		var current: Array = _saving.settings.get("ndiCropRect", [-500.0, bottom - 1000.0, 500.0, bottom])
		_saving.settings["ndiCropRect"] = [float(current[0]), minf(float(current[1]), bottom - 64.0), float(current[2]), bottom]


func _assign_default_ndi_reference() -> void:
	for sprite in _global.sprite_nodes():
		if sprite.ndiRefLayer:
			return
	for keyword in ["neck", "body"]:
		for sprite in _global.sprite_nodes():
			var filename: String = sprite.path.get_file().strip_edges().to_lower()
			while filename.contains("."):
				filename = filename.get_basename()
			if filename == keyword or filename.begins_with(keyword + " "):
				sprite.ndiRefLayer = true
				return


func _create_progress_dialog(status_text: String) -> ModalDialogUI:
	var dialog := ModalDialogUI.new()
	_main.get_node("UILayer").add_child(dialog)
	dialog.set_title(status_text)
	dialog.add_progress_bar()
	return dialog
