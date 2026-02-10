extends Node

const MAX_HISTORY = 50

var _undo_stack: Array = []
var _redo_stack: Array = []
var _continuous_saved: bool = false

var _sprite_scene = preload("res://ui_scenes/selectedSprite/spriteObject.tscn")

# Cache of sprite id -> base64 PNG string. Image data for a given sprite id
# never changes during normal property edits (position, drag, layers, etc.),
# so we only need to encode once and reuse across snapshots.
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

			if _image_cache.has(child.id):
				data[idx]["imageData"] = _image_cache[child.id]
			else:
				var encoded = Marshalls.raw_to_base64(child.imageData.save_png_to_buffer())
				_image_cache[child.id] = encoded
				data[idx]["imageData"] = encoded

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
		idx += 1
	return data

func _restore(data: Dictionary):
	if _can_restore_in_place(data):
		_restore_in_place(data)
	else:
		_restore_full(data)

# Check if snapshot has the same sprite IDs as the live scene.
# If so we can patch properties in place instead of rebuilding everything.
func _can_restore_in_place(data: Dictionary) -> bool:
	var nodes = get_tree().get_nodes_in_group("saved")
	if nodes.size() != data.size():
		return false

	var by_id = {}
	for node in nodes:
		by_id[node.id] = node

	for item in data:
		if !by_id.has(data[item]["identification"]):
			return false

	return true

# Fast path: same sprites, update properties and reparent if needed.
func _restore_in_place(data: Dictionary):
	var nodes = get_tree().get_nodes_in_group("saved")
	var by_id = {}
	for node in nodes:
		by_id[node.id] = node

	var reparented = false

	for item in data:
		var d = data[item]
		var sprite = by_id[d["identification"]]
		var new_parent_id = d["parentId"]

		# Handle reparenting if parentId changed
		if sprite.parentId != new_parent_id:
			reparented = true
			sprite.get_parent().remove_child(sprite)
			if new_parent_id == null:
				Global.main.origin.add_child(sprite)
				sprite.parentId = null
				sprite.parentSprite = null
			else:
				var parent_sprite = by_id.get(new_parent_id)
				if parent_sprite:
					parent_sprite.sprite.add_child(sprite)
					sprite.parentId = new_parent_id
					sprite.parentSprite = parent_sprite

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

	# Update costume visibility without nulling heldSprite
	var costume = Global.main.costume
	for node in nodes:
		if node.costumeLayers[costume - 1] == 1:
			node.visible = true
			node.changeCollision(true)
		else:
			node.visible = false
			node.changeCollision(false)

	if reparented:
		Global.spriteList.updateData()
	if Global.heldSprite != null:
		Global.spriteEdit.setImage()

# Slow path: sprite set changed, full rebuild (add/delete/link/load).
func _restore_full(data: Dictionary):
	Global.heldSprite = null

	# Prime cache from snapshot so restored sprites don't need re-encoding
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
		var sprite = _sprite_scene.instantiate()
		sprite.path = data[item]["path"]
		sprite.id = data[item]["identification"]
		sprite.parentId = data[item]["parentId"]

		sprite.offset = str_to_var(data[item]["offset"])
		sprite.z = data[item]["zindex"]
		sprite.dragSpeed = data[item]["drag"]

		sprite.xFrq = data[item]["xFrq"]
		sprite.xAmp = data[item]["xAmp"]
		sprite.yFrq = data[item]["yFrq"]
		sprite.yAmp = data[item]["yAmp"]

		sprite.rdragStr = data[item]["rotDrag"]
		sprite.showOnTalk = data[item]["showTalk"]
		sprite.showOnBlink = data[item]["showBlink"]

		if data[item].has("rLimitMin"):
			sprite.rLimitMin = data[item]["rLimitMin"]
		if data[item].has("rLimitMax"):
			sprite.rLimitMax = data[item]["rLimitMax"]

		if data[item].has("costumeLayers"):
			sprite.costumeLayers = str_to_var(data[item]["costumeLayers"]).duplicate()
			if sprite.costumeLayers.size() < 8:
				for i in range(5):
					sprite.costumeLayers.append(1)

		if data[item].has("stretchAmount"):
			sprite.stretchAmount = data[item]["stretchAmount"]

		if data[item].has("ignoreBounce"):
			sprite.ignoreBounce = data[item]["ignoreBounce"]

		if data[item].has("frames"):
			sprite.frames = data[item]["frames"]
		if data[item].has("animSpeed"):
			sprite.animSpeed = data[item]["animSpeed"]
		if data[item].has("imageData"):
			sprite.loadedImageData = data[item]["imageData"]
		if data[item].has("clipped"):
			sprite.clipped = data[item]["clipped"]
		if data[item].has("toggle"):
			sprite.toggle = data[item]["toggle"]

		new_origin.add_child(sprite)
		sprite.position = str_to_var(data[item]["pos"])

	Global.main.changeCostume(Global.main.costume)
	Global.spriteList.updateData()
	Global.main.onWindowSizeChange()

func invalidate_image(sprite_id):
	_image_cache.erase(sprite_id)

func save_state():
	if Global.main == null or !Global.main.saveLoaded:
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
	_redo_stack.push_back(_snapshot())
	var snapshot = _undo_stack.pop_back()
	_restore(snapshot)
	Global.pushUpdate("Undo.")

func redo():
	if _redo_stack.is_empty():
		Global.pushUpdate("Nothing to redo.")
		return
	_undo_stack.push_back(_snapshot())
	var snapshot = _redo_stack.pop_back()
	_restore(snapshot)
	Global.pushUpdate("Redo.")

func _input(event):
	if event is InputEventMouseButton and !event.pressed:
		_continuous_saved = false
