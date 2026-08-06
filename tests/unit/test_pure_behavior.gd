extends RefCounted

const Animator = preload("res://effects/animation/layer_animator.gd")
const BlendModes = preload("res://effects/blend/blend_mode.gd")

func run(t) -> void:
	_test_animation_curves(t)
	_test_oscillation(t)
	_test_blend_registry(t)
	_test_settings_source_contract(t)

func _test_animation_curves(t) -> void:
	t.assert_approx(Animator.envelope("smooth", 0.0), 0.0, 0.00001, "smooth curve starts at rest")
	t.assert_approx(Animator.envelope("smooth", 0.5), 1.0, 0.00001, "smooth curve reaches its peak")
	t.assert_approx(Animator.envelope("smooth", 1.0), 0.0, 0.00001, "smooth curve returns to rest")
	t.assert_approx(Animator.envelope("pulse", 0.5), 1.0, 0.00001, "pulse curve peaks halfway")
	t.assert_approx(Animator.envelope("unknown", 0.5), 1.0, 0.00001, "unknown curves retain the legacy smooth fallback")

func _test_oscillation(t) -> void:
	var animator = Animator.new()
	var clips := [{
		"shape": "oscillate",
		"channel": "translation",
		"freqX": PI * 0.5,
		"freqY": 0.0,
		"ampX": 10.0,
		"ampY": 0.0,
	}]
	animator.evaluate(clips, 1, 1.0 / 60.0)
	t.assert_approx(animator.trans.x, 10.0, 0.0001, "legacy oscillation reaches the expected X amplitude")
	t.assert_approx(animator.trans.y, 0.0, 0.0001, "legacy oscillation preserves an inactive Y axis")

func _test_blend_registry(t) -> void:
	t.assert_equal(BlendModes.count(), 14, "persisted blend mode registry remains append-only")
	t.assert_equal(BlendModes.display_name(BlendModes.Mode.NORMAL), "Normal", "normal blend mode keeps persisted index zero")
	t.assert_equal(BlendModes.display_name(999), "Normal", "invalid blend modes display as Normal")
	t.assert_true(BlendModes.is_native(BlendModes.Mode.ADD), "Add uses native compositing")
	t.assert_true(BlendModes.needs_backbuffer(BlendModes.Mode.MULTIPLY), "Multiply retains its screen-read requirement")

func _test_settings_source_contract(t) -> void:
	var source := FileAccess.get_file_as_string("res://autoload/saving.gd")
	for key in ["volume", "sense", "maxFPS", "costumeKeys", "ndiEnabled", "ndiCropRect", "recordingFormat", "recordingFPS"]:
		t.assert_true(source.contains('"%s"' % key), "settings source declares %s" % key)
	t.assert_true(source.contains('["1","2","3","4","5","6","7","8","9","0"]'), "ten costume binding slots remain available")
