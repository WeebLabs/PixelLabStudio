extends Line2D
class_name WiggleAppendage2D

# A textured Line2D ribbon driven by an angular-spring/verlet chain. The layer's
# texture is stretched along the chain (texture_mode = STRETCH), so the appendage
# bends geometrically — no quad clipping, and (unlike a UV-warp shader) Line2D
# carries CanvasTexture normal-mapped lighting.
#
# Cleaned-up, decoupled port of PNGTuberRemix's WigglyAppendage2D: keeps the core
# angular-momentum spring chain (stiffness / damping / max-angle / comeback /
# curvature / gravity) but drops the anchor-targeting, mirror-movement, and
# actor.get_value() coupling. The owning spriteObject drives it via tick(); the
# root point follows this node's global_position, so avatar bounce/drag/wobble
# propagate into the chain as momentum (the whip / reactive jiggle).

# physics point layout
const _PREV := 0   # reference to the previous point's array (null for root)
const _POS := 1    # Vector2 world position
const _ROT := 2    # float segment angle (radians)
const _MOM := 3    # float angular momentum (radians/sec)

# --- Parameters (pushed via configure()) ---
var segment_count := 6
var segment_length := 30.0
var stiffness := 20.0
var stiffness_decay := 0.0
var stiffness_decay_exponent := 1.0
var damping := 5.0
var max_angular_momentum := 25.0
var max_angle := PI
var comeback_speed := 0.4
var gravity := Vector2.ZERO
var curvature := 0.0
var curvature_exponent := 0.0
var subdivision := 3
var rest_direction_angle := 0.0     # radians, appendage's rest direction from the root
var root_follow_smoothness := 0.65
var auto_wag := false
var wag_speed := 0.15
var wag_amount := 0.4

var _points: Array = []
var _smoothed_root := Vector2.ZERO
var _cur_curvature := 0.0
var _wag_offset := 0.0   # current auto-wag sway applied to the root direction

func configure(p: Dictionary) -> void:
	segment_count = clampi(int(p.get("segment_count", segment_count)), 1, 24)
	segment_length = float(p.get("segment_length", segment_length))
	stiffness = float(p.get("stiffness", stiffness))
	stiffness_decay = float(p.get("stiffness_decay", stiffness_decay))
	stiffness_decay_exponent = float(p.get("stiffness_decay_exponent", stiffness_decay_exponent))
	damping = float(p.get("damping", damping))
	max_angular_momentum = float(p.get("max_angular_momentum", max_angular_momentum))
	max_angle = float(p.get("max_angle", max_angle))
	comeback_speed = float(p.get("comeback_speed", comeback_speed))
	gravity = p.get("gravity", gravity)
	curvature = float(p.get("curvature", curvature))
	curvature_exponent = float(p.get("curvature_exponent", curvature_exponent))
	subdivision = int(p.get("subdivision", subdivision))
	rest_direction_angle = float(p.get("rest_direction_angle", rest_direction_angle))
	root_follow_smoothness = float(p.get("root_follow_smoothness", root_follow_smoothness))
	auto_wag = bool(p.get("auto_wag", auto_wag))
	wag_speed = float(p.get("wag_speed", wag_speed))
	wag_amount = float(p.get("wag_amount", wag_amount))
	if _points.size() != segment_count + 1:
		reset()

# Snap the chain straight along the rest direction from the current root position.
# Call when enabling wiggle or after a teleport/snap so the chain doesn't fling.
func reset() -> void:
	_points = []
	var start := get_global_position()
	_smoothed_root = start
	var dir := Vector2.RIGHT.rotated(rest_direction_angle + global_rotation)
	for i in segment_count + 1:
		var pt := [null, start + dir * segment_length * float(i), dir.angle(), 0.0]
		if i != 0:
			pt[_PREV] = _points[-1]
		_points.append(pt)
	_update_line()

# Advance one frame. frame_tick drives auto-wag (a per-layer frame counter).
func tick(delta: float, frame_tick: int) -> void:
	if delta <= 0.0 or _points.size() < 2:
		return
	# Auto-wag is a clean sinusoidal sway of the root direction; the chain follows
	# it with spring lag, so the base moves smoothly and the tip whips.
	_wag_offset = (sin(float(frame_tick) * wag_speed) * wag_amount) if auto_wag else 0.0
	_cur_curvature = curvature
	for i in _points.size():
		if i == 0:
			_process_root(_points[i], delta)
		else:
			_process_point(_points[i], delta, i)
	_update_line()

func _process_root(point: Array, delta: float) -> void:
	var cur := get_global_position()
	# Frame-rate-independent exponential smoothing toward the live root position.
	var f := 1.0 - pow(1.0 - root_follow_smoothness, delta * 60.0)
	_smoothed_root = _smoothed_root.lerp(cur, f)
	point[_POS] = _smoothed_root
	point[_ROT] = rest_direction_angle + global_rotation + _wag_offset

func _process_point(point: Array, delta: float, index: int) -> void:
	var prev = point[_PREV]
	var dir: Vector2 = prev[_POS].direction_to(point[_POS])
	var rot: float = dir.angle()
	var ideal: float = prev[_ROT] + _cur_curvature * pow(float(index), curvature_exponent)
	ideal = fmod(ideal, TAU)
	var diff := _angle_diff(ideal, rot)
	var k := maxf(0.0, stiffness - pow(float(index), stiffness_decay_exponent) * stiffness_decay)
	var force := _signed_sqrt(diff) * k
	force += gravity.length() * cos(rot - gravity.angle() + TAU / 4.0)
	# Standard linear damping: smooth, symmetric response (no brake-on-reversal
	# stutter). The momentum cap then limits how fast a rotation travels down.
	point[_MOM] += (force - damping * point[_MOM]) * delta
	point[_MOM] = clampf(point[_MOM], -max_angular_momentum, max_angular_momentum)
	rot += point[_MOM] * delta
	# Hard angle limit relative to the parent, with a comeback spring.
	if absf(diff) > max_angle:
		rot += diff - absf(max_angle) * signf(diff)
		if signf(point[_MOM]) != signf(diff) or absf(point[_MOM]) < comeback_speed:
			point[_MOM] = comeback_speed * signf(diff)
	point[_ROT] = rot
	point[_POS] = prev[_POS] + Vector2(segment_length, 0).rotated(rot)

func _update_line() -> void:
	var pts := PackedVector2Array()
	for p in _points:
		pts.append(to_local(p[_POS]))
	points = _bezier(pts, subdivision)

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

func _angle_diff(a: float, b: float) -> float:
	var d := a - b
	if absf(d) > PI:
		d -= TAU * signf(d)
	return d

func _signed_sqrt(v: float) -> float:
	return sqrt(absf(v)) * signf(v)

# Quadratic-bezier smoothing of the polyline for a rounder ribbon (port of the
# remix's _bezier_interpolate). subdivision < 1 returns the raw points.
func _bezier(line: PackedVector2Array, sub: int) -> PackedVector2Array:
	if sub < 1 or line.size() < 3:
		return line
	var out := PackedVector2Array()
	for i in line.size() - 1:
		var a := line[i]
		var b := line[i + 1]
		var c: Vector2
		var subs: int
		var ci := i + 2
		if ci > line.size() - 1:
			var before := line[i - 1]
			var ang := _angle_diff((b - a).angle(), (a - before).angle())
			c = b + (b - a).rotated(ang)
			subs = sub / 2 + 1
		else:
			c = line[ci]
			subs = sub
		var ta := a.lerp(b, 0.5) if i != 0 else a
		var tc := b.lerp(c, 0.5)
		for o in subs:
			var tt := 1.0 / float(sub) * float(o)
			out.append(ta.lerp(b, tt).lerp(b.lerp(tc, tt), tt))
	return out
