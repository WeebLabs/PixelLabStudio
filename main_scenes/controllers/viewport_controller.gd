class_name ViewportController
extends RefCounted

const RESIZE_COOLDOWN_FRAMES := 5
const MIN_ZOOM_PERCENT := 10
const MAX_ZOOM_PERCENT := 400
const ZOOM_STEP_PERCENT := 10
const ZOOM_STEP := Vector2(0.1, 0.1)

var _main: Node2D = null
var _global: Node = null
var _saving: Node = null
var _panning := false
var _pan_offset := Vector2.ZERO
var _resize_cooldown := 0
var _last_viewport_size := Vector2.ZERO
var _scale_percent := 100


func setup(main_node: Node2D, global_service: Node, saving_service: Node) -> void:
	_main = main_node
	_global = global_service
	_saving = saving_service


func process_frame() -> void:
	if not is_instance_valid(_main):
		return
	_update_resize_state()
	_update_zoom_input()
	_main.camera.position = _main.origin.position + _pan_offset
	_follow_selection_shadow()


func handle_unhandled_input(event: InputEvent) -> void:
	if not is_instance_valid(_main):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = event.pressed
	elif event is InputEventMouseMotion and _panning:
		_pan_offset -= event.relative / _main.camera.zoom
		window_size_changed()


func window_size_changed() -> void:
	if not is_instance_valid(_main) or not _main.saveLoaded:
		return
	_saving.settings["windowSize"] = var_to_str(_main.get_window().size)
	var viewport_size := _main.get_viewport().get_visible_rect().size
	_main.origin.position = viewport_size * 0.5
	_main.lines.position = viewport_size * 0.5
	_main.lines.drawLine()
	_main.camera.position = _main.origin.position + _pan_offset
	# The viewer control panel sizes itself from the viewport and needs no
	# repositioning; the tutorial card is still pinned to the corner by hand.
	_main.tutorial.position = viewport_size
	_main.spriteList.position.y = _main.editControls.MENU_BAR_HEIGHT + 2
	_main.spriteList._apply_size()
	_main.pushUpdates.position = Vector2(0, viewport_size.y)


func update_window_transparency() -> void:
	if not is_instance_valid(_main):
		return
	var ndi_active: bool = _main.ndi_manager != null and _main.ndi_manager.is_enabled()
	if ndi_active and not _main.editMode:
		_main.get_viewport().transparent_bg = false
		_set_native_window_transparent(false)
		RenderingServer.set_default_clear_color(
			_global.backgroundColor if _global.backgroundColor.a != 0.0 else Color(0.3, 0.3, 0.3)
		)
	else:
		_main.get_viewport().transparent_bg = not _main.editMode
		if _global.backgroundColor.a != 0.0:
			_main.get_viewport().transparent_bg = false
		_set_native_window_transparent(_main.get_viewport().transparent_bg)
		RenderingServer.set_default_clear_color(_global.backgroundColor)


func swap_mode() -> void:
	if not is_instance_valid(_main):
		return
	_global.heldSprite = null
	_main.editMode = not _main.editMode
	_global.pushUpdate("Toggled editing mode.")
	update_window_transparency()
	_main.editControls.set_process(_main.editMode)
	_main.editControls.visible = _main.editMode
	_main.tutorial.visible = _main.editMode
	_main.controlPanel.set_active(not _main.editMode)
	_main.lines.visible = _main.editMode
	_main.spriteList.visible = _main.editMode
	_main.viewerArrows.visible = _main.editMode
	if _main.ndi_manager != null:
		_main.ndi_manager.set_crop_visible(_main.editMode and _main.ndi_manager.is_enabled())
	if _main._light_gizmo != null:
		_main._light_gizmo.queue_redraw()
	window_size_changed()


func scale_percent() -> int:
	return _scale_percent


func _update_resize_state() -> void:
	var viewport_size := _main.get_viewport().get_visible_rect().size
	if viewport_size != _last_viewport_size:
		_last_viewport_size = viewport_size
		_main.resize_active = true
		_resize_cooldown = RESIZE_COOLDOWN_FRAMES
		return
	if _resize_cooldown > 0:
		_resize_cooldown -= 1
		if _resize_cooldown == 0:
			_main.resize_active = false
			for sprite in _main.get_tree().get_nodes_in_group("saved"):
				sprite._force_drag_snap = true


func _update_zoom_input() -> void:
	if Input.is_action_pressed("control") and not _global.isMouseOverSidebar():
		if Input.is_action_just_pressed("scrollUp"):
			var upward_scale := next_zoom_percent(_scale_percent, 1)
			if upward_scale != _scale_percent:
				_main.camera.zoom += ZOOM_STEP * float(upward_scale - _scale_percent) / ZOOM_STEP_PERCENT
				_scale_percent = upward_scale
				_apply_zoom()
		if Input.is_action_just_pressed("scrollDown"):
			var downward_scale := next_zoom_percent(_scale_percent, -1)
			if downward_scale != _scale_percent:
				_main.camera.zoom += ZOOM_STEP * float(downward_scale - _scale_percent) / ZOOM_STEP_PERCENT
				_scale_percent = downward_scale
				_apply_zoom()


func _apply_zoom() -> void:
	_main.lines.scale = Vector2.ONE / _main.camera.zoom
	# The readout owns its own fade; this just says what to show.
	_main.controlPanel.show_zoom(_scale_percent)
	_global.pushUpdate("Set zoom to %d%%" % _scale_percent)
	window_size_changed()


func _follow_selection_shadow() -> void:
	_main.shadow.visible = is_instance_valid(_global.heldSprite)
	if not _main.shadow.visible:
		return
	_main.shadow.global_position = _global.heldSprite.sprite.global_position + Vector2(6, 6)
	_main.shadow.global_rotation = _global.heldSprite.sprite.global_rotation
	_main.shadow.offset = _global.heldSprite.sprite.offset
	_main.shadow.texture = _global.heldSprite.sprite.texture
	_main.shadow.hframes = _global.heldSprite.sprite.hframes
	_main.shadow.frame = _global.heldSprite.sprite.frame


func _set_native_window_transparent(want_transparent: bool) -> void:
	# Windows can leave the transparent viewport black if native transparency
	# is disabled at runtime, so only enable it there.
	if OS.get_name() == "Windows":
		if want_transparent and not _main.get_window().transparent:
			_main.get_window().transparent = true
		return
	if _main.get_window().transparent != want_transparent:
		_main.get_window().transparent = want_transparent


static func next_zoom_percent(current_percent: int, direction: int) -> int:
	return clampi(
		current_percent + signi(direction) * ZOOM_STEP_PERCENT,
		MIN_ZOOM_PERCENT,
		MAX_ZOOM_PERCENT,
	)
