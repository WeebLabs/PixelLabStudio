extends PanelContainer

var sprite = null
var parent = null
var spritePath = ""

var indent = 0
var childrenTags = []
var parentTag = null
var collapsed = false

var _collapse_btn: Button
var _thumbnail: TextureRect
var _name_label: Label
var _vis_btn: Button
var _indent_spacer: Control
var _hovered = false
var _was_selected = false

static var _style_normal: StyleBoxFlat
static var _style_hover: StyleBoxFlat
static var _style_selected: StyleBoxFlat
static var _styles_ready = false

func _ready():
	_init_styles()

	custom_minimum_size = Vector2(290, 42)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("panel", _style_normal)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hbox)

	# Indent spacer — grows with depth, pushes arrow+thumb+name right together
	_indent_spacer = Control.new()
	_indent_spacer.custom_minimum_size.x = 0
	_indent_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_indent_spacer)

	# Collapse arrow — in HBox flow, moves with indent
	_collapse_btn = Button.new()
	_collapse_btn.flat = true
	_collapse_btn.text = ""
	_collapse_btn.custom_minimum_size = Vector2(20, 20)
	_collapse_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_collapse_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapse_btn.add_theme_font_size_override("font_size", 11)
	_collapse_btn.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	_collapse_btn.pressed.connect(_on_collapse_toggled)
	hbox.add_child(_collapse_btn)

	# Thumbnail — cropped to opaque bounding box
	_thumbnail = TextureRect.new()
	_thumbnail.custom_minimum_size = Vector2(32, 32)
	_thumbnail.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumbnail.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_thumbnail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var used = sprite.imageData.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var cropped = sprite.imageData.get_region(used)
		_thumbnail.texture = ImageTexture.create_from_image(cropped)
	else:
		_thumbnail.texture = sprite.sprite.texture
	hbox.add_child(_thumbnail)

	# Sprite name — expands to fill, absorbs remaining space as indent grows
	_name_label = Label.new()
	var count = spritePath.get_slice_count("/") - 1
	_name_label.text = spritePath.get_slice("/", count)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(_name_label)

	# Visibility toggle — pinned to right edge
	_vis_btn = Button.new()
	_vis_btn.flat = true
	_vis_btn.custom_minimum_size = Vector2(24, 24)
	_vis_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vis_btn.add_theme_font_size_override("font_size", 12)
	_vis_btn.pressed.connect(_on_vis_toggled)
	hbox.add_child(_vis_btn)
	_update_vis_display()

	mouse_entered.connect(func(): _hovered = true; _update_style())
	mouse_exited.connect(func(): _hovered = false; _update_style())

static func _init_styles():
	if _styles_ready:
		return
	_styles_ready = true

	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.13, 0.13, 0.13, 0.9)
	_style_normal.set_corner_radius_all(4)
	_style_normal.content_margin_left = 4
	_style_normal.content_margin_right = 4
	_style_normal.content_margin_top = 2
	_style_normal.content_margin_bottom = 2

	_style_hover = StyleBoxFlat.new()
	_style_hover.bg_color = Color(0.19, 0.19, 0.19, 0.95)
	_style_hover.set_corner_radius_all(4)
	_style_hover.content_margin_left = 4
	_style_hover.content_margin_right = 4
	_style_hover.content_margin_top = 2
	_style_hover.content_margin_bottom = 2

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.22, 0.22, 0.22, 0.95)
	_style_selected.set_corner_radius_all(4)
	_style_selected.content_margin_left = 4
	_style_selected.content_margin_right = 4
	_style_selected.content_margin_top = 2
	_style_selected.content_margin_bottom = 2
	_style_selected.border_color = Color(0.45, 0.45, 0.45, 0.6)
	_style_selected.set_border_width_all(1)

func _update_style():
	var is_selected = sprite == Global.heldSprite
	if is_selected:
		add_theme_stylebox_override("panel", _style_selected)
	elif _hovered:
		add_theme_stylebox_override("panel", _style_hover)
	else:
		add_theme_stylebox_override("panel", _style_normal)

func _update_vis_display():
	if sprite.visible:
		_vis_btn.text = "●"
		_vis_btn.add_theme_color_override("font_color", Color(0.5, 0.78, 0.5))
		modulate.a = 1.0
	else:
		_vis_btn.text = "○"
		_vis_btn.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
		modulate.a = 0.5

func _on_vis_toggled():
	sprite.visible = !sprite.visible
	_update_vis_display()

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select()
		accept_event()

func _select():
	if Global.heldSprite != null and Global.reparentMode:
		Global.linkSprite(Global.heldSprite, sprite)
		Global.chain.enable(false)

	Global.heldSprite = sprite
	Global.spriteEdit.setImage()

	var count = sprite.path.get_slice_count("/") - 1
	var i1 = sprite.path.get_slice("/", count)
	Global.pushUpdate("Selected sprite \"" + i1 + "\".")

	sprite.set_physics_process(true)

func _draw():
	# Ancestor guide lines — each child draws a segment for every parent in its chain
	var ancestor = parentTag
	while ancestor != null:
		var line_x = 18 + ancestor.indent * 19
		draw_line(Vector2(line_x, 0), Vector2(line_x, size.y), Color(0.4, 0.4, 0.48, 0.45), 1.5, true)
		ancestor = ancestor.parentTag
	# Own guide line — parent draws from arrow center down when expanded
	if childrenTags.size() > 0 and not collapsed:
		var my_x = 18 + indent * 19
		draw_line(Vector2(my_x, size.y * 0.5), Vector2(my_x, size.y), Color(0.4, 0.4, 0.48, 0.45), 1.5, true)

func _process(_delta):
	var is_selected = sprite == Global.heldSprite
	if is_selected != _was_selected:
		_was_selected = is_selected
		_update_style()

func updateChildren():
	for child in childrenTags:
		child.indent = indent + 1
	if childrenTags.size() > 0:
		_collapse_btn.text = "▼"
		_collapse_btn.mouse_filter = Control.MOUSE_FILTER_STOP

func updateIndent():
	_indent_spacer.custom_minimum_size.x = indent * 19
	_update_vis_display()
	queue_redraw()

func updateVis():
	_update_vis_display()

func _on_collapse_toggled():
	collapsed = !collapsed
	_collapse_btn.text = "▶" if collapsed else "▼"
	_set_descendants_visible(!collapsed)
	queue_redraw()

func _set_descendants_visible(vis: bool):
	for child in childrenTags:
		child.visible = vis
		if vis and child.collapsed:
			continue
		if !vis:
			child._set_descendants_visible(false)
		else:
			child._set_descendants_visible(true)
