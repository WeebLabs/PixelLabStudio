extends Node2D

# talkBlink() looks up whether a (showOnTalk + 3*blinkVal + 10*speaking + 20*blink)
# combination should be visible. The values mirror the original literal
# [0,10,20,30,1,21,12,32,3,13,4,15,26,36,27,38].has(int(value)) — moving them
# to a class const Dictionary means we don't allocate an Array each frame for
# each sprite (was Array literal in a tight per-frame loop).
const VISIBLE_TALKBLINK_STATES := {
	0: true, 1: true, 3: true, 4: true,
	10: true, 12: true, 13: true, 15: true,
	20: true, 21: true, 26: true, 27: true,
	30: true, 32: true, 36: true, 38: true,
}

var type = "sprite"

#Passed Variables
var imageData = null
var tex = null
@export var path = ""

var loadedImageData = null
var loadedImage: Image = null  # Direct in-memory Image (for PSD import)

var id = 0
var parentId = null
var parentSprite = null

var imageSize = Vector2.ZERO

#Node Reference
@onready var sprite = $WobbleOrigin/DragOrigin/Sprite

@onready var grabArea = $WobbleOrigin/DragOrigin/Grab

@onready var dragOrigin = $WobbleOrigin/DragOrigin
@onready var dragger = $WobbleOrigin/Dragger

@onready var originSprite = $WobbleOrigin/DragOrigin/Sprite/Origin

@onready var wob = $WobbleOrigin

@onready var outlineScene = preload("res://ui_scenes/selectedSprite/outline.tscn")

#Visuals
var mouseOffset = Vector2.ZERO
var grabDelay = 0
var size = Vector2(1,1)

var showOnTalk = 0
var showOnBlink = 0

var z = 0

#Movement
var heldTicks = 0
var dragSpeed = 0
var _force_drag_snap: bool = true


#Origin
var origTick = 0
var offset = Vector2.ZERO
var _origin_dragging = false
var _origin_drag_start_mouse_local = Vector2.ZERO
var _origin_drag_start_offset = Vector2.ZERO
var _origin_drag_start_pos = Vector2.ZERO

#Wobble
var xFrq = 0.0
var xAmp = 0.0

var yFrq = 0.0
var yAmp = 0.0

#Rotational Drag
var rdragStr = 0
var rLimitMax = 180
var rLimitMin = -180

#Layer
var costumeLayers = [1,1,1,1,1,1,1,1,1,1]

#Stretch
var stretchAmount = 0.0

#Ignore Bounce
var ignoreBounce = false
var staticElement = false

# Cache of imageData.get_used_rect() — set lazily, invalidated when image changes.
# Image.get_used_rect() scans every pixel, so per-frame NDI framing recomputation
# was paying that cost N times for an N-sprite avatar.
var _cached_used_rect: Rect2i = Rect2i(0, 0, -1, -1)

func get_image_used_rect() -> Rect2i:
	if _cached_used_rect.size.x < 0 and imageData != null:
		_cached_used_rect = imageData.get_used_rect()
	return _cached_used_rect

func invalidate_used_rect_cache():
	_cached_used_rect = Rect2i(0, 0, -1, -1)

#Eye Tracking
var eyeTrack = false
var eyeTrackDistance = 20.0
var eyeTrackSpeed = 0.15
var eyeTrackInvert = false
var eyeTrackMode = 0  # 0 = cursor, 1 = layer
var eyeTrackTargetId = null  # int sprite id when eyeTrackMode == 1
var _eyeTrackOffset = Vector2.ZERO

# Wiggle (physics) — bends this layer with a textured Line2D ribbon driven by an
# angular-spring/verlet chain (effects/wiggle/). User-facing units (degrees /
# friendly ranges); mapped to the chain in _wiggle_params(). Persisted; all
# backward-compatible (defaults applied).
var wiggleEnabled = false
var wiggleDirection = 90.0     # rest direction from the origin, degrees (90 = down)
var wiggleSegments = 8
var wiggleStiffness = 20.0
var wiggleDamping = 5.0
var wiggleWeight = 0.0          # gravity droop strength
var wiggleMaxBend = 25.0        # max bend per joint, degrees
var wiggleBendFocus = 0.4       # comeback speed off the angle limit (springiness)
var wiggleWagEnabled = true     # auto-wag drives a side-to-side sweep
var wiggleWagAmount = 15.0      # auto-wag base-sway amplitude, degrees
var wiggleWagSpeed = 0.12
var wiggleReactivity = 1.0      # how much the ribbon lags/whips with the layer's motion
var wiggleChildrenFollow = false

const _WIGGLE_APPENDAGE = preload("res://effects/wiggle/wiggle_appendage.gd")
var _wiggleAppendage: WiggleAppendage2D = null
# Set on this layer while a wiggle parent drives it (child-follow); stores rest transform.
var _wiggleRestPos = Vector2.ZERO
var _wiggleRestRot = 0.0
var _wiggleFollowing = false

#Blink Animation
var _blinkAnimPlaying = false
var _blinkAnimTick = 0
var _prevBlink = false
var _blinkQueue = 0

#Animation
var frames = 1
var animSpeed = 0

var remadePolygon = false

var clipped = false
var ndiRefLayer = false

# Normal map
var normalImageData: Image = null
var normalTex: ImageTexture = null
var normalPath: String = ""
var loadedNormalImage: Image = null
var loadedNormalData: String = ""

var tick = 0

#Vis toggle
var toggle = "null"
var _skip_ready_reparent = false
var _prebuilt_pma_image: Image = null
var _prebuilt_polygons: Array = []

func _make_premultiplied_texture(img: Image) -> ImageTexture:
	var pma = img.duplicate()
	pma.premultiply_alpha()
	return ImageTexture.create_from_image(pma)

func _rebuild_sprite_texture():
	if normalTex != null:
		var canvas_tex = CanvasTexture.new()
		canvas_tex.diffuse_texture = tex
		canvas_tex.normal_texture = normalTex
		sprite.texture = canvas_tex
	else:
		sprite.texture = tex
	# Keep the wiggle ribbon's texture in sync when the image/normal changes.
	if _wiggleAppendage != null:
		_rebuild_wiggle_texture()

func setNormalMap(img: Image, nrml_path: String):
	if imageData != null and img.get_size() != imageData.get_size():
		Global.pushUpdate("Normal map size mismatch. Must match diffuse dimensions.")
		return
	normalImageData = img
	normalPath = nrml_path
	normalTex = ImageTexture.create_from_image(img)
	_rebuild_sprite_texture()

func clearNormalMap():
	normalImageData = null
	normalTex = null
	normalPath = ""
	loadedNormalImage = null
	loadedNormalData = ""
	_rebuild_sprite_texture()

func hasNormalMap() -> bool:
	return normalTex != null

func _ready():
	
	Global.main.spriteVisToggles.connect(visToggle)
	
	var img = Image.new()
	if loadedImage != null:
		img = loadedImage
		loadedImage = null
	else:
		var err = img.load(path)
		if err != OK:
			#Runs if image import fails. Needs error dialog box at some point
			if loadedImageData == null:
				Global.epicFail(err)
				print_debug("Failed to load image.")
				queue_free()
				return
			else:
				var data = Marshalls.base64_to_raw(loadedImageData)
				var errr = img.load_png_from_buffer(data)
				if errr != OK:
					Global.epicFail(err)
					print_debug("Failed to load image.")
					queue_free()
					return
		
	imageData = img

	# Use prebuilt premultiplied image if available (from threaded import)
	if _prebuilt_pma_image != null:
		tex = ImageTexture.create_from_image(_prebuilt_pma_image)
		_prebuilt_pma_image = null
	else:
		tex = _make_premultiplied_texture(img)

	imageSize = img.get_size()

	# Load normal map if present (from PSD import or save file)
	if loadedNormalImage != null:
		setNormalMap(loadedNormalImage, normalPath)
		loadedNormalImage = null
	elif loadedNormalData != "":
		var nrml_raw = Marshalls.base64_to_raw(loadedNormalData)
		var nrml_img = Image.new()
		if nrml_img.load_png_from_buffer(nrml_raw) == OK:
			setNormalMap(nrml_img, normalPath)
		loadedNormalData = ""
	else:
		_rebuild_sprite_texture()

	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	sprite.material = mat

	# Use prebuilt polygons if available (from threaded import)
	var polygons
	if _prebuilt_polygons.size() > 0:
		polygons = _prebuilt_polygons
		_prebuilt_polygons = []
	else:
		var bitmap = BitMap.new()
		bitmap.create_from_image_alpha(imageData)
		polygons = bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), bitmap.get_size()), 4.0)

	var b = false
	for polygon in polygons:
		b = true
		var collider = CollisionPolygon2D.new()
		collider.polygon = polygon
		grabArea.add_child(collider)

		var outline = outlineScene.instantiate()
		outline.points = polygon
		outline.add_point(outline.points[0])
		outline.visibility_layer = 2
		grabArea.add_child(outline)

	size = imageData.get_size()
	grabArea.position = size*-0.5

	sprite.offset = offset

	grabArea.position = (size*-0.5) + offset

	# Selection overlays are off by default; _process toggles them on for the held sprite.
	# Layer 2 keeps them on the main camera but out of the NDI camera's cull mask.
	grabArea.visible = false
	grabArea.visibility_layer = 2
	originSprite.visible = false
	originSprite.visibility_layer = 2
	
	changeFrames()
	setZIndex()
	
	if frames > 1:
		remakePolygon()
	if !b:
		remakePolygon()
	
	
	add_to_group(str(id))

	# Avatar load handles reparenting synchronously and sets _skip_ready_reparent,
	# so we don't need to suspend on a timer that does nothing afterwards
	if not _skip_ready_reparent:
		await get_tree().create_timer(0.1).timeout
		if parentId != null:
			var nodes = get_tree().get_nodes_in_group(str(parentId))
			if nodes.size() > 0:
				get_parent().remove_child(self)
				nodes[0].sprite.add_child(self)
				parentSprite = nodes[0]
				set_owner(nodes[0].sprite)
				# Reparent changed our global transform — re-snap the top_level dragger
				_force_drag_snap = true
			else:
				parentId = null
				parentSprite = null

	setClip(clipped)


	if Global.filtering:
		sprite.texture_filter = 2

	if wiggleEnabled:
		_set_wiggle_active(true)
	
func replaceSprite(pathNew):
	var img = Image.new()
	var err = img.load(pathNew)
	if err != OK:
		#Runs if image import fails.
		Global.epicFail(err)
		print_debug("Failed to load image.")
		return

	path = pathNew

	imageData = img
	invalidate_used_rect_cache()
	tex = _make_premultiplied_texture(img)

	# Clear normal if new diffuse has different dimensions
	if hasNormalMap() and normalImageData.get_size() != img.get_size():
		clearNormalMap()
		Global.pushUpdate("Normal map cleared (size mismatch after replace).")
	else:
		_rebuild_sprite_texture()
	
	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(imageData)
	
	var polygons = bitmap.opaque_to_polygons(Rect2(Vector2(0, 0), bitmap.get_size()))
	
	for i in grabArea.get_children():
		i.queue_free()
	
	var b = false
	for polygon in polygons:
		b = true
		var collider = CollisionPolygon2D.new()
		collider.polygon = polygon
		grabArea.add_child(collider)

		var outline = outlineScene.instantiate()
		outline.points = polygon
		outline.add_point(outline.points[0])
		outline.visibility_layer = 2
		grabArea.add_child(outline)
	size = imageData.get_size()

	sprite.offset = offset
	
	grabArea.position = (size*-0.5) + offset
	
	if !b:
		remakePolygon()

func replaceSpriteFromData(img: Image, layer_name: String):
	path = "psd://" + layer_name
	imageData = img
	invalidate_used_rect_cache()
	tex = _make_premultiplied_texture(img)

	# Clear normal if new diffuse has different dimensions
	if hasNormalMap() and normalImageData.get_size() != img.get_size():
		clearNormalMap()
		Global.pushUpdate("Normal map cleared (size mismatch after replace).")
	else:
		_rebuild_sprite_texture()

	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(imageData)
	var polygons = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()))

	for i in grabArea.get_children():
		i.queue_free()

	var b = false
	for polygon in polygons:
		b = true
		var collider = CollisionPolygon2D.new()
		collider.polygon = polygon
		grabArea.add_child(collider)
		var outline = outlineScene.instantiate()
		outline.points = polygon
		outline.add_point(outline.points[0])
		outline.visibility_layer = 2
		grabArea.add_child(outline)

	size = imageData.get_size()
	sprite.offset = offset
	grabArea.position = (size * -0.5) + offset

	if !b:
		remakePolygon()

func _process(delta):
	# While the window is being resized, freeze the avatar entirely: don't
	# advance wobble/animation/drag, since the viewport size and origin position
	# are mid-flight and feeding partial deltas into physics produces visible
	# glitches and stretches. main.gd flips Global.main.resize_active to true
	# when size changes and back to false (with a one-shot drag-snap) when it
	# stabilizes.
	if Global.main != null and Global.main.resize_active:
		return
	tick += 1
	if Global.heldSprite == self:

		grabArea.visible = true
		originSprite.visible = true

		var cam_zoom = Global.main.camera.zoom.x
		for child in grabArea.get_children():
			if child is Line2D:
				child.width = 3.0 / cam_zoom

	else:
		grabArea.visible = false
		originSprite.visible = false
	
	if staticElement:
		# Follow drag, wobble, rotation, and stretch as normal — but cancel the
		# avatar-wide bounce by lerping the dragger toward the un-bounced wob
		# position instead of the bounced one.
		wobble()
		var bounce_offset = Global.main.origin.get_parent().position
		var target = wob.global_position - bounce_offset
		var glob = dragger.global_position
		var did_snap = _force_drag_snap
		if did_snap:
			_force_drag_snap = false
			dragger.global_position = target
		elif dragSpeed == 0:
			dragger.global_position = target
		else:
			dragger.global_position = lerp(dragger.global_position, target, 1.0 / float(dragSpeed))
		dragOrigin.global_position = dragger.global_position
		var length = 0.0 if did_snap else (glob.y - dragger.global_position.y)
		rotationalDrag(length, delta)
		stretch(length, delta)
	else:
		var glob = dragger.global_position
		if ignoreBounce:
			glob.y -= Global.main.bounceChange

		# A snap-frame teleports the dragger; don't let that feed stretch/rotation
		var did_snap = _force_drag_snap
		drag(delta)
		wobble()

		var length = 0.0 if did_snap else (glob.y - dragger.global_position.y)

		rotationalDrag(length,delta)
		stretch(length,delta)
	
	if grabDelay > 0:
		grabDelay -= 1

	if wiggleEnabled:
		_update_wiggle(delta)

	talkBlink()

	if Global.originMode and Global.heldSprite == self:
		var mouse_pos = get_global_mouse_position()
		if mouse_pos.distance_to(sprite.global_position) <= 24.0:
			Global.mouse.text = "Drag origin"

	if !blinkAnimation():
		animation()

func animation():
	
	var speed = max(float(animSpeed),Engine.max_fps*6.0)
	if animSpeed > 0 and frames > 1:
		if Global.animationTick % int((speed)/float(animSpeed)) == 0:
			if sprite.frame == frames - 1:
				sprite.frame = 0
			else:
				sprite.frame += 1
	if frames > 1:
		remakePolygon()

func setZIndex():
	sprite.z_index = z

func talkBlink():
	var faded = 0.2 * int(Global.main.editMode)
	var blinkVal = showOnBlink if showOnBlink != 3 else 0
	var value = (showOnTalk + (blinkVal*3)) + (int(Global.speaking)*10) + (int(Global.blink)*20)
	var yes = VISIBLE_TALKBLINK_STATES.has(int(value))
	var a = max(int(yes),faded)
	sprite.self_modulate = Color(a, a, a, a)
	# When the sprite is only showing because of the edit-mode faded preview, render
	# it on layer 2 so the NDI camera (layer 1 only) doesn't pick up the preview frame.
	sprite.visibility_layer = 2 if (!yes and faded > 0) else 1
	# When wiggling, the ribbon stands in for the (hidden) sprite — fade it identically.
	if _wiggleAppendage != null:
		_wiggleAppendage.self_modulate = sprite.self_modulate
		_wiggleAppendage.visibility_layer = sprite.visibility_layer

func blinkAnimation():
	if showOnBlink != 3 or frames <= 1:
		return false

	if Global.blink and !_prevBlink:
		if _blinkAnimPlaying:
			_blinkQueue += 1
		else:
			_blinkAnimPlaying = true
			_blinkAnimTick = 0
			sprite.frame = 0
	_prevBlink = Global.blink

	if !_blinkAnimPlaying:
		sprite.frame = 0
		return true

	_blinkAnimTick += 1
	var speed = max(float(animSpeed), Engine.max_fps * 6.0)
	if animSpeed > 0:
		if _blinkAnimTick % max(int(speed / float(animSpeed)), 1) == 0:
			if sprite.frame >= frames - 1:
				if _blinkQueue > 0:
					_blinkQueue -= 1
					_blinkAnimTick = 0
					sprite.frame = 0
				else:
					_blinkAnimPlaying = false
					sprite.frame = 0
			else:
				sprite.frame += 1

	return true

func delete():
	queue_free()

func _input(event):
	if !Global.originMode or Global.heldSprite != self:
		_origin_dragging = false
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var gizmo_center = sprite.global_position
			var mouse_pos = get_global_mouse_position()
			if mouse_pos.distance_to(gizmo_center) <= 24.0:
				UndoManager.save_state()
				_origin_dragging = true
				_origin_drag_start_mouse_local = get_parent().to_local(mouse_pos)
				_origin_drag_start_offset = offset
				_origin_drag_start_pos = position
				get_viewport().set_input_as_handled()
		else:
			_origin_dragging = false

	elif event is InputEventMouseMotion and _origin_dragging:
		var mouse_local = get_parent().to_local(get_global_mouse_position())
		var delta = mouse_local - _origin_drag_start_mouse_local
		position = _origin_drag_start_pos + delta
		position = Vector2(int(position.x), int(position.y))
		offset = _origin_drag_start_offset - delta
		offset = Vector2(int(offset.x), int(offset.y))
		sprite.offset = offset
		grabArea.position = (size * -0.5) + offset
		get_viewport().set_input_as_handled()

func _physics_process(delta):
	if Global.heldSprite == self:
		var dir = pressingDirection()
		if Input.is_action_pressed("origin"):
			moveOrigin(dir)
		elif !Global.originMode:
			moveSprite(dir)
	else:
		set_physics_process(false)

func pressingDirection():
	var dir = Vector2.ZERO
	
	dir.x = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	dir.y = Input.get_action_strength("move_up") - Input.get_action_strength("move_down")
	return dir
	
func moveSprite(dir):
	if dir != Vector2.ZERO:
		if heldTicks == 0:
			UndoManager.save_state_continuous()
		heldTicks += 1
	else:
		heldTicks = 0

	if heldTicks > 30 or heldTicks == 1:
		var multiplier = 2
		if heldTicks == 1:
			multiplier = 1
		position -= dir * multiplier
	
	position = Vector2(int(position.x),int(position.y))

func moveOrigin(dir):
	if dir != Vector2.ZERO:
		if origTick == 0:
			UndoManager.save_state_continuous()
		origTick += 1
	else:
		origTick = 0

	if origTick > 30 or origTick == 1:
		var multiplier = 2
		if origTick == 1:
			multiplier = 1

		offset += dir * multiplier
		position -= dir * multiplier

	offset = Vector2(int(offset.x),int(offset.y))

	sprite.offset = offset
	grabArea.position = (size*-0.5) + offset

func snapOriginToMouse():
	var mouse_pos = get_global_mouse_position()
	var new_pos = get_parent().to_local(mouse_pos)
	new_pos = Vector2(int(new_pos.x), int(new_pos.y))
	var delta = new_pos - position
	position = new_pos
	offset -= delta
	offset = Vector2(int(offset.x), int(offset.y))
	sprite.offset = offset
	grabArea.position = (size * -0.5) + offset

func drag(delta):
	if _force_drag_snap:
		_force_drag_snap = false
		dragger.global_position = wob.global_position
		dragOrigin.global_position = dragger.global_position
		return
	if dragSpeed == 0:
		dragger.global_position = wob.global_position
	else:
		dragger.global_position = lerp(dragger.global_position,wob.global_position,1/dragSpeed)
		dragOrigin.global_position = dragger.global_position

func wobble():
	# Skip wobble while NDI ruler is being dragged (frozen at worst-case-down)
	if Global.main.ndi_manager != null and Global.main.ndi_manager.ruler_dragging:
		return
	wob.position.x = sin(tick*xFrq)*xAmp
	wob.position.y = sin(tick*yFrq)*yAmp

	# Look-at target: either the cursor (mode 0) or another sprite's live position (mode 1).
	# Global.eyeTrackingGloballyEnabled is the kill switch from global-scope UI; sprite-level
	# eyeTrack flag is the per-sprite enable. Both must be on to track.
	var target_world_pos = Vector2.ZERO
	var have_target = false
	if eyeTrack and Global.eyeTrackingGloballyEnabled and not (Global.main.editMode and Global.heldSprite == self):
		if eyeTrackMode == 1:
			if eyeTrackTargetId != null:
				var nodes = get_tree().get_nodes_in_group(str(eyeTrackTargetId))
				if nodes.size() > 0 and nodes[0] != self:
					target_world_pos = nodes[0].global_position
					have_target = true
		else:
			target_world_pos = Global.cursorWorldPos
			have_target = true

	if have_target:
		var rest_pos = global_position
		var direction = target_world_pos - rest_pos
		if eyeTrackInvert:
			direction = -direction
		var target_offset = direction.normalized() * min(direction.length(), eyeTrackDistance)
		_eyeTrackOffset = _eyeTrackOffset.lerp(target_offset, eyeTrackSpeed)
		wob.position += _eyeTrackOffset
	else:
		_eyeTrackOffset = _eyeTrackOffset.lerp(Vector2.ZERO, 0.15)
		if _eyeTrackOffset.length() > 0.01:
			wob.position += _eyeTrackOffset

func rotationalDrag(length,delta):
	var yvel = (length * rdragStr)
	
	#Calculate Max angle
	
	yvel = clamp(yvel,rLimitMin,rLimitMax)
	
	sprite.rotation = lerp_angle(sprite.rotation,deg_to_rad(yvel),0.25)

func stretch(length,delta):
	var yvel = (length * stretchAmount * 0.01)
	var target = Vector2(1.0-yvel,1.0+yvel)

	sprite.scale = lerp(sprite.scale,target,0.5)

# --- Wiggle (physics) ---

# Turn wiggle on/off for this layer. When on, the Sprite2D is hidden and a
# textured Line2D ribbon (WiggleAppendage2D) is shown in its place, bending along
# the spring chain. The Physics tab calls this; safe to call any time.
func setWiggle(on: bool):
	wiggleEnabled = on
	_set_wiggle_active(on)
	if not on:
		_release_wiggle_children()

func setWiggleChildrenFollow(on: bool):
	wiggleChildrenFollow = on
	if not on:
		_release_wiggle_children()

func _set_wiggle_active(on: bool):
	if on:
		if _wiggleAppendage == null:
			_wiggleAppendage = _WIGGLE_APPENDAGE.new()
			_wiggleAppendage.texture_mode = Line2D.LINE_TEXTURE_STRETCH
			_wiggleAppendage.joint_mode = Line2D.LINE_JOINT_ROUND
			# No caps: LINE_CAP_BOX/ROUND extend the ribbon by half its width past the
			# root as a rigid stub that never bends. NONE maps the texture exactly to
			# the chain points.
			_wiggleAppendage.begin_cap_mode = Line2D.LINE_CAP_NONE
			_wiggleAppendage.end_cap_mode = Line2D.LINE_CAP_NONE
			dragOrigin.add_child(_wiggleAppendage)
		_rebuild_wiggle_texture()
		_wiggleAppendage.z_index = sprite.z_index
		_wiggleAppendage.configure(_wiggle_params())
		_wiggleAppendage.reset()
		sprite.visible = false
	else:
		if _wiggleAppendage != null:
			_wiggleAppendage.queue_free()
			_wiggleAppendage = null
		sprite.visible = true
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE

# (Re)build the ribbon texture from the raw image (+ normal map if present). The
# appendage length runs along the texture's longer axis; taller-than-wide art is
# rotated so that axis maps along the ribbon (Line2D stretches U along the line).
func _rebuild_wiggle_texture():
	if _wiggleAppendage == null or imageData == null:
		return
	var dimg: Image = imageData
	var nimg: Image = normalImageData
	if imageData.get_height() > imageData.get_width():
		dimg = imageData.duplicate()
		dimg.rotate_90(CLOCKWISE)
		if normalImageData != null:
			nimg = normalImageData.duplicate()
			nimg.rotate_90(CLOCKWISE)
	var diff := ImageTexture.create_from_image(dimg)
	if nimg != null:
		var ct := CanvasTexture.new()
		ct.diffuse_texture = diff
		ct.normal_texture = ImageTexture.create_from_image(nimg)
		_wiggleAppendage.texture = ct
	else:
		_wiggleAppendage.texture = diff
	_wiggleAppendage.width = _wiggle_dims().y

# Per-frame: keep the hidden sprite at identity (so linked children, parented
# under it, map cleanly to the appendage's space), then configure + advance the
# ribbon. The appendage root follows the layer origin in world space, so avatar
# bounce/drag/wobble drive the whip.
func _update_wiggle(delta: float):
	if _wiggleAppendage == null:
		_set_wiggle_active(true)
		return
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	_wiggleAppendage.configure(_wiggle_params())
	_wiggleAppendage.tick(delta, tick)
	if wiggleChildrenFollow:
		_apply_wiggle_to_children()

# Appendage length (along the bend) and cross width, in pixels.
func _wiggle_dims() -> Vector2:
	if imageData == null:
		return Vector2(1, 1)
	var w := float(imageData.get_width())
	var h := float(imageData.get_height())
	return Vector2(h, w) if h > w else Vector2(w, h)

func _wiggle_params() -> Dictionary:
	var dims := _wiggle_dims()
	var segs := clampi(int(wiggleSegments), 1, 24)
	return {
		"segment_count": segs,
		"segment_length": dims.x / float(segs),
		"stiffness": wiggleStiffness,
		"damping": wiggleDamping,
		# Cap per-joint rotation speed and soften joints toward the tip so a root
		# rotation travels down the tail with lag (a smooth wave) instead of the
		# whole chain snapping to follow. Both scale with stiffness, so Stiffness
		# stays the single "snappy vs smooth" knob.
		"max_angular_momentum": clampf(wiggleStiffness * 0.45, 2.0, 30.0),
		"stiffness_decay": wiggleStiffness * 0.05,
		"stiffness_decay_exponent": 1.3,
		"max_angle": deg_to_rad(wiggleMaxBend),
		"comeback_speed": wiggleBendFocus,
		"gravity": Vector2(0.0, wiggleWeight),
		"curvature": 0.0,
		"subdivision": 4,
		"rest_direction_angle": deg_to_rad(wiggleDirection),
		"root_follow_smoothness": clampf(lerp(0.85, 0.2, clampf(wiggleReactivity / 3.0, 0.0, 1.0)), 0.05, 0.95),
		"auto_wag": wiggleWagEnabled,
		"wag_speed": wiggleWagSpeed,
		"wag_amount": deg_to_rad(wiggleWagAmount),
	}

# Make directly-linked children ride the ribbon: place each at the chain point
# matching its rest distance along the appendage. The hidden sprite is held at
# identity, so its local space matches the appendage's. Deeper descendants follow
# for free via the scene tree.
func _apply_wiggle_to_children():
	if _wiggleAppendage == null:
		return
	var dir := deg_to_rad(wiggleDirection)
	var total := maxf(_wiggle_dims().x, 1.0)
	for child in getAllLinkedSprites():
		if not child._wiggleFollowing:
			child._wiggleRestPos = child.position
			child._wiggleRestRot = child.rotation
			child._wiggleFollowing = true
		var along: float = child._wiggleRestPos.rotated(-dir).x   # rest distance along the appendage
		var t := clampf(along / total, 0.0, 1.0)
		var p: Vector2 = _wiggleAppendage.sample_local(t)
		var tangent: Vector2 = _wiggleAppendage.sample_local(minf(t + 0.05, 1.0)) - p
		child.position = p
		if tangent.length() > 0.001:
			child.rotation = child._wiggleRestRot + (tangent.angle() - dir)

# Restore any children we were driving back to their captured rest transform.
func _release_wiggle_children():
	for child in getAllLinkedSprites():
		if child._wiggleFollowing:
			child.position = child._wiggleRestPos
			child.rotation = child._wiggleRestRot
			child._wiggleFollowing = false

func changeCollision(enable):
	grabArea.monitorable = enable
	grabArea.monitorable = enable

func changeFrames():
	sprite.hframes = frames
	sprite.frame = 0

func remakePolygon():
	if remadePolygon:
		return
	for c in grabArea.get_children():
		c.queue_free()
	var collider = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(imageSize.y,imageSize.y)
	collider.shape = shape
	collider.position = Vector2(imageSize.x,imageSize.y) * Vector2(0.5,0.5)
	grabArea.add_child(collider)
	
	var p = imageSize.y * 0.5
	var outline = outlineScene.instantiate()
	outline.visibility_layer = 2
	outline.add_point(Vector2(-p,-p))
	outline.add_point(Vector2(p,-p))
	outline.add_point(Vector2(p,p))
	outline.add_point(Vector2(-p,p))
	outline.add_point(Vector2(-p,-p))
	outline.position = collider.position
	grabArea.add_child(outline)
	
	remadePolygon = true
	
func setClip(toggle):
	if toggle:
		sprite.clip_children = CLIP_CHILDREN_AND_DRAW

		for node in getAllDescendants():
			node.z = z
			node.setZIndex()

	else:
		sprite.clip_children = CLIP_CHILDREN_DISABLED

	clipped = toggle

func getAllLinkedSprites():
	var nodes = get_tree().get_nodes_in_group("saved")
	var linkedSprites = []
	for node in nodes:
		if node.parentId == id:
			linkedSprites.append(node)
	return linkedSprites

func getAllDescendants() -> Array:
	var result = []
	var stack = getAllLinkedSprites()
	while stack.size() > 0:
		var current = stack.pop_back()
		result.append(current)
		for node in get_tree().get_nodes_in_group("saved"):
			if node.parentId == current.id:
				stack.append(node)
	return result

func visToggle(keys):
	if Global.awaitingToggleBind: return
	if keys.has(toggle):
		$WobbleOrigin/DragOrigin.visible = !$WobbleOrigin/DragOrigin.visible

func makeVis():
	$WobbleOrigin/DragOrigin.visible = true
