extends Node

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

func _snapshot() -> Dictionary:
	var data = {}
	var nodes = get_tree().get_nodes_in_group("saved")
	var idx = 0
	for child in nodes:
		if child.type == "sprite":
			data[idx] = {}
			data[idx]["type"] = "sprite"
			data[idx]["path"] = child.path

			if !_image_cache.has(child.id):
				_image_cache[child.id] = child.imageData
			data[idx]["imageData"] = _image_cache[child.id]

			data[idx]["identification"] = child.id
			data[idx]["parentId"] = child.parentId
			data[idx]["pos"] = var_to_str(child.position)
			data[idx]["offset"] = var_to_str(child.offset)
			data[idx]["zindex"] = child.z
			data[idx]["drag"] = child.dragSpeed
			data[idx]["xFrq"] = child.xFrq
			data[idx]["xAmp"] = child.xAmp
			data[idx]["yFrq"] = child.yFrq
			data[idx]["yAmp"] = child.yAmp
			data[idx]["rotDrag"] = child.rdragStr
			data[idx]["showTalk"] = child.showOnTalk
			data[idx]["showBlink"] = child.showOnBlink
			data[idx]["rLimitMin"] = child.rLimitMin
			data[idx]["rLimitMax"] = child.rLimitMax
			data[idx]["costumeLayers"] = var_to_str(child.costumeLayers)
			data[idx]["stretchAmount"] = child.stretchAmount
			data[idx]["ignoreBounce"] = child.ignoreBounce
			data[idx]["frames"] = child.frames
			data[idx]["animSpeed"] = child.animSpeed
			data[idx]["clipped"] = child.clipped
			data[idx]["toggle"] = child.toggle
			data[idx]["eyeTrack"] = child.eyeTrack
			data[idx]["eyeTrackDistance"] = child.eyeTrackDistance
			data[idx]["eyeTrackSpeed"] = child.eyeTrackSpeed
			data[idx]["eyeTrackInvert"] = child.eyeTrackInvert
		idx += 1
	return data

func _restore(data: Dictionary):
	var nodes = get_tree().get_nodes_in_group("saved")
	var current_ids = {}
	for node in nodes:
		current_ids[node.id] = node

	var snapshot_ids = {}
	for item in data:
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
		var d = data[item]
		if !current_ids.has(d["identification"]):
			scene_changed = true
			_add_sprite_from_data(d)

	# 3. Update existing sprites' properties and reparent if needed
	var reparented = false
	for item in data:
		var d = data[item]
		var sprite = current_ids.get(d["identification"])
		if sprite == null:
			continue

		var new_parent_id = d["parentId"]
		if sprite.parentId != new_parent_id:
			reparented = true
			sprite.get_parent().remove_child(sprite)
			if new_parent_id == null:
				Global.main.origin.add_child(sprite)
				sprite.parentId = null
				sprite.parentSprite = null
			else:
				var parent_nodes = get_tree().get_nodes_in_group(str(new_parent_id))
				if parent_nodes.size() > 0:
					parent_nodes[0].sprite.add_child(sprite)
					sprite.parentId = new_parent_id
					sprite.parentSprite = parent_nodes[0]

		sprite.position = str_to_var(d["pos"])
		sprite.offset = str_to_var(d["offset"])
		sprite.sprite.offset = sprite.offset
		sprite.grabArea.position = (sprite.size * -0.5) + sprite.offset

		sprite.z = d["zindex"]
		sprite.setZIndex()
		sprite.dragSpeed = d["drag"]

		sprite.xFrq = d["xFrq"]
		sprite.xAmp = d["xAmp"]
		sprite.yFrq = d["yFrq"]
		sprite.yAmp = d["yAmp"]

		sprite.rdragStr = d["rotDrag"]
		sprite.showOnTalk = d["showTalk"]
		sprite.showOnBlink = d["showBlink"]

		sprite.rLimitMin = d.get("rLimitMin", sprite.rLimitMin)
		sprite.rLimitMax = d.get("rLimitMax", sprite.rLimitMax)

		if d.has("costumeLayers"):
			sprite.costumeLayers = str_to_var(d["costumeLayers"]).duplicate()
		if d.has("stretchAmount"):
			sprite.stretchAmount = d["stretchAmount"]
		if d.has("ignoreBounce"):
			sprite.ignoreBounce = d["ignoreBounce"]
		if d.has("frames"):
			var old_frames = sprite.frames
			sprite.frames = d["frames"]
			if sprite.frames != old_frames:
				sprite.changeFrames()
		if d.has("animSpeed"):
			sprite.animSpeed = d["animSpeed"]
		if d.has("clipped"):
			sprite.setClip(d["clipped"])
		if d.has("toggle"):
			sprite.toggle = d["toggle"]
		if d.has("eyeTrack"):
			sprite.eyeTrack = d["eyeTrack"]
		if d.has("eyeTrackDistance"):
			sprite.eyeTrackDistance = d["eyeTrackDistance"]
		if d.has("eyeTrackSpeed"):
			sprite.eyeTrackSpeed = d["eyeTrackSpeed"]
		if d.has("eyeTrackInvert"):
			sprite.eyeTrackInvert = d["eyeTrackInvert"]

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

	if scene_changed or reparented:
		Global.spriteList.updateData()
	if Global.heldSprite != null:
		Global.spriteEdit.setImage()

# Instantiate a single sprite from snapshot data and add to origin.
func _add_sprite_from_data(d: Dictionary):
	var sprite = _sprite_scene.instantiate()
	sprite.path = d["path"]
	sprite.id = d["identification"]
	sprite.parentId = d["parentId"]
	sprite.offset = str_to_var(d["offset"])
	sprite.z = d["zindex"]
	sprite.dragSpeed = d["drag"]
	sprite.xFrq = d["xFrq"]
	sprite.xAmp = d["xAmp"]
	sprite.yFrq = d["yFrq"]
	sprite.yAmp = d["yAmp"]
	sprite.rdragStr = d["rotDrag"]
	sprite.showOnTalk = d["showTalk"]
	sprite.showOnBlink = d["showBlink"]
	if d.has("rLimitMin"): sprite.rLimitMin = d["rLimitMin"]
	if d.has("rLimitMax"): sprite.rLimitMax = d["rLimitMax"]
	if d.has("costumeLayers"):
		sprite.costumeLayers = str_to_var(d["costumeLayers"]).duplicate()
		if sprite.costumeLayers.size() < 8:
			for i in range(5):
				sprite.costumeLayers.append(1)
	if d.has("stretchAmount"): sprite.stretchAmount = d["stretchAmount"]
	if d.has("ignoreBounce"): sprite.ignoreBounce = d["ignoreBounce"]
	if d.has("frames"): sprite.frames = d["frames"]
	if d.has("animSpeed"): sprite.animSpeed = d["animSpeed"]
	if d.has("imageData"): sprite.loadedImage = d["imageData"]
	if d.has("clipped"): sprite.clipped = d["clipped"]
	if d.has("toggle"): sprite.toggle = d["toggle"]
	if d.has("eyeTrack"): sprite.eyeTrack = d["eyeTrack"]
	if d.has("eyeTrackDistance"): sprite.eyeTrackDistance = d["eyeTrackDistance"]
	if d.has("eyeTrackSpeed"): sprite.eyeTrackSpeed = d["eyeTrackSpeed"]
	if d.has("eyeTrackInvert"): sprite.eyeTrackInvert = d["eyeTrackInvert"]
	Global.main.origin.add_child(sprite)
	sprite.position = str_to_var(d["pos"])

# Full rebuild — only used when loading a completely different avatar (no ID overlap).
func _restore_full(data: Dictionary):
	Global.heldSprite = null

	_image_cache.clear()
	for item in data:
		if data[item].has("imageData"):
			_image_cache[data[item]["identification"]] = data[item]["imageData"]

	var main = Global.main
	main.origin.queue_free()
	var new_origin = Node2D.new()
	main.get_node("OriginMotion").add_child(new_origin)
	main.origin = new_origin

	for item in data:
		_add_sprite_from_data(data[item])

	Global.main.changeCostume(Global.main.costume)
	Global.spriteList.updateData()
	Global.main.onWindowSizeChange()

func invalidate_image(sprite_id):
	_image_cache.erase(sprite_id)

func save_state():
	if suppressed or Global.main == null or !Global.main.saveLoaded:
		return
	_undo_stack.push_back(_snapshot())
	_redo_stack.clear()
	_continuous_saved = false
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()

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
