extends RefCounted

const SpriteStateDomain = preload("res://autoload/domain/sprite_state.gd")
const CollisionDomain = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")


class LegacyWobbleProbe:
	extends RefCounted
	var path := ""
	var id := 0
	var parentId: Variant = null
	var offset := Vector2.ZERO
	var xFrq := 0.0
	var xAmp := 0.0
	var yFrq := 0.0
	var yAmp := 0.0
	var animClips: Array = []
	var migration_calls := 0

	func migrateLegacyWobble() -> void:
		migration_calls += 1
		if xAmp != 0.0 or yAmp != 0.0:
			animClips.append({"ampX": xAmp, "freqX": xFrq, "ampY": yAmp, "freqY": yFrq})


func run(t) -> void:
	_test_persistent_property_contract(t)
	_test_structured_value_round_trip(t)
	_test_legacy_wobble_migration(t)
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


func _test_legacy_wobble_migration(t) -> void:
	var legacy := LegacyWobbleProbe.new()
	SpriteStateDomain.apply_before_ready(legacy, {
		"path": "legacy.png",
		"identification": 1,
		"parentId": null,
		"offset": "Vector2(0, 0)",
		"xFrq": 0.0,
		"xAmp": 0.0,
		"yFrq": 0.041,
		"yAmp": 11.0,
	})
	t.assert_equal(legacy.migration_calls, 1, "legacy loads invoke wobble migration when animClips is absent")
	t.assert_equal(legacy.animClips.size(), 1, "legacy sway becomes an animation clip")
	t.assert_approx(legacy.animClips[0]["ampY"], 11.0, 0.00001, "legacy sway amplitude is preserved")

	var modern := LegacyWobbleProbe.new()
	SpriteStateDomain.apply_before_ready(modern, {
		"path": "modern.png",
		"identification": 2,
		"parentId": null,
		"offset": "Vector2(0, 0)",
		"yFrq": 0.041,
		"yAmp": 11.0,
		"animClips": "[]",
	})
	t.assert_equal(modern.migration_calls, 0, "modern saves do not duplicate explicit animation state")


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

	_test_collision_shape_contract(t)


# The collider is a broad phase only: mouse_cursor._is_pixel_opaque decides every
# hit from the image alpha. So it has to CONTAIN the traced outlines (never clip
# them, or clicks that work today would stop working) while staying one shape,
# because a CollisionPolygon2D decomposes into pieces the broadphase re-fits on
# every tick the avatar moves. The traced outlines themselves are what the user
# sees around a selected layer and must survive untouched.
func _test_collision_shape_contract(t) -> void:
	# Two disjoint blocks, so the fixture traces more than one outline: with one
	# outline the collider count cannot tell the two implementations apart.
	var image := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(6, 26):
		for x in range(4, 22):
			image.set_pixel(x, y, Color.WHITE)
		for x in range(40, 58):
			image.set_pixel(x, y, Color.WHITE)
	var polygons := CollisionDomain.alpha_polygons(image)
	t.assert_true(polygons.size() > 1, "the fixture traces more than one outline")

	var area := Area2D.new()
	var bounds := Rect2(Vector2.ZERO, Vector2(image.get_size()))
	var added: bool = CollisionDomain.populate_polygons(area, _outline_scene(), polygons, bounds)
	t.assert_true(added, "tracing produced collision geometry")

	var colliders := 0
	var outlines := 0
	var shape: Shape2D = null
	var shape_position := Vector2.ZERO
	for child in area.get_children():
		if child is CollisionShape2D:
			colliders += 1
			shape = child.shape
			shape_position = child.position
		elif child is CollisionPolygon2D:
			colliders += 1
		elif child is Line2D:
			outlines += 1
	t.assert_equal(colliders, 1, "a layer carries exactly one collider, whatever its outline count")
	t.assert_true(shape is RectangleShape2D, "that collider is a rectangle, not a decomposed polygon")
	t.assert_equal(outlines, polygons.size(), "every traced outline is still drawn")

	# The bound must contain every traced point, or a click that lands today
	# would miss tomorrow.
	var rect := Rect2(shape_position - (shape as RectangleShape2D).size * 0.5, (shape as RectangleShape2D).size)
	var contained := true
	for polygon in polygons:
		for point in polygon:
			if not rect.has_point(point):
				contained = false
	t.assert_true(contained, "the collider contains every traced outline point")
	area.free()


func _outline_scene() -> PackedScene:
	var line := Line2D.new()
	var packed := PackedScene.new()
	packed.pack(line)
	line.free()
	return packed


func _test_shared_call_sites(t) -> void:
	var source_root := _source_root()
	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	var undo_source := FileAccess.get_file_as_string(source_root.path_join("autoload/undo_manager.gd"))
	var sprite_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/selectedSprite/spriteObject.gd"))
	t.assert_true(main_source.contains("SpriteState.capture_save"), "manual save uses the shared sprite-state map")
	t.assert_true(main_source.contains("SpriteState.apply_before_ready"), "avatar load uses the shared sprite-state map")
	t.assert_true(main_source.contains("spr.reparent(parent_sprite.sprite, false)"), "avatar hierarchy reconstruction preserves registry membership")
	t.assert_true(main_source.contains("SpriteState.copy_for_duplicate"), "sprite duplication uses the shared sprite-state map")
	t.assert_equal(main_source.count("func _next_sprite_id"), 1, "sprite IDs are allocated through one collision-checked path")
	t.assert_equal(main_source.count("RandomNumberGenerator.new()"), 1, "sprite creation reuses one randomized ID generator")
	t.assert_true(undo_source.contains("SpriteState.capture_snapshot"), "undo capture uses the shared sprite-state map")
	t.assert_true(undo_source.contains("SpriteState.apply_existing"), "undo restore uses the shared sprite-state map")
	t.assert_false(undo_source.contains("sprite.get_parent().remove_child(sprite)"), "undo reparenting does not unregister live sprites")
	t.assert_false(global_source.contains("heldSprite.get_parent().remove_child(heldSprite)"), "unlinking does not unregister live sprites")
	t.assert_false(undo_source.contains("sprite.wiggleStiffness = d"), "undo no longer carries a parallel wiggle property map")
	t.assert_true(sprite_source.contains("CollisionBuilder.alpha_polygons"), "sprite collision construction uses the shared geometry boundary")
	t.assert_false(sprite_source.contains("BitMap.new()"), "sprite object no longer rebuilds alpha geometry itself")
	t.assert_true(sprite_source.contains("func _enter_tree() -> void:"), "sprites expose a hierarchy re-entry lifecycle hook")
	t.assert_equal(sprite_source.count("Global.register_sprite(self)"), 1, "sprite registry enrollment has one lifecycle owner")
	t.assert_false(sprite_source.contains("get_parent().remove_child(self)"), "deferred parenting does not unregister live sprites")
	t.assert_equal(sprite_source.count("grabArea.monitorable = enable"), 1, "collision enablement performs one state write")


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
