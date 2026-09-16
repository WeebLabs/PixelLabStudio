extends RefCounted

## A "label  X [ ] Y [ ]" row of two numeric entries, for the left sidebar's
## position and origin-offset readouts.
##
## The readouts used to be plain labels, redrawn from the held layer every frame.
## They still are, except while a field has focus: whatever the user is typing is
## theirs until they commit it with Enter or by clicking away.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

const FIELD_WIDTH := 52.0
const FIELD_HEIGHT := 20.0
const FONT_SIZE := 12

signal committed(value: Vector2)

var row: HBoxContainer = null

var _x: LineEdit = null
var _y: LineEdit = null


func build(caption: String) -> HBoxContainer:
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	_x = _field("X")
	_y = _field("Y")
	return row


# Push the layer's value into the fields. Skipped for a field being typed in, so
# a per-frame refresh cannot overwrite a half-typed number.
func show_value(value: Vector2) -> void:
	if not _x.has_focus():
		_x.text = str(int(round(value.x)))
	if not _y.has_focus():
		_y.text = str(int(round(value.y)))


# No layer selected, or the selected layers disagree.
func show_text(text: String) -> void:
	if not _x.has_focus():
		_x.text = text
	if not _y.has_focus():
		_y.text = text


func set_enabled(enabled: bool) -> void:
	_x.editable = enabled
	_y.editable = enabled


func _field(placeholder: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.custom_minimum_size = Vector2(FIELD_WIDTH, FIELD_HEIGHT)
	field.add_theme_font_size_override("font_size", FONT_SIZE)
	# Enter applies the value and gives focus back. A field that keeps focus keeps
	# swallowing the keyboard: the app suppresses its shortcuts while a text field
	# is focused, so undo did nothing until the user clicked away.
	field.text_submitted.connect(func(_text: String):
		_commit()
		field.release_focus())
	field.focus_exited.connect(_commit)
	row.add_child(field)
	return field


# Both fields together, since a layer's position is one value. A field left
# unreadable (blank, or text) keeps whatever it had, so a stray keystroke and a
# click away cannot move a layer to zero.
func _commit() -> void:
	if not _x.text.is_valid_float() or not _y.text.is_valid_float():
		return
	committed.emit(Vector2(roundi(float(_x.text)), roundi(float(_y.text))))
