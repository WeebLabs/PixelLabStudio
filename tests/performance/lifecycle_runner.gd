extends Node

# Phase 15 lifecycle qualification. Every workload the decomposed architecture
# made cheap to get wrong is measured here against the real production scene:
# costume switching, hierarchy rebuild, sidebar refresh on both pages, command
# undo memory, wiggle frame cost, import/load cancellation, and repeated
# application shutdown.
#
# The ceilings are broad algorithmic smoke tests, not optimization targets. The
# exact numbers in the JSON artifact are the useful trend line; a ceiling only
# fires when something has changed complexity class.

const MAIN_SCENE := preload("res://main_scenes/main.tscn")
const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const LAYER_COUNT := 100
const COSTUME_CYCLES := 20
const HIERARCHY_REBUILDS := 50
const SIDEBAR_FRAMES := 60
const UNDO_COMMANDS := 200
const WIGGLE_LAYERS := 25
const WIGGLE_TICKS := 200
const SHUTDOWN_CYCLES := 5

const MAX_COSTUME_SWITCH_MS := 8000.0
const MAX_HIERARCHY_REBUILD_MS := 12000.0
const MAX_SIDEBAR_REFRESH_MS := 6000.0
const MAX_UNDO_MEMORY_BYTES := 600_000_000
const MAX_WIGGLE_US_PER_LAYER_TICK := 500.0
const MAX_CANCELLED_TEARDOWN_MS := 8000.0
const MAX_SHUTDOWN_CYCLE_MS := 8000.0

var _main: Node2D = null
var _temporary_paths: Array[String] = []
var _failures: Array[String] = []
var _results := {}
var _paced_fps := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	if not Saving.is_isolated_session():
		_failures.append("lifecycle benchmark did not start in an isolated session")
		await _finish()
		return

	_results = {
		"engine": Engine.get_version_info()["string"],
		"platform": OS.get_name(),
		"processor": OS.get_processor_name(),
		"layers": LAYER_COUNT,
		"budgets": {
			"costume_switch_ms": MAX_COSTUME_SWITCH_MS,
			"hierarchy_rebuild_ms": MAX_HIERARCHY_REBUILD_MS,
			"sidebar_refresh_ms": MAX_SIDEBAR_REFRESH_MS,
			"undo_memory_bytes": MAX_UNDO_MEMORY_BYTES,
			"wiggle_us_per_layer_tick": MAX_WIGGLE_US_PER_LAYER_TICK,
			"cancelled_teardown_ms": MAX_CANCELLED_TEARDOWN_MS,
			"shutdown_cycle_ms": MAX_SHUTDOWN_CYCLE_MS,
		},
	}

	_main = MAIN_SCENE.instantiate()
	get_tree().root.add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var fixture := _write_fixture(LAYER_COUNT)
	if fixture.is_empty():
		_failures.append("could not create the lifecycle fixture")
		await _finish()
		return
	await _main.load_avatar_file(fixture)
	await get_tree().process_frame
	if Global.sprite_count() != LAYER_COUNT:
		_failures.append("lifecycle fixture registered %d of %d layers" % [Global.sprite_count(), LAYER_COUNT])

	# Headless frames are paced by Engine.max_fps, so a paced wall clock reports
	# the frame interval no matter how much work a frame did. Uncapping makes
	# wall clock the actual cost of the work for every measurement below.
	_paced_fps = Engine.max_fps
	Engine.max_fps = 0
	await get_tree().process_frame

	_stage("costume_switching")
	_results["costume_switching"] = _measure_costume_switching()
	_stage("hierarchy_rebuild")
	_results["hierarchy_rebuild"] = await _measure_hierarchy_rebuild()
	_stage("sidebar_refresh")
	_results["sidebar_refresh"] = await _measure_sidebar_refresh()
	_stage("undo_memory")
	_results["undo_memory"] = _measure_undo_memory()
	_stage("wiggle_frame_cost")
	_results["wiggle_frame_cost"] = await _measure_wiggle_frame_cost()
	_stage("cancelled_load_teardown")
	_results["cancelled_load_teardown"] = await _measure_cancelled_load_teardown()
	_stage("repeated_shutdown")
	_results["repeated_shutdown"] = await _measure_repeated_shutdown()
	_stage("done")

	_results["passed"] = _failures.is_empty()
	await _finish()


# --- Workloads ---


# Costume switching walks all ten costumes, re-deriving visibility and collision
# for every layer each time.
func _measure_costume_switching() -> Dictionary:
	var started := Time.get_ticks_usec()
	for _cycle in range(COSTUME_CYCLES):
		for costume in range(1, 11):
			_main.changeCostume(costume)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var switches := COSTUME_CYCLES * 10
	_check(elapsed_ms <= MAX_COSTUME_SWITCH_MS, "costume switching %.2f ms exceeded %.2f ms" % [elapsed_ms, MAX_COSTUME_SWITCH_MS])
	_main.changeCostume(1)
	return {
		"switches": switches,
		"total_ms": elapsed_ms,
		"ms_per_switch": elapsed_ms / float(switches),
	}


# A full rebuild flattens the layer tree, re-sorts by depth, and reconstructs
# every row; the refresh path only re-reads the existing rows' hierarchy.
func _measure_hierarchy_rebuild() -> Dictionary:
	var sidebar = Global.spriteList
	if sidebar == null:
		_failures.append("layer sidebar was unavailable for the hierarchy benchmark")
		return {}
	# Both calls must be awaited. update_data() yields a frame and then abandons
	# stale generations, so an un-awaited loop coalesces into a single rebuild
	# and reports a cost that has nothing to do with rebuilding the tree.
	var rebuild_started := Time.get_ticks_usec()
	for _index in range(HIERARCHY_REBUILDS):
		await sidebar.updateData()
	var rebuild_ms := float(Time.get_ticks_usec() - rebuild_started) / 1000.0
	var row_count: int = sidebar._layer_tree._container.get_child_count()

	var refresh_started := Time.get_ticks_usec()
	for _index in range(HIERARCHY_REBUILDS):
		await sidebar.refreshHierarchy()
	var refresh_ms := float(Time.get_ticks_usec() - refresh_started) / 1000.0

	_check(
		row_count == LAYER_COUNT,
		"hierarchy rebuild produced %d rows for %d layers" % [row_count, LAYER_COUNT],
	)

	_check(rebuild_ms <= MAX_HIERARCHY_REBUILD_MS, "hierarchy rebuild %.2f ms exceeded %.2f ms" % [rebuild_ms, MAX_HIERARCHY_REBUILD_MS])
	return {
		"iterations": HIERARCHY_REBUILDS,
		"rows": row_count,
		"full_rebuild_ms": rebuild_ms,
		"ms_per_full_rebuild": rebuild_ms / float(HIERARCHY_REBUILDS),
		"refresh_only_ms": refresh_ms,
		"ms_per_refresh": refresh_ms / float(HIERARCHY_REBUILDS),
	}


# The player page must do no hidden edit work: the edit tree is dormant there,
# so its frames cannot cost more than the edit page's.
func _measure_sidebar_refresh() -> Dictionary:
	if not _main.editMode:
		_main.swapMode()
		await get_tree().process_frame
	var edit_process_mode: int = _main.editControls.process_mode
	var edit_processing := _edit_processing_nodes()
	var edit_frames := await _measure_frames(SIDEBAR_FRAMES)

	_main.swapMode()
	await get_tree().process_frame
	var player_process_mode: int = _main.editControls.process_mode
	var player_processing := _edit_processing_nodes()
	var player_frames := await _measure_frames(SIDEBAR_FRAMES)

	_main.swapMode()
	await get_tree().process_frame

	var edit_avg: float = edit_frames["ms_per_frame"]
	var player_avg: float = player_frames["ms_per_frame"]
	# A generous tolerance: real hidden edit work shows up as a multiple, not as
	# the fraction of a millisecond that separates two noisy samples.
	var ceiling := edit_avg * 1.25 + 0.1

	_check(
		edit_process_mode == Node.PROCESS_MODE_INHERIT,
		"the edit component tree did not resume on the edit page",
	)
	_check(
		player_process_mode == Node.PROCESS_MODE_DISABLED,
		"the edit component tree kept processing on the player page",
	)
	# Per-frame wall clock at this layer count is dominated by the layers
	# themselves, so timing alone cannot prove the sidebars are idle. The
	# structural check below is what actually establishes it; the timing stays
	# as a trend value with a generous ceiling.
	_check(
		player_avg <= ceiling,
		"player page frames (%.4f ms) cost more than the edit page allows (%.4f ms)" % [player_avg, ceiling],
	)
	_check(
		edit_processing == ["spriteEdit", "spriteList"],
		"the edit sidebars were not both processing on the edit page (%s)" % str(edit_processing),
	)
	_check(
		player_processing.is_empty(),
		"the player page still processes edit components: %s" % str(player_processing),
	)
	_check(
		edit_frames["total_ms"] <= MAX_SIDEBAR_REFRESH_MS,
		"sidebar refresh %.2f ms exceeded %.2f ms" % [edit_frames["total_ms"], MAX_SIDEBAR_REFRESH_MS],
	)
	# Recorded so a reader can tell whether the frames were doing real work: if
	# the avatar were frozen (resize_active) or the layers were not ticking, the
	# millisecond figures above would describe an idle scene.
	return {
		"frames": SIDEBAR_FRAMES,
		"edit_page": edit_frames,
		"player_page": player_frames,
		"player_to_edit_ratio": player_avg / maxf(edit_avg, 0.0001),
		"edit_page_processing": edit_processing,
		"player_page_processing": player_processing,
		"avatar_frozen_for_resize": _main.resize_active,
		"processing_layers": _processing_layer_count(),
	}


# History is bounded at MAX_HISTORY entries, so sustained editing must reach a
# memory plateau rather than growing without limit.
func _measure_undo_memory() -> Dictionary:
	var sprite = _first_sprite()
	if sprite == null:
		_failures.append("no layer was available for the undo memory benchmark")
		return {}
	Global.select_sprite(sprite)
	MutationCommands.end_gesture()

	var before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var started := Time.get_ticks_usec()
	for index in range(UNDO_COMMANDS):
		MutationCommands.set_layer_property(sprite, "stretchAmount", float(index % 13) + 1.0)
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var depth: int = UndoManager.history_depth()

	_check(
		depth <= UndoManager.MAX_HISTORY,
		"history reached %d entries past the %d-entry bound" % [depth, UndoManager.MAX_HISTORY],
	)
	_check(
		after - before <= MAX_UNDO_MEMORY_BYTES,
		"undo history grew %d bytes past the %d byte ceiling" % [after - before, MAX_UNDO_MEMORY_BYTES],
	)
	return {
		"commands": UNDO_COMMANDS,
		"history_depth": depth,
		"history_bound": UndoManager.MAX_HISTORY,
		"total_ms": elapsed_ms,
		"ms_per_command": elapsed_ms / float(UNDO_COMMANDS),
		"static_memory_delta_bytes": after - before,
		"bytes_per_entry": int(float(after - before) / float(maxi(depth, 1))),
	}


# A wiggle layer replaces its sprite with a simulated verlet chain. Measuring it
# by frame difference does not work: one chain is a rounding error against the
# per-frame cost of a hundred layers, and the sign of the difference flips
# between runs. The tick is driven directly instead, which is deterministic and
# is the number that actually scales with the physics chain.
func _measure_wiggle_frame_cost() -> Dictionary:
	var targets: Array = []
	for candidate in Global.sprite_nodes():
		if candidate.type == "sprite":
			targets.append(candidate)
		if targets.size() >= WIGGLE_LAYERS:
			break
	if targets.is_empty():
		_failures.append("no layer was available for the wiggle benchmark")
		return {}

	var enabled := 0
	for target in targets:
		target.setWiggle(true)
		if target.wiggleEnabled:
			enabled += 1
	# The ribbon mesh is built on the first update, so let a frame run before
	# timing steady-state ticks.
	await get_tree().process_frame
	await get_tree().process_frame

	var simulating := 0
	for target in targets:
		if target._wiggleRuntime.has_appendage():
			simulating += 1

	# Confirm the chain is actually advanced by the frame loop before timing it:
	# a ribbon that never moves would make the cost below meaningless.
	var probe = targets[0]._wiggleRuntime.appendage
	var before_polygon: PackedVector2Array = probe.polygon.duplicate() if probe != null else PackedVector2Array()
	for _frame in range(10):
		await get_tree().process_frame
	var animated: bool = probe != null and probe.polygon != before_polygon
	_check(animated, "the wiggle ribbon did not advance across frames")

	var step := 1.0 / 60.0
	var started := Time.get_ticks_usec()
	for _iteration in range(WIGGLE_TICKS):
		for target in targets:
			target._update_wiggle(step)
	var total_ms := float(Time.get_ticks_usec() - started) / 1000.0

	for target in targets:
		target.setWiggle(false)
	await get_tree().process_frame

	var ticks := WIGGLE_TICKS * targets.size()
	var us_per_layer_tick := total_ms * 1000.0 / float(maxi(ticks, 1))
	_check(enabled == targets.size(), "only %d of %d wiggle benchmark layers enabled their ribbon" % [enabled, targets.size()])
	_check(
		simulating == targets.size(),
		"only %d of %d wiggle layers built a ribbon mesh to simulate" % [simulating, targets.size()],
	)
	_check(
		us_per_layer_tick <= MAX_WIGGLE_US_PER_LAYER_TICK,
		"wiggle cost %.2f us per layer tick past the %.2f us ceiling" % [us_per_layer_tick, MAX_WIGGLE_US_PER_LAYER_TICK],
	)
	return {
		"wiggle_layers": targets.size(),
		"simulating_layers": simulating,
		"advances_per_frame": animated,
		"ticks_per_layer": WIGGLE_TICKS,
		"total_ticks": ticks,
		"total_ms": total_ms,
		"us_per_layer_tick": us_per_layer_tick,
	}


# Tearing the scene down while an avatar load is still in flight is the path
# that leaks worker threads if cancellation is not owned somewhere.
func _measure_cancelled_load_teardown() -> Dictionary:
	var fixture := _write_fixture(LAYER_COUNT)
	if fixture.is_empty():
		_failures.append("could not create the cancellation fixture")
		return {}

	# Start a load and deliberately do not await it, then cancel through the
	# production shutdown path while its worker group is still decoding.
	_main.load_avatar_file(fixture)
	await get_tree().process_frame
	var was_loading: bool = _main.avatar_controller.is_loading()

	var started := Time.get_ticks_usec()
	_main._shutdown_import_workers()
	var drain_ms := float(Time.get_ticks_usec() - started) / 1000.0
	# Give the cancelled load its next frame so it unwinds at a suspension point
	# rather than continuing to build against a scene that is going away.
	await get_tree().process_frame
	await get_tree().process_frame
	var unwind_ms := float(Time.get_ticks_usec() - started) / 1000.0

	var still_loading: bool = _main.avatar_controller.is_loading()

	# Now tear the scene down for real; the load is no longer in flight.
	var teardown_started := Time.get_ticks_usec()
	_main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var teardown_ms := float(Time.get_ticks_usec() - teardown_started) / 1000.0
	_main = null

	_check(was_loading, "the cancellation benchmark did not catch a load in flight")
	_check(not still_loading, "a cancelled load kept its worker group alive")
	_check(
		unwind_ms + teardown_ms <= MAX_CANCELLED_TEARDOWN_MS,
		"cancelled-load teardown %.2f ms exceeded %.2f ms" % [unwind_ms + teardown_ms, MAX_CANCELLED_TEARDOWN_MS],
	)
	_check(Global.main == null, "the application context still referenced a torn-down scene")
	_check(Global.sprite_count() == 0, "the sprite registry survived a cancelled load teardown")
	return {
		"caught_load_in_flight": was_loading,
		"worker_drain_ms": drain_ms,
		"unwind_ms": unwind_ms,
		"teardown_ms": teardown_ms,
		"registry_cleared": Global.sprite_count() == 0,
	}


# Repeated startup and shutdown must return the object count to its starting
# point; a climbing count is the signature of a retained node or resource.
func _measure_repeated_shutdown() -> Dictionary:
	await get_tree().process_frame
	var baseline_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var cycles: Array = []
	var worst_ms := 0.0

	for _index in range(SHUTDOWN_CYCLES):
		var started := Time.get_ticks_usec()
		var scene := MAIN_SCENE.instantiate()
		get_tree().root.add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		scene.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		worst_ms = maxf(worst_ms, elapsed_ms)
		cycles.append({
			"total_ms": elapsed_ms,
			"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		})

	await get_tree().process_frame
	var final_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	# Autoload caches (undo history, settings) legitimately retain a little, so
	# the check is that the count does not climb per cycle.
	var drift := final_objects - baseline_objects
	_check(
		worst_ms <= MAX_SHUTDOWN_CYCLE_MS,
		"slowest startup/shutdown cycle %.2f ms exceeded %.2f ms" % [worst_ms, MAX_SHUTDOWN_CYCLE_MS],
	)
	_check(
		drift <= SHUTDOWN_CYCLES * 200,
		"object count drifted %d across %d startup/shutdown cycles" % [drift, SHUTDOWN_CYCLES],
	)
	_check(Global.main == null, "the application context retained a scene after the shutdown cycles")
	return {
		"cycles": SHUTDOWN_CYCLES,
		"slowest_cycle_ms": worst_ms,
		"baseline_object_count": baseline_objects,
		"final_object_count": final_objects,
		"object_count_drift": drift,
		"per_cycle": cycles,
	}


# --- Helpers ---


# Runs with the frame rate uncapped (see _run), so this wall clock is the real
# cost of the frames rather than the pacing interval.
func _measure_frames(count: int) -> Dictionary:
	for _warmup in range(5):
		await get_tree().process_frame
	var started := Time.get_ticks_usec()
	for _frame in range(count):
		await get_tree().process_frame
	var total_ms := float(Time.get_ticks_usec() - started) / 1000.0
	return {
		"frames": count,
		"total_ms": total_ms,
		"ms_per_frame": total_ms / float(count),
	}


# Which edit-side components the tree will actually tick this frame.
# can_process() resolves the whole process_mode chain, so a disabled ancestor
# shows up here as an idle component regardless of the node's own flags.
func _processing_layer_count() -> int:
	var count := 0
	for sprite in Global.sprite_nodes():
		if sprite.type == "sprite" and sprite.is_processing() and sprite.can_process():
			count += 1
	return count


func _edit_processing_nodes() -> Array:
	var processing: Array = []
	if Global.spriteEdit != null and Global.spriteEdit.can_process():
		processing.append("spriteEdit")
	if Global.spriteList != null and Global.spriteList.can_process():
		processing.append("spriteList")
	return processing


func _first_sprite():
	for sprite in Global.sprite_nodes():
		if sprite.type == "sprite":
			return sprite
	return null


func _stage(name: String) -> void:
	print("[LIFECYCLE PERF] stage: ", name)


func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)


func _write_fixture(layer_count: int) -> String:
	var image_path := ProjectSettings.globalize_path("res://test/testBody.png")
	var data := {"_schemaVersion": 1, "_eyeTrackingGloballyEnabled": true}
	for index in range(layer_count):
		data[str(index)] = {
			"type": "sprite",
			"path": image_path,
			"identification": 3100000000 + index,
			"parentId": 3100000000 + index - 1 if index > 0 and index % 5 != 0 else null,
			"pos": var_to_str(Vector2(index % 20, -(index % 30))),
			"offset": "Vector2(0, 0)",
			"zindex": index,
			"costumeLayers": var_to_str(_costume_membership(index)),
			"animClips": "[]",
		}
	var path := OS.get_temp_dir().path_join("pngtuberplus-lifecycle-%d-%d-%d.json" % [
		layer_count, OS.get_process_id(), _temporary_paths.size(),
	])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data))
	file.close()
	_temporary_paths.append(path)
	return path


# Spread membership across the ten costumes so switching genuinely changes
# visibility rather than leaving every layer on in every costume.
func _costume_membership(index: int) -> Array:
	var membership := []
	for slot in range(10):
		membership.append(1 if index % 10 == slot or index % 3 == 0 else 0)
	return membership


func _finish() -> void:
	if _paced_fps > 0:
		Engine.max_fps = _paced_fps
	_results["passed"] = _failures.is_empty()
	for failure in _failures:
		printerr("[LIFECYCLE PERF] ", failure)
	var output_path := _output_path()
	if not output_path.is_empty():
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			printerr("[LIFECYCLE PERF] Unable to write ", output_path)
			_failures.append("lifecycle artifact could not be written")
		else:
			file.store_string(JSON.stringify(_results, "\t") + "\n")
			file.close()
			print("[LIFECYCLE PERF] wrote ", output_path)
	print("LIFECYCLE_PERF_RESULT ", JSON.stringify(_results))
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
