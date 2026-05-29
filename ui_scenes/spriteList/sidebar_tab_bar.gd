extends Control
class_name SidebarTabBar

# Reusable sidebar tab strip: a row of evenly-distributed flat buttons with a
# pink underline marking the active tab. Emits tab_changed(index) when the user
# picks a tab. Layout is rule-based — buttons share the width equally via
# SIZE_EXPAND_FILL and the underline is positioned by (index / count), so the
# strip reflows correctly at any sidebar width. Match the sidebar theme:
# inactive flat-button grey, active brighter text, pink accent underline.

signal tab_changed(index: int)

const BAR_HEIGHT := 26.0
const UNDERLINE_HEIGHT := 2.0
const _INACTIVE := Color(0.7, 0.7, 0.75)
const _ACTIVE := Color(1, 1, 1)
const _ACCENT := Color(1.0, 0.7, 0.8)

var _row: HBoxContainer
var _underline: ColorRect
var _buttons: Array[Button] = []
var _active: int = 0

func _ready() -> void:
	custom_minimum_size.y = BAR_HEIGHT

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_underline = ColorRect.new()
	_underline.color = _ACCENT
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_underline)

# Add a tab button. Tabs are indexed in insertion order.
func add_tab(title: String) -> void:
	var btn := Button.new()
	btn.text = title
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_color_override("font_color", _INACTIVE)
	btn.add_theme_color_override("font_hover_color", _ACTIVE)
	btn.add_theme_color_override("font_pressed_color", _ACTIVE)
	var idx := _buttons.size()
	btn.pressed.connect(func(): set_active(idx, true))
	_row.add_child(btn)
	_buttons.append(btn)
	_refresh_styles()

# Select a tab. Pass emit = true to fire tab_changed (button presses do; the
# owner's programmatic restore on startup passes false).
func set_active(index: int, emit: bool = false) -> void:
	if index < 0 or index >= _buttons.size():
		return
	_active = index
	_refresh_styles()
	_layout()
	if emit:
		tab_changed.emit(index)

func get_active() -> int:
	return _active

# Size the strip to a width and reflow. Called from the owner's layout pass.
func set_bar_size(width: float) -> void:
	size = Vector2(width, BAR_HEIGHT)
	_layout()

func _refresh_styles() -> void:
	for i in _buttons.size():
		_buttons[i].add_theme_color_override("font_color",
			_ACTIVE if i == _active else _INACTIVE)

func _layout() -> void:
	if _buttons.is_empty():
		return
	_row.position = Vector2.ZERO
	_row.size = Vector2(size.x, BAR_HEIGHT)
	var seg := size.x / float(_buttons.size())
	_underline.position = Vector2(_active * seg, BAR_HEIGHT - UNDERLINE_HEIGHT)
	_underline.size = Vector2(seg, UNDERLINE_HEIGHT)
