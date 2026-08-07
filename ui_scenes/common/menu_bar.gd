class_name AppMenuBar
extends Control

# Shared top menu bar. Both application modes build their bar from this one
# component, so the two can never drift apart visually.
#
# Layout is constructed, not placed: the bar is a full-width row holding three
# container zones (left / center / right) separated by expanding spacers. Items
# find their own position from their content, and the whole bar reflows on
# resize without a single hard-coded coordinate. A bar that fills only the
# center zone renders as one centered strip, which is how edit mode uses it.
#
# Everything that goes on a bar is produced by the item factories below
# (`add_button`, `add_separator`, `add_label`, `add_group`, `add_level_meter`).
# That is deliberate: styling lives here once instead of at every call site.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

# --- Chrome -----------------------------------------------------------------
const BAR_HEIGHT := SidebarUIFactory.MENU_BAR_HEIGHT
const BAR_COLOR := Color(0.15, 0.15, 0.15)
const EDGE_MARGIN := 8.0
const ITEM_SEPARATION := 2
const GROUP_SEPARATION := 16
const FONT_SIZE := 14
const LABEL_FONT_SIZE := 12

const COLOR_NORMAL := Color(0.75, 0.75, 0.8)
const COLOR_HOVER := Color(1.0, 1.0, 1.0)
const COLOR_DISABLED := Color(0.35, 0.35, 0.4)
const COLOR_DANGER := Color(0.9, 0.45, 0.5)
const COLOR_DANGER_HOVER := Color(1.0, 0.6, 0.65)
const COLOR_SEPARATOR := Color(0.4, 0.4, 0.45)
const COLOR_MUTED := Color(0.6, 0.6, 0.65)

# --- Level meter widget ------------------------------------------------------
# A live meter with a threshold marker riding on top of it, which is how the mic
# controls read: the bar shows the signal, the disc shows where it triggers.
const METER_WIDTH := 128.0
const METER_HEIGHT := 8.0
const METER_TRACK_COLOR := Color(0.2, 0.2, 0.22)
const METER_CORNER_RADIUS := 3
const GRABBER_DIAMETER := 16
const GRABBER_RADIUS := 7

# --- Popups ------------------------------------------------------------------
const POPUP_GAP := 4.0

# --- Auto reveal (viewer mode) ----------------------------------------------
# The bar hides off the top edge and slides back in when the cursor approaches.
# REVEAL_BAND_RATIO is the fraction of window height that arms the reveal;
# HIDE_BAND_RATIO is the (deliberately larger) fraction the cursor must leave
# before it slides away again, so it cannot flicker on the boundary. Both are
# clamped to a pixel range because "top eighth" is 135px on a 1080-tall window
# but only 37px on a small avatar window.
const REVEAL_BAND_RATIO := 0.125
const HIDE_BAND_RATIO := 0.180
const BAND_MIN_PX := 48.0
const BAND_MAX_PX := 160.0
const SLIDE_SPEED := 8.0

var left: HBoxContainer = null
var center: HBoxContainer = null
var right: HBoxContainer = null

var _background: ColorRect = null
var _row: HBoxContainer = null
var _auto_reveal := false
var _reveal := 1.0
var _pins := {}
var _grabber_texture: ImageTexture = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = BAR_COLOR
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = EDGE_MARGIN
	_row.offset_right = -EDGE_MARGIN
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)

	left = _add_zone("Left", ITEM_SEPARATION)
	_row.add_child(_new_spacer())
	center = _add_zone("Center", GROUP_SEPARATION)
	_row.add_child(_new_spacer())
	right = _add_zone("Right", GROUP_SEPARATION)

	get_window().size_changed.connect(_fit_to_viewport)
	set_process(_auto_reveal)
	_fit_to_viewport()


func _exit_tree() -> void:
	var window := get_window()
	if window != null and window.size_changed.is_connected(_fit_to_viewport):
		window.size_changed.disconnect(_fit_to_viewport)


# The bar spans the window and is placed by its own position, not by anchors: a
# Control parented to a Node2D inherits a zero-sized anchorable rect, so anchors
# would collapse it to its minimum width. Zones and background anchor normally
# inside it, because their parent is a Control.
func _fit_to_viewport() -> void:
	if not is_inside_tree():
		return
	size = Vector2(get_viewport().get_visible_rect().size.x, BAR_HEIGHT)
	position.x = 0.0
	_apply_reveal()


# --- Item factories ----------------------------------------------------------

func add_button(zone: Container, label: String, callback: Callable, danger := false) -> Button:
	var button := Button.new()
	button.text = label
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_constant_override("h_separation", 0)

	var style := StyleBoxEmpty.new()
	style.content_margin_left = 6
	style.content_margin_right = 6
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)

	button.set_meta("base_color", COLOR_DANGER if danger else COLOR_NORMAL)
	button.set_meta("hover_color", COLOR_DANGER_HOVER if danger else COLOR_HOVER)
	set_button_tone(button, button.get_meta("base_color"), button.get_meta("hover_color"))

	if callback.is_valid():
		button.pressed.connect(callback)
	zone.add_child(button)
	return button


func add_separator(zone: Container) -> Label:
	return add_label(zone, "|", COLOR_SEPARATOR)


func add_label(zone: Container, text: String, color := COLOR_NORMAL, font_size := FONT_SIZE) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	zone.add_child(label)
	return label


# A nested row, for items that read as one unit (a caption beside its meter).
func add_group(zone: Container, separation := ITEM_SEPARATION) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group.add_theme_constant_override("separation", separation)
	zone.add_child(group)
	return group


# Caption + live meter + threshold marker, returned as {"meter", "slider"}.
# `fill` colors the meter; the slider is drawn as a bare grabber so it reads as
# a marker sitting on the meter rather than a second track.
func add_level_meter(
	zone: Container,
	caption: String,
	fill: Color,
	meter_max: float,
	slider_max: float,
	slider_step: float,
) -> Dictionary:
	var group := add_group(zone, 6)
	add_label(group, caption, COLOR_MUTED, LABEL_FONT_SIZE)

	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.custom_minimum_size = Vector2(METER_WIDTH, GRABBER_DIAMETER)
	group.add_child(stack)

	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.max_value = meter_max
	meter.value = 0.0
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.anchor_right = 1.0
	meter.anchor_top = 0.5
	meter.anchor_bottom = 0.5
	meter.offset_top = -METER_HEIGHT * 0.5
	meter.offset_bottom = METER_HEIGHT * 0.5
	meter.add_theme_stylebox_override("background", _meter_box(METER_TRACK_COLOR))
	meter.add_theme_stylebox_override("fill", _meter_box(fill))
	stack.add_child(meter)

	var slider := HSlider.new()
	slider.max_value = slider_max
	slider.step = slider_step
	slider.scrollable = false
	slider.focus_mode = Control.FOCUS_NONE
	slider.anchor_right = 1.0
	slider.anchor_top = 0.5
	slider.anchor_bottom = 0.5
	# Inset by the grabber radius so the disc stops at each end of the meter
	# instead of overshooting it.
	slider.offset_left = GRABBER_RADIUS
	slider.offset_right = -GRABBER_RADIUS
	slider.offset_top = -GRABBER_DIAMETER * 0.5
	slider.offset_bottom = GRABBER_DIAMETER * 0.5
	var empty := StyleBoxEmpty.new()
	for part in ["slider", "grabber_area", "grabber_area_highlight"]:
		slider.add_theme_stylebox_override(part, empty)
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		slider.add_theme_icon_override(icon, _grabber())
	slider.add_theme_constant_override("center_grabber", 1)
	slider.add_theme_constant_override("grabber_offset", 0)
	stack.add_child(slider)

	return {"meter": meter, "slider": slider}


# Recolor a button without rebuilding it (enable/disable, active states).
func set_button_tone(button: Button, color: Color, hover_color: Color) -> void:
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_focus_color", color)


func set_button_enabled(button: Button, enabled: bool) -> void:
	button.disabled = not enabled
	if enabled:
		set_button_tone(button, button.get_meta("base_color"), button.get_meta("hover_color"))
	else:
		set_button_tone(button, COLOR_DISABLED, COLOR_DISABLED)


# --- Popups ------------------------------------------------------------------

# Hang a bar-owned popup from the item that opens it, clamped to the viewport.
# Every such popup is placed through here so their layout has one seam rather
# than a scattering of literals.
func anchor_popup(item: Control, popup: Node2D, popup_size: Vector2) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var bounds := viewport.get_visible_rect().size
	var x := clampf(
		item.global_position.x,
		EDGE_MARGIN,
		maxf(EDGE_MARGIN, bounds.x - popup_size.x - EDGE_MARGIN),
	)
	var y := clampf(BAR_HEIGHT + POPUP_GAP, 0.0, maxf(0.0, bounds.y - popup_size.y))
	popup.position = popup.get_parent().to_local(Vector2(x, y))


# --- Auto reveal --------------------------------------------------------------

# Off: the bar is permanently visible (edit mode). On: it hides off the top edge
# and slides in while the cursor is near the top of the window (viewer mode).
func configure_auto_reveal(enabled: bool) -> void:
	_auto_reveal = enabled
	_reveal = 0.0 if enabled else 1.0
	if is_node_ready():
		set_process(enabled)
		_apply_reveal()


# Hold the bar open for as long as `key` is pinned. Used while a bar popup is
# open or a slider is being dragged, when the cursor is legitimately outside the
# reveal band but the bar is still in use.
func set_pin(key: StringName, pinned: bool) -> void:
	if pinned:
		_pins[key] = true
	else:
		_pins.erase(key)


# How much of the bar is currently on screen. Canvas hit-testing uses this so a
# hidden bar does not steal clicks from the avatar underneath it.
func revealed_height() -> float:
	return BAR_HEIGHT * _reveal


func snap_hidden() -> void:
	if not _auto_reveal:
		return
	_reveal = 0.0
	_apply_reveal()


func _process(delta: float) -> void:
	_reveal = move_toward(_reveal, 1.0 if _wants_reveal() else 0.0, SLIDE_SPEED * delta)
	_apply_reveal()


func _wants_reveal() -> bool:
	if not _pins.is_empty():
		return true
	var viewport := get_viewport()
	if viewport == null:
		return false
	var bounds := viewport.get_visible_rect()
	var pointer := viewport.get_mouse_position()
	return should_reveal(_reveal > 0.0, bounds.has_point(pointer), pointer.y, bounds.size.y)


func _apply_reveal() -> void:
	position.y = -BAR_HEIGHT * (1.0 - _reveal)
	visible = _reveal > 0.0 or not _auto_reveal


# --- Pure helpers (unit tested) -----------------------------------------------

static func reveal_band(viewport_height: float, ratio: float) -> float:
	return clampf(viewport_height * ratio, BAND_MIN_PX, BAND_MAX_PX)


# Hysteresis: an armed bar keeps the wider hide band, so the cursor has to
# travel further to dismiss it than it did to summon it.
static func should_reveal(
	revealed: bool,
	pointer_inside: bool,
	pointer_y: float,
	viewport_height: float,
) -> bool:
	if not pointer_inside:
		return false
	var ratio := HIDE_BAND_RATIO if revealed else REVEAL_BAND_RATIO
	return pointer_y <= reveal_band(viewport_height, ratio)


# --- Construction helpers ------------------------------------------------------

func _add_zone(zone_name: String, separation: int) -> HBoxContainer:
	var zone := HBoxContainer.new()
	zone.name = zone_name
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zone.add_theme_constant_override("separation", separation)
	_row.add_child(zone)
	return zone


func _new_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _meter_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(METER_CORNER_RADIUS)
	return box


func _grabber() -> ImageTexture:
	if _grabber_texture == null:
		_grabber_texture = SidebarUIFactory.circle_texture(
			Color(1.0, 1.0, 1.0, 1.0), GRABBER_DIAMETER, GRABBER_RADIUS
		)
	return _grabber_texture
