extends RefCounted

## Frame-rate independence for the avatar's motion, calibrated so nothing looks
## or feels different at 60 fps.
##
## Every motion value in this app was tuned against a 60 fps frame step: the
## bounce integrated a hardcoded 0.0166 per frame, drag lerped by `1/dragSpeed`
## per frame, rotational drag turned each frame's displacement into an angle, and
## the oscillating clips took their sine phase from a frame counter. All of that
## is correct only while frames arrive exactly 60 times a second. When they do
## not, the motion speeds up, slows down and jitters, and rotational drag shows it
## worst because it reads a displacement and renders it as an angle.
##
## So: keep the tuning, change the clock.
##
##   frames(delta)      how many 60 fps frames this delta is worth, so a
##                      per-frame displacement or increment scales by it
##   smooth(w, delta)   a per-frame lerp weight tuned at 60 fps, corrected for
##                      this delta, so the same fraction is covered per SECOND
##
## At delta = 1/60 both are identities: frames() is 1 and smooth(w) is w.

const REFERENCE_FPS := 60.0

## A hitch should slow the avatar down, not teleport it. Anything longer than
## this is treated as this long, which costs a little accuracy on a stall and
## avoids a spring exploding after one.
const MAX_STEP := 1.0 / 15.0


static func frames(delta: float) -> float:
	return clampf(delta, 0.0, MAX_STEP) * REFERENCE_FPS


# The exponential-decay correction: covering fraction `weight` per 60 fps frame
# means covering 1 - (1 - weight)^frames over this delta.
static func smooth(weight: float, delta: float) -> float:
	if weight >= 1.0:
		return 1.0
	if weight <= 0.0:
		return 0.0
	return clampf(1.0 - pow(1.0 - weight, frames(delta)), 0.0, 1.0)


# Per-frame displacement, read as displacement per 60 fps frame. Rotational drag
# and squash are tuned against "how far it moved this frame", which is a speed
# wearing the wrong units.
static func per_frame(distance: float, delta: float) -> float:
	var step := frames(delta)
	return distance / step if step > 0.0 else 0.0
