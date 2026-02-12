extends Node2D

@onready var container = $ScrollContainer/VBoxContainer
var SpriteListObject = preload("res://ui_scenes/spriteList/sprite_list_object.gd")

var speaking_tex = preload("res://ui_scenes/spriteEditMenu/speaking.png")
var blink_tex = preload("res://ui_scenes/spriteEditMenu/blink.png")
var trash_tex = preload("res://ui_scenes/spriteEditMenu/trash.png")
var unlink_tex = preload("res://ui_scenes/spriteEditMenu/unlink.png")

var panel_width: float = 310
var panel_height: float = 630
const MIN_WIDTH = 200
const GRAB_MARGIN = 6
const CONTROLS_HEIGHT = 44
const DIVIDER_MARGIN = 6

var _bg: ColorRect
var _divider: ColorRect
var _controls: Node2D
var _speaking_spr: Sprite2D
var _blinking_spr: Sprite2D
var _unlink_spr: Sprite2D
var _trash_spr: Sprite2D
var _link_btn: Button

var _dragging = false
var _drag_start = Vector2.ZERO
var _drag_start_width: float = 0
var _hover_left = false
var _divider_ratio: float = 0.67
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
	add_child(_bg)
	move_child(_bg, 0)
	_create_controls()
	_apply_size()

func _create_controls():
	_divider = ColorRect.new()
	_divider.color = Color(0.3, 0.3, 0.35)
	_divider.size = Vector2(panel_width - 16, 1)
	add_child(_divider)

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

func _apply_size():
	var s = get_viewport().get_visible_rect().size
	panel_height = s.y
	_bg.position = Vector2(-4, -4)
	_bg.size = Vector2(panel_width + 8, panel_height + 8)

	var scroll_bottom = panel_height * _divider_ratio
	$ScrollContainer.offset_right = panel_width - 10
	$ScrollContainer.offset_bottom = scroll_bottom
	container.custom_minimum_size.x = panel_width - 20

	_divider.position = Vector2(8, scroll_bottom + DIVIDER_MARGIN)
	_divider.size.x = panel_width - 16
	var controls_center_x = (panel_width - 200.0) / 2.0
	_controls.position = Vector2(controls_center_x, scroll_bottom + DIVIDER_MARGIN + 6)

	$Area2D2/CollisionShape2D.shape.size = Vector2(panel_width, panel_height)
	$Area2D2/CollisionShape2D.position = Vector2(panel_width / 2.0, panel_height / 2.0)
	position.x = s.x - (panel_width + 3)

func _process(_delta):
	var no_sprite = Global.heldSprite == null
	var dim = Color(0.3, 0.3, 0.35)
	var normal = Color(1, 1, 1)
	_speaking_spr.modulate = dim if no_sprite else normal
	_blinking_spr.modulate = dim if no_sprite else normal
	_unlink_spr.modulate = dim if no_sprite else normal
	_trash_spr.modulate = dim if no_sprite else normal
	_link_btn.disabled = no_sprite
	if no_sprite:
		_link_btn.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	else:
		_link_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))

	if !no_sprite:
		_speaking_spr.frame = Global.heldSprite.showOnTalk
		_blinking_spr.frame = Global.heldSprite.showOnBlink

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
			panel_width = max(MIN_WIDTH, _drag_start_width - delta.x)
			_apply_size()
			get_viewport().set_input_as_handled()
		elif _divider_dragging:
			var local = get_local_mouse_position()
			_divider_ratio = clamp(local.y / panel_height, 0.2, 0.9)
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
