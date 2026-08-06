extends Node

const SpriteState = preload("res://autoload/domain/sprite_state.gd")

# Emitted when save_state() actually captures a snapshot (not when suppressed
# during an undo/redo restore). Subscribers — currently main.gd's session
# auto-save — use this to flag the rig as "dirty since last persisted save."
signal state_saved

const MAX_HISTORY = 50

var _undo_stack: Array = []
var _redo_stack: Array = []
var _continuous_saved: bool = false
var suppressed: bool = false

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
	var nodes = get_tree().get_nodes_in_group("saved")
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

	# Snapshot light gizmo
	if Global.main and Global.main._light_gizmo:
		var g = Global.main._light_gizmo
		data["_light"] = {
			"pos": var_to_str(g.position),
			"energy": g.light_energy,
			"color": var_to_str(g.light_color),
			"range": g.light_range,
			"enabled": g.light_enabled
		}

	# Global eye-tracking kill switch
	data["_eyeTrackingGloballyEnabled"] = Global.eyeTrackingGloballyEnabled

	return data

func _restore(data: Dictionary):
	var nodes = get_tree().get_nodes_in_group("saved")
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
				Global.heldSprite = null
			sprite.queue_free()

	# 2. Add sprites not in current scene (parentId reparenting handled by _ready)
	for item in data:
		if _is_meta_key(item):
			continue
		var d = data[item]
		if !current_ids.has(d["identification"]):
			scene_changed = true
			_add_sprite_from_data(d)

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

	# Update costume visibility without nulling heldSprite
	var costume = Global.main.costume
	for node in get_tree().get_nodes_in_group("saved"):
		if node.is_queued_for_deletion():
			continue
		if node.costumeLayers[costume - 1] == 1:
			node.visible = true
			node.changeCollision(true)
		else:
			node.visible = false
			node.changeCollision(false)

	if scene_changed:
		Global.spriteList.updateData()
	elif reparented:
		Global.spriteList.refreshHierarchy()
	if Global.heldSprite != null:
		Global.spriteEdit.setImage()

	# Restore light gizmo
	if data.has("_light") and Global.main and Global.main._light_gizmo:
		Global.main._apply_light_data(data["_light"])

	# Restore global eye-tracking kill switch
	if data.has("_eyeTrackingGloballyEnabled"):
		Global.eyeTrackingGloballyEnabled = bool(data["_eyeTrackingGloballyEnabled"])

# Instantiate a single sprite from snapshot data and add to origin.
func _add_sprite_from_data(d: Dictionary):
	var sprite = _sprite_scene.instantiate()
	SpriteState.apply_before_ready(sprite, d)
	SpriteState.prepare_snapshot_images(sprite, d)
	Global.main.origin.add_child(sprite)
	sprite.position = str_to_var(d["pos"])

# Full rebuild — only used when loading a completely different avatar (no ID overlap).
func _restore_full(data: Dictionary):
	Global.heldSprite = null

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

	for item in data:
		if _is_meta_key(item):
			continue
		_add_sprite_from_data(data[item])

	# Re-create light gizmo on new origin
	main._create_light_gizmo()
	if data.has("_light"):
		main._apply_light_data(data["_light"])

	# Restore global eye-tracking kill switch
	if data.has("_eyeTrackingGloballyEnabled"):
		Global.eyeTrackingGloballyEnabled = bool(data["_eyeTrackingGloballyEnabled"])

	Global.main.changeCostume(Global.main.costume)
	Global.spriteList.updateData()
	Global.main.onWindowSizeChange()

func invalidate_image(sprite_id):
	_image_cache.erase(sprite_id)

func invalidate_normal(sprite_id):
	_normal_cache.erase(sprite_id)

func save_state():
	if suppressed or Global.main == null or !Global.main.saveLoaded:
		return
	_undo_stack.push_back(_snapshot())
	_redo_stack.clear()
	_continuous_saved = false
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	state_saved.emit()

func save_state_continuous():
	if _continuous_saved:
		return
	save_state()
	_continuous_saved = true

func undo():
	if _undo_stack.is_empty():
		Global.pushUpdate("Nothing to undo.")
		return
	suppressed = true
	_redo_stack.push_back(_snapshot())
	var snapshot = _undo_stack.pop_back()
	_restore(snapshot)
	suppressed = false
	Global.pushUpdate("Undo.")

func redo():
	if _redo_stack.is_empty():
		Global.pushUpdate("Nothing to redo.")
		return
	suppressed = true
	_undo_stack.push_back(_snapshot())
	var snapshot = _redo_stack.pop_back()
	_restore(snapshot)
	suppressed = false
	Global.pushUpdate("Redo.")

func _input(event):
	if event is InputEventMouseButton and !event.pressed:
		_continuous_saved = false
