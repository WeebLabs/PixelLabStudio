extends Control
class_name AnimationCurveGraph

# A small preview that plots an animation clip's curve (value vs normalized time)
# and a dot that rides the curve while the clip plays — fired by the Test button
# or by an organic trigger (random / key / always). Polls the selected layer's
# live phase each frame via spriteObject.getAnimSample(), so the dot tracks the
# real animation. The curve itself comes from LayerAnimator.envelope(), the same
# function the runtime uses, so the preview matches exactly. For oscillate clips
# the curve is one sine period and the dot cycles continuously.

const _BG := Color(0.1, 0.1, 0.12)
const _FRAME := Color(0.28, 0.28, 0.33)
const _BASELINE := Color(0.4, 0.4, 0.46)
const _LINE := Color(1.0, 0.7, 0.8)
const _DOT := Color(1.0, 1.0, 1.0)
const _SAMPLES := 56

var curve := "smooth"
var shape := "twitch"
var clip_index := -1

var _ph := 0.0
var _active := false

func _init() -> void:
	custom_minimum_size = Vector2(0, 62)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(curve_name: String, shape_name: String, index: int) -> void:
	curve = curve_name
	shape = shape_name
	clip_index = index
	queue_redraw()

func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var s := {"active": false, "ph": 0.0}
	if Global.heldSprite != null and clip_index >= 0:
		s = Global.heldSprite.getAnimSample(clip_index)
	var act := bool(s.get("active", false))
	var ph := float(s.get("ph", 0.0))
	if act != _active or (act and absf(ph - _ph) > 0.001):
		_active = act
		_ph = ph
		queue_redraw()

# Curve value at normalized x∈[0,1].
func _value(x: float) -> float:
	if shape == "oscillate":
		return sin(x * TAU)
	return LayerAnimator.envelope(curve, x)

# Map a curve value to a pixel y (higher value = higher on screen).
func _y(v: float) -> float:
	var vmin := -1.15
	var vmax := 1.15
	if shape != "oscillate":
		vmin = -0.8   # room for the spring's bounce below rest
		vmax = 1.3    # room for overshoot above the target amplitude
	var pad := 6.0
	var t := (v - vmin) / (vmax - vmin)
	return lerpf(size.y - pad, pad, clampf(t, 0.0, 1.0))

func _draw() -> void:
	var w := size.x
	draw_rect(Rect2(Vector2.ZERO, size), _BG)
	draw_rect(Rect2(Vector2.ZERO, size), _FRAME, false, 1.0)
	# rest (value 0) baseline
	var y0 := _y(0.0)
	draw_line(Vector2(0, y0), Vector2(w, y0), _BASELINE, 1.0)
	# the curve
	var pts := PackedVector2Array()
	for i in _SAMPLES + 1:
		var x := float(i) / float(_SAMPLES)
		pts.append(Vector2(x * w, _y(_value(x))))
	draw_polyline(pts, _LINE, 1.5, true)
	# progress dot
	if _active:
		var p := Vector2(_ph * w, _y(_value(_ph)))
		draw_line(Vector2(p.x, 0), Vector2(p.x, size.y), Color(_LINE, 0.25), 1.0)
		draw_circle(p, 3.5, _DOT)
