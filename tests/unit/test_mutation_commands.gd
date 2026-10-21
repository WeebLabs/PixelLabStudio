extends RefCounted

# Phase 14: the command layer and the input decoder are pure policy, so both are
# exercised here against a recording history sink and plain dictionaries — no
# scene, no autoloads, no engine input.

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")
const InputCommands = preload("res://autoload/input/input_commands.gd")


# Records the transaction boundary a command opens so the tests can assert that
# each command captures history exactly once, and discards it when nothing changed.
class HistoryRecorder extends RefCounted:
	var entries: Array = []
	var open: Array = []
	var depth := 0
	var aborted := 0
	var active_gesture := ""

	func begin(gesture: String = "") -> void:
		var pushed := false
		if depth == 0:
			if gesture.is_empty():
				pushed = true
				active_gesture = ""
			elif active_gesture != gesture:
				pushed = true
				active_gesture = gesture
		if pushed:
			entries.append(gesture)
		open.push_back(pushed)
		depth += 1

	func commit() -> void:
		if depth == 0:
			return
		depth -= 1
		open.pop_back()

	func abort() -> void:
		if depth == 0:
			return
		depth -= 1
		if open.pop_back():
			entries.pop_back()
			active_gesture = ""
			aborted += 1

	func end_gesture(gesture: String = "") -> void:
		if gesture.is_empty() or active_gesture == gesture:
			active_gesture = ""


# Stand-in layer carrying the persistent properties the commands write.
class FakeLayer extends RefCounted:
	var id := 7
	var opacity := 1.0
	var blendMode := 0
	var staticElement := false
	var costumeLayers := [1, 1, 1, 1, 1, 1, 1, 1, 1, 1]
	var animClips: Array = []


func run(t) -> void:
	_test_discrete_commands(t)
	_test_continuous_gestures(t)
	_test_structured_field_commands(t)
	_test_structural_abort(t)
	_test_property_validation(t)
	_test_foreground_decoding(t)
	_test_background_decoding(t)
	_test_device_decoding(t)
	MutationCommands.set_history_sink(null)


func _fresh(t) -> Array:
	var history := HistoryRecorder.new()
	MutationCommands.set_history_sink(history)
	return [history, FakeLayer.new()]


func _test_discrete_commands(t) -> void:
	var fixture := _fresh(t)
	var history: HistoryRecorder = fixture[0]
	var layer: FakeLayer = fixture[1]

	t.assert_true(MutationCommands.set_layer_property(layer, "blendMode", 3), "a discrete command applies its write")
	t.assert_equal(layer.blendMode, 3, "the command wrote the requested value")
	t.assert_equal(history.entries.size(), 1, "a discrete command captures history exactly once")

	t.assert_false(MutationCommands.set_layer_property(layer, "blendMode", 3), "re-writing the current value is not a change")
	t.assert_equal(history.entries.size(), 1, "an unchanged write leaves no dead history entry")

	t.assert_false(MutationCommands.set_layer_property(null, "blendMode", 4), "a command with no layer does nothing")
	t.assert_equal(history.entries.size(), 1, "a command with no layer captures no history")

	t.assert_true(MutationCommands.set_layer_property(layer, "staticElement", true), "boolean properties round-trip through the command layer")
	t.assert_equal(history.entries.size(), 2, "each discrete command is its own history entry")


func _test_continuous_gestures(t) -> void:
	var fixture := _fresh(t)
	var history: HistoryRecorder = fixture[0]
	var layer: FakeLayer = fixture[1]

	for step in [0.9, 0.8, 0.7, 0.6]:
		MutationCommands.drag_layer_property(layer, "opacity", step, "slider")
	t.assert_equal(history.entries.size(), 1, "a continuous drag produces one logical history entry")
	t.assert_approx(layer.opacity, 0.6, 0.0001, "every step of the drag reaches the layer")

	MutationCommands.end_gesture()
	MutationCommands.drag_layer_property(layer, "opacity", 0.5, "slider")
	t.assert_equal(history.entries.size(), 2, "the next drag after the gesture ends starts a new entry")

	# Switching controls mid-drag must not be swallowed by the first gesture.
	MutationCommands.drag_layer_property(layer, "blendMode", 2, "slider")
	t.assert_equal(history.entries.size(), 3, "a different property during the same drag captures its own entry")

	# A named end must not cut short an unrelated gesture still in flight.
	var before := history.active_gesture
	MutationCommands.end_gesture("move-layer")
	t.assert_equal(history.active_gesture, before, "ending a named gesture leaves an unrelated gesture active")

	var second := FakeLayer.new()
	second.id = 9
	MutationCommands.drag_layer_property(second, "blendMode", 2, "slider")
	t.assert_equal(history.entries.size(), 4, "the same control on a different layer is a separate entry")


func _test_structured_field_commands(t) -> void:
	var fixture := _fresh(t)
	var history: HistoryRecorder = fixture[0]
	var layer: FakeLayer = fixture[1]
	layer.animClips = [{"name": "Twitch", "amp": 10.0}]

	t.assert_true(MutationCommands.set_layer_field(layer, "animClips", 0, "name", "Ear"), "a structured-field command applies its write")
	t.assert_equal(layer.animClips[0]["name"], "Ear", "the clip entry carries the new value")
	t.assert_equal(history.entries.size(), 1, "a structured-field edit captures history once")

	t.assert_false(MutationCommands.set_layer_field(layer, "animClips", 0, "name", "Ear"), "an unchanged clip edit is not a change")
	t.assert_equal(history.entries.size(), 1, "an unchanged clip edit leaves no dead entry")

	t.assert_false(MutationCommands.set_layer_field(layer, "animClips", 4, "name", "Ear"), "an out-of-range clip index is rejected")

	MutationCommands.end_gesture()
	for amp in [11.0, 12.0, 13.0]:
		MutationCommands.set_layer_field(layer, "animClips", 0, "amp", amp, "slider")
	t.assert_equal(history.entries.size(), 2, "a continuous clip-field drag collapses into one entry")


func _test_structural_abort(t) -> void:
	var fixture := _fresh(t)
	var history: HistoryRecorder = fixture[0]

	t.assert_true(MutationCommands.structural(func(): return true), "a structural command that changed something keeps its entry")
	t.assert_equal(history.entries.size(), 1, "a structural command captures history once")

	t.assert_false(MutationCommands.structural(func(): return false), "a structural command reports a no-op")
	t.assert_equal(history.entries.size(), 1, "a no-op structural command discards its history entry")
	t.assert_equal(history.aborted, 1, "the discarded entry was explicitly aborted")
	t.assert_equal(history.depth, 0, "every transaction is closed")

	# A command nested inside another joins the outer entry rather than adding one.
	MutationCommands.structural(func():
		MutationCommands.structural(func(): return true)
		return true)
	t.assert_equal(history.entries.size(), 2, "a composite command still yields one history entry")
	t.assert_equal(history.depth, 0, "nested transactions unwind completely")


func _test_property_validation(t) -> void:
	var properties := MutationCommands.persistent_properties()
	for expected in ["opacity", "blendMode", "costumeLayers", "animClips", "position", "offset", "parentId", "wigglePath"]:
		t.assert_true(properties.has(expected), "the command layer recognizes '%s' as persistent" % expected)
	t.assert_false(MutationCommands.is_persistent_property("userHidden"), "session-only visibility is not a persistent command target")
	t.assert_false(MutationCommands.is_persistent_property("heldTicks"), "runtime scratch state is not a persistent command target")


func _test_foreground_decoding(t) -> void:
	var all_guards := {
		"has_selection": true, "edit_mode": true, "control_held": true,
		"text_focus": false, "file_dialog_open": false,
	}
	t.assert_equal(
		InputCommands.decode_foreground({"zUp": true}, all_guards), ["layer_depth_up"],
		"a depth key decodes to one depth command",
	)
	t.assert_equal(
		InputCommands.decode_foreground({"zUp": true}, {"has_selection": false}), [],
		"depth keys need a selected layer",
	)
	t.assert_equal(
		InputCommands.decode_foreground({"undo": true}, {"control_held": false}), [],
		"undo needs the control modifier",
	)
	t.assert_equal(
		InputCommands.decode_foreground({"undo": true, "redo": true}, all_guards), ["undo", "redo"],
		"multiple commands decode in a deterministic order",
	)

	var typing := all_guards.duplicate()
	typing["text_focus"] = true
	t.assert_equal(
		InputCommands.decode_foreground({"zUp": true, "undo": true, "unlink": true}, typing), [],
		"a focused text field suppresses every key command",
	)

	var dialog := all_guards.duplicate()
	dialog["file_dialog_open"] = true
	t.assert_equal(
		InputCommands.decode_foreground({"undo": true, "refresh": true}, dialog), [],
		"an open file dialog suppresses the commands that were guarded by it",
	)
	t.assert_equal(
		InputCommands.decode_foreground({"zUp": true}, dialog), ["layer_depth_up"],
		"a file dialog does not suppress commands that were never guarded by it",
	)
	t.assert_equal(
		InputCommands.decode_foreground({"reparent": true}, {"has_selection": true, "edit_mode": false}), [],
		"reparent mode is edit-page only",
	)


func _test_background_decoding(t) -> void:
	var guards := {
		"costume_keys": ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
		"awaiting_costume_index": -1,
	}
	var costume := InputCommands.decode_background(["3"], guards)
	t.assert_equal(costume.size(), 2, "a bound costume key changes costume and still offers an animation trigger")
	t.assert_equal(costume[0], {"command": "change_costume", "costume": 3}, "the costume index follows the bound key position")
	t.assert_equal(costume[1]["command"], "trigger_animation_key", "unbound behavior still reaches animation clips")

	t.assert_equal(
		InputCommands.decode_background([], guards), [{"command": "capture_emptied"}],
		"an empty capture reports the release rather than a command",
	)

	var binding := guards.duplicate()
	binding["awaiting_animation_bind"] = true
	t.assert_equal(
		InputCommands.decode_background(["3"], binding),
		[{"command": "bind_animation_key", "key": "3"}],
		"an armed animation bind swallows the key instead of triggering",
	)

	var costume_bind := guards.duplicate()
	costume_bind["awaiting_costume_index"] = 2
	var bound := InputCommands.decode_background(["K"], costume_bind)
	t.assert_equal(bound[0], {"command": "bind_costume_key", "index": 2, "key": "K"}, "costume binding captures the pressed key")
	for command in bound:
		t.assert_false(command["command"] == "trigger_animation_key", "animation clips do not fire while binding a costume key")

	var mouse_bind := costume_bind.duplicate()
	mouse_bind["settings_has_mouse"] = false
	t.assert_equal(
		InputCommands.decode_background(["Keycode1"], mouse_bind),
		[{"command": "capture_rejected"}],
		"mouse button one is refused as a costume key unless mouse capture is enabled",
	)

	var typing := guards.duplicate()
	typing["text_focus"] = true
	for command in InputCommands.decode_background(["7"], typing):
		t.assert_false(command["command"] == "trigger_animation_key", "typing suppresses animation key triggers")

	var modal := guards.duplicate()
	modal["file_dialog_open"] = true
	t.assert_equal(InputCommands.decode_background(["3"], modal), [], "an open file dialog swallows background keys")
	var z_editor := guards.duplicate()
	z_editor["z_editor_active"] = true
	t.assert_equal(InputCommands.decode_background(["3"], z_editor), [], "the z-index editor swallows background keys")

	t.assert_equal(
		InputCommands.decode_visibility_capture([], {}), {"command": "visibility_capture_armed"},
		"an empty visibility capture arms the binding",
	)
	t.assert_equal(
		InputCommands.decode_visibility_capture(["J"], {}),
		{"command": "visibility_keys_captured", "keys": ["J"]},
		"a visibility capture reports the pressed keys",
	)


func _test_device_decoding(t) -> void:
	t.assert_equal(
		InputCommands.decode_device_costume("4"), {"command": "change_costume", "costume": 4},
		"a device costume id decodes to a costume change",
	)
	t.assert_equal(InputCommands.decode_device_costume("0")["command"], "ignore", "costume ids below one are ignored")
	t.assert_equal(InputCommands.decode_device_costume("11")["command"], "ignore", "costume ids past the last costume are ignored")
	t.assert_equal(InputCommands.decode_device_costume("mute")["command"], "ignore", "a non-numeric device key is ignored")
