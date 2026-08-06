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
const CollisionBuilder = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")

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
var _micRot = 0.0   # smoothed mic-driven rotation, kept separate from sprite.rotation so
					# eye-track rotation isn't fed back into its own smoothing (→ spin)

#Layer
var costumeLayers = [1,1,1,1,1,1,1,1,1,1]
# Manual eye-button hide (layer-list ●/○), runtime only. Kept separate from the
# costume system so re-applying costume visibility (on selection / costume change)
# doesn't clobber it.
var userHidden = false

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
var eyeTrackMode = 0  # TARGET: 0 = cursor, 1 = layer (UI label "Target")
var eyeTrackTargetId = null  # int sprite id when eyeTrackMode == 1
var eyeTrackType = 0  # MODE: 0 = Position (translate toward target), 1 = Rotation (swivel toward it) — UI label "Mode"
var eyeTrackForward = 0  # DEPRECATED (2026-06-04): the "Up side" control was removed — the saddle is X/Y-symmetric so it only flipped sign (redundant with Invert). Kept at default 0 for save compat; no longer read by the formula or any UI.
var _eyeTrackOffset = Vector2.ZERO
var _eyeTrackRotation = 0.0  # runtime: smoothed eye-track rotation, radians (Rotation mode)

# Animation clips — per-layer keyframe/transform animations (rotation + translation),
# evaluated by effects/animation/layer_animator.gd. Triggered at random, by keypress,
# always-on, or manually. The legacy wobble (xFrq/xAmp/yFrq/yAmp) migrates into an
# always-on oscillate/translation clip here (see migrateLegacyWobble). Persisted as
# animClips (var_to_str). _animRot rides DragOrigin (so it also swings the wiggle
# chain); _animTrans feeds WobbleOrigin.position in wobble().
var animClips: Array = []
var _animator = null
var _animRot := 0.0
var _animTrans := Vector2.ZERO
var _anim_had_clips := false

# Blend mode + opacity (per-layer compositing). blendMode is a BlendMode.Mode int;
# opacity (0..1) is folded into the talk/blink self_modulate every frame (see talkBlink).
# Normal/Add/Subtract render natively; the rest use the blend shader + a BackBufferCopy
# (effects/blend/). Persisted; backward-compatible (default Normal / fully opaque).
var blendMode: int = 0
var opacity: float = 1.0
var _blendBackBuffer: BackBufferCopy = null

# Wiggle (physics) — bends this layer with a deformable textured MESH driven by an
# angular-spring chain whose REST shape is a user-traced path over the layer's
# content (effects/wiggle/). The mesh's per-vertex UVs map straight to the layer
# texture, so at rest it IS the artwork exactly (no distortion, even on curves) and
# only deforms when it moves. This is what lets irregular, off-origin, oversized
# (canvas-sized) layers wiggle correctly. Persisted; backward-compatible (auto-fit
# when a wiggle layer has no path).
var wiggleEnabled = false
var wigglePath: PackedVector2Array = PackedVector2Array()        # rest centerline, texture-local px
var wigglePathWidths: PackedFloat32Array = PackedFloat32Array()  # per-point half-width px (taper-ready)
var wiggleThickness = 1.0       # global multiplier over the per-point widths (uniform-thickness knob)
var wiggleSegments = 12         # physics resolution (chain joints resampled from the path)
var wiggleStiffness = 20.0
var wiggleDamping = 5.0
var wiggleWeight = 0.0          # gravity droop strength
var wiggleMaxBend = 25.0        # max bend per joint, degrees
var wiggleBendFocus = 0.4       # comeback speed off the angle limit (springiness)
var wiggleShapeReturn = 0.0     # over-damped pull back to the original (rest) shape
var wiggleWagEnabled = true     # auto-wag drives a side-to-side sweep
var wiggleWagAmount = 15.0      # auto-wag base-sway amplitude, degrees
var wiggleWagSpeed = 0.12
var wiggleReactivity = 1.0      # how snappily the base tracks the layer (higher = more immediate, lower = floatier)
var wiggleMotionIntensity = 1.0 # master scale on motion-imparted wiggle (1 = normal, 0 = ignores motion)
var wiggleChildrenFollow = false

const _WIGGLE_APPENDAGE = preload("res://effects/wiggle/wiggle_appendage.gd")
const _WIGGLE_PATH_EDITOR = preload("res://effects/wiggle/wiggle_path_editor.gd")
var _wiggleAppendage: WiggleAppendage2D = null
var _wigglePathEditor = null     # on-canvas WigglePathEditor while editing this layer's path
var _wigglePathEditPrevVisible = false
var _wiggleSmooth: PackedVector2Array = PackedVector2Array()  # cached smooth rest centerline, texture-local
# Set on this layer while a wiggle parent drives it (child-follow); stores rest transform.
var _wiggleRestPos = Vector2.ZERO
var _wiggleRestRot = 0.0
var _wiggleFollowing = false

const _WIGGLE_WIDTH_MIN := 4.0
const _WIGGLE_WIDTH_MARGIN := 3.0
const _WIGGLE_WIDTH_GROW := 1.08

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
var _last_visual_key := -1
var _last_visual_opacity := -1.0
var _last_visual_has_wiggle := false
var _last_visual_has_editor := false

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
	# Refresh the wiggle mesh when the image/normal changes: it samples the layer's
	# texture directly, so re-point it and rebuild the geometry/UVs.
	if _wiggleAppendage != null:
		_wiggleAppendage.texture = sprite.texture
		_apply_wiggle_geometry()

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

	# Compositing material (blend mode) + the optional screen-read backbuffer. Defaults to
	# Normal, i.e. a premultiplied-alpha CanvasItemMaterial (identical to the prior behaviour).
	applyBlendMode()

	# Use prebuilt polygons if available (from threaded import)
	var polygons
	if _prebuilt_polygons.size() > 0:
		polygons = _prebuilt_polygons
		_prebuilt_polygons = []
	else:
		polygons = CollisionBuilder.alpha_polygons(imageData)

	var has_collision := CollisionBuilder.populate_polygons(grabArea, outlineScene, polygons)

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
	if not has_collision:
		remakePolygon()
	
	
	add_to_group(str(id))
	Global.register_sprite(self)

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

func _exit_tree() -> void:
	Global.unregister_sprite(self)
	
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
	
	CollisionBuilder.clear(grabArea)
	var polygons := CollisionBuilder.alpha_polygons(imageData)
	var has_collision := CollisionBuilder.populate_polygons(grabArea, outlineScene, polygons)
	size = imageData.get_size()

	sprite.offset = offset
	
	grabArea.position = (size*-0.5) + offset
	
	remadePolygon = false
	if not has_collision:
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

	CollisionBuilder.clear(grabArea)
	var polygons := CollisionBuilder.alpha_polygons(imageData)
	var has_collision := CollisionBuilder.populate_polygons(grabArea, outlineScene, polygons)

	size = imageData.get_size()
	sprite.offset = offset
	grabArea.position = (size * -0.5) + offset

	remadePolygon = false
	if not has_collision:
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
	_anim_update(delta)
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

	# Eye-track Rotation composes with the mic rotational sway. rotationalDrag smooths
	# into its own _micRot (not sprite.rotation), so the look-at is added cleanly here
	# without feeding back into that smoothing (which compounded into a runaway spin).
	sprite.rotation = _micRot + _eyeTrackRotation

	# Animation rotation rides on DragOrigin (outermost on the layer), so it swings
	# the visible Sprite2D AND, for wiggle layers, the mesh + chain anchor — the
	# twitch drives the verlet chain into secondary motion. Suppressed while tracing
	# a wiggle path (the editor works over the static, un-rotated sprite).
	dragOrigin.rotation = 0.0 if _wigglePathEditor != null else _animRot

	if grabDelay > 0:
		grabDelay -= 1

	_update_path_editor()
	# While the path is being traced the static Sprite2D stands in for tracing and
	# the ribbon is hidden, so there's nothing to advance.
	if wiggleEnabled and _wigglePathEditor == null:
		_update_wiggle(delta)

	talkBlink()

	if Global.originMode and Global.heldSprite == self:
		var mouse_pos = get_global_mouse_position()
		if mouse_pos.distance_to(sprite.global_position) <= 24.0:
			Global.mouse.text = "Drag origin"

	if !blinkAnimation():
		animation()

func animation():
	if frames <= 1:
		return
	var speed = max(float(animSpeed),Engine.max_fps*6.0)
	if animSpeed > 0:
		if Global.animationTick % int((speed)/float(animSpeed)) == 0:
			if sprite.frame == frames - 1:
				sprite.frame = 0
			else:
				sprite.frame += 1
	remakePolygon()

func setZIndex():
	sprite.z_index = z
	# Keep the wiggle ribbon at the same depth as the sprite it stands in for, so
	# reordering a wiggling layer re-depths the ribbon too (not just the sprite).
	if _wiggleAppendage != null:
		_wiggleAppendage.z_index = z
	# The blend backbuffer copies at the layer's depth too, so it snapshots exactly the
	# layers drawn below this one.
	if _blendBackBuffer != null:
		_blendBackBuffer.z_index = z

# Apply the current blend mode to the Sprite2D's material + the optional backbuffer.
# Native tier (Normal/Add/Subtract) uses a CanvasItemMaterial and needs no screen read;
# every other mode uses the shared blend shader fed by a BackBufferCopy. Safe to re-call.
func applyBlendMode():
	if BlendMode.needs_backbuffer(blendMode):
		var sm: ShaderMaterial
		if sprite.material is ShaderMaterial:
			sm = sprite.material
		else:
			sm = ShaderMaterial.new()
			sm.shader = BlendMode.SHADER
			sprite.material = sm
		sm.set_shader_parameter("blend_mode", blendMode)
		_ensure_blend_backbuffer(true)
	else:
		var cm: CanvasItemMaterial
		if sprite.material is CanvasItemMaterial:
			cm = sprite.material
		else:
			cm = CanvasItemMaterial.new()
			sprite.material = cm
		cm.blend_mode = BlendMode.native_blend(blendMode)
		_ensure_blend_backbuffer(false)
	# The wiggle ribbon stands in for the (hidden) Sprite2D, so keep it on the same material.
	if _wiggleAppendage != null:
		_wiggleAppendage.material = sprite.material

# Create/remove the BackBufferCopy that feeds screen-reading blend modes. It sits as the
# first child of DragOrigin — drawn before the Sprite/ribbon — at the layer's absolute z,
# so its viewport snapshot contains exactly the layers below this one.
func _ensure_blend_backbuffer(enabled: bool):
	if enabled:
		if _blendBackBuffer == null:
			_blendBackBuffer = BackBufferCopy.new()
			_blendBackBuffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			_blendBackBuffer.z_as_relative = false
			_blendBackBuffer.z_index = z
			dragOrigin.add_child(_blendBackBuffer)
			dragOrigin.move_child(_blendBackBuffer, 0)
	elif _blendBackBuffer != null:
		_blendBackBuffer.queue_free()
		_blendBackBuffer = null

func talkBlink():
	var faded = 0.2 * int(Global.main.editMode)
	var blinkVal = showOnBlink if showOnBlink != 3 else 0
	var value = (showOnTalk + (blinkVal*3)) + (int(Global.speaking)*10) + (int(Global.blink)*20)
	var yes = VISIBLE_TALKBLINK_STATES.has(int(value))
	var a = max(int(yes),faded)
	# Fold per-layer opacity into the same gray self_modulate: premultiplied content scales
	# correctly when every channel is multiplied by o, and shader blend modes read it as COLOR.a.
	var o = a * opacity
	var visual_key := int(value) | (int(faded > 0) << 8)
	var has_wiggle := _wiggleAppendage != null
	var has_editor := _wigglePathEditor != null
	if visual_key == _last_visual_key and is_equal_approx(o, _last_visual_opacity) \
		and has_wiggle == _last_visual_has_wiggle and has_editor == _last_visual_has_editor:
		return
	_last_visual_key = visual_key
	_last_visual_opacity = o
	_last_visual_has_wiggle = has_wiggle
	_last_visual_has_editor = has_editor
	sprite.self_modulate = Color(o, o, o, o)
	# When the sprite is only showing because of the edit-mode faded preview, render
	# it on layer 2 so the NDI camera (layer 1 only) doesn't pick up the preview frame.
	sprite.visibility_layer = 2 if (!yes and faded > 0) else 1
	# When wiggling, the ribbon stands in for the (hidden) sprite — fade it identically.
	if _wiggleAppendage != null:
		_wiggleAppendage.self_modulate = sprite.self_modulate
		_wiggleAppendage.visibility_layer = sprite.visibility_layer
	# While tracing the ribbon path, the Sprite2D is the tracing target: show it
	# solid (overriding talk/blink fade) but on layer 2 so the NDI cam ignores it.
	if _wigglePathEditor != null:
		sprite.self_modulate = Color(1, 1, 1, 1)
		sprite.visibility_layer = 2

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
		# Snap the drag delta to a whole pixel ONCE and apply it equally/oppositely, so position
		# and offset stay exactly coupled. Truncating each independently (int() rounds toward
		# zero) drifted them apart by a pixel when both had the same sign — moving the artwork.
		var idelta = Vector2(roundi(delta.x), roundi(delta.y))
		position = _origin_drag_start_pos + idelta
		offset = _origin_drag_start_offset - idelta
		sprite.offset = offset
		grabArea.position = (size * -0.5) + offset
		_sync_wiggle_to_offset()
		get_viewport().set_input_as_handled()

func _physics_process(delta):
	if Global.heldSprite == self:
		var dir = pressingDirection()
		if Input.is_action_pressed("origin"):
			moveOrigin(dir)
		elif !Global.originMode and !Global.wigglePathMode:
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
	_sync_wiggle_to_offset()

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
	_sync_wiggle_to_offset()

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
	# Skip wobble while the NDI crop box is being dragged (frozen at worst-case-down)
	if Global.main.ndi_manager != null and Global.main.ndi_manager.crop_dragging:
		return
	# Base layer translation comes from animation clips (the legacy wobble migrates
	# into an oscillate/translation clip that reproduces sin(tick*freq)*amp exactly).
	# Eye-track then adds its offset on top, below.
	wob.position = _animTrans

	# Look-at target: either the cursor (mode 0) or another sprite's live position (mode 1).
	# Global.eyeTrackingGloballyEnabled is the kill switch from global-scope UI; sprite-level
	# eyeTrack flag is the per-sprite enable. Both must be on to track.
	var target_world_pos = Vector2.ZERO
	var have_target = false
	if eyeTrack and Global.eyeTrackingGloballyEnabled and not (Global.main.editMode and Global.heldSprite == self):
		if eyeTrackMode == 1:
			if eyeTrackTargetId != null:
				var target_sprite := Global.sprite_by_id(eyeTrackTargetId)
				if target_sprite != null and target_sprite != self:
					target_world_pos = target_sprite.global_position
					have_target = true
		else:
			target_world_pos = Global.cursorWorldPos
			have_target = true

	if have_target:
		var rest_pos = global_position
		var to_target = target_world_pos - rest_pos
		if eyeTrackType == 1:
			# Rotation = LIMITED head-tilt that tracks the cursor's VERTICAL position on
			# whichever side it's on: the side nearest the cursor lifts toward an upper
			# cursor and drops toward a lower one. It's a saddle — the screen-frame
			# horizontal × vertical cursor offset — so it's 0 when the cursor is straight
			# up/down or straight to a side, peaks (±eyeTrackDistance°) at the diagonals,
			# and reverses across the artwork's center lines. Referenced from the artwork's
			# VISUAL CENTER (not the origin), so the reversal lands on the artwork's 50%
			# line wherever the origin sits. Default (no invert): cursor upper-left -> top
			# tilts right (left side lifts), upper-right -> top left; lower mirrors. Invert
			# flips the lean.
			var center_world = rest_pos
			var ur = get_image_used_rect()
			if imageData != null and ur.size.x > 0 and ur.size.y > 0:
				center_world = dragOrigin.to_global(_tex_to_local(Vector2(ur.position) + Vector2(ur.size) * 0.5))
			var d = target_world_pos - center_world
			var max_rad = deg_to_rad(eyeTrackDistance)
			var target_rot = 0.0
			if d.length() > 0.001:
				var u = d.normalized()
				var sgn = -1.0 if eyeTrackInvert else 1.0
				target_rot = clampf(sgn * 2.0 * max_rad * u.x * u.y, -max_rad, max_rad)
			_eyeTrackRotation = lerp_angle(_eyeTrackRotation, target_rot, eyeTrackSpeed)
			_eyeTrackOffset = _eyeTrackOffset.lerp(Vector2.ZERO, 0.15)
			if _eyeTrackOffset.length() > 0.01:
				wob.position += _eyeTrackOffset
		else:
			# Position mode: translate toward the target, capped at eyeTrackDistance px.
			var direction = to_target
			if eyeTrackInvert:
				direction = -direction
			var target_offset = direction.normalized() * min(direction.length(), eyeTrackDistance)
			_eyeTrackOffset = _eyeTrackOffset.lerp(target_offset, eyeTrackSpeed)
			wob.position += _eyeTrackOffset
			_eyeTrackRotation = lerp(_eyeTrackRotation, 0.0, eyeTrackSpeed)
	else:
		_eyeTrackOffset = _eyeTrackOffset.lerp(Vector2.ZERO, 0.15)
		if _eyeTrackOffset.length() > 0.01:
			wob.position += _eyeTrackOffset
		_eyeTrackRotation = lerp(_eyeTrackRotation, 0.0, 0.15)

func rotationalDrag(length,delta):
	var yvel = (length * rdragStr)
	
	#Calculate Max angle
	
	yvel = clamp(yvel,rLimitMin,rLimitMax)

	_micRot = lerp_angle(_micRot, deg_to_rad(yvel), 0.25)
	sprite.rotation = _micRot

func stretch(length,delta):
	var yvel = (length * stretchAmount * 0.01)
	var target = Vector2(1.0-yvel,1.0+yvel)

	sprite.scale = lerp(sprite.scale,target,0.5)

# --- Animation clips ---

# Advance this layer's animation clips one frame; results land in _animRot /
# _animTrans (consumed by the rotation composite and wobble() respectively).
func _anim_update(delta):
	if animClips.is_empty():
		if _anim_had_clips and _animator != null:
			_animator.reset()
		_anim_had_clips = false
		_animRot = 0.0
		_animTrans = Vector2.ZERO
		return
	_anim_had_clips = true
	if _animator == null:
		_animator = LayerAnimator.new()
	_animator.evaluate(animClips, tick, delta)
	_animRot = _animator.rot
	_animTrans = _animator.trans

# Fire every key-triggered clip bound to keystr (called from main.gd's background
# key handler). Cheap no-op when this layer has no key clips.
func triggerAnimationKey(keystr: String):
	if _animator == null:
		_animator = LayerAnimator.new()
	_animator.fire_key(animClips, keystr)

# Fire a single clip's one-shot now (the Animation tab "Test" button).
func triggerAnimationClip(i: int):
	if _animator == null:
		_animator = LayerAnimator.new()
	_animator.fire_clip(animClips, i)

# Live {active, ph} of clip i for the Animation tab's curve-preview dot.
func getAnimSample(i: int) -> Dictionary:
	if _animator == null:
		return {"active": false, "ph": 0.0}
	return _animator.sample(i)

# Back-compat: fold a legacy wobble (xFrq/xAmp/yFrq/yAmp) into an always-on
# oscillate/translation clip. Called on load for avatars saved before animClips
# existed. The legacy fields are left intact (older app builds still read them).
func migrateLegacyWobble():
	if xAmp == 0.0 and yAmp == 0.0:
		return
	animClips.append({
		"name": "Wobble",
		"channel": "translation",
		"shape": "oscillate",
		"trigger": "always",
		"ampX": xAmp, "freqX": xFrq, "ampY": yAmp, "freqY": yFrq,
	})

# --- Wiggle (physics) ---

# Turn wiggle on/off for this layer. When on, the Sprite2D is hidden and a
# deformable textured mesh (WiggleAppendage2D) is shown in its place, bending along
# the spring chain. The Physics tab calls this; safe to call any time.
func setWiggle(on: bool):
	wiggleEnabled = on
	_set_wiggle_active(on)   # _set_wiggle_active(false) releases linked children

func setWiggleChildrenFollow(on: bool):
	wiggleChildrenFollow = on
	if not on:
		_release_wiggle_children()

func _set_wiggle_active(on: bool):
	_last_visual_key = -1
	if on:
		if wigglePath.size() < 2:
			_auto_fit_wiggle_path()
		if _wiggleAppendage == null:
			_wiggleAppendage = _WIGGLE_APPENDAGE.new()
			# Match the Sprite2D's absolute z so the mesh sits at the layer's real
			# depth (the Sprite is z_as_relative=false; a plain node defaults to
			# relative, which mis-orders it once layers are reparented/linked).
			_wiggleAppendage.z_as_relative = false
			dragOrigin.add_child(_wiggleAppendage)
		# The deformable mesh samples the layer's own texture directly (the same
		# CanvasTexture the Sprite2D uses, so normals come along). Match the sprite's
		# filter (Linear; the project default is Nearest → stair-stepped edges) AND
		# its premultiplied-alpha blend material — the textures are premultiplied, so
		# without it the mesh blends them as straight alpha and a dark fringe bleeds
		# in along the edges.
		_wiggleAppendage.texture = sprite.texture
		_wiggleAppendage.texture_filter = sprite.texture_filter
		_wiggleAppendage.material = sprite.material
		_wiggleAppendage.z_index = z
		_apply_wiggle_geometry()     # builds chain rest + the deformable mesh
		_wiggleAppendage.configure(_wiggle_params())
		_wiggleAppendage.reset()
		sprite.visible = false
	else:
		# Return linked children under the Sprite2D before it becomes visible again.
		_release_wiggle_children()
		if _wiggleAppendage != null:
			_wiggleAppendage.queue_free()
			_wiggleAppendage = null
		sprite.visible = true
		sprite.rotation = 0.0
		sprite.scale = Vector2.ONE

# --- Ribbon path editor (Phase 2) ---

# Create/destroy the on-canvas path editor as Global.wigglePathMode toggles for
# this layer. Polled each frame (state-driven, like the rest of the app).
func _update_path_editor():
	var want: bool = Global.wigglePathMode and Global.heldSprite == self
	if want and _wigglePathEditor == null:
		_enter_path_edit()
	elif not want and _wigglePathEditor != null:
		_exit_path_edit()

func _enter_path_edit():
	if wigglePath.size() < 2:
		_auto_fit_wiggle_path()
	_wigglePathEditor = _WIGGLE_PATH_EDITOR.new()
	dragOrigin.add_child(_wigglePathEditor)
	_wigglePathEditor.setup(self)
	# Show the real artwork to trace over; hide the (now stale) ribbon stand-in.
	_wigglePathEditPrevVisible = sprite.visible
	sprite.visible = true
	if _wiggleAppendage != null:
		_wiggleAppendage.visible = false

func _exit_path_edit():
	if _wigglePathEditor != null:
		_wigglePathEditor.queue_free()
		_wigglePathEditor = null
	# Rebuild the ribbon from the edited path and restore the wiggle/idle look.
	if _wiggleAppendage != null:
		_apply_wiggle_geometry()
		_wiggleAppendage.reset()
		_wiggleAppendage.visible = true
		sprite.visible = false
	else:
		sprite.visible = _wigglePathEditPrevVisible

# Rebuild geometry after an external path/width/coverage change (editor commit,
# auto-fit, coverage slider). No-op when the mesh isn't built yet — the path is
# simply stored until wiggle is enabled.
func apply_wiggle_path_changed():
	if _wiggleAppendage != null:
		_apply_wiggle_geometry()
		_wiggleAppendage.reset()

# The "Auto-fit" button: re-detect the spine (centerline trace) AND the band
# (silhouette fit) from the content — a full auto from scratch. Undoable (the
# Physics tab saves undo state first), so it's safe to use as a reset.
func wiggle_auto_fit_path():
	_auto_fit_wiggle_path()
	apply_wiggle_path_changed()
	if _wigglePathEditor != null:
		_wigglePathEditor.queue_redraw()

# Rebuild the chain rest shape + the deformable mesh from the current path. Call on
# enable and whenever the path, widths, segment count, or image change. Cheap
# enough to be event-driven (NOT per frame).
func _apply_wiggle_geometry():
	if _wiggleAppendage == null or imageData == null or wigglePath.size() < 2:
		return
	_wiggleSmooth = WiggleAppendage2D.smooth_path(wigglePath, 10)   # texture-local px
	if _wiggleSmooth.size() < 2:
		_wiggleSmooth = wigglePath
	_rebuild_wiggle_chain()
	# Build the deformable mesh: per-along widths (incl thickness) + the UV offset
	# (the path root in texture pixels) so each vertex maps to the real artwork.
	_wiggleAppendage.build_mesh(_smooth_widths(_wiggleSmooth), _wiggleSmooth[0])

# Chain-only rebuild from the cached smooth path: anchor the ribbon at the path
# root and pass the rest path relative to it, so the chain pivots where the user
# said the base is (not the layer origin). Cheap — also used on resolution change.
func _rebuild_wiggle_chain():
	if _wiggleAppendage == null or _wiggleSmooth.size() < 2:
		return
	var root_local := _tex_to_local(_wiggleSmooth[0])
	_wiggleAppendage.position = root_local
	var rest_rel := PackedVector2Array()
	for p in _wiggleSmooth:
		rest_rel.append(_tex_to_local(p) - root_local)
	_wiggleAppendage.set_geometry(rest_rel, clampi(int(wiggleSegments), 2, 48))

# Texture-pixel -> appendage/dragOrigin local. The Sprite2D is centered, shifted
# by `offset`, so texture (px) maps to local (px - size/2 + offset).
func _tex_to_local(tex_px: Vector2) -> Vector2:
	return tex_px - Vector2(size) * 0.5 + offset

func _local_to_tex(local: Vector2) -> Vector2:
	return local + Vector2(size) * 0.5 - offset

# Re-anchor the wiggle mesh after the origin (offset) moves. The mesh sits at
# _tex_to_local(path root), which includes `offset`; moving the origin shifts both
# `position` (+d) and `offset` (-d), and the Sprite2D compensates via sprite.offset,
# but the mesh would otherwise ride `position` and visibly slide. Its rest vertices
# are offset-independent (the offset cancels in `_tex_to_local(p) - root`), so only the
# anchor position needs updating — no rebuild, no chain reset.
func _sync_wiggle_to_offset():
	if _wiggleAppendage != null and not _wiggleSmooth.is_empty():
		_wiggleAppendage.position = _tex_to_local(_wiggleSmooth[0])

# Per-smooth-point half-widths (px): the per-control-point widths interpolated
# along the smooth path, scaled by the global thickness knob. This sets how far the
# mesh band reaches perpendicular to the path (how much of the layer it covers);
# thickness widens/trims that band. Changing thickness rebuilds the mesh.
func _smooth_widths(smooth: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := smooth.size()
	var m := wigglePathWidths.size()
	var k := maxf(wiggleThickness, 0.01)
	for i in n:
		if m == 0:
			out.append(16.0 * k)
		elif m == 1:
			out.append(wigglePathWidths[0] * k)
		else:
			var f := float(i) / float(n - 1) * float(m - 1)
			var a := int(f)
			var b := mini(a + 1, m - 1)
			out.append(lerp(wigglePathWidths[a], wigglePathWidths[b], f - float(a)) * k)
	return out

# Approximate the rest centerline that WiggleAppendage2D will actually render.
# Width fitting uses this path instead of the raw controls, so coverage accounts
# for chain resampling / smoothing instead of only measuring at sparse handles.
func _wiggle_mesh_rest_path() -> PackedVector2Array:
	var smooth := WiggleAppendage2D.smooth_path(wigglePath, 10) if wigglePath.size() >= 3 else wigglePath
	if smooth.size() < 2:
		return smooth
	var joints := WiggleAppendage2D.resample_equal_arc(smooth, clampi(int(wiggleSegments), 2, 48) + 1)
	if joints.size() < 3:
		return joints
	var seg := maxi(joints.size() - 1, 1)
	var per := clampi(int(ceil(float(WiggleAppendage2D.RENDER_POINTS) / float(seg))), 4, 48)
	return WiggleAppendage2D.smooth_path(joints, per)


# Auto path: trace the artwork's centerline (medial spine) so it follows the
# content's curve, adding as many points as the curve needs. Falls back to a
# straight principal-axis path if the shape can't be traced. Endpoints are pushed
# out to the true tip so the band's end-cap doesn't clip pointed ends, then the band
# is sized to the actual silhouette.
func _auto_fit_wiggle_path():
	var traced := _trace_centerline()
	if traced.size() >= 2:
		wigglePath = traced
	else:
		var r := get_image_used_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			r = Rect2i(0, 0, int(Vector2(size).x), int(Vector2(size).y))
		var center := Vector2(r.position) + Vector2(r.size) * 0.5
		var horizontal := r.size.x >= r.size.y
		var half_len := (float(r.size.x) if horizontal else float(r.size.y)) * 0.5
		var axis := Vector2.RIGHT if horizontal else Vector2.DOWN
		wigglePath = PackedVector2Array([center - axis * half_len, center, center + axis * half_len])
	wigglePath = _extend_ends(wigglePath)
	wigglePath = _orient_path_to_origin(wigglePath)
	_fit_widths_to_content()

# Orient the path so its root (index 0 — the wiggle pivot) is the end nearest the layer
# origin. The trace's endpoint order is otherwise arbitrary (it follows the PCA axis
# sign), which can root a tail/ear at its tip and wiggle it from the wrong end. The
# origin gizmo sits at texture-px `size/2 - offset` (inverse of _tex_to_local at local
# 0,0), so the user picks the base simply by placing the origin near it.
func _orient_path_to_origin(path: PackedVector2Array) -> PackedVector2Array:
	if path.size() < 2:
		return path
	var origin_tex: Vector2 = Vector2(size) * 0.5 - offset
	if path[path.size() - 1].distance_squared_to(origin_tex) < path[0].distance_squared_to(origin_tex):
		var rev := PackedVector2Array()
		for i in range(path.size() - 1, -1, -1):
			rev.append(path[i])
		return rev
	return path

# Push each endpoint outward along the path tangent by however far the opaque content
# overhangs it, so the band's flat end-cap reaches past a pointed/rounded tip instead
# of clipping it. A flat attachment (no overhang along the tangent) is left in place,
# so it doesn't push the base out into empty space.
func _extend_ends(path: PackedVector2Array) -> PackedVector2Array:
	if imageData == null or path.size() < 2:
		return path
	var img: Image = imageData
	var reach := maxf(float(img.get_width()), float(img.get_height()))
	var out := path.duplicate()
	var n := out.size()
	var d0 := out[0] - out[1]
	if d0.length() > 0.001:
		d0 = d0.normalized()
		var over0 := _content_reach(img, out[0], d0, reach, 0.05)
		if over0 > 0.5:
			out[0] = out[0] + d0 * (over0 + 1.0)
	var d1 := out[n - 1] - out[n - 2]
	if d1.length() > 0.001:
		d1 = d1.normalized()
		var over1 := _content_reach(img, out[n - 1], d1, reach, 0.05)
		if over1 > 0.5:
			out[n - 1] = out[n - 1] + d1 * (over1 + 1.0)
	return out

# Trace the centerline of the opaque content: PCA for the main axis, start from an
# interior spine point, walk both ways re-centering on each perpendicular
# cross-section (so it follows curves), then simplify (Douglas-Peucker) to control
# points. Texture-px. Empty if the content is too small.
func _trace_centerline() -> PackedVector2Array:
	if imageData == null:
		return PackedVector2Array()
	var img: Image = imageData
	var w := img.get_width()
	var h := img.get_height()
	var reach := float(maxi(w, h))
	var stride := maxi(1, int(reach / 200.0))
	var sum := Vector2.ZERO
	var cnt := 0
	var samples: Array = []
	for y in range(0, h, stride):
		for x in range(0, w, stride):
			if _alpha_at(img, x, y) > 0.5:
				var p := Vector2(x, y)
				samples.append(p)
				sum += p
				cnt += 1
	if cnt < 6:
		return PackedVector2Array()
	var centroid: Vector2 = sum / float(cnt)
	var cxx := 0.0
	var cxy := 0.0
	var cyy := 0.0
	for p in samples:
		var dp: Vector2 = p - centroid
		cxx += dp.x * dp.x
		cxy += dp.x * dp.y
		cyy += dp.y * dp.y
	var axis := Vector2(cos(0.5 * atan2(2.0 * cxy, cxx - cyy)), sin(0.5 * atan2(2.0 * cxy, cxx - cyy)))
	var trace_step := maxf(reach * 0.02, 4.0)
	var start := centroid
	var best := INF
	for p in samples:
		var dd: float = p.distance_to(centroid)
		if dd < best:
			best = dd
			start = p
	start = _spine_center(img, start, axis, reach)[0]
	var fwd := _spine_walk(img, start, axis, trace_step, reach)
	var bwd := _spine_walk(img, start, -axis, trace_step, reach)
	var raw := PackedVector2Array()
	for i in range(bwd.size() - 1, -1, -1):
		raw.append(bwd[i])
	raw.append(start)
	for p in fwd:
		raw.append(p)
	return _simplify_path(raw, clampf(reach * 0.025, 5.0, 14.0))

func _spine_walk(img: Image, start: Vector2, d0: Vector2, trace_step: float, reach: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var P := start
	var d := d0.normalized()
	for s in 500:
		var Pn: Vector2 = P + d * trace_step
		var res := _spine_center(img, Pn, d, reach)
		if not res[1]:
			break
		Pn = res[0]
		var nd: Vector2 = Pn - P
		# End-of-ribbon: a normal step advances ~trace_step; if re-centering snapped
		# the point far across a gap, we walked off a tip and it grabbed distant
		# content (a U-turn back along the shape). Stop instead of following the jump.
		if nd.length() > trace_step * 3.0:
			break
		if nd.length() > 0.001:
			d = nd.normalized()
		out.append(Pn)
		P = Pn
	return out

# Perpendicular-span center at P, and whether P is on/near content.
func _spine_center(img: Image, P: Vector2, d: Vector2, reach: float) -> Array:
	var perp := d.orthogonal()
	var ep := _content_reach(img, P, perp, reach)
	var en := _content_reach(img, P, -perp, reach)
	var on := _alpha_at(img, int(round(P.x)), int(round(P.y))) > 0.25 or ep > 0.0 or en > 0.0
	return [P + perp * (ep - en) * 0.5, on]

func _alpha_at(img: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return 0.0
	return img.get_pixel(x, y).a

# Douglas-Peucker polyline simplification.
func _simplify_path(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep: Dictionary = {0: true, pts.size() - 1: true}
	_dp(pts, 0, pts.size() - 1, eps, keep)
	var idx := keep.keys()
	idx.sort()
	var out := PackedVector2Array()
	for i in idx:
		out.append(pts[i])
	return out

func _dp(pts: PackedVector2Array, lo: int, hi: int, eps: float, keep: Dictionary) -> void:
	if hi <= lo + 1:
		return
	var a: Vector2 = pts[lo]
	var b: Vector2 = pts[hi]
	var ab := b - a
	var len2 := ab.length_squared()
	var dmax := 0.0
	var idx := -1
	for i in range(lo + 1, hi):
		var t := 0.0 if len2 < 0.001 else clampf((pts[i] - a).dot(ab) / len2, 0.0, 1.0)
		var dist: float = pts[i].distance_to(a + ab * t)
		if dist > dmax:
			dmax = dist
			idx = i
	if dmax > eps and idx > 0:
		keep[idx] = true
		_dp(pts, lo, idx, eps, keep)
		_dp(pts, idx, hi, eps, keep)

# Size the band to the artwork's actual silhouette: sample the rendered rest path,
# march perpendicular until the opaque content ends, then pool the sample widths
# back to the user-visible control points. Keeps the band hugging the art without
# clipping bulges between sparse handles.
func _fit_widths_to_content():
	if imageData == null or wigglePath.size() < 1:
		return
	var img: Image = imageData
	var reach := maxf(float(img.get_width()), float(img.get_height()))
	# Measure coverage along the same smoothed / resampled rest centerline that the
	# mesh will render. Then pool each sample's required width back to the adjacent
	# control widths. This is intentionally an envelope: if a bulge falls between two
	# handles, both handles learn about it instead of letting the interpolated band
	# cut a straight chord through the art.
	var smooth := _wiggle_mesh_rest_path()
	if smooth.size() < 2:
		smooth = wigglePath
	var ns := smooth.size()
	var sample_widths := PackedFloat32Array()
	sample_widths.resize(ns)
	for i in ns:
		var a: Vector2 = smooth[maxi(i - 1, 0)]
		var b: Vector2 = smooth[mini(i + 1, ns - 1)]
		var t := b - a
		if t.length() < 0.001:
			t = Vector2.RIGHT
		var perp := t.normalized().orthogonal()
		var c: Vector2 = smooth[i]
		var ext := maxf(
			_content_reach(img, c, perp, reach, 0.08),
			_content_reach(img, c, -perp, reach, 0.08)
		)
		sample_widths[i] = maxf((ext + _WIGGLE_WIDTH_MARGIN) * _WIGGLE_WIDTH_GROW, _WIGGLE_WIDTH_MIN)

	var out := PackedFloat32Array()
	var m := wigglePath.size()
	out.resize(m)
	for i in m:
		out[i] = _WIGGLE_WIDTH_MIN
	if m == 1:
		for w in sample_widths:
			out[0] = maxf(out[0], w)
		wigglePathWidths = out
		return
	for i in ns:
		var f := float(i) / float(ns - 1) * float(m - 1)
		var a := int(f)
		var b := mini(a + 1, m - 1)
		out[a] = maxf(out[a], sample_widths[i])
		out[b] = maxf(out[b], sample_widths[i])
	wigglePathWidths = out

# Distance from `start` to the furthest opaque pixel along `dir`, stopping after a
# sustained transparent gap (the content edge).
func _content_reach(img: Image, start: Vector2, dir: Vector2, reach: float, threshold := 0.25) -> float:
	var last := 0.0
	var gap := 0.0
	var w := img.get_width()
	var h := img.get_height()
	var d := 1.0
	while d <= reach:
		var p := start + dir * d
		var x := int(round(p.x))
		var y := int(round(p.y))
		var alpha := 0.0
		if x >= 0 and y >= 0 and x < w and y < h:
			alpha = img.get_pixel(x, y).a
		if alpha > threshold:
			last = d
			gap = 0.0
		else:
			gap += 1.0
			if gap >= 8.0 and last > 0.0:
				break
		d += 1.0
	return last

func _update_wiggle(delta: float):
	if _wiggleAppendage == null:
		_set_wiggle_active(true)
		return
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	# Resolution change → rebuild chain AND mesh (the mesh vertex count tracks it).
	if _wiggleAppendage.segment_count != clampi(int(wiggleSegments), 2, 48):
		_apply_wiggle_geometry()
	_wiggleAppendage.configure(_wiggle_params())
	_wiggleAppendage.tick(delta, tick)
	# Linked children sit under this layer's Sprite2D, which wiggle hides — reparent
	# them onto DragOrigin (visible) so they stay on screen, then ride the bend.
	_attach_wiggle_children()
	_apply_wiggle_to_children()

func _wiggle_params() -> Dictionary:
	return {
		"stiffness": wiggleStiffness,
		"damping": wiggleDamping,
		# Cap per-joint rotation speed and soften joints toward the tip so a root
		# rotation travels down the appendage with lag (a smooth wave). Both scale
		# with stiffness, so Stiffness is the single "snappy vs smooth" knob.
		"max_angular_momentum": clampf(wiggleStiffness * 0.45, 2.0, 30.0),
		"stiffness_decay": wiggleStiffness * 0.05,
		"stiffness_decay_exponent": 1.3,
		"max_angle": deg_to_rad(wiggleMaxBend),
		"comeback_speed": wiggleBendFocus,
		"rest_return": wiggleShapeReturn,
		"gravity": Vector2(0.0, wiggleWeight),
		"subdivision": 4,
		# Base tracks the layer tightly so the wiggle reacts immediately — the whip
		# comes from the chain trailing the base, NOT from delaying the base. Higher
		# reactivity = snappier (toward instant); lower = a floatier, laggier base.
		"root_follow_smoothness": clampf(0.6 + wiggleReactivity * 0.3, 0.5, 1.0),
		"motion_intensity": wiggleMotionIntensity,
		"auto_wag": wiggleWagEnabled,
		"wag_speed": wiggleWagSpeed,
		"wag_amount": deg_to_rad(wiggleWagAmount),
	}

# Make directly-linked children ride the ribbon: project each child's rest spot
# onto the path to get its position along the appendage, then place it at the
# matching (bent) chain point. Deeper descendants follow via the scene tree.
func _apply_wiggle_to_children():
	if _wiggleAppendage == null or _wiggleSmooth.size() < 2:
		return
	for child in getAllLinkedSprites():
		if not child._wiggleFollowing:
			child._wiggleRestPos = child.position
			child._wiggleRestRot = child.rotation
			child._wiggleFollowing = true
		var tex: Vector2 = _local_to_tex(child._wiggleRestPos)
		var t := _project_on_smooth(tex)
		var p: Vector2 = _wiggleAppendage.sample_local(t) + _wiggleAppendage.position
		var p2: Vector2 = _wiggleAppendage.sample_local(minf(t + 0.04, 1.0)) + _wiggleAppendage.position
		child.position = p
		var cur_tan := p2 - p
		var rest_tan := _smooth_tangent(t)
		if cur_tan.length() > 0.001 and rest_tan.length() > 0.001:
			child.rotation = child._wiggleRestRot + (cur_tan.angle() - rest_tan.angle())

# Nearest arc-fraction [0,1] of a texture-space point onto the cached smooth path.
func _project_on_smooth(tex: Vector2) -> float:
	var n := _wiggleSmooth.size()
	if n < 2:
		return 0.0
	var lens := PackedFloat32Array()
	var total := 0.0
	for i in n - 1:
		var l := _wiggleSmooth[i].distance_to(_wiggleSmooth[i + 1])
		lens.append(l)
		total += l
	if total < 0.0001:
		return 0.0
	var best := 0.0
	var best_d := INF
	var acc := 0.0
	for i in n - 1:
		var a: Vector2 = _wiggleSmooth[i]
		var b: Vector2 = _wiggleSmooth[i + 1]
		var ab := b - a
		var seg := maxf(ab.length(), 0.0001)
		var u := clampf((tex - a).dot(ab) / (seg * seg), 0.0, 1.0)
		var proj := a + ab * u
		var d := tex.distance_squared_to(proj)
		if d < best_d:
			best_d = d
			best = (acc + u * seg) / total
		acc += lens[i]
	return best

# Local-space tangent of the smooth path at arc-fraction t (texture deltas equal
# local deltas — the mapping is a translation).
func _smooth_tangent(t: float) -> Vector2:
	var n := _wiggleSmooth.size()
	if n < 2:
		return Vector2.RIGHT
	var i := clampi(int(t * float(n - 1)), 0, n - 2)
	return _wiggleSmooth[i + 1] - _wiggleSmooth[i]

# Reparent linked children off the (wiggle-hidden) Sprite2D onto DragOrigin so they
# stay visible and ride the bend. Capture each child's authored rest offset BEFORE
# reparenting so _release can restore it exactly (no drift across on/off cycles).
# keep_global_transform on the move avoids a visual pop; the follow pass repositions
# them next. NOTE: a child that was clip-masked by this layer (setClip) loses that
# mask while the parent wiggles — clipping to a deforming mesh isn't supported; it
# re-clips when wiggle turns off and the child returns under the Sprite2D.
func _attach_wiggle_children():
	for child in getAllLinkedSprites():
		if child.get_parent() == sprite:
			child._wiggleRestPos = child.position
			child._wiggleRestRot = child.rotation
			child._wiggleFollowing = true
			child.reparent(dragOrigin, true)

# Return any children we were driving back under the Sprite2D at their captured rest.
func _release_wiggle_children():
	for child in getAllLinkedSprites():
		if child._wiggleFollowing:
			if child.get_parent() == dragOrigin:
				child.reparent(sprite, false)
			child.position = child._wiggleRestPos
			child.rotation = child._wiggleRestRot
			child._wiggleFollowing = false

func changeCollision(enable):
	grabArea.monitorable = enable

func changeFrames():
	sprite.hframes = frames
	sprite.frame = 0

func remakePolygon():
	if remadePolygon:
		return
	CollisionBuilder.replace_with_fallback(grabArea, outlineScene, imageSize, frames)
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
	var linkedSprites = []
	for node in Global.sprite_nodes():
		if node.parentId == id:
			linkedSprites.append(node)
	return linkedSprites

func getAllDescendants() -> Array:
	var children_by_parent := {}
	for node in Global.sprite_nodes():
		if node.parentId == null:
			continue
		if not children_by_parent.has(node.parentId):
			children_by_parent[node.parentId] = []
		children_by_parent[node.parentId].append(node)
	var result := []
	var stack: Array = children_by_parent.get(id, []).duplicate()
	while stack.size() > 0:
		var current = stack.pop_back()
		result.append(current)
		stack.append_array(children_by_parent.get(current.id, []))
	return result

func visToggle(keys):
	if Global.awaitingToggleBind: return
	if keys.has(toggle):
		$WobbleOrigin/DragOrigin.visible = !$WobbleOrigin/DragOrigin.visible

func makeVis():
	$WobbleOrigin/DragOrigin.visible = true

# Set this layer's visibility from its costume membership, honoring the manual
# eye-button hide. The single place costume + manual-hide combine, so every caller
# (selection refresh, costume change, the eye button) stays consistent.
func applyCostumeVisibility():
	if Global.main == null:
		return
	var on = costumeLayers[Global.main.costume - 1] == 1 and not userHidden
	visible = on
	changeCollision(on)
