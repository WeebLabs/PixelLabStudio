extends Node2D

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const NormalMapPanel = preload("res://ui_scenes/spriteEditMenu/normal_map_panel.gd")
const VectorFieldRow = preload("res://ui_scenes/spriteEditMenu/vector_field_row.gd")
const RotationPreviewRenderer = preload("res://ui_scenes/spriteEditMenu/rotation_preview_renderer.gd")
const SelectionPresenter = preload("res://ui_scenes/spriteEditMenu/selection_presenter.gd")

@onready var spriteRotDisplay = $RotationalLimits/RotBack/SpriteDisplay

var _preview: Sprite2D
var _parent_label: Label


@onready var coverCollider = $Area2D/CollisionShape2D

var _bg: ColorRect
var panel_width: float = 265
var panel_height: float = 630
var content_height: float = 0.0

const ROT_RADIUS = 105.0           # rotation-circle visualization radius at full panel width
const ROT_CONTROLS_GAP = 20.0      # gap between the circle and the min/max label rows
const DEFAULT_PANEL_WIDTH = 265.0  # baseline; preview & rotation circle scale down below this
const PREVIEW_MAX_W = 240.0
const PREVIEW_MAX_H = 120.0
const PREVIEW_Y = 65.0             # preview center-y (top half of panel)

# Resize handle
const MIN_PANEL_WIDTH = 220        # minimum sidebar width (clamps the drag)
const MAX_PANEL_WIDTH_RATIO = 0.4  # max sidebar width as a fraction of the viewport
const GRAB_MARGIN = 6              # pixels of horizontal grab tolerance around the right edge

var _resize_dragging: bool = false
var _resize_drag_start_x: float = 0.0
var _resize_drag_start_width: float = 0.0
var _resize_hover: bool = false

var _resizables: Array = []
var _dividers: Array = []
var _controls_enabled: bool = false
var _sliders: Array = []
var _buttons: Array = []
var _sections: Array = []

var _tab_bar: AppTabBar
var _active_left_tab: int = 0
var _anim_panel: AnimationClipPanel
var _anim_section: Node2D       # Node2D wrapper so _place_section can lay it out
var _anim_panel_root: Control   # the clip-panel VBox (sized via _resizables)

var _slider_fill_enabled: StyleBoxFlat
var _slider_fill_disabled: StyleBoxFlat
var _slider_grabber_enabled: ImageTexture
var _slider_grabber_disabled: ImageTexture
var _slider_theme: Dictionary

# Normal map section
var _normal_section: Control
var _normal_panel = NormalMapPanel.new()
var _rotation_renderer = RotationPreviewRenderer.new()
var _selection_presenter = SelectionPresenter.new()

# Slider section — single label + DragSlider, reparented into VBox.
var _slider_vbox: VBoxContainer
var _drag_label: Label
var _drag_slider: HSlider

# Rotation section — squash + rDrag pairs.
var _rotation_vbox: VBoxContainer
var _squash_label: Label
var _squash_slider: HSlider
var _rdrag_label: Label
var _rdrag_slider: HSlider

# Animation section — animFrames + animSpeed pairs.
var _animation_vbox: VBoxContainer
var _anim_frames_label: Label
var _anim_frames_slider: HSlider
var _anim_speed_label: Label
var _anim_speed_slider: HSlider

# Position section — parent label + 3 info labels (position / offset / layer).
var _position_vbox: VBoxContainer
var _pos_label: Label
var _offset_label: Label
var _pos_fields = VectorFieldRow.new()
var _offset_fields = VectorFieldRow.new()
var _layer_label: Label

# RotationalLimits — circle visualization at top + a VBox of min/max
# label+slider rows below. The bounds Control wraps both so the layout pass
# can place the section like any other.
var _rot_bounds: Control
var _rot_controls_vbox: VBoxContainer
var _rot_min_label: Label
var _rot_min_slider: HSlider
var _rot_max_label: Label
var _rot_max_slider: HSlider
# Preview thumbnail base scale (the value setImage() computes from the texture
# size assuming full panel width); _apply_size() multiplies this by the
# current panel-width factor to get the actual scale.
var _preview_base_scale: float = 1.0


func _exit_tree() -> void:
	Global.detach_sprite_edit(self)


func _ready():
	Global.attach_sprite_edit(self)
	$RotationalLimits/RotBorder.visible = false

	# Create static 2D sprite preview
	_preview = Sprite2D.new()
	_preview.position = Vector2(123, 65)
	add_child(_preview)

	# Position section — parent label + 3 info labels in a VBoxContainer.
	# Replaces the prior offset-by-hand layout (and the offset shifts that used
	# to push Label/Label2/Label3 down to make room for _parent_label).
	_parent_label = Label.new()
	_parent_label.text = "Root Element"
	_pos_label = get_node("Position/Label")
	_offset_label = get_node("Position/Label2")
	_layer_label = get_node("Position/Label3")
	# Position and offset are typed in, not just read: the labels they replace
	# only ever displayed what the canvas drag had already done.
	_pos_fields.build("position")
	_offset_fields.build("offset")
	_position_vbox = _build_section_vbox($Position, Vector2(10, 155), 226,
		[_parent_label, _pos_fields.row, _offset_fields.row, _layer_label])
	_pos_label.visible = false
	_offset_label.visible = false

	# (Section position shifts are consolidated into a single block below the
	# VBox creation — see "Section layout" comment further down.)

	# Containerize the label+slider sections. Each scene-defined section node
	# (Slider, Rotation, Animation) gets a VBoxContainer placed
	# at the original first-widget offset; the section's existing children are
	# reparented into it in display order, sliders set to SIZE_EXPAND_FILL.

	# Slider — single drag label + DragSlider
	_drag_label = get_node("Slider/Label")
	_drag_slider = get_node("Slider/DragSlider")
	_slider_vbox = _build_section_vbox($Slider, Vector2(9, 155), 223,
		[_drag_label, _drag_slider])

	# Rotation — squash + rDrag (note: scene order has squash first visually)
	_squash_label = get_node("Rotation/squashlabel")
	_squash_slider = get_node("Rotation/squash")
	_rdrag_label = get_node("Rotation/rDragLabel")
	_rdrag_slider = get_node("Rotation/rDrag")
	_rotation_vbox = _build_section_vbox($Rotation, Vector2(11, 156), 223,
		[_squash_label, _squash_slider, _rdrag_label, _rdrag_slider])

	# Animation — animFrames + animSpeed
	_anim_frames_label = get_node("Animation/animFramesLabel")
	_anim_frames_slider = get_node("Animation/animFrames")
	_anim_speed_label = get_node("Animation/animSpeedLabel")
	_anim_speed_slider = get_node("Animation/animSpeed")
	_animation_vbox = _build_section_vbox($Animation, Vector2(10, 984), 223,
		[_anim_frames_label, _anim_frames_slider, _anim_speed_label, _anim_speed_slider])

	# RotationalLimits min/max widgets — cached here so the _sliders array and
	# make_slider_resettable calls can reference them. The actual VBox is
	# constructed below alongside _rot_bounds.
	_rot_min_label = get_node("RotationalLimits/RotLimitMin")
	_rot_min_slider = get_node("RotationalLimits/rotLimitMin")
	_rot_max_label = get_node("RotationalLimits/RotLimitMax")
	_rot_max_slider = get_node("RotationalLimits/rotLimitMax")

	# Collect interactive controls for enable/disable toggling
	_sliders = [
		_drag_slider,
		_rdrag_slider, _squash_slider,
		_rot_min_slider, _rot_max_slider,
		_anim_speed_slider, _anim_frames_slider,
	]
	# Plain scroll scrolls the panel; only Ctrl+scroll adjusts (global.gd:_input).
	for _s in _sliders:
		_s.scrollable = false

	# Right-click resets each sprite-property slider to spriteObject.gd's factory default
	Global.make_slider_resettable(_drag_slider, 0)
	Global.make_slider_resettable(_rdrag_slider, 0)
	Global.make_slider_resettable(_squash_slider, 0)
	Global.make_slider_resettable(_rot_min_slider, -180)
	Global.make_slider_resettable(_rot_max_slider, 180)
	Global.make_slider_resettable(_anim_speed_slider, 0)
	Global.make_slider_resettable(_anim_frames_slider, 1)
	# Layer toggles (Ignore bounce / Clip linked / Static element / NDI reference)
	# now live in the right sidebar's Details tab — see ui_scenes/spriteList/viewer.gd.

	# Sections to dim when no sprite is selected
	_sections = [
		_preview,
		$Position, $Slider,
		$Rotation, $RotationalLimits, $Animation,
	]

	# Build slider style resources (matching right sidebar)
	_slider_theme = SidebarUIFactory.create_slider_theme()
	_slider_fill_enabled = _slider_theme["fill_enabled"]
	_slider_fill_disabled = _slider_theme["fill_disabled"]
	_slider_grabber_enabled = _slider_theme["grab_enabled"]
	_slider_grabber_disabled = _slider_theme["grab_disabled"]

	for slider in _sliders:
		slider.theme = null
		SidebarUIFactory.apply_slider_theme(slider, _slider_theme)

	# Restyle labels to match right sidebar
	var _labels = [
		_drag_label,
		_rdrag_label, _squash_label,
		_rot_min_label, _rot_max_label,
		_anim_frames_label, _anim_speed_label,
		_pos_label, _offset_label, _layer_label,
		_parent_label,
	]
	for label in _labels:
		label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		label.add_theme_font_size_override("font_size", 12)

	$Position/fileTitle.visible = false

	# Normal Map row — below preview, above Position.
	_normal_section = _normal_panel.build(self, Global, UndoManager, panel_width)
	_resizables.append([_normal_section, 20])
	_sections.append(_normal_section)
	_buttons.append_array(_normal_panel.buttons())

	# RotationalLimits has no VBox (the rotation circle uses angular geometry).
	# Wrap it in a Control whose bounds match the visible content extent so the
	# layout pass can place it like every other section.
	_rot_bounds = Control.new()
	_rot_bounds.name = "Bounds"
	_rot_bounds.position = Vector2.ZERO
	# Height is finalized below once _rot_controls_vbox is built.
	_rot_bounds.custom_minimum_size = Vector2(panel_width - 16, 0)
	_rot_bounds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$RotationalLimits.add_child(_rot_bounds)
	_resizables.append([_rot_bounds, 16])

	# Position the circle at the top of the section's local space (will be
	# repositioned/rescaled in _apply_size() based on panel width).
	$RotationalLimits/RotBack.position.y = ROT_RADIUS
	$RotationalLimits/RotBorder.position.y = ROT_RADIUS

	# Build the controls VBox using the same position/width as every other
	# section (left x=11, width=223 at default panel_width), so the sliders
	# match the others above and resize identically.
	_rot_controls_vbox = _build_section_vbox($RotationalLimits,
		Vector2(11, ROT_RADIUS * 2 + ROT_CONTROLS_GAP), 223,
		[_rot_min_label, _rot_min_slider, _rot_max_label, _rot_max_slider])

	# Now that the controls VBox exists, set the bounds Control's full height.
	_rot_bounds.custom_minimum_size.y = (ROT_RADIUS * 2 + ROT_CONTROLS_GAP
		+ _rot_controls_vbox.get_combined_minimum_size().y)

	# --- Animation / Reactive tab strip (sits below the sprite-sheet section) ---
	# Animation tab = the clip list + inspector (absorbs the old wobble); Reactive
	# tab = drag, rotational drag + limits, squash. Reuses the right sidebar's
	# AppTabBar. The clip panel is wrapped in a Node2D so _place_section lays
	# it out like every other section.
	_tab_bar = AppTabBar.new()
	add_child(_tab_bar)
	_tab_bar.add_tab("Animation")
	_tab_bar.add_tab("Reactive")
	_tab_bar.tab_changed.connect(_on_left_tab_changed)

	_anim_panel = AnimationClipPanel.new()
	_anim_section = Node2D.new()
	_anim_section.name = "AnimationTab"
	add_child(_anim_section)
	_anim_panel_root = _anim_panel.build(_slider_fill_enabled, _slider_fill_disabled,
		_slider_grabber_enabled, _slider_grabber_disabled, _layout_panel)
	_anim_panel_root.position = Vector2(11, 0)
	_anim_section.add_child(_anim_panel_root)
	_resizables.append([_anim_panel_root, 42])

	_active_left_tab = clampi(int(Saving.settings.get("leftSidebarTab", 0)), 0, 1)
	_tab_bar.set_active(_active_left_tab, false)
	_apply_tab_visibility()

	# Lay out the panel: sections stack sequentially below the normal-map row,
	# each section sized to its own content height; dividers fall in the
	# inter-section gaps automatically.
	_layout_panel()

	_replace_rot_display_textures()

	# Create dark gray background panel
	_bg = SidebarUIFactory.create_panel_background()
	add_child(_bg)
	move_child(_bg, 0)

	# Restore saved sidebar width before the first _apply_size() so every
	# resizable element gets sized to the user's preference on startup.
	var saved_w = Saving.settings.get("leftSidebarWidth", panel_width)
	panel_width = SidebarUIFactory.clamp_panel_width(
		saved_w, get_viewport().get_visible_rect().size.x, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH_RATIO,
	)
	_selection_presenter.setup(Global, _selection_ui(), _normal_panel,
		Vector2(PREVIEW_MAX_W, PREVIEW_MAX_H), ROT_RADIUS)
	_selection_presenter.connect_transform_fields()
	_set_controls_enabled(Global.heldSprite != null)
	setImage()
	_apply_size()

func _set_controls_enabled(enabled: bool):
	_controls_enabled = enabled
	var dim = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.35)
	for section in _sections:
		section.modulate = dim
	for slider in _sliders:
		slider.editable = enabled
	for button in _buttons:
		button.disabled = !enabled
	for slider in _sliders:
		SidebarUIFactory.apply_slider_theme(slider, _slider_theme, enabled)
	_pos_fields.set_enabled(enabled)
	_offset_fields.set_enabled(enabled)
	
func _replace_rot_display_textures():
	_rotation_renderer.rebuild($RotationalLimits/RotBack, ROT_RADIUS)

func setImage():
	_preview_base_scale = _selection_presenter.sync()
	_apply_size()


func _selection_ui() -> Dictionary:
	return {
		"preview": _preview,
		"parent_label": _parent_label,
		"position_label": _pos_label,
		"offset_label": _offset_label,
		"position_fields": _pos_fields,
		"offset_fields": _offset_fields,
		"layer_label": _layer_label,
		"drag_label": _drag_label,
		"drag_slider": _drag_slider,
		"rdrag_label": _rdrag_label,
		"rdrag_slider": _rdrag_slider,
		"rot_display": spriteRotDisplay,
		"rot_pointer": $RotationalLimits/RotBack/RotLineDisplay3,
		"rot_progress": $RotationalLimits/RotBack/rotLimitBar,
		"rot_min_line": $RotationalLimits/RotBack/RotLineDisplay,
		"rot_max_line": $RotationalLimits/RotBack/RotLineDisplay2,
		"rot_min_label": _rot_min_label,
		"rot_min_slider": _rot_min_slider,
		"rot_max_label": _rot_max_label,
		"rot_max_slider": _rot_max_slider,
		"squash_label": _squash_label,
		"squash_slider": _squash_slider,
		"anim_speed_label": _anim_speed_label,
		"anim_speed_slider": _anim_speed_slider,
		"anim_frames_label": _anim_frames_label,
		"anim_frames_slider": _anim_frames_slider,
	}


# Place a section so its content Control's top edge lands at scene-y `y`. The
# section is a Node2D; its child Control (a VBox, or the RotationalLimits
# bounds wrapper) lives at an internal offset — we just translate the parent.
func _place_section(section: Node2D, content: Control, y: float):
	section.position.y = y - content.position.y

# Single sequential layout pass for the whole panel. Non-divider transitions
# (within a section, or between dividerless sections) use Global.UI_ROW_GAP. Section
# boundaries marked with a divider use Global.UI_DIVIDER_PAD on each side of the divider
# instead, so the divider has visible breathing room without affecting any
# other gap. No other pixel constants.
func _layout_panel():
	# Re-runnable (called on tab switch): clear dividers from the prior pass so
	# they don't accumulate.
	for d in _dividers:
		d.queue_free()
	_dividers.clear()

	# Layout cursor starts flush with the bottom of the normal-map row; the
	# loop treats the normal-row → Position transition like every other
	# divider-marked section boundary.
	var y = _normal_section.position.y + _normal_section.size.y

	# Header — always visible (Position info + sprite-sheet frames/speed).
	# Each entry: [section_node, content_control, has_divider_above]
	for entry in [[$Position, _position_vbox, true], [$Animation, _animation_vbox, true]]:
		y = _place_entry(y, entry[0], entry[1], entry[2])

	# Tab strip, with a divider above it.
	y += Global.UI_DIVIDER_PAD
	_create_divider(y)
	y += Global.UI_DIVIDER_PAD
	_tab_bar.position = Vector2(11, y)
	_tab_bar.set_bar_size(max(0.0, panel_width - 22))
	y += AppTabBar.BAR_HEIGHT + Global.UI_ROW_GAP

	# Active tab content.
	var tab_sections: Array
	if _active_left_tab == 0:
		tab_sections = [[_anim_section, _anim_panel_root, false]]
	else:
		tab_sections = [
			[$Slider,           _slider_vbox,    false],
			[$Rotation,         _rotation_vbox,  false],
			[$RotationalLimits, _rot_bounds,     true],
		]
	for entry in tab_sections:
		y = _place_entry(y, entry[0], entry[1], entry[2])

	# Final layout cursor = bottom of the last section. Used by the scroll
	# clamp so we always allow scrolling all the way to the actual end of
	# content (the previous hardcoded ~1150 estimate was stale).
	content_height = y + Global.UI_DIVIDER_PAD  # small bottom padding

# Place one section, advancing the layout cursor. A divider-marked boundary uses
# UI_DIVIDER_PAD on each side; otherwise a single UI_ROW_GAP.
func _place_entry(y: float, section: Node2D, content: Control, divider_above: bool) -> float:
	if divider_above:
		y += Global.UI_DIVIDER_PAD
		_create_divider(y)
		y += Global.UI_DIVIDER_PAD
	else:
		y += Global.UI_ROW_GAP
	_place_section(section, content, y)
	return y + content.get_combined_minimum_size().y

# Show only the active tab's sections (hide the other tab's so they don't render
# at stale positions or eat clicks).
func _apply_tab_visibility():
	var anim := _active_left_tab == 0
	_anim_section.visible = anim
	$Slider.visible = not anim
	$Rotation.visible = not anim
	$RotationalLimits.visible = not anim

func _on_left_tab_changed(index: int):
	_active_left_tab = index
	Saving.settings["leftSidebarTab"] = index
	Saving.write_settings(Saving.settingsPath)
	_apply_tab_visibility()
	_layout_panel()
	_apply_size()

# Build a VBoxContainer inside a scene-defined section node, place it at the
# original first-widget offset, and reparent the section's widgets into it
# in display order. Sliders auto-fill the VBox width; labels and other Controls
# use their natural min size.
func _build_section_vbox(section: Node, pos: Vector2, vbox_width: float, widgets: Array) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	# Uniform per-row spacing across every section in the panel.
	vbox.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	vbox.position = pos
	vbox.size = Vector2(vbox_width, 0)  # height auto-fits to children
	section.add_child(vbox)
	for w in widgets:
		if w.get_parent() == null:
			vbox.add_child(w)
		else:
			w.reparent(vbox)
		if w is HSlider:
			w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resizables.append([vbox, panel_width - vbox_width])
	return vbox

func _create_divider(y_pos: float) -> ColorRect:
	# Match the section VBoxes' content frame so dividers line up with the
	# sliders above/below them: x=11, width=panel_width-42 (= 223 at default).
	var div := SidebarUIFactory.create_divider(Vector2(panel_width - 42, 1))
	div.position = Vector2(11, y_pos)
	add_child(div)
	_dividers.append(div)
	return div

func _apply_size():
	var s = get_viewport().get_visible_rect().size
	panel_height = s.y
	# Clamp bg top to menu bar bottom so it never overlaps the menu bar
	var menu_bar_bottom = SidebarUIFactory.MENU_BAR_HEIGHT
	var bg_top = max(round(position.y) - 2, menu_bar_bottom)
	_bg.position = Vector2(-19, bg_top - round(position.y))
	_bg.size = Vector2(panel_width + 19, round(s.y) - bg_top)

	# Reflow every width-dependent element to the new panel_width, preserving
	# the right padding each element had at creation time.
	for entry in _resizables:
		var control: Control = entry[0]
		var margin: float = entry[1]
		var w = max(0.0, panel_width - margin)
		control.size.x = w
		if control is Container:
			control.custom_minimum_size.x = w
	for div in _dividers:
		# Match the section VBoxes' content width (margin 42 = 265 - 223).
		div.size.x = panel_width - 42
	if _tab_bar:
		_tab_bar.set_bar_size(max(0.0, panel_width - 22))

	# Scale the layer preview and the rotation circle when the panel is
	# narrower than its default; both stay at full size when wider. Both are
	# centered on the section VBoxes' horizontal midline (which sits ~10px
	# left of the panel midline due to the VBoxes' asymmetric left/right
	# padding), so they align with the sliders rather than the panel edges.
	var f: float = min(1.0, panel_width / DEFAULT_PANEL_WIDTH)
	var content_center_x: float = panel_width * 0.5
	if _rot_controls_vbox:
		content_center_x = _rot_controls_vbox.position.x + _rot_controls_vbox.size.x * 0.5
	if _preview:
		_preview.position = Vector2(content_center_x, PREVIEW_Y)
		_preview.scale = Vector2(_preview_base_scale * f, _preview_base_scale * f)
	if _rot_controls_vbox:
		var rot_back: Sprite2D = $RotationalLimits/RotBack
		var rot_border: Sprite2D = $RotationalLimits/RotBorder
		var current_radius = ROT_RADIUS * f
		rot_back.scale = Vector2(f, f)
		rot_back.position = Vector2(content_center_x, current_radius)
		rot_border.scale = Vector2(f, f)
		rot_border.position = Vector2(content_center_x, current_radius)
		_rot_controls_vbox.position.y = current_radius * 2 + ROT_CONTROLS_GAP
		_rot_bounds.custom_minimum_size.y = (current_radius * 2 + ROT_CONTROLS_GAP
			+ _rot_controls_vbox.get_combined_minimum_size().y)

# Returns true when the mouse is within GRAB_MARGIN of the panel's right edge.
# Local x = panel_width is the visible right edge; the panel extends the full
# viewport height so no vertical constraint is needed.
func _is_on_right_edge(local: Vector2) -> bool:
	return SidebarUIFactory.is_near_vertical_edge(local, panel_width, GRAB_MARGIN)

func _input(event):
	if Global.main == null or !visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local = get_local_mouse_position()
		if event.pressed:
			if _is_on_right_edge(local):
				_resize_dragging = true
				_resize_drag_start_x = get_global_mouse_position().x
				_resize_drag_start_width = panel_width
				get_viewport().set_input_as_handled()
				return
		else:
			if _resize_dragging:
				_resize_dragging = false
				Saving.settings["leftSidebarWidth"] = panel_width
				Saving.write_settings(Saving.settingsPath)
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion:
		if _resize_dragging:
			var delta_x = get_global_mouse_position().x - _resize_drag_start_x
			var viewport_w = get_viewport().get_visible_rect().size.x
			panel_width = SidebarUIFactory.clamp_panel_width(
				_resize_drag_start_width + delta_x,
				viewport_w,
				MIN_PANEL_WIDTH,
				MAX_PANEL_WIDTH_RATIO,
			)
			_apply_size()
			get_viewport().set_input_as_handled()
			return
		else:
			var on_edge = _is_on_right_edge(get_local_mouse_position())
			if on_edge != _resize_hover:
				_resize_hover = on_edge
				if on_edge:
					Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
				else:
					Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	# Wheel-scroll the panel vertically when the window is too short to fit it.
	if !(event is InputEventMouseButton and event.pressed):
		return
	if !Global.main.editMode:
		return
	if event.position.x > panel_width + 19:
		return
	# Ctrl+scroll over a slider is an intentional adjust (global.gd:_input), so
	# don't steal it to scroll the panel. This runs in the same _input stage as
	# global.gd, so guarding on Ctrl here keeps the two order-independent.
	if Input.is_action_pressed("control"):
		return
	var s = get_viewport().get_visible_rect().size
	# Only enable scroll when the viewport can't fit the whole panel.
	var top_pad = 30  # menu bar clearance
	if s.y > content_height + top_pad:
		return
	var step = 50
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		position.y += step
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		position.y -= step
	else:
		return
	var top_y = 30
	# min_y lets the bottom of content land flush with the bottom of the
	# viewport — content_height is the actual laid-out extent (see _layout_panel).
	var min_y = s.y - content_height
	position.y = clamp(position.y, min_y, top_y)
	get_viewport().set_input_as_handled()

func _process(delta):
	_apply_size()

	# Sync the Animation tab (clip list + inspector) to the current selection.
	# Dims itself when nothing is selected; rebuilds/relayouts on structural change.
	_anim_panel.sync()

	coverCollider.disabled = Global.heldSprite == null

	var should_enable = Global.heldSprite != null
	if should_enable != _controls_enabled:
		_set_controls_enabled(should_enable)
		if !should_enable:
			setImage()

	if Global.heldSprite == null:
		return

	var obj = Global.heldSprite
	
	_selection_presenter.sync_transform_fields(obj)
	# Keep the rotation-limit preview's pivot in sync with the live origin: offset changes
	# when the origin point is moved, but setImage() only sets it on selection.
	spriteRotDisplay.offset = obj.offset
	_layer_label.text = "layer : "+str(obj.z)
	
	#Sprite Rotational Limit Display
		
	var size = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	var minimum = Global.heldSprite.rLimitMin
		
	spriteRotDisplay.rotation_degrees = sin(Global.animationTick*0.05)*(size/2.0)+(minimum+(size/2.0))
	$RotationalLimits/RotBack/RotLineDisplay3.rotation_degrees = spriteRotDisplay.rotation_degrees


func _on_drag_slider_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "dragSpeed", value, "slider")
	_drag_label.text = "drag: " + str(value)



func _on_r_drag_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "rdragStr", value, "slider")
	_rdrag_label.text = "rotational drag: " + str(value)
	Global.main.ndi_mark_dirty()


func _on_rot_limit_min_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "rLimitMin", value, "slider")
	_rot_min_label.text = "rotational limit min: " + str(value)
	Global.main.ndi_mark_dirty()

	changeRotLimit()

func _on_rot_limit_max_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "rLimitMax", value, "slider")
	_rot_max_label.text = "rotational limit max: " + str(value)
	Global.main.ndi_mark_dirty()

	changeRotLimit()

func changeRotLimit():
	_selection_presenter.sync_rotation_limits()

func setLayerButtons() -> void:
	for sprite in Global.sprite_nodes():
		sprite.applyCostumeVisibility()


func _on_squash_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "stretchAmount", value, "slider")
	_squash_label.text = "squash: " + str(value)


func _on_anim_speed_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "animSpeed", value, "slider")
	_anim_speed_label.text = "animation speed: " + str(value)

func _on_anim_frames_value_changed(value):
	if Global.heldSprite == null: return
	MutationCommands.drag_layer_property(Global.heldSprite, "frames", value, "slider")
	_anim_frames_label.text = "sprite frames: " + str(value)
	Global.heldSprite.changeFrames()
	setImage()
