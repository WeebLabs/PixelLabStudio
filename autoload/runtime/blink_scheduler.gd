class_name BlinkScheduler
extends RefCounted

var speed: float = 1.0
var chance: int = 200
var active: bool = false
var tick: float = 0.0
var random := RandomNumberGenerator.new()


func advance() -> bool:
	return advance_with_roll(random.randf_range(-1.0, 1.0), random.randi())


func advance_with_roll(random_float: float, random_integer: int) -> bool:
	var safe_chance := maxi(chance, 1)
	var floor_frames := 2.0 * float(safe_chance) * maxf(speed, 0.0)
	tick += 1.0
	if is_equal_approx(tick, 0.0):
		active = false
		if random_float > 0.5:
			tick = floor_frames + 1.0
	if tick > floor_frames and posmod(random_integer, safe_chance) == 0:
		active = true
		tick = -12.0
	return active
