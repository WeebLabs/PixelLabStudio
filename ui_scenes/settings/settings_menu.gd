extends Node2D

# The settings panel. A fixed-size dropdown from the menu bar's Settings button,
# built entirely from the shared UI vocabulary: AppTabBar for the strip, FormUI
# for the labelled rows, SidebarUI for the palette. Nothing here carries a
# hard-coded child coordinate; every tab is a column of rows that reflows on its
# own.
#
# Tabs are declared in _TABS and built by the matching _build_* method. To add a
# setting, add a row to one of those methods. To add a category, add a tab.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const Form = preload("res://ui_scenes/common/form_ui.gd")

const PANEL_SIZE := Vector2(420, 380)
const PANEL_PADDING := 12
const PANEL_CORNER_RADIUS := 4
const _TABS := ["Audio", "Display", "Motion", "Hotkeys", "Output"]

const COSTUME_COUNT := 10
const NDI_WIDTHS := [512, 720, 1080, 1920]
const RECORDING_FORMATS := ["webm", "apng", "gif"]
const RECORDING_FORMAT_NAMES := ["Video (WebM)", "Animated PNG", "GIF"]
const RECORDING_FPS := [15, 30, 60]
const UNLIMITED_FPS := 241

const BACKGROUND_PRESETS := [
	{"name": "Transparent", "color": Color(0.0, 0.0, 0.0, 0.0)},
	{"name": "Green", "color": Color(0.0, 1.0, 0.0, 1.0)},
	{"name": "Blue", "color": Color(0.0, 0.0, 1.0, 1.0)},
	{"name": "Magenta", "color": Color(1.0, 0.0, 1.0, 1.0)},
]

# Read by main.gd: which costume slot is capturing a key, and whether the cursor
# is over the panel (so a keypress aimed at the panel is not eaten elsewhere).
var awaitingCostumeInput := -1
var hasMouse := false

var _panel: PanelContainer = null
var _tab_bar: AppTabBar = null
var _bodies: Array[VBoxContainer] = []
var _slider_theme: Dictionary = {}

# Audio
var _device_list: VBoxContainer = null
var _mute_check: CheckBox = null

# Display
var _color_picker: ColorPickerButton = null
var _filtering_check: CheckBox = null
var _fps_slider: HSlider = null

# Motion
var _bounce_force: HSlider = null
var _bounce_gravity: HSlider = null
var _costume_bounce_check: CheckBox = null
var _blink_speed: HSlider = null
var _blink_chance: HSlider = null

# Hotkeys
var _hotkey_buttons: Array[Button] = []

# Output
var _ndi_status: Label = null
var _ndi_toggle: CheckBox = null
var _ndi_width: OptionButton = null
var _ndi_mode: OptionButton = null
var _ndi_manual_row: HBoxContainer = null
var _ndi_manual_w: SpinBox = null
var _ndi_manual_h: SpinBox = null
var _ndi_source_name: LineEdit = null
var _recording_format: OptionButton = null
var _recording_fps: OptionButton = null


func _ready() -> void:
	_slider_theme = SidebarUIFactory.create_slider_theme()
	_build_panel()


func panel_size() -> Vector2:
	return PANEL_SIZE


# Pull every control back into line with current state. Called once at startup
# by main.gd and again each time the panel is opened.
func setvalues() -> void:
	_refresh_audio()
	_refresh_display()
	_refresh_motion()
	_refresh_hotkeys()
	_refresh_output()


func _process(_delta: float) -> void:
	hasMouse = visible and Rect2(Vector2.ZERO, PANEL_SIZE).has_point(
		to_local(get_global_mouse_position())
	)


# --- Frame ---------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.size = PANEL_SIZE
	_panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = SidebarUIFactory.DEFAULT_PANEL_COLOR
	style.border_color = SidebarUIFactory.DEFAULT_DIVIDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	style.set_content_margin_all(PANEL_PADDING)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)

	_tab_bar = AppTabBar.new()
	for title in _TABS:
		_tab_bar.add_tab(title)
	_tab_bar.tab_changed.connect(_show_tab)
	column.add_child(_tab_bar)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)

	for builder in [_build_audio, _build_display, _build_motion, _build_hotkeys, _build_output]:
		var body := Form.column(stack, Form.SECTION_SEPARATION)
		builder.call(body)
		_bodies.append(body)

	_show_tab(0)


func _show_tab(index: int) -> void:
	for i in _bodies.size():
		_bodies[i].visible = i == index


# --- Audio ---------------------------------------------------------------------

func _build_audio(body: VBoxContainer) -> void:
	var input_group := Form.section(body, "Input device")
	_device_list = Form.column(input_group, 2)

	var behaviour := Form.section(body, "Behaviour")
	_mute_check = Form.check_row(behaviour, "Mute microphone")
	_mute_check.toggled.connect(_on_mute_toggled)


func _refresh_audio() -> void:
	if _device_list == null:
		return
	for child in _device_list.get_children():
		child.queue_free()

	var devices := AudioServer.get_input_device_list()
	if devices.is_empty():
		var empty := Label.new()
		empty.text = "No input devices found."
		empty.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
		empty.add_theme_color_override("font_color", SidebarUIFactory.TEXT_DISABLED)
		_device_list.add_child(empty)
	for device in devices:
		_add_device_row(device)

	_mute_check.set_pressed_no_signal(Global.micMuted)


# One selectable device. The active one is marked by an accent dot and brighter
# text rather than a separate widget, matching the layer list's selected row.
func _add_device_row(device: String) -> void:
	var active: bool = device == AudioServer.input_device

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", Form.ROW_SEPARATION)
	_device_list.add_child(line)

	var marker := Label.new()
	marker.text = "●" if active else ""
	marker.custom_minimum_size = Vector2(12, 0)
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	marker.add_theme_color_override("font_color", SidebarUIFactory.SLIDER_FILL_ENABLED)
	line.add_child(marker)

	var pick := Button.new()
	pick.text = device
	pick.flat = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.clip_text = true
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	pick.add_theme_color_override(
		"font_color",
		SidebarUIFactory.TEXT_HEADING if active else SidebarUIFactory.TEXT_BODY,
	)
	pick.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	pick.pressed.connect(_on_device_selected.bind(device))
	line.add_child(pick)


func _on_device_selected(device: String) -> void:
	if Global.selectMicrophone(device, 1.0):
		Saving.settings["audioDevice"] = device
	else:
		Global.pushUpdate("Microphone is no longer available.")
	_refresh_audio()


func _on_mute_toggled(pressed: bool) -> void:
	Global.micMuted = pressed
	Global.pushUpdate("Microphone muted." if pressed else "Microphone unmuted.")


# --- Display -------------------------------------------------------------------

func _build_display(body: VBoxContainer) -> void:
	var background := Form.section(body, "Background")

	var presets := Form.row(background, "")
	for preset in BACKGROUND_PRESETS:
		var swatch := Form.button(presets, preset["name"], _on_background_preset.bind(preset["color"]))
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var custom := Form.row(background, "Custom colour")
	_color_picker = ColorPickerButton.new()
	_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_color_picker.custom_minimum_size = Vector2(0, Form.CONTROL_HEIGHT)
	_color_picker.color_changed.connect(_on_custom_background)
	custom.add_child(_color_picker)

	var rendering := Form.section(body, "Rendering")
	_filtering_check = Form.check_row(rendering, "Texture filtering")
	_filtering_check.toggled.connect(_on_filtering_toggled)

	var fps := Form.slider_row(
		rendering, "Max FPS", 1, UNLIMITED_FPS, 1, _slider_theme,
		func(value: float) -> String:
			return "Unlimited" if int(value) == UNLIMITED_FPS else str(int(value))
	)
	_fps_slider = fps["slider"]
	Global.make_slider_resettable(_fps_slider, 60)
	Form.button(Form.row(rendering, ""), "Apply frame limit", _on_apply_fps)


func _refresh_display() -> void:
	var background: Color = Global.backgroundColor
	_color_picker.color = Color(1, 1, 1, 1) if background.a == 0.0 else background
	_filtering_check.set_pressed_no_signal(Global.filtering)
	_fps_slider.value = UNLIMITED_FPS if Engine.max_fps == 0 else Engine.max_fps


func _on_background_preset(color: Color) -> void:
	_apply_background(color)


func _on_custom_background(color: Color) -> void:
	_apply_background(color)


func _apply_background(color: Color) -> void:
	get_viewport().transparent_bg = color.a == 0.0
	Global.backgroundColor = color
	Saving.settings["backgroundColor"] = var_to_str(color)
	RenderingServer.set_default_clear_color(color)
	Global.pushUpdate("Background colour updated.")


func _on_filtering_toggled(pressed: bool) -> void:
	var mode := 2 if pressed else 0
	for sprite in get_tree().get_nodes_in_group("saved"):
		sprite.sprite.texture_filter = mode
	Global.filtering = pressed
	Saving.settings["filtering"] = pressed
	Global.pushUpdate("Texture filtering set to: " + str(pressed))


# Applied on demand rather than per slider step: retargeting the frame limit
# mid-drag stutters the whole application.
func _on_apply_fps() -> void:
	var value := int(_fps_slider.value)
	Engine.max_fps = 0 if value == UNLIMITED_FPS else value
	Saving.settings["maxFPS"] = Engine.max_fps
	Global.pushUpdate("Max fps set to " + ("unlimited" if Engine.max_fps == 0 else str(Engine.max_fps)) + ".")


# --- Motion --------------------------------------------------------------------

func _build_motion(body: VBoxContainer) -> void:
	var bounce := Form.section(body, "Bounce")

	var force := Form.slider_row(bounce, "Force", 0, 500, 1, _slider_theme)
	_bounce_force = force["slider"]
	_bounce_force.value_changed.connect(_on_bounce_force)
	Global.make_slider_resettable(_bounce_force, 250)

	var gravity := Form.slider_row(bounce, "Gravity", 0, 3000, 1, _slider_theme)
	_bounce_gravity = gravity["slider"]
	_bounce_gravity.value_changed.connect(_on_bounce_gravity)
	Global.make_slider_resettable(_bounce_gravity, 1000)

	_costume_bounce_check = Form.check_row(bounce, "Bounce on costume change")
	_costume_bounce_check.toggled.connect(_on_costume_bounce)

	var blink := Form.section(body, "Blink")

	var speed := Form.slider_row(blink, "Speed", 0, 20, 1, _slider_theme)
	_blink_speed = speed["slider"]
	_blink_speed.value_changed.connect(_on_blink_speed)
	Global.make_slider_resettable(_blink_speed, 1)

	var chance := Form.slider_row(
		blink, "Chance", 1, 300, 1, _slider_theme,
		func(value: float) -> String: return "1 in %d" % int(value)
	)
	_blink_chance = chance["slider"]
	_blink_chance.value_changed.connect(_on_blink_chance)
	Global.make_slider_resettable(_blink_chance, 200)


func _refresh_motion() -> void:
	_bounce_force.value = Saving.settings["bounce"]
	_bounce_gravity.value = Saving.settings["gravity"]
	_costume_bounce_check.set_pressed_no_signal(Global.main.bounceOnCostumeChange)
	_blink_speed.value = int(1.0 / Global.blinkSpeed) if Global.blinkSpeed > 0.0 else 0
	_blink_chance.value = Global.blinkChance


func _on_bounce_force(value: float) -> void:
	Global.main.bounceSlider = value
	Saving.settings["bounce"] = value
	Global.main.ndi_mark_dirty()


func _on_bounce_gravity(value: float) -> void:
	Global.main.bounceGravity = value
	Saving.settings["gravity"] = value
	Global.main.ndi_mark_dirty()


func _on_costume_bounce(pressed: bool) -> void:
	Global.main.bounceOnCostumeChange = pressed
	Saving.settings["bounceOnCostumeChange"] = pressed


func _on_blink_speed(value: float) -> void:
	var speed := 0.0 if value == 0 else 1.0 / float(value)
	Global.blinkSpeed = speed
	Saving.settings["blinkSpeed"] = speed


func _on_blink_chance(value: float) -> void:
	Global.blinkChance = int(value)
	Saving.settings["blinkChance"] = int(value)


# --- Hotkeys -------------------------------------------------------------------

# Ten identical rows, built in a loop. The previous panel spelled each one out as
# its own node tree plus a bind handler and a delete handler, twenty methods for
# ten rows.
func _build_hotkeys(body: VBoxContainer) -> void:
	var group := Form.section(body, "Costume hotkeys")
	for slot in range(1, COSTUME_COUNT + 1):
		var line := Form.row(group, "Costume %d" % slot)

		var bind := Button.new()
		bind.flat = true
		bind.focus_mode = Control.FOCUS_NONE
		bind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bind.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
		bind.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
		bind.add_theme_color_override("font_hover_color", Color(1, 1, 1))
		Form.apply_field_style(bind)
		bind.pressed.connect(_on_hotkey_rebind.bind(slot))
		line.add_child(bind)
		_hotkey_buttons.append(bind)

		Form.button(line, "x", _on_hotkey_cleared.bind(slot), true)


func _refresh_hotkeys() -> void:
	for slot in range(1, COSTUME_COUNT + 1):
		_write_hotkey_label(slot)


func _write_hotkey_label(slot: int) -> void:
	_hotkey_buttons[slot - 1].text = Global.main.costumeKeys[slot - 1]


func _on_hotkey_rebind(slot: int) -> void:
	_hotkey_buttons[slot - 1].text = "press a key..."
	await Global.main.emptiedCapture
	awaitingCostumeInput = slot - 1
	await Global.main.pressedKey
	_write_hotkey_label(slot)
	await Global.main.emptiedCapture
	awaitingCostumeInput = -1


func _on_hotkey_cleared(slot: int) -> void:
	Global.main.costumeKeys[slot - 1] = "null"
	_write_hotkey_label(slot)
	Global.pushUpdate("Deleted costume hotkey " + str(slot) + ".")


# --- Output --------------------------------------------------------------------

func _build_output(body: VBoxContainer) -> void:
	var ndi := Form.section(body, "NDI output")

	_ndi_status = Label.new()
	_ndi_status.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	_ndi_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	_ndi_status.visible = false
	ndi.add_child(_ndi_status)

	_ndi_toggle = Form.check_row(ndi, "Enabled")
	_ndi_toggle.toggled.connect(_on_ndi_toggle)

	_ndi_width = Form.option_row(ndi, "Width", NDI_WIDTHS)
	_ndi_width.item_selected.connect(_on_ndi_width_selected)

	_ndi_mode = Form.option_row(ndi, "Mode", ["auto", "manual"])
	_ndi_mode.item_selected.connect(_on_ndi_mode_selected)

	var manual := Form.spin_row(ndi, "Manual size", 128, 3840)
	_ndi_manual_w = manual[0]
	_ndi_manual_h = manual[1]
	_ndi_manual_row = _ndi_manual_w.get_parent()
	_ndi_manual_row.visible = false
	for spin in manual:
		spin.value_changed.connect(_on_ndi_manual_size_changed)

	_ndi_source_name = Form.text_row(ndi, "Source name", "PixelLab Studio")
	_ndi_source_name.text_submitted.connect(_on_ndi_source_name_committed)
	_ndi_source_name.focus_exited.connect(_on_ndi_source_name_focus_exited)

	var recording := Form.section(body, "Recording")
	_recording_format = Form.option_row(recording, "Format", RECORDING_FORMAT_NAMES)
	_recording_format.item_selected.connect(_on_recording_format_selected)
	_recording_fps = Form.option_row(recording, "Frame rate", RECORDING_FPS)
	_recording_fps.item_selected.connect(_on_recording_fps_selected)


func _refresh_output() -> void:
	_refresh_ndi()
	_refresh_recording()


func _refresh_ndi() -> void:
	var ndi = Global.main.ndi_manager
	if ndi == null:
		return

	if not ndi.is_plugin_available():
		_ndi_status.text = "Plugin not installed."
		_ndi_status.visible = true
		_ndi_toggle.set_pressed_no_signal(false)
		for control in [_ndi_toggle, _ndi_width, _ndi_mode]:
			control.disabled = true
		_ndi_source_name.editable = false
		return

	_ndi_status.visible = false
	_ndi_toggle.disabled = false
	_ndi_toggle.set_pressed_no_signal(ndi.is_enabled())

	_ndi_source_name.editable = true
	_ndi_source_name.text = Saving.settings.get("ndiSourceName", "PixelLab Studio")

	_ndi_width.selected = maxi(NDI_WIDTHS.find(Saving.settings["ndiWidth"]), 0)

	var mode: String = Saving.settings["ndiMode"]
	_ndi_mode.selected = 1 if mode == "manual" else 0
	_ndi_manual_row.visible = mode == "manual"
	if mode == "manual":
		_ndi_manual_w.value = Saving.settings["ndiManualWidth"]
		_ndi_manual_h.value = Saving.settings["ndiManualHeight"]

	var enabled: bool = ndi.is_enabled()
	_ndi_width.disabled = not enabled
	_ndi_mode.disabled = not enabled


func _refresh_recording() -> void:
	_recording_format.selected = maxi(
		RECORDING_FORMATS.find(Saving.settings.get("recordingFormat", "webm")), 0
	)
	var fps_index := RECORDING_FPS.find(Saving.settings.get("recordingFPS", 30))
	_recording_fps.selected = fps_index if fps_index >= 0 else 1


func _on_ndi_toggle(pressed: bool) -> void:
	var ndi = Global.main.ndi_manager
	if ndi == null:
		return
	ndi.set_enabled(pressed)
	_refresh_ndi()
	if Global.main.editMode:
		ndi.set_crop_visible(pressed)
	# NDI disables window transparency for performance, so re-derive it.
	Global.main.updateWindowTransparency()
	Global.pushUpdate("NDI output enabled." if pressed else "NDI output disabled.")


func _on_ndi_width_selected(index: int) -> void:
	var ndi = Global.main.ndi_manager
	if ndi != null:
		ndi.set_width(NDI_WIDTHS[index])
	Global.pushUpdate("NDI width set to " + str(NDI_WIDTHS[index]) + ".")


func _on_ndi_mode_selected(index: int) -> void:
	var mode := "auto" if index == 0 else "manual"
	var ndi = Global.main.ndi_manager
	if ndi != null:
		ndi.set_mode(mode)
	_ndi_manual_row.visible = mode == "manual"
	Global.pushUpdate("NDI mode set to " + mode + ".")


func _on_ndi_manual_size_changed(_value: float) -> void:
	var ndi = Global.main.ndi_manager
	if ndi != null:
		ndi.set_manual_size(int(_ndi_manual_w.value), int(_ndi_manual_h.value))


func _on_ndi_source_name_committed(new_text: String) -> void:
	_apply_ndi_source_name(new_text)
	_ndi_source_name.release_focus()


func _on_ndi_source_name_focus_exited() -> void:
	_apply_ndi_source_name(_ndi_source_name.text)


func _apply_ndi_source_name(new_text: String) -> void:
	var ndi = Global.main.ndi_manager
	if ndi == null:
		return
	var previous: String = Saving.settings.get("ndiSourceName", "PixelLab Studio")
	ndi.set_source_name(new_text)
	var applied: String = Saving.settings.get("ndiSourceName", "PixelLab Studio")
	_ndi_source_name.text = applied
	if applied != previous:
		Global.pushUpdate("NDI source name set to \"" + applied + "\".")


func _on_recording_format_selected(index: int) -> void:
	var format: String = RECORDING_FORMATS[index]
	Saving.settings["recordingFormat"] = format
	# Still frames are expensive per frame, so drop the default rate for them.
	Saving.settings["recordingFPS"] = 15 if format != "webm" else 30
	_refresh_recording()
	Global.pushUpdate("Recording format set to " + RECORDING_FORMAT_NAMES[index] + ".")


func _on_recording_fps_selected(index: int) -> void:
	Saving.settings["recordingFPS"] = RECORDING_FPS[index]
	Global.pushUpdate("Recording FPS set to " + str(RECORDING_FPS[index]) + ".")
