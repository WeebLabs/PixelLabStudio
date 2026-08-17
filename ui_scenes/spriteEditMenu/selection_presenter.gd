extends RefCounted

var _global: Node
var _ui: Dictionary
var _normal_panel: RefCounted
var _preview_max_size: Vector2
var _rotation_target_size: float


func setup(
		global: Node,
		ui: Dictionary,
		normal_panel: RefCounted,
		preview_max_size: Vector2,
		rotation_target_size: float,
) -> void:
	_global = global
	_ui = ui
	_normal_panel = normal_panel
	_preview_max_size = preview_max_size
	_rotation_target_size = rotation_target_size


func sync() -> float:
	var sprite = _global.heldSprite
	if sprite == null:
		_clear()
		_normal_panel.sync()
		return 1.0
	var preview_scale := _update_preview(sprite)
	_update_parent(sprite)
	_update_rotation_preview(sprite)
	_sync_controls(sprite)
	sync_rotation_limits()
	for layer in _global.sprite_nodes():
		layer.applyCostumeVisibility()
	_normal_panel.sync()
	if _global.spriteList != null:
		_global.spriteList.updateControls()
		_global.spriteList.scroll_to_selected()
	return preview_scale


func sync_rotation_limits() -> void:
	if _global.heldSprite == null:
		return
	var sprite = _global.heldSprite
	_ui.rot_progress.value = sprite.rLimitMax - sprite.rLimitMin
	_ui.rot_progress.rotation_degrees = sprite.rLimitMin + 90
	_ui.rot_min_line.rotation_degrees = sprite.rLimitMin
	_ui.rot_max_line.rotation_degrees = sprite.rLimitMax


func _clear() -> void:
	_ui.preview.texture = null
	_ui.parent_label.text = ""
	_ui.position_label.text = ""
	_ui.offset_label.text = ""
	_ui.layer_label.text = ""
	_ui.drag_label.text = ""
	_ui.rot_display.texture = null
	_ui.rot_display.rotation_degrees = 0
	_ui.rot_pointer.rotation_degrees = 0
	_ui.rot_min_slider.set_value_no_signal(-180)
	_ui.rot_max_slider.set_value_no_signal(180)
	_ui.rot_min_label.text = "rotational limit min: -180"
	_ui.rot_max_label.text = "rotational limit max: 180"
	_ui.rot_progress.value = 360
	_ui.rot_progress.rotation_degrees = -90
	_ui.rot_min_line.rotation_degrees = -180
	_ui.rot_max_line.rotation_degrees = 180


func _update_preview(sprite) -> float:
	var image_size: Vector2i = sprite.imageData.get_size()
	var frame_width := int(image_size.x / sprite.frames)
	var frame_height := int(image_size.y)
	var used: Rect2i
	if sprite.frames <= 1:
		used = sprite.imageData.get_used_rect()
	else:
		used = sprite.imageData.get_region(Rect2i(0, 0, frame_width, frame_height)).get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var content_rect := Rect2(used)
		var atlas := AtlasTexture.new()
		atlas.atlas = sprite.tex
		atlas.region = content_rect
		_ui.preview.texture = atlas
		_ui.preview.hframes = 1
		return min(_preview_max_size.x / content_rect.size.x, _preview_max_size.y / content_rect.size.y)
	_ui.preview.texture = sprite.tex
	_ui.preview.hframes = sprite.frames
	return min(_preview_max_size.x / frame_width, _preview_max_size.y / frame_height)


func _update_parent(sprite) -> void:
	_ui.parent_label.text = "Root Element"
	if sprite.parentId == null:
		return
	var parent = _global.sprite_by_id(sprite.parentId)
	if is_instance_valid(parent):
		_ui.parent_label.text = "Parent: " + str(parent.path).get_file()


func _update_rotation_preview(sprite) -> void:
	_ui.rot_display.texture = sprite.tex
	_ui.rot_display.offset = sprite.offset
	var used: Rect2i = sprite.imageData.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var scale_factor: float = _rotation_target_size / float(max(used.size.x, used.size.y))
		_ui.rot_display.scale = Vector2(scale_factor, scale_factor)
	else:
		_ui.rot_display.scale = Vector2.ONE * (_rotation_target_size / sprite.imageData.get_size().y)


func _sync_controls(sprite) -> void:
	_ui.drag_label.text = "drag: " + str(sprite.dragSpeed)
	_ui.drag_slider.set_value_no_signal(sprite.dragSpeed)
	_ui.rdrag_label.text = "rotational drag: " + str(sprite.rdragStr)
	_ui.rdrag_slider.set_value_no_signal(sprite.rdragStr)
	_ui.rot_min_slider.set_value_no_signal(sprite.rLimitMin)
	_ui.rot_min_label.text = "rotational limit min: " + str(sprite.rLimitMin)
	_ui.rot_max_slider.set_value_no_signal(sprite.rLimitMax)
	_ui.rot_max_label.text = "rotational limit max: " + str(sprite.rLimitMax)
	_ui.squash_label.text = "squash: " + str(sprite.stretchAmount)
	_ui.squash_slider.set_value_no_signal(sprite.stretchAmount)
	_ui.anim_speed_label.text = "animation speed: " + str(sprite.animSpeed)
	_ui.anim_speed_slider.set_value_no_signal(sprite.animSpeed)
	_ui.anim_frames_label.text = "sprite frames: " + str(sprite.frames)
	_ui.anim_frames_slider.set_value_no_signal(sprite.frames)
