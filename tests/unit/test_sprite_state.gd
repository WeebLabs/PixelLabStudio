extends RefCounted

const SpriteStateDomain = preload("res://autoload/domain/sprite_state.gd")
const CollisionDomain = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")


func run(t) -> void:
	_test_persistent_property_contract(t)
	_test_structured_value_round_trip(t)
	_test_costume_compatibility(t)
	_test_clone_ownership(t)
	_test_collision_geometry(t)
	_test_shared_call_sites(t)


func _test_persistent_property_contract(t) -> void:
	var keys := SpriteStateDomain.persistent_keys()
	var unique := {}
	for key in keys:
		unique[key] = true
	t.assert_equal(keys.size(), unique.size(), "sprite persistence keys are unique")
	for required_key in [
		"path", "identification", "parentId", "pos", "offset", "zindex",
		"ndiRefLayer", "normalPath", "animClips", "wiggleChildrenFollow",
		"blendMode", "opacity",
	]:
		t.assert_true(keys.has(required_key), "sprite state includes required key: " + required_key)


func _test_structured_value_round_trip(t) -> void:
	var path := PackedVector2Array([Vector2(1, 2), Vector2(3, 4)])
	var encoded_path: Variant = SpriteStateDomain.encode_structured("wigglePath", path, true)
	var decoded_path: PackedVector2Array = SpriteStateDomain.decode_structured("wigglePath", encoded_path)
	t.assert_equal(decoded_path, path, "wiggle paths survive the shared serialized representation")

	var widths := PackedFloat32Array([2.5, 9.0])
	var encoded_widths: Variant = SpriteStateDomain.encode_structured("wigglePathWidths", widths, true)
	var decoded_widths: PackedFloat32Array = SpriteStateDomain.decode_structured("wigglePathWidths", encoded_widths)
	t.assert_equal(decoded_widths, widths, "wiggle widths survive the shared serialized representation")

	var clips := [{"name": "Idle", "keys": [{"time": 0.0}]}]
	var decoded_clips: Array = SpriteStateDomain.decode_structured(
		"animClips",
		SpriteStateDomain.encode_structured("animClips", clips, true),
	)
	t.assert_equal(decoded_clips, clips, "animation clips survive the shared serialized representation")
	decoded_clips[0]["name"] = "Changed"
	t.assert_equal(clips[0]["name"], "Idle", "decoded animation clips do not alias their source")


func _test_costume_compatibility(t) -> void:
	var legacy := SpriteStateDomain.normalize_costume_layers([0, 1, 0])
	t.assert_equal(legacy.size(), 10, "legacy costume membership expands to ten slots")
	t.assert_equal(legacy.slice(0, 3), [0, 1, 0], "legacy costume membership preserves existing slots")
	t.assert_equal(legacy.slice(3), [1, 1, 1, 1, 1, 1, 1], "new costume slots default visible")
	var oversized := SpriteStateDomain.normalize_costume_layers([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
	t.assert_equal(oversized.size(), 10, "costume membership is bounded to supported slots")


func _test_clone_ownership(t) -> void:
	var source := {"nested": [{"value": 1}]}
	var clone: Dictionary = SpriteStateDomain.clone_value(source)
	clone["nested"][0]["value"] = 2
	t.assert_equal(source["nested"][0]["value"], 1, "sprite-state dictionaries are deep-cloned")


func _test_collision_geometry(t) -> void:
	var square_sheet := CollisionDomain.fallback_frame_rect(Vector2(800, 200), 4)
	t.assert_equal(square_sheet.size, Vector2(200, 200), "animated fallback collision uses one frame, not the full sheet")
	var rectangular_sheet := CollisionDomain.fallback_frame_rect(Vector2(600, 200), 4)
	t.assert_equal(rectangular_sheet.size, Vector2(150, 200), "fallback collision preserves non-square frame dimensions")
	var invalid_frames := CollisionDomain.fallback_frame_rect(Vector2(20, 10), 0)
	t.assert_equal(invalid_frames.size, Vector2(20, 10), "fallback collision guards invalid frame counts")

	var opaque := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	opaque.fill(Color.WHITE)
	t.assert_true(not CollisionDomain.alpha_polygons(opaque).is_empty(), "opaque images produce selectable collision geometry")
	var transparent := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	transparent.fill(Color.TRANSPARENT)
	t.assert_true(CollisionDomain.alpha_polygons(transparent).is_empty(), "transparent images request fallback collision geometry")


func _test_shared_call_sites(t) -> void:
	var source_root := _source_root()
	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var undo_source := FileAccess.get_file_as_string(source_root.path_join("autoload/undo_manager.gd"))
	var sprite_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/selectedSprite/spriteObject.gd"))
	t.assert_true(main_source.contains("SpriteState.capture_save"), "manual save uses the shared sprite-state map")
	t.assert_true(main_source.contains("SpriteState.apply_before_ready"), "avatar load uses the shared sprite-state map")
	t.assert_true(main_source.contains("SpriteState.copy_for_duplicate"), "sprite duplication uses the shared sprite-state map")
	t.assert_equal(main_source.count("func _next_sprite_id"), 1, "sprite IDs are allocated through one collision-checked path")
	t.assert_equal(main_source.count("RandomNumberGenerator.new()"), 1, "sprite creation reuses one randomized ID generator")
	t.assert_true(undo_source.contains("SpriteState.capture_snapshot"), "undo capture uses the shared sprite-state map")
	t.assert_true(undo_source.contains("SpriteState.apply_existing"), "undo restore uses the shared sprite-state map")
	t.assert_false(undo_source.contains("sprite.wiggleStiffness = d"), "undo no longer carries a parallel wiggle property map")
	t.assert_true(sprite_source.contains("CollisionBuilder.alpha_polygons"), "sprite collision construction uses the shared geometry boundary")
	t.assert_false(sprite_source.contains("BitMap.new()"), "sprite object no longer rebuilds alpha geometry itself")
	t.assert_equal(sprite_source.count("grabArea.monitorable = enable"), 1, "collision enablement performs one state write")


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
