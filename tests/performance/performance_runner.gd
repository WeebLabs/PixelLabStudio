extends SceneTree

const Animator = preload("res://effects/animation/layer_animator.gd")
const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")

# These are deliberately generous, hardware-independent smoke ceilings. They
# catch accidental algorithmic regressions while the JSON artifact retains the
# exact measurements for trend analysis on consistent CI runners.
const MAX_ANIMATION_US_PER_LAYER_FRAME := 15.0
const MAX_SERIALIZATION_MS := 500.0
const MAX_IMAGE_GEOMETRY_MS := 200.0
const MAX_AVATAR_VALIDATION_MS := 3000.0

var results: Dictionary = {}
var budget_failures: Array[String] = []

func _initialize() -> void:
	results["engine"] = Engine.get_version_info()["string"]
	results["platform"] = OS.get_name()
	results["processor"] = OS.get_processor_name()
	results["processor_count"] = OS.get_processor_count()
	results["animation"] = _benchmark_animation()
	results["serialization"] = _benchmark_serialization()
	results["avatar_validation"] = _benchmark_avatar_validation()
	results["image_geometry"] = _benchmark_image_geometry()
	_check_budgets()
	results["smoke_budgets"] = {
		"animation_us_per_layer_frame": MAX_ANIMATION_US_PER_LAYER_FRAME,
		"serialization_ms": MAX_SERIALIZATION_MS,
		"image_geometry_ms": MAX_IMAGE_GEOMETRY_MS,
		"avatar_validation_ms": MAX_AVATAR_VALIDATION_MS,
		"passed": budget_failures.is_empty(),
	}

	var json := JSON.stringify(results, "\t")
	print("PERF_RESULT ", JSON.stringify(results))
	var output_path := _output_path()
	if output_path != "":
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			printerr("Unable to write performance results to ", output_path)
			quit(1)
			return
		file.store_string(json + "\n")
		file.close()
		print("[PERF] wrote ", output_path)
	for failure in budget_failures:
		printerr("[PERF] budget exceeded: ", failure)
	quit(0 if budget_failures.is_empty() else 1)

func _benchmark_animation() -> Dictionary:
	var measurements := {}
	var clips := [
		{"shape": "oscillate", "channel": "translation", "freqX": 0.01, "freqY": 0.015, "ampX": 10.0, "ampY": 8.0},
		{"shape": "oscillate", "channel": "rotation", "speed": 0.02, "amount": 12.0},
		{"shape": "twitch", "channel": "translation", "trigger": "manual", "speed": 1.0, "amount": 6.0},
	]
	const FRAMES := 600
	for layer_count in [1, 10, 50, 100]:
		var animators: Array = []
		for _i in layer_count:
			animators.append(Animator.new())
		var started := Time.get_ticks_usec()
		for frame in FRAMES:
			for animator in animators:
				animator.evaluate(clips, frame, 1.0 / 60.0)
		var elapsed := Time.get_ticks_usec() - started
		measurements[str(layer_count)] = {
			"total_ms": float(elapsed) / 1000.0,
			"us_per_layer_frame": float(elapsed) / float(layer_count * FRAMES),
		}
	return measurements

func _benchmark_serialization() -> Dictionary:
	var avatar := _avatar_payload()
	var started := Time.get_ticks_usec()
	var bytes := 0
	for _i in 100:
		bytes = JSON.stringify(avatar).length()
	var elapsed := Time.get_ticks_usec() - started
	return {"layers": 100, "iterations": 100, "payload_bytes": bytes, "total_ms": float(elapsed) / 1000.0}

func _benchmark_avatar_validation() -> Dictionary:
	var avatar := _avatar_payload()
	var started := Time.get_ticks_usec()
	var valid := false
	for _i in 100:
		valid = AvatarSave.normalize(avatar)["ok"]
	var elapsed := Time.get_ticks_usec() - started
	return {"layers": 100, "iterations": 100, "valid": valid, "total_ms": float(elapsed) / 1000.0}

func _avatar_payload() -> Dictionary:
	var avatar := {}
	for i in 100:
		avatar[i] = {
			"type": "sprite", "path": "user://layer-%d.png" % i,
			"identification": i, "parentId": i - 1 if i > 0 else null,
			"pos": "Vector2(%d, %d)" % [i, -i], "offset": "Vector2(0, 0)",
			"drag": 5.0, "rotDrag": 2.0, "costumeLayers": "[1,1,1,1,1,1,1,1,1,1]",
			"wigglePath": "PackedVector2Array(0, 0, 10, 10)", "animClips": "[]",
		}
	return avatar

func _benchmark_image_geometry() -> Dictionary:
	var image := Image.load_from_file("res://test/testBody.png")
	if image == null or image.is_empty():
		return {"skipped": true}
	var started := Time.get_ticks_usec()
	var polygon_count := 0
	for _i in 25:
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(image)
		polygon_count = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, bitmap.get_size()), 4.0).size()
	var elapsed := Time.get_ticks_usec() - started
	return {"iterations": 25, "polygons": polygon_count, "total_ms": float(elapsed) / 1000.0}

func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return ""

func _check_budgets() -> void:
	var animation_100: Dictionary = results["animation"]["100"]
	_check_budget(
		"100-layer animation %.3f us/layer-frame > %.3f" % [animation_100["us_per_layer_frame"], MAX_ANIMATION_US_PER_LAYER_FRAME],
		float(animation_100["us_per_layer_frame"]),
		MAX_ANIMATION_US_PER_LAYER_FRAME
	)
	_check_budget(
		"serialization %.3f ms > %.3f" % [results["serialization"]["total_ms"], MAX_SERIALIZATION_MS],
		float(results["serialization"]["total_ms"]),
		MAX_SERIALIZATION_MS
	)
	_check_budget(
		"avatar validation %.3f ms > %.3f" % [results["avatar_validation"]["total_ms"], MAX_AVATAR_VALIDATION_MS],
		float(results["avatar_validation"]["total_ms"]),
		MAX_AVATAR_VALIDATION_MS
	)
	if not results["image_geometry"].has("skipped"):
		_check_budget(
			"image geometry %.3f ms > %.3f" % [results["image_geometry"]["total_ms"], MAX_IMAGE_GEOMETRY_MS],
			float(results["image_geometry"]["total_ms"]),
			MAX_IMAGE_GEOMETRY_MS
		)

func _check_budget(message: String, actual: float, maximum: float) -> void:
	if actual > maximum:
		budget_failures.append(message)
