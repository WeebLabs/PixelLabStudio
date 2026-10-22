class_name ViewportController
extends RefCounted

# A resize counts as over once the size has held still this long; until then
# motion runs on MotionTiming.RESIZE_MAX_STEP. Counted in time, not frames: a
# drag-resize delivers sizes in uneven bursts with gaps of several frames.
const RESIZE_SETTLE_MSEC := 300
const MIN_ZOOM_PERCENT := 10
const MAX_ZOOM_PERCENT := 400
const ZOOM_STEP_PERCENT := 10
const ZOOM_STEP := Vector2(0.1, 0.1)

var _main: Node2D = null
var _global: Node = null
var _saving: Node = null
var _panning := false
var _pan_offset := Vector2.ZERO
var _last_resize_msec := 0
var _last_viewport_size := Vector2.ZERO
var _scale_percent := 100


func setup(main_node: Node2D, global_service: Node, saving_service: Node) -> void:
	_main = main_node
	_global = global_service
	_saving = saving_service
	_install_live_resize()


# A fast drag of the window edge starves Godot's own redraw timer on Windows, so
# the avatar froze mid-drag. The native WindowLiveResize hook
# (addons/window-live-resize) runs a frame on each size change instead. Looked up
# by name: only Windows exports ship the extension.
func _install_live_resize() -> void:
	if not ClassDB.class_exists("WindowLiveResize") or DisplayServer.get_name() != "Windows":
		return
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	ClassDB.class_call_static("WindowLiveResize", "install", handle)


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
		# Only the offset. process_frame() moves the camera from it every frame, so
		# a pan needs nothing else; it used to run the whole window-resize path
		# instead, re-laying out the right sidebar once per mouse-motion event
		# (3.3 ms on a 54-layer rig, several times per frame while dragging).
		_pan_offset -= event.relative / _main.camera.zoom


func window_size_changed() -> void:
	if not is_instance_valid(_main) or not _main.saveLoaded:
		return
	_saving.settings["windowSize"] = var_to_str(_main.get_window().size)
	var viewport_size := _main.get_viewport().get_visible_rect().size
	var before: Vector2 = _main.origin.global_position
	_main.origin.position = viewport_size * 0.5
	var moved: Vector2 = _main.origin.global_position - before
	if moved != Vector2.ZERO:
		for sprite in _global.sprite_nodes():
			if not sprite.is_queued_for_deletion():
				sprite.translate_world(moved)
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
	# The selection survives a page switch, so the editor comes back with the same
	# layer; its chrome is gated on the page (spriteObject._update_selection_gizmos).
	# What belongs to editing ends here.
	_global.end_edit_interactions()
	_main.editMode = not _main.editMode
	_global.notify_user("Toggled editing mode.")
	update_window_transparency()
	_main.editControls.set_process(_main.editMode)
	_main.editControls.visible = _main.editMode
	# Hiding a node does not stop its _process. Both sidebars and every layer row
	# live under EditControls, so on the player page they were re-syncing hidden
	# UI 60 times a second. Disabling the branch stops the whole subtree at once.
	_main.editControls.process_mode = (
		Node.PROCESS_MODE_INHERIT if _main.editMode else Node.PROCESS_MODE_DISABLED
	)
	set_layer_collision(_main.editMode)
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


# Click-to-select only runs in edit mode, so the layer grab shapes only need to
# be in the physics space there. Applied to every layer on each mode switch;
# layers built later pick the state up in spriteObject._build_collision.
func set_layer_collision(active: bool) -> void:
	if not is_instance_valid(_main) or _main.get_tree() == null:
		return
	for node in _global.sprite_nodes():
		if node.is_queued_for_deletion() or not node.has_method("setCollisionActive"):
			continue
		node.setCollisionActive(active)



func _update_resize_state() -> void:
	var viewport_size := _main.get_viewport().get_visible_rect().size
	var now := Time.get_ticks_msec()
	if viewport_size != _last_viewport_size:
		# The first size seen is the window opening, not a resize.
		var first := _last_viewport_size == Vector2.ZERO
		_last_viewport_size = viewport_size
		_last_resize_msec = now
		_main.resize_active = not first
		return
	# No snap on the way out: window_size_changed carried every layer's world-space
	# state along, so there is nothing stale to correct.
	if _main.resize_active and resize_settled(now, _last_resize_msec):
		_main.resize_active = false


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
	_global.notify_user("Set zoom to %d%%" % _scale_percent)
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


static func resize_settled(now_msec: int, last_resize_msec: int) -> bool:
	return now_msec - last_resize_msec >= RESIZE_SETTLE_MSEC


static func next_zoom_percent(current_percent: int, direction: int) -> int:
	return clampi(
		current_percent + signi(direction) * ZOOM_STEP_PERCENT,
		MIN_ZOOM_PERCENT,
		MAX_ZOOM_PERCENT,
	)
