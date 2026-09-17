class_name AppTabBar
extends Control

# Reusable tab strip, shared by both sidebars and the settings panel: a row of
# evenly distributed flat buttons with a pink underline marking the active tab.
# Emits tab_changed(index) when the user picks a tab.
#
# Layout is rule-based. Buttons share the width equally via SIZE_EXPAND_FILL and
# the underline's target is (index / count), so the strip reflows correctly at
# any width. Picking a tab slides the underline to that target; a reflow or a
# programmatic restore snaps it. Palette comes from the shared UI factory: inactive flat-button
# grey, active brighter text, pink accent underline.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const MotionTiming = preload("res://autoload/domain/motion_timing.gd")

const BAR_HEIGHT := 26.0
const UNDERLINE_HEIGHT := 2.0
# Fraction of the remaining distance covered per 60 fps frame, and how close
# counts as arrived. Together they settle the slide in about 12 frames.
const SLIDE_WEIGHT := 0.25
const SLIDE_SNAP := 0.5
const _INACTIVE := Color(0.7, 0.7, 0.75)
const _ACTIVE := Color(1, 1, 1)
const _ACCENT := SidebarUIFactory.SLIDER_FILL_ENABLED

signal tab_changed(index: int)

var _row: HBoxContainer
var _underline: ColorRect
var _buttons: Array[Button] = []
var _active: int = 0
var _underline_x: float = 0.0
var _sliding: bool = false

func _ready() -> void:
	_ensure_built()
	# Owners that place the strip by hand call set_bar_size(); owners that put it
	# in a container get the same reflow from the container's own sizing.
	resized.connect(_layout)

# Built on demand rather than in _ready alone, so a caller may add tabs before
# the strip enters the tree without silently doing nothing.
func _ensure_built() -> void:
	if _row != null:
		return
	custom_minimum_size.y = BAR_HEIGHT

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)

	_underline = ColorRect.new()
	_underline.color = _ACCENT
	_underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_underline)

	# Defining _process turns processing on, so switch it off until a slide
	# actually needs it. An idle tab strip should cost nothing per frame.
	set_process(false)

# Add a tab button. Tabs are indexed in insertion order.
func add_tab(title: String) -> void:
	_ensure_built()
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
	var previous := _active
	_active = index
	_refresh_styles()
	# A tab the user picked slides; the owner's restore on startup snaps, so the
	# strip doesn't animate in from the first tab on every launch.
	_sliding = emit and previous != index
	set_process(_sliding)
	_layout()
	if emit:
		tab_changed.emit(index)

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
	var seg := _segment_width()
	_underline.size = Vector2(seg, UNDERLINE_HEIGHT)
	# A reflow is not a selection change, so the underline snaps to the active
	# tab unless a slide is already carrying it there.
	if not _sliding:
		_underline_x = _active * seg
	_underline.position = Vector2(_underline_x, BAR_HEIGHT - UNDERLINE_HEIGHT)


func _segment_width() -> float:
	return size.x / float(_buttons.size()) if not _buttons.is_empty() else 0.0


# The slide itself. Polled rather than tweened, in keeping with the rest of the
# app, and only while it has somewhere to go: _process switches itself off on
# arrival. The lerp weight goes through MotionTiming so the slide takes the same
# time whatever the frame rate, and the strip can be resized mid-slide because
# the target is recomputed from the current width each frame.
func _process(delta: float) -> void:
	var target := _active * _segment_width()
	_underline_x = lerpf(_underline_x, target, MotionTiming.smooth(SLIDE_WEIGHT, delta))
	if absf(target - _underline_x) < SLIDE_SNAP:
		_underline_x = target
		_sliding = false
		set_process(false)
	_underline.position.x = _underline_x
