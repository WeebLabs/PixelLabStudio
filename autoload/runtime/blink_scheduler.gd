class_name BlinkScheduler
extends RefCounted

## When the avatar blinks. The timing is counted in 60 fps frames rather than in
## real frames, so the blink rate is the same whatever the frame rate: rolling
## once per frame meant 240 fps blinked four times as often as 60 fps for the
## same settings (measured: 1 blink in ten seconds at 60, 3 at 240).
##
## `tick` stays in the same units it always was, and `advance` takes how many
## 60 fps frames the last real frame was worth, so a caller stepping at 60 fps
## behaves exactly as before.

const BLINK_FRAMES := 12.0

var speed: float = 1.0
var chance: int = 200
var active: bool = false
var tick: float = 0.0
var random := RandomNumberGenerator.new()


func advance(step: float = 1.0) -> bool:
	return advance_with_roll(random.randf_range(-1.0, 1.0), random.randf(), step)


# `open_roll` decides whether a closed blink re-arms; `blink_roll` is the chance
# of starting one, in [0, 1). The chance is per 60 fps frame, so a step worth two
# of those frames is twice as likely to blink, and one worth half is half.
func advance_with_roll(open_roll: float, blink_roll: float, step: float = 1.0) -> bool:
	var safe_chance := maxi(chance, 1)
	var safe_step := maxf(step, 0.0)
	var floor_frames := 2.0 * float(safe_chance) * maxf(speed, 0.0)
	tick += safe_step
	if absf(tick) < safe_step * 0.5 or is_equal_approx(tick, 0.0):
		active = false
		if open_roll > 0.5:
			tick = floor_frames + 1.0
	if tick > floor_frames and blink_roll < safe_step / float(safe_chance):
		active = true
		tick = -BLINK_FRAMES
	return active
