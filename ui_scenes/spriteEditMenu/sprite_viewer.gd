extends Node2D

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

#Node Reference
@onready var spriteRotDisplay = $RotationalLimits/RotBack/SpriteDisplay

var _preview: Sprite2D
var _parent_label: Label


@onready var coverCollider = $Area2D/CollisionShape2D

var _bg: ColorRect
var panel_width: float = 265
var panel_height: float = 630
# Total vertical extent of laid-out content, set by _layout_panel(). The
# scroll clamp uses this so the user can always scroll to the actual bottom
# even if sections grow or shrink.
var content_height: float = 0.0

# Spacing constants live on Global so both sidebars share one source of truth.
# Tune Global.UI_ROW_GAP / UI_DIVIDER_PAD to reflow every panel that uses them.
const ROT_RADIUS = 105.0           # rotation-circle visualization radius at full panel width
const ROT_CONTROLS_GAP = 20.0      # gap between the circle and the min/max label rows
const DEFAULT_PANEL_WIDTH = 265.0  # baseline; preview & rotation circle scale down below this
# Maximum preview-thumbnail rect at full panel width; both axes scale together
# with the panel width once it drops below DEFAULT_PANEL_WIDTH.
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

# Width-dependent UI elements tracked so _apply_size() can reflow on resize.
# Each entry: [control, margin] where the control's width is kept at
# (panel_width - margin), so the right padding it had at creation is preserved.
var _resizables: Array = []
var _dividers: Array = []
var _controls_enabled: bool = false
var _sliders: Array = []
var _buttons: Array = []
var _sections: Array = []

# Sidebar tabs (below the sprite-sheet section): Animation (clip list + inspector,
# absorbs the old wobble) and Reactive (drag / rotational drag + limits / squash).
var _tab_bar: SidebarTabBar
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
var _normal_status: Label
var _normal_import_btn: Button
var _normal_clear_btn: Button
var _normal_dialog: FileDialog

# WobbleControl section — 4 label+slider pairs (xFrq/xAmp/yFrq/yAmp) reparented
# into a VBoxContainer for auto-layout. Cached refs replace $WobbleControl/...
# node paths.
var _wobble_vbox: VBoxContainer
var _xfrq_label: Label
var _xfrq_slider: HSlider
var _xamp_label: Label
var _xamp_slider: HSlider
var _yfrq_label: Label
var _yfrq_slider: HSlider
var _yamp_label: Label
var _yamp_slider: HSlider

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

func _ready():
	Global.spriteEdit = self
	# Legacy icon sprites — kept hidden because the .tscn still has them at
	# fixed positions that would overlap the wobble sliders. Real controls
	# moved to viewer.gd's right sidebar.
	$Buttons/Speaking.visible = false
	$Buttons/Blinking.visible = false
	$Buttons/Trash.visible = false
	$Buttons/Unlink.visible = false

	# Hide individual panel backgrounds to integrate into unified sidebar
	$Border.visible = false
	$WobbleControl/animationBox.visible = false
	$RotationalLimits/RotBorder.visible = false
	$VisToggle/setToggle/rect.visible = false

	# Hide 3D SubViewport previews — replaced by static 2D preview
	$SubViewportContainer.visible = false
	$SubViewportContainer2.visible = false

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
	_position_vbox = _build_section_vbox($Position, Vector2(10, 155), 226,
		[_parent_label, _pos_label, _offset_label, _layer_label])

	# (Section position shifts are consolidated into a single block below the
	# VBox creation — see "Section layout" comment further down.)

	# Hide sections moved to right sidebar
	$Layers.visible = false
	$EyeTracking.visible = false
	$VisToggle.visible = false

	# Containerize the label+slider sections. Each scene-defined section node
	# (Slider, WobbleControl, Rotation, Animation) gets a VBoxContainer placed
	# at the original first-widget offset; the section's existing children are
	# reparented into it in display order, sliders set to SIZE_EXPAND_FILL.

	# Slider — single drag label + DragSlider
	_drag_label = get_node("Slider/Label")
	_drag_slider = get_node("Slider/DragSlider")
	_slider_vbox = _build_section_vbox($Slider, Vector2(9, 155), 223,
		[_drag_label, _drag_slider])

	# WobbleControl (legacy x/y wobble sliders) — wobble is now authored as an
	# oscillate/translation clip in the Animation tab, so this scene section is
	# hidden and left out of the layout. Old saves fold their wobble into a clip
	# via spriteObject.migrateLegacyWobble(). The handler funcs + scene signal
	# connections are kept (a hidden slider can't emit) so the .tscn stays valid.
	$WobbleControl.visible = false
	# Cache the hidden widget refs anyway so the legacy _on_x_frq_value_changed etc.
	# handlers (still wired in the .tscn) hold valid nodes rather than nulls.
	_xfrq_label = $WobbleControl/xFrqLabel
	_xfrq_slider = $WobbleControl/xFrq
	_xamp_label = $WobbleControl/xAmpLabel
	_xamp_slider = $WobbleControl/xAmp
	_yfrq_label = $WobbleControl/yFrqLabel
	_yfrq_slider = $WobbleControl/yFrq
	_yamp_label = $WobbleControl/yAmpLabel
	_yamp_slider = $WobbleControl/yAmp

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
		$Position, $Buttons, $Slider,
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

	_set_controls_enabled(false)
	setImage()

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

	# Normal Map row — below preview, above Position. HBoxContainer auto-arranges
	# status label (expanding) + Normal button + Clear button.
	const NRML_Y = 132
	const NRML_ROW_HEIGHT = 24
	_normal_section = HBoxContainer.new()
	_normal_section.position = Vector2(10, NRML_Y)
	_normal_section.size = Vector2(panel_width - 20, NRML_ROW_HEIGHT)
	_normal_section.add_theme_constant_override("separation", 4)
	add_child(_normal_section)
	_resizables.append([_normal_section, 20])

	_normal_status = Label.new()
	_normal_status.text = "(none)"
	_normal_status.add_theme_font_size_override("font_size", 11)
	_normal_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_normal_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_normal_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_normal_status.clip_text = true
	_normal_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_normal_section.add_child(_normal_status)

	_normal_import_btn = Button.new()
	_normal_import_btn.text = "Normal"
	_normal_import_btn.custom_minimum_size = Vector2(70, 22)
	_normal_import_btn.add_theme_font_size_override("font_size", 11)
	_normal_import_btn.pressed.connect(_on_normal_import)
	_normal_section.add_child(_normal_import_btn)

	_normal_clear_btn = Button.new()
	_normal_clear_btn.text = "Clear"
	_normal_clear_btn.custom_minimum_size = Vector2(60, 22)
	_normal_clear_btn.add_theme_font_size_override("font_size", 11)
	_normal_clear_btn.disabled = true
	_normal_clear_btn.pressed.connect(_on_normal_clear)
	_normal_section.add_child(_normal_clear_btn)

	_sections.append(_normal_section)
	_sections.append(_normal_status)
	_buttons.append(_normal_import_btn)
	_buttons.append(_normal_clear_btn)

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
	# SidebarTabBar. The clip panel is wrapped in a Node2D so _place_section lays
	# it out like every other section.
	_tab_bar = SidebarTabBar.new()
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
	
func _replace_rot_display_textures():
	# Textures-only: positions for RotBack / RotBorder / RotLimit* are handled
	# in _ready before _layout_panel so the section's bounds Control is correct.
	var size = 260
	var cx = 130.0
	var cy = 130.0
	var radius = ROT_RADIUS
	var fill_color = Color(0.18, 0.18, 0.18)
	var border_color = Color(0.4, 0.4, 0.4, 0.6)
	var border_width = 2.0

	# Dark grey filled circle with clean border for RotBack
	var back_img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(Vector2(cx, cy))
			if dist <= radius - border_width:
				back_img.set_pixel(x, y, fill_color)
			elif dist <= radius:
				back_img.set_pixel(x, y, border_color)
	$RotationalLimits/RotBack.texture = ImageTexture.create_from_image(back_img)

	# Clean thin line for rotation markers (spans from center to circle edge)
	var line_w = int(radius)
	var line_h = 4
	var line_img = Image.create(line_w, line_h, false, Image.FORMAT_RGBA8)
	var line_color = Color(0.75, 0.75, 0.8, 0.6)
	for x in range(line_w):
		line_img.set_pixel(x, 1, line_color)
		line_img.set_pixel(x, 2, line_color)
	var line_tex = ImageTexture.create_from_image(line_img)
	var pointer_img = Image.create(line_w, line_h, false, Image.FORMAT_RGBA8)
	var pointer_color = Color(0.85, 0.85, 0.9, 0.9)
	for x in range(line_w):
		pointer_img.set_pixel(x, 1, pointer_color)
		pointer_img.set_pixel(x, 2, pointer_color)
	var pointer_tex = ImageTexture.create_from_image(pointer_img)
	for node in [$RotationalLimits/RotBack/RotLineDisplay,
				$RotationalLimits/RotBack/RotLineDisplay2]:
		node.texture = line_tex
		node.offset = Vector2(radius / 2.0, 0)
	$RotationalLimits/RotBack/RotLineDisplay3.texture = pointer_tex
	$RotationalLimits/RotBack/RotLineDisplay3.offset = Vector2(radius / 2.0, 0)

	# Reorder children: fill → lines → sprite → dot (later = on top)
	var rot_back = $RotationalLimits/RotBack
	rot_back.move_child($RotationalLimits/RotBack/rotLimitBar, 0)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay, 1)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay2, 2)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay3, 3)
	rot_back.move_child($RotationalLimits/RotBack/SpriteDisplay, 4)
	# White dot to indicate origin point
	var dot_size = 8
	var dot_img = Image.create(dot_size, dot_size, false, Image.FORMAT_RGBA8)
	var dot_center = dot_size / 2.0
	for x in range(dot_size):
		for y in range(dot_size):
			if Vector2(x, y).distance_to(Vector2(dot_center, dot_center)) <= dot_center:
				dot_img.set_pixel(x, y, Color(1, 1, 1))
	var origin_dot = Sprite2D.new()
	origin_dot.texture = ImageTexture.create_from_image(dot_img)
	rot_back.add_child(origin_dot)
	$RotationalLimits/RotBack/SpriteDisplay.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay2.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay3.position = Vector2.ZERO
	# Resize rotLimitBar to fill circle radius, change to light blue
	var bar = $RotationalLimits/RotBack/rotLimitBar
	var bar_size = int(radius) * 2
	var fill_img = Image.create(bar_size, bar_size, false, Image.FORMAT_RGBA8)
	fill_img.fill(Color(0.55, 0.78, 1.0))
	bar.texture_progress = ImageTexture.create_from_image(fill_img)
	bar.offset_left = -radius
	bar.offset_top = -radius
	bar.offset_right = radius
	bar.offset_bottom = radius
	bar.pivot_offset = Vector2(radius, radius)

func setImage():
	if Global.heldSprite == null:
		_preview.texture = null
		_parent_label.text = ""
		_pos_label.text = ""
		_offset_label.text = ""
		_layer_label.text = ""
		_drag_label.text = ""
		spriteRotDisplay.texture = null
		spriteRotDisplay.rotation_degrees = 0
		$RotationalLimits/RotBack/RotLineDisplay3.rotation_degrees = 0
		_rot_min_slider.set_value_no_signal(-180)
		_rot_max_slider.set_value_no_signal(180)
		_rot_min_label.text = "rotational limit min: -180"
		_rot_max_label.text = "rotational limit max: 180"
		$RotationalLimits/RotBack/rotLimitBar.value = 360
		$RotationalLimits/RotBack/rotLimitBar.rotation_degrees = -180 + 90
		$RotationalLimits/RotBack/RotLineDisplay.rotation_degrees = -180
		$RotationalLimits/RotBack/RotLineDisplay2.rotation_degrees = 180
		_update_normal_display()
		return

	# Crop to opaque content of the first frame so the sprite fills the preview
	var img = Global.heldSprite.imageData
	var img_size = img.get_size()
	var frame_w = int(img_size.x / Global.heldSprite.frames)
	var frame_h = int(img_size.y)

	# Find bounding rect of non-transparent pixels in first frame (native C++)
	var used: Rect2i
	if Global.heldSprite.frames <= 1:
		used = img.get_used_rect()
	else:
		used = img.get_region(Rect2i(0, 0, frame_w, frame_h)).get_used_rect()

	if used.size.x > 0 and used.size.y > 0:
		var content_rect = Rect2(used)
		var atlas = AtlasTexture.new()
		atlas.atlas = Global.heldSprite.tex
		atlas.region = content_rect
		_preview.texture = atlas
		_preview.hframes = 1
		_preview_base_scale = min(PREVIEW_MAX_W / content_rect.size.x, PREVIEW_MAX_H / content_rect.size.y)
	else:
		_preview.texture = Global.heldSprite.tex
		_preview.hframes = Global.heldSprite.frames
		_preview_base_scale = min(PREVIEW_MAX_W / frame_w, PREVIEW_MAX_H / frame_h)
	# _apply_size() applies the panel-width scale factor on top of the base
	# scale and re-centers the preview.
	_apply_size()

	# Update parent label
	if Global.heldSprite.parentId != null:
		var nodes = get_tree().get_nodes_in_group(str(Global.heldSprite.parentId))
		if nodes.size() > 0:
			var count = nodes[0].path.get_slice_count("/") - 1
			_parent_label.text = "Parent: " + nodes[0].path.get_slice("/", count)
		else:
			_parent_label.text = "Root Element"
	else:
		_parent_label.text = "Root Element"

	spriteRotDisplay.texture = Global.heldSprite.tex
	spriteRotDisplay.offset = Global.heldSprite.offset
	# Scale so opaque area occupies 50% of circle radius
	var rot_img = Global.heldSprite.imageData
	var rot_used = rot_img.get_used_rect()
	var target_size = 105.0  # 50% of radius (105) = 52.5 per side from center
	if rot_used.size.x > 0 and rot_used.size.y > 0:
		var rot_scale = target_size / max(rot_used.size.x, rot_used.size.y)
		spriteRotDisplay.scale = Vector2(rot_scale, rot_scale)
	else:
		spriteRotDisplay.scale = Vector2(1, 1) * (target_size / rot_img.get_size().y)

	_drag_label.text = "drag: " + str(Global.heldSprite.dragSpeed)
	_drag_slider.set_value_no_signal(Global.heldSprite.dragSpeed)

	_rdrag_label.text = "rotational drag: " + str(Global.heldSprite.rdragStr)
	_rdrag_slider.set_value_no_signal(Global.heldSprite.rdragStr)

	_rot_min_slider.set_value_no_signal(Global.heldSprite.rLimitMin)
	_rot_min_label.text = "rotational limit min: " + str(Global.heldSprite.rLimitMin)
	_rot_max_slider.set_value_no_signal(Global.heldSprite.rLimitMax)
	_rot_max_label.text = "rotational limit max: " + str(Global.heldSprite.rLimitMax)

	_squash_label.text = "squash: " + str(Global.heldSprite.stretchAmount)
	_squash_slider.set_value_no_signal(Global.heldSprite.stretchAmount)

	_anim_speed_label.text = "animation speed: " + str(Global.heldSprite.animSpeed)
	_anim_speed_slider.set_value_no_signal(Global.heldSprite.animSpeed)

	_anim_frames_label.text = "sprite frames: " + str(Global.heldSprite.frames)
	_anim_frames_slider.set_value_no_signal(Global.heldSprite.frames)

	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""

	$EyeTracking/EyeTrackToggle.set_pressed_no_signal(Global.heldSprite.eyeTrack)
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(Global.heldSprite.eyeTrackDistance)
	$EyeTracking/eyeTrackDist.set_value_no_signal(Global.heldSprite.eyeTrackDistance)
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(Global.heldSprite.eyeTrackSpeed)
	$EyeTracking/eyeTrackSpeed.set_value_no_signal(Global.heldSprite.eyeTrackSpeed)
	$EyeTracking/EyeTrackInvert.set_pressed_no_signal(Global.heldSprite.eyeTrackInvert)

	changeRotLimit()

	setLayerButtons()

	_update_normal_display()

	if Global.spriteList:
		Global.spriteList.updateControls()
		Global.spriteList.scroll_to_selected()


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
	y += SidebarTabBar.BAR_HEIGHT + Global.UI_ROW_GAP

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
	var menu_bar_bottom = 28  # MENU_BAR_HEIGHT
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
	
	_pos_label.text = "position     X : "+str(obj.position.x)+"     Y: " + str(obj.position.y)
	_offset_label.text = "offset         X : "+str(obj.offset.x)+"     Y: " + str(obj.offset.y)
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
	UndoManager.save_state_continuous()
	_drag_label.text = "drag: " + str(value)
	Global.heldSprite.dragSpeed = value


func _on_x_frq_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_xfrq_label.text = "x frequency: " + str(value)
	Global.heldSprite.xFrq = value


func _on_x_amp_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_xamp_label.text = "x amplitude: " + str(value)
	Global.heldSprite.xAmp = value
	Global.main.ndi_mark_dirty()


func _on_y_frq_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_yfrq_label.text = "y frequency: " + str(value)
	Global.heldSprite.yFrq = value

func _on_y_amp_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_yamp_label.text = "y amplitude: " + str(value)
	Global.heldSprite.yAmp = value
	Global.main.ndi_mark_dirty()


func _on_r_drag_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_rdrag_label.text = "rotational drag: " + str(value)
	Global.heldSprite.rdragStr = value
	Global.main.ndi_mark_dirty()


# (Removed: _on_speaking_pressed / _on_blinking_pressed / _on_trash_pressed /
# _on_unlink_pressed — these were connected to scene buttons inside the now-
# hidden $Buttons/Speaking, $Buttons/Blinking, $Buttons/Trash, $Buttons/Unlink
# sprites. The real handlers live in viewer.gd's right sidebar.)


func _on_rot_limit_min_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_rot_min_label.text = "rotational limit min: " + str(value)
	Global.heldSprite.rLimitMin = value
	Global.main.ndi_mark_dirty()

	changeRotLimit()

func _on_rot_limit_max_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_rot_max_label.text = "rotational limit max: " + str(value)
	Global.heldSprite.rLimitMax = value
	Global.main.ndi_mark_dirty()

	changeRotLimit()

func changeRotLimit():
	if Global.heldSprite == null: return
	$RotationalLimits/RotBack/rotLimitBar.value = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/rotLimitBar.rotation_degrees = Global.heldSprite.rLimitMin + 90

	$RotationalLimits/RotBack/RotLineDisplay.rotation_degrees = Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/RotLineDisplay2.rotation_degrees = Global.heldSprite.rLimitMax

func setLayerButtons():
	if Global.heldSprite == null: return
	var a = Global.heldSprite.costumeLayers.duplicate()
	
	var active_mod = Color(1, 1, 1, 1)
	var inactive_mod = Color(0.5, 0.5, 0.5, 0.7)
	$Layers/Layer1.self_modulate = active_mod if a[0] == 1 else inactive_mod
	$Layers/Layer2.self_modulate = active_mod if a[1] == 1 else inactive_mod
	$Layers/Layer3.self_modulate = active_mod if a[2] == 1 else inactive_mod
	$Layers/Layer4.self_modulate = active_mod if a[3] == 1 else inactive_mod
	$Layers/Layer5.self_modulate = active_mod if a[4] == 1 else inactive_mod
	$Layers/Layer6.self_modulate = active_mod if a[5] == 1 else inactive_mod
	$Layers/Layer7.self_modulate = active_mod if a[6] == 1 else inactive_mod
	$Layers/Layer8.self_modulate = active_mod if a[7] == 1 else inactive_mod
	$Layers/Layer9.self_modulate = active_mod if a[8] == 1 else inactive_mod
	$Layers/Layer10.self_modulate = active_mod if a[9] == 1 else inactive_mod
	
	var nodes = get_tree().get_nodes_in_group("saved")
	for sprite in nodes:
		sprite.applyCostumeVisibility()   # costume membership, honoring a manual hide
		


func _on_layer_button_1_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[0] == 0:
		Global.heldSprite.costumeLayers[0] = 1
	else:
		Global.heldSprite.costumeLayers[0] = 0
	setLayerButtons()


func _on_layer_button_2_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[1] == 0:
		Global.heldSprite.costumeLayers[1] = 1
	else:
		Global.heldSprite.costumeLayers[1] = 0
	setLayerButtons()


func _on_layer_button_3_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[2] == 0:
		Global.heldSprite.costumeLayers[2] = 1
	else:
		Global.heldSprite.costumeLayers[2] = 0
	setLayerButtons()


func _on_layer_button_4_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[3] == 0:
		Global.heldSprite.costumeLayers[3] = 1
	else:
		Global.heldSprite.costumeLayers[3] = 0
	setLayerButtons()


func _on_layer_button_5_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[4] == 0:
		Global.heldSprite.costumeLayers[4] = 1
	else:
		Global.heldSprite.costumeLayers[4] = 0
	setLayerButtons()

func _on_layer_button_6_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[5] == 0:
		Global.heldSprite.costumeLayers[5] = 1
	else:
		Global.heldSprite.costumeLayers[5] = 0
	setLayerButtons()

func _on_layer_button_7_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[6] == 0:
		Global.heldSprite.costumeLayers[6] = 1
	else:
		Global.heldSprite.costumeLayers[6] = 0
	setLayerButtons()

func _on_layer_button_8_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[7] == 0:
		Global.heldSprite.costumeLayers[7] = 1
	else:
		Global.heldSprite.costumeLayers[7] = 0
	setLayerButtons()

func _on_layer_button_9_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[8] == 0:
		Global.heldSprite.costumeLayers[8] = 1
	else:
		Global.heldSprite.costumeLayers[8] = 0
	setLayerButtons()

func _on_layer_button_10_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[9] == 0:
		Global.heldSprite.costumeLayers[9] = 1
	else:
		Global.heldSprite.costumeLayers[9] = 0
	setLayerButtons()

func layerSelected():
	var newPos = Vector2.ZERO
	match Global.main.costume:
		1:
			newPos = $Layers/Layer1.position
		2:
			newPos = $Layers/Layer2.position
		3:
			newPos = $Layers/Layer3.position
		4:
			newPos = $Layers/Layer4.position
		5:
			newPos = $Layers/Layer5.position
		6:
			newPos = $Layers/Layer6.position
		7:
			newPos = $Layers/Layer7.position
		8:
			newPos = $Layers/Layer8.position
		9:
			newPos = $Layers/Layer9.position
		10:
			newPos = $Layers/Layer10.position
	$Layers/Select.position = newPos


func _on_squash_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_squash_label.text = "squash: " + str(value)
	Global.heldSprite.stretchAmount = value


func _on_anim_speed_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_anim_speed_label.text = "animation speed: " + str(value)
	Global.heldSprite.animSpeed = value

func _on_anim_frames_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	_anim_frames_label.text = "sprite frames: " + str(value)
	Global.heldSprite.frames = value
	Global.heldSprite.changeFrames()
	setImage()


func _on_delete_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.toggle = "null"
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""
	Global.heldSprite.makeVis()

func _on_set_toggle_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	$VisToggle/setToggle/Label.text = "toggle: AWAITING INPUT"
	Global.awaitingToggleBind = true
	await Global.main.fatfuckingballs

	var keys = await Global.main.spriteVisToggles
	Global.awaitingToggleBind = false
	var key = keys[0]
	if Global.heldSprite == null: return
	Global.heldSprite.toggle = key
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""

func _on_eye_track_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrack = button_pressed
	Global.main.ndi_mark_dirty()

func _on_eye_track_dist_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(value)
	Global.heldSprite.eyeTrackDistance = value
	Global.main.ndi_mark_dirty()

func _on_eye_track_speed_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(value)
	Global.heldSprite.eyeTrackSpeed = value

func _on_eye_track_invert_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrackInvert = button_pressed

func _update_normal_display():
	if _normal_status == null:
		return
	if Global.heldSprite == null or !Global.heldSprite.hasNormalMap():
		_normal_status.text = "(none)"
		_normal_clear_btn.disabled = true
	else:
		var nname = Global.heldSprite.normalPath.get_file()
		if nname == "":
			nname = "(embedded)"
		_normal_status.text = nname
		_normal_clear_btn.disabled = false

func _on_normal_import():
	if _normal_dialog == null:
		_normal_dialog = FileDialog.new()
		_normal_dialog.title = "Select Normal Map"
		_normal_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_normal_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_normal_dialog.filters = PackedStringArray(["*.png;PNG Image"])
		_normal_dialog.use_native_dialog = true
		_normal_dialog.file_selected.connect(_on_normal_file_selected)
		add_child(_normal_dialog)
	_normal_dialog.popup_centered(Vector2i(600, 400))

func _on_normal_file_selected(path: String):
	if Global.heldSprite == null:
		return
	var img = Image.new()
	if img.load(path) != OK:
		Global.pushUpdate("Failed to load normal map.")
		return
	UndoManager.save_state()
	Global.heldSprite.setNormalMap(img, path)
	UndoManager.invalidate_normal(Global.heldSprite.id)
	_update_normal_display()

func _on_normal_clear():
	if Global.heldSprite == null or !Global.heldSprite.hasNormalMap():
		return
	UndoManager.save_state()
	Global.heldSprite.clearNormalMap()
	UndoManager.invalidate_normal(Global.heldSprite.id)
	_update_normal_display()
