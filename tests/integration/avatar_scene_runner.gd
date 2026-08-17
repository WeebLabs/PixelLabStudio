extends Node

const MAIN_SCENE := preload("res://main_scenes/main.tscn")
const AvatarSaveControllerScript = preload("res://main_scenes/controllers/save_controller.gd")
const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

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
	await _main._on_load_dialog_file_selected(_materialized_fixture_path)
	await get_tree().process_frame
	_test_loaded_avatar("fixture load")
	await _test_sidebar_selection_state()
	await _test_edit_commands()
	await _test_idle_motion()
	await _test_costumes()
	await _test_command_history()
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


func _test_idle_motion() -> void:
	var base = Global.sprite_by_id(BASE_ID)
	if base == null:
		return
	var start_y: float = base.get_node("WobbleOrigin").position.y
	for _frame in range(8):
		await get_tree().process_frame
	var moved_y: float = base.get_node("WobbleOrigin").position.y
	assert_true(absf(moved_y - start_y) > 0.1, "migrated idle sway produces visible runtime motion")


func _test_edit_commands() -> void:
	var source = Global.sprite_by_id(COSTUME_ONE_ID)
	assert_not_null(source, "duplicate command source exists")
	if source == null:
		return
	Global.select_sprite(source)
	_main._on_duplicate_button_pressed()
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


func _test_rejected_load_preserves_avatar() -> void:
	var previous_origin = _main.origin
	var previous_base = Global.sprite_by_id(BASE_ID)
	await _main._on_load_dialog_file_selected(INVALID_FIXTURE)
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

	await _main._on_load_dialog_file_selected(round_trip_path)
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
