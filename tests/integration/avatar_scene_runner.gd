extends Node

const MAIN_SCENE := preload("res://main_scenes/main.tscn")
const AvatarSaveControllerScript = preload("res://main_scenes/controllers/save_controller.gd")

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

	_materialized_fixture_path = _materialize_regression_fixture()
	assert_false(_materialized_fixture_path.is_empty(), "regression fixture is materialized with an absolute image path")
	if _materialized_fixture_path.is_empty():
		get_tree().quit(1)
		return
	await _main._on_load_dialog_file_selected(_materialized_fixture_path)
	await get_tree().process_frame
	_test_loaded_avatar("fixture load")
	await _test_idle_motion()
	await _test_costumes()
	await _test_rejected_load_preserves_avatar()
	await _test_save_load_round_trip()

	if is_instance_valid(_main):
		_main.queue_free()
		await get_tree().process_frame
	_remove_temp_file(_materialized_fixture_path)
	print("[AVATAR SCENE] %d assertions, %d failures" % [assertions, failures])
	get_tree().quit(1 if failures > 0 else 0)


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
