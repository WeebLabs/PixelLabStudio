extends Node2D

## NDI Ruler - Draggable horizontal crop line
## Marks the avatar's bottom boundary for NDI framing.
## Visible in edit mode when NDI is enabled.

var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_start_mouse_y: float = 0.0

const LINE_COLOR = Color(1.0, 0.55, 0.0, 0.85)  # Orange
const LINE_COLOR_HOVER = Color(1.0, 0.7, 0.2, 1.0)
const HANDLE_COLOR = Color(1.0, 0.55, 0.0, 1.0)
const DASH_LENGTH = 12.0
const GAP_LENGTH = 8.0
const LINE_WIDTH = 2.0
const GRAB_THRESHOLD = 12.0

var _hovered: bool = false
var _last_cam_pos: Vector2
var _last_cam_zoom: float
var _last_vp_size: Vector2
var _last_node_pos: Vector2

func _ready():
	z_index = 100

func _process(_delta):
	if !visible:
		return

	var origin = Global.main.origin
	position = origin.global_position + Vector2(0, _get_ruler_y())

	# Update hover state
	var mouse_pos = get_global_mouse_position()
	var dist = abs(mouse_pos.y - global_position.y)
	var was_hovered = _hovered
	_hovered = dist < GRAB_THRESHOLD / Global.main.camera.zoom.x

	# Redraw when any value that affects drawing changes
	var cam = Global.main.camera
	var vp_size = Global.main.get_viewport().get_visible_rect().size
	if _hovered != was_hovered or _dragging \
			or cam.position != _last_cam_pos \
			or cam.zoom.x != _last_cam_zoom \
			or vp_size != _last_vp_size \
			or global_position != _last_node_pos:
		_last_cam_pos = cam.position
		_last_cam_zoom = cam.zoom.x
		_last_vp_size = vp_size
		_last_node_pos = global_position
		queue_redraw()

func _draw():
	var cam = Global.main.camera
	var vp_size = Global.main.get_viewport().get_visible_rect().size
	var half_w = (vp_size.x / cam.zoom.x) * 0.5

	var start_x = -half_w - 100
	var end_x = half_w + 100

	var color = LINE_COLOR_HOVER if (_hovered or _dragging) else LINE_COLOR
	var width = LINE_WIDTH / cam.zoom.x

	# Draw dashed line (all coordinates local to this node, so y=0 is the line)
	var cam_center_x = cam.position.x - global_position.x
	var draw_start = cam_center_x + start_x
	var draw_end = cam_center_x + end_x

	var x = draw_start
	while x < draw_end:
		var seg_end = min(x + DASH_LENGTH / cam.zoom.x, draw_end)
		draw_line(Vector2(x, 0), Vector2(seg_end, 0), color, width)
		x = seg_end + GAP_LENGTH / cam.zoom.x

	# Draw handle indicators at center of view
	var handle_size = 8.0 / cam.zoom.x
	var hx = cam_center_x
	draw_rect(Rect2(hx - handle_size, -handle_size, handle_size * 2, handle_size * 2), HANDLE_COLOR)

	# Draw label
	var font = ThemeDB.fallback_font
	if font:
		var font_size = int(12.0 / cam.zoom.x)
		font_size = max(font_size, 8)
		draw_string(font, Vector2(hx + handle_size + 4.0 / cam.zoom.x, handle_size + font_size),
					"NDI Crop", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _unhandled_input(event):
	if !visible:
		return
	if !Global.main.editMode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_global_mouse_position()
			var dist = abs(mouse_pos.y - global_position.y)
			var cam_zoom = Global.main.camera.zoom.x
			if dist < GRAB_THRESHOLD / cam_zoom:
				_dragging = true
				_drag_start_y = _get_ruler_y()
				_drag_start_mouse_y = mouse_pos.y
				_set_freeze(true)
				get_viewport().set_input_as_handled()
		else:
			if _dragging:
				_dragging = false
				_set_freeze(false)
				_save_ruler_y()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		var mouse_pos = get_global_mouse_position()
		var delta_y = mouse_pos.y - _drag_start_mouse_y
		var new_y = _drag_start_y + delta_y
		_set_ruler_y(new_y)
		get_viewport().set_input_as_handled()

func _get_ruler_y() -> float:
	return Saving.settings["ndiRulerY"]

func _set_ruler_y(y: float):
	Saving.settings["ndiRulerY"] = y
	# Mark NDI manager dirty
	var ndi_manager = get_parent().get_node_or_null("NDIManager")
	if ndi_manager:
		ndi_manager.mark_dirty()

func _set_freeze(frozen: bool):
	var ndi_manager = Global.main.ndi_manager
	if ndi_manager:
		ndi_manager.ruler_dragging = frozen
	if frozen:
		# Freeze bounce: snap OriginMotion to rest
		Global.main.origin.get_parent().position.y = 0
		Global.main.yVel = 0
		# Push sprites to max downward wobble extent
		var sprites = get_tree().get_nodes_in_group("saved")
		for sprite_obj in sprites:
			if sprite_obj.visible:
				sprite_obj.wob.position.y = abs(sprite_obj.yAmp)

func _save_ruler_y():
	Global.pushUpdate("NDI crop line moved to Y=" + str(int(_get_ruler_y())))
