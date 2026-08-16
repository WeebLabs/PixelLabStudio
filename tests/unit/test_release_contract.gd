extends RefCounted

const SOURCE_ROOTS := ["autoload", "effects", "main_scenes", "ndi", "ui_scenes"]
const COMPACT_SCENES := [
	"main_scenes/main.tscn",
	"ui_scenes/spriteEditMenu/sprite_viewer.tscn",
	"ui_scenes/settings/settings_menu.tscn",
	"ui_scenes/spriteList/sprite_list_object.tscn",
]
const REQUIRED_EXPORT_PATTERNS := [
	"autoload/persistence/*.gd",
	"autoload/runtime/*.gd",
	"main_scenes/controllers/*.gd",
	"ndi/*.gd",
	"ui_scenes/microphoneSelect/*",
	"ui_scenes/selectedSprite/*",
	"ui_scenes/spriteList/*.svg",
	"addons/godot-streamdeck-addon/*.gd",
]


func run(t) -> void:
	var source_root := _source_root()
	_test_product_metadata(t, source_root)
	_test_export_presets(t, source_root)
	_test_native_manifests(t, source_root)
	_test_cleanup_contract(t, source_root)
	_test_terminology_and_optional_native_input(t, source_root)
	_test_maintainer_documentation(t, source_root)


func _test_product_metadata(t, source_root: String) -> void:
	var project := ConfigFile.new()
	t.assert_equal(project.load(source_root.path_join("project.godot")), OK, "release project configuration loads")
	t.assert_equal(project.get_value("application", "config/name"), "PixelLab Studio", "product name is explicit")
	t.assert_equal(project.get_value("application", "config/version"), "1.7.0a", "product version is explicit")
	var features: PackedStringArray = project.get_value("application", "config/features", PackedStringArray())
	t.assert_true(features.has("4.6"), "release metadata remains on the Godot 4.6 feature line")


func _test_export_presets(t, source_root: String) -> void:
	var presets := ConfigFile.new()
	t.assert_equal(presets.load(source_root.path_join("export_presets.cfg")), OK, "export presets load")
	var expected := [
		["Windows Desktop", "Windows Desktop", ".artifacts/exports/windows/PixelLab Studio.exe"],
		["Linux/X11", "Linux", ".artifacts/exports/linux/PixelLab Studio.x86_64"],
		["macOS", "macOS", ".artifacts/exports/macos/PixelLab Studio.zip"],
	]
	for index in range(expected.size()):
		var section := "preset.%d" % index
		t.assert_equal(presets.get_value(section, "name"), expected[index][0], "preset %d has the expected name" % index)
		t.assert_equal(presets.get_value(section, "platform"), expected[index][1], "preset %d targets the expected platform" % index)
		t.assert_equal(presets.get_value(section, "export_filter"), "scenes", "preset %d does not sweep developer files into releases" % index)
		var files: PackedStringArray = presets.get_value(section, "export_files", PackedStringArray())
		t.assert_equal(files, PackedStringArray(["res://main_scenes/main.tscn"]), "preset %d exports the production entry scene" % index)
		var include_filter: String = presets.get_value(section, "include_filter", "")
		for pattern in REQUIRED_EXPORT_PATTERNS:
			t.assert_true(include_filter.split(",").has(pattern), "preset %d explicitly includes indirect runtime dependency %s" % [index, pattern])
		t.assert_false(include_filter.contains("ui_scenes/light"), "preset %d excludes dormant untracked light work" % index)
		t.assert_equal(presets.get_value(section, "export_path"), expected[index][2], "preset %d writes below the ignored artifact directory" % index)

	t.assert_equal(presets.get_value("preset.0.options", "application/product_version"), "1.7.0.0", "Windows product version matches the application")
	t.assert_equal(presets.get_value("preset.2.options", "application/bundle_identifier"), "com.weeblabs.pixellabstudio", "macOS bundle identifier is stable")
	t.assert_true(String(presets.get_value("preset.2.options", "privacy/microphone_usage_description", "")).contains("animate the avatar"), "macOS microphone purpose is user-facing")
	for script_path in ["scripts/run_export_smoke.sh", "scripts/run_release_checks.sh"]:
		t.assert_true(FileAccess.file_exists(source_root.path_join(script_path)), "release gate exists: %s" % script_path)


func _test_native_manifests(t, source_root: String) -> void:
	for relative_path in [
		"bin/gdexample.gdextension",
		"addons/godot-ndi/godot-ndi.gdextension",
		"addons/psd-native/psd_native.gdextension",
	]:
		var manifest_path := source_root.path_join(relative_path)
		var manifest := ConfigFile.new()
		t.assert_equal(manifest.load(manifest_path), OK, "native manifest loads: %s" % relative_path)
		var keys := manifest.get_section_keys("libraries")
		t.assert_true(keys.size() >= 2, "native manifest declares release/debug or platform libraries: %s" % relative_path)
		for key in keys:
			var library_path := String(manifest.get_value("libraries", key))
			var absolute_path := source_root.path_join(library_path.trim_prefix("res://")) if library_path.begins_with("res://") else manifest_path.get_base_dir().path_join(library_path)
			t.assert_true(FileAccess.file_exists(absolute_path), "native library mapping exists: %s -> %s" % [key, library_path])

	t.assert_true(FileAccess.file_exists(source_root.path_join("addons/godot-streamdeck-addon/LICENSE.md")), "Stream Deck addon ships its MIT license")
	var ndi_patch_path := source_root.path_join("addons/godot-ndi/patches/0001-fix-render-router-teardown.patch")
	t.assert_true(FileAccess.file_exists(ndi_patch_path), "the modified NDI binary ships its source patch")
	var ndi_patch := FileAccess.get_file_as_string(ndi_patch_path)
	t.assert_true(ndi_patch.contains("vptr->shutdown()") and ndi_patch.contains("std::atomic_bool shutting_down"), "the NDI patch records early quiescence and callback-safe lifetime")
	t.assert_equal(FileAccess.get_sha256(source_root.path_join("addons/godot-ndi/bin/macos/libgodot-ndi.macos.template_debug.universal.dylib")), "7bed10a7eecc2c07b3815d4db2f7c27581d6a5481683961373179f2deff1538a", "the patched macOS NDI debug binary matches its audited build")
	t.assert_equal(FileAccess.get_sha256(source_root.path_join("addons/godot-ndi/bin/macos/libgodot-ndi.macos.template_release.universal.dylib")), "4fc04977156eacdf7b048b5aaf87a1a0095f5ff04458f1a7313d80bf74663f42", "the patched macOS NDI release binary matches its audited build")
	t.assert_true(FileAccess.file_exists(source_root.path_join("scripts/run_ndi_teardown_smoke.sh")), "the macOS NDI native teardown regression gate is available")


func _test_cleanup_contract(t, source_root: String) -> void:
	t.assert_false(DirAccess.dir_exists_absolute(source_root.path_join("addons/godot-ndi/demo")), "NDI demonstration media is not shipped with the application")
	var ignore_source := FileAccess.get_file_as_string(source_root.path_join(".gitignore"))
	t.assert_true(ignore_source.contains("*.exp"), "Windows linker export intermediates are ignored")
	t.assert_true(ignore_source.contains("*.lib"), "Windows linker import libraries are ignored")
	for relative_path in COMPACT_SCENES:
		var path := source_root.path_join(relative_path)
		var source := FileAccess.get_file_as_string(path)
		t.assert_false(source.contains("cache/0/"), "scene does not contain generated font glyph cache: %s" % relative_path)
		t.assert_false(source.contains("glyphs/"), "scene does not contain generated glyph data: %s" % relative_path)
		var file := FileAccess.open(path, FileAccess.READ)
		t.assert_true(file != null and file.get_length() < 1024 * 1024, "scene remains reviewable and below 1 MiB: %s" % relative_path)
		if file != null:
			file.close()


func _test_terminology_and_optional_native_input(t, source_root: String) -> void:
	var sources: Array[String] = []
	for root in SOURCE_ROOTS:
		sources.append_array(_collect_files(source_root.path_join(root), ["gd", "tscn", "gdshader"]))
	var joined := ""
	for path in sources:
		joined += FileAccess.get_file_as_string(path)
	t.assert_false(joined.contains("fatfuckingballs"), "legacy visibility signal name is removed from first-party source")
	t.assert_false(joined.contains("\"penis\""), "legacy input-blocker group name is removed from first-party source")
	t.assert_true(joined.contains("visibility_binding_armed"), "visibility binding uses an intention-revealing signal name")
	t.assert_true(joined.contains("canvas_input_blocker"), "modal hit areas use an intention-revealing group name")

	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var main_scene := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.tscn"))
	t.assert_true(main_source.contains("ClassDB.class_exists(\"BackgroundInputCapture\")"), "background capture checks the optional native class before instantiation")
	t.assert_true(main_source.contains("ClassDB.instantiate(\"BackgroundInputCapture\")"), "background capture is instantiated dynamically")
	t.assert_false(main_scene.contains("type=\"BackgroundInputCapture\""), "the production scene loads without the optional native input extension")
	var save_controller := FileAccess.get_file_as_string(source_root.path_join("main_scenes/controllers/save_controller.gd"))
	t.assert_true(save_controller.count("*.save;PNGTuberPlus Avatar") >= 2, "native save and load dialogs use the documented avatar extension")
	var saving_source := FileAccess.get_file_as_string(source_root.path_join("autoload/saving.gd"))
	t.assert_true(saving_source.contains("--release-smoke") and saving_source.contains("begin_isolated_session()"), "release smoke isolates settings before other autoloads start")
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	t.assert_true(global_source.contains("not OS.get_cmdline_user_args().has(\"--release-smoke\")"), "release smoke does not open the host microphone")


func _test_maintainer_documentation(t, source_root: String) -> void:
	for relative_path in [
		"CONTRIBUTING.md",
		"docs/architecture_guide.md",
		"docs/dependencies.md",
		"docs/quality_baseline.md",
		"docs/refactor_plan.md",
		"docs/save_format.md",
	]:
		t.assert_true(FileAccess.file_exists(source_root.path_join(relative_path)), "maintainer contract exists: %s" % relative_path)
	var architecture := FileAccess.get_file_as_string(source_root.path_join("docs/architecture_guide.md"))
	t.assert_true(architecture.contains("visibility_binding_armed"), "architecture map documents the renamed signal")
	t.assert_true(architecture.contains("User-facing file extension: `.save`"), "architecture map distinguishes avatar and internal persistence extensions")


func _collect_files(root: String, extensions: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := root.path_join(entry)
			if dir.current_is_dir():
				result.append_array(_collect_files(path, extensions))
			elif extensions.has(entry.get_extension().to_lower()):
				result.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	return result


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
