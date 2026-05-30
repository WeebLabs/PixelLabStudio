extends Line2D
class_name WiggleAppendage2D

# A textured Line2D ribbon driven by an angular-spring chain whose REST shape is a
# user-traced path (the appendage's spine). The chain holds that (possibly curved)
# rest shape and wiggles around it; the owner bakes the layer's content, unwrapped
# along the same rest path, into a straight strip and assigns it as the texture,
# so at rest the ribbon re-wraps to exactly the original look and only deforms when
# it moves. Reuses Line2D (texture STRETCH) — proven for normals/premult/etc.
#
# Cleaned-up, decoupled port of PNGTuberRemix's WigglyAppendage2D angular-momentum
# chain (stiffness / damping / max-angle / comeback / gravity), generalised from a
# straight rest to an arbitrary rest path. Driven by the owning spriteObject via
# tick(); the root point follows this node's global_position, so avatar
# bounce/drag/wobble propagate into the chain as momentum (the whip / jiggle).

# physics point layout
const RENDER_POINTS := 96   # target Line2D point count for smooth edges at any physics resolution
const _PREV := 0   # reference to the previous point's array (null for root)
const _POS := 1    # Vector2 world position
const _ROT := 2    # float segment angle (radians)
const _MOM := 3    # float angular momentum (radians/sec)

# --- Dynamics (configure()) ---
var stiffness := 20.0
var stiffness_decay := 0.0
var stiffness_decay_exponent := 1.0
var damping := 5.0
var max_angular_momentum := 9.0
var max_angle := 0.6
var comeback_speed := 0.4
var rest_return := 0.0     # over-damped pull back to the rest shape (0 = pure spring)
var gravity := Vector2.ZERO
var root_follow_smoothness := 0.65
var motion_intensity := 1.0   # how strongly the layer's movement drives the whip (1 = normal)
var auto_wag := false
var wag_speed := 0.15
var wag_amount := 0.4
var subdivision := 3

# --- Geometry (set_geometry()), derived from the rest path ---
var segment_count := 8
var segment_length := 30.0
var _base_rest_angle := 0.0                              # root segment direction (local), at rest
var _rest_rel: PackedFloat32Array = PackedFloat32Array() # per-joint rest relative angle, index 1..N

var _points: Array = []
var _smoothed_root := Vector2.ZERO
var _prev_root_pos := Vector2.ZERO   # root world pos last frame, for motion_intensity
var _wag_offset := 0.0

func configure(p: Dictionary) -> void:
	stiffness = float(p.get("stiffness", stiffness))
	stiffness_decay = float(p.get("stiffness_decay", stiffness_decay))
	stiffness_decay_exponent = float(p.get("stiffness_decay_exponent", stiffness_decay_exponent))
	damping = float(p.get("damping", damping))
	max_angular_momentum = float(p.get("max_angular_momentum", max_angular_momentum))
	max_angle = float(p.get("max_angle", max_angle))
	comeback_speed = float(p.get("comeback_speed", comeback_speed))
	rest_return = float(p.get("rest_return", rest_return))
	gravity = p.get("gravity", gravity)
	root_follow_smoothness = float(p.get("root_follow_smoothness", root_follow_smoothness))
	motion_intensity = float(p.get("motion_intensity", motion_intensity))
	auto_wag = bool(p.get("auto_wag", auto_wag))
	wag_speed = float(p.get("wag_speed", wag_speed))
	wag_amount = float(p.get("wag_amount", wag_amount))
	subdivision = int(p.get("subdivision", subdivision))

# Define the rest shape from a centerline path in this node's LOCAL space (point 0
# at the root / node origin). Resamples into `segments` equal-arc segments and
# stores each joint's rest relative angle, so the chain springs back to this shape.
func set_geometry(rest_path_local: PackedVector2Array, segments: int) -> void:
	segment_count = clampi(segments, 1, 64)
	var pts := resample_equal_arc(rest_path_local, segment_count + 1)
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	segment_length = maxf(total / float(segment_count), 0.001)
	_rest_rel = PackedFloat32Array()
	_rest_rel.resize(segment_count + 1)
	var prev_ang := 0.0
	for i in segment_count:
		var seg_ang: float = (pts[i + 1] - pts[i]).angle()
		if i == 0:
			_base_rest_angle = seg_ang
			_rest_rel[1] = 0.0
		else:
			_rest_rel[i + 1] = _angle_diff(seg_ang, prev_ang)
		prev_ang = seg_ang
	reset()

# Snap the chain to its rest shape from the current root position. Call after
# set_geometry, on enable, or after a teleport so the chain doesn't fling.
func reset() -> void:
	if _rest_rel.size() < 2:
		return
	_points = []
	var start := get_global_position()
	_smoothed_root = start
	_prev_root_pos = start
	var ang := _base_rest_angle + global_rotation
	var pos := start
	_points.append([null, pos, ang, 0.0])
	for i in range(1, segment_count + 1):
		ang += _rest_rel[i]
		pos += Vector2(segment_length, 0).rotated(ang)
		_points.append([_points[-1], pos, ang, 0.0])
	_update_line()

# Advance one frame. frame_tick drives auto-wag (a per-layer frame counter).
func tick(delta: float, frame_tick: int) -> void:
	if delta <= 0.0 or _points.size() < 2:
		return
	# Auto-wag is a clean sinusoidal sway of the root direction; the chain follows
	# it with spring lag, so the base moves smoothly and the tip whips.
	_wag_offset = (sin(float(frame_tick) * wag_speed) * wag_amount) if auto_wag else 0.0
	_process_root(_points[0], delta)
	# Motion intensity: carry the rest of the chain along with (1 - intensity) of
	# the root's actual displacement this frame, so `motion_intensity` scales how
	# much the layer's movement is felt as relative lag (the whip). 1 = full
	# (default), 0 = rides along rigidly (ignores motion), >1 = exaggerated.
	var root_motion: Vector2 = _points[0][_POS] - _prev_root_pos
	_prev_root_pos = _points[0][_POS]
	var carry := root_motion * (1.0 - motion_intensity)
	for i in range(1, _points.size()):
		_points[i][_POS] += carry
		_process_point(_points[i], delta, i)
	_update_line()

func _process_root(point: Array, delta: float) -> void:
	var cur := get_global_position()
	# Frame-rate-independent exponential smoothing toward the live root position.
	var f := 1.0 - pow(1.0 - root_follow_smoothness, delta * 60.0)
	_smoothed_root = _smoothed_root.lerp(cur, f)
	point[_POS] = _smoothed_root
	point[_ROT] = _base_rest_angle + global_rotation + _wag_offset

func _process_point(point: Array, delta: float, index: int) -> void:
	var prev = point[_PREV]
	var dir: Vector2 = prev[_POS].direction_to(point[_POS])
	var rot: float = dir.angle()
	# Spring toward the parent's angle plus this joint's REST relative angle, so the
	# chain holds the traced shape (not a straight line).
	var ideal: float = prev[_ROT] + _rest_rel[index]
	var diff := _angle_diff(ideal, rot)
	var k := maxf(0.0, stiffness - pow(float(index), stiffness_decay_exponent) * stiffness_decay)
	var force := _signed_sqrt(diff) * k
	force += gravity.length() * cos(rot - gravity.angle() + TAU / 4.0)
	# Standard linear damping: smooth, symmetric response (no brake-on-reversal
	# stutter). The momentum cap then limits how fast a rotation travels down.
	point[_MOM] += (force - damping * point[_MOM]) * delta
	point[_MOM] = clampf(point[_MOM], -max_angular_momentum, max_angular_momentum)
	rot += point[_MOM] * delta
	# Hard angle limit relative to the parent's REST, with a comeback spring.
	if absf(diff) > max_angle:
		rot += diff - absf(max_angle) * signf(diff)
		if signf(point[_MOM]) != signf(diff) or absf(point[_MOM]) < comeback_speed:
			point[_MOM] = comeback_speed * signf(diff)
	# Over-damped settle toward the rest shape — "how much it wants to return to its
	# original shape", separate from the spring: pulls the angle straight back to
	# rest and bleeds momentum, so it eases home without the spring's overshoot.
	if rest_return > 0.0:
		var rf := 1.0 - pow(1.0 - clampf(rest_return, 0.0, 1.0), delta * 60.0)
		rot += _angle_diff(ideal, rot) * rf
		point[_MOM] *= (1.0 - rf)
	point[_ROT] = rot
	point[_POS] = prev[_POS] + Vector2(segment_length, 0).rotated(rot)

func _update_line() -> void:
	var pts := PackedVector2Array()
	for p in _points:
		pts.append(to_local(p[_POS]))
	# Render resolution is decoupled from physics resolution: smooth the chain with
	# a Catmull-Rom spline to a high fixed point count, so the ribbon stays a smooth
	# curve (no faceting/stair-step on warped edges) even at low segment counts —
	# which give smoother motion but a coarse polyline. Catmull-Rom rounds sparse
	# points far better than the quadratic bezier, and passes through the endpoints
	# (so the tip is exact — no overshoot "tail").
	var seg := maxi(pts.size() - 1, 1)
	var per := clampi(int(ceil(float(RENDER_POINTS) / float(seg))), subdivision, 48)
	points = smooth_path(pts, per) if pts.size() >= 3 else pts

# Position along the chain at normalized t in [0,1], in this node's local space.
# Used by child-follow so attached props ride the ribbon.
func sample_local(t: float) -> Vector2:
	if _points.is_empty():
		return Vector2.ZERO
	t = clampf(t, 0.0, 1.0)
	var fpos := t * float(_points.size() - 1)
	var i := int(fpos)
	if i >= _points.size() - 1:
		return to_local(_points[-1][_POS])
	return to_local(_points[i][_POS]).lerp(to_local(_points[i + 1][_POS]), fpos - float(i))

# --- Geometry helpers (static, shared with the owner's bake) ---

# Catmull-Rom smoothing of control points into a dense polyline. Endpoints are
# duplicated so the curve passes through the first/last control point.
static func smooth_path(control: PackedVector2Array, per_seg: int = 10) -> PackedVector2Array:
	var n := control.size()
	if n < 3 or per_seg < 2:
		return control
	var out := PackedVector2Array()
	for i in n - 1:
		var p0: Vector2 = control[i - 1] if i > 0 else control[i]
		var p1: Vector2 = control[i]
		var p2: Vector2 = control[i + 1]
		var p3: Vector2 = control[i + 2] if i + 2 < n else control[i + 1]
		for s in per_seg:
			var t := float(s) / float(per_seg)
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(control[n - 1])
	return out

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

# Resample a polyline into exactly `m` points spaced equally by arc length.
static func resample_equal_arc(pts: PackedVector2Array, m: int) -> PackedVector2Array:
	if pts.size() < 2 or m < 2:
		return pts
	var seg_len := PackedFloat32Array()
	var total := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		seg_len.append(l)
		total += l
	var out := PackedVector2Array()
	out.append(pts[0])
	if total < 0.0001:
		for k in range(1, m):
			out.append(pts[0])
		return out
	var step := total / float(m - 1)
	var seg := 0
	var acc := 0.0
	for k in range(1, m - 1):
		var target := step * float(k)
		while seg < seg_len.size() - 1 and acc + seg_len[seg] < target:
			acc += seg_len[seg]
			seg += 1
		var t := (target - acc) / maxf(seg_len[seg], 0.0001)
		out.append(pts[seg].lerp(pts[seg + 1], t))
	out.append(pts[pts.size() - 1])
	return out

func _angle_diff(a: float, b: float) -> float:
	var d := a - b
	if absf(d) > PI:
		d -= TAU * signf(d)
	return d

func _signed_sqrt(v: float) -> float:
	return sqrt(absf(v)) * signf(v)
