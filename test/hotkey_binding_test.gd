extends SceneTree

const HotkeyBinding = preload("../autoload/hotkey_binding.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_canonical_modifier_order()
	_test_capture_uses_new_primary_key()
	_test_capture_waits_for_primary_key()
	_test_single_key_backward_compatibility()
	_test_modifier_matching_is_exact()
	_test_unrelated_gameplay_keys_are_ignored()
	_test_modifier_aliases_are_normalized()
	_test_invalid_bindings_do_not_activate()

	if _failures.is_empty():
		print("hotkey_binding_test: all tests passed")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_canonical_modifier_order() -> void:
	_assert_equal(
		HotkeyBinding.from_pressed(["2", "Shift", "Alt", "Ctrl"], ["2"]),
		"Ctrl+Alt+Shift+2",
		"canonicalizes modifiers in a stable order"
	)


func _test_capture_uses_new_primary_key() -> void:
	_assert_equal(
		HotkeyBinding.from_pressed(["W", "Shift", "2"], ["2"]),
		"Shift+2",
		"captures the newly pressed primary instead of an already-held game key"
	)


func _test_capture_waits_for_primary_key() -> void:
	_assert_equal(
		HotkeyBinding.from_pressed(["Shift"], ["Shift"]),
		"",
		"does not finish capture when only a modifier is pressed"
	)


func _test_single_key_backward_compatibility() -> void:
	_assert_true(
		HotkeyBinding.is_active("2", ["W", "2"]),
		"old single-key bindings still activate"
	)
	_assert_false(
		HotkeyBinding.is_active("2", ["Shift", "2"]),
		"a plain binding does not activate with an extra modifier"
	)


func _test_modifier_matching_is_exact() -> void:
	_assert_true(
		HotkeyBinding.is_active("Shift+2", ["Shift", "2"]),
		"a chord activates when its modifier and primary are held"
	)
	_assert_false(
		HotkeyBinding.is_active("Shift+2", ["2"]),
		"a chord does not activate without its modifier"
	)
	_assert_false(
		HotkeyBinding.is_active("Shift+2", ["Ctrl", "Shift", "2"]),
		"a chord does not activate with an additional modifier"
	)


func _test_unrelated_gameplay_keys_are_ignored() -> void:
	_assert_true(
		HotkeyBinding.is_active("Shift+2", ["W", "A", "Shift", "2"]),
		"unrelated held non-modifier keys do not block a chord"
	)


func _test_modifier_aliases_are_normalized() -> void:
	_assert_equal(
		HotkeyBinding.canonicalize("Shift+Control+Meta+2"),
		"Ctrl+Shift+Meta+2",
		"normalizes modifier aliases"
	)


func _test_invalid_bindings_do_not_activate() -> void:
	_assert_false(HotkeyBinding.is_active("", ["2"]), "empty bindings stay inactive")
	_assert_false(HotkeyBinding.is_active("null", ["2"]), "deleted bindings stay inactive")
	_assert_false(HotkeyBinding.is_active("Shift", ["Shift"]), "modifier-only bindings stay inactive")
	_assert_false(HotkeyBinding.is_active("Q+E", ["Q", "E"]), "multi-primary chords stay inactive")


func _assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, expected, actual])


func _assert_true(actual: bool, message: String) -> void:
	if not actual:
		_failures.append("%s: expected true" % message)


func _assert_false(actual: bool, message: String) -> void:
	if actual:
		_failures.append("%s: expected false" % message)
