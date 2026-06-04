class_name BlendOpacitySection
extends RefCounted

# Per-layer Opacity + Blend on a single row, à la Photoshop / Affinity:
#   [ 100% ▾ ]  [ Blend dropdown .......... ]
# Opacity (left) is a compact editable text box ("100%") joined to a ▾ button that pops a
# horizontal slider flyout; together they read as one pill that shares the blend dropdown's
# themed background (field rounded-left, arrow rounded-right). The blend dropdown fills the
# rest of the row. Pinned to the bottom of the right sidebar's layer-list region by
# viewer.gd. build() constructs it; sync() tracks Global.heldSprite each frame.

const _BODY := Color(0.75, 0.75, 0.8)
const _DISABLED := Color(0.35, 0.35, 0.4)

var _root: VBoxContainer
var _opacity_wrap: HBoxContainer
var _opacity_edit: LineEdit
var _opacity_arrow: Button
var _opacity_popup: PopupPanel
var _opacity_slider: HSlider
var _blend_option: OptionButton

# Shared slider look (passed in from the sidebar so both sidebars stay identical).
var _fill_on: StyleBoxFlat
var _fill_off: StyleBoxFlat
var _grab_on: ImageTexture
var _grab_off: ImageTexture
var _slider_enabled := true

func build(parent: Node, fill_on: StyleBoxFlat, fill_off: StyleBoxFlat, grab_on: ImageTexture, grab_off: ImageTexture) -> VBoxContainer:
	_fill_on = fill_on
	_fill_off = fill_off
	_grab_on = grab_on
	_grab_off = grab_off

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	parent.add_child(_root)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(row)

	# --- Blend dropdown (right): fills the rest of the row. Built first so the opacity
	#     control can read and match its themed background colour. ---
	_blend_option = OptionButton.new()
	_blend_option.add_theme_font_size_override("font_size", 12)
	_blend_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_option.custom_minimum_size = Vector2(0, 22)
	for i in range(BlendMode.count()):
		_blend_option.add_item(BlendMode.display_name(i), i)  # item id == Mode int
	_blend_option.item_selected.connect(_on_blend_selected)
	row.add_child(_blend_option)

	# Exact match to the dropdown's background so the opacity control isn't darker.
	var match_color := Color(0.2, 0.2, 0.2)
	var ob_sb := _blend_option.get_theme_stylebox("normal")
	if ob_sb is StyleBoxFlat:
		match_color = (ob_sb as StyleBoxFlat).bg_color

	# --- Opacity (left): editable "100%" box + ▾ slider flyout. Inserted ahead of the dropdown. ---
	_opacity_wrap = HBoxContainer.new()
	_opacity_wrap.add_theme_constant_override("separation", 0)  # field + arrow touch → one pill
	row.add_child(_opacity_wrap)
	row.move_child(_opacity_wrap, 0)  # opacity on the left, blend fills the right

	_opacity_edit = LineEdit.new()
	_opacity_edit.text = "100%"
	_opacity_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER  # equal space left/right of "100%"
	_opacity_edit.add_theme_font_size_override("font_size", 12)
	_opacity_edit.custom_minimum_size = Vector2(36, 22)     # just wide enough for "100%"
	_opacity_edit.select_all_on_focus = true
	_opacity_edit.tooltip_text = "Layer opacity — type 0–100, or use the slider (▾)"
	# Box shares the dropdown's bg colour, rounded on the LEFT only so it meets the arrow as a pill.
	var box := StyleBoxFlat.new()
	box.bg_color = match_color
	box.corner_radius_top_left = 3
	box.corner_radius_bottom_left = 3
	box.content_margin_left = 3
	box.content_margin_right = 3
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	var box_focus := box.duplicate()
	box_focus.border_color = Color(0.45, 0.45, 0.5)
	box_focus.set_border_width_all(1)
	_opacity_edit.add_theme_stylebox_override("normal", box)
	_opacity_edit.add_theme_stylebox_override("focus", box_focus)
	_opacity_edit.text_submitted.connect(_on_opacity_text_submitted)
	_opacity_edit.focus_exited.connect(_commit_opacity_text)
	_opacity_wrap.add_child(_opacity_edit)

	# Arrow button — same bg colour as the field (so the pill is uniform), rounded on the RIGHT,
	# with hover/press lightening so it still reads as clickable.
	_opacity_arrow = Button.new()
	_opacity_arrow.text = "▾"
	_opacity_arrow.focus_mode = Control.FOCUS_NONE
	_opacity_arrow.add_theme_font_size_override("font_size", 13)
	_opacity_arrow.add_theme_color_override("font_color", _BODY)
	_opacity_arrow.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_opacity_arrow.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	_opacity_arrow.custom_minimum_size = Vector2(19, 22)
	_style_arrow_box("normal", match_color)
	_style_arrow_box("hover", match_color.lightened(0.12))
	_style_arrow_box("pressed", match_color.darkened(0.12))
	_style_arrow_box("disabled", match_color.darkened(0.25))
	_opacity_arrow.pressed.connect(_open_opacity_popup)
	_opacity_wrap.add_child(_opacity_arrow)

	# Horizontal slider flyout, shown under the field when ▾ is pressed.
	_opacity_popup = PopupPanel.new()
	parent.add_child(_opacity_popup)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.0
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.01
	_opacity_slider.value = 1.0
	_opacity_slider.custom_minimum_size = Vector2(150, 16)
	_opacity_slider.value_changed.connect(_on_opacity_slider_changed)
	_apply_slider_style(true)
	_opacity_popup.add_child(_opacity_slider)
	Global.make_slider_resettable(_opacity_slider, 1.0)  # double-click resets to fully opaque

	sync()
	return _root

# Build one arrow-button stylebox state: a filled box rounded on the right to match the field.
func _style_arrow_box(state: String, color: Color):
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	_opacity_arrow.add_theme_stylebox_override(state, sb)

func _on_blend_selected(idx: int):
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	Global.heldSprite.blendMode = idx
	Global.heldSprite.applyBlendMode()

func _open_opacity_popup():
	if Global.heldSprite == null:
		return
	_opacity_slider.set_value_no_signal(Global.heldSprite.opacity)
	var gr = _opacity_wrap.get_global_rect()
	var sz = Vector2i(170, 30)
	# Left-align the flyout under the opacity field (the field sits at the row's left edge).
	var pos = Vector2i(int(gr.position.x), int(gr.position.y + gr.size.y) + 2)
	_opacity_popup.popup(Rect2i(pos, sz))

func _on_opacity_slider_changed(value: float):
	if Global.heldSprite == null:
		return
	UndoManager.save_state_continuous()
	Global.heldSprite.opacity = value  # applied each frame via talkBlink()
	if not _opacity_edit.has_focus():
		_set_edit_text(value)

func _on_opacity_text_submitted(_t: String):
	_commit_opacity_text()
	_opacity_edit.release_focus()

# Parse the text box ("75", "75%", "75.5") → opacity; revert display on invalid. Only snapshots
# undo when the value actually changes, so tabbing out without an edit is free.
func _commit_opacity_text():
	if Global.heldSprite == null:
		return
	var raw = _opacity_edit.text.strip_edges().trim_suffix("%").strip_edges()
	if raw.is_valid_float():
		var newop = clampf(float(raw) / 100.0, 0.0, 1.0)
		if not is_equal_approx(newop, Global.heldSprite.opacity):
			UndoManager.save_state()
			Global.heldSprite.opacity = newop
	_refresh_opacity_display()

# Keep the controls in step with the selected layer; disabled + neutral when none.
func sync():
	var spr = Global.heldSprite
	var has = spr != null
	_blend_option.disabled = not has
	_opacity_edit.editable = has
	_opacity_arrow.disabled = not has
	_set_slider_enabled(has)
	_opacity_arrow.add_theme_color_override("font_color", _BODY if has else _DISABLED)
	if has:
		_blend_option.selected = spr.blendMode
		_refresh_opacity_display()
	elif not _opacity_edit.has_focus():
		_opacity_edit.text = "—"

# Push heldSprite.opacity into the text box (skipped while it's being typed in) and the slider.
func _refresh_opacity_display():
	if Global.heldSprite == null:
		return
	if not _opacity_edit.has_focus():
		_set_edit_text(Global.heldSprite.opacity)
	_opacity_slider.set_value_no_signal(Global.heldSprite.opacity)

func _set_edit_text(value: float):
	_opacity_edit.text = str(int(round(value * 100.0))) + "%"

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
