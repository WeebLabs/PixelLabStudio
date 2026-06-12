extends Node2D

@onready var container = $ScrollContainer/VBoxContainer
var SpriteListObject = preload("res://ui_scenes/spriteList/sprite_list_object.gd")

var speaking_tex = preload("res://ui_scenes/spriteEditMenu/speaking.png")
var blink_tex = preload("res://ui_scenes/spriteEditMenu/blink.png")
var trash_tex = preload("res://ui_scenes/spriteEditMenu/trash.png")
var unlink_tex = preload("res://ui_scenes/spriteEditMenu/unlink.png")
var select_tex = preload("res://ui_scenes/spriteEditMenu/layerButtons/select.png")

var layer_textures: Array = []

var panel_width: float = 310
var panel_height: float = 630
const MIN_WIDTH = 310
const MAX_WIDTH_RATIO = 0.25
const GRAB_MARGIN = 6
const CONTROLS_ROW_HEIGHT = 32

# Spacing constants live on Global so both sidebars share one source of truth.
# Tune Global.UI_ROW_GAP / UI_DIVIDER_PAD to reflow every panel that uses them.

var _bg: ColorRect
var _divider1: ColorRect
var _divider2: ColorRect
var _divider3: ColorRect
var _controls: HBoxContainer
var _speaking_spr: Sprite2D
var _blinking_spr: Sprite2D
var _unlink_spr: Sprite2D
var _trash_spr: Sprite2D
var _link_btn: Button

var _costume_section: HBoxContainer
var _costume_btn_widgets: Array = []  # Buttons holding each costume sprite, for layout queries
var _costume_btns: Array = []
var _costume_select: Sprite2D

var _eye_section: VBoxContainer
var _eye_toggle: CheckBox
var _eye_dist_label: Label
var _eye_dist_slider: HSlider
var _eye_speed_label: Label
var _eye_speed_slider: HSlider
var _eye_invert: CheckBox
var _eye_type_option: OptionButton   # Mode: Position / Rotation
var _eye_mode_option: OptionButton   # Target: Cursor / Layer
var _eye_pick_btn: Button
var _eye_whip_line: Line2D
var _eye_mode_tooltip_label: Label
var _eye_mode_tooltip_timer: Timer

# Tabs (below costume row): Details / Eye Tracking / Physics. The tab bar selects
# which content VBox is visible; all three live in _tab_host inside a scroll area
# so a tab's content can grow upward into freed space if the layer list above is
# ever detached.
const BOTTOM_MARGIN = 12
var _tab_bar: SidebarTabBar
var _tab_scroll: ScrollContainer
var _tab_host: VBoxContainer
var _details_content: VBoxContainer
var _eye_content: VBoxContainer
var _physics_content: VBoxContainer
var _physics_tab: WigglePhysicsTab

# Details tab — layer toggles relocated here from the left sidebar.
var _cb_ignore_bounce: CheckBox
var _cb_clip_linked: CheckBox
var _cb_static: CheckBox
var _cb_ndi_ref: CheckBox

var _slider_fill_enabled: StyleBoxFlat
var _slider_fill_disabled: StyleBoxFlat
var _slider_grabber_enabled: ImageTexture
var _slider_grabber_disabled: ImageTexture
var _slider_enabled_state: bool = true
# Tracks the previous _eye_scope() result so we only reset values to neutral
# on transitions into a scope, not on every per-frame refresh.
var _prev_eye_scope: String = ""

var _vis_toggle_section: VBoxContainer
var _vis_toggle_btn: Button
var _vis_toggle_label: Label
var _vis_toggle_delete_btn: Button
var _divider4: ColorRect

var _filter_field: LineEdit

# Opacity + Blend strip, pinned to the bottom of the layer-list region (above the draggable
# divider). Built by a dedicated module (ui_scenes/spriteList/blend_section.gd).
var _blend_section_helper: BlendOpacitySection
var _blend_section: VBoxContainer

var _saved_collapse_states: Dictionary = {}
var _update_generation: int = 0
var _pending_scroll_target = null
var _dragging = false
var _drag_start = Vector2.ZERO
var _drag_start_width: float = 0
var _hover_left = false
var _divider_ratio: float = 0.50
var _divider_dragging = false
var _hover_divider = false

func _ready():
	Global.spriteList = self
	container.add_theme_constant_override("separation", 2)
	$Area2D2/CollisionShape2D.disabled = false
	$NinePatchRect.visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.15, 0.15, 0.15)
	_bg.z_index = -1
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	move_child(_bg, 0)

	for i in range(1, 11):
		layer_textures.append(load("res://icons/" + str(i) + ".svg"))

	_filter_field = LineEdit.new()
	_filter_field.placeholder_text = "Filter layers..."
	_filter_field.add_theme_font_size_override("font_size", 12)
	_filter_field.clear_button_enabled = true
	_filter_field.caret_blink = true
	_filter_field.caret_blink_interval = 0.5
	_filter_field.text_changed.connect(_on_filter_changed)
	var fs_normal = StyleBoxFlat.new()
	fs_normal.bg_color = Color(0.1, 0.1, 0.1)
	fs_normal.set_corner_radius_all(3)
	fs_normal.content_margin_left = 6
	fs_normal.content_margin_right = 6
	fs_normal.content_margin_top = 4
	fs_normal.content_margin_bottom = 4
	var fs_focus = fs_normal.duplicate()
	fs_focus.border_color = Color(0.45, 0.45, 0.5)
	fs_focus.set_border_width_all(1)
	_filter_field.add_theme_stylebox_override("normal", fs_normal)
	_filter_field.add_theme_stylebox_override("focus", fs_focus)
	add_child(_filter_field)

	_build_slider_styles()
	_create_controls()
	_create_costume_buttons()
	_create_blend_section()
	_create_tabs()
	_create_details_tab()
	_create_eye_tracking()
	_create_physics_tab()
	_create_vis_toggle()

	# Restore saved sidebar width before the first _apply_size() so all
	# resizable elements pick up the user's preference on startup.
	var saved_w = Saving.settings.get("rightSidebarWidth", panel_width)
	# Floor the max at MIN_WIDTH: at startup the stretched viewport is narrow, so
	# viewport.x * ratio can fall below MIN_WIDTH, inverting the clamp (min > max) and
	# collapsing the panel under its minimum until a drag re-clamps it.
	var max_w = maxf(MIN_WIDTH, get_viewport().get_visible_rect().size.x * MAX_WIDTH_RATIO)
	panel_width = clamp(saved_w, MIN_WIDTH, max_w)

	# Restore the active tab before the first layout pass.
	var saved_tab = clamp(int(Saving.settings.get("rightSidebarTab", 0)), 0, 2)
	_tab_bar.set_active(saved_tab)
	_show_tab(saved_tab)

	_apply_size()

# Build the shared slider fill/grabber resources once, before any section
# attaches them (eye tracking, physics). Mirrors the left sidebar's slider look.
func _build_slider_styles():
	_slider_fill_enabled = StyleBoxFlat.new()
	_slider_fill_enabled.bg_color = Color(1.0, 0.7, 0.8)
	_slider_fill_disabled = StyleBoxFlat.new()
	_slider_fill_disabled.bg_color = Color(0.55, 0.4, 0.45)

	var grabber_img_on = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	grabber_img_on.fill(Color(0, 0, 0, 0))
	var grabber_img_off = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	grabber_img_off.fill(Color(0, 0, 0, 0))
	for px in range(16):
		for py in range(16):
			var dx = px - 8
			var dy = py - 8
			if dx * dx + dy * dy <= 36:  # Circle radius ~6
				grabber_img_on.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
				grabber_img_off.set_pixel(px, py, Color(0.45, 0.45, 0.48, 1.0))
	_slider_grabber_enabled = ImageTexture.create_from_image(grabber_img_on)
	_slider_grabber_disabled = ImageTexture.create_from_image(grabber_img_off)

func _create_controls():
	_divider1 = ColorRect.new()
	_divider1.color = Color(0.3, 0.3, 0.35)
	_divider1.size = Vector2(panel_width - 16, 1)
	add_child(_divider1)

	_divider2 = ColorRect.new()
	_divider2.color = Color(0.3, 0.3, 0.35)
	_divider2.size = Vector2(panel_width - 16, 1)
	add_child(_divider2)

	_divider3 = ColorRect.new()
	_divider3.color = Color(0.3, 0.3, 0.35)
	_divider3.size = Vector2(panel_width - 16, 1)
	add_child(_divider3)

	# Top controls row: speaking/blinking/link/unlink/trash. HBox distributes them
	# horizontally and centers the row in _apply_size.
	_controls = HBoxContainer.new()
	_controls.add_theme_constant_override("separation", 8)
	_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_controls)

	var icon_scale = Vector2(0.65, 0.65)

	_speaking_spr = _build_icon_button(speaking_tex, icon_scale, _on_speaking_pressed, 3)
	_blinking_spr = _build_icon_button(blink_tex, icon_scale, _on_blinking_pressed, 4)

	_link_btn = Button.new()
	_link_btn.text = "Link"
	_link_btn.flat = true
	_link_btn.add_theme_font_size_override("font_size", 12)
	_link_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_link_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_link_btn.pressed.connect(_on_link_pressed)
	_controls.add_child(_link_btn)

	_unlink_spr = _build_icon_button(unlink_tex, icon_scale, _on_unlink_pressed, 1)
	_trash_spr = _build_icon_button(trash_tex, icon_scale, _on_trash_pressed, 1)

# Build an icon-style button (Button + Sprite2D inside) and add to _controls.
# Returns the inner Sprite2D so callers can tint/animate it.
func _build_icon_button(tex: Texture2D, icon_scale: Vector2, on_pressed: Callable, hframes: int) -> Sprite2D:
	var btn = Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(32, 32)
	btn.pressed.connect(on_pressed)
	_controls.add_child(btn)

	var spr = Sprite2D.new()
	spr.texture = tex
	if hframes > 1:
		spr.hframes = hframes
	spr.scale = icon_scale
	spr.position = Vector2(16, 16)  # center of 32x32 button
	btn.add_child(spr)
	return spr

func _create_costume_buttons():
	# 10 costume icons in a centered row. HBox handles horizontal layout;
	# each icon is a Button with a Sprite2D inside for tinting/visibility.
	_costume_section = HBoxContainer.new()
	_costume_section.add_theme_constant_override("separation", 1)
	_costume_section.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_costume_section)

	var icon_scale = Vector2(0.4, 0.4)

	for i in range(10):
		var btn = Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(28, 28)
		btn.pressed.connect(_on_costume_btn_pressed.bind(i))
		_costume_section.add_child(btn)
		_costume_btn_widgets.append(btn)

		var spr = Sprite2D.new()
		spr.texture = layer_textures[i]
		spr.scale = icon_scale
		spr.position = Vector2(14, 14)  # center of 28x28 button
		btn.add_child(spr)
		_costume_btns.append(spr)

	# Selection indicator — free-floating sprite repositioned in _process from
	# whichever button is currently active.
	_costume_select = Sprite2D.new()
	_costume_select.texture = select_tex
	_costume_select.scale = icon_scale
	_costume_select.visible = false
	add_child(_costume_select)

# Build the Opacity + Blend strip and hand it the shared slider styles. The sidebar
# positions it in _apply_size (bottom of the layer-list region, above the divider).
func _create_blend_section():
	_blend_section_helper = BlendOpacitySection.new()
	_blend_section = _blend_section_helper.build(self, _slider_fill_enabled,
		_slider_fill_disabled, _slider_grabber_enabled, _slider_grabber_disabled)

# Build the tab strip + the scrollable host that holds the three tab contents.
# Only the active content is visible; the scroll lets a tall tab (Physics) grow
# into whatever vertical space is available below the costume row.
func _create_tabs():
	_tab_bar = SidebarTabBar.new()
	add_child(_tab_bar)
	_tab_bar.add_tab("Details")
	_tab_bar.add_tab("Tracking")
	_tab_bar.add_tab("Physics")
	_tab_bar.tab_changed.connect(_on_tab_changed)

	_tab_scroll = ScrollContainer.new()
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_tab_scroll)

	_tab_host = VBoxContainer.new()
	_tab_host.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	_tab_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_scroll.add_child(_tab_host)

	_details_content = _make_tab_content()
	_eye_content = _make_tab_content()
	_physics_content = _make_tab_content()

func _make_tab_content() -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_host.add_child(vbox)
	return vbox

func _show_tab(index: int):
	_details_content.visible = index == 0
	_eye_content.visible = index == 1
	_physics_content.visible = index == 2

func _on_tab_changed(index: int):
	_show_tab(index)
	Saving.settings["rightSidebarTab"] = index
	Saving.write_settings(Saving.settingsPath)

# Details tab — layer toggles relocated from the left sidebar (same behaviour).
func _create_details_tab():
	var c = Color(0.75, 0.75, 0.8)
	_cb_ignore_bounce = _make_details_checkbox("Ignore bounce velocity", _on_details_ignore_bounce_toggled, c)
	_cb_clip_linked = _make_details_checkbox("Clip linked sprites", _on_details_clip_linked_toggled, c)
	_cb_static = _make_details_checkbox("Static element", _on_details_static_toggled, c)
	_cb_ndi_ref = _make_details_checkbox("NDI reference layer", _on_details_ndi_ref_toggled, c)

func _make_details_checkbox(text: String, on_toggled: Callable, color: Color) -> CheckBox:
	var cb = CheckBox.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", 12)
	cb.add_theme_color_override("font_color", color)
	cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cb.toggled.connect(on_toggled)
	_details_content.add_child(cb)
	return cb

# Physics tab — wiggle controls (effects/wiggle). Built by a dedicated module so
# this file stays focused on sidebar structure.
func _create_physics_tab():
	_physics_tab = WigglePhysicsTab.new()
	_physics_tab.build(_physics_content, _slider_fill_enabled, _slider_fill_disabled,
		_slider_grabber_enabled, _slider_grabber_disabled)

func _create_eye_tracking():
	# Section is a VBoxContainer; rows are HBoxContainers. No manual `y += ...`
	# accumulators — VBox handles vertical stacking, HBox handles horizontal.
	# Width is set in _apply_size; height is auto-fit from children.
	_eye_section = VBoxContainer.new()
	_eye_section.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	_eye_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eye_content.add_child(_eye_section)

	var label_color = Color(0.75, 0.75, 0.8)

	# Row: eye-track toggle + invert direction
	var toggle_row = HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 4)
	_eye_section.add_child(toggle_row)

	_eye_toggle = CheckBox.new()
	_eye_toggle.text = "Enable (Global)"
	_eye_toggle.add_theme_font_size_override("font_size", 12)
	_eye_toggle.add_theme_color_override("font_color", label_color)
	_eye_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eye_toggle.toggled.connect(_on_eye_track_toggled)
	toggle_row.add_child(_eye_toggle)

	_eye_invert = CheckBox.new()
	_eye_invert.text = "Invert direction"
	_eye_invert.add_theme_font_size_override("font_size", 12)
	_eye_invert.add_theme_color_override("font_color", label_color)
	_eye_invert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eye_invert.toggled.connect(_on_eye_track_invert_toggled)
	toggle_row.add_child(_eye_invert)

	# Row: Mode (Position = translate toward target / Rotation = swivel toward it)
	var type_row = HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 6)
	_eye_section.add_child(type_row)

	var type_label = Label.new()
	type_label.text = "Mode:"
	type_label.add_theme_font_size_override("font_size", 12)
	type_label.add_theme_color_override("font_color", label_color)
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	type_row.add_child(type_label)

	_eye_type_option = OptionButton.new()
	_eye_type_option.add_item("Position", 0)
	_eye_type_option.add_item("Rotation", 1)
	_eye_type_option.add_theme_font_size_override("font_size", 12)
	_eye_type_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_eye_type_option.custom_minimum_size = Vector2(0, 22)
	_eye_type_option.item_selected.connect(_on_eye_track_type_selected)
	type_row.add_child(_eye_type_option)

	# Row: target label + dropdown (Cursor / Layer) + pick button
	var mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	_eye_section.add_child(mode_row)

	var mode_label = Label.new()
	mode_label.text = "Target:"
	mode_label.add_theme_font_size_override("font_size", 12)
	mode_label.add_theme_color_override("font_color", label_color)
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_row.add_child(mode_label)

	_eye_mode_option = OptionButton.new()
	_eye_mode_option.add_item("Cursor", 0)
	_eye_mode_option.add_item("Layer", 1)
	_eye_mode_option.add_theme_font_size_override("font_size", 12)
	# Width auto-fits the longest item text (recomputed dynamically when the
	# Layer item is renamed to a target's truncated name)
	_eye_mode_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_eye_mode_option.custom_minimum_size = Vector2(0, 22)
	_eye_mode_option.item_selected.connect(_on_eye_track_mode_selected)
	_eye_mode_option.mouse_entered.connect(_on_eye_mode_option_hover)
	_eye_mode_option.mouse_exited.connect(_on_eye_mode_option_unhover)
	# Right-click while in Layer mode clears the target; Cursor mode no-op so
	# accidental right-clicks don't trash unrelated state.
	_eye_mode_option.gui_input.connect(_on_eye_mode_option_gui_input)
	mode_row.add_child(_eye_mode_option)

	_eye_pick_btn = Button.new()
	_eye_pick_btn.text = "Pick"
	_eye_pick_btn.flat = true
	_eye_pick_btn.add_theme_font_size_override("font_size", 12)
	_eye_pick_btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_eye_pick_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_eye_pick_btn.custom_minimum_size = Vector2(50, 22)
	_eye_pick_btn.pressed.connect(_on_eye_track_pick_pressed)
	_eye_pick_btn.visible = false
	mode_row.add_child(_eye_pick_btn)

	# Custom hover tooltip — shows the full target name after a 2s dwell. Free-
	# floating; not part of the section's vertical layout.
	_eye_mode_tooltip_label = Label.new()
	_eye_mode_tooltip_label.add_theme_font_size_override("font_size", 12)
	_eye_mode_tooltip_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1))
	var tip_bg = StyleBoxFlat.new()
	tip_bg.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	tip_bg.content_margin_left = 6
	tip_bg.content_margin_right = 6
	tip_bg.content_margin_top = 3
	tip_bg.content_margin_bottom = 3
	tip_bg.set_corner_radius_all(3)
	_eye_mode_tooltip_label.add_theme_stylebox_override("normal", tip_bg)
	_eye_mode_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_mode_tooltip_label.visible = false
	_eye_mode_tooltip_label.z_index = 4095
	add_child(_eye_mode_tooltip_label)

	_eye_mode_tooltip_timer = Timer.new()
	_eye_mode_tooltip_timer.one_shot = true
	_eye_mode_tooltip_timer.wait_time = 2.0
	_eye_mode_tooltip_timer.timeout.connect(_on_eye_mode_tooltip_show)
	add_child(_eye_mode_tooltip_timer)

	# Whip line — invisible until pick mode is active; free-floating
	_eye_whip_line = Line2D.new()
	_eye_whip_line.width = 2.0
	_eye_whip_line.default_color = Color(1.0, 0.85, 0.35, 0.9)
	_eye_whip_line.visible = false
	_eye_whip_line.z_index = 4090
	add_child(_eye_whip_line)

	# Distance label + slider
	_eye_dist_label = Label.new()
	_eye_dist_label.text = "tracking distance: 20.0"
	_eye_dist_label.add_theme_font_size_override("font_size", 12)
	_eye_dist_label.add_theme_color_override("font_color", label_color)
	_eye_section.add_child(_eye_dist_label)

	_eye_dist_slider = HSlider.new()
	# Plain scroll scrolls the section; only Ctrl+scroll adjusts (global.gd:_input).
	_eye_dist_slider.scrollable = false
	_eye_dist_slider.min_value = 1.0
	_eye_dist_slider.max_value = 200.0
	_eye_dist_slider.step = 1.0
	_eye_dist_slider.value = 20.0
	_eye_dist_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eye_dist_slider.custom_minimum_size = Vector2(0, 16)
	_eye_dist_slider.value_changed.connect(_on_eye_track_dist_changed)
	_eye_dist_slider.add_theme_stylebox_override("grabber_area", _slider_fill_enabled)
	_eye_dist_slider.add_theme_stylebox_override("grabber_area_highlight", _slider_fill_enabled)
	_eye_dist_slider.add_theme_icon_override("grabber", _slider_grabber_enabled)
	_eye_dist_slider.add_theme_icon_override("grabber_highlight", _slider_grabber_enabled)
	_eye_dist_slider.add_theme_icon_override("grabber_disabled", _slider_grabber_disabled)
	_eye_section.add_child(_eye_dist_slider)
	Global.make_slider_resettable(_eye_dist_slider, 20.0)

	# Speed label + slider
	_eye_speed_label = Label.new()
	_eye_speed_label.text = "tracking speed: 0.15"
	_eye_speed_label.add_theme_font_size_override("font_size", 12)
	_eye_speed_label.add_theme_color_override("font_color", label_color)
	_eye_section.add_child(_eye_speed_label)

	_eye_speed_slider = HSlider.new()
	_eye_speed_slider.scrollable = false
	_eye_speed_slider.min_value = 0.01
	_eye_speed_slider.max_value = 1.0
	_eye_speed_slider.step = 0.01
	_eye_speed_slider.value = 0.15
	_eye_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eye_speed_slider.custom_minimum_size = Vector2(0, 16)
	_eye_speed_slider.value_changed.connect(_on_eye_track_speed_changed)
	_eye_speed_slider.add_theme_stylebox_override("grabber_area", _slider_fill_enabled)
	_eye_speed_slider.add_theme_stylebox_override("grabber_area_highlight", _slider_fill_enabled)
	_eye_speed_slider.add_theme_icon_override("grabber", _slider_grabber_enabled)
	_eye_speed_slider.add_theme_icon_override("grabber_highlight", _slider_grabber_enabled)
	_eye_speed_slider.add_theme_icon_override("grabber_disabled", _slider_grabber_disabled)
	_eye_section.add_child(_eye_speed_slider)
	Global.make_slider_resettable(_eye_speed_slider, 0.15)

func _create_vis_toggle():
	# Divider above the vis-toggle section — kept as a ColorRect for now since
	# it's positioned independently from both sections.
	_divider4 = ColorRect.new()
	_divider4.color = Color(0.3, 0.3, 0.35)
	_divider4.size = Vector2(panel_width - 16, 1)
	_divider4.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divider4)

	# Section is a VBoxContainer with a header row and a control row inside.
	_vis_toggle_section = VBoxContainer.new()
	_vis_toggle_section.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	add_child(_vis_toggle_section)

	var label_color = Color(0.75, 0.75, 0.8)

	# Section header
	var header = Label.new()
	header.text = "Visibility Toggle"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", label_color)
	_vis_toggle_section.add_child(header)

	# Control row: [Set Key] [toggle: "..."]  ...  [x]
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_vis_toggle_section.add_child(row)

	_vis_toggle_btn = Button.new()
	_vis_toggle_btn.text = "Set Key"
	_vis_toggle_btn.flat = true
	_vis_toggle_btn.add_theme_font_size_override("font_size", 12)
	_vis_toggle_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_vis_toggle_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_vis_toggle_btn.pressed.connect(_on_set_toggle_pressed)
	row.add_child(_vis_toggle_btn)

	_vis_toggle_label = Label.new()
	_vis_toggle_label.text = "toggle: \"null\""
	_vis_toggle_label.add_theme_font_size_override("font_size", 12)
	_vis_toggle_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_vis_toggle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_vis_toggle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_vis_toggle_label)

	_vis_toggle_delete_btn = Button.new()
	_vis_toggle_delete_btn.text = "x"
	_vis_toggle_delete_btn.flat = true
	_vis_toggle_delete_btn.add_theme_font_size_override("font_size", 11)
	_vis_toggle_delete_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_vis_toggle_delete_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.45, 0.5))
	_vis_toggle_delete_btn.custom_minimum_size = Vector2(20, 0)
	_vis_toggle_delete_btn.pressed.connect(_on_vis_toggle_delete_pressed)
	row.add_child(_vis_toggle_delete_btn)

func _apply_size():
	var s = get_viewport().get_visible_rect().size
	panel_height = s.y
	_bg.position = Vector2(-4, -4)
	_bg.size = Vector2(panel_width + 8, panel_height + 8)

	var section_width = panel_width - 20
	var section_x = (panel_width - section_width) / 2.0

	# === Above the user-draggable scroll divider ===
	# Sequential layout cursor. Every divider gets Global.UI_DIVIDER_PAD on each side;
	# non-divider transitions use Global.UI_ROW_GAP. No more per-divider magic offsets.
	var y = 0.0

	_controls.position = Vector2(0, y)
	_controls.size = Vector2(panel_width, CONTROLS_ROW_HEIGHT)
	y += CONTROLS_ROW_HEIGHT

	y += Global.UI_DIVIDER_PAD
	_divider1.position = Vector2(8, y)
	_divider1.size.x = panel_width - 16
	y += Global.UI_DIVIDER_PAD

	_filter_field.position = Vector2(0, y)
	_filter_field.custom_minimum_size = Vector2(panel_width - 10, 24)
	_filter_field.size = Vector2(panel_width - 10, 24)
	y += 24 + Global.UI_ROW_GAP

	$ScrollContainer.offset_top = y
	$ScrollContainer.offset_right = panel_width - 10
	container.custom_minimum_size.x = panel_width - 20
	var scroll_bottom = panel_height * _divider_ratio
	# Opacity + Blend strip rides the bottom of the layer-list region, just above the
	# draggable divider — it reads as part of the list (like the filter field caps the top).
	var blend_h = _blend_section.get_combined_minimum_size().y
	_blend_section.position = Vector2(section_x, scroll_bottom - blend_h)
	_blend_section.size = Vector2(section_width, blend_h)
	$ScrollContainer.offset_bottom = scroll_bottom - blend_h - Global.UI_ROW_GAP

	# === Draggable scroll divider (centered between scroll and costume) ===
	y = scroll_bottom + Global.UI_DIVIDER_PAD
	_divider2.position = Vector2(8, y)
	_divider2.size.x = panel_width - 16
	y += Global.UI_DIVIDER_PAD

	# === Below the draggable divider ===
	_costume_section.position = Vector2(0, y)
	_costume_section.size = Vector2(panel_width,
		_costume_section.get_combined_minimum_size().y)
	y += _costume_section.size.y

	y += Global.UI_DIVIDER_PAD
	_divider3.position = Vector2(8, y)
	_divider3.size.x = panel_width - 16
	y += Global.UI_DIVIDER_PAD

	# Tab bar, then a scroll area that fills the space down to a bottom-pinned
	# Visibility Toggle. When the layer list above is detached later, this region
	# grows and the active tab's content expands upward to use it.
	_tab_bar.position = Vector2(section_x, y)
	_tab_bar.set_bar_size(section_width)
	y += SidebarTabBar.BAR_HEIGHT + Global.UI_ROW_GAP

	var vis_h = _vis_toggle_section.get_combined_minimum_size().y
	var vis_y = panel_height - vis_h - BOTTOM_MARGIN
	var divider4_y = vis_y - Global.UI_DIVIDER_PAD
	var tab_bottom = divider4_y - Global.UI_DIVIDER_PAD

	_tab_scroll.position = Vector2(section_x, y)
	_tab_scroll.size = Vector2(section_width, max(0.0, tab_bottom - y))

	_divider4.position = Vector2(8, divider4_y)
	_divider4.size.x = panel_width - 16

	_vis_toggle_section.position = Vector2(section_x, vis_y)
	_vis_toggle_section.size = Vector2(section_width, vis_h)

	# Collision area + sidebar anchor
	$Area2D2/CollisionShape2D.shape.size = Vector2(panel_width, panel_height)
	$Area2D2/CollisionShape2D.position = Vector2(panel_width / 2.0, panel_height / 2.0)
	position.x = s.x - (panel_width + 3)

func _process(_delta):
	# Whip line follows the cursor while pick mode is active
	refreshEyePickWhip()
	# Keep eye-tracking section in sync with the current scope. Cheap: a single
	# group iteration when no sprite is selected, no-op otherwise.
	refreshEyeUI()
	_sync_details_tab()
	_physics_tab.sync()
	_blend_section_helper.sync()

	var no_sprite = Global.heldSprite == null
	var dim = Color(0.3, 0.3, 0.35)
	var normal = Color(1, 1, 1)

	# Top controls
	_speaking_spr.modulate = dim if no_sprite else normal
	_blinking_spr.modulate = dim if no_sprite else normal
	_unlink_spr.modulate = dim if no_sprite else normal
	_trash_spr.modulate = dim if no_sprite else normal
	_link_btn.disabled = no_sprite
	if no_sprite:
		_link_btn.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	else:
		_link_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))

	# Costume buttons
	for btn in _costume_btns:
		btn.modulate = dim if no_sprite else normal
	_costume_select.visible = !no_sprite

	# Eye-tracking control enable/disable is handled by refreshEyeUI() above
	# based on scope (per_layer / global / dead); don't blanket-disable here.

	# Visibility Toggle
	_vis_toggle_btn.disabled = no_sprite
	_vis_toggle_delete_btn.disabled = no_sprite
	if no_sprite:
		_vis_toggle_label.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	elif not Global.awaitingToggleBind:
		_vis_toggle_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

	# Swap slider styles to "enabled" appearance whenever the eye-tracking
	# scope is interactive (per_layer or global), "disabled" only in dead scope.
	var slider_should_enable = _prev_eye_scope != "dead"
	if slider_should_enable != _slider_enabled_state:
		_slider_enabled_state = slider_should_enable
		var fill = _slider_fill_enabled if slider_should_enable else _slider_fill_disabled
		var grab = _slider_grabber_enabled if slider_should_enable else _slider_grabber_disabled
		for s in [_eye_dist_slider, _eye_speed_slider]:
			s.add_theme_stylebox_override("grabber_area", fill)
			s.add_theme_stylebox_override("grabber_area_highlight", fill)
			s.add_theme_icon_override("grabber", grab)
			s.add_theme_icon_override("grabber_highlight", grab)

	if !no_sprite:
		_speaking_spr.frame = Global.heldSprite.showOnTalk
		_blinking_spr.frame = Global.heldSprite.showOnBlink

		# Costume button frames
		for i in range(10):
			if Global.heldSprite.costumeLayers[i] == 1:
				_costume_btns[i].self_modulate = Color(1, 1, 1, 1)
			else:
				_costume_btns[i].self_modulate = Color(0.5, 0.5, 0.5, 0.7)

		# Costume select position — _costume_select is parented to the viewer
		# (free-floating), so we translate the active button's center into
		# viewer-local coordinates.
		var costume_idx = Global.main.costume - 1
		if costume_idx >= 0 and costume_idx < 10 and costume_idx < _costume_btn_widgets.size():
			var btn = _costume_btn_widgets[costume_idx]
			_costume_select.position = to_local(btn.global_position + btn.size * 0.5)

func scroll_to_selected():
	if Global.heldSprite == null:
		return
	for child in container.get_children():
		if child.sprite == Global.heldSprite:
			$ScrollContainer.ensure_control_visible(child)
			return

func scroll_to_sprite(target_sprite):
	if target_sprite == null:
		return
	for child in container.get_children():
		if child.sprite == target_sprite:
			$ScrollContainer.scroll_vertical = int(child.position.y)
			return

func updateControls():
	_sync_details_tab()
	_physics_tab.sync()
	_blend_section_helper.sync()
	if Global.heldSprite == null:
		refreshEyeUI()
		return
	_eye_toggle.set_pressed_no_signal(Global.heldSprite.eyeTrack)
	_eye_dist_label.text = "tracking distance: " + str(Global.heldSprite.eyeTrackDistance)
	_eye_dist_slider.set_value_no_signal(Global.heldSprite.eyeTrackDistance)
	_eye_speed_label.text = "tracking speed: " + str(Global.heldSprite.eyeTrackSpeed)
	_eye_speed_slider.set_value_no_signal(Global.heldSprite.eyeTrackSpeed)
	_eye_invert.set_pressed_no_signal(Global.heldSprite.eyeTrackInvert)
	_vis_toggle_label.text = "toggle: \"" + Global.heldSprite.toggle + "\""
	refreshEyeUI()

# --- Top control handlers ---

func _on_speaking_pressed():
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	var f = (_speaking_spr.frame + 1) % 3
	_speaking_spr.frame = f
	Global.heldSprite.showOnTalk = f
	Global.spriteEdit.setImage()

func _on_blinking_pressed():
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	var f = (_blinking_spr.frame + 1) % 4
	_blinking_spr.frame = f
	Global.heldSprite.showOnBlink = f
	Global.spriteEdit.setImage()

func _on_link_pressed():
	if Global.heldSprite == null:
		return
	Global.main._on_link_button_pressed()

func _on_unlink_pressed():
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	if Global.heldSprite.parentId == null:
		return
	Global.unlinkSprite()
	Global.spriteEdit.setImage()

func _on_trash_pressed():
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	Global.unlinkChildren(Global.heldSprite)
	Global.heldSprite.queue_free()
	Global.heldSprite = null
	Global.spriteList.updateData()

# --- Costume button handlers ---

func _on_costume_btn_pressed(index: int):
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[index] == 0:
		Global.heldSprite.costumeLayers[index] = 1
	else:
		Global.heldSprite.costumeLayers[index] = 0
	Global.spriteEdit.setLayerButtons()

# --- Details tab handlers (relocated from the left sidebar) ---

func _on_details_ignore_bounce_toggled(pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.ignoreBounce = pressed

func _on_details_clip_linked_toggled(pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.setClip(pressed)

func _on_details_static_toggled(pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.staticElement = pressed
	# Re-snap the dragger when toggling off so physics resumes from the rest pose
	if not pressed:
		Global.heldSprite._force_drag_snap = true

func _on_details_ndi_ref_toggled(pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	if pressed:
		for spr in get_tree().get_nodes_in_group("saved"):
			if spr != Global.heldSprite:
				spr.ndiRefLayer = false
	Global.heldSprite.ndiRefLayer = pressed
	Global.main.ndi_mark_dirty()

# Sync the Details checkboxes to the selected sprite; disabled when none.
func _sync_details_tab():
	var spr = Global.heldSprite
	var has = spr != null
	for cb in [_cb_ignore_bounce, _cb_clip_linked, _cb_static, _cb_ndi_ref]:
		cb.disabled = not has
	if has:
		_cb_ignore_bounce.set_pressed_no_signal(spr.ignoreBounce)
		_cb_clip_linked.set_pressed_no_signal(spr.clipped)
		_cb_static.set_pressed_no_signal(spr.staticElement)
		_cb_ndi_ref.set_pressed_no_signal(spr.ndiRefLayer)
	else:
		for cb in [_cb_ignore_bounce, _cb_clip_linked, _cb_static, _cb_ndi_ref]:
			cb.set_pressed_no_signal(false)

# --- Eye tracking handlers ---

func _on_eye_track_toggled(pressed):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state()
		Global.heldSprite.eyeTrack = pressed
	elif scope == "global":
		# Global scope: this is the kill switch, NOT a per-sprite toggle.
		# Per-sprite eyeTrack flags stay exactly as they are.
		UndoManager.save_state()
		Global.eyeTrackingGloballyEnabled = pressed

func _on_eye_track_dist_changed(value):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state_continuous()
		_update_eye_amount_label()
		Global.heldSprite.eyeTrackDistance = value
	elif scope == "global":
		UndoManager.save_state_continuous()
		_update_eye_amount_label()
		for spr in _eye_tracked_sprites():
			spr.eyeTrackDistance = value

func _on_eye_track_speed_changed(value):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state_continuous()
		_eye_speed_label.text = "tracking speed: " + str(value)
		Global.heldSprite.eyeTrackSpeed = value
	elif scope == "global":
		UndoManager.save_state_continuous()
		_eye_speed_label.text = "tracking speed: " + str(value)
		for spr in _eye_tracked_sprites():
			spr.eyeTrackSpeed = value

# --- Scope helpers ---
# Eye-tracking controls operate in one of three scopes:
#   "per_layer" — a sprite is selected; everything edits that sprite
#   "global"    — no selection but ≥1 sprite has eyeTrack on; controls broadcast
#                 to every eyeTrack-on sprite; enable checkbox toggles the global
#                 kill switch (Global.eyeTrackingGloballyEnabled) without
#                 touching per-sprite eyeTrack flags
#   "dead"      — no selection and no sprite has eyeTrack on; all disabled

func _eye_scope() -> String:
	if Global.heldSprite != null:
		return "per_layer"
	for spr in get_tree().get_nodes_in_group("saved"):
		if spr.eyeTrack:
			return "global"
	return "dead"

func _eye_tracked_sprites() -> Array:
	var out = []
	for spr in get_tree().get_nodes_in_group("saved"):
		if spr.eyeTrack:
			out.append(spr)
	return out

# --- Eye tracking handlers (scope-aware) ---

func _on_eye_track_invert_toggled(pressed):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state()
		Global.heldSprite.eyeTrackInvert = pressed
	elif scope == "global":
		UndoManager.save_state()
		for spr in _eye_tracked_sprites():
			spr.eyeTrackInvert = pressed

# Mode: 0 = Position (translate toward target), 1 = Rotation (swivel toward it).
func _on_eye_track_type_selected(idx):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state()
		Global.heldSprite.eyeTrackType = idx
	elif scope == "global":
		UndoManager.save_state()
		for spr in _eye_tracked_sprites():
			spr.eyeTrackType = idx
	refreshEyeUI()

# The amount slider is shared: tracking distance (px) in Position, max tilt (°) in Rotation.
func _update_eye_amount_label():
	if _eye_type_option.selected == 1:
		_eye_dist_label.text = "max tilt: " + str(_eye_dist_slider.value) + "°"
	else:
		_eye_dist_label.text = "tracking distance: " + str(_eye_dist_slider.value)

# The amount label/slider shows in both modes (its text differs per mode).
func _eye_apply_mode_visibility(_is_rot: bool):
	_eye_dist_label.visible = true
	_eye_dist_slider.visible = true

func _on_eye_track_mode_selected(idx):
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state()
		Global.heldSprite.eyeTrackMode = idx
	elif scope == "global":
		UndoManager.save_state()
		for spr in _eye_tracked_sprites():
			spr.eyeTrackMode = idx
	# Switching mode while a pick is in progress cancels the pick
	if Global.eyeTrackPickMode:
		Global._clear_eye_track_pick()
	refreshEyeUI()

func _on_eye_track_pick_pressed():
	var scope = _eye_scope()
	if scope == "per_layer":
		Global.eyeTrackPickMode = true
		Global.eyeTrackPickSource = Global.heldSprite
		Global.eyeTrackPickBroadcast = false
		Global.pushUpdate("Click a layer to track (right-click to cancel).")
	elif scope == "global":
		Global.eyeTrackPickMode = true
		Global.eyeTrackPickSource = null
		Global.eyeTrackPickBroadcast = true
		Global.pushUpdate("Click a layer to broadcast as target (right-click to cancel).")
	refreshEyePickWhip()

func _on_eye_track_target_clear():
	# No-op if there's nothing to clear (avoids spurious undo snapshots)
	if _full_eye_target_name() == "":
		return
	var scope = _eye_scope()
	if scope == "per_layer":
		UndoManager.save_state()
		Global.heldSprite.eyeTrackTargetId = null
	elif scope == "global":
		UndoManager.save_state()
		for spr in _eye_tracked_sprites():
			spr.eyeTrackTargetId = null
	refreshEyeUI()

# Right-click on the mode dropdown: in Layer mode, clear the picked target.
# In Cursor mode, do nothing so a stray right-click doesn't lose state the
# user can't see while Cursor is selected.
func _on_eye_mode_option_gui_input(event: InputEvent):
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
		return
	if _eye_mode_option.selected != 1:
		return
	_eye_mode_option.accept_event()
	_on_eye_track_target_clear()

# Sync the eye-track UI state to the current scope. Called from _process so the
# scope re-evaluates as the user toggles things, plus from updateControls() on
# selection change for an immediate refresh. Tracks scope transitions so
# global-scope values reset to neutral only on first entry, not every frame.
func refreshEyeUI():
	var scope = _eye_scope()
	var transitioned = scope != _prev_eye_scope
	_prev_eye_scope = scope
	# The enable checkbox is the per-layer toggle when a layer is selected, and the global
	# kill switch otherwise — label it so the active scope is obvious.
	_eye_toggle.text = "Enable (Layer)" if Global.heldSprite != null else "Enable (Global)"
	if scope == "per_layer":
		_refresh_eye_ui_per_layer()
	elif scope == "global":
		_refresh_eye_ui_global(transitioned)
	else:
		_refresh_eye_ui_dead()

func _refresh_eye_ui_per_layer():
	var spr = Global.heldSprite
	_eye_toggle.disabled = false
	_eye_toggle.set_pressed_no_signal(spr.eyeTrack)
	_eye_type_option.disabled = false
	_eye_type_option.selected = spr.eyeTrackType
	_eye_apply_mode_visibility(spr.eyeTrackType == 1)
	_eye_mode_option.disabled = false
	_eye_mode_option.selected = spr.eyeTrackMode
	_eye_invert.disabled = false
	_eye_invert.set_pressed_no_signal(spr.eyeTrackInvert)
	_eye_dist_slider.editable = true
	_eye_speed_slider.editable = true
	_eye_dist_slider.set_value_no_signal(spr.eyeTrackDistance)
	_eye_speed_slider.set_value_no_signal(spr.eyeTrackSpeed)
	_update_eye_amount_label()
	_eye_speed_label.text = "tracking speed: " + str(spr.eyeTrackSpeed)
	var layer_mode = spr.eyeTrackMode == 1
	_eye_pick_btn.visible = layer_mode
	_eye_pick_btn.disabled = false
	# Layer-item text shows the target name (truncated) when one is picked.
	# Right-clicking the dropdown in Layer mode clears the target.
	_update_layer_item_label()

func _refresh_eye_ui_global(_reset_values: bool):
	# Enable checkbox reflects the global kill switch (interactable, NOT per-sprite)
	_eye_toggle.disabled = false
	_eye_toggle.set_pressed_no_signal(Global.eyeTrackingGloballyEnabled)
	_eye_type_option.disabled = false
	_eye_mode_option.disabled = false
	_eye_invert.disabled = false
	_eye_dist_slider.editable = true
	_eye_speed_slider.editable = true

	# Always sync the UI to the agreed state across eye-tracking sprites. This
	# avoids drift where the dropdown lies about the actual per-sprite mode
	# (e.g. sprites at Layer but UI stuck on Cursor from an old "reset on
	# transition" code path). When sprites disagree, fall back to neutral.
	var agreed_type = _agreed_eye_value("eyeTrackType")
	var agreed_mode = _agreed_eye_value("eyeTrackMode")
	var agreed_invert = _agreed_eye_value("eyeTrackInvert")
	var agreed_dist = _agreed_eye_value("eyeTrackDistance")
	var agreed_speed = _agreed_eye_value("eyeTrackSpeed")
	_eye_type_option.selected = (agreed_type if agreed_type != null else 0)
	_eye_apply_mode_visibility(agreed_type == 1)
	_eye_mode_option.selected = (agreed_mode if agreed_mode != null else 0)
	_eye_invert.set_pressed_no_signal(agreed_invert if agreed_invert != null else false)
	_eye_dist_slider.set_value_no_signal(agreed_dist if agreed_dist != null else _eye_dist_slider.min_value)
	_eye_speed_slider.set_value_no_signal(agreed_speed if agreed_speed != null else _eye_speed_slider.min_value)

	_update_eye_amount_label()
	_eye_speed_label.text = "tracking speed: " + str(_eye_speed_slider.value)
	# Pick button only relevant when mode is Layer
	_eye_pick_btn.visible = _eye_mode_option.selected == 1
	_eye_pick_btn.disabled = false
	# Right-clicking the dropdown in Layer mode broadcasts a clear, which restores
	# the dropdown's "Layer" label.
	_update_layer_item_label()

# Return the value of `prop` if every eye-tracking sprite has the same value,
# null when mixed or there are no eye-tracking sprites.
func _agreed_eye_value(prop: String):
	var first = true
	var agreed = null
	for s in get_tree().get_nodes_in_group("saved"):
		if not s.eyeTrack:
			continue
		if first:
			agreed = s.get(prop)
			first = false
		elif s.get(prop) != agreed:
			return null
	return agreed

func _refresh_eye_ui_dead():
	_eye_toggle.disabled = true
	_eye_toggle.set_pressed_no_signal(false)
	_eye_type_option.disabled = true
	_eye_type_option.selected = 0
	_eye_apply_mode_visibility(false)
	_eye_mode_option.disabled = true
	_eye_mode_option.selected = 0
	_eye_invert.disabled = true
	_eye_invert.set_pressed_no_signal(false)
	_eye_dist_slider.editable = false
	_eye_speed_slider.editable = false
	_eye_dist_slider.set_value_no_signal(_eye_dist_slider.min_value)
	_eye_speed_slider.set_value_no_signal(_eye_speed_slider.min_value)
	_eye_dist_label.text = "tracking distance: —"
	_eye_speed_label.text = "tracking speed: —"
	_eye_pick_btn.visible = false
	_eye_mode_option.set_item_text(1, "Layer")

# Resolve the eye-track target name for the current scope/state. Returns "" when
# there's nothing single to display:
#   per-layer scope — sprite's target if in Layer mode, else ""
#   global scope    — broadcast target if every eyeTrack sprite shares the same
#                     non-null targetId (the state right after a global Pick),
#                     else ""
func _full_eye_target_name() -> String:
	if Global.heldSprite != null:
		var spr = Global.heldSprite
		if spr.eyeTrackMode != 1 or spr.eyeTrackTargetId == null:
			return ""
		var nodes = get_tree().get_nodes_in_group(str(spr.eyeTrackTargetId))
		if nodes.size() == 0:
			return ""
		return _display_target_name(nodes[0])

	# Global scope: only show a name if every eye-tracking sprite points at the
	# same target. Mixed targets or any null target → no unambiguous label.
	var target_id = null
	var initialized = false
	for s in get_tree().get_nodes_in_group("saved"):
		if not s.eyeTrack:
			continue
		if not initialized:
			target_id = s.eyeTrackTargetId
			initialized = true
		elif s.eyeTrackTargetId != target_id:
			return ""
	if not initialized or target_id == null:
		return ""
	var t_nodes = get_tree().get_nodes_in_group(str(target_id))
	if t_nodes.size() == 0:
		return ""
	return _display_target_name(t_nodes[0])

# Update the dropdown's "Layer" item text to show the target name (truncated to
# 8 chars + ellipsis) when one is set in per-layer scope. Reverts to "Layer"
# in all other cases.
func _update_layer_item_label():
	var full = _full_eye_target_name()
	if full == "":
		_eye_mode_option.set_item_text(1, "Layer")
		return
	var truncated = full if full.length() <= 8 else full.substr(0, 8) + "…"
	_eye_mode_option.set_item_text(1, truncated)

func _on_eye_mode_option_hover():
	if _full_eye_target_name() == "":
		return
	_eye_mode_tooltip_timer.start()

func _on_eye_mode_option_unhover():
	_eye_mode_tooltip_timer.stop()
	if _eye_mode_tooltip_label != null:
		_eye_mode_tooltip_label.visible = false

func _on_eye_mode_tooltip_show():
	var full = _full_eye_target_name()
	if full == "":
		return
	_eye_mode_tooltip_label.text = full
	# Position just below the dropdown — use global_position because the
	# dropdown lives inside nested containers now, not directly in _eye_section.
	var anchor_global = _eye_mode_option.global_position + Vector2(0, _eye_mode_option.size.y + 4)
	_eye_mode_tooltip_label.position = to_local(anchor_global)
	_eye_mode_tooltip_label.visible = true

func _display_target_name(target_sprite) -> String:
	var p = target_sprite.path
	if p == null:
		return "(unnamed)"
	var leaf = p.get_file()
	if leaf == "":
		leaf = p
	# Trim file extension if present
	var dot = leaf.rfind(".")
	if dot > 0:
		leaf = leaf.substr(0, dot)
	return leaf

# Update the eye-pick whip visual. Called from main.gd's _process so the line
# follows the cursor while pick mode is active.
func refreshEyePickWhip():
	if _eye_whip_line == null:
		return
	if Global.eyeTrackPickMode and _eye_pick_btn != null and _eye_pick_btn.visible:
		var anchor_global = _eye_pick_btn.global_position + _eye_pick_btn.size * 0.5
		var anchor_local = to_local(anchor_global)
		var mouse_local = to_local(get_global_mouse_position())
		_eye_whip_line.clear_points()
		_eye_whip_line.add_point(anchor_local)
		_eye_whip_line.add_point(mouse_local)
		_eye_whip_line.visible = true
	else:
		_eye_whip_line.visible = false

# --- Visibility Toggle handlers ---

func _on_set_toggle_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	_vis_toggle_label.text = "toggle: AWAITING INPUT"
	_vis_toggle_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.8))
	Global.awaitingToggleBind = true
	await Global.main.fatfuckingballs
	var keys = await Global.main.spriteVisToggles
	Global.awaitingToggleBind = false
	var key = keys[0]
	if Global.heldSprite == null: return
	Global.heldSprite.toggle = key
	_vis_toggle_label.text = "toggle: \"" + Global.heldSprite.toggle + "\""
	_vis_toggle_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

func _on_vis_toggle_delete_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.toggle = "null"
	_vis_toggle_label.text = "toggle: \"" + Global.heldSprite.toggle + "\""
	Global.heldSprite.makeVis()

# --- Resize and drag ---

func _is_on_left_edge(local: Vector2) -> bool:
	var left = -4.0
	if local.x < left - GRAB_MARGIN or local.x > left + GRAB_MARGIN:
		return false
	if local.y < -4 - GRAB_MARGIN or local.y > panel_height + GRAB_MARGIN:
		return false
	return true

func _is_on_divider(local: Vector2) -> bool:
	# Divider2 lives Global.UI_DIVIDER_PAD below the scroll bottom (= panel_height * _divider_ratio).
	# Must match the position set in _apply_size().
	var divider_y = panel_height * _divider_ratio + Global.UI_DIVIDER_PAD
	if abs(local.y - divider_y) > GRAB_MARGIN:
		return false
	if local.x < 0 or local.x > panel_width:
		return false
	return true

func _input(event):
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

	if event is InputEventMouseButton and event.pressed and _filter_field.has_focus():
		var local = get_local_mouse_position()
		var field_rect = Rect2(_filter_field.position, _filter_field.size)
		if not field_rect.has_point(local):
			_filter_field.release_focus()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_on_left_edge(get_local_mouse_position()):
				_dragging = true
				_drag_start = get_global_mouse_position()
				_drag_start_width = panel_width
				get_viewport().set_input_as_handled()
			elif _is_on_divider(get_local_mouse_position()):
				_divider_dragging = true
				get_viewport().set_input_as_handled()
		else:
			if _dragging:
				_dragging = false
				Saving.settings["rightSidebarWidth"] = panel_width
				Saving.write_settings(Saving.settingsPath)
				get_viewport().set_input_as_handled()
			if _divider_dragging:
				_divider_dragging = false
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging:
			var delta = get_global_mouse_position() - _drag_start
			var viewport_width = get_viewport().get_visible_rect().size.x
			var max_width = maxf(MIN_WIDTH, viewport_width * MAX_WIDTH_RATIO)
			panel_width = clamp(_drag_start_width - delta.x, MIN_WIDTH, max_width)
			_apply_size()
			get_viewport().set_input_as_handled()
		elif _divider_dragging:
			var local = get_local_mouse_position()
			var min_y = (CONTROLS_ROW_HEIGHT + 60.0 + _blend_section.get_combined_minimum_size().y) / panel_height
			var max_y = (panel_height - 280.0) / panel_height
			_divider_ratio = clamp(local.y / panel_height, min_y, max_y)
			_apply_size()
			get_viewport().set_input_as_handled()
		else:
			var local = get_local_mouse_position()
			var on_left = _is_on_left_edge(local)
			var on_divider = _is_on_divider(local)
			if on_left != _hover_left or on_divider != _hover_divider:
				_hover_left = on_left
				_hover_divider = on_divider
				if on_left:
					Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
				elif on_divider:
					Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
				else:
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)

# --- Layer list data ---

func updateData(sort_by_z: bool = true):
	_filter_field.text = ""
	_saved_collapse_states = {}
	for child in container.get_children():
		if is_instance_valid(child.sprite) and child.collapsed:
			_saved_collapse_states[child.sprite.id] = true
	clearContainer()
	_update_generation += 1
	var my_generation = _update_generation
	await get_tree().process_frame
	if my_generation != _update_generation:
		return
	var spritesAll = get_tree().get_nodes_in_group("saved")

	if sort_by_z:
		spritesAll.sort_custom(func(a, b): return a.z > b.z)

	var spritesWithParents = []
	var allSprites = []

	for sprite in spritesAll:
		var listObj = SpriteListObject.new()
		listObj.spritePath = sprite.path
		listObj.sprite = sprite
		listObj.parent = sprite.parentSprite
		# Fallback: look up parent by ID when parentSprite isn't set yet (e.g. during load)
		if listObj.parent == null and sprite.parentId != null:
			for other in spritesAll:
				if other.id == sprite.parentId:
					listObj.parent = other
					break
		if listObj.parent != null:
			spritesWithParents.append(listObj)
		allSprites.append(listObj)

		container.add_child(listObj)

	# Build parent-child relationships
	for child in spritesWithParents:
		for obj in allSprites:
			if child.parent == obj.sprite:
				child.parentTag = obj
				obj.childrenTags.append(child)
				break

	# DFS flatten: roots first, then children in z-sorted order
	var roots = []
	for obj in allSprites:
		if obj.parentTag == null:
			roots.append(obj)

	var final_order = []
	var stack = []
	for i in range(roots.size() - 1, -1, -1):
		stack.append(roots[i])
	while stack.size() > 0:
		var node = stack.pop_back()
		final_order.append(node)
		for i in range(node.childrenTags.size() - 1, -1, -1):
			stack.append(node.childrenTags[i])

	for i in range(final_order.size()):
		container.move_child(final_order[i], i)

	# Compute indent by chain-walk (order-independent)
	for obj in final_order:
		obj.indent = 0
		var ancestor = obj.parentTag
		while ancestor != null:
			obj.indent += 1
			ancestor = ancestor.parentTag
		if obj.childrenTags.size() > 0:
			obj._collapse_btn.text = "▼"
			obj._collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		obj.updateIndent()

	# Restore collapse states from before rebuild
	for obj in final_order:
		if _saved_collapse_states.has(obj.sprite.id):
			obj.collapsed = true
			obj._collapse_btn.text = "▶"
			obj._set_descendants_visible(false)

	if _pending_scroll_target != null:
		var target = _pending_scroll_target
		_pending_scroll_target = null
		await get_tree().process_frame
		scroll_to_sprite(target)

func refreshHierarchy():
	var items = container.get_children()
	if items.size() == 0:
		return

	# Reset relationships
	for obj in items:
		obj.childrenTags = []
		obj.parentTag = null
		obj.indent = 0
		obj.collapsed = false
		obj._collapse_btn.text = ""
		obj._collapse_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		obj.parent = obj.sprite.parentSprite

	# Build parent-child relationships
	for obj in items:
		if obj.parent != null:
			for other in items:
				if obj.parent == other.sprite:
					obj.parentTag = other
					other.childrenTags.append(obj)
					break

	# DFS flatten
	var roots = []
	for obj in items:
		if obj.parentTag == null:
			roots.append(obj)

	var final_order = []
	var stack = []
	for i in range(roots.size() - 1, -1, -1):
		stack.append(roots[i])
	while stack.size() > 0:
		var node = stack.pop_back()
		final_order.append(node)
		for i in range(node.childrenTags.size() - 1, -1, -1):
			stack.append(node.childrenTags[i])

	for i in range(final_order.size()):
		container.move_child(final_order[i], i)

	# Compute indent by chain-walk
	for obj in final_order:
		obj.indent = 0
		var ancestor = obj.parentTag
		while ancestor != null:
			obj.indent += 1
			ancestor = ancestor.parentTag
		if obj.childrenTags.size() > 0:
			obj._collapse_btn.text = "▼"
			obj._collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		obj.updateIndent()

	if _pending_scroll_target != null:
		var target = _pending_scroll_target
		_pending_scroll_target = null
		await get_tree().process_frame
		scroll_to_sprite(target)

func clearContainer():
	for i in container.get_children():
		i.queue_free()

func _on_filter_changed(text: String):
	var filter = text.to_lower()
	if filter == "":
		for child in container.get_children():
			child.visible = true
		for child in container.get_children():
			if child.collapsed:
				child._set_descendants_visible(false)
		return

	# Hide all first
	for child in container.get_children():
		child.visible = false

	# Show matches and their full ancestor chains
	for child in container.get_children():
		if child._name_label.text.to_lower().begins_with(filter):
			child.visible = true
			var ancestor = child.parentTag
			while ancestor != null:
				ancestor.visible = true
				ancestor = ancestor.parentTag

func updateAllVisible():
	for i in container.get_children():
		i.updateVis()
