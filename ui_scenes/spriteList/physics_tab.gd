extends RefCounted
class_name WigglePhysicsTab

# Builds and drives the Physics tab in the right sidebar. Controls edit the
# selected layer's wiggle parameters (Global.heldSprite). Layout is fully
# container-based and reuses the sidebar's shared slider styling, so it matches
# the rest of the UI and reflows at any width. Future physics features can add
# their own grouped sections here without disturbing the wiggle controls.
#
# Per-layer scope, mirroring eye tracking: the enable checkbox is live whenever a
# layer is selected; every other control is live only while that layer's wiggle
# is on, so it's obvious what the knobs affect.

const _BODY := Color(0.75, 0.75, 0.8)
const _HEADER := Color(0.85, 0.85, 0.9)

var _content: VBoxContainer
var _fill_on: StyleBoxFlat
var _fill_off: StyleBoxFlat
var _grab_on: ImageTexture
var _grab_off: ImageTexture

var _cb_enabled: CheckBox
var _cb_children: CheckBox
var _cb_wag: CheckBox

var _edit_btn: Button
var _autofit_btn: Button
var _edit_box_idle: StyleBoxFlat
var _edit_box_hover: StyleBoxFlat
var _edit_box_active: StyleBoxFlat

# prop name -> { slider, label, prefix, suffix, is_int }
var _rows: Dictionary = {}
var _sliders: Array = []        # value sliders, for enable/disable styling
var _slider_state := true

func build(content: VBoxContainer, fill_on: StyleBoxFlat, fill_off: StyleBoxFlat,
		grab_on: ImageTexture, grab_off: ImageTexture) -> void:
	_content = content
	_fill_on = fill_on
	_fill_off = fill_off
	_grab_on = grab_on
	_grab_off = grab_off

	_cb_enabled = _checkbox("Wiggle this layer", _on_enabled_toggled)
	_cb_children = _checkbox("Linked layers follow", _on_children_toggled)

	_header("Ribbon")
	_build_ribbon_group()
	_slider("thickness", "wiggleThickness", 0.2, 3.0, 0.05, 1.0, "×", false)

	_header("Motion")
	_cb_wag = _checkbox("Auto-wag (waves on its own)", _on_wag_toggled)
	_slider("wag amount", "wiggleWagAmount", 0.0, 45.0, 0.5, 15.0, "°", false)
	_slider("wag speed", "wiggleWagSpeed", 0.02, 1.0, 0.01, 0.12, "", false)
	_slider("reactivity", "wiggleReactivity", 0.0, 3.0, 0.05, 1.0, "", false)
	_slider("motion intensity", "wiggleMotionIntensity", 0.0, 3.0, 0.05, 1.0, "×", false)

	_header("Feel")
	_slider("stiffness", "wiggleStiffness", 1.0, 60.0, 0.5, 20.0, "", false)
	_slider("damping", "wiggleDamping", 0.5, 20.0, 0.5, 5.0, "", false)
	_slider("springiness", "wiggleBendFocus", 0.0, 6.0, 0.1, 0.4, "", false)
	_slider("shape return", "wiggleShapeReturn", 0.0, 1.0, 0.02, 0.0, "", false)
	_slider("weight (droop)", "wiggleWeight", 0.0, 30.0, 0.5, 0.0, "", false)

	_header("Shape")
	_slider("resolution", "wiggleSegments", 4.0, 32.0, 1.0, 12.0, "", true)
	_slider("max bend", "wiggleMaxBend", 5.0, 90.0, 1.0, 25.0, "°", true)

# Refresh control states/values from the selected layer. Called per frame.
func sync() -> void:
	var spr = Global.heldSprite
	var has = spr != null
	var active = has and spr.wiggleEnabled

	_cb_enabled.disabled = not has
	_cb_children.disabled = not active
	_cb_wag.disabled = not active

	# Ribbon controls light up with the layer's wiggle; the Edit toggle reflects
	# whether the on-canvas path editor is currently open for this layer.
	_edit_btn.disabled = not active
	_autofit_btn.disabled = not active
	var editing = active and Global.wigglePathMode
	_edit_btn.text = "✓  Done editing" if editing else "✎  Edit ribbon path"
	_edit_btn.add_theme_stylebox_override("normal", _edit_box_active if editing else _edit_box_idle)
	_edit_btn.add_theme_color_override("font_color",
		Color(0.16, 0.1, 0.12) if editing else Color(1.0, 0.82, 0.88))
	if has:
		_cb_enabled.set_pressed_no_signal(spr.wiggleEnabled)
		_cb_children.set_pressed_no_signal(spr.wiggleChildrenFollow)
		_cb_wag.set_pressed_no_signal(spr.wiggleWagEnabled)
	else:
		_cb_enabled.set_pressed_no_signal(false)
		_cb_children.set_pressed_no_signal(false)
		_cb_wag.set_pressed_no_signal(false)

	for prop in _rows:
		var row = _rows[prop]
		row.slider.editable = active
		if has:
			row.slider.set_value_no_signal(spr.get(prop))
		_update_label(prop)

	# Auto-wag-only sliders do nothing unless auto-wag is on, so only show them then
	# (the Auto-wag checkbox itself stays). The container reflows to close the gap.
	var wag_on = active and spr.wiggleWagEnabled
	for prop in ["wiggleWagAmount", "wiggleWagSpeed"]:
		var row = _rows[prop]
		row.slider.visible = wag_on
		row.label.visible = wag_on

	if active != _slider_state:
		_slider_state = active
		var fill = _fill_on if active else _fill_off
		var grab = _grab_on if active else _grab_off
		for s in _sliders:
			s.add_theme_stylebox_override("grabber_area", fill)
			s.add_theme_stylebox_override("grabber_area_highlight", fill)
			s.add_theme_icon_override("grabber", grab)
			s.add_theme_icon_override("grabber_highlight", grab)

# --- builders ---

func _header(text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _HEADER)
	_content.add_child(label)

func _checkbox(text: String, on_toggled: Callable) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", 12)
	cb.add_theme_color_override("font_color", _BODY)
	cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.toggled.connect(on_toggled)
	_content.add_child(cb)
	return cb

func _slider(prefix: String, prop: String, minv: float, maxv: float, step: float,
		default: float, suffix: String, is_int: bool) -> void:
	var label = Label.new()
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _BODY)
	_content.add_child(label)

	var slider = HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = default
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 16)
	slider.add_theme_stylebox_override("grabber_area", _fill_on)
	slider.add_theme_stylebox_override("grabber_area_highlight", _fill_on)
	slider.add_theme_icon_override("grabber", _grab_on)
	slider.add_theme_icon_override("grabber_highlight", _grab_on)
	slider.add_theme_icon_override("grabber_disabled", _grab_off)
	slider.value_changed.connect(_on_slider_changed.bind(prop))
	_content.add_child(slider)
	Global.make_slider_resettable(slider, default)

	_sliders.append(slider)
	_rows[prop] = {"slider": slider, "label": label, "prefix": prefix,
		"suffix": suffix, "is_int": is_int}
	_update_label(prop)

# Ribbon-path controls: a primary "edit on canvas" toggle (filled accent box that
# lights up while active), a secondary auto-fit, and a one-line how-to hint. The
# thickness slider is added separately so it sits in the standard slider styling.
func _build_ribbon_group() -> void:
	_edit_box_idle = _box(Color(1.0, 0.7, 0.8, 0.16))
	_edit_box_hover = _box(Color(1.0, 0.7, 0.8, 0.26))
	_edit_box_active = _box(Color(1.0, 0.7, 0.8, 0.9))

	_edit_btn = Button.new()
	_edit_btn.text = "✎  Edit ribbon path"
	_edit_btn.add_theme_font_size_override("font_size", 12)
	_edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_btn.add_theme_stylebox_override("normal", _edit_box_idle)
	_edit_btn.add_theme_stylebox_override("hover", _edit_box_hover)
	_edit_btn.add_theme_stylebox_override("pressed", _edit_box_active)
	_edit_btn.add_theme_stylebox_override("disabled", _box(Color(0.3, 0.3, 0.32, 0.18)))
	_edit_btn.add_theme_color_override("font_color", Color(1.0, 0.82, 0.88))
	_edit_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_edit_btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.5, 0.52))
	_edit_btn.pressed.connect(_on_edit_path_pressed)
	_content.add_child(_edit_btn)

	_autofit_btn = Button.new()
	_autofit_btn.text = "Auto-fit to content"
	_autofit_btn.flat = true
	_autofit_btn.add_theme_font_size_override("font_size", 12)
	_autofit_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_autofit_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_autofit_btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
	_autofit_btn.pressed.connect(_on_autofit_pressed)
	_content.add_child(_autofit_btn)

	var hint = Label.new()
	hint.text = "Drag points to shape · drag amber grips to taper · click to add · right-click to remove · Esc when done"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(hint)

func _box(col: Color) -> StyleBoxFlat:
	var b = StyleBoxFlat.new()
	b.bg_color = col
	b.set_corner_radius_all(4)
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 5
	b.content_margin_bottom = 5
	return b

func _update_label(prop: String) -> void:
	var row = _rows[prop]
	var v = row.slider.value
	var shown = str(int(round(v))) if row.is_int else str(snappedf(v, 0.01))
	row.label.text = row.prefix + ": " + shown + row.suffix

# --- handlers ---

func _on_enabled_toggled(pressed: bool) -> void:
	if Global.heldSprite == null: return
	UndoManager.save_state()
	if not pressed:
		Global.wigglePathMode = false    # ribbon controls disable with wiggle
	Global.heldSprite.setWiggle(pressed)

func _on_children_toggled(pressed: bool) -> void:
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.setWiggleChildrenFollow(pressed)

func _on_wag_toggled(pressed: bool) -> void:
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.wiggleWagEnabled = pressed

func _on_edit_path_pressed() -> void:
	if Global.heldSprite == null: return
	Global.wigglePathMode = not Global.wigglePathMode
	Global.pushUpdate("Editing ribbon path." if Global.wigglePathMode else "Finished editing ribbon path.")

func _on_autofit_pressed() -> void:
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.wiggle_auto_fit_path()

func _on_slider_changed(value: float, prop: String) -> void:
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	Global.heldSprite.set(prop, value)
	# Thickness scales the captured band, so it needs a re-bake to take effect.
	if prop == "wiggleThickness":
		Global.heldSprite.apply_wiggle_path_changed()
	_update_label(prop)
