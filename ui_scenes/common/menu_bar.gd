class_name AppMenuBar
extends Control

# Shared top menu bar. Both application modes build their bar from this one
# component, so the two can never drift apart visually.
#
# Layout is constructed, not placed. Three container zones:
#
#   left ──────────────── center ──────────────── right
#   pinned to the        centred on the          pinned to the
#   left edge            WINDOW                  right edge
#
# The center zone is centred against the bar itself, in its own CenterContainer
# spanning the full width, not shared between the side zones. Balancing it
# between them looks correct only while the two sides happen to be the same
# width: a heavy right zone silently drags the centre strip left. Items find
# their own position from their content, and the whole bar reflows on resize
# without a single hard-coded coordinate.
#
# Everything that goes on a bar is produced by the item factories below
# (`add_button`, `add_icon_button`, `add_separator`, `add_label`, `add_group`,
# `add_level_meter`).
# That is deliberate: styling lives here once instead of at every call site.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

# --- Chrome -----------------------------------------------------------------
const BAR_HEIGHT := SidebarUIFactory.MENU_BAR_HEIGHT
const BAR_COLOR := SidebarUIFactory.DEFAULT_PANEL_COLOR
const EDGE_MARGIN := 8.0
const ITEM_SEPARATION := 2
const GROUP_SEPARATION := 16
const FONT_SIZE := 14
const LABEL_FONT_SIZE := 12
const ITEM_PADDING := 6.0
# 16 logical px lands 1:1 on the 32px source art at 2x scaling, so bar icons
# stay crisp on a Retina display instead of being resampled.
const ICON_SIZE := 16.0

const COLOR_NORMAL := SidebarUIFactory.TEXT_BODY
const COLOR_HOVER := Color(1.0, 1.0, 1.0)
const COLOR_DISABLED := SidebarUIFactory.TEXT_DISABLED
const COLOR_DANGER := Color(0.9, 0.45, 0.5)
const COLOR_DANGER_HOVER := Color(1.0, 0.6, 0.65)
const COLOR_SEPARATOR := Color(0.4, 0.4, 0.45)
const COLOR_MUTED := Color(0.6, 0.6, 0.65)

# --- Level meter widget ------------------------------------------------------
# A live meter with a threshold marker riding on top of it, which is how the mic
# controls read: the bar shows the signal, the disc shows where it triggers.
# The thumb marks a threshold ON the meter behind it, so the fill edge and the
# grabber centre have to land on the same pixel for the same value. With
# center_grabber the grabber's CENTRE travels the slider's whole rect instead of
# stopping half a grabber short of each end, so the meter spans exactly that rect
# and the stack is widened to keep the visible track its full length. Measured
# from rendered pixels at 0.25 / 0.5 / 0.75 / 1.0: 0 px apart at every step,
# against 7 px at the top end when the meter spanned the stack.
const GRABBER_DIAMETER := 16
const GRABBER_RADIUS := 7
const METER_TRACK_WIDTH := 128.0
const METER_EDGE := float(GRABBER_RADIUS)
const METER_WIDTH := METER_TRACK_WIDTH + METER_EDGE * 2.0
const METER_HEIGHT := 8.0
const METER_TRACK_COLOR := Color(0.2, 0.2, 0.22)
const METER_CORNER_RADIUS := 3

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

# The item that yields when the bar runs out of room. See set_collapsible.
var collapsible: Control = null

var _background: ColorRect = null
var _row: HBoxContainer = null
var _center_holder: CenterContainer = null
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

	# Side zones ride a row pinned to both edges.
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_left = EDGE_MARGIN
	_row.offset_right = -EDGE_MARGIN
	_row.add_theme_constant_override("separation", 0)
	add_child(_row)

	left = _add_zone(_row, "Left", ITEM_SEPARATION)
	_row.add_child(_new_spacer())
	right = _add_zone(_row, "Right", GROUP_SEPARATION)

	# The center zone gets its own full-width container so it centres on the
	# window rather than on whatever space the side zones leave over. Added last
	# so it draws above them if a very narrow window forces an overlap.
	_center_holder = CenterContainer.new()
	_center_holder.name = "CenterHolder"
	_center_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_center_holder)
	center = _add_zone(_center_holder, "Center", GROUP_SEPARATION)

	for zone in [left, center, right]:
		zone.minimum_size_changed.connect(_apply_crowding)

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
	_apply_crowding()


# Nominate the one item that yields when the bar runs out of room. Which item is
# expendable is the bar owner's judgement, not the component's: the viewer bar
# gives up its mic meters so the buttons stay reachable. Bars that nominate
# nothing never collapse.
func set_collapsible(node: Control) -> void:
	collapsible = node
	_apply_crowding()


# Nothing warns when the centred strip runs into a side zone; they simply draw
# over each other. The measurement always counts the collapsible item as if it
# were showing, so hiding it cannot change the answer and the state cannot
# oscillate.
func _apply_crowding() -> void:
	if collapsible == null:
		return
	var hidden_width := 0.0
	if not collapsible.visible:
		hidden_width = collapsible.get_combined_minimum_size().x + GROUP_SEPARATION
	collapsible.visible = zones_fit(
		size.x,
		left.get_combined_minimum_size().x,
		center.get_combined_minimum_size().x,
		right.get_combined_minimum_size().x + hidden_width,
	)


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
	style.content_margin_left = ITEM_PADDING
	style.content_margin_right = ITEM_PADDING
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)

	button.set_meta("base_color", COLOR_DANGER if danger else COLOR_NORMAL)
	button.set_meta("hover_color", COLOR_DANGER_HOVER if danger else COLOR_HOVER)
	set_button_tone(button, button.get_meta("base_color"), button.get_meta("hover_color"))

	if callback.is_valid():
		button.pressed.connect(callback)
	zone.add_child(button)
	return button


# An icon in place of a label, for items whose symbol is clearer than their name.
# The artwork is expected to be a white silhouette: it is tinted with the same
# tones as the text buttons, so icon and text items light up alike on hover. A
# tooltip is required, since an icon alone does not say what it does.
func add_icon_button(
	zone: Container,
	icon: Texture2D,
	tooltip: String,
	callback: Callable,
) -> Button:
	var button := add_button(zone, "", callback)
	button.icon = icon
	button.tooltip_text = tooltip
	button.expand_icon = true
	# The button's own padding sits outside the icon, so add it back or the
	# artwork is squeezed into what is left of the minimum width.
	button.custom_minimum_size = Vector2(ICON_SIZE + ITEM_PADDING * 2.0, ICON_SIZE)
	# Project default is nearest-neighbour filtering, which frays a 32px glyph
	# scaled down to bar height.
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_button_tone(button, button.get_meta("base_color"), button.get_meta("hover_color"))
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
	# Span exactly the grabber's travel, so the fill edge and the thumb agree.
	meter.offset_left = METER_EDGE
	meter.offset_right = -METER_EDGE
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


# Recolor a button without rebuilding it (enable/disable, active states). Tones
# the icon alongside the text, so a text item and an icon item respond to the
# same states identically.
func set_button_tone(button: Button, color: Color, hover_color: Color) -> void:
	for state in ["font_color", "font_focus_color", "icon_normal_color", "icon_focus_color"]:
		button.add_theme_color_override(state, color)
	for state in ["font_hover_color", "font_pressed_color", "icon_hover_color", "icon_pressed_color"]:
		button.add_theme_color_override(state, hover_color)


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

# Whether the three zones clear each other. Because the centre strip is centred
# on the bar, the binding constraint is the WIDER side, not the sum: half the
# width left over by the centre has to clear it, plus the edge margin and a
# visible gap. Two zones of the same total width can therefore fit when balanced
# and collide when lopsided.
static func zones_fit(
	bar_width: float,
	left_width: float,
	center_width: float,
	right_width: float,
) -> bool:
	var half_gap := (bar_width - center_width) * 0.5
	return half_gap >= maxf(left_width, right_width) + EDGE_MARGIN + GROUP_SEPARATION


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

func _add_zone(parent: Container, zone_name: String, separation: int) -> HBoxContainer:
	var zone := HBoxContainer.new()
	zone.name = zone_name
	zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zone.add_theme_constant_override("separation", separation)
	parent.add_child(zone)
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
