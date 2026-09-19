extends Node2D

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const LayerTreeController = preload("res://ui_scenes/spriteList/layer_tree_controller.gd")
const EyeTrackingPanel = preload("res://ui_scenes/spriteList/eye_tracking_panel.gd")
const LayerDetailsPanel = preload("res://ui_scenes/spriteList/layer_details_panel.gd")
const LayerContextMenu = preload("res://ui_scenes/spriteList/layer_context_menu.gd")
const VisibilityToggleSection = preload("res://ui_scenes/spriteList/visibility_toggle_section.gd")
const SpriteVisibility = preload("res://ui_scenes/selectedSprite/sprite_visibility_policy.gd")

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

var _eye_tracking = EyeTrackingPanel.new()

const BOTTOM_MARGIN = 12
var _tab_bar: AppTabBar
var _tab_scroll: ScrollContainer
var _tab_host: VBoxContainer
var _details_content: VBoxContainer
var _eye_content: VBoxContainer
var _physics_content: VBoxContainer
var _physics_tab: WigglePhysicsTab

var _details_panel = LayerDetailsPanel.new()

var _slider_fill_enabled: StyleBoxFlat
var _slider_fill_disabled: StyleBoxFlat
var _slider_grabber_enabled: ImageTexture
var _slider_grabber_disabled: ImageTexture
var _slider_theme: Dictionary

var _vis_toggle = VisibilityToggleSection.new()
var _divider4: ColorRect

var _filter_field: LineEdit

# Opacity + Blend strip, pinned to the bottom of the layer-list region (above the draggable
# divider). Built by a dedicated module (ui_scenes/spriteList/blend_section.gd).
var _blend_section_helper: BlendOpacitySection
var _blend_section: VBoxContainer

var _layer_tree = LayerTreeController.new()
var _dragging = false
var _drag_start = Vector2.ZERO
var _drag_start_width: float = 0
var _hover_left = false
var _divider_ratio: float = 0.50
var _divider_dragging = false
var _hover_divider = false


func _exit_tree() -> void:
	Global.detach_sprite_list(self)


func _ready():
	Global.attach_sprite_list(self)
	_layer_tree.setup(self, container, $ScrollContainer, Global, SpriteListObject)
	container.add_theme_constant_override("separation", 2)
	$Area2D2/CollisionShape2D.disabled = false
	$NinePatchRect.visible = false
	_bg = SidebarUIFactory.create_panel_background()
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
	panel_width = SidebarUIFactory.clamp_panel_width(
		saved_w, get_viewport().get_visible_rect().size.x, MIN_WIDTH, MAX_WIDTH_RATIO,
	)

	# Restore the active tab before the first layout pass.
	var saved_tab = clamp(int(Saving.settings.get("rightSidebarTab", 0)), 0, 2)
	_tab_bar.set_active(saved_tab)
	_show_tab(saved_tab)

	_apply_size()

# Build the shared slider fill/grabber resources once, before any section
# attaches them (eye tracking, physics). Mirrors the left sidebar's slider look.
func _build_slider_styles():
	_slider_theme = SidebarUIFactory.create_slider_theme()
	_slider_fill_enabled = _slider_theme["fill_enabled"]
	_slider_fill_disabled = _slider_theme["fill_disabled"]
	_slider_grabber_enabled = _slider_theme["grab_enabled"]
	_slider_grabber_disabled = _slider_theme["grab_disabled"]

func _create_controls():
	_divider1 = SidebarUIFactory.create_divider(Vector2(panel_width - 16, 1))
	add_child(_divider1)

	_divider2 = SidebarUIFactory.create_divider(Vector2(panel_width - 16, 1))
	add_child(_divider2)

	_divider3 = SidebarUIFactory.create_divider(Vector2(panel_width - 16, 1))
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

# An icon-style button (Button + Sprite2D inside) on _controls. Returns the inner
# Sprite2D so callers can tint or animate it.
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

# The Opacity + Blend strip, with the shared slider styles. The sidebar positions
# it in _apply_size (bottom of the layer-list region, above the divider).
func _create_blend_section():
	_blend_section_helper = BlendOpacitySection.new()
	_blend_section = _blend_section_helper.build(self, _slider_fill_enabled,
		_slider_fill_disabled, _slider_grabber_enabled, _slider_grabber_disabled)

# Build the tab strip + the scrollable host that holds the three tab contents.
# Only the active content is visible; the scroll lets a tall tab (Physics) grow
# into whatever vertical space is available below the costume row.
func _create_tabs():
	_tab_bar = AppTabBar.new()
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
	_details_panel.build(_details_content, Global, UndoManager)

# Physics tab — wiggle controls (effects/wiggle). Built by a dedicated module so
# this file stays focused on sidebar structure.
func _create_physics_tab():
	_physics_tab = WigglePhysicsTab.new()
	_physics_tab.build(_physics_content, _slider_fill_enabled, _slider_fill_disabled,
		_slider_grabber_enabled, _slider_grabber_disabled)

func _create_eye_tracking():
	_eye_tracking.build(self, _eye_content, Global, UndoManager, SidebarUIFactory, _slider_theme)

func _create_vis_toggle():
	# Divider above the vis-toggle section, a ColorRect because it is positioned
	# independently from both sections.
	_divider4 = SidebarUIFactory.create_divider(Vector2(panel_width - 16, 1))
	add_child(_divider4)
	_vis_toggle.build(self)

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
	# The scroll container sizes the column (see layer_tree_controller.reflow).
	container.custom_minimum_size.x = 0
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layer_tree.reflow()
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
	y += AppTabBar.BAR_HEIGHT + Global.UI_ROW_GAP

	var vis_h = _vis_toggle.section.get_combined_minimum_size().y
	var vis_y = panel_height - vis_h - BOTTOM_MARGIN
	var divider4_y = vis_y - Global.UI_DIVIDER_PAD
	var tab_bottom = divider4_y - Global.UI_DIVIDER_PAD

	_tab_scroll.position = Vector2(section_x, y)
	_tab_scroll.size = Vector2(section_width, max(0.0, tab_bottom - y))

	_divider4.position = Vector2(8, divider4_y)
	_divider4.size.x = panel_width - 16

	_vis_toggle.section.position = Vector2(section_x, vis_y)
	_vis_toggle.section.size = Vector2(section_width, vis_h)

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
	_details_panel.sync()
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

	_vis_toggle.set_enabled(not no_sprite)

	if !no_sprite:
		_speaking_spr.frame = Global.heldSprite.showOnTalk
		_blinking_spr.frame = Global.heldSprite.showOnBlink

		# Costume button frames. A costume the layer belongs to still reads as off
		# when an ancestor is out of that costume, because the parent's hidden
		# node hides this one too. Showing it lit would promise a layer the
		# viewer never sees.
		var ancestor_layers := _ancestor_costume_chain(Global.heldSprite)
		for i in range(10):
			var on: bool = Global.heldSprite.costumeLayers[i] == 1 \
				and SpriteVisibility.costume_allowed_by_ancestors(ancestor_layers, i + 1)
			if on:
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
	_layer_tree.scroll_to_selected()

func scroll_to_sprite(target_sprite):
	_layer_tree.scroll_to_sprite(target_sprite)

func updateControls():
	_details_panel.sync()
	_physics_tab.sync()
	_blend_section_helper.sync()
	refreshEyeUI()
	_vis_toggle.refresh()

# --- Top control handlers ---

func _on_speaking_pressed():
	if Global.heldSprite == null:
		return
	var f = (_speaking_spr.frame + 1) % 3
	_speaking_spr.frame = f
	MutationCommands.set_layer_property(Global.heldSprite, "showOnTalk", f)
	Global.spriteEdit.setImage()

func _on_blinking_pressed():
	if Global.heldSprite == null:
		return
	var f = (_blinking_spr.frame + 1) % 4
	_blinking_spr.frame = f
	MutationCommands.set_layer_property(Global.heldSprite, "showOnBlink", f)
	Global.spriteEdit.setImage()

func _on_link_pressed():
	if Global.heldSprite == null:
		return
	Global.main.begin_link_mode()

func _on_unlink_pressed():
	if Global.heldSprite == null:
		return
	if Global.heldSprite.parentId == null:
		return
	MutationCommands.structural(func():
		Global.unlinkSprite()
		return true)
	Global.spriteEdit.setImage()

func _on_trash_pressed():
	if Global.heldSprite == null:
		return
	LayerContextMenu.confirm_delete(self, Global.heldSprite)

# --- Costume button handlers ---

# This layer's ancestors' costumeLayers, nearest parent first. Guarded against a
# cycle in parentId so a malformed save can't spin the sidebar refresh.
func _ancestor_costume_chain(sprite) -> Array:
	var chain := []
	var seen := {}
	var current = sprite.parentId
	while current != null and not seen.has(current):
		seen[current] = true
		var ancestor = Global.sprite_by_id(current)
		if ancestor == null or not is_instance_valid(ancestor):
			break
		chain.append(ancestor.costumeLayers)
		current = ancestor.parentId
	return chain


func _on_costume_btn_pressed(index: int):
	if Global.heldSprite == null:
		return
	var layers: Array = Global.heldSprite.costumeLayers.duplicate()
	layers[index] = 0 if layers[index] == 1 else 1
	MutationCommands.set_layer_property(Global.heldSprite, "costumeLayers", layers)
	Global.spriteEdit.setLayerButtons()

# Keep the established sidebar API while the panel owns eye-tracking behavior.
func refreshEyeUI() -> void:
	_eye_tracking.refresh_ui()

func refreshEyePickWhip() -> void:
	_eye_tracking.refresh_pick_whip()

# --- Resize and drag ---

func _is_on_left_edge(local: Vector2) -> bool:
	return SidebarUIFactory.is_near_vertical_edge(local, -4.0, GRAB_MARGIN, -4.0, panel_height)

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
			panel_width = SidebarUIFactory.clamp_panel_width(
				_drag_start_width - delta.x, viewport_width, MIN_WIDTH, MAX_WIDTH_RATIO,
			)
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
	await _layer_tree.update_data(sort_by_z)

func layersBetween(a, b) -> Array:
	return _layer_tree.layers_between(a, b)


func refreshNames():
	_layer_tree.refresh_names()

func rowFor(sprite) -> Node:
	return _layer_tree.row_for(sprite)

# Centre these layers in the list after the next layout. See
# layer_tree_controller.frame_sprites.
func frameLayers(sprites: Array):
	await _layer_tree.frame_sprites(sprites)

# Rename this layer on its own row. Returns false when the list has no row to
# edit, which is the caller's cue that nothing happened.
func beginRename(sprite) -> bool:
	var row := rowFor(sprite)
	if row == null or not row.visible:
		return false
	row.beginRename()
	return true

# Widen the sidebar so the deepest layer in this avatar shows its indentation in
# full, rather than having it compressed away by the row budget. Called when an
# avatar is loaded, since that is when the rig's depth is known and when the user
# is not in the middle of reading the list. It only ever grows the panel, and
# never past the usual maximum; names truncate instead, which is what the panel
# is already built to do.
func fitPanelToDepth():
	var extra: float = _layer_tree.extra_width_for_full_indent(panel_width)
	if extra <= 0.0:
		return
	var target: float = SidebarUIFactory.clamp_panel_width(
		panel_width + extra, get_viewport().get_visible_rect().size.x, MIN_WIDTH, MAX_WIDTH_RATIO,
	)
	if target <= panel_width:
		return
	panel_width = target
	_apply_size()


# Rows in line with the live layers, in place (delete, duplicate, undo).
func syncRows(sort_by_z: bool = true):
	_layer_tree.sync_rows(sort_by_z)
	if not _filter_field.text.is_empty():
		_layer_tree.filter(_filter_field.text)


func refreshHierarchy():
	await _layer_tree.refresh_hierarchy()

# Where the list should land once a link's rebuild is done. See
# layer_tree_controller.prepare_link_framing.
func prepareLinkFraming(child, parent, parent_picked_on_canvas: bool):
	_layer_tree.prepare_link_framing(child, parent, parent_picked_on_canvas)

func _on_filter_changed(text: String):
	_layer_tree.filter(text)

func updateAllVisible():
	_layer_tree.update_all_visible()
