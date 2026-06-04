class_name BlendOpacitySection
extends RefCounted

# Per-layer Opacity + Blend controls. Built as a standalone strip that the right sidebar
# pins to the bottom of the layer-list region (just above the draggable divider), so it
# reads as part of the layer list — the way the filter field caps the top. Mirrors the
# module pattern of physics_tab.gd (WigglePhysicsTab): build() constructs the UI once,
# sync() keeps it in step with Global.heldSprite each frame.

const _BODY := Color(0.75, 0.75, 0.8)      # standard label
const _DISABLED := Color(0.35, 0.35, 0.4)  # label when no sprite selected
const _HEADING := Color(0.85, 0.85, 0.9)   # active readout

var _root: VBoxContainer
var _blend_label: Label
var _blend_option: OptionButton
var _opacity_label: Label
var _opacity_slider: HSlider
var _opacity_value: Label

# Shared slider look (passed in from the sidebar so both sidebars stay identical).
var _fill_on: StyleBoxFlat
var _fill_off: StyleBoxFlat
var _grab_on: ImageTexture
var _grab_off: ImageTexture
var _slider_enabled := true

# Build the section under `parent`; returns the root VBox so the sidebar can position it.
func build(parent: Node, fill_on: StyleBoxFlat, fill_off: StyleBoxFlat, grab_on: ImageTexture, grab_off: ImageTexture) -> VBoxContainer:
	_fill_on = fill_on
	_fill_off = fill_off
	_grab_on = grab_on
	_grab_off = grab_off

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	parent.add_child(_root)

	# Row: "Blend" + mode dropdown (all common Photoshop modes).
	var blend_row = HBoxContainer.new()
	blend_row.add_theme_constant_override("separation", 6)
	_root.add_child(blend_row)

	_blend_label = _make_label("Blend")
	blend_row.add_child(_blend_label)

	_blend_option = OptionButton.new()
	_blend_option.add_theme_font_size_override("font_size", 12)
	_blend_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_option.custom_minimum_size = Vector2(0, 22)
	for i in range(BlendMode.count()):
		_blend_option.add_item(BlendMode.display_name(i), i)  # item id == Mode int
	_blend_option.item_selected.connect(_on_blend_selected)
	blend_row.add_child(_blend_option)

	# Row: "Opacity" + slider + percentage readout.
	var op_row = HBoxContainer.new()
	op_row.add_theme_constant_override("separation", 6)
	_root.add_child(op_row)

	_opacity_label = _make_label("Opacity")
	op_row.add_child(_opacity_label)

	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.01
	_opacity_slider.value = 1.0
	_opacity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opacity_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_opacity_slider.custom_minimum_size = Vector2(0, 16)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	_apply_slider_style(true)
	op_row.add_child(_opacity_slider)
	Global.make_slider_resettable(_opacity_slider, 1.0)  # double-click resets to fully opaque

	_opacity_value = Label.new()
	_opacity_value.text = "100%"
	_opacity_value.add_theme_font_size_override("font_size", 12)
	_opacity_value.add_theme_color_override("font_color", _HEADING)
	_opacity_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_opacity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_opacity_value.custom_minimum_size = Vector2(36, 0)
	op_row.add_child(_opacity_value)

	sync()
	return _root

func _make_label(text: String) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", _BODY)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _on_blend_selected(idx: int):
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	Global.heldSprite.blendMode = idx
	Global.heldSprite.applyBlendMode()

func _on_opacity_changed(value: float):
	if Global.heldSprite == null:
		return
	UndoManager.save_state_continuous()
	Global.heldSprite.opacity = value  # applied each frame via talkBlink()
	_opacity_value.text = str(int(round(value * 100.0))) + "%"

# Keep the controls in step with the selected layer; disabled + neutral when none.
func sync():
	var spr = Global.heldSprite
	var has = spr != null
	_blend_option.disabled = not has
	_opacity_slider.editable = has
	_set_slider_enabled(has)
	_blend_label.add_theme_color_override("font_color", _BODY if has else _DISABLED)
	_opacity_label.add_theme_color_override("font_color", _BODY if has else _DISABLED)
	_opacity_value.add_theme_color_override("font_color", _HEADING if has else _DISABLED)
	if has:
		_blend_option.selected = spr.blendMode
		_opacity_slider.set_value_no_signal(spr.opacity)
		_opacity_value.text = str(int(round(spr.opacity * 100.0))) + "%"
	else:
		_blend_option.selected = 0
		_opacity_slider.set_value_no_signal(1.0)
		_opacity_value.text = "—"

# Swap the slider fill/grabber between enabled and disabled looks, only on change.
func _set_slider_enabled(on: bool):
	if on == _slider_enabled:
		return
	_slider_enabled = on
	_apply_slider_style(on)

func _apply_slider_style(on: bool):
	var fill = _fill_on if on else _fill_off
	var grab = _grab_on if on else _grab_off
	_opacity_slider.add_theme_stylebox_override("grabber_area", fill)
	_opacity_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	_opacity_slider.add_theme_icon_override("grabber", grab)
	_opacity_slider.add_theme_icon_override("grabber_highlight", grab)
	_opacity_slider.add_theme_icon_override("grabber_disabled", _grab_off)
