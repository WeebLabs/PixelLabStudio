extends Node2D

## NDI Crop Box - Resizable orange rectangle defining the NDI output region.
## Replaces the old auto-framing + horizontal crop line: the user draws the
## frame directly. Resize via 8 gizmos — one at the midpoint of each edge
## (moves that edge) and one in each corner (moves both adjacent edges).
## Grabbing anywhere along an edge's dashed line also moves that edge, so the
## bottom edge still handles like the old crop line.
## Visible in edit mode when NDI is enabled. The box is stored origin-relative
## in Saving.settings["ndiCropRect"] = [left, top, right, bottom] and travels
## with the avatar save (see main.gd "_ndiCropRect").

const LINE_COLOR = Color(1.0, 0.55, 0.0, 0.85)  # Orange
const LINE_COLOR_HOVER = Color(1.0, 0.7, 0.2, 1.0)
const HANDLE_COLOR = Color(1.0, 0.55, 0.0, 1.0)
const HANDLE_COLOR_HOVER = Color(1.0, 0.8, 0.3, 1.0)
const DASH_LENGTH = 12.0
const GAP_LENGTH = 8.0
const LINE_WIDTH = 2.0
const GRAB_THRESHOLD = 12.0
const HANDLE_SIZE = 8.0     # half-size of the gizmo squares, screen px
const MIN_SIZE = 64.0       # minimum box width/height, world px

# Handle ids. Edge midpoints move one side; corners move two; H_MOVE (grabbing a
# bare edge line, away from any gizmo) translates the whole box without resizing.
enum { H_NONE = -1, H_L, H_R, H_T, H_B, H_TL, H_TR, H_BL, H_BR, H_MOVE }

var _dragging: int = H_NONE
var _drag_start_edges: Array = []
var _drag_start_mouse := Vector2.ZERO

var _hovered: int = H_NONE
var _last_cam_pos: Vector2
var _last_cam_zoom: float
var _last_vp_size: Vector2
var _last_node_pos: Vector2
var _last_edges: Array = []
# Tracks whether we own the current cursor override (to avoid resetting
# another component's cursor when we leave hover).
var _set_cursor: bool = false

func _ready():
	z_index = 100

func _process(_delta):
	if !visible:
		return

	# Anchor to the avatar's REST position, not its live (bouncing) position. The NDI
	# camera frames the box at rest and stays put while the avatar bounces through it
	# (see ndi_output_manager._recalculate_framing), so anchoring the box to the live
	# origin made it ride the bounce here while the real OBS frame stayed still. Subtract
	# the bounce offset (OriginMotion.position.y) so the on-canvas box matches the output.
	var origin = Global.main.origin
	var bounce_offset = origin.get_parent().position.y
	position = origin.global_position - Vector2(0, bounce_offset)

	# Update hover state. Hover applies only when the cursor is near a gizmo or
	# edge AND not over either sidebar — sidebars block dragging and the cursors.
	var was_hovered = _hovered
	if _dragging != H_NONE:
		_hovered = _dragging
	elif _mouse_over_sidebar():
		_hovered = H_NONE
	else:
		_hovered = _hit_test(to_local(get_global_mouse_position()))

	if _hovered != H_NONE:
		Input.set_default_cursor_shape(_cursor_for(_hovered))
		_set_cursor = true
	elif _set_cursor:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		_set_cursor = false

	# Redraw when any value that affects drawing changes
	var cam = Global.main.camera
	var vp_size = Global.main.get_viewport().get_visible_rect().size
	var edges = _edges()
	if _hovered != was_hovered or _dragging != H_NONE \
			or cam.position != _last_cam_pos \
			or cam.zoom.x != _last_cam_zoom \
			or vp_size != _last_vp_size \
			or global_position != _last_node_pos \
			or edges != _last_edges:
		_last_cam_pos = cam.position
		_last_cam_zoom = cam.zoom.x
		_last_vp_size = vp_size
		_last_node_pos = global_position
		_last_edges = edges
		queue_redraw()

func _draw():
	var cam = Global.main.camera
	var zoom = cam.zoom.x
	var e = _edges()
	var color = LINE_COLOR_HOVER if (_hovered != H_NONE or _dragging != H_NONE) else LINE_COLOR
	var width = LINE_WIDTH / zoom

	# Dashed edges (local coords are origin-relative, same space as the rect)
	var tl = Vector2(e[0], e[1])
	var tr = Vector2(e[2], e[1])
	var bl = Vector2(e[0], e[3])
	var br = Vector2(e[2], e[3])
	_draw_dashed(tl, tr, color, width, zoom)
	_draw_dashed(bl, br, color, width, zoom)
	_draw_dashed(tl, bl, color, width, zoom)
	_draw_dashed(tr, br, color, width, zoom)

	# Gizmo squares: 4 corners + 4 edge midpoints, constant screen size
	var hs = HANDLE_SIZE / zoom
	var points = _handle_points(e)
	for h in points:
		var p: Vector2 = points[h]
		var c = HANDLE_COLOR_HOVER if h == _hovered else HANDLE_COLOR
		var s = hs * (1.25 if h == _hovered else 1.0)
		draw_rect(Rect2(p - Vector2(s, s), Vector2(s * 2, s * 2)), c)

	# Label by the bottom-center gizmo (where the old crop-line label lived)
	var font = ThemeDB.fallback_font
	if font:
		var font_size = max(int(12.0 / zoom), 8)
		var lp: Vector2 = points[H_B] + Vector2(hs + 4.0 / zoom, hs + font_size)
		draw_string(font, lp, "NDI Crop", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float, zoom: float):
	var dir = (to - from).normalized()
	var total = from.distance_to(to)
	var t = 0.0
	while t < total:
		var seg_end = min(t + DASH_LENGTH / zoom, total)
		draw_line(from + dir * t, from + dir * seg_end, color, width)
		t = seg_end + GAP_LENGTH / zoom

func _unhandled_input(event):
	if !visible:
		return
	if !Global.main.editMode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Don't let the click start a drag if the cursor is over a sidebar
			if _mouse_over_sidebar():
				return
			var h = _hit_test(to_local(get_global_mouse_position()))
			if h != H_NONE:
				_dragging = h
				_drag_start_edges = _edges()
				_drag_start_mouse = get_global_mouse_position()
				_set_freeze(true)
				get_viewport().set_input_as_handled()
		else:
			if _dragging != H_NONE:
				_dragging = H_NONE
				_set_freeze(false)
				Global.pushUpdate("NDI crop box updated.")
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging != H_NONE:
		var d = get_global_mouse_position() - _drag_start_mouse
		var e = _drag_start_edges.duplicate()
		if _dragging == H_MOVE:
			# Translate all four edges together: reposition without resizing.
			e[0] = _drag_start_edges[0] + d.x
			e[1] = _drag_start_edges[1] + d.y
			e[2] = _drag_start_edges[2] + d.x
			e[3] = _drag_start_edges[3] + d.y
		else:
			# Move the edges this handle controls, never collapsing below MIN_SIZE
			if _dragging in [H_L, H_TL, H_BL]:
				e[0] = min(_drag_start_edges[0] + d.x, e[2] - MIN_SIZE)
			if _dragging in [H_R, H_TR, H_BR]:
				e[2] = max(_drag_start_edges[2] + d.x, e[0] + MIN_SIZE)
			if _dragging in [H_T, H_TL, H_TR]:
				e[1] = min(_drag_start_edges[1] + d.y, e[3] - MIN_SIZE)
			if _dragging in [H_B, H_BL, H_BR]:
				e[3] = max(_drag_start_edges[3] + d.y, e[1] + MIN_SIZE)
		_write_edges(e)
		queue_redraw()
		get_viewport().set_input_as_handled()

# --- Geometry / hit testing ---

func _edges() -> Array:
	var ndi_manager = Global.main.ndi_manager
	if ndi_manager != null:
		return ndi_manager.get_crop_edges()
	var a = Saving.settings.get("ndiCropRect", [-500.0, -800.0, 500.0, 200.0])
	return [float(a[0]), float(a[1]), float(a[2]), float(a[3])]

func _write_edges(e: Array):
	var ndi_manager = Global.main.ndi_manager
	if ndi_manager != null:
		ndi_manager.set_crop_edges(e)

func _handle_points(e: Array) -> Dictionary:
	var mx = (e[0] + e[2]) * 0.5
	var my = (e[1] + e[3]) * 0.5
	return {
		H_TL: Vector2(e[0], e[1]), H_TR: Vector2(e[2], e[1]),
		H_BL: Vector2(e[0], e[3]), H_BR: Vector2(e[2], e[3]),
		H_L: Vector2(e[0], my), H_R: Vector2(e[2], my),
		H_T: Vector2(mx, e[1]), H_B: Vector2(mx, e[3]),
	}

# Nearest handle within grab range of a local-space point, or the edge line
# under it (a gizmo resizes; a bare edge line, away from any gizmo, moves the box).
func _hit_test(p: Vector2) -> int:
	var zoom = Global.main.camera.zoom.x
	var thr = GRAB_THRESHOLD / zoom
	var e = _edges()
	var points = _handle_points(e)
	for h in [H_TL, H_TR, H_BL, H_BR, H_L, H_R, H_T, H_B]:
		if p.distance_to(points[h]) < thr:
			return h
	# Bare edge lines (away from the gizmos above): grab anywhere along a side to
	# drag the whole box without resizing.
	var in_x = p.x > e[0] - thr and p.x < e[2] + thr
	var in_y = p.y > e[1] - thr and p.y < e[3] + thr
	if in_x and (abs(p.y - e[1]) < thr or abs(p.y - e[3]) < thr):
		return H_MOVE
	if in_y and (abs(p.x - e[0]) < thr or abs(p.x - e[2]) < thr):
		return H_MOVE
	return H_NONE

func _cursor_for(h: int) -> int:
	match h:
		H_L, H_R:
			return Input.CURSOR_HSIZE
		H_T, H_B:
			return Input.CURSOR_VSIZE
		H_TL, H_BR:
			return Input.CURSOR_FDIAGSIZE
		H_TR, H_BL:
			return Input.CURSOR_BDIAGSIZE
		H_MOVE:
			return Input.CURSOR_MOVE
	return Input.CURSOR_ARROW

func _set_freeze(frozen: bool):
	var ndi_manager = Global.main.ndi_manager
	if ndi_manager:
		ndi_manager.crop_dragging = frozen
	if frozen:
		# Freeze bounce: snap OriginMotion to rest
		Global.main.origin.get_parent().position.y = 0
		Global.main.yVel = 0
		# Push sprites to max downward wobble extent, zero horizontal wobble
		var sprites = get_tree().get_nodes_in_group("saved")
		for sprite_obj in sprites:
			if sprite_obj.visible:
				sprite_obj.wob.position.y = abs(sprite_obj.yAmp)
				sprite_obj.wob.position.x = 0

# Returns true when the mouse is currently over the left (sprite-edit) or
# right (layer-list) sidebar. Uses viewport-pixel coordinates because the
# sidebars are HUD-layer Controls positioned in screen space.
func _mouse_over_sidebar() -> bool:
	var vp = Global.main.get_viewport()
	if vp == null:
		return false
	var screen_x = vp.get_mouse_position().x
	if Global.spriteEdit != null and Global.spriteEdit.visible:
		# Left sidebar — bounds matched to spriteEdit._unhandled_input
		if screen_x < Global.spriteEdit.panel_width + 19:
			return true
	if Global.spriteList != null:
		# Right sidebar — anchored at viewport_width - (panel_width + 3)
		var vp_w = vp.get_visible_rect().size.x
		if screen_x > vp_w - (Global.spriteList.panel_width + 3):
			return true
	return false
