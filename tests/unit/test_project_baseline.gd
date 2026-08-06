extends RefCounted

const REQUIRED_AUTOLOADS := ["Saving", "Global", "DefaultAvatarData", "UndoManager"]
const SCAN_ROOTS := ["autoload", "effects", "main_scenes", "ndi", "ui_scenes"]

func run(t) -> void:
	var version := Engine.get_version_info()
	t.assert_equal(int(version["major"]), 4, "tests run on Godot major version 4")
	t.assert_equal(int(version["minor"]), 6, "tests run on the Godot 4.6 compatibility line")

	var source_root := _source_root()
	t.assert_true(source_root.is_absolute_path(), "the test harness receives an absolute source root")
	var project_config := ConfigFile.new()
	t.assert_equal(project_config.load(source_root.path_join("project.godot")), OK, "the production project configuration loads")
	t.assert_equal(
		project_config.get_value("application", "run/main_scene"),
		"res://main_scenes/main.tscn",
		"the documented main scene is configured"
	)

	var features: PackedStringArray = project_config.get_value("application", "config/features", PackedStringArray())
	t.assert_true(features.has("4.6"), "project features declare Godot 4.6")
	for autoload_name in REQUIRED_AUTOLOADS:
		t.assert_true(project_config.has_section_key("autoload", autoload_name), "autoload %s is configured" % autoload_name)
		var resource_path: String = String(project_config.get_value("autoload", autoload_name)).trim_prefix("*").trim_prefix("res://")
		t.assert_true(FileAccess.file_exists(source_root.path_join(resource_path)), "autoload %s points to an existing resource" % autoload_name)

	t.assert_false(DirAccess.dir_exists_absolute(source_root.path_join("godot-ndi")), "only addons/godot-ndi may provide the NDI extension")
	t.assert_true(FileAccess.file_exists(source_root.path_join("addons/godot-ndi/godot-ndi.gdextension")), "the canonical NDI extension exists")
	t.assert_false(DirAccess.dir_exists_absolute(source_root.path_join("addons/godot-git-plugin")), "the obsolete native Git editor plugin is not bundled")
	for build_artifact in [
		"addons/psd-native/.sconsign.dblite",
		"addons/psd-native/src/psd_native.os",
		"addons/psd-native/src/register_types.os",
	]:
		t.assert_false(_is_tracked_source(source_root, build_artifact), "native build artifact is ignored: %s" % build_artifact)

	var source_files: Array[String] = []
	for root in SCAN_ROOTS:
		source_files.append_array(_collect_files(source_root.path_join(root), ["gd", "tscn", "gdshader"]))
	t.assert_true(source_files.size() >= 50, "the baseline audit covers the complete first-party source tree")
	for path in source_files:
		t.assert_true(FileAccess.file_exists(path), "source inventory entry exists: %s" % path)

func _collect_files(root: String, extensions: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path: String = root.path_join(entry)
			if dir.current_is_dir():
				result.append_array(_collect_files(path, extensions))
			elif extensions.has(entry.get_extension().to_lower()):
				result.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	result.sort()
	return result

func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""

func _is_tracked_source(source_root: String, relative_path: String) -> bool:
	# Build outputs can exist locally after compilation; the source contract is
	# represented by the ignore policy rather than their physical presence.
	var ignore_source := FileAccess.get_file_as_string(source_root.path_join(".gitignore"))
	var extension := relative_path.get_extension()
	if relative_path.ends_with(".sconsign.dblite"):
		return not ignore_source.contains(".sconsign.dblite")
	return not ignore_source.contains("*.%s" % extension)
