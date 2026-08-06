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
	var volume_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/volume/volumeSlider.gd"))
	var sensitivity_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/volume/sensitiveSlider.gd"))
	var undo_source := FileAccess.get_file_as_string(source_root.path_join("autoload/undo_manager.gd"))
	t.assert_true(main_source.contains("WorkerThreadPool.add_group_task(\n\t\t_precompute_import_layer"), "PSD preparation uses the bounded engine worker pool")
	t.assert_false(main_source.contains("var threads: Array"), "PSD preparation no longer creates one OS thread per layer")
	t.assert_true(row_source.contains("Global.is_eye_track_target(sprite.id)"), "layer rows share one indexed eye-target calculation")
	t.assert_false(row_source.contains("get_nodes_in_group(\"saved\")"), "layer rows no longer perform quadratic tree scans every frame")
	t.assert_true(list_source.contains("sprite_to_list_item"), "layer hierarchy rebuild indexes parent rows directly")
	for slider_source in [volume_source, sensitivity_source]:
		t.assert_true(slider_source.contains("value_changed.connect"), "stream sliders persist settings only when values change")
		t.assert_false(slider_source.contains("func _process"), "stream sliders no longer write settings every frame")
	t.assert_true(undo_source.contains("if not live_ids.has(sprite_id)"), "undo image caches prune sprites no longer in the live rig")
	t.assert_true(undo_source.contains("_normal_cache.erase(child.id)"), "undo normal-image cache releases cleared maps")

func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
