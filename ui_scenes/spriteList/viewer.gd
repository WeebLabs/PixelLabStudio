extends Node2D

@onready var container = $ScrollContainer/VBoxContainer
var SpriteListObject = preload("res://ui_scenes/spriteList/sprite_list_object.gd")

var panel_width: float = 310
var panel_height: float = 630
const MIN_WIDTH = 200
const MIN_HEIGHT = 200
const GRAB_MARGIN = 6

enum ResizeEdge { NONE, LEFT, BOTTOM, BOTTOM_LEFT }
var _resize_edge = ResizeEdge.NONE
var _dragging = false
var _drag_start = Vector2.ZERO
var _drag_start_width: float = 0
var _drag_start_height: float = 0
var _hover_edge = ResizeEdge.NONE

func _ready():
	Global.spriteList = self
	container.add_theme_constant_override("separation", 2)
	_apply_size()

func _apply_size():
	$ScrollContainer.offset_right = panel_width - 10
	$ScrollContainer.offset_bottom = panel_height - 8
	$NinePatchRect.offset_left = -4
	$NinePatchRect.offset_right = panel_width - 4
	$NinePatchRect.offset_bottom = panel_height - 4
	container.custom_minimum_size.x = panel_width - 20
	$Area2D2/CollisionShape2D.shape.size = Vector2(panel_width, panel_height)
	$Area2D2/CollisionShape2D.position = Vector2(panel_width / 2.0, panel_height / 2.0)
	var s = get_viewport().get_visible_rect().size
	position.x = s.x - (panel_width + 3)

func _get_edge(local: Vector2) -> ResizeEdge:
	var left = -4.0
	var right = panel_width - 4
	var bottom = panel_height - 4

	if local.x < left - GRAB_MARGIN or local.x > right + GRAB_MARGIN:
		return ResizeEdge.NONE
	if local.y < -4 - GRAB_MARGIN or local.y > bottom + GRAB_MARGIN:
		return ResizeEdge.NONE

	var on_left = local.x < left + GRAB_MARGIN
	var on_bottom = local.y > bottom - GRAB_MARGIN

	if on_left and on_bottom:
		return ResizeEdge.BOTTOM_LEFT
	if on_left:
		return ResizeEdge.LEFT
	if on_bottom:
		return ResizeEdge.BOTTOM
	return ResizeEdge.NONE

func _input(event):
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if not $NinePatchRect.visible:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var edge = _get_edge(get_local_mouse_position())
			if edge != ResizeEdge.NONE:
				_resize_edge = edge
				_dragging = true
				_drag_start = get_global_mouse_position()
				_drag_start_width = panel_width
				_drag_start_height = panel_height
				get_viewport().set_input_as_handled()
		else:
			if _dragging:
				_dragging = false
				_resize_edge = ResizeEdge.NONE
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if _dragging:
			var delta = get_global_mouse_position() - _drag_start
			if _resize_edge == ResizeEdge.LEFT or _resize_edge == ResizeEdge.BOTTOM_LEFT:
				panel_width = max(MIN_WIDTH, _drag_start_width - delta.x)
			if _resize_edge == ResizeEdge.BOTTOM or _resize_edge == ResizeEdge.BOTTOM_LEFT:
				panel_height = max(MIN_HEIGHT, _drag_start_height + delta.y)
			_apply_size()
			get_viewport().set_input_as_handled()
		else:
			var edge = _get_edge(get_local_mouse_position())
			if edge != _hover_edge:
				_hover_edge = edge
				match edge:
					ResizeEdge.LEFT:
						Input.set_default_cursor_shape(Input.CURSOR_HSIZE)
					ResizeEdge.BOTTOM:
						Input.set_default_cursor_shape(Input.CURSOR_VSIZE)
					ResizeEdge.BOTTOM_LEFT:
						Input.set_default_cursor_shape(Input.CURSOR_FDIAGSIZE)
					ResizeEdge.NONE:
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

func _on_toggle_visibility_pressed():
	$NinePatchRect.visible = !$NinePatchRect.visible
	$ScrollContainer.visible = $NinePatchRect.visible
	$Eyes.frame = int(!$NinePatchRect.visible)
	if $NinePatchRect.visible:
		$Eyes.position = Vector2(-21, 12)
	else:
		$Eyes.position = Vector2(panel_width - 1, 12)
	$Area2D2/CollisionShape2D.disabled = !$NinePatchRect.visible
