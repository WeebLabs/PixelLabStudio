extends RefCounted

const Registry = preload("res://autoload/domain/sprite_registry.gd")
const Animator = preload("res://effects/animation/layer_animator.gd")

class FakeSprite extends RefCounted:
	var id: int
	var z: int
	var eyeTrackMode := 0
	var eyeTrackTargetId: Variant = null

	func _init(sprite_id: int, z_index: int = 0) -> void:
		id = sprite_id
		z = z_index

var _pool_results: Array = []

func run(t) -> void:
	_test_registry(t)
	_test_idle_animation(t)
	_test_worker_pool(t)
	_test_optimized_call_sites(t)

func _test_registry(t) -> void:
	var registry := Registry.new()
	var first := FakeSprite.new(10, 4)
	var second := FakeSprite.new(20, 9)
	second.eyeTrackMode = 1
	second.eyeTrackTargetId = 10
	registry.register(first)
	registry.register(second)
	registry.rebuild_eye_targets()
	t.assert_equal(registry.size(), 2, "sprite registry tracks each live sprite once")
	t.assert_equal(registry.by_id(20), second, "sprite registry resolves IDs without a scene-tree scan")
	t.assert_equal(registry.maximum_z(), 9, "sprite registry calculates the current maximum layer")
	t.assert_true(registry.is_eye_target(10), "sprite registry indexes eye-tracking target IDs")
	t.assert_false(registry.is_eye_target(20), "unreferenced sprite IDs are not target badges")
	var replacement := FakeSprite.new(10, 12)
	registry.register(replacement)
	t.assert_equal(registry.by_id(10), replacement, "registering a reused ID atomically replaces its stale object")
	t.assert_equal(registry.size(), 2, "reused IDs do not duplicate registry rows")
	registry.unregister(replacement)
	t.assert_equal(registry.by_id(10), null, "unregister removes the matching live object")
	registry.clear()
	t.assert_equal(registry.size(), 0, "registry clear releases all scene references")

func _test_idle_animation(t) -> void:
	var animator := Animator.new()
	animator.evaluate([], 1, 1.0 / 60.0)
	t.assert_false(animator._seeded, "empty animation lists do not initialize a random generator")
	t.assert_equal(animator.rot, 0.0, "idle animation fast path resets rotation")
	t.assert_equal(animator.trans, Vector2.ZERO, "idle animation fast path resets translation")
	animator.evaluate([{"shape": "twitch", "channel": "rotation", "trigger": "always"}], 2, 0.1)
	animator.reset()
	t.assert_true(animator._rt.is_empty(), "animation reset releases per-clip runtime dictionaries")

func _test_worker_pool(t) -> void:
	_pool_results.resize(32)
	var group_id := WorkerThreadPool.add_group_task(_pool_square, _pool_results.size(), -1, false, "test pool")
	t.assert_true(group_id >= 0, "engine worker pool accepts bounded group jobs")
	WorkerThreadPool.wait_for_group_task_completion(group_id)
	for index in _pool_results.size():
		t.assert_equal(_pool_results[index], index * index, "worker pool writes each isolated result slot")

func _pool_square(index: int) -> void:
	_pool_results[index] = index * index

func _test_optimized_call_sites(t) -> void:
	var source_root := _source_root()
	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var row_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/sprite_list_object.gd"))
	var list_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/viewer.gd"))
	var viewer_bar_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/ControlPanel.gd"))
	var undo_source := FileAccess.get_file_as_string(source_root.path_join("autoload/undo_manager.gd"))
	t.assert_true(main_source.contains("WorkerThreadPool.add_group_task(\n\t\t_precompute_import_layer"), "PSD preparation uses the bounded engine worker pool")
	t.assert_false(main_source.contains("var threads: Array"), "PSD preparation no longer creates one OS thread per layer")
	t.assert_true(row_source.contains("Global.is_eye_track_target(sprite.id)"), "layer rows share one indexed eye-target calculation")
	t.assert_false(row_source.contains("get_nodes_in_group(\"saved\")"), "layer rows no longer perform quadratic tree scans every frame")
	t.assert_true(list_source.contains("sprite_to_list_item"), "layer hierarchy rebuild indexes parent rows directly")
	# The mic threshold sliders live on the viewer menu bar. Its _process polls the
	# live meters every frame, so the settings write must stay on value_changed.
	t.assert_true(viewer_bar_source.contains("value_changed.connect"), "stream sliders persist settings only when values change")
	t.assert_false(
		_function_body(viewer_bar_source, "func _process").contains("Saving."),
		"the viewer bar no longer writes settings every frame",
	)
	# Layer grab areas are only ever found by the cursor's intersect_point query,
	# which matches an area's LAYER. Leaving their mask at the default 1 makes the
	# physics server pair every overlapping layer with every other one and solve
	# SAT against their traced polygons at 60 Hz: measured 198.8 ms/frame for 25
	# layers versus 16.0 ms with the mask cleared, on a 16.1 ms no-pairs floor.
	var sprite_scene := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/selectedSprite/spriteObject.tscn"))
	t.assert_true(sprite_scene.contains("collision_mask = 0"), "layer grab areas detect nothing, so the physics server never pairs them")
	t.assert_true(undo_source.contains("if not live_ids.has(sprite_id)"), "undo image caches prune sprites no longer in the live rig")
	t.assert_true(undo_source.contains("_normal_cache.erase(child.id)"), "undo normal-image cache releases cleared maps")

# The body of a top-level function, for assertions about what runs per frame.
func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var body := ""
	for line in source.substr(start).split("\n").slice(1):
		if not line.is_empty() and not line.begins_with("\t"):
			break
		body += line + "\n"
	return body


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
