extends Node2D

# The on-canvas z-index entry overlay: a small panel with a numeric field that
# sets the selected layer's depth, with a confirm flash on each accepted value.
#
# This owns its own nodes, styling, tween, and hit test. `Global` keeps only the
# open/close/active surface it needs for input routing, so the state singleton
# no longer carries a UI widget's construction and theming.

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

# Half-extents of the panel, used for the click-outside-to-dismiss test.
const PANEL_HALF_WIDTH := 110.0
const PANEL_HALF_HEIGHT := 40.0

var _global: Node = null
var _input_field: LineEdit = null
var _style_normal: StyleBoxFlat = null
var _style_focus: StyleBoxFlat = null
var _flash_tween: Tween = null
var _active := false


func setup(global: Node) -> void:
	_global = global
	z_index = 4095
	visible = false
	_build()


func is_active() -> bool:
	return _active


# Position the panel near the bottom of the current view and take focus.
func open() -> void:
	var main = _global.main
	if _global.heldSprite == null or main == null:
		return
	var view_size: Vector2 = get_viewport().get_visible_rect().size / main.camera.zoom
	position = main.camera.position + Vector2(0, view_size.y * 0.5 - 80)
	visible = true
	_input_field.text = str(_global.heldSprite.z)
	_input_field.select_all()
	_input_field.grab_focus()
	_active = true


func close() -> void:
	visible = false
	if _input_field != null:
		_input_field.release_focus()
	_active = false


# True when a click at this global position lands outside the panel, which the
# input router treats as a dismissal.
func is_click_outside(global_point: Vector2) -> bool:
	var local := to_local(global_point)
	return absf(local.x) > PANEL_HALF_WIDTH or absf(local.y) > PANEL_HALF_HEIGHT


# Follow a selection change made while the overlay is open.
func sync_to_selection() -> void:
	if not _active or _global.heldSprite == null:
		return
	_input_field.text = str(_global.heldSprite.z)
	_input_field.grab_focus()
	_input_field.select_all()


func _build() -> void:
	var panel := Panel.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.13, 0.15, 0.97)
	panel_style.set_corner_radius_all(8)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 0.6)
	panel_style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(-110, -40)
	panel.size = Vector2(220, 80)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var title := Label.new()
	title.text = "Set Z-Index"
	title.position = Vector2(-100, -32)
	title.size = Vector2(200, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	add_child(title)

	_input_field = LineEdit.new()
	_input_field.position = Vector2(-90, -4)
	_input_field.size = Vector2(180, 32)
	_input_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input_field.add_theme_font_size_override("font_size", 16)
	_input_field.caret_blink = true
	_input_field.caret_blink_interval = 0.5

	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.08, 0.08, 0.08)
	_style_normal.set_corner_radius_all(4)
	_style_normal.content_margin_left = 8
	_style_normal.content_margin_right = 8
	_style_normal.content_margin_top = 4
	_style_normal.content_margin_bottom = 4
	_style_focus = _style_normal.duplicate()
	_style_focus.border_color = Color(0.45, 0.45, 0.5)
	_style_focus.set_border_width_all(1)
	_input_field.add_theme_stylebox_override("normal", _style_normal)
	_input_field.add_theme_stylebox_override("focus", _style_focus)

	_input_field.text_submitted.connect(func(_text): _apply())
	_input_field.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_apply())
	add_child(_input_field)


func _apply() -> void:
	var text: String = _input_field.text.strip_edges()
	var sprite = _global.heldSprite
	if sprite == null or not text.is_valid_int():
		return
	var requested := text.to_int()
	MutationCommands.structural(func():
		if sprite.z == requested:
			return false
		sprite.z = requested
		sprite.setZIndex()
		return true)
	_global.notify_user("Set z-index to " + str(sprite.z) + ".")
	if _global.spriteList != null:
		_global.spriteList.updateData()
	_input_field.select_all()
	_flash_confirm()


# Brief pink pulse on the field so an accepted value is visible without moving
# focus away from it.
func _flash_confirm() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var flash_style: StyleBoxFlat = _style_focus.duplicate()
	_input_field.add_theme_stylebox_override("normal", flash_style)
	_input_field.add_theme_stylebox_override("focus", flash_style)
	var background_from: Color = _style_focus.bg_color
	var background_peak := Color(0.22, 0.12, 0.15)
	var border_from: Color = _style_focus.border_color
	var border_peak := Color(1.0, 0.7, 0.8)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(t: float):
		flash_style.bg_color = background_from.lerp(background_peak, t)
		flash_style.border_color = border_from.lerp(border_peak, t)
	, 0.0, 1.0, 0.15)
	_flash_tween.tween_method(func(t: float):
		flash_style.bg_color = background_peak.lerp(background_from, t)
		flash_style.border_color = border_peak.lerp(border_from, t)
	, 0.0, 1.0, 0.35)
	_flash_tween.tween_callback(_reset_style)


func _reset_style() -> void:
	if _input_field != null:
		_input_field.add_theme_stylebox_override("normal", _style_normal)
		_input_field.add_theme_stylebox_override("focus", _style_focus)
