extends RefCounted
class_name AnimationClipPanel

# The left sidebar's "Animation" tab content: a list of animation clips with
# New/Remove, plus an inspector that edits the currently-selected clip. Operates
# on Global.heldSprite.animClips (an Array of clip Dictionaries — see
# effects/animation/layer_animator.gd for the schema and runtime).
#
# Rebuild strategy: a per-frame sync() recomputes a structural signature (sprite,
# clip count, selection, and the selected clip's channel/shape/trigger). When it
# changes, the list + inspector are rebuilt and the owner is asked to relayout.
# Otherwise sync() only refreshes live values (so undo of a slider edit shows up
# without rebuilding mid-drag). Value/name handlers just mutate the clip; the
# signature check picks up structural edits on the next frame.

const _CHANNELS := ["rotation", "translation"]
const _CHANNEL_LABELS := ["Rotation", "Translation"]
const _SHAPES := ["twitch", "oscillate"]
const _SHAPE_LABELS := ["Twitch (one-shot)", "Oscillate (loop)"]
const _TRIGGERS := ["always", "random", "key", "manual"]
const _TRIGGER_LABELS := ["Always", "Random", "Key press", "Manual / Test"]
const _CURVES := ["smooth", "ease", "snap", "spring", "pulse"]
const _CURVE_LABELS := ["Smooth", "Ease in-out", "Snap", "Spring", "Pulse"]

const _BODY := Color(0.75, 0.75, 0.8)
const _ACCENT := Color(1.0, 0.7, 0.8)

var _root: VBoxContainer
var _header_new: Button
var _header_remove: Button
var _list: VBoxContainer
var _inspector: VBoxContainer

var _fill_on: StyleBoxFlat
var _fill_off: StyleBoxFlat
var _grab_on: ImageTexture
var _grab_off: ImageTexture
var _relayout: Callable

var _selected: int = 0
var _last_sig: String = ""
# Per-frame value refresh targets, rebuilt with the inspector.
var _value_rows: Array = []   # [{slider, field, prefix, suffix, is_int, default}]
var _name_edit: LineEdit = null
var _bind_btn: Button = null

func build(fill_on: StyleBoxFlat, fill_off: StyleBoxFlat,
		grab_on: ImageTexture, grab_off: ImageTexture, relayout: Callable) -> Control:
	_fill_on = fill_on
	_fill_off = fill_off
	_grab_on = grab_on
	_grab_off = grab_off
	_relayout = relayout

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", Global.UI_ROW_GAP)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "Animations"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", _BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_header_new = _small_button("+ New", _on_new_pressed)
	header.add_child(_header_new)
	_header_remove = _small_button("Remove", _on_remove_pressed)
	header.add_child(_header_remove)
	_root.add_child(header)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_list)

	var div := ColorRect.new()
	div.color = Color(0.3, 0.3, 0.35)
	div.custom_minimum_size = Vector2(0, 1)
	div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(div)

	_inspector = VBoxContainer.new()
	_inspector.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(_inspector)

	return _root

# ----------------------------------------------------------------------------
# Per-frame sync
# ----------------------------------------------------------------------------

func sync() -> void:
	var spr = Global.heldSprite
	var has = spr != null
	_root.modulate = Color(1, 1, 1, 1) if has else Color(1, 1, 1, 0.35)
	_header_new.disabled = not has
	_header_remove.disabled = not has or spr.animClips.is_empty()

	if not has:
		if _last_sig != "":
			_clear(_list)
			_clear(_inspector)
			_value_rows.clear()
			_name_edit = null
			_bind_btn = null
			_last_sig = ""
			if _relayout.is_valid():
				_relayout.call()
		return

	var clips: Array = spr.animClips
	_selected = clampi(_selected, 0, max(0, clips.size() - 1))

	var sig := _struct_sig(spr, clips)
	if sig != _last_sig:
		_rebuild(clips)
		_last_sig = sig
		if _relayout.is_valid():
			_relayout.call()
	else:
		_refresh_values(clips)

func _struct_sig(spr, clips: Array) -> String:
	var s := str(spr.get_instance_id()) + "|" + str(clips.size()) + "|" + str(_selected)
	if _selected >= 0 and _selected < clips.size():
		var c: Dictionary = clips[_selected]
		s += "|" + str(c.get("channel", "")) + "|" + str(c.get("shape", "")) \
			+ "|" + str(c.get("trigger", "")) + "|" + str(c.get("curve", ""))
	return s

# Update live values without rebuilding (handles undo of slider/name edits).
func _refresh_values(clips: Array) -> void:
	for i in _list.get_child_count():
		if i < clips.size():
			(_list.get_child(i) as Button).text = _clip_label(clips[i])
	if _selected < 0 or _selected >= clips.size():
		return
	var c: Dictionary = clips[_selected]
	for row in _value_rows:
		var v = float(c.get(row.field, row.default))
		row.slider.set_value_no_signal(v)
		row.label.text = row.prefix + (str(int(v)) if row.is_int else str(snappedf(v, 0.001))) + row.suffix
	if _name_edit != null and not _name_edit.has_focus():
		_name_edit.text = str(c.get("name", ""))
	if _bind_btn != null:
		_bind_btn.text = _bind_label(c)

# ----------------------------------------------------------------------------
# Rebuild
# ----------------------------------------------------------------------------

func _rebuild(clips: Array) -> void:
	_clear(_list)
	_clear(_inspector)
	_value_rows.clear()
	_name_edit = null
	_bind_btn = null

	# Clip list
	for i in clips.size():
		var btn := Button.new()
		btn.text = _clip_label(clips[i])
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color", _ACCENT if i == _selected else _BODY)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func(): _select(idx))
		_list.add_child(btn)

	if clips.is_empty():
		var hint := Label.new()
		hint.text = "No animations. Press + New."
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		_list.add_child(hint)
		return

	if _selected < 0 or _selected >= clips.size():
		return
	_build_inspector(clips[_selected])

func _build_inspector(c: Dictionary) -> void:
	_name_edit = LineEdit.new()
	_name_edit.text = str(c.get("name", "Animation"))
	_name_edit.placeholder_text = "name"
	_name_edit.add_theme_font_size_override("font_size", 12)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t): _set_name(t))
	_inspector.add_child(_name_edit)

	var channel := String(c.get("channel", "rotation"))
	var shape := String(c.get("shape", "twitch"))

	_dropdown("Channel", _CHANNEL_LABELS, _CHANNELS, channel, "channel")
	_dropdown("Shape", _SHAPE_LABELS, _SHAPES, shape, "shape")

	# Motion parameters per channel + shape.
	if shape == "oscillate":
		if channel == "translation":
			_slider("x amplitude: ", "ampX", 0, 512, 1, true, " px", 0.0)
			_slider("x frequency: ", "freqX", 0, 0.5, 0.005, false, "", 0.0)
			_slider("y amplitude: ", "ampY", 0, 512, 1, true, " px", 0.0)
			_slider("y frequency: ", "freqY", 0, 0.5, 0.005, false, "", 0.0)
		else:
			_slider("amount: ", "amount", 0, 90, 1, false, "°", 10.0)
			_slider("frequency: ", "speed", 0, 0.5, 0.005, false, "", 0.05)
	else:
		if channel == "translation":
			_slider("amount: ", "amount", 0, 512, 1, true, " px", 30.0)
			_slider("direction x: ", "dirX", -1, 1, 0.05, false, "", 0.0)
			_slider("direction y: ", "dirY", -1, 1, 0.05, false, "", -1.0)
			_slider("speed: ", "speed", 0.2, 5, 0.05, false, "", 1.5)
		else:
			_slider("amount: ", "amount", 1, 90, 1, false, "°", 15.0)
			_slider("speed: ", "speed", 0.2, 5, 0.05, false, "", 1.5)

	# Curve picker (twitch only — oscillate is a sine wave).
	if shape == "twitch":
		_dropdown("Curve", _CURVE_LABELS, _CURVES, String(c.get("curve", "smooth")), "curve")

	# Live curve + progress preview: the dot rides the curve whenever the clip
	# plays (Test or an organic trigger). For oscillate it shows the sine cycling.
	var graph := AnimationCurveGraph.new()
	graph.configure(String(c.get("curve", "smooth")), shape, _selected)
	_inspector.add_child(graph)

	# Oscillate is continuous (always-on); only twitch has a trigger + Test.
	if shape == "twitch":
		_dropdown("Trigger", _TRIGGER_LABELS, _TRIGGERS, String(c.get("trigger", "random")), "trigger")
		var trig := String(c.get("trigger", "random"))
		if trig == "random":
			_slider("chance (1 in N/frame): ", "chance", 10, 600, 1, true, "", 200.0)
		elif trig == "key":
			_bind_btn = Button.new()
			_bind_btn.text = _bind_label(c)
			_bind_btn.add_theme_font_size_override("font_size", 12)
			_bind_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_bind_btn.pressed.connect(_on_bind_pressed)
			_inspector.add_child(_bind_btn)

		var test := Button.new()
		test.text = "▶ Test"
		test.add_theme_font_size_override("font_size", 12)
		test.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		test.pressed.connect(_on_test_pressed)
		_inspector.add_child(test)

func _on_test_pressed() -> void:
	if Global.heldSprite != null:
		Global.heldSprite.triggerAnimationClip(_selected)

# ----------------------------------------------------------------------------
# Control builders
# ----------------------------------------------------------------------------

func _slider(prefix: String, field: String, minv: float, maxv: float, step: float,
		is_int: bool, suffix: String, default: float) -> void:
	var c: Dictionary = Global.heldSprite.animClips[_selected]
	var v := float(c.get(field, default))
	var label := Label.new()
	label.text = prefix + (str(int(v)) if is_int else str(snappedf(v, 0.001))) + suffix
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _BODY)
	_inspector.add_child(label)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.set_value_no_signal(v)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.add_theme_stylebox_override("grabber_area", _fill_on)
	slider.add_theme_stylebox_override("grabber_area_highlight", _fill_on)
	slider.add_theme_icon_override("grabber", _grab_on)
	slider.add_theme_icon_override("grabber_highlight", _grab_on)
	slider.value_changed.connect(func(value): _set_value(field, value, is_int, label, prefix, suffix))
	_inspector.add_child(slider)

	_value_rows.append({"slider": slider, "label": label, "field": field,
		"prefix": prefix, "suffix": suffix, "is_int": is_int, "default": default})

func _dropdown(label_text: String, labels: Array, values: Array, current: String, field: String) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", _BODY)
	_inspector.add_child(label)

	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", 12)
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in labels.size():
		opt.add_item(labels[i], i)
	opt.select(maxi(0, values.find(current)))
	opt.item_selected.connect(func(idx): _set_choice(field, values[idx]))
	_inspector.add_child(opt)

func _small_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(cb)
	return b

# ----------------------------------------------------------------------------
# Handlers
# ----------------------------------------------------------------------------

func _select(i: int) -> void:
	_selected = i

func _set_value(field: String, value: float, is_int: bool, label: Label, prefix: String, suffix: String) -> void:
	var spr = Global.heldSprite
	if spr == null or _selected < 0 or _selected >= spr.animClips.size():
		return
	UndoManager.save_state_continuous()
	var v = int(value) if is_int else value
	spr.animClips[_selected][field] = v
	label.text = prefix + str(v) + suffix

func _set_choice(field: String, value) -> void:
	var spr = Global.heldSprite
	if spr == null or _selected < 0 or _selected >= spr.animClips.size():
		return
	UndoManager.save_state()
	spr.animClips[_selected][field] = value
	# Channel/shape/trigger change -> signature changes -> sync() rebuilds.

func _set_name(t: String) -> void:
	var spr = Global.heldSprite
	if spr == null or _selected < 0 or _selected >= spr.animClips.size():
		return
	spr.animClips[_selected]["name"] = t
	if _selected < _list.get_child_count():
		(_list.get_child(_selected) as Button).text = _clip_label(spr.animClips[_selected])

func _on_new_pressed() -> void:
	var spr = Global.heldSprite
	if spr == null:
		return
	UndoManager.save_state()
	spr.animClips.append(_new_clip())
	_selected = spr.animClips.size() - 1

func _on_remove_pressed() -> void:
	var spr = Global.heldSprite
	if spr == null or spr.animClips.is_empty():
		return
	UndoManager.save_state()
	spr.animClips.remove_at(clampi(_selected, 0, spr.animClips.size() - 1))
	_selected = clampi(_selected, 0, max(0, spr.animClips.size() - 1))

func _on_bind_pressed() -> void:
	var spr = Global.heldSprite
	if spr == null or _selected < 0 or _selected >= spr.animClips.size():
		return
	UndoManager.save_state()
	Global.awaitingAnimKeyBind = true
	Global.animKeyBindClip = spr.animClips[_selected]

func _new_clip() -> Dictionary:
	return {
		"name": "Twitch",
		"channel": "rotation",
		"shape": "twitch",
		"trigger": "random",
		"curve": "smooth",
		"amount": 15.0,
		"speed": 1.5,
		"chance": 200,
		"key": "",
		"dirX": 0.0, "dirY": -1.0,
		"ampX": 0.0, "freqX": 0.0, "ampY": 0.0, "freqY": 0.0,
	}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _clip_label(c: Dictionary) -> String:
	var nm := str(c.get("name", "Animation"))
	var ch := "rot" if String(c.get("channel", "rotation")) == "rotation" else "pos"
	var sh := String(c.get("shape", "twitch"))
	return "%s  (%s · %s)" % [nm, ch, sh]

func _bind_label(c: Dictionary) -> String:
	if Global.awaitingAnimKeyBind and Global.animKeyBindClip == c:
		return "Press a key…"
	var k := str(c.get("key", ""))
	return "Bind key: \"%s\"" % k if k != "" else "Bind key: (none)"

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
