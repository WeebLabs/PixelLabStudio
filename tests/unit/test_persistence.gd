extends RefCounted

const JsonStore = preload("res://autoload/persistence/json_file_store.gd")
const Settings = preload("res://autoload/persistence/settings_schema.gd")
const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")
const ValueCodec = preload("res://autoload/persistence/value_codec.gd")
const DefaultAvatar = preload("res://autoload/defaultAvatarData.gd")


func run(t) -> void:
	_test_value_codec(t)
	_test_settings_migration(t)
	_test_avatar_migration(t)
	_test_unsigned_sprite_identifiers(t)
	_test_costume_membership_round_trip(t)
	_test_bundled_avatar(t)
	_test_schema_rejections(t)
	_test_atomic_round_trip_and_recovery(t)


func _test_value_codec(t) -> void:
	t.assert_equal(ValueCodec.vector2_value("Vector2(12, -3)"), Vector2(12, -3), "legacy Vector2 strings decode")
	t.assert_equal(ValueCodec.vector2_value("Object(unsafe)", Vector2(7, 8)), Vector2(7, 8), "unexpected Variant syntax is not parsed")
	t.assert_equal(ValueCodec.color_value("not a color", Color.RED), Color.RED, "malformed colors use a typed fallback")
	t.assert_equal(ValueCodec.array_value("[1, 2, 3]"), [1, 2, 3], "legacy array strings decode")
	t.assert_equal(ValueCodec.array_value("Array[int]([0, 1, 0])"), [0, 1, 0], "typed integer array strings decode")
	t.assert_equal(ValueCodec.array_value("Resource(\"x\")", [9]), [9], "non-array Variant text is rejected")


func _test_settings_migration(t) -> void:
	var parsed: Variant = _read_fixture("res://tests/fixtures/settings_v0.json")
	var normalized := Settings.normalize(parsed)
	t.assert_true(normalized["ok"], "legacy settings normalize")
	var settings: Dictionary = normalized["value"]
	t.assert_equal(settings["_schemaVersion"], Settings.CURRENT_VERSION, "settings gain the current schema version")
	t.assert_approx(settings["volume"], 1.0, 0.00001, "volume is clamped to its supported range")
	t.assert_approx(settings["sense"], 0.4, 0.00001, "numeric setting strings migrate")
	t.assert_equal(ValueCodec.vector2i_value(settings["windowSize"]), Vector2i(1440, 900), "legacy Vector2 window sizes become Vector2i strings")
	t.assert_equal(settings["costumeKeys"].size(), 10, "short legacy costume arrays are expanded")
	t.assert_equal(settings["costumeKeys"][0], "A", "existing costume bindings are preserved")
	t.assert_equal(settings["recordingFormat"], "webm", "unsupported recording formats use the safe default")
	t.assert_equal(settings["ndiCropRect"], Settings.defaults()["ndiCropRect"], "invalid crop geometry uses the safe default")
	t.assert_true(settings["futureIntegrationSetting"]["preserved"], "unknown settings survive migration")
	var ruler_migration: Dictionary = Settings.normalize({"ndiRulerY": 300})["value"]
	t.assert_equal(ruler_migration["ndiCropRect"], [-500.0, -700.0, 500.0, 300.0], "legacy NDI ruler settings migrate to a crop rectangle")
	t.assert_false(Settings.normalize([])["ok"], "non-object settings are rejected")


func _test_avatar_migration(t) -> void:
	var parsed: Variant = _read_fixture("res://tests/fixtures/avatar_v0.json")
	var normalized := AvatarSave.normalize(parsed)
	t.assert_true(normalized["ok"], "legacy avatars normalize")
	t.assert_true(normalized["migrated"], "unversioned avatars are reported as migrated")
	t.assert_equal(normalized["sprite_count"], 2, "all legacy sprite layers remain present")
	var avatar: Dictionary = normalized["value"]
	t.assert_equal(avatar["_schemaVersion"], AvatarSave.CURRENT_VERSION, "avatars gain the current schema version")
	t.assert_equal(avatar["0"]["opacity"], 1.0, "new sprite properties receive compatibility defaults")
	t.assert_equal(ValueCodec.vector2_value(avatar["1"]["pos"]), Vector2(0, -100), "sprite transforms round-trip through canonical text")
	t.assert_equal(avatar["_ndiRulerY"], 240.0, "legacy NDI ruler metadata remains available")

	var second_pass := AvatarSave.normalize(JSON.parse_string(JSON.stringify(avatar)))
	t.assert_true(second_pass["ok"], "normalized avatar JSON loads again")
	t.assert_false(second_pass["migrated"], "current avatar data does not re-run migrations")
	t.assert_equal(second_pass["value"], avatar, "avatar normalization is idempotent")


func _test_unsigned_sprite_identifiers(t) -> void:
	var parent_id := 4226717595
	var child_id := 4000000001
	var source := {
		"0": {"type": "sprite", "path": "parent.png", "identification": parent_id},
		"1": {
			"type": "sprite",
			"path": "child.png",
			"identification": child_id,
			"parentId": parent_id,
			"eyeTrackTargetId": parent_id,
		},
	}
	var parsed_again: Variant = JSON.parse_string(JSON.stringify(source))
	var normalized := AvatarSave.normalize(parsed_again)
	t.assert_true(normalized["ok"], "distinct unsigned 32-bit sprite identifiers remain loadable")
	if not normalized["ok"]:
		return
	var avatar: Dictionary = normalized["value"]
	t.assert_equal(avatar["0"]["identification"], parent_id, "large parent identifiers are preserved")
	t.assert_equal(avatar["1"]["identification"], child_id, "large child identifiers are preserved")
	t.assert_equal(avatar["1"]["parentId"], parent_id, "large parent references are preserved")
	t.assert_equal(avatar["1"]["eyeTrackTargetId"], parent_id, "large eye-tracking references are preserved")


func _test_costume_membership_round_trip(t) -> void:
	var expected := [0, 1, 0, 0, 0, 0, 0, 0, 0, 0]
	var source := {
		"0": {
			"type": "sprite",
			"path": "legacy-costume.png",
			"identification": 1,
			"costumeLayers": "[0, 1, 0, 0, 0, 0, 0, 0, 0, 0]",
		},
		"1": {
			"type": "sprite",
			"path": "typed-costume.png",
			"identification": 2,
			"costumeLayers": "Array[int]([0, 1, 0, 0, 0, 0, 0, 0, 0, 0])",
		},
	}
	var normalized := AvatarSave.normalize(source)
	t.assert_true(normalized["ok"], "legacy and typed costume membership encodings normalize")
	if not normalized["ok"]:
		return
	for key in ["0", "1"]:
		var encoded: String = normalized["value"][key]["costumeLayers"]
		t.assert_true(encoded.begins_with("["), "costume membership uses canonical plain-array text")
		t.assert_equal(ValueCodec.array_value(encoded), expected, "disabled costume slots survive normalization")


func _test_bundled_avatar(t) -> void:
	var default_avatar := DefaultAvatar.new()
	var normalized := AvatarSave.normalize(default_avatar.data)
	t.assert_true(normalized["ok"], "the bundled default avatar conforms to the current migration boundary")
	t.assert_equal(normalized["sprite_count"], default_avatar.data.size(), "default avatar migration preserves every bundled layer")
	default_avatar.free()


func _test_schema_rejections(t) -> void:
	t.assert_false(AvatarSave.normalize([])["ok"], "non-object avatar roots are rejected")
	t.assert_false(AvatarSave.normalize({"_schemaVersion": AvatarSave.CURRENT_VERSION + 1, "0": {}})["ok"], "future schemas fail with an actionable compatibility error")
	t.assert_false(AvatarSave.normalize({"0": "not an entry"})["ok"], "non-object sprite entries are rejected")
	var duplicate_ids := {
		"0": {"type": "sprite", "path": "a.png", "identification": 4},
		"1": {"type": "sprite", "path": "b.png", "identification": 4},
	}
	t.assert_false(AvatarSave.normalize(duplicate_ids)["ok"], "duplicate sprite identifiers are rejected before scene teardown")
	var no_path := {"0": {"type": "sprite", "identification": 1}}
	t.assert_false(AvatarSave.normalize(no_path)["ok"], "sprite entries without an image path are rejected")
	var cyclic := {
		"0": {"type": "sprite", "path": "a.png", "identification": 1, "parentId": 2},
		"1": {"type": "sprite", "path": "b.png", "identification": 2, "parentId": 1},
	}
	t.assert_false(AvatarSave.normalize(cyclic)["ok"], "cyclic parent relationships are rejected before scene construction")


func _test_atomic_round_trip_and_recovery(t) -> void:
	var path := "user://phase1-persistence-test.json"
	_cleanup(path)
	var first := JsonStore.write_document_atomic(path, {"revision": 1, "nested": {"safe": true}})
	t.assert_true(first["ok"], "atomic JSON write succeeds")
	var second := JsonStore.write_document_atomic(path, {"revision": 2})
	t.assert_true(second["ok"], "atomic JSON replacement succeeds")
	var loaded := JsonStore.read_document(path)
	t.assert_true(loaded["ok"], "atomically written JSON reads")
	t.assert_equal(loaded["value"]["revision"], 2, "replacement exposes the complete new document")
	t.assert_false(FileAccess.file_exists(path + ".tmp"), "successful writes leave no temporary file")

	var backup := FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string("{\"revision\":3}\n")
	backup.close()
	var primary := FileAccess.open(path, FileAccess.WRITE)
	primary.store_string("{broken")
	primary.close()
	var recovered := JsonStore.read_document(path)
	t.assert_true(recovered["ok"], "a valid backup recovers a torn primary write")
	t.assert_equal(recovered["value"]["revision"], 3, "backup recovery returns the previous complete document")
	t.assert_true(recovered.has("recovered_from"), "backup recovery is explicitly reported")

	var malformed := FileAccess.open(path, FileAccess.WRITE)
	malformed.store_string("[1, 2, 3]")
	malformed.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	var wrong_root := JsonStore.read_document(path)
	t.assert_false(wrong_root["ok"], "unexpected JSON root types are rejected")
	_cleanup(path)

	var blocker_path := "user://phase1-persistence-blocker"
	_cleanup(blocker_path)
	var blocker := FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("this path is a file, not a directory")
	blocker.close()
	var failed_write := JsonStore.write_document_atomic(blocker_path.path_join("child.json"), {"value": 1})
	t.assert_false(failed_write["ok"], "write failures return a structured error")
	t.assert_true(String(failed_write["error"]).length() > 0, "write failures include an actionable message")
	_cleanup(blocker_path)


func _read_fixture(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cleanup(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var candidate: String = path + str(suffix)
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
