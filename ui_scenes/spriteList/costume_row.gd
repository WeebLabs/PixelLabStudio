extends RefCounted

## The costume row under the layer list: ten numbered chips, one per costume.
##
## Drawn in code rather than from images, so the chips stay crisp at any size and
## take their colours from the shared palette. They replaced pixel-art SVGs that
## were rasterised at 64 px and scaled down to about 26, which blurred them.
##
## A chip shows whether the selected layer appears in that costume: pink (the
## slider fill) when it does, dark when it does not or a parent layer out of the
## costume hides it anyway. Numerals are bold, white with a pink outline on the
## pink chips and light on the dark ones. At the regular weight they read as thin. The costume the avatar is wearing carries a ring.
## With no layer selected every chip is dimmed and inert.

const SidebarUI = preload("res://ui_scenes/common/sidebar_ui.gd")

const COUNT := 10
const CHIP_SIZE := Vector2(26, 26)
const CHIP_GAP := 3
const CORNER_RADIUS := 5
const FONT_SIZE := 18
# The app's font, thickened: at this size the regular weight read as thin.
const FONT_EMBOLDEN := 0.9
const RING_WIDTH := 2
# White numerals on the light pink need an edge. A deep 0.62/0.28/0.42 at 4 px
# read as a black drop shadow, so this one is clearly pink and thinner.
const OUTLINE_SIZE := 3

const ON_FILL := SidebarUI.SLIDER_FILL_ENABLED
const ON_FILL_HOVER := Color(1.0, 0.8, 0.87)
const ON_TEXT := Color(1, 1, 1)
const ON_OUTLINE := Color(0.72, 0.31, 0.48)
const OFF_FILL := Color(0.26, 0.26, 0.29)
const OFF_FILL_HOVER := Color(0.33, 0.33, 0.36)
const OFF_TEXT := Color(0.85, 0.85, 0.9)
const DISABLED_FILL := Color(0.18, 0.18, 0.2)
const DISABLED_TEXT := SidebarUI.TEXT_DISABLED
const RING := Color(1, 1, 1, 0.9)

enum State { DISABLED, OFF, ON }

var section: Control = null
var _buttons: Array[Button] = []
# The last look applied to each chip, so a steady row is not restyled every frame.
var _applied: Array = []
var _states: Array = []
var _worn := -1


func build(owner: Node, on_pressed: Callable) -> Control:
	var bold := FontVariation.new()
	bold.base_font = ThemeDB.fallback_font
	bold.variation_embolden = FONT_EMBOLDEN
	# The chips are placed by hand, not by a box container: a box shares spare
	# width out in whole pixels and drops the remainder, which left the last chip
	# a pixel short of the row's end. See _layout().
	section = Control.new()
	section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	section.custom_minimum_size = Vector2(
		COUNT * CHIP_SIZE.x + (COUNT - 1) * CHIP_GAP, CHIP_SIZE.y
	)
	section.resized.connect(_layout)
	owner.add_child(section)
	for i in COUNT:
		var chip := Button.new()
		chip.text = str(i + 1)
		chip.custom_minimum_size = CHIP_SIZE
		chip.focus_mode = Control.FOCUS_NONE
		chip.tooltip_text = "Costume %d" % (i + 1)
		chip.add_theme_font_override("font", bold)
		chip.add_theme_font_size_override("font_size", FONT_SIZE)
		chip.add_theme_constant_override("outline_size", OUTLINE_SIZE)
		chip.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		chip.pressed.connect(on_pressed.bind(i))
		# Styled at once: an unstyled button carries the default theme's padding,
		# and a control is never sized below its minimum, so a chip laid out
		# before its first sync came out larger than the rest.
		_style(chip, State.DISABLED, false)
		section.add_child(chip)
		_buttons.append(chip)
		_applied.append([State.DISABLED, false])
		_states.append(State.DISABLED)
	_layout()
	return section


# Edge to edge across the row: the first chip flush left, the last flush right,
# even gaps between, chips square. The gap is fractional and each position is
# rounded, so the ends land exactly on the row's edges at any width.
func _layout() -> void:
	var gap := maxf(CHIP_GAP, (section.size.x - COUNT * CHIP_SIZE.x) / (COUNT - 1))
	for i in _buttons.size():
		_buttons[i].position = Vector2(roundf(i * (CHIP_SIZE.x + gap)), 0)
		_buttons[i].size = CHIP_SIZE


# `in_costume` holds one bool per costume for the selected layer, or is empty when
# nothing is selected. `worn` is the index of the costume the avatar is wearing.
func sync(in_costume: Array, worn: int) -> void:
	var selected := not in_costume.is_empty()
	_worn = worn if selected else -1
	for i in COUNT:
		var state: int = State.DISABLED
		if selected:
			state = State.ON if in_costume[i] else State.OFF
		_states[i] = state
		var look := [state, i == _worn]
		if _applied[i] == look:
			continue
		_applied[i] = look
		_style(_buttons[i], state, i == _worn)


func state_of(index: int) -> int:
	return _states[index]


func worn_index() -> int:
	return _worn


func chip(index: int) -> Button:
	return _buttons[index]


func _style(chip: Button, state: int, worn: bool) -> void:
	chip.disabled = state == State.DISABLED
	var fill := ON_FILL if state == State.ON else OFF_FILL
	var hover := ON_FILL_HOVER if state == State.ON else OFF_FILL_HOVER
	var text := ON_TEXT if state == State.ON else OFF_TEXT
	# Only the pink chips outline their numerals; a dark chip needs no edge.
	chip.add_theme_color_override("font_outline_color", ON_OUTLINE if state == State.ON else Color(0, 0, 0, 0))
	chip.add_theme_stylebox_override("normal", _box(fill, worn))
	chip.add_theme_stylebox_override("hover", _box(hover, worn))
	chip.add_theme_stylebox_override("pressed", _box(hover, worn))
	chip.add_theme_stylebox_override("hover_pressed", _box(hover, worn))
	chip.add_theme_stylebox_override("disabled", _box(DISABLED_FILL, false))
	for part in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		chip.add_theme_color_override(part, text)
	chip.add_theme_color_override("font_disabled_color", DISABLED_TEXT)


# No content margins, so the numeral and the ring never raise a chip's minimum
# size past CHIP_SIZE: left to default, a StyleBoxFlat pads by its border width,
# and the ring made the worn chip taller than the rest. The ring is drawn outside
# the chip, in an expand margin as wide as the border, so the fill keeps its full
# size instead of looking narrowed.
func _box(fill: Color, ring: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(CORNER_RADIUS)
	box.anti_aliasing = true
	box.set_content_margin_all(0)
	if ring:
		box.border_color = RING
		box.set_border_width_all(RING_WIDTH)
		box.set_expand_margin_all(RING_WIDTH)
		box.set_corner_radius_all(CORNER_RADIUS + RING_WIDTH)
	return box
