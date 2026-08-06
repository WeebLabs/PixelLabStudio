extends RefCounted

const BlinkScheduler = preload("res://autoload/runtime/blink_scheduler.gd")
const MicrophoneMonitor = preload("res://autoload/runtime/microphone_monitor.gd")


func run(t) -> void:
	_test_blink_scheduler(t)
	_test_microphone_envelope(t)
	_test_microphone_state_transitions(t)
	_test_global_source_boundaries(t)


func _test_blink_scheduler(t) -> void:
	var scheduler := BlinkScheduler.new()
	scheduler.speed = 1.0
	scheduler.chance = 2
	scheduler.tick = 5.0
	t.assert_true(scheduler.advance_with_roll(0.0, 4), "a successful deterministic roll starts a blink")
	t.assert_equal(scheduler.tick, -12.0, "a blink retains the legacy twelve-frame duration")
	for _frame in range(11):
		scheduler.advance_with_roll(0.0, 1)
	t.assert_true(scheduler.active, "blink remains active before its final duration frame")
	scheduler.advance_with_roll(0.0, 1)
	t.assert_false(scheduler.active, "blink clears on the final duration frame")

	scheduler.chance = 0
	scheduler.speed = -5.0
	scheduler.tick = 1.0
	scheduler.advance_with_roll(0.0, 1)
	t.assert_true(scheduler.chance == 0, "invalid caller configuration is handled without mutating public preferences")
	t.assert_true(scheduler.active, "zero chance input is safely evaluated as one-in-one without division by zero")


func _test_microphone_envelope(t) -> void:
	t.assert_approx(MicrophoneMonitor.next_sensitivity(1.0, 0.0, 0.5, 0.25), 0.5, 0.00001, "microphone sensitivity decays at the legacy rate")
	t.assert_approx(MicrophoneMonitor.next_sensitivity(0.25, 0.75, 0.5, 0.01), 1.0, 0.00001, "levels over the volume threshold trigger full sensitivity")
	t.assert_approx(MicrophoneMonitor.next_sensitivity(1.0, 0.0, 0.5, 10.0), 0.0, 0.00001, "long frames clamp envelope interpolation instead of overshooting")


func _test_microphone_state_transitions(t) -> void:
	var monitor := MicrophoneMonitor.new()
	monitor.volume_limit = 0.5
	monitor.sense_limit = 0.2
	var transitions := {"started": 0, "stopped": 0}
	monitor.speaking_started.connect(func(): transitions["started"] += 1)
	monitor.speaking_stopped.connect(func(): transitions["stopped"] += 1)
	monitor.update_from_level(0.75, 0.016)
	t.assert_true(monitor.speaking, "microphone monitor enters speaking state above threshold")
	t.assert_equal(transitions["started"], 1, "speaking start emits exactly once")
	monitor.update_from_level(0.75, 0.016)
	t.assert_equal(transitions["started"], 1, "steady speaking state does not emit duplicate starts")
	monitor.muted = true
	monitor.update_from_level(0.75, 0.016)
	t.assert_false(monitor.speaking, "mute overrides an active microphone level")
	t.assert_equal(transitions["stopped"], 1, "mute emits one speaking stop transition")
	monitor.free()


func _test_global_source_boundaries(t) -> void:
	var source := FileAccess.get_file_as_string("res://autoload/global.gd")
	t.assert_true(source.contains("MicrophoneMonitorService"), "Global delegates microphone lifecycle to the runtime service")
	t.assert_true(source.contains("BlinkSchedulerService"), "Global delegates blink timing to the runtime service")
	t.assert_true(source.contains("signal notification_requested"), "Global exposes notifications as a lifecycle-safe signal")
	t.assert_false(source.contains("get_bus_effect_instance(1, 1)"), "audio lookup no longer depends on hard-coded bus/effect indexes")
	t.assert_false(source.contains("for child in get_children():\n\t\tchild.queue_free()"), "microphone reset no longer deletes unrelated Global children")
	t.assert_false(source.contains("updatePusherNode"), "Global no longer retains a stale-prone notification UI reference")
