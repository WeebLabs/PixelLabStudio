extends RefCounted

var _global: Node
var _undo_manager: Node
var _ignore_bounce: CheckBox
var _clip_linked: CheckBox
var _static_element: CheckBox
var _ndi_reference: CheckBox


func build(content: VBoxContainer, global: Node, undo_manager: Node) -> void:
	_global = global
	_undo_manager = undo_manager
	var color := Color(0.75, 0.75, 0.8)
	_ignore_bounce = _make_checkbox(content, "Ignore bounce velocity", _on_ignore_bounce_toggled, color)
	_clip_linked = _make_checkbox(content, "Clip linked sprites", _on_clip_linked_toggled, color)
	_static_element = _make_checkbox(content, "Static element", _on_static_toggled, color)
	_ndi_reference = _make_checkbox(content, "NDI reference layer", _on_ndi_reference_toggled, color)


func sync() -> void:
	var sprite = _global.heldSprite
	var has_selection := sprite != null
	for checkbox in _checkboxes():
		checkbox.disabled = not has_selection
	if not has_selection:
		for checkbox in _checkboxes():
			checkbox.set_pressed_no_signal(false)
		return
	_ignore_bounce.set_pressed_no_signal(sprite.ignoreBounce)
	_clip_linked.set_pressed_no_signal(sprite.clipped)
	_static_element.set_pressed_no_signal(sprite.staticElement)
	_ndi_reference.set_pressed_no_signal(sprite.ndiRefLayer)


func _make_checkbox(content: VBoxContainer, text: String, callback: Callable, color: Color) -> CheckBox:
	var checkbox := CheckBox.new()
	checkbox.text = text
	checkbox.add_theme_font_size_override("font_size", 12)
	checkbox.add_theme_color_override("font_color", color)
	checkbox.alignment = HORIZONTAL_ALIGNMENT_LEFT
	checkbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkbox.toggled.connect(callback)
	content.add_child(checkbox)
	return checkbox


func _checkboxes() -> Array:
	return [_ignore_bounce, _clip_linked, _static_element, _ndi_reference]


func _on_ignore_bounce_toggled(pressed: bool) -> void:
	if _global.heldSprite == null:
		return
	_undo_manager.save_state()
	_global.heldSprite.ignoreBounce = pressed


func _on_clip_linked_toggled(pressed: bool) -> void:
	if _global.heldSprite == null:
		return
	_undo_manager.save_state()
	_global.heldSprite.setClip(pressed)


func _on_static_toggled(pressed: bool) -> void:
	if _global.heldSprite == null:
		return
	_undo_manager.save_state()
	_global.heldSprite.staticElement = pressed
	if not pressed:
		_global.heldSprite._force_drag_snap = true


func _on_ndi_reference_toggled(pressed: bool) -> void:
	if _global.heldSprite == null:
		return
	_undo_manager.save_state()
	if pressed:
		for sprite in _global.sprite_nodes():
			if sprite != _global.heldSprite:
				sprite.ndiRefLayer = false
	_global.heldSprite.ndiRefLayer = pressed
	_global.main.ndi_mark_dirty()
