extends RefCounted

const SelectionState = preload("res://autoload/domain/selection_state.gd")


func run(t) -> void:
	_test_selection_state(t)
	_test_global_boundary_contract(t)


func _test_selection_state(t) -> void:
	var state := SelectionState.new()
	var first := RefCounted.new()
	var second := RefCounted.new()
	var hit_one := RefCounted.new()
	var hit_two := RefCounted.new()
	var resolved := {hit_one: first, hit_two: second}
	var changes: Array = []
	state.changed.connect(func(current, previous): changes.append([current, previous]))

	state.select(first)
	t.assert_true(state.current == first, "selection state stores an explicit selection")
	t.assert_equal(changes.size(), 1, "selection state reports a changed selection once")
	state.select(first)
	t.assert_equal(changes.size(), 1, "selecting the current layer does not emit a duplicate change")

	var resolve := func(hit): return resolved.get(hit)
	state.clear()
	state.choose_from_hits([hit_one, hit_two], resolve)
	t.assert_true(state.current == first, "a hit stack selects its topmost layer")
	state.choose_from_hits([hit_one, hit_two], resolve)
	t.assert_true(state.current == second, "a repeated hit stack cycles to its next layer")
	state.choose_from_hits([hit_one, hit_two], resolve)
	t.assert_true(state.current == first, "hit-stack cycling wraps deterministically")

	# Cycling is anchored to the held layer, not to an index into the previous
	# click's candidate array, because a moving avatar hands back a different
	# array almost every click.
	state.choose_from_hits([hit_two], resolve)
	t.assert_true(state.current == second, "a stack the held layer has dropped out of selects its top")
	state.choose_from_hits([hit_one, hit_two], resolve)
	t.assert_true(state.current == first, "cycling continues after the candidate list changes")
	state.select(second)
	state.choose_from_hits([hit_one, hit_two], resolve)
	t.assert_true(state.current == first, "cycling steps on from whatever layer is selected")

	state.choose_from_hits([], resolve)
	t.assert_true(state.current == null, "an empty canvas hit clears selection")


func _test_global_boundary_contract(t) -> void:
	var source_root := _source_root()
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	t.assert_true(global_source.contains("SelectionStateService"), "Global delegates selection storage and hit cycling")
	t.assert_true(global_source.contains("func sprite_from_hit_area"), "the required Area2D traversal has one public boundary")
	t.assert_true(global_source.contains("func attach_sprite_edit"), "edit sidebar registration is explicit")
	t.assert_true(global_source.contains("func attach_sprite_list"), "layer sidebar registration is explicit")
	t.assert_true(global_source.contains("func is_text_entry_active"), "input focus state has a public read boundary")
	t.assert_true(global_source.contains("func begin_eye_track_pick"), "eye-target capture starts through a state boundary")
	t.assert_true(global_source.contains("func notify_user"), "notifications have a purpose-named public boundary")

	var scan_paths := [
		"main_scenes/main.gd",
		"ui_scenes/mouse/mouse_cursor.gd",
		"ui_scenes/spriteEditMenu/sprite_viewer.gd",
		"ui_scenes/spriteList/sprite_list_object.gd",
		"ui_scenes/spriteList/viewer.gd",
	]
	for relative_path in scan_paths:
		var source := FileAccess.get_file_as_string(source_root.path_join(relative_path))
		t.assert_false(source.contains("Global._"), "%s does not call Global's private implementation" % relative_path)
		t.assert_false(source.contains("Global.heldSprite = null"), "%s cannot clear selection storage directly" % relative_path)
		t.assert_false(source.contains("Global.heldSprite = sprite"), "%s cannot replace selection storage directly" % relative_path)

	var cursor_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/mouse/mouse_cursor.gd"))
	t.assert_false(cursor_source.contains("get_parent().get_parent().get_parent()"), "mouse hit handling uses the canonical sprite-root resolver")

	var duplicate_traversal: Array[String] = []
	var group_enumeration: Array[String] = []
	var legacy_notifications: Array[String] = []
	for root in ["autoload", "main_scenes", "ndi", "ui_scenes"]:
		for path in _collect_scripts(source_root.path_join(root)):
			var source := FileAccess.get_file_as_string(path)
			if source.contains("get_parent().get_parent().get_parent()"):
				duplicate_traversal.append(path)
			if source.contains("get_nodes_in_group(\"saved\")"):
				group_enumeration.append(path)
			# Match the call, not one spelling of the receiver: the controllers
			# reach Global through an injected reference, so a check for the
			# literal "Global.pushUpdate(" passed while thirteen call sites used
			# "_global.pushUpdate(".
			if source.contains(".pushUpdate("):
				legacy_notifications.append(path)
	t.assert_true(duplicate_traversal.is_empty(), "production code has no duplicated three-parent sprite traversal: " + str(duplicate_traversal))
	t.assert_true(group_enumeration.is_empty(), "production code enumerates layers through the sprite registry: " + str(group_enumeration))
	t.assert_true(legacy_notifications.is_empty(), "production code emits notifications through notify_user(): " + str(legacy_notifications))


func _collect_scripts(root: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if directory.current_is_dir():
				result.append_array(_collect_scripts(path))
			elif entry.get_extension().to_lower() == "gd":
				result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
