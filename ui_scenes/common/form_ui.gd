class_name FormUI
extends RefCounted

# Labelled control rows in the application's design language. Panels declare
# what a setting is, not where it sits: every row is a container, so a form
# reflows at any width and nothing carries a hard-coded coordinate.
#
# Palette and primitives come from sidebar_ui.gd; this file only knows how a
# labelled row is put together. Add a row type here rather than hand-building
# one at a call site, so the forms cannot drift apart.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

const LABEL_FONT_SIZE := 12
const HEADING_FONT_SIZE := 12
const ROW_HEIGHT := 24.0
const ROW_SEPARATION := 8
const SECTION_SEPARATION := 10
const LABEL_WIDTH := 118.0
const CONTROL_HEIGHT := 22.0

const FIELD_BG := Color(0.1, 0.1, 0.1)
const FIELD_FOCUS_BORDER := Color(0.45, 0.45, 0.5)
const FIELD_CORNER_RADIUS := 3


# A vertical stack of rows. Use one per tab body or per titled group.
static func column(parent: Node, separation := ROW_SEPARATION) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	return box


# A titled group: a heading, a hairline, then the rows the caller adds to the
# returned column.
static func section(parent: Node, title: String) -> VBoxContainer:
	var group := column(parent, SECTION_SEPARATION)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", HEADING_FONT_SIZE)
	heading.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
	group.add_child(heading)

	var rule := ColorRect.new()
	rule.color = SidebarUIFactory.DEFAULT_DIVIDER_COLOR
	rule.custom_minimum_size = Vector2(0, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(rule)

	return column(group)


# One row: caption on the left at a fixed width, control filling the rest, so
# controls line up down the form without anyone positioning them.
static func row(parent: Node, caption: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", ROW_SEPARATION)
	line.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	parent.add_child(line)

	if not caption.is_empty():
		var label := Label.new()
		label.text = caption
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
		line.add_child(label)

	return line


# Caption, slider, and a live readout of the value. `format` receives the value
# and returns the readout text, so callers can say "Unlimited" or "1 in 200"
# without reaching back into the row.
static func slider_row(
	parent: Node,
	caption: String,
	minimum: float,
	maximum: float,
	step: float,
	slider_theme: Dictionary,
	format := Callable(),
) -> Dictionary:
	var line := row(parent, caption)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	SidebarUIFactory.apply_slider_theme(slider, slider_theme)
	line.add_child(slider)

	var readout := Label.new()
	readout.custom_minimum_size = Vector2(56, 0)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	readout.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
	line.add_child(readout)

	var write := func(value: float) -> void:
		readout.text = format.call(value) if format.is_valid() else str(int(value))
	slider.value_changed.connect(write)
	write.call(slider.value)

	return {"row": line, "slider": slider, "readout": readout, "refresh": write}


static func check_row(parent: Node, caption: String) -> CheckBox:
	var line := row(parent, caption)
	var check := CheckBox.new()
	check.focus_mode = Control.FOCUS_NONE
	check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	check.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	check.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	line.add_child(check)
	return check


static func option_row(parent: Node, caption: String, items: Array) -> OptionButton:
	var line := row(parent, caption)
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	option.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	option.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	for index in items.size():
		option.add_item(str(items[index]), index)
	line.add_child(option)
	return option


static func text_row(parent: Node, caption: String, placeholder: String) -> LineEdit:
	var line := row(parent, caption)
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	field.custom_minimum_size = Vector2(0, CONTROL_HEIGHT)
	field.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	apply_field_style(field)
	line.add_child(field)
	return field


static func spin_row(parent: Node, caption: String, minimum: float, maximum: float) -> Array:
	var line := row(parent, caption)
	var boxes: Array = []
	for axis in ["w", "h"]:
		var tag := Label.new()
		tag.text = axis
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
		tag.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
		line.add_child(tag)

		var spin := SpinBox.new()
		spin.min_value = minimum
		spin.max_value = maximum
		spin.step = 1
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(spin)
		boxes.append(spin)
	return boxes


# A flat text button sized for a form row, in the shared button styling.
static func button(parent: Node, text: String, callback: Callable, danger := false) -> Button:
	var action := Button.new()
	action.text = text
	action.flat = true
	action.focus_mode = Control.FOCUS_NONE
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	action.add_theme_font_size_override("font_size", LABEL_FONT_SIZE)
	action.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	action.add_theme_color_override(
		"font_hover_color", Color(0.9, 0.45, 0.5) if danger else Color(1, 1, 1)
	)
	if callback.is_valid():
		action.pressed.connect(callback)
	parent.add_child(action)
	return action


# The dark rounded field look shared by the layer filter and the text rows.
static func apply_field_style(field: Control) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = FIELD_BG
	normal.set_corner_radius_all(FIELD_CORNER_RADIUS)
	normal.set_content_margin_all(4)
	var focused := normal.duplicate()
	focused.border_color = FIELD_FOCUS_BORDER
	focused.set_border_width_all(1)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focused)
