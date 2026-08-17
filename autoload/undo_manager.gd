extends Node

const SpriteState = preload("res://autoload/domain/sprite_state.gd")
const ValueCodec = preload("res://autoload/persistence/value_codec.gd")

# Emitted when a transaction actually captures a snapshot (not when suppressed
# during an undo/redo restore). Subscribers — currently main.gd's session
# auto-save — use this to flag the rig as "dirty since last persisted save."
signal state_saved

# Emitted after a snapshot has been applied back onto the scene. Undo owns
# sprite state only; every scene/UI consequence of a restore belongs to the
# subscriber (AvatarController), so this history has no UI knowledge.
# Scope keys: structure_changed, hierarchy_changed, full_rebuild, light.
signal state_restored(scope: Dictionary)

const MAX_HISTORY = 50

var _undo_stack: Array = []
var _redo_stack: Array = []
var suppressed: bool = false

# Transaction bookkeeping. begin()/commit()/abort() are the only way production
# code captures history; MutationCommands is the single caller. Nested begins
# join the outermost transaction so a composite command still yields one entry.
var _txn_depth: int = 0
var _txn_pushed: Array[bool] = []

# The gesture currently collapsing into one history entry ("" = none). A
# continuous edit (slider drag, held arrow key) snapshots on its first call and
# then suppresses until the gesture ends. Keying by gesture rather than a single
# global latch means switching controls mid-drag starts a new entry instead of
# silently dropping the second control's history.
var _active_gesture: String = ""

var _sprite_scene = preload("res://ui_scenes/selectedSprite/spriteObject.tscn")

# Cache of sprite id -> Image reference. Image data for a given sprite id
# never changes during normal property edits (position, drag, layers, etc.),
# so we store a reference once and reuse across snapshots. No PNG encoding
# needed — that only happens at file-save time in main.gd.
var _image_cache: Dictionary = {}
var _normal_cache: Dictionary = {}

# Snapshot dicts mix integer sprite-id keys with a handful of special string
# keys ("_light", "_eyeTrackingGloballyEnabled"). Iteration sites that operate
# only on sprite entries must skip these. Comparison via str() because int
# vs String == raises in Godot 4 GDScript.
func _is_meta_key(item) -> bool:
	var s = str(item)
	return s == "_light" or s == "_eyeTrackingGloballyEnabled"

func _snapshot() -> Dictionary:
	var data = {}
	var nodes = Global.sprite_nodes()
	var live_ids := {}
	var idx = 0
	for child in nodes:
		if child.type == "sprite":
			live_ids[child.id] = true
			if _image_cache.get(child.id) != child.imageData:
				_image_cache[child.id] = child.imageData
			var normal_image: Image = null
			if child.normalImageData != null:
				if _normal_cache.get(child.id) != child.normalImageData:
					_normal_cache[child.id] = child.normalImageData
				normal_image = _normal_cache[child.id]
			else:
				_normal_cache.erase(child.id)
			data[idx] = SpriteState.capture_snapshot(child, _image_cache[child.id], normal_image)
		idx += 1
	for sprite_id in _image_cache.keys():
		if not live_ids.has(sprite_id):
			_image_cache.erase(sprite_id)
			_normal_cache.erase(sprite_id)

	# Snapshot light gizmo through the scene's public accessor rather than
	# reaching into its private node reference.
	if Global.main:
		var light_data = Global.main.light_snapshot()
		if light_data != null:
			data["_light"] = light_data

	# Global eye-tracking kill switch
	data["_eyeTrackingGloballyEnabled"] = Global.eyeTrackingGloballyEnabled

	return data

func _restore(data: Dictionary):
	var nodes = Global.sprite_nodes()
	var current_ids = {}
	for node in nodes:
		current_ids[node.id] = node

	var snapshot_ids = {}
	for item in data:
		if _is_meta_key(item):
			continue
		snapshot_ids[data[item]["identification"]] = true

	# Check if any current sprites survive into the snapshot
	var has_overlap = false
	for id in current_ids:
		if snapshot_ids.has(id):
			has_overlap = true
			break

	# No overlap at all = complete avatar swap, full rebuild
	if !has_overlap and (current_ids.size() + data.size()) > 0:
		_restore_full(data)
		return

	# In-place: remove extras, add missing, update & reparent existing
	var scene_changed = false

	# 1. Remove sprites not in snapshot
	for id in current_ids:
		if !snapshot_ids.has(id):
			scene_changed = true
			var sprite = current_ids[id]
			if Global.heldSprite == sprite:
				Global.clear_selection()
			sprite.queue_free()

	# 2. Add sprites not in current scene
	var restored: Array = []
	for item in data:
		if _is_meta_key(item):
			continue
		var d = data[item]
		if !current_ids.has(d["identification"]):
			scene_changed = true
			restored.append(_add_sprite_from_data(d))
	_link_restored_parents(restored)

	# 3. Update existing sprites' properties and reparent if needed
	var reparented = false
	for item in data:
		if _is_meta_key(item):
			continue
		var d = data[item]
		var sprite = current_ids.get(d["identification"])
		if sprite == null:
			continue

		var new_parent_id = d["parentId"]
		if sprite.parentId != new_parent_id:
			reparented = true
			if new_parent_id == null:
				sprite.reparent(Global.main.origin, false)
				sprite.parentId = null
				sprite.parentSprite = null
			else:
				var parent_nodes = get_tree().get_nodes_in_group(str(new_parent_id))
				if parent_nodes.size() > 0:
					var new_parent = parent_nodes[0]
					if sprite.is_ancestor_of(new_parent):
						sprite.reparent(Global.main.origin, false)
						sprite.parentId = null
						sprite.parentSprite = null
					else:
						sprite.reparent(new_parent.sprite, false)
						sprite.parentId = new_parent_id
						sprite.parentSprite = new_parent
				else:
					sprite.reparent(Global.main.origin, false)
					sprite.parentId = null
					sprite.parentSprite = null

		SpriteState.apply_existing(sprite, d)

	# Re-derive costume visibility without nulling heldSprite. This must go
	# through applyCostumeVisibility(): reading costumeLayers directly ignores
	# userHidden, so every eye-hidden layer used to reappear on undo/redo.
	for node in Global.sprite_nodes():
		if node.is_queued_for_deletion():
			continue
		node.applyCostumeVisibility()

	# Restore global eye-tracking kill switch
	if data.has("_eyeTrackingGloballyEnabled"):
		Global.eyeTrackingGloballyEnabled = bool(data["_eyeTrackingGloballyEnabled"])

	state_restored.emit({
		"structure_changed": scene_changed,
		"hierarchy_changed": reparented,
		"full_rebuild": false,
		"light": data.get("_light"),
	})

# Instantiate a single sprite from snapshot data and add to origin. Reparenting
# is resolved by _link_restored_parents() once every sprite in the snapshot
# exists, so the sprite's own deferred 0.1s reparent timer is skipped: that timer
# outlives a short session (it leaks at exit) and cannot see siblings that the
# same restore has not added yet.
func _add_sprite_from_data(d: Dictionary):
	var sprite = _sprite_scene.instantiate()
	SpriteState.apply_before_ready(sprite, d)
	SpriteState.prepare_snapshot_images(sprite, d)
	sprite._skip_ready_reparent = true
	Global.main.origin.add_child(sprite)
	sprite.position = ValueCodec.vector2_value(d["pos"], Vector2.ZERO)
	return sprite


# Attach restored sprites to their recorded parents. Runs after the whole
# snapshot is instantiated so a parent added later in the same restore is found.
func _link_restored_parents(restored: Array) -> void:
	for sprite in restored:
		if not is_instance_valid(sprite) or sprite.parentId == null:
			continue
		var parents = get_tree().get_nodes_in_group(str(sprite.parentId))
		if parents.is_empty():
			sprite.parentId = null
			sprite.parentSprite = null
			continue
		var parent = parents[0]
		if sprite.is_ancestor_of(parent):
			continue
		sprite.reparent(parent.sprite, false)
		sprite.parentSprite = parent
		sprite.set_owner(parent.sprite)
		# Reparent changed the global transform — re-snap the top_level dragger.
		sprite._force_drag_snap = true

# Full rebuild — only used when loading a completely different avatar (no ID overlap).
func _restore_full(data: Dictionary):
	Global.clear_selection()

	_image_cache.clear()
	_normal_cache.clear()
	for item in data:
		if _is_meta_key(item):
			continue
		if data[item].has("imageData"):
			_image_cache[data[item]["identification"]] = data[item]["imageData"]
		if data[item].has("normalImageData"):
			_normal_cache[data[item]["identification"]] = data[item]["normalImageData"]

	var main = Global.main
	main.origin.queue_free()
	var new_origin = Node2D.new()
	main.get_node("OriginMotion").add_child(new_origin)
	main.origin = new_origin

	var restored: Array = []
	for item in data:
		if _is_meta_key(item):
			continue
		restored.append(_add_sprite_from_data(data[item]))
	_link_restored_parents(restored)

	# Restore global eye-tracking kill switch
	if data.has("_eyeTrackingGloballyEnabled"):
		Global.eyeTrackingGloballyEnabled = bool(data["_eyeTrackingGloballyEnabled"])

	state_restored.emit({
		"structure_changed": true,
		"hierarchy_changed": true,
		"full_rebuild": true,
		"light": data.get("_light"),
	})

func invalidate_image(sprite_id):
	_image_cache.erase(sprite_id)

func invalidate_normal(sprite_id):
	_normal_cache.erase(sprite_id)

# --- Transactions ---
#
# Open a history transaction. An empty gesture is a discrete edit and always
# captures; a named gesture captures once and then collapses until the gesture
# ends. Every begin() must be paired with commit() or abort(); abort() discards
# the snapshot so a command that changed nothing leaves no dead history entry.
func begin(gesture: String = "") -> void:
	var pushed := false
	if _txn_depth == 0:
		if gesture.is_empty():
			pushed = _push_snapshot()
			_active_gesture = ""
		elif _active_gesture != gesture:
			pushed = _push_snapshot()
			if pushed:
				_active_gesture = gesture
	_txn_pushed.push_back(pushed)
	_txn_depth += 1

func commit() -> void:
	if _txn_depth == 0:
		return
	_txn_depth -= 1
	_txn_pushed.pop_back()

func abort() -> void:
	if _txn_depth == 0:
		return
	_txn_depth -= 1
	if _txn_pushed.pop_back():
		_undo_stack.pop_back()
		_active_gesture = ""

# End the current continuous gesture so the next continuous edit starts a new
# history entry. Called on mouse release and when a held-key burst stops.
# Pass the gesture name to end only that gesture: a per-frame poll that ends
# gestures unconditionally would cut short an unrelated drag still in progress.
func end_gesture(gesture: String = "") -> void:
	if gesture.is_empty() or _active_gesture == gesture:
		_active_gesture = ""

func history_depth() -> int:
	return _undo_stack.size()

func _push_snapshot() -> bool:
	if suppressed or Global.main == null or !Global.main.saveLoaded:
		return false
	_undo_stack.push_back(_snapshot())
	_redo_stack.clear()
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	state_saved.emit()
	return true

func undo():
	if _undo_stack.is_empty():
		Global.notify_user("Nothing to undo.")
		return
	end_gesture()
	suppressed = true
	_redo_stack.push_back(_snapshot())
	var snapshot = _undo_stack.pop_back()
	_restore(snapshot)
	suppressed = false
	Global.notify_user("Undo.")

func redo():
	if _redo_stack.is_empty():
		Global.notify_user("Nothing to redo.")
		return
	end_gesture()
	suppressed = true
	_undo_stack.push_back(_snapshot())
	var snapshot = _redo_stack.pop_back()
	_restore(snapshot)
	suppressed = false
	Global.notify_user("Redo.")

func _input(event):
	if event is InputEventMouseButton and !event.pressed:
		end_gesture()
