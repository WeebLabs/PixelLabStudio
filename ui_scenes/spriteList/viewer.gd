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
const DIVIDER_MARGIN = 6
const CONTROLS_ROW_HEIGHT = 32

var _bg: ColorRect
var _divider1: ColorRect
var _divider2: ColorRect
var _divider3: ColorRect
var _controls: Node2D
var _speaking_spr: Sprite2D
var _blinking_spr: Sprite2D
var _unlink_spr: Sprite2D
var _trash_spr: Sprite2D
var _link_btn: Button

var _costume_section: Node2D
var _costume_btns: Array = []
var _costume_select: Sprite2D

var _eye_section: Node2D
var _eye_toggle: CheckBox
var _eye_dist_label: Label
var _eye_dist_slider: HSlider
var _eye_speed_label: Label
var _eye_speed_slider: HSlider
var _eye_invert: CheckBox

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
		layer_textures.append(load("res://ui_scenes/spriteEditMenu/layerButtons/" + str(i) + ".png"))

	_create_controls()
	_create_costume_buttons()
	_create_eye_tracking()
	_apply_size()

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

	_controls = Node2D.new()
	add_child(_controls)

	var icon_scale = Vector2(0.65, 0.65)
	var spacing = 40
	var start_x = 10

	# Speaking
	_speaking_spr = Sprite2D.new()
	_speaking_spr.texture = speaking_tex
	_speaking_spr.hframes = 3
	_speaking_spr.scale = icon_scale
	_speaking_spr.position = Vector2(start_x, 16)
	_controls.add_child(_speaking_spr)
	var speaking_btn = Button.new()
	speaking_btn.flat = true
	speaking_btn.offset_left = -16
	speaking_btn.offset_top = -16
	speaking_btn.offset_right = 16
	speaking_btn.offset_bottom = 16
	speaking_btn.pressed.connect(_on_speaking_pressed)
	_speaking_spr.add_child(speaking_btn)

	# Blinking
	_blinking_spr = Sprite2D.new()
	_blinking_spr.texture = blink_tex
	_blinking_spr.hframes = 4
	_blinking_spr.scale = icon_scale
	_blinking_spr.position = Vector2(start_x + spacing, 16)
	_controls.add_child(_blinking_spr)
	var blink_btn = Button.new()
	blink_btn.flat = true
	blink_btn.offset_left = -16
	blink_btn.offset_top = -16
	blink_btn.offset_right = 16
	blink_btn.offset_bottom = 16
	blink_btn.pressed.connect(_on_blinking_pressed)
	_blinking_spr.add_child(blink_btn)

	# Link (text button)
	_link_btn = Button.new()
	_link_btn.text = "Link"
	_link_btn.flat = true
	_link_btn.add_theme_font_size_override("font_size", 12)
	_link_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_link_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_link_btn.position = Vector2(start_x + spacing * 2 - 8, 4)
	_link_btn.pressed.connect(_on_link_pressed)
	_controls.add_child(_link_btn)

	# Unlink
	_unlink_spr = Sprite2D.new()
	_unlink_spr.texture = unlink_tex
	_unlink_spr.scale = icon_scale
	_unlink_spr.position = Vector2(start_x + spacing * 3 + 10, 16)
	_controls.add_child(_unlink_spr)
	var unlink_btn = Button.new()
	unlink_btn.flat = true
	unlink_btn.offset_left = -16
	unlink_btn.offset_top = -16
	unlink_btn.offset_right = 16
	unlink_btn.offset_bottom = 16
	unlink_btn.pressed.connect(_on_unlink_pressed)
	_unlink_spr.add_child(unlink_btn)

	# Trash
	_trash_spr = Sprite2D.new()
	_trash_spr.texture = trash_tex
	_trash_spr.scale = icon_scale
	_trash_spr.position = Vector2(start_x + spacing * 4 + 20, 16)
	_controls.add_child(_trash_spr)
	var trash_btn = Button.new()
	trash_btn.flat = true
	trash_btn.offset_left = -16
	trash_btn.offset_top = -16
	trash_btn.offset_right = 16
	trash_btn.offset_bottom = 16
	trash_btn.pressed.connect(_on_trash_pressed)
	_trash_spr.add_child(trash_btn)

func _create_costume_buttons():
	_costume_section = Node2D.new()
	add_child(_costume_section)

	var icon_scale = Vector2(0.55, 0.55)
	var spacing_x = 42
	var spacing_y = 28

	for i in range(10):
		var spr = Sprite2D.new()
		spr.texture = layer_textures[i]
		spr.hframes = 2
		spr.scale = icon_scale
		var row = i / 5
		var col = i % 5
		spr.position = Vector2(col * spacing_x, row * spacing_y + 14)
		_costume_section.add_child(spr)

		var btn = Button.new()
		btn.flat = true
		btn.offset_left = -14
		btn.offset_top = -14
		btn.offset_right = 14
		btn.offset_bottom = 14
		btn.pressed.connect(_on_costume_btn_pressed.bind(i))
		spr.add_child(btn)
		_costume_btns.append(spr)

	_costume_select = Sprite2D.new()
	_costume_select.texture = select_tex
	_costume_select.scale = icon_scale
	_costume_select.visible = false
	_costume_section.add_child(_costume_select)

func _create_eye_tracking():
	_eye_section = Node2D.new()
	add_child(_eye_section)

	var ctrl_left = 10
	var ctrl_width = 200
	var y = 0
	var label_color = Color(0.75, 0.75, 0.8)

	_eye_toggle = CheckBox.new()
	_eye_toggle.text = "Eye tracking"
	_eye_toggle.add_theme_font_size_override("font_size", 12)
	_eye_toggle.add_theme_color_override("font_color", label_color)
	_eye_toggle.position = Vector2(ctrl_left, y)
	_eye_toggle.size = Vector2(ctrl_width, 20)
	_eye_toggle.toggled.connect(_on_eye_track_toggled)
	_eye_section.add_child(_eye_toggle)
	y += 24

	_eye_dist_label = Label.new()
	_eye_dist_label.text = "tracking distance: 20.0"
	_eye_dist_label.add_theme_font_size_override("font_size", 12)
	_eye_dist_label.add_theme_color_override("font_color", label_color)
	_eye_dist_label.position = Vector2(ctrl_left, y)
	_eye_section.add_child(_eye_dist_label)
	y += 16

	_eye_dist_slider = HSlider.new()
	_eye_dist_slider.min_value = 1.0
	_eye_dist_slider.max_value = 200.0
	_eye_dist_slider.step = 1.0
	_eye_dist_slider.value = 20.0
	_eye_dist_slider.position = Vector2(ctrl_left, y)
	_eye_dist_slider.size = Vector2(ctrl_width, 16)
	_eye_dist_slider.value_changed.connect(_on_eye_track_dist_changed)
	_eye_section.add_child(_eye_dist_slider)
	y += 22

	_eye_speed_label = Label.new()
	_eye_speed_label.text = "tracking speed: 0.15"
	_eye_speed_label.add_theme_font_size_override("font_size", 12)
	_eye_speed_label.add_theme_color_override("font_color", label_color)
	_eye_speed_label.position = Vector2(ctrl_left, y)
	_eye_section.add_child(_eye_speed_label)
	y += 16

	_eye_speed_slider = HSlider.new()
	_eye_speed_slider.min_value = 0.01
	_eye_speed_slider.max_value = 1.0
	_eye_speed_slider.step = 0.01
	_eye_speed_slider.value = 0.15
	_eye_speed_slider.position = Vector2(ctrl_left, y)
	_eye_speed_slider.size = Vector2(ctrl_width, 16)
	_eye_speed_slider.value_changed.connect(_on_eye_track_speed_changed)
	_eye_section.add_child(_eye_speed_slider)
	y += 22

	_eye_invert = CheckBox.new()
	_eye_invert.text = "Invert direction"
	_eye_invert.add_theme_font_size_override("font_size", 12)
	_eye_invert.add_theme_color_override("font_color", label_color)
	_eye_invert.position = Vector2(ctrl_left, y)
	_eye_invert.size = Vector2(ctrl_width, 20)
	_eye_invert.toggled.connect(_on_eye_track_invert_toggled)
	_eye_section.add_child(_eye_invert)

func _apply_size():
	var s = get_viewport().get_visible_rect().size
	panel_height = s.y
	_bg.position = Vector2(-4, -4)
	_bg.size = Vector2(panel_width + 8, panel_height + 8)

	# Top controls
	var controls_center_x = (panel_width - 200.0) / 2.0
	_controls.position = Vector2(controls_center_x, 0)
	_divider1.position = Vector2(8, CONTROLS_ROW_HEIGHT + 4)
	_divider1.size.x = panel_width - 16

	# Layer list scroll area
	var scroll_top = CONTROLS_ROW_HEIGHT + 10
	var scroll_bottom = panel_height * _divider_ratio
	$ScrollContainer.offset_top = scroll_top
	$ScrollContainer.offset_right = panel_width - 10
	$ScrollContainer.offset_bottom = scroll_bottom
	container.custom_minimum_size.x = panel_width - 20

	# Draggable divider (between list and costume)
	_divider2.position = Vector2(8, scroll_bottom + DIVIDER_MARGIN)
	_divider2.size.x = panel_width - 16

	# Costume buttons
	var costume_y = scroll_bottom + DIVIDER_MARGIN * 2 + 4
	var costume_span_x = 42.0 * 4  # 168px from first to last center
	var costume_center_x = (panel_width - costume_span_x) / 2.0
	_costume_section.position = Vector2(costume_center_x, costume_y)

	# Divider between costume and eye tracking
	var costume_bottom = costume_y + 62
	_divider3.position = Vector2(8, costume_bottom + 4)
	_divider3.size.x = panel_width - 16

	# Eye tracking section
	_eye_section.position = Vector2(0, costume_bottom + 14)

	# Collision area
	$Area2D2/CollisionShape2D.shape.size = Vector2(panel_width, panel_height)
	$Area2D2/CollisionShape2D.position = Vector2(panel_width / 2.0, panel_height / 2.0)
	position.x = s.x - (panel_width + 3)

func _process(_delta):
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

	# Eye tracking
	_eye_toggle.disabled = no_sprite
	_eye_dist_slider.editable = !no_sprite
	_eye_speed_slider.editable = !no_sprite
	_eye_invert.disabled = no_sprite

	if !no_sprite:
		_speaking_spr.frame = Global.heldSprite.showOnTalk
		_blinking_spr.frame = Global.heldSprite.showOnBlink

		# Costume button frames
		for i in range(10):
			_costume_btns[i].frame = 1 - Global.heldSprite.costumeLayers[i]

		# Costume select position
		var costume_idx = Global.main.costume - 1
		if costume_idx >= 0 and costume_idx < 10:
			_costume_select.position = _costume_btns[costume_idx].position

func scroll_to_selected():
	if Global.heldSprite == null:
		return
	for child in container.get_children():
		if child.sprite == Global.heldSprite:
			$ScrollContainer.ensure_control_visible(child)
			return

func updateControls():
	if Global.heldSprite == null:
		return
	_eye_toggle.set_pressed_no_signal(Global.heldSprite.eyeTrack)
	_eye_dist_label.text = "tracking distance: " + str(Global.heldSprite.eyeTrackDistance)
	_eye_dist_slider.set_value_no_signal(Global.heldSprite.eyeTrackDistance)
	_eye_speed_label.text = "tracking speed: " + str(Global.heldSprite.eyeTrackSpeed)
	_eye_speed_slider.set_value_no_signal(Global.heldSprite.eyeTrackSpeed)
	_eye_invert.set_pressed_no_signal(Global.heldSprite.eyeTrackInvert)

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

# --- Eye tracking handlers ---

func _on_eye_track_toggled(pressed):
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	Global.heldSprite.eyeTrack = pressed

func _on_eye_track_dist_changed(value):
	if Global.heldSprite == null:
		return
	UndoManager.save_state_continuous()
	_eye_dist_label.text = "tracking distance: " + str(value)
	Global.heldSprite.eyeTrackDistance = value

func _on_eye_track_speed_changed(value):
	if Global.heldSprite == null:
		return
	UndoManager.save_state_continuous()
	_eye_speed_label.text = "tracking speed: " + str(value)
	Global.heldSprite.eyeTrackSpeed = value

func _on_eye_track_invert_toggled(pressed):
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	Global.heldSprite.eyeTrackInvert = pressed

# --- Resize and drag ---

func _is_on_left_edge(local: Vector2) -> bool:
	var left = -4.0
	if local.x < left - GRAB_MARGIN or local.x > left + GRAB_MARGIN:
		return false
	if local.y < -4 - GRAB_MARGIN or local.y > panel_height + GRAB_MARGIN:
		return false
	return true

func _is_on_divider(local: Vector2) -> bool:
	var divider_y = panel_height * _divider_ratio + DIVIDER_MARGIN
	if abs(local.y - divider_y) > GRAB_MARGIN:
		return false
	if local.x < 0 or local.x > panel_width:
		return false
	return true

func _input(event):
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return

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
				get_viewport().set_input_as_handled()
			if _divider_dragging:
				_divider_dragging = false
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging:
			var delta = get_global_mouse_position() - _drag_start
			var viewport_width = get_viewport().get_visible_rect().size.x
			var max_width = viewport_width * MAX_WIDTH_RATIO
			panel_width = clamp(_drag_start_width - delta.x, MIN_WIDTH, max_width)
			_apply_size()
			get_viewport().set_input_as_handled()
		elif _divider_dragging:
			var local = get_local_mouse_position()
			var min_y = (CONTROLS_ROW_HEIGHT + 60.0) / panel_height
			var max_y = (panel_height - 230.0) / panel_height
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

func updateData(sort_by_z: bool = false):
	clearContainer()
	await get_tree().create_timer(0.15).timeout
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
		if sprite.parentSprite != null:
			spritesWithParents.append(listObj)
		allSprites.append(listObj)

		container.add_child(listObj)

	for child in spritesWithParents:
		var parentListObj = null
		var index = 0
		for sprite in allSprites:
			if child.parent == sprite.sprite:
				parentListObj = sprite
				index = sprite.get_index() + 1
				sprite.childrenTags.append(child)
				break
		child.parentTag = parentListObj
		container.move_child(child,index)

	for sprite in allSprites:
		sprite.updateChildren()

	for child in spritesWithParents:
		child.updateIndent()

func clearContainer():
	for i in container.get_children():
		i.queue_free()

func updateAllVisible():
	for i in container.get_children():
		i.updateVis()
