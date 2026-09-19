extends Node2D

# The settings panel. A fixed-size dropdown from the menu bar's Settings button,
# built entirely from the shared UI vocabulary: AppTabBar for the strip, FormUI
# for the labelled rows, SidebarUI for the palette. Nothing here carries a
# hard-coded child coordinate; every tab is a column of rows that reflows on its
# own.
#
# Tabs are declared in _TABS and implemented by focused component scripts.

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const Form = preload("res://ui_scenes/common/form_ui.gd")
const AudioSettingsTab = preload("res://ui_scenes/settings/audio_settings_tab.gd")
const DisplaySettingsTab = preload("res://ui_scenes/settings/display_settings_tab.gd")
const MotionSettingsTab = preload("res://ui_scenes/settings/motion_settings_tab.gd")
const HotkeySettingsTab = preload("res://ui_scenes/settings/hotkey_settings_tab.gd")
const OutputSettingsTab = preload("res://ui_scenes/settings/output_settings_tab.gd")

const PANEL_SIZE := Vector2(420, 380)
const PANEL_PADDING := 12
const PANEL_CORNER_RADIUS := 4
const _TABS := ["Audio", "Display", "Motion", "Hotkeys", "Output"]

# Read by main.gd: which costume slot is capturing a key, and whether the cursor
# is over the panel (so a keypress aimed at the panel is not eaten elsewhere).
var awaitingCostumeInput: int:
	get: return _hotkeys_tab.awaiting_input
var hasMouse := false

var _panel: PanelContainer = null
var _tab_bar: AppTabBar = null
var _bodies: Array[VBoxContainer] = []
var _slider_theme: Dictionary = {}
var _audio_tab = AudioSettingsTab.new()
var _display_tab = DisplaySettingsTab.new()
var _motion_tab = MotionSettingsTab.new()
var _hotkeys_tab = HotkeySettingsTab.new()
var _output_tab = OutputSettingsTab.new()


func _ready() -> void:
	_slider_theme = SidebarUIFactory.create_slider_theme()
	_build_panel()
	visibility_changed.connect(_on_visibility_changed)


# A costume rebind belongs to this panel and ends when it is hidden, whether the
# panel itself is closed or something above it is.
func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_hotkeys_tab.cancel_capture()


func panel_size() -> Vector2:
	return PANEL_SIZE


# Pull every control back into line with current state. Called once at startup
# by main.gd and again each time the panel is opened.
func setvalues() -> void:
	_audio_tab.refresh()
	_display_tab.refresh()
	_motion_tab.refresh()
	_hotkeys_tab.refresh()
	_output_tab.refresh()


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

	var audio_body := _add_tab_body(stack)
	_audio_tab.build(audio_body, Global, Saving)
	var display_body := _add_tab_body(stack)
	_display_tab.build(display_body, Global, Saving, get_viewport(), _slider_theme)
	var motion_body := _add_tab_body(stack)
	_motion_tab.build(motion_body, Global, Saving, _slider_theme)
	var hotkeys_body := _add_tab_body(stack)
	_hotkeys_tab.build(hotkeys_body, Global)
	var output_body := _add_tab_body(stack)
	_output_tab.build(output_body, Global, Saving)

	_show_tab(0)


func _show_tab(index: int) -> void:
	for i in _bodies.size():
		_bodies[i].visible = i == index


func _add_tab_body(stack: VBoxContainer) -> VBoxContainer:
	var body := Form.column(stack, Form.SECTION_SEPARATION)
	_bodies.append(body)
	return body
