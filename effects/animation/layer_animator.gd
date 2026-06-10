extends RefCounted
class_name LayerAnimator

# Evaluates a layer's animClips each frame into a composite ROTATION (radians)
# and TRANSLATION (pixels) offset. The owning spriteObject applies:
#   rot   -> DragOrigin.rotation  (outermost, so it also swings the wiggle mesh
#                                   + chain anchor — twitch drives the physics)
#   trans -> WobbleOrigin.position (alongside the eye-track offset)
#
# Two shapes:
#   oscillate — continuous sine. Translation oscillate carries independent X/Y
#               (ampX/freqX, ampY/freqY) so it reproduces the legacy "wobble"
#               byte-for-byte (sin(tick*freq)*amp). Rotation oscillate is a sway.
#   twitch    — one-shot ease out-and-back (half-sine), fired by a trigger.
#
# Triggers: always (idle; oscillate runs continuously, twitch loops), random
# (blink-style per-frame probability), key (BackgroundInputCapture), manual
# (Test button / scripts). Oscillate ignores the trigger (it always runs); the
# UI only offers "always" for it.

var rot := 0.0             # output rotation, radians
var trans := Vector2.ZERO  # output translation, pixels

var _rng := RandomNumberGenerator.new()
var _rt: Array = []        # per-clip runtime state, parallel to the clips array
var _seeded := false

# Keep the runtime-state array the same length as the clips array. Index-based:
# a reorder may restart an in-flight twitch, which is visually negligible.
func _ensure(n: int) -> void:
	if not _seeded:
		_rng.randomize()
		_seeded = true
	while _rt.size() < n:
		_rt.append({"playing": false, "t": 0.0})
	while _rt.size() > n:
		_rt.pop_back()

# Advance every clip one frame. `tick` is the layer's frame counter (sine phase).
func evaluate(clips: Array, tick: int, delta: float) -> void:
	rot = 0.0
	trans = Vector2.ZERO
	_ensure(clips.size())
	for i in clips.size():
		var c: Dictionary = clips[i]
		var st: Dictionary = _rt[i]
		if String(c.get("shape", "twitch")) == "oscillate":
			_eval_oscillate(c, String(c.get("channel", "rotation")), tick)
		else:
			_eval_twitch(c, String(c.get("channel", "rotation")), st, delta)

func _eval_oscillate(c: Dictionary, channel: String, tick: int) -> void:
	if channel == "translation":
		trans += Vector2(
			sin(tick * float(c.get("freqX", 0.0))) * float(c.get("ampX", 0.0)),
			sin(tick * float(c.get("freqY", 0.0))) * float(c.get("ampY", 0.0)))
	else:
		rot += deg_to_rad(sin(tick * float(c.get("speed", 0.0))) * float(c.get("amount", 0.0)))

func _eval_twitch(c: Dictionary, channel: String, st: Dictionary, delta: float) -> void:
	# Auto-fire for self-driven triggers; key/manual are fired externally.
	if not st.get("playing", false):
		var trigger := String(c.get("trigger", "manual"))
		if trigger == "always":
			_start(st)
		elif trigger == "random":
			var chance := maxi(2, int(c.get("chance", 200)))
			if _rng.randi() % chance == 0:
				_start(st)
	if not st.get("playing", false):
		return
	var dur := clampf(1.0 / maxf(0.05, float(c.get("speed", 1.0))), 0.08, 6.0)
	st["t"] = float(st["t"]) + delta
	var ph := clampf(float(st["t"]) / dur, 0.0, 1.0)
	if ph >= 1.0:
		st["playing"] = false
		st["t"] = 0.0
	var env := sin(ph * PI)   # 0 -> 1 -> 0, smooth out-and-back
	var amount := float(c.get("amount", 0.0))
	if channel == "translation":
		var dir := Vector2(float(c.get("dirX", 0.0)), float(c.get("dirY", -1.0)))
		trans += dir * (env * amount)
	else:
		rot += deg_to_rad(env * amount)

func _start(st: Dictionary) -> void:
	st["playing"] = true
	st["t"] = 0.0

# --- External triggers -------------------------------------------------------

# Fire a single clip's one-shot (Test button / scripts).
func fire_clip(clips: Array, i: int) -> void:
	_ensure(clips.size())
	if i >= 0 and i < _rt.size():
		_start(_rt[i])

# Fire every key-triggered clip bound to `keystr`.
func fire_key(clips: Array, keystr: String) -> void:
	_ensure(clips.size())
	for i in clips.size():
		var c: Dictionary = clips[i]
		if String(c.get("trigger", "")) == "key" and String(c.get("key", "")) == keystr:
			_start(_rt[i])
