extends Node

const MAIN_SCENE := preload("res://main_scenes/main.tscn")
const AvatarSaveControllerScript = preload("res://main_scenes/controllers/save_controller.gd")
const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")
const LayerContextMenu = preload("res://ui_scenes/spriteList/layer_context_menu.gd")
const SpriteRestPose = preload("res://ui_scenes/selectedSprite/sprite_rest_pose.gd")
const SpriteListObject = preload("res://ui_scenes/spriteList/sprite_list_object.gd")

const REGRESSION_FIXTURE := "res://tests/fixtures/avatar_scene_regression.json"
const INVALID_FIXTURE := "res://tests/fixtures/avatar_duplicate_id.json"
const EXPECTED_SPRITES := 12
const BASE_ID := 4294967295
const COSTUME_ONE_ID := 4294967294
const COSTUME_TWO_ID := 4294967293
const NESTED_ID := 4294967292

var assertions := 0
var failures := 0
var _main: Node2D = null
var _materialized_fixture_path := ""


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[AVATAR SCENE] Godot ", Engine.get_version_info()["string"])
	assert_true(Saving.is_isolated_session(), "integration runner uses isolated persistence and device state")

	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(_main.saveLoaded, "production main scene completes startup")
	assert_not_null(_main.avatar_controller, "production main scene owns the avatar lifecycle controller")
	assert_not_null(_main.import_controller, "production main scene owns the import lifecycle controller")
	await _test_component_scenes()

	_materialized_fixture_path = _materialize_regression_fixture()
	assert_false(_materialized_fixture_path.is_empty(), "regression fixture is materialized with an absolute image path")
	if _materialized_fixture_path.is_empty():
		get_tree().quit(1)
		return
	await _main.load_avatar_file(_materialized_fixture_path)
	await get_tree().process_frame
	_test_loaded_avatar("fixture load")
	await _test_sidebar_selection_state()
	await _test_edit_commands()
	await _test_idle_motion()
	await _test_motion_is_time_based()
	await _test_click_cycling()
	await _test_layer_list_deletion()
	await _test_layer_deletion_children()
	await _test_layer_rename()
	await _test_layer_context_menu()
	await _test_layer_replace_target()
	await _test_replace_review_names()
	await _test_duplicate_placement()
	await _test_multi_selection()
	await _test_mixed_value_indicator()
	await _test_transform_entry()
	await _test_costume_keeps_selection()
	await _test_layer_name_display()
	await _test_link_into_collapsed_group()
	await _test_link_framing()
	await _test_unlink_keeps_rest_place()
	await _test_unlink_wiggle_child()
	await _test_link_keeps_rest_place()
	await _test_unlink_undo_round_trip()
	await _test_layer_list_indentation()
	await _test_layer_list_fits_panel()
	await _test_sidebar_fits_depth()
	await _test_wiggle_child_follow()
	await _test_costumes()
	await _test_command_history()
	await _test_z_index_editor()
	await _test_legacy_canvas_replacement()
	await _test_rejected_load_preserves_avatar()
	await _test_save_load_round_trip()

	if is_instance_valid(_main):
		_main.queue_free()
		await get_tree().process_frame
	assert_true(Global.main == null, "main scene detaches from the application context")
	assert_true(Global.spriteEdit == null, "edit sidebar detaches from the application context")
	assert_true(Global.spriteList == null, "layer sidebar detaches from the application context")
	assert_true(Global.mouse == null, "mouse coordinator detaches from the application context")
	assert_true(Global.chain == null, "reparenting chain detaches from the application context")
	assert_equal(Global.sprite_count(), 0, "avatar-session teardown clears the live sprite registry")
	_remove_temp_file(_materialized_fixture_path)
	print("[AVATAR SCENE] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _test_component_scenes() -> void:
	var settings = _main.settingsMenu
	assert_equal(settings.panel_size(), Vector2(420, 380), "settings facade retains its menu-bar sizing API")
	assert_equal(settings._bodies.size(), 5, "settings scene constructs one real body per tab component")
	for index in settings._bodies.size():
		settings._show_tab(index)
		for body_index in settings._bodies.size():
			assert_equal(
				settings._bodies[body_index].visible, body_index == index,
				"settings tab %d owns the only visible component body" % index,
			)
		assert_true(settings._bodies[index].get_child_count() > 0, "settings tab %d constructs real controls" % index)
	settings._show_tab(0)
	for retired_node in ["Buttons", "WobbleControl", "Layers", "VisToggle", "EyeTracking", "SubViewportContainer"]:
		assert_false(Global.spriteEdit.has_node(retired_node), "left sidebar no longer instantiates retired %s UI" % retired_node)
	assert_equal(_main.editControls.process_mode, Node.PROCESS_MODE_DISABLED, "edit component tree is dormant on the player page")
	_main.swapMode()
	await get_tree().process_frame
	assert_equal(_main.editControls.process_mode, Node.PROCESS_MODE_INHERIT, "edit component tree resumes on the edit page")
	_main.swapMode()
	await get_tree().process_frame
	assert_equal(_main.editControls.process_mode, Node.PROCESS_MODE_DISABLED, "edit component tree stops after returning to the player page")


func _test_sidebar_selection_state() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	_main.swapMode()
	Global.select_sprite(sprite)
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_true(Global.spriteEdit._controls_enabled, "left inspector enables its component controls for a selection")
	assert_not_null(Global.spriteEdit._preview.texture, "left inspector presenter synchronizes the selected image")
	Global.clear_selection()
	await get_tree().process_frame
	assert_false(Global.spriteEdit._controls_enabled, "left inspector disables its component controls without a selection")
	_main.swapMode()
	await get_tree().process_frame


func _materialize_regression_fixture() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGRESSION_FIXTURE))
	if not parsed is Dictionary:
		return ""
	var absolute_image_path := ProjectSettings.globalize_path("res://test/testBody.png")
	for key in parsed:
		if parsed[key] is Dictionary and parsed[key].get("type") == "sprite":
			parsed[key]["path"] = absolute_image_path
	var path := OS.get_temp_dir().path_join("pngtuberplus-avatar-fixture-%d.json" % OS.get_process_id())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(parsed, "\t"))
	file.close()
	return path


func _remove_temp_file(path: String) -> void:
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var remove_error := DirAccess.remove_absolute(path)
	assert_true(remove_error == OK, "integration runner removes temporary fixture data")


func _test_loaded_avatar(context: String) -> void:
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, context + ": every sprite is registered")
	var base = Global.sprite_by_id(BASE_ID)
	var costume_one = Global.sprite_by_id(COSTUME_ONE_ID)
	var costume_two = Global.sprite_by_id(COSTUME_TWO_ID)
	var nested = Global.sprite_by_id(NESTED_ID)
	for sprite in [base, costume_one, costume_two, nested]:
		assert_not_null(sprite, context + ": expected unsigned-ID sprite exists")
	if base == null or costume_one == null or costume_two == null or nested == null:
		return

	assert_true(Global.sprite_from_hit_area(base.grabArea) == base, context + ": grab-area traversal resolves the sprite root")
	Global.select_sprite(base)
	assert_true(Global.heldSprite == base, context + ": selection changes through the application boundary")
	Global.clear_selection()
	assert_true(Global.heldSprite == null, context + ": selection clearing changes through the application boundary")
	assert_equal(costume_one.parentId, BASE_ID, context + ": first child retains its parent ID")
	assert_true(costume_one.parentSprite == base, context + ": first child resolves its parent object")
	assert_true(costume_one.get_parent() == base.sprite, context + ": first child is reparented under the base Sprite2D")
	assert_equal(nested.parentId, COSTUME_TWO_ID, context + ": nested child retains its parent ID")
	assert_true(nested.parentSprite == costume_two, context + ": nested child resolves its parent object")
	assert_true(nested.get_parent() == costume_two.sprite, context + ": nested child restores the complete hierarchy")
	assert_equal(costume_one.position, Vector2(0, -40), context + ": local child position survives hierarchy assembly")
	assert_equal(costume_one.offset, Vector2(2, 3), context + ": structured sprite offsets survive load")
	assert_equal(costume_one.eyeTrackTargetId, BASE_ID, context + ": unsigned eye-target references survive load")
	assert_false(Global.eyeTrackingGloballyEnabled, context + ": avatar-level eye tracking state is restored")
	assert_equal(base.animClips.size(), 1, context + ": legacy sway migrates to one animation clip")
	if base.animClips.size() == 1:
		assert_equal(base.animClips[0].get("channel"), "translation", context + ": migrated sway uses translation")
		assert_approx(float(base.animClips[0].get("ampY", 0.0)), 11.0, 0.0001, context + ": migrated sway amplitude is preserved")


# Clicking a stack of overlapping layers must select the topmost one and then
# step down the stack, and it must keep stepping while the avatar is moving. The
# real pick path is used: the physics broad phase, the alpha test and the
# top-first ordering all run, with only the cursor position injected.
func _test_click_cycling() -> void:
	if not _main.editMode:
		_main.swapMode()
	await get_tree().process_frame
	await get_tree().physics_frame

	var point := _busiest_click_point()
	var first_hits := _pick_at(point)
	assert_true(first_hits.size() >= 2, "the fixture offers a stack of overlapping layers to cycle")
	if first_hits.size() < 2:
		return

	Global.clear_selection()
	var seen := {}
	var stepped_correctly := true
	for click in range(8):
		# Keep the rig in motion, which is what resets index-based cycling.
		if click % 2 == 0:
			_main.onSpeak()
		for _frame in range(6):
			await get_tree().process_frame
		var hits := _pick_at(point)
		if hits.is_empty():
			continue
		var candidates := []
		for hit in hits:
			candidates.append(Global.sprite_from_hit_area(hit))
		var held_before = Global.heldSprite
		var expected = candidates[0]
		var held_index: int = candidates.find(held_before)
		if held_index != -1:
			expected = candidates[(held_index + 1) % candidates.size()]
		Global.select(hits)
		if Global.heldSprite != expected:
			stepped_correctly = false
		if Global.heldSprite != null:
			seen[Global.heldSprite.id] = true

	assert_true(stepped_correctly, "each click selects the layer below the held one, wrapping at the bottom")
	assert_true(seen.size() >= 2, "clicking a stack on a moving avatar reaches more than one layer")
	Global.clear_selection()


# The world point covered by the most opaque layers, so the test cycles a real
# stack rather than whatever happens to sit at a fixed coordinate.
func _busiest_click_point() -> Vector2:
	var best := Vector2.ZERO
	var best_count := 0
	for sprite in Global.sprite_nodes():
		var center: Vector2 = sprite.sprite.global_position
		for dx in range(-40, 41, 8):
			for dy in range(-40, 41, 8):
				var point := center + Vector2(dx, dy)
				var count := _pick_at(point).size()
				if count > best_count:
					best_count = count
					best = point
	return best


func _pick_at(world_point: Vector2) -> Array:
	var space := _main.get_world_2d().direct_space_state
	var params := PhysicsPointQueryParameters2D.new()
	params.position = world_point
	params.collision_mask = Global.mouse.SELECT_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var areas := []
	for result in space.intersect_point(params):
		if result.collider is Area2D:
			areas.append(result.collider)
	var opaque: Array = Global.mouse._opaque_candidates(areas, world_point)
	Global.mouse._sort_top_first(opaque)
	return opaque


# Deleting a layer drops its row where it was. The list must not jump back to
# the top, and the rows around it must not reorder.
func _test_layer_list_deletion() -> void:
	var list = Global.spriteList
	var rows: Array = list.container.get_children()
	assert_true(rows.size() >= 4, "the layer list is populated before a deletion")
	if rows.size() < 4:
		return

	# Rigs routinely share one z across many layers, which is what used to make
	# the rebuilt order arbitrary.
	for sprite in Global.sprite_nodes():
		sprite.z = 0
		sprite.setZIndex()
	await list.updateData()
	await get_tree().process_frame

	var before := _row_sprite_ids()
	await list.updateData()
	await get_tree().process_frame
	assert_equal(_row_sprite_ids(), before, "rebuilding the layer list keeps the same order at equal z")

	var scroll_container: ScrollContainer = list.get_node("ScrollContainer")
	scroll_container.scroll_vertical = 40
	await get_tree().process_frame
	var scroll_before: int = scroll_container.scroll_vertical

	# Delete a leaf, so the test is about the list rather than about re-parenting.
	var victim = null
	for row in list.container.get_children():
		if row.childrenTags.is_empty():
			victim = row.sprite
			break
	assert_not_null(victim, "the layer list offers a leaf layer to delete")
	if victim == null:
		return
	var expected := _row_sprite_ids()
	expected.erase(victim.id)

	Global.select_sprite(victim)
	_main.delete_layer(victim, false)
	# Enough frames for a full rebuild to have finished, so the order assertion
	# reads a settled list either way.
	for _frame in range(3):
		await get_tree().process_frame

	assert_equal(_row_sprite_ids(), expected, "deleting a layer removes its row and leaves the order alone")
	assert_equal(
		scroll_container.scroll_vertical, scroll_before,
		"deleting a layer keeps the list where the user was reading it",
	)
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES - 1, "deleting a layer unregisters exactly one layer")

	await list.updateData()
	await get_tree().process_frame
	assert_equal(_row_sprite_ids(), expected, "a rebuild after a deletion keeps that order")

	UndoManager.undo()
	await get_tree().process_frame
	await get_tree().process_frame


# Deleting a layer keeps the layers under it by default, moving them up to the
# deleted layer's own parent. Only the checkbox on the prompt takes them too.
func _test_layer_deletion_children() -> void:
	var list = Global.spriteList
	var scroll_container: ScrollContainer = list.get_node("ScrollContainer")
	var parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var child = Global.sprite_by_id(NESTED_ID)
	assert_not_null(parent, "the fixture has a layer with a child to delete")
	assert_not_null(child, "the fixture has a child layer to keep")
	if parent == null or child == null:
		return
	var grandparent_id = parent.parentId
	var child_id = child.id

	scroll_container.scroll_vertical = 30
	_main.delete_layer(parent, false)
	for _frame in range(3):
		await get_tree().process_frame

	assert_true(is_instance_valid(child), "deleting a layer keeps the layers under it by default")
	assert_equal(child.parentId, grandparent_id, "a kept child moves up to the deleted layer's parent")
	assert_true(_row_sprite_ids().has(child_id), "a kept child keeps its row")
	assert_false(_row_sprite_ids().has(COSTUME_TWO_ID), "the deleted layer loses its row")
	assert_equal(scroll_container.scroll_vertical, 30, "deleting through the command keeps the scroll position")

	# Undo has to put the layer back without blanking the list.
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "undoing a deletion restores the layer")
	assert_true(_row_sprite_ids().has(COSTUME_TWO_ID), "undoing a deletion restores its row")
	assert_equal(scroll_container.scroll_vertical, 30, "undoing a deletion keeps the scroll position")

	# The checkbox path: the layer and everything under it.
	var again = Global.sprite_by_id(COSTUME_TWO_ID)
	_main.delete_layer(again, true)
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES - 2, "deleting with children takes the descendants too")
	assert_false(_row_sprite_ids().has(NESTED_ID), "a deleted child loses its row")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "undoing a deletion with children restores both layers")


# A child layer's row is indented under its parent's.
func _test_layer_list_indentation() -> void:
	var list = Global.spriteList
	await list.updateData()
	await get_tree().process_frame

	var indent_for := {}
	for row in list.container.get_children():
		if is_instance_valid(row.sprite):
			indent_for[row.sprite.id] = [row.indent, row._indent_spacer.custom_minimum_size.x]

	# BASE is a root, COSTUME_TWO is its child, NESTED is a child of that.
	var step := float(SpriteListObject.INDENT_STEP)
	assert_equal(indent_for.get(BASE_ID), [0, 0.0], "a root layer's row is not indented")
	assert_equal(indent_for.get(COSTUME_TWO_ID), [1, step], "a child layer's row is indented one step")
	assert_equal(indent_for.get(NESTED_ID), [2, step * 2.0], "a grandchild's row is indented two steps")


# Deep hierarchies and a narrow sidebar must not push the show/hide button off
# the panel. Rows shrink with the panel, and indentation gives way first.
func _test_layer_list_fits_panel() -> void:
	var list = Global.spriteList
	var original_width: float = list.panel_width

	# Chain the flat fixture layers into one deep hierarchy, as one history entry
	# so the rig can be put back exactly as it was.
	var chain := [4000000004, 4000000005, 4000000006, 4000000007, 4000000008, 4000000009]
	MutationCommands.structural(func():
		for index in range(1, chain.size()):
			var child = Global.sprite_by_id(chain[index])
			var parent = Global.sprite_by_id(chain[index - 1])
			if child != null and parent != null:
				Global.linkSprite(child, parent)
		return true)
	await list.updateData()
	await get_tree().process_frame

	var deepest := 0
	for row in list.container.get_children():
		deepest = maxi(deepest, row.indent)
	assert_true(deepest >= 5, "the test rig nests deeply enough to crowd a row")

	for width in [320.0, 260.0, 220.0]:
		list.panel_width = width
		list._apply_size()
		for _frame in range(3):
			await get_tree().process_frame
		# The panel's own right edge, not the scroll container's: with a fixed
		# minimum row width the scroll container itself refuses to shrink and
		# hangs outside the sidebar, taking the buttons with it.
		var right_edge: float = list.position.x + list.panel_width
		var overflow := 0.0
		var narrowest := 9999.0
		for row in list.container.get_children():
			var button_right: float = row._vis_btn.global_position.x + row._vis_btn.size.x
			overflow = maxf(overflow, button_right - right_edge)
			narrowest = minf(narrowest, row._name_label.size.x)
		assert_true(overflow <= 0.0, "at %d px the show/hide button stays inside the panel (over by %.1f)" % [int(width), overflow])
		assert_true(narrowest > 0.0, "at %d px the layer name keeps some room" % int(width))

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	for id in chain.slice(1):
		var restored = Global.sprite_by_id(id)
		assert_true(restored != null and restored.parentId == BASE_ID, "the test rig's hierarchy is put back")
	list.panel_width = original_width
	list._apply_size()
	await list.updateData()
	await get_tree().process_frame


# Loading an avatar widens the sidebar until the deepest layer can show its
# indentation in full, so depth is never compressed away on a rig as it opens.
func _test_sidebar_fits_depth() -> void:
	var list = Global.spriteList
	var original_width: float = list.panel_width

	# One chain through every fixture layer, as deep as this rig can go.
	var ids := []
	for sprite in Global.sprite_nodes():
		ids.append(sprite.id)
	MutationCommands.structural(func():
		for index in range(1, ids.size()):
			var child = Global.sprite_by_id(ids[index])
			var parent = Global.sprite_by_id(ids[index - 1])
			if child != null and parent != null:
				Global.linkSprite(child, parent)
		return true)
	await list.updateData()
	await get_tree().process_frame

	var width_before: float = list.panel_width
	list.fitPanelToDepth()
	for _frame in range(3):
		await get_tree().process_frame

	assert_true(list.panel_width >= width_before, "fitting the sidebar to depth never narrows it")
	var maximum: float = get_viewport().get_visible_rect().size.x * list.MAX_WIDTH_RATIO
	var compressed := 0
	var deepest := 0
	for row in list.container.get_children():
		deepest = maxi(deepest, row.indent)
		if row.indentWidth() < row.indent * SpriteListObject.INDENT_STEP:
			compressed += 1
	assert_true(deepest >= 8, "the test rig is deep enough to need the width")
	if list.panel_width < maximum:
		assert_equal(compressed, 0, "after fitting, no row's indentation is compressed")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	list.panel_width = original_width
	list._apply_size()
	await list.updateData()
	await get_tree().process_frame


# Modifier-clicking builds a selection of several layers, which duplicate and
# delete then act on, and which the sidebars write to as one history entry.
func _test_multi_selection() -> void:
	var first = Global.sprite_by_id(BASE_ID)
	var second = Global.sprite_by_id(COSTUME_ONE_ID)
	var third = Global.sprite_by_id(COSTUME_TWO_ID)
	if first == null or second == null or third == null:
		return

	Global.select_sprite(first)
	Global.toggle_sprite_selection(second)
	assert_equal(Global.selected_sprites().size(), 2, "a modifier-click adds a layer to the selection")
	assert_true(Global.heldSprite == first, "the layer clicked first stays the active one")
	assert_true(Global.is_sprite_selected(second), "the added layer reads as selected")

	Global.toggle_sprite_selection(second)
	assert_equal(Global.selected_sprites().size(), 1, "a second modifier-click removes it again")

	# Removing the active layer promotes another, so an edit always has a target.
	Global.toggle_sprite_selection(second)
	Global.toggle_sprite_selection(first)
	assert_true(Global.heldSprite == second, "dropping the active layer promotes the next one")

	# A plain selection replaces the group.
	Global.select_sprite(third)
	assert_equal(Global.selected_sprites().size(), 1, "an ordinary click replaces the selection")

	# A sidebar edit writes to every selected layer, in one history entry.
	Global.select_sprite(first)
	Global.toggle_sprite_selection(second)
	var before_talk: int = second.showOnTalk
	MutationCommands.set_layer_property(first, "showOnTalk", 2)
	assert_equal(first.showOnTalk, 2, "the edit reaches the active layer")
	assert_equal(second.showOnTalk, 2, "the edit reaches the rest of the selection")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_by_id(COSTUME_ONE_ID).showOnTalk, before_talk, "one undo puts every layer back")

	# Deleting a group is one entry too.
	var count: int = Global.sprite_count()
	Global.select_sprite(Global.sprite_by_id(4000000010))
	Global.toggle_sprite_selection(Global.sprite_by_id(4000000011))
	_main.delete_layers(Global.selected_sprites(), false)
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_count(), count - 2, "deleting a group removes every layer in it")
	assert_equal(Global.selected_sprites().size(), 0, "the deleted layers leave the selection")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_count(), count, "one undo restores the whole group")
	Global.clear_selection()


# A control whose selected layers disagree shows a dash rather than the active
# layer's number.
func _test_mixed_value_indicator() -> void:
	var first = Global.sprite_by_id(BASE_ID)
	var second = Global.sprite_by_id(COSTUME_ONE_ID)
	if first == null or second == null:
		return
	var drag_label: Label = Global.spriteEdit._drag_label

	first.dragSpeed = 4
	second.dragSpeed = 4
	Global.select_sprite(first)
	Global.toggle_sprite_selection(second)
	assert_false(Global.selection_is_mixed("dragSpeed"), "layers that agree are not mixed")
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_true(drag_label.text.contains("4"), "an agreed value still shows its number")

	second.dragSpeed = 9
	assert_true(Global.selection_is_mixed("dragSpeed"), "layers that disagree read as mixed")
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_true(drag_label.text.ends_with(Global.MIXED_VALUE), "a mixed value shows the dash instead")

	# One layer alone is never mixed, whatever the others hold.
	Global.select_sprite(first)
	assert_false(Global.selection_is_mixed("dragSpeed"), "a single layer is never mixed")
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_true(drag_label.text.contains("4"), "the number comes back with one layer selected")
	Global.clear_selection()


# Position and origin offset are typed in, not just read.
func _test_transform_entry() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	Global.select_sprite(sprite)
	Global.spriteEdit.setImage()
	await get_tree().process_frame

	var position_fields = Global.spriteEdit._pos_fields
	var offset_fields = Global.spriteEdit._offset_fields
	var original: Vector2 = sprite.authoredPosition()
	var original_offset: Vector2 = sprite.offset

	position_fields._x.text = "12"
	position_fields._y.text = "-34"
	position_fields._commit()
	await get_tree().process_frame
	assert_equal(sprite.authoredPosition(), Vector2(12, -34), "typing a position moves the layer")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_by_id(BASE_ID).authoredPosition(), original, "undo puts the position back")

	sprite = Global.sprite_by_id(BASE_ID)
	offset_fields._x.text = "7"
	offset_fields._y.text = "8"
	offset_fields._commit()
	await get_tree().process_frame
	assert_equal(sprite.offset, Vector2(7, 8), "typing an offset moves the origin")
	assert_equal(sprite.sprite.offset, Vector2(7, 8), "the artwork follows the offset")
	assert_equal(sprite.authoredPosition(), original, "an offset entry leaves the position alone")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_by_id(BASE_ID).offset, original_offset, "undo puts the offset back")

	# Enter applies the value and hands the keyboard back, so the app's own
	# shortcuts (undo among them) work without clicking away first.
	sprite = Global.sprite_by_id(BASE_ID)
	position_fields._x.grab_focus()
	await get_tree().process_frame
	assert_true(position_fields._x.has_focus(), "a field takes focus when it is clicked into")
	position_fields._x.text = "3"
	position_fields._x.text_submitted.emit("3")
	await get_tree().process_frame
	assert_false(position_fields._x.has_focus(), "Enter gives focus back")
	assert_false(Global.is_text_entry_active(), "the app's shortcuts are live again")
	assert_equal(sprite.authoredPosition().x, 3.0, "Enter applied the value")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	sprite = Global.sprite_by_id(BASE_ID)

	# A click anywhere outside the field hands the keyboard back too, since
	# clicking a label or a panel's blank area does not move focus by itself.
	position_fields._x.grab_focus()
	await get_tree().process_frame
	var elsewhere := InputEventMouseButton.new()
	elsewhere.button_index = MOUSE_BUTTON_LEFT
	elsewhere.pressed = true
	elsewhere.position = position_fields._x.get_global_rect().position - Vector2(40, 40)
	Global._release_text_focus_outside(elsewhere)
	await get_tree().process_frame
	assert_false(position_fields._x.has_focus(), "clicking away releases the field")

	# A click inside the field keeps it, or typing would be impossible.
	position_fields._x.grab_focus()
	await get_tree().process_frame
	var inside := InputEventMouseButton.new()
	inside.button_index = MOUSE_BUTTON_LEFT
	inside.pressed = true
	inside.position = position_fields._x.get_global_rect().get_center()
	Global._release_text_focus_outside(inside)
	await get_tree().process_frame
	assert_true(position_fields._x.has_focus(), "a click inside the field keeps it")
	position_fields._x.release_focus()
	await get_tree().process_frame

	# Committing a field nobody changed leaves no history entry to undo through.
	var before_entry: Vector2 = sprite.authoredPosition()
	var depth: int = UndoManager._undo_stack.size()
	position_fields.show_value(before_entry)
	position_fields._commit()
	await get_tree().process_frame
	assert_equal(UndoManager._undo_stack.size(), depth, "an unchanged entry adds no history")

	# Unreadable entries are ignored rather than moving the layer to zero.
	sprite = Global.sprite_by_id(BASE_ID)
	var held: Vector2 = sprite.authoredPosition()
	position_fields._x.text = ""
	position_fields._y.text = "nonsense"
	position_fields._commit()
	await get_tree().process_frame
	assert_equal(sprite.authoredPosition(), held, "an unreadable entry changes nothing")
	Global.spriteEdit.setImage()
	await get_tree().process_frame


# Switching costume changes what is shown, not what is being edited.
func _test_costume_keeps_selection() -> void:
	var first = Global.sprite_by_id(BASE_ID)
	var second = Global.sprite_by_id(COSTUME_ONE_ID)
	if first == null or second == null:
		return
	Global.select_sprite(first)
	Global.toggle_sprite_selection(second)
	var before: int = Global.selected_sprites().size()

	_main.changeCostume(2)
	await get_tree().process_frame
	assert_equal(Global.selected_sprites().size(), before, "changing costume keeps the selection")
	assert_true(Global.heldSprite == first, "changing costume keeps the active layer")

	_main.changeCostume(1)
	await get_tree().process_frame
	Global.clear_selection()


# The left sidebar names the layer it is editing, without path or extension.
func _test_layer_name_display() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	var heading: Label = Global.spriteEdit._name_heading

	Global.select_sprite(sprite)
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_equal(heading.text, sprite.displayName(), "the sidebar names the selected layer")
	assert_false(heading.text.contains("/"), "the name carries no path")
	assert_false(heading.text.contains("."), "the name carries no extension")

	MutationCommands.set_layer_property(sprite, "layerName", "Left Arm")
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_equal(heading.text, "Left Arm", "a renamed layer shows its own name")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	Global.clear_selection()
	Global.spriteEdit.setImage()
	await get_tree().process_frame
	assert_equal(heading.text, "", "no selection, no name")


# Linking a layer into a collapsed group hides it with the rest of that group,
# and the group stays collapsed.
func _test_link_into_collapsed_group() -> void:
	var list = Global.spriteList
	await list.updateData()
	await get_tree().process_frame

	var parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var child = Global.sprite_by_id(NESTED_ID)
	var newcomer = Global.sprite_by_id(COSTUME_ONE_ID)
	if parent == null or child == null or newcomer == null:
		return
	var parent_row = _row_for(parent)
	var original_parent = newcomer.parentId

	parent_row._on_collapse_toggled()
	await get_tree().process_frame
	assert_true(parent_row.collapsed, "the group is collapsed to begin with")
	assert_false(_row_for(child).visible, "its child is hidden")
	assert_true(_row_for(newcomer).visible, "the layer to link is visible outside it")

	MutationCommands.structural(func():
		Global.linkSprite(newcomer, parent)
		return true)
	for _frame in range(3):
		await get_tree().process_frame

	assert_true(parent_row.collapsed, "the group is still collapsed after a link")
	assert_equal(parent_row._collapse_btn.text, "▶", "and still says so")
	assert_false(_row_for(newcomer).visible, "the newly linked layer is hidden with the group")
	assert_false(_row_for(child).visible, "the layers already in the group stay hidden")

	# Expanding shows everything in the group, including the newcomer.
	parent_row._on_collapse_toggled()
	await get_tree().process_frame
	assert_true(_row_for(newcomer).visible, "expanding shows the newly linked layer")
	assert_true(_row_for(child).visible, "expanding shows the rest of the group")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_by_id(COSTUME_ONE_ID).parentId, original_parent, "the test rig is put back")
	await list.updateData()
	await get_tree().process_frame


# How the layer list follows a link depends on where the parent was picked. In
# the list, the user had already scrolled to it, so the parent row stays exactly
# where it was on screen. On the canvas, the child has just moved out from under
# the list's frame, so the list brings child and parent into view together.
func _test_link_framing() -> void:
	var list = Global.spriteList
	var view: ScrollContainer = list.get_node("ScrollContainer")
	await list.updateData()
	for _frame in range(3):
		await get_tree().process_frame

	# The canvas caller is the one that says so; nothing else can tell the two
	# routes apart once they reach linkSprite.
	var global_source := FileAccess.get_file_as_string("res://autoload/global.gd")
	assert_true(
		global_source.contains("linkSprite(prevSpr, heldSprite, true)"),
		"a parent clicked on the canvas is linked as a canvas pick",
	)

	# Parent picked in the list, through the row's own click. The child's row sits
	# above the parent's, so its leaving shifts the parent up a row: holding the
	# raw scroll offset would not hold the parent in place.
	var child = Global.sprite_by_id(4000000004)
	var parent = Global.sprite_by_id(COSTUME_TWO_ID)
	if child == null or parent == null:
		return
	assert_true(_row_for(child).position.y < _row_for(parent).position.y, "the child's row starts above the parent's")
	view.scroll_vertical = int(_row_for(parent).position.y) - 40
	await get_tree().process_frame
	var held_offset: float = _row_for(parent).position.y - view.scroll_vertical
	var scroll_before: int = view.scroll_vertical
	Global.select_sprite(child)
	Global.begin_reparenting()
	_row_for(parent)._select()
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(child.parentSprite == parent, "clicking the parent's row links the held layer to it")
	assert_approx(
		_row_for(parent).position.y - view.scroll_vertical, held_offset, 1.0,
		"a parent picked in the list stays where it was on screen",
	)
	assert_true(view.scroll_vertical != scroll_before, "the list compensated for the row that left from above")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame

	# Parent picked on the canvas, where child and parent fit in the view
	# together: both are shown, centred.
	child = Global.sprite_by_id(4000000011)
	parent = Global.sprite_by_id(4000000005)
	if child == null or parent == null:
		return
	view.ensure_control_visible(_row_for(child))
	await get_tree().process_frame
	MutationCommands.structural(func():
		Global.linkSprite(child, parent, true)
		return true)
	for _frame in range(3):
		await get_tree().process_frame
	var top: float = _row_for(parent).position.y
	var bottom: float = _row_for(child).position.y + _row_for(child).size.y
	assert_true(bottom - top <= view.size.y, "this pair fits in the view together")
	assert_true(_row_fully_in_view(view, _row_for(parent)), "a canvas link shows the parent")
	assert_true(_row_fully_in_view(view, _row_for(child)), "a canvas link shows the child where it went")
	assert_approx(
		view.scroll_vertical + view.size.y * 0.5, (top + bottom) * 0.5, 1.0,
		"the pair is centred in the list",
	)
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame

	# Parent picked on the canvas, where the pair is taller than the view: the
	# child is the layer that moved, so it wins, and the parent sits as close
	# above it as the view allows. A new child joins its siblings in list order,
	# so taking the bottom row puts it after the parent's existing child, which
	# makes the pair three rows tall.
	parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var rows: Array = list.container.get_children()
	child = rows[rows.size() - 1].sprite
	assert_true(
		_row_for(child).position.y > _row_for(Global.sprite_by_id(NESTED_ID)).position.y,
		"the layer to link sits below the parent's existing child",
	)
	view.ensure_control_visible(_row_for(child))
	await get_tree().process_frame
	MutationCommands.structural(func():
		Global.linkSprite(child, parent, true)
		return true)
	for _frame in range(3):
		await get_tree().process_frame
	top = _row_for(parent).position.y
	bottom = _row_for(child).position.y + _row_for(child).size.y
	assert_true(bottom - top > view.size.y, "this pair is taller than the view")
	assert_true(_row_fully_in_view(view, _row_for(child)), "when the pair does not fit, the child stays in view")
	assert_approx(view.scroll_vertical + view.size.y, bottom, 1.0, "and the parent is as close above it as fits")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame

	# Parent picked on the canvas while it is collapsed: the child is hidden with
	# the rest of the group, so the parent is framed on its own.
	rows = list.container.get_children()
	child = rows[rows.size() - 1].sprite
	parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var parent_row = _row_for(parent)
	parent_row._on_collapse_toggled()
	view.ensure_control_visible(_row_for(child))
	await get_tree().process_frame
	MutationCommands.structural(func():
		Global.linkSprite(child, parent, true)
		return true)
	for _frame in range(3):
		await get_tree().process_frame
	parent_row = _row_for(parent)
	assert_true(parent_row.collapsed, "the collapsed parent stays collapsed")
	assert_false(_row_for(child).visible, "and the child is hidden with its group")
	assert_approx(
		view.scroll_vertical + view.size.y * 0.5, parent_row.position.y + parent_row.size.y * 0.5, 1.0,
		"a collapsed parent is centred on its own",
	)
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	_row_for(parent)._on_collapse_toggled()
	Global.clear_selection()
	await list.updateData()
	await get_tree().process_frame


# Unlinking must leave a layer, and everything under it, where the rig puts it at
# rest. The avatar never stops moving, so the unlink is taken mid-motion here on
# purpose: idle/bounce motion on OriginMotion, drag lag and rotation on the
# parent's DragOrigin, and squash on its Sprite2D. None of it may leak into the
# layer's new authored position.
func _test_unlink_keeps_rest_place() -> void:
	var parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var child = Global.sprite_by_id(NESTED_ID)
	if parent == null or child == null:
		return
	assert_true(child.parentSprite == parent, "the nested fixture layer starts linked")
	var chain: Array = [child]
	while chain[-1].parentSprite != null:
		chain.append(chain[-1].parentSprite)
	assert_true(chain.size() >= 3, "the layer sits two links deep, so an ancestor above its parent counts too")
	var motion: Node2D = _main.get_node("OriginMotion")
	var motion_rest := motion.position

	# Where the layer is on screen with the rig at rest, before the unlink.
	_hold_rest(chain)
	var rest_before: Vector2 = child.global_position

	# Unlink mid-motion.
	motion.position = motion_rest + Vector2(0, -37)
	parent.wob.position = Vector2(6, -4)
	parent.dragOrigin.position = Vector2(11, 7)
	parent.dragOrigin.rotation = 0.35
	parent.sprite.rotation = -0.2
	parent.sprite.scale = Vector2(1.1, 0.9)
	Global.select_sprite(child)
	MutationCommands.structural(func():
		Global.unlinkSprite()
		return true)
	assert_true(child.parentId == null, "the layer is unlinked")
	assert_true(child.parentSprite == null, "and forgets its parent")
	assert_true(child.get_parent() == _main.origin, "an unlinked layer hangs off the avatar origin")
	assert_true(Global.heldSprite == child, "the unlinked layer stays selected")
	assert_equal(child.authoredPosition(), child.position, "the saved position is the one the layer now has")

	# Back at rest, it is exactly where it was.
	motion.position = motion_rest
	_hold_rest(chain)
	assert_approx(child.global_position.x, rest_before.x, 0.01, "unlinking leaves the layer in place at rest (x)")
	assert_approx(child.global_position.y, rest_before.y, 0.01, "unlinking leaves the layer in place at rest (y)")
	assert_approx(child.rotation, 0.0, 0.0001, "unlinking carries no live rotation into the layer")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(Global.sprite_by_id(NESTED_ID).parentId == COSTUME_TWO_ID, "undo re-links the layer")

	# A layer with children carries them: unlink the parent, mid-motion again, and
	# its child is still where it was at rest.
	parent = Global.sprite_by_id(COSTUME_TWO_ID)
	child = Global.sprite_by_id(NESTED_ID)
	var grandparent = parent.parentSprite
	chain = [child, parent, grandparent]
	_hold_rest(chain)
	var child_rest: Vector2 = child.global_position
	var parent_rest: Vector2 = parent.global_position
	motion.position = motion_rest + Vector2(0, -37)
	grandparent.dragOrigin.position = Vector2(-9, 12)
	grandparent.dragOrigin.rotation = -0.4
	grandparent.sprite.scale = Vector2(0.9, 1.15)
	Global.select_sprite(parent)
	MutationCommands.structural(func():
		Global.unlinkSprite()
		return true)
	motion.position = motion_rest
	_hold_rest(chain)
	assert_true(child.parentSprite == parent, "an unlinked layer keeps its own children")
	assert_true(parent.global_position.distance_to(parent_rest) < 0.01, "a layer with children stays in place at rest")
	assert_true(child.global_position.distance_to(child_rest) < 0.01, "its children stay in place at rest")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(Global.sprite_by_id(COSTUME_TWO_ID).parentId == BASE_ID, "undo re-links the parent layer")
	Global.clear_selection()


# A child of a wiggle layer has its position and rotation driven by the chain, and
# its authored place lives in _wiggleRestPos. Unlinking it mid-bend must land it
# at that authored place and release the binding, or the stale rest position is
# what the next save records.
func _test_unlink_wiggle_child() -> void:
	var base = Global.sprite_by_id(BASE_ID)
	var child = Global.sprite_by_id(COSTUME_ONE_ID)
	if base == null or child == null:
		return
	var saved := {}
	for field in ["animClips", "wigglePath", "wigglePathWidths", "wiggleWagEnabled", "wiggleWeight", "wiggleShapeReturn"]:
		saved[field] = base.get(field)
	base.animClips = []
	for _frame in range(10):
		await get_tree().process_frame
	var authored: Vector2 = child.position
	base.wigglePath = PackedVector2Array([
		base._local_to_tex(Vector2(-20, 0)), base._local_to_tex(Vector2.ZERO), base._local_to_tex(Vector2(20, 0)),
	])
	base.wigglePathWidths = PackedFloat32Array([8.0, 8.0, 8.0])
	base.wiggleWagEnabled = false
	base.wiggleWeight = 0.0
	base.wiggleShapeReturn = 1.0
	base.wiggleEnabled = true
	base.setWiggle(true)
	for _frame in range(10):
		await get_tree().process_frame
	assert_true(child._wiggleFollowing, "the child rides the wiggle chain")
	var expected: Vector2 = base.authoredPosition() + authored

	# Bend it, as live motion would.
	child.position = authored + Vector2(14, -9)
	child.rotation = 0.5
	Global.select_sprite(child)
	MutationCommands.structural(func():
		Global.unlinkSprite()
		return true)
	assert_false(child._wiggleFollowing, "unlinking releases the wiggle binding")
	assert_true(child.get_parent() == _main.origin, "the child leaves the wiggle parent's DragOrigin")
	assert_true(child.position.distance_to(expected) < 0.01, "a wiggle child lands at its authored place, not mid-bend (got %s, want %s)" % [child.position, expected])
	assert_approx(child.rotation, 0.0, 0.0001, "and without the chain's rotation")
	assert_equal(child.authoredPosition(), child.position, "the position saves record is the one it now has")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	base = Global.sprite_by_id(BASE_ID)
	base.wiggleEnabled = false
	base.setWiggle(false)
	for field in saved:
		base.set(field, saved[field])
	Global.clear_selection()
	await get_tree().process_frame


# Linking, like unlinking, must not move a layer at rest, whatever the rig is
# doing at the moment of the link. The layer changes branch here: it leaves one
# parent and joins a sibling of that parent, both of them moving.
func _test_link_keeps_rest_place() -> void:
	var child = Global.sprite_by_id(NESTED_ID)
	var old_parent = Global.sprite_by_id(COSTUME_TWO_ID)
	var new_parent = Global.sprite_by_id(4000000005)
	if child == null or old_parent == null or new_parent == null:
		return
	var base = Global.sprite_by_id(BASE_ID)
	var everyone: Array = [child, old_parent, new_parent, base]
	var motion: Node2D = _main.get_node("OriginMotion")
	var motion_rest := motion.position
	_hold_rest(everyone)
	var rest_before: Vector2 = child.global_position

	motion.position = motion_rest + Vector2(4, -29)
	for layer in [old_parent, new_parent, base]:
		layer.wob.position = Vector2(5, -3)
		layer.dragOrigin.position = Vector2(-8, 6)
		layer.dragOrigin.rotation = 0.3
		layer.sprite.scale = Vector2(1.12, 0.88)
	MutationCommands.structural(func():
		Global.linkSprite(child, new_parent, true)
		return true)
	motion.position = motion_rest
	_hold_rest(everyone)
	assert_true(child.parentSprite == new_parent, "the layer is linked to its new parent")
	assert_true(child.get_parent() == new_parent.sprite, "and hangs off that parent's Sprite2D")
	assert_true(child.global_position.distance_to(rest_before) < 0.01, "linking mid-motion leaves the layer in place at rest (moved %s)" % [child.global_position - rest_before])
	assert_approx(child.rotation, 0.0, 0.0001, "linking carries no live rotation into the layer")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(Global.sprite_by_id(NESTED_ID).parentId == COSTUME_TWO_ID, "undo puts the layer back under its old parent")
	Global.clear_selection()


# An unlink is one history entry, and undo and redo each put the layer back
# exactly: link data and position, at rest.
func _test_unlink_undo_round_trip() -> void:
	var child = Global.sprite_by_id(NESTED_ID)
	var parent = Global.sprite_by_id(COSTUME_TWO_ID)
	if child == null or parent == null:
		return
	var chain: Array = [child, parent, parent.parentSprite]
	var motion: Node2D = _main.get_node("OriginMotion")
	var motion_rest := motion.position
	_hold_rest(chain)
	var linked_authored: Vector2 = child.authoredPosition()
	var linked_rest: Vector2 = child.global_position
	var depth_before: int = UndoManager.history_depth()

	parent.dragOrigin.rotation = 0.4
	parent.dragOrigin.position = Vector2(9, -5)
	motion.position = motion_rest + Vector2(0, -21)
	Global.select_sprite(child)
	MutationCommands.structural(func():
		Global.unlinkSprite()
		return true)
	motion.position = motion_rest
	assert_equal(UndoManager.history_depth(), depth_before + 1, "an unlink is one history entry")
	_hold_rest(chain)
	var unlinked_authored: Vector2 = child.authoredPosition()

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	child = Global.sprite_by_id(NESTED_ID)
	parent = Global.sprite_by_id(COSTUME_TWO_ID)
	chain = [child, parent, parent.parentSprite]
	_hold_rest(chain)
	assert_true(child.parentId == COSTUME_TWO_ID, "undoing an unlink re-links the layer")
	assert_true(child.parentSprite == parent, "to the same parent object")
	assert_true(child.get_parent() == parent.sprite, "and hangs it off that parent again")
	assert_equal(child.authoredPosition(), linked_authored, "undo restores the linked position")
	assert_true(child.global_position.distance_to(linked_rest) < 0.01, "undo puts the layer back where it was")

	UndoManager.redo()
	for _frame in range(3):
		await get_tree().process_frame
	child = Global.sprite_by_id(NESTED_ID)
	parent = Global.sprite_by_id(COSTUME_TWO_ID)
	chain = [child, parent, parent.parentSprite]
	_hold_rest(chain)
	assert_true(child.parentId == null, "redo unlinks it again")
	assert_true(child.get_parent() == _main.origin, "back onto the avatar origin")
	assert_equal(child.authoredPosition(), unlinked_authored, "redo restores the unlinked position")
	assert_true(child.global_position.distance_to(linked_rest) < 0.01, "and the layer still has not moved at rest")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(Global.sprite_by_id(NESTED_ID).parentId == COSTUME_TWO_ID, "the test rig is put back")
	Global.clear_selection()


# Put these layers in their rest pose right now, as the motion pause does.
func _hold_rest(layers: Array) -> void:
	for layer in layers:
		SpriteRestPose.apply(layer)


func _row_fully_in_view(view: ScrollContainer, row) -> bool:
	return row.position.y >= view.scroll_vertical - 0.5 \
		and row.position.y + row.size.y <= view.scroll_vertical + view.size.y + 0.5


func _row_for(sprite):
	for row in Global.spriteList.container.get_children():
		if row.sprite == sprite:
			return row
	return null


# The avatar has to reach the same place after the same amount of TIME, whether
# that time arrived as one long frame or two short ones. Frames are stepped by
# hand here, so the assertion is about the motion and not about real timing.
func _test_motion_is_time_based() -> void:
	var sprite = Global.sprite_by_id(COSTUME_ONE_ID)
	if sprite == null:
		return
	sprite.rdragStr = 3
	sprite.rLimitMin = -45
	sprite.rLimitMax = 45
	sprite.dragSpeed = 4.0
	var sixty := 1.0 / 60.0

	var coarse := _bounce_trace(sprite, sixty * 2.0, 30)
	var fine := _bounce_trace(sprite, sixty, 60)

	# The bounce height after the same elapsed time. The remaining couple of
	# pixels is the discrete step overshooting the true apex (31.25 px here), by
	# less the more often the avatar is stepped; it used to be the whole arc that
	# changed, not the top two pixels of it.
	assert_true(
		absf(coarse["height"] - fine["height"]) < 3.0,
		"the bounce reaches the same height at 30 and 60 fps (%.2f vs %.2f)" % [coarse["height"], fine["height"]],
	)
	# And the angle rotational drag produced from it.
	assert_true(
		absf(coarse["rotation"] - fine["rotation"]) < 1.0,
		"rotational drag settles at the same angle (%.2f deg vs %.2f deg)" % [coarse["rotation"], fine["rotation"]],
	)
	sprite.rdragStr = 0
	sprite.dragSpeed = 0

	# A sprite sheet steps on elapsed time, including at the Unlimited FPS
	# setting, where max_fps is 0 and the old frame-count divisor collapsed to a
	# step every frame.
	var cap := Engine.max_fps
	sprite.frames = 4
	sprite.animSpeed = 12          # 12 frames per six seconds: one step every 0.5 s
	sprite.changeFrames()
	for setting in [60, 0]:
		Engine.max_fps = setting
		# Four seconds at one step per half second, so seven or eight depending on
		# where the last boundary lands. What matters is that the two rates agree.
		var at_60 := _sheet_steps(sprite, sixty, 60 * 4)
		var at_240 := _sheet_steps(sprite, sixty / 4.0, 240 * 4)
		assert_equal(at_240, at_60, "a sheet steps the same number of times at 60 and 240 fps (max_fps %d)" % setting)
		assert_true(at_60 >= 7 and at_60 <= 8, "and about once a half second (max_fps %d, got %d)" % [setting, at_60])
	Engine.max_fps = cap
	sprite.frames = 1
	sprite.animSpeed = 0
	sprite.changeFrames()
	Global.clear_selection()


# How many times the sheet advances over `steps` frames of `step` seconds.
func _sheet_steps(sprite, step: float, steps: int) -> int:
	sprite._frameClock = 0.0
	sprite.sprite.frame = 0
	var advances := 0
	var last := 0
	for i in steps:
		sprite.animation(step)
		if sprite.sprite.frame != last:
			advances += 1
			last = sprite.sprite.frame
	return advances


# Step the avatar by hand for `steps` frames of `step` seconds, and report where
# the bounce and one layer's rotational drag ended up.
func _bounce_trace(sprite, step: float, steps: int) -> Dictionary:
	_main.origin.get_parent().position.y = 0.0
	_main.yVel = 0.0
	sprite._micRot = 0.0
	sprite._force_drag_snap = true
	_main.onSpeak()
	var height := 0.0
	for i in steps:
		_main._process(step)
		sprite._process(step)
		height = minf(height, _main.origin.get_parent().position.y)
	return {"height": height, "rotation": rad_to_deg(sprite._micRot)}


# A duplicate belongs beside the layer it came from, under the same parent.
func _test_duplicate_placement() -> void:
	var source = Global.sprite_by_id(COSTUME_ONE_ID)
	if source == null:
		return
	Global.select_sprite(source)
	_main.duplicate_selected_layer()
	for _frame in range(3):
		await get_tree().process_frame

	var duplicate = Global.heldSprite
	assert_true(duplicate != null and duplicate != source, "duplicating selects the new layer")
	if duplicate == null or duplicate == source:
		return
	assert_equal(duplicate.parentId, source.parentId, "a duplicate keeps the source's parent")

	var ids := _row_sprite_ids()
	var source_row := ids.find(source.id)
	var duplicate_row := ids.find(duplicate.id)
	assert_true(source_row != -1 and duplicate_row != -1, "both layers have rows")
	assert_equal(duplicate_row, source_row + 1, "the duplicate's row sits directly under the source")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame


# The right-click menu opens where the cursor is, and the delete prompt always
# offers the choice about the layers underneath.
func _test_layer_context_menu() -> void:
	var list = Global.spriteList
	var sprite = Global.sprite_by_id(COSTUME_TWO_ID)
	if sprite == null:
		return

	var menu: PopupMenu = LayerContextMenu.open(list, sprite)
	await get_tree().process_frame
	assert_not_null(menu, "right-clicking a layer opens its menu")
	if menu == null:
		return
	assert_equal(menu.item_count, 5, "the layer menu offers duplicate, rename, replace and delete")
	var labels := []
	for index in menu.item_count:
		labels.append(menu.get_item_text(index))
	assert_true(labels.has("Replace"), "the layer menu can replace this layer's image")
	# Subwindows are embedded by default, and an embedded popup is positioned in
	# viewport coordinates. Screen coordinates put the menu off the right edge of
	# the viewport, where it was clamped into the corner.
	assert_true(get_tree().root.gui_embed_subwindows, "this project embeds its subwindows")
	assert_equal(
		Vector2i(menu.position), Vector2i(get_tree().root.get_mouse_position()),
		"the menu opens at the cursor",
	)
	menu.hide()
	await get_tree().process_frame

	# The prompt for a layer with children, and for one without.
	for target in [sprite, Global.sprite_by_id(NESTED_ID)]:
		if target == null:
			continue
		LayerContextMenu.confirm_delete(list, target)
		await get_tree().process_frame
		var checkbox := _prompt_checkbox()
		assert_not_null(checkbox, "the delete prompt always shows the child-layer choice")
		if checkbox != null:
			assert_false(checkbox.button_pressed, "the child-layer choice starts unchecked")
			assert_equal(
				checkbox.disabled, target.getAllDescendants().is_empty(),
				"the child-layer choice is only usable when there are layers underneath",
			)
		_dismiss_prompt()
		await get_tree().process_frame


# Replacing from the menu targets the layer that was right-clicked, which the
# single-image path reads as the held layer.
func _test_layer_replace_target() -> void:
	var sprite = Global.sprite_by_id(NESTED_ID)
	if sprite == null:
		return
	Global.clear_selection()
	_main.replace_layer(sprite)
	await get_tree().process_frame
	assert_true(Global.heldSprite == sprite, "replacing from the menu selects that layer first")
	assert_true(_main.import_controller.is_replace_dialog_open(), "replacing from the menu opens a file dialog")
	assert_true(_main.isFileSystemOpen(), "the layer replace dialog blocks canvas selection while it is open")
	_main.import_controller._layer_replace_dialog.hide()
	await get_tree().process_frame
	assert_false(_main.import_controller.is_replace_dialog_open(), "dismissing it releases the canvas")


# The replace review names each layer the way the layer list does, so a rig with
# renamed layers is still readable against the file being imported. The source
# name it was imported under is what the match is made on, so it is named too.
func _test_replace_review_names() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	var dialog = _main.replaceReviewDialog
	var source: String = dialog._extract_sprite_name(sprite.path)
	MutationCommands.set_layer_property(sprite, "layerName", "Left ear")
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)

	dialog.setup([{"sprite": sprite, "name": source, "image": image, "position": Vector2.ZERO}], [], [], Vector2.ZERO)
	await get_tree().process_frame
	var labels := _review_labels(dialog)
	assert_true(labels.has("Left ear"), "a matched row is named the way the layer list names it")
	assert_true(labels.has("imported as \"%s\"" % source), "a matched row names the source layer it matched")

	dialog.setup([], [], [sprite], Vector2.ZERO)
	await get_tree().process_frame
	labels = _review_labels(dialog)
	assert_true(labels.has("Left ear"), "an orphan row is named the way the layer list names it")
	assert_true(labels.has("imported as \"%s\"" % source), "an orphan row names the source layer it came from")

	# A layer that has not been renamed carries no note, which would only repeat
	# the name above it.
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	sprite = Global.sprite_by_id(BASE_ID)
	dialog.setup([{"sprite": sprite, "name": source, "image": image, "position": Vector2.ZERO}], [], [], Vector2.ZERO)
	await get_tree().process_frame
	labels = _review_labels(dialog)
	assert_true(labels.has(source), "an unrenamed row is named by its source layer")
	assert_false(labels.has("imported as \"%s\"" % source), "an unrenamed row carries no source note")
	dialog.visible = false
	await get_tree().process_frame


func _review_labels(dialog) -> Array:
	var found := []
	var pending: Array = [dialog._layerList]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		for child in node.get_children():
			if child is Label:
				found.append(child.text)
			pending.append(child)
	return found


func _prompt_checkbox() -> CheckBox:
	for dialog in _main.get_node("UILayer").get_children():
		if not dialog.has_method("add_checkbox"):
			continue
		for item in dialog.column.get_children():
			if item is CheckBox:
				return item
	return null


func _dismiss_prompt() -> void:
	for dialog in _main.get_node("UILayer").get_children():
		if dialog.has_method("add_checkbox"):
			dialog.queue_free()


# A renamed layer reads by its own name everywhere the list shows one, and the
# name is ordinary layer state: undoable, saved, copied by duplication.
func _test_layer_rename() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	var original: String = sprite.displayName()
	MutationCommands.set_layer_property(sprite, "layerName", "Body")
	Global.spriteList.refreshNames()
	await get_tree().process_frame

	assert_equal(sprite.displayName(), "Body", "a renamed layer reports its own name")
	assert_true(_row_names().has("Body"), "the list row shows the new name")
	assert_true(SpriteState.capture_save(sprite).has("layerName"), "the name is written to the save file")

	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame
	assert_equal(Global.sprite_by_id(BASE_ID).displayName(), original, "undo restores the previous name")
	assert_false(_row_names().has("Body"), "undo puts the old name back on the row")

	# Renaming from the menu edits the row in place: no prompt, Enter commits.
	sprite = Global.sprite_by_id(BASE_ID)
	var row = Global.spriteList.rowFor(sprite)
	assert_not_null(row, "the list has a row for this layer")
	if row == null:
		return
	LayerContextMenu.begin_rename(Global.spriteList, sprite)
	for _frame in range(2):
		await get_tree().process_frame
	assert_true(row.isRenaming(), "renaming from the menu opens the field on the row")
	assert_equal(row._name_edit.text, original, "the field starts on the layer's current name")
	assert_true(row._name_edit.has_focus(), "the field takes the keyboard")
	assert_true(Global.has_text_entry_focus(), "shortcuts stand down while the name is being typed")
	row._name_edit.text = "Torso"
	row._name_edit.text_submitted.emit("Torso")
	await get_tree().process_frame
	assert_false(row.isRenaming(), "Enter closes the field")
	assert_equal(sprite.displayName(), "Torso", "Enter commits the new name")
	assert_true(_row_names().has("Torso"), "the row shows the name that was typed")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame

	# Double-clicking the row opens the same field.
	sprite = Global.sprite_by_id(BASE_ID)
	row = Global.spriteList.rowFor(sprite)
	var double := InputEventMouseButton.new()
	double.button_index = MOUSE_BUTTON_LEFT
	double.pressed = true
	double.double_click = true
	row._gui_input(double)
	await get_tree().process_frame
	assert_true(row.isRenaming(), "double-clicking a row renames it in place")
	assert_equal(row._name_edit.text, original, "the field starts on the layer's current name")
	row._name_edit.release_focus()
	await get_tree().process_frame

	# Clicking away commits too, which reaches the field as a lost focus.
	sprite = Global.sprite_by_id(BASE_ID)
	row = Global.spriteList.rowFor(sprite)
	row.beginRename()
	await get_tree().process_frame
	row._name_edit.text = "Chest"
	row._name_edit.release_focus()
	await get_tree().process_frame
	assert_equal(sprite.displayName(), "Chest", "clicking away commits the new name")
	UndoManager.undo()
	for _frame in range(3):
		await get_tree().process_frame

	# Escape abandons the edit, and an empty field is not a name.
	sprite = Global.sprite_by_id(BASE_ID)
	row = Global.spriteList.rowFor(sprite)
	for typed in ["Discarded", ""]:
		row.beginRename()
		await get_tree().process_frame
		row._name_edit.text = typed
		if typed.is_empty():
			row._name_edit.release_focus()
		else:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			row._name_edit.gui_input.emit(escape)
		await get_tree().process_frame
		assert_false(row.isRenaming(), "the field closes without renaming")
		assert_equal(sprite.displayName(), original, "the layer keeps the name it had")


func _row_names() -> Array:
	var names := []
	for row in Global.spriteList.container.get_children():
		if is_instance_valid(row.sprite):
			names.append(row._name_label.text)
	return names


func _row_sprite_ids() -> Array:
	var ids := []
	for row in Global.spriteList.container.get_children():
		if is_instance_valid(row.sprite):
			ids.append(row.sprite.id)
	return ids


func _test_idle_motion() -> void:
	var base = Global.sprite_by_id(BASE_ID)
	if base == null:
		return
	var start_y: float = base.get_node("WobbleOrigin").position.y
	for _frame in range(8):
		await get_tree().process_frame
	var moved_y: float = base.get_node("WobbleOrigin").position.y
	assert_true(absf(moved_y - start_y) > 0.1, "migrated idle sway produces visible runtime motion")


# A child placed beside a wiggle parent's spine must stay where it was authored
# while the chain is at rest (it used to snap onto the spine), and user moves must
# land on its authored position rather than being overwritten by the follow.
func _test_wiggle_child_follow() -> void:
	var base = Global.sprite_by_id(BASE_ID)
	var child = Global.sprite_by_id(COSTUME_ONE_ID)
	if base == null or child == null:
		return
	var saved := {}
	for field in ["animClips", "wigglePath", "wigglePathWidths", "wiggleWagEnabled", "wiggleWeight", "wiggleShapeReturn"]:
		saved[field] = base.get(field)
	base.animClips = []
	for _frame in range(30):
		await get_tree().process_frame
	var authored: Vector2 = child.position
	base.wigglePath = PackedVector2Array([
		base._local_to_tex(Vector2(-20, 0)), base._local_to_tex(Vector2.ZERO), base._local_to_tex(Vector2(20, 0)),
	])
	base.wigglePathWidths = PackedFloat32Array([8.0, 8.0, 8.0])
	base.wiggleWagEnabled = false
	base.wiggleWeight = 0.0
	base.wiggleShapeReturn = 1.0
	base.wiggleEnabled = true
	base.setWiggle(true)
	for _frame in range(10):
		await get_tree().process_frame
	assert_true(child.get_parent() == base.dragOrigin, "wiggle parent carries its linked child on DragOrigin")
	assert_true(child.position.distance_to(authored) < 0.01, "a child beside the wiggle spine stays at its authored position at rest (got %s, want %s)" % [child.position, authored])
	child.setAuthoredPosition(authored + Vector2(3, 0))
	for _frame in range(3):
		await get_tree().process_frame
	assert_true(child.position.distance_to(authored + Vector2(3, 0)) < 0.01, "moving a following child moves it instead of being overwritten")
	assert_equal(child.authoredPosition(), authored + Vector2(3, 0), "a following child reports its authored position for saves")
	base.wiggleEnabled = false
	base.setWiggle(false)
	assert_true(child.get_parent() == base.sprite, "disabling wiggle returns the child to the Sprite2D")
	assert_equal(child.position, authored + Vector2(3, 0), "disabling wiggle restores the child's authored position")
	child.position = authored
	for field in saved:
		base.set(field, saved[field])
	await get_tree().process_frame


func _test_edit_commands() -> void:
	var source = Global.sprite_by_id(COSTUME_ONE_ID)
	assert_not_null(source, "duplicate command source exists")
	if source == null:
		return
	Global.select_sprite(source)
	_main.duplicate_selected_layer()
	await get_tree().process_frame
	var duplicate = Global.heldSprite
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES + 1, "duplicate command registers exactly one new layer")
	assert_true(duplicate != null and duplicate != source, "duplicate command selects the new layer")
	if duplicate == null or duplicate == source:
		return
	assert_equal(duplicate.parentId, source.parentId, "duplicate command preserves the parent identifier")
	assert_true(duplicate.parentSprite == source.parentSprite, "duplicate command preserves the resolved parent")
	assert_equal(duplicate.costumeLayers, source.costumeLayers, "duplicate command preserves costume membership")
	var replacement := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	replacement.fill(Color.WHITE)
	_main._on_replace_confirmed(
		[{"sprite": duplicate, "name": "Controller Replacement", "image": replacement}],
		[], [], Vector2.ZERO, false,
	)
	assert_equal(duplicate.path, "psd://Controller Replacement", "replacement application runs through the avatar controller")
	assert_equal(duplicate.size, Vector2i(8, 6), "replacement synchronizes the live image size before visual rebuild")
	assert_equal(duplicate.imageSize, Vector2i(8, 6), "replacement synchronizes fallback collision dimensions")
	var replacement_shape: CollisionShape2D = null
	for collision_child in duplicate.grabArea.get_children():
		if collision_child is CollisionShape2D:
			replacement_shape = collision_child
			break
	assert_not_null(replacement_shape, "replacement rebuilds the broad-phase collision shape")
	if replacement_shape != null:
		var rectangle := replacement_shape.shape as RectangleShape2D
		assert_not_null(rectangle, "replacement collision keeps the rectangular broad-phase contract")
		if rectangle != null:
			assert_equal(rectangle.size, Vector2(8, 6), "replacement collision matches the new image dimensions")
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES + 1, "replacement application does not alter layer membership")
	var image_size := Vector2(duplicate.imageData.get_size())
	var center := image_size * 0.5
	duplicate.wigglePath = PackedVector2Array([
		center - Vector2(1, 0), center, center + Vector2(1, 0),
	])
	duplicate.wigglePathWidths = PackedFloat32Array([2.0, 2.0, 2.0])
	duplicate.setWiggle(true)
	assert_true(duplicate._wiggleRuntime.has_appendage(), "wiggle enable builds the extracted runtime appendage")
	assert_false(duplicate.sprite.visible, "active wiggle runtime replaces the static sprite")
	duplicate.setWiggle(false)
	assert_false(duplicate._wiggleRuntime.has_appendage(), "wiggle disable releases the runtime appendage")
	assert_true(duplicate.sprite.visible, "wiggle disable restores the static sprite")
	duplicate.queue_free()
	Global.clear_selection()
	await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "duplicate cleanup unregisters the temporary layer")


func _test_costumes() -> void:
	var base = Global.sprite_by_id(BASE_ID)
	var nested = Global.sprite_by_id(NESTED_ID)
	if base == null or nested == null:
		return
	var costume_ids := [
		COSTUME_ONE_ID,
		COSTUME_TWO_ID,
		4000000004,
		4000000005,
		4000000006,
		4000000007,
		4000000008,
		4000000009,
		4000000010,
		4000000011,
	]
	for costume_number in range(1, 11):
		_main.changeCostume(costume_number)
		await get_tree().process_frame
		assert_true(base.visible and base.is_visible_in_tree(), "costume %d keeps the shared base visible" % costume_number)
		for index in range(costume_ids.size()):
			var layer = Global.sprite_by_id(costume_ids[index])
			assert_not_null(layer, "costume %d layer exists" % (index + 1))
			if layer != null:
				var expected := index + 1 == costume_number
				assert_equal(layer.visible, expected, "costume %d applies own visibility to layer %d" % [costume_number, index + 1])
				assert_equal(layer.is_visible_in_tree(), expected, "costume %d applies effective visibility to layer %d" % [costume_number, index + 1])
		var nested_own_visible := costume_number == 1 or costume_number == 2
		assert_equal(nested.visible, nested_own_visible, "costume %d preserves nested membership" % costume_number)
		assert_equal(nested.is_visible_in_tree(), costume_number == 2, "costume %d respects hidden ancestors" % costume_number)

	var costume_five = Global.sprite_by_id(4000000006)
	if costume_five != null:
		costume_five.userHidden = true
		_main.changeCostume(4)
		_main.changeCostume(5)
		await get_tree().process_frame
		assert_false(costume_five.visible, "manual layer hiding survives costume changes")
		costume_five.userHidden = false


# Phase 14: every user mutation reaches history through MutationCommands, so
# these run the real commands against the real scene and undo/redo them.
func _test_command_history() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	_main.changeCostume(1)
	Global.select_sprite(sprite)
	await get_tree().process_frame

	# Discrete command.
	var original_blend: int = sprite.blendMode
	var depth_before := UndoManager.history_depth()
	assert_true(MutationCommands.set_layer_property(sprite, "blendMode", original_blend + 1), "a production discrete command applies")
	assert_equal(UndoManager.history_depth(), depth_before + 1, "a discrete command adds one history entry")
	UndoManager.undo()
	await get_tree().process_frame
	assert_equal(sprite.blendMode, original_blend, "undo restores the pre-command value")
	UndoManager.redo()
	await get_tree().process_frame
	assert_equal(sprite.blendMode, original_blend + 1, "redo reapplies the command")
	UndoManager.undo()
	await get_tree().process_frame
	assert_equal(sprite.blendMode, original_blend, "the layer is left as it was found")

	# Unchanged writes must not accumulate history the user has to undo through.
	depth_before = UndoManager.history_depth()
	assert_false(MutationCommands.set_layer_property(sprite, "blendMode", original_blend), "re-writing the current value is not a change")
	assert_false(MutationCommands.structural(func(): return false), "a no-op structural command reports no change")
	assert_equal(UndoManager.history_depth(), depth_before, "no-op commands leave the history untouched")

	# Continuous gesture: one entry for the whole drag, fully reverted by one undo.
	var original_opacity: float = sprite.opacity
	MutationCommands.end_gesture()
	depth_before = UndoManager.history_depth()
	for step in [0.9, 0.8, 0.7, 0.6]:
		MutationCommands.drag_layer_property(sprite, "opacity", step, "slider")
	assert_equal(UndoManager.history_depth(), depth_before + 1, "a continuous drag produces one history entry")
	assert_approx(sprite.opacity, 0.6, 0.0001, "every drag step reaches the layer")
	UndoManager.undo()
	await get_tree().process_frame
	assert_approx(sprite.opacity, original_opacity, 0.0001, "one undo reverts the whole drag")
	MutationCommands.end_gesture()

	# Structural command: deleting a layer and restoring it rebuilds the scene.
	var doomed = Global.sprite_by_id(COSTUME_TWO_ID)
	if doomed != null:
		var count_before := Global.sprite_count()
		MutationCommands.structural(func():
			Global.unlinkChildren(doomed)
			doomed.queue_free()
			return true)
		Global.clear_selection()
		await get_tree().process_frame
		assert_equal(Global.sprite_count(), count_before - 1, "a structural delete command removes the layer")
		UndoManager.undo()
		await get_tree().process_frame
		assert_equal(Global.sprite_count(), count_before, "undo restores the deleted layer")
		assert_not_null(Global.sprite_by_id(COSTUME_TWO_ID), "the restored layer keeps its identity")

	# A restored child re-attaches to its parent in the same frame. Restore used
	# to lean on the sprite's deferred 0.1s reparent timer, which left the
	# hierarchy briefly wrong and outlived a short session.
	var nested = Global.sprite_by_id(NESTED_ID)
	if nested != null and nested.parentId != null:
		var parent_id = nested.parentId
		MutationCommands.structural(func():
			nested.queue_free()
			return true)
		Global.clear_selection()
		await get_tree().process_frame
		UndoManager.undo()
		var restored_child = Global.sprite_by_id(NESTED_ID)
		assert_not_null(restored_child, "undo restores the nested layer")
		if restored_child != null:
			assert_equal(restored_child.parentId, parent_id, "the restored child keeps its recorded parent")
			assert_not_null(restored_child.parentSprite, "the restored child is linked to its parent without waiting on a timer")
			if restored_child.parentSprite != null:
				assert_equal(restored_child.parentSprite.id, parent_id, "the restored child is linked to the right parent")
		await get_tree().process_frame

	# Undo must not resurrect a layer the user hid by hand: visibility is
	# re-derived through the layer policy, which reads userHidden.
	var hidden = Global.sprite_by_id(BASE_ID)
	if hidden != null:
		hidden.userHidden = true
		hidden.applyCostumeVisibility()
		assert_false(hidden.visible, "a hand-hidden layer starts hidden")
		MutationCommands.set_layer_property(hidden, "stretchAmount", hidden.stretchAmount + 1)
		UndoManager.undo()
		await get_tree().process_frame
		assert_false(hidden.visible, "undo leaves a hand-hidden layer hidden")
		hidden.userHidden = false
		hidden.applyCostumeVisibility()

	# The history stays bounded rather than growing without limit.
	for step in range(UndoManager.MAX_HISTORY + 10):
		MutationCommands.set_layer_property(sprite, "stretchAmount", float(step % 7) + 1.0)
	assert_true(UndoManager.history_depth() <= UndoManager.MAX_HISTORY, "history stays within its bound under sustained editing")

	# Every command above either reverted itself or restored what it removed, so
	# the avatar is left exactly as the earlier tests set it up.
	MutationCommands.end_gesture()
	_main.changeCostume(1)
	await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "the command history walk leaves the avatar intact")


# Phase 16: the z-index overlay moved out of the state singleton into its own
# component, so it is exercised as the real on-canvas widget it is.
func _test_z_index_editor() -> void:
	var sprite = Global.sprite_by_id(BASE_ID)
	if sprite == null:
		return
	Global.select_sprite(sprite)
	await get_tree().process_frame

	assert_false(Global.is_z_index_editor_active(), "the z-index overlay starts closed")
	Global._show_z_input()
	await get_tree().process_frame
	assert_true(Global.is_z_index_editor_active(), "the z-index overlay opens for a selected layer")
	assert_not_null(Global._z_editor, "opening the overlay constructs the real component")
	assert_true(Global._z_editor.visible, "the opened overlay is visible on the canvas")

	# A click well outside the panel dismisses it; a click on it does not.
	var centre: Vector2 = Global._z_editor.global_position
	assert_false(Global._z_editor.is_click_outside(centre), "a click on the panel is not a dismissal")
	assert_true(Global._z_editor.is_click_outside(centre + Vector2(400, 400)), "a click away from the panel dismisses it")

	# The field commits through the command layer, so the edit is undoable.
	var original_z: int = sprite.z
	var depth_before := UndoManager.history_depth()
	Global._z_editor._input_field.text = str(original_z + 3)
	Global._z_editor._apply()
	await get_tree().process_frame
	assert_equal(sprite.z, original_z + 3, "the overlay applies the entered depth")
	# The history may already sit at its bound from the command-history test, in
	# which case a new entry replaces the oldest rather than growing the stack.
	assert_equal(
		UndoManager.history_depth(), mini(depth_before + 1, UndoManager.MAX_HISTORY),
		"the overlay commits one undoable command",
	)
	UndoManager.undo()
	await get_tree().process_frame
	assert_equal(sprite.z, original_z, "undo restores the previous depth")

	# Re-entering the same value is not a change and must not add history.
	depth_before = UndoManager.history_depth()
	Global._z_editor._input_field.text = str(sprite.z)
	Global._z_editor._apply()
	assert_equal(UndoManager.history_depth(), depth_before, "re-entering the current depth adds no history")

	Global._hide_z_input()
	await get_tree().process_frame
	assert_false(Global.is_z_index_editor_active(), "the overlay closes on request")
	assert_false(Global._z_editor.visible, "the closed overlay leaves the canvas")


func _test_rejected_load_preserves_avatar() -> void:
	var previous_origin = _main.origin
	var previous_base = Global.sprite_by_id(BASE_ID)
	await _main.load_avatar_file(INVALID_FIXTURE)
	await get_tree().process_frame
	assert_true(_main.origin == previous_origin, "schema rejection preserves the current avatar root")
	assert_true(Global.sprite_by_id(BASE_ID) == previous_base, "schema rejection preserves the current sprite instances")
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "schema rejection preserves the current sprite registry")


func _test_save_load_round_trip() -> void:
	var round_trip_path := OS.get_temp_dir().path_join("pngtuberplus-avatar-scene-%d.save" % OS.get_process_id())
	var data: Dictionary = _main._build_avatar_save_data()
	for key in data:
		AvatarSaveControllerScript._encode_entry_images(data[key])
	Saving.data = data
	assert_true(Saving.write_save(round_trip_path), "production avatar state writes through the persistence boundary")
	if not FileAccess.file_exists(round_trip_path):
		_fail("round-trip avatar file was not created")
		return

	await _main.load_avatar_file(round_trip_path)
	await get_tree().process_frame
	_test_loaded_avatar("save/load round trip")
	_main.changeCostume(10)
	await get_tree().process_frame
	var costume_ten = Global.sprite_by_id(4000000011)
	assert_true(costume_ten != null and costume_ten.is_visible_in_tree(), "round-trip load preserves costume ten membership")
	_remove_temp_file(round_trip_path)


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
		_fail("%s (expected %s +/- %s, got %s)" % [message, expected, tolerance, actual])


func assert_not_null(value: Variant, message: String) -> void:
	assertions += 1
	if value == null:
		_fail(message)


func _fail(message: String) -> void:
	failures += 1
	printerr("  Avatar scene assertion failed: ", message)


# Legacy full-canvas rigs: a padded layer replaced by a cropped PSD layer has to
# keep its artwork on exactly the same screen pixels. Verified through a marker
# pixel rather than through `offset`, so the assertion fails if any part of the
# pivot, origin or crop arithmetic drifts.
func _test_legacy_canvas_replacement() -> void:
	var canvas := Vector2(64, 48)
	var marker := Vector2i(40, 12)
	var full := Image.create(int(canvas.x), int(canvas.y), false, Image.FORMAT_RGBA8)
	full.fill(Color(0, 0, 0, 0))
	full.set_pixelv(marker, Color.WHITE)

	var layer = _main.avatar_controller.add_image_from_data(full, "Legacy Canvas Layer", Vector2(30, -12))
	await get_tree().process_frame
	assert_not_null(layer, "the legacy placement fixture layer enters the rig")
	if layer == null:
		return
	assert_equal(Vector2(layer.size), canvas, "the fixture layer carries the full legacy canvas")

	# A user-placed origin: the correction has to survive one, since it is exactly
	# what the pivot arithmetic is anchored on.
	layer.offset = Vector2(5, -7)
	layer.sprite.offset = layer.offset
	var placed_position: Vector2 = layer.position
	var before: Vector2 = layer.dragOrigin.to_global(layer._tex_to_local(Vector2(marker)))

	# The same marker, cropped to its own bounds the way a PSD layer arrives.
	var crop_origin := Vector2i(36, 8)
	var crop := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	crop.fill(Color(0, 0, 0, 0))
	crop.set_pixelv(marker - crop_origin, Color.WHITE)
	var item_position := Vector2(crop_origin) + Vector2(4, 4) - canvas * 0.5
	var entry := {"sprite": layer, "name": "Legacy Canvas Layer", "image": crop, "position": item_position}

	_main.avatar_controller.apply_replacement([entry], [], [], false, canvas)
	var after: Vector2 = layer.dragOrigin.to_global(layer._tex_to_local(Vector2(marker - crop_origin)))
	assert_true(
		before.distance_to(after) < 0.001,
		"legacy compatibility placement holds the artwork on the same screen position (%s vs %s)" % [before, after],
	)
	assert_equal(layer.position, placed_position, "legacy compatibility placement never moves the layer node itself")
	assert_equal(Vector2(layer.size), Vector2(8, 8), "the replaced layer adopts the cropped image")

	# Without the compatibility canvas the same replacement collapses toward the
	# layer origin: the correction is opt-in, not a silent behaviour change.
	var plain := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	plain.fill(Color(0, 0, 0, 0))
	plain.set_pixelv(marker - crop_origin, Color.WHITE)
	var plain_offset: Vector2 = layer.offset
	_main.avatar_controller.apply_replacement(
		[{"sprite": layer, "name": "Legacy Canvas Layer", "image": plain, "position": item_position}],
		[], [], false, Vector2.ZERO,
	)
	assert_equal(layer.offset, plain_offset, "a replacement without the compatibility canvas leaves the origin untouched")

	layer.queue_free()
	Global.clear_selection()
	await get_tree().process_frame
	assert_equal(Global.sprite_count(), EXPECTED_SPRITES, "the legacy placement fixture layer is released")
