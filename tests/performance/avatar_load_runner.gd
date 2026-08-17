extends Node

const MAIN_SCENE := preload("res://main_scenes/main.tscn")

# Broad smoke ceilings protect CI from accidental algorithmic regressions. The
# exact artifact is the useful trend line; these are not optimization targets.
const MAX_LOAD_100_MS := 5000.0
const MAX_LOAD_250_MS := 12000.0

var _main: Node2D = null
var _temporary_paths: Array[String] = []
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Saving.is_isolated_session():
		_failures.append("production load benchmark did not start in an isolated session")
		await _finish({})
		return

	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var results := {
		"engine": Engine.get_version_info()["string"],
		"platform": OS.get_name(),
		"processor": OS.get_processor_name(),
		"loads": {},
		"budgets_ms": {"100": MAX_LOAD_100_MS, "250": MAX_LOAD_250_MS},
	}
	for layer_count in [100, 250]:
		var fixture_path := _write_fixture(layer_count)
		if fixture_path.is_empty():
			_failures.append("could not create %d-layer load fixture" % layer_count)
			continue
		var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var started := Time.get_ticks_usec()
		await _main._on_load_dialog_file_selected(fixture_path)
		await get_tree().process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
		var registered := Global.sprite_count()
		results["loads"][str(layer_count)] = {
			"total_ms": elapsed_ms,
			"registered_sprites": registered,
			"static_memory_before_bytes": memory_before,
			"static_memory_after_bytes": memory_after,
			"static_memory_delta_bytes": memory_after - memory_before,
		}
		if registered != layer_count:
			_failures.append("%d-layer load registered %d sprites" % [layer_count, registered])
		var maximum := MAX_LOAD_100_MS if layer_count == 100 else MAX_LOAD_250_MS
		if elapsed_ms > maximum:
			_failures.append("%d-layer load %.2f ms exceeded %.2f ms" % [layer_count, elapsed_ms, maximum])

	results["passed"] = _failures.is_empty()
	await _finish(results)


func _write_fixture(layer_count: int) -> String:
	var image_path := ProjectSettings.globalize_path("res://test/testBody.png")
	var data := {"_schemaVersion": 1, "_eyeTrackingGloballyEnabled": true}
	for index in range(layer_count):
		data[str(index)] = {
			"type": "sprite",
			"path": image_path,
			"identification": 3000000000 + index,
			"parentId": 3000000000 + index - 1 if index > 0 and index % 5 != 0 else null,
			"pos": var_to_str(Vector2(index % 20, -(index % 30))),
			"offset": "Vector2(0, 0)",
			"zindex": index,
			"costumeLayers": "[1, 1, 1, 1, 1, 1, 1, 1, 1, 1]",
			"animClips": "[]",
			"ndiRefLayer": index == 0,
		}
	var path := OS.get_temp_dir().path_join("pngtuberplus-load-%d-%d.json" % [layer_count, OS.get_process_id()])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data))
	file.close()
	_temporary_paths.append(path)
	return path


func _finish(results: Dictionary) -> void:
	for failure in _failures:
		printerr("[AVATAR LOAD PERF] ", failure)
	var output_path := _output_path()
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			printerr("[AVATAR LOAD PERF] Unable to write ", output_path)
			_failures.append("performance artifact could not be written")
		else:
			file.store_string(JSON.stringify(results, "\t") + "\n")
			file.close()
			print("[AVATAR LOAD PERF] wrote ", output_path)
	print("AVATAR_LOAD_PERF_RESULT ", JSON.stringify(results))
	for path in _temporary_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if is_instance_valid(_main):
		_main.queue_free()
		await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""
