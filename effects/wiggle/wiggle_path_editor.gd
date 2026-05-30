extends Node2D
class_name WigglePathEditor

# On-canvas editor for a layer's wiggle ribbon path (the appendage's spine). Lives
# as a child of the layer's DragOrigin while Global.wigglePathMode is on for that
# layer, so it inherits the content's transform and stays glued to the artwork as
# it wobbles. The user traces a multi-point centerline directly over the artwork;
# the band shows the swept thickness, so irregular / canvas-sized layers can be
# given a spine that follows their actual content (fixing the off-origin displace).
#
# Direct manipulation, all in the layer's texture space (owner.wigglePath, px):
#   • drag a handle    — move that control point
#   • click empty      — add a point (split the nearest segment, or extend an end)
#                        then immediately drag it (click-place-drag)
#   • right-click a pt  — remove it (min two kept)
# Geometry is only re-baked when the (hidden) ribbon needs it — on exit / auto-fit
# (owner.apply_wiggle_path_changed) — so dragging stays cheap. The editor draws
# itself every frame; the owner shows the static Sprite2D underneath for tracing.

const ACCENT := Color(1.0, 0.7, 0.8)              # theme pink
const BAND_FILL := Color(1.0, 0.7, 0.8, 0.13)
const BAND_EDGE := Color(1.0, 0.7, 0.8, 0.45)
const CENTER_LINE := Color(1.0, 0.72, 0.82, 0.95)
const FLOW := Color(1.0, 0.86, 0.92, 0.85)
const HANDLE_CORE := Color(0.12, 0.12, 0.15, 0.96)
const HANDLE_RING := Color(1.0, 0.88, 0.93)
const ROOT_COL := Color(1.0, 0.72, 0.82)          # warm anchor
const TIP_COL := Color(0.62, 0.88, 1.0)           # cool free end
const HALO := Color(1.0, 1.0, 1.0, 0.65)

const WIDTH_CORE := Color(0.12, 0.12, 0.15, 0.95)
const WIDTH_EDGE := Color(1.0, 0.82, 0.4)         # amber width grips (vs pink position handles)
const WIDTH_SPOKE := Color(1.0, 0.82, 0.4, 0.4)

const HANDLE_R := 6.0          # screen px (scaled to constant on-screen size)
const WIDTH_R := 4.5           # screen px half-size of the square width grips
const HIT_R := 11.0            # screen px hit radius for grabbing a handle
const INSERT_NEAR := 16.0      # screen px: within this of the line -> split it
const MIN_WIDTH := 1.0         # min per-point half-width (px)

var owner_sprite = null        # the spriteObject we edit
var _drag := -1                # control point index being dragged, -1 = none
var _hover := -1               # control point index under the cursor
var _width_drag := -1          # control point whose width grip is being dragged
var _width_hover := -1         # control point whose width grip is under the cursor

func setup(spr) -> void:
	owner_sprite = spr
	z_index = 1000               # draw above the artwork
	z_as_relative = false
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

# Editor-local units per on-screen pixel: 1 / (world-scale * camera-zoom). Keeps
# handles and line weights a constant on-screen size at any zoom or layer scale.
func _px() -> float:
	var s: float = get_global_transform_with_canvas().get_scale().x
	return 1.0 / s if s > 0.0001 else 1.0

func _mouse_tex() -> Vector2:
	return owner_sprite._local_to_tex(to_local(get_global_mouse_position()))

# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if owner_sprite == null or not Global.wigglePathMode or Global.heldSprite != owner_sprite:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var tex := _mouse_tex()
				_ensure_widths()
				var ph := _hit_handle(tex)               # position grip
				var wh := _hit_width_handle(tex)         # width grip
				var pd := tex.distance_to(owner_sprite.wigglePath[ph]) if ph >= 0 else INF
				var wd := tex.distance_to(_width_handle_tex(wh)) if wh >= 0 else INF
				UndoManager.save_state()
				if wh >= 0 and wd <= pd:
					_width_drag = wh                     # grab the closer of the two
				elif ph >= 0:
					_drag = ph
				else:
					_drag = _insert_point(tex)
				queue_redraw()
				get_viewport().set_input_as_handled()
			elif _drag >= 0 or _width_drag >= 0:
				_drag = -1
				_width_drag = -1
				owner_sprite.apply_wiggle_path_changed()
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hit := _hit_handle(_mouse_tex())
			if hit >= 0:
				UndoManager.save_state()
				_remove_point(hit)
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var tex := _mouse_tex()
		if _width_drag >= 0:
			# Perpendicular distance from the centerline = the displayed half-width;
			# divide out the global thickness so the stored per-point width is the
			# base taper profile (thickness still scales it).
			var d: float = absf((tex - owner_sprite.wigglePath[_width_drag]).dot(_path_normal(_width_drag)))
			var base: float = d / maxf(owner_sprite.wiggleThickness, 0.01)
			owner_sprite.wigglePathWidths[_width_drag] = maxf(base, MIN_WIDTH)
			queue_redraw()
			get_viewport().set_input_as_handled()
		elif _drag >= 0:
			owner_sprite.wigglePath[_drag] = tex
			queue_redraw()
			get_viewport().set_input_as_handled()
		else:
			var h := _hit_handle(tex)
			var wh := _hit_width_handle(tex)
			if wh >= 0 and tex.distance_to(_width_handle_tex(wh)) < (tex.distance_to(owner_sprite.wigglePath[h]) if h >= 0 else INF):
				h = -1   # width grip wins the hover
			if h != _hover or wh != _width_hover:
				_hover = h
				_width_hover = wh if h < 0 else -1
				queue_redraw()

# Nearest control point within the hit radius, or -1.
func _hit_handle(tex: Vector2) -> int:
	var path: PackedVector2Array = owner_sprite.wigglePath
	var thr := HIT_R * _px()
	var best := -1
	var best_d := thr
	for i in path.size():
		var d := tex.distance_to(path[i])
		if d <= best_d:
			best_d = d
			best = i
	return best

# Add a point and return its new index (so the caller can start dragging it).
# Splits the nearest segment if the click is near the line; otherwise extends
# whichever end is closer. New width is interpolated / copied from neighbours.
func _insert_point(tex: Vector2) -> int:
	var path: PackedVector2Array = owner_sprite.wigglePath
	var ws: PackedFloat32Array = owner_sprite.wigglePathWidths
	while ws.size() < path.size():
		ws.append(16.0)
	if path.size() < 2:
		path.append(tex)
		ws.append(ws[ws.size() - 1] if ws.size() > 0 else 16.0)
		owner_sprite.wigglePath = path
		owner_sprite.wigglePathWidths = ws
		return path.size() - 1

	var best_i := -1
	var best_t := 0.0
	var best_d := INF
	for i in path.size() - 1:
		var pr := _project(tex, path[i], path[i + 1])
		if pr.y < best_d:
			best_d = pr.y
			best_i = i
			best_t = pr.x

	var idx: int
	if best_d <= INSERT_NEAR * _px() and best_t > 0.02 and best_t < 0.98:
		idx = best_i + 1
		path.insert(idx, tex)
		ws.insert(idx, lerp(ws[best_i], ws[best_i + 1], best_t))
	elif tex.distance_to(path[path.size() - 1]) <= tex.distance_to(path[0]):
		path.append(tex)
		ws.append(ws[ws.size() - 1])
		idx = path.size() - 1
	else:
		path.insert(0, tex)
		ws.insert(0, ws[0])
		idx = 0
	owner_sprite.wigglePath = path
	owner_sprite.wigglePathWidths = ws
	return idx

func _remove_point(i: int) -> void:
	var path: PackedVector2Array = owner_sprite.wigglePath
	if path.size() <= 2:
		return
	var ws: PackedFloat32Array = owner_sprite.wigglePathWidths
	path.remove_at(i)
	if i < ws.size():
		ws.remove_at(i)
	owner_sprite.wigglePath = path
	owner_sprite.wigglePathWidths = ws
	_hover = -1
	owner_sprite.apply_wiggle_path_changed()
	queue_redraw()

# Project point p onto segment a-b; returns (t in [0,1], distance).
func _project(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 < 0.0001 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return Vector2(t, p.distance_to(a + ab * t))

# --- per-point width grips (Phase 4) -----------------------------------------

# Keep the per-point widths array the same length as the path.
func _ensure_widths() -> void:
	var path: PackedVector2Array = owner_sprite.wigglePath
	var ws: PackedFloat32Array = owner_sprite.wigglePathWidths
	if ws.size() == path.size():
		return
	while ws.size() < path.size():
		ws.append(ws[ws.size() - 1] if ws.size() > 0 else 16.0)
	while ws.size() > path.size():
		ws.remove_at(ws.size() - 1)
	owner_sprite.wigglePathWidths = ws

# Path normal at control point i (perpendicular to the local tangent), texture space.
func _path_normal(i: int) -> Vector2:
	var path: PackedVector2Array = owner_sprite.wigglePath
	var n := path.size()
	var t: Vector2 = path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]
	if t.length() < 0.001:
		t = Vector2.RIGHT
	return t.normalized().orthogonal()

# Texture-space position of control point i's width grip (on the band edge, the
# displayed half-width = base width * thickness out along the path normal).
func _width_handle_tex(i: int) -> Vector2:
	if i < 0:
		return Vector2.ZERO
	var ws: PackedFloat32Array = owner_sprite.wigglePathWidths
	var w: float = (ws[i] if i < ws.size() else 16.0) * maxf(owner_sprite.wiggleThickness, 0.01)
	return owner_sprite.wigglePath[i] + _path_normal(i) * w

# Nearest width grip within the hit radius, or -1.
func _hit_width_handle(tex: Vector2) -> int:
	var path: PackedVector2Array = owner_sprite.wigglePath
	var thr := HIT_R * _px()
	var best := -1
	var best_d := thr
	for i in path.size():
		var d := tex.distance_to(_width_handle_tex(i))
		if d <= best_d:
			best_d = d
			best = i
	return best

# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	var o = owner_sprite
	if o == null:
		return
	var path: PackedVector2Array = o.wigglePath
	if path.size() < 1:
		return
	var ppx := _px()

	# Smooth centerline + per-point half-widths (px), scaled by the thickness knob
	# so the band previews the ribbon's actual swept coverage.
	var smooth: PackedVector2Array = WiggleAppendage2D.smooth_path(path, 8) if path.size() >= 3 else path
	var widths: PackedFloat32Array = o._smooth_widths(smooth)
	var k: float = maxf(o.wiggleThickness, 0.01)
	for wi in widths.size():
		widths[wi] *= k
	var n := smooth.size()

	var ctr := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var c: Vector2 = o._tex_to_local(smooth[i])
		ctr.append(c)
		var a: Vector2 = smooth[maxi(i - 1, 0)]
		var b: Vector2 = smooth[mini(i + 1, n - 1)]
		var tang := b - a
		if tang.length() < 0.0001:
			tang = Vector2.RIGHT
		var nrm := tang.normalized().orthogonal()
		left.append(c + nrm * widths[i])
		right.append(c - nrm * widths[i])

	# Swept band (per-segment quads — robust vs. a single concave polygon).
	for i in n - 1:
		draw_colored_polygon(PackedVector2Array([left[i], left[i + 1], right[i + 1], right[i]]), BAND_FILL)
	if n >= 2:
		draw_polyline(left, BAND_EDGE, 1.0 * ppx, true)
		draw_polyline(right, BAND_EDGE, 1.0 * ppx, true)
		draw_polyline(ctr, CENTER_LINE, 2.0 * ppx, true)
		_draw_flow(ctr, ppx)

	# Per-point width grips: an amber square on a spoke out to the band edge — drag
	# to taper that point. Drawn under the position handles so the points stay on top.
	for i in path.size():
		var cp: Vector2 = o._tex_to_local(path[i])
		var wp: Vector2 = o._tex_to_local(_width_handle_tex(i))
		var wactive: bool = (i == _width_hover or i == _width_drag)
		draw_line(cp, wp, WIDTH_SPOKE, 1.0 * ppx, true)
		var wr := (WIDTH_R + (1.5 if wactive else 0.0)) * ppx
		if wactive:
			draw_arc(wp, wr + 3.0 * ppx, 0.0, TAU, 16, HALO, 1.0 * ppx, true)
		draw_rect(Rect2(wp - Vector2(wr, wr), Vector2(wr * 2.0, wr * 2.0)), WIDTH_CORE)
		draw_rect(Rect2(wp - Vector2(wr, wr), Vector2(wr * 2.0, wr * 2.0)), WIDTH_EDGE, false, 1.5 * ppx)

	# Control handles: root = warm filled diamond, tip = cool ring, mid = dot.
	for i in path.size():
		var lp: Vector2 = o._tex_to_local(path[i])
		var active: bool = (i == _hover or i == _drag)
		var r := (HANDLE_R + (2.0 if active else 0.0)) * ppx
		if active:
			draw_arc(lp, r + 3.0 * ppx, 0.0, TAU, 24, HALO, 1.0 * ppx, true)
		if i == 0:
			var d := _diamond(lp, r * 1.5)
			draw_colored_polygon(d, ROOT_COL)
			d.append(d[0])
			draw_polyline(d, HANDLE_CORE, 1.5 * ppx, true)
		elif i == path.size() - 1:
			draw_circle(lp, r * 1.15, HANDLE_CORE)
			draw_arc(lp, r * 1.15, 0.0, TAU, 24, TIP_COL, 2.0 * ppx, true)
		else:
			draw_circle(lp, r, HANDLE_CORE)
			draw_arc(lp, r, 0.0, TAU, 20, HANDLE_RING, 1.5 * ppx, true)

func _draw_flow(ctr: PackedVector2Array, ppx: float) -> void:
	var n := ctr.size()
	if n < 2:
		return
	var s := 5.0 * ppx
	for f in [0.22, 0.5, 0.78]:
		var fi: float = f * float(n - 1)
		var i := clampi(int(fi), 0, n - 2)
		var c: Vector2 = ctr[i].lerp(ctr[i + 1], fi - float(i))
		var dir: Vector2 = (ctr[i + 1] - ctr[i])
		if dir.length() < 0.0001:
			continue
		dir = dir.normalized()
		var m := dir.orthogonal()
		var tip := c + dir * s
		draw_line(tip, c - dir * s + m * s, FLOW, 1.5 * ppx, true)
		draw_line(tip, c - dir * s - m * s, FLOW, 1.5 * ppx, true)

func _diamond(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
