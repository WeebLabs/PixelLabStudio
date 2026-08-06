extends SceneTree

const SUITES := [
	preload("res://tests/unit/test_project_baseline.gd"),
	preload("res://tests/unit/test_pure_behavior.gd"),
	preload("res://tests/unit/test_import_detection.gd"),
	preload("res://tests/unit/test_persistence.gd"),
	preload("res://tests/unit/test_runtime_services.gd"),
	preload("res://tests/unit/test_main_controllers.gd"),
]

var assertions := 0
var failures := 0

func _initialize() -> void:
	print("[TEST] Godot ", Engine.get_version_info()["string"])
	for suite_resource in SUITES:
		var suite_script: Script = suite_resource as Script
		var suite: RefCounted = suite_script.new()
		var suite_name: String = String(suite_script.resource_path).get_file().get_basename()
		var failures_before := failures
		suite.run(self)
		if failures == failures_before:
			print("[PASS] ", suite_name)
		else:
			print("[FAIL] ", suite_name)

	print("[TEST] %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func assert_true(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		_fail(message)

func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)

func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	assertions += 1
	if actual != expected:
		_fail("%s (expected %s, got %s)" % [message, str(expected), str(actual)])

func assert_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	assertions += 1
	if absf(actual - expected) > tolerance:
		_fail("%s (expected %s ± %s, got %s)" % [message, expected, tolerance, actual])

func assert_not_null(value: Variant, message: String) -> void:
	assertions += 1
	if value == null:
		_fail(message)

func _fail(message: String) -> void:
	failures += 1
	printerr("  Assertion failed: ", message)
