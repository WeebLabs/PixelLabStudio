extends Node2D

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const CollisionBuilder = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")
const SpriteCollisionRuntime = preload("res://ui_scenes/selectedSprite/sprite_collision_runtime.gd")
const SpriteHierarchy = preload("res://ui_scenes/selectedSprite/sprite_hierarchy.gd")
const SpriteVisibility = preload("res://ui_scenes/selectedSprite/sprite_visibility_policy.gd")
const SpriteVisualRuntime = preload("res://ui_scenes/selectedSprite/sprite_visual_runtime.gd")
const SpriteRestPose = preload("res://ui_scenes/selectedSprite/sprite_rest_pose.gd")
const LegacyCompat = preload("res://autoload/domain/legacy_canvas_compat.gd")
const WiggleGeometry = preload("res://effects/wiggle/wiggle_geometry.gd")
const WiggleRuntime = preload("res://effects/wiggle/wiggle_runtime.gd")
const MotionTiming = preload("res://autoload/domain/motion_timing.gd")
const SpriteEyeTracking = preload("res://ui_scenes/selectedSprite/sprite_eye_tracking.gd")

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
var _origin_drag_captured = false
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
var _visualRuntime = SpriteVisualRuntime.new()
var _collisionRuntime = SpriteCollisionRuntime.new()

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

var _wiggleRuntime = WiggleRuntime.new()
# Set on this layer while a wiggle parent drives it (child-follow); stores rest transform.
var _wiggleRestPos = Vector2.ZERO
var _wiggleRestRot = 0.0
var _wiggleFollowing = false
var _changing_parent := false
var _wiggleBind = {}

#Blink Animation
var _blinkAnimPlaying = false
var _prevBlink = false
var _blinkQueue = 0

#Animation
var frames = 1
var animSpeed = 0
# Seconds since this layer's sprite sheet last stepped, for the two animation
# paths below.
var _frameClock := 0.0

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
# Elapsed time in 60 fps frames: `tick` for oscillators, but honest about time.
var motionTime := 0.0

#Vis toggle
var toggle = "null"
# User-given name for this layer. Empty means the name is read off the image
# path, which is where every layer's name came from before renaming existed.
var layerName = ""
var _skip_ready_reparent = false
var _prebuilt_pma_image: Image = null
var _prebuilt_polygons: Array = []

func _make_premultiplied_texture(img: Image) -> ImageTexture:
	return SpriteVisualRuntime.premultiplied_texture(img)

func _rebuild_sprite_texture():
	_visualRuntime.rebuild_texture()

func setNormalMap(img: Image, nrml_path: String):
	if not _visualRuntime.set_normal_map(img, nrml_path):
		Global.notify_user("Normal map size mismatch. Must match diffuse dimensions.")

func clearNormalMap():
	_visualRuntime.clear_normal_map()

func hasNormalMap() -> bool:
	return _visualRuntime.has_normal_map()

func _ready():
	_wiggleRuntime.setup(self)
	_visualRuntime.setup(self)
	_collisionRuntime.setup(self)
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

	var has_collision := _build_collision(polygons)

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

	# Avatar load handles reparenting synchronously and sets _skip_ready_reparent,
	# so we don't need to suspend on a timer that does nothing afterwards
	if not _skip_ready_reparent:
		await get_tree().create_timer(0.1).timeout
		if parentId != null:
			var nodes = get_tree().get_nodes_in_group(str(parentId))
			if nodes.size() > 0:
				reparent(nodes[0].sprite, false)
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

func _enter_tree() -> void:
	# Reparenting emits _exit_tree/_enter_tree without running _ready again.
	# Register here so hierarchy changes cannot permanently evict live sprites.
	if _changing_parent:
		return
	Global.register_sprite(self)

func _exit_tree() -> void:
	if _changing_parent:
		return
	Global.unregister_sprite(self)


# Move this layer to a new parent. A plain reparent() runs _exit_tree and
# _enter_tree, and a layer only changing parent must not be treated as leaving:
# unregistering dropped it from the selection partway through an unlink (the
# held layer went null mid-function and the unlink aborted with the layer half
# moved), and re-registering put it at the end of the registry, which is the
# layer list's tie-break at equal z.
func moveUnder(new_parent: Node, keep_global: bool) -> void:
	_changing_parent = true
	reparent(new_parent, keep_global)
	_changing_parent = false


# Stop riding a wiggle parent's chain and put back the pose it was riding from.
# A layer leaving that parent otherwise kept a stale binding, and its stale
# _wiggleRestPos was what saves and undo snapshots recorded.
func leaveWiggleParent() -> void:
	if not _wiggleFollowing:
		return
	position = _wiggleRestPos
	rotation = _wiggleRestRot
	_wiggleFollowing = false
	_wiggleBind = {}
	
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
	imageSize = img.get_size()
	size = imageSize
	invalidate_used_rect_cache()
	tex = _make_premultiplied_texture(img)

	# Clear normal if new diffuse has different dimensions
	if hasNormalMap() and normalImageData.get_size() != img.get_size():
		clearNormalMap()
		Global.notify_user("Normal map cleared (size mismatch after replace).")
	else:
		_rebuild_sprite_texture()
	
	var polygons := CollisionBuilder.alpha_polygons(imageData)
	var has_collision := _collisionRuntime.replace(polygons, _collision_should_be_active())
	sprite.offset = offset
	
	grabArea.position = (size*-0.5) + offset
	
	remadePolygon = false
	if not has_collision:
		remakePolygon()

# `canvasShift` is set only for a legacy full-canvas layer being replaced by a
# cropped PSD layer: it is that layer's centre relative to the source canvas
# centre, and applying it to `offset` keeps the artwork where it already sat.
# See LegacyCanvasCompat for the derivation.
func replaceSpriteFromData(img: Image, layer_name: String, canvasShift = null):
	var previousSize = size
	path = "psd://" + layer_name
	imageData = img
	imageSize = img.get_size()
	size = imageSize
	if canvasShift != null:
		_applyCanvasShift(previousSize, canvasShift)
	invalidate_used_rect_cache()
	tex = _make_premultiplied_texture(img)

	# Clear normal if new diffuse has different dimensions
	if hasNormalMap() and normalImageData.get_size() != img.get_size():
		clearNormalMap()
		Global.notify_user("Normal map cleared (size mismatch after replace).")
	else:
		_rebuild_sprite_texture()

	var polygons := CollisionBuilder.alpha_polygons(imageData)
	var has_collision := _collisionRuntime.replace(polygons, _collision_should_be_active())

	sprite.offset = offset
	grabArea.position = (size * -0.5) + offset

	remadePolygon = false
	if not has_collision:
		remakePolygon()

func _applyCanvasShift(previousSize, shift: Vector2):
	offset = LegacyCompat.offset_after_replace(offset, shift)
	# The wiggle rest path is texture-space data, so it moves with the crop.
	_wiggleRuntime.remap_path(-LegacyCompat.texture_origin_shift(Vector2(previousSize), Vector2(size), shift))


func _process(delta):
	# While the window is being resized, freeze the avatar entirely: don't
	# advance wobble/animation/drag, since the viewport size and origin position
	# are mid-flight and feeding partial deltas into physics produces visible
	# glitches and stretches. main.gd flips Global.main.resize_active to true
	# when size changes and back to false (with a one-shot drag-snap) when it
	# stabilizes.
	if Global.main != null and Global.main.resize_active:
		return
	# Edit-mode motion pause: hold this layer at its authored rest pose (see
	# sprite_rest_pose.gd) instead of advancing anything. Re-applied every frame, so
	# a layer moved while paused still shows its true rest position. `tick` does not
	# advance either: it drives frame animation and the wiggle wag.
	if Global.motion_paused():
		_update_selection_gizmos()
		SpriteRestPose.apply(self)
		_update_path_editor()
		talkBlink()
		return

	tick += 1
	motionTime += MotionTiming.frames(delta)
	_anim_update(delta)
	_update_selection_gizmos()
	
	if staticElement:
		# Follow drag, wobble, rotation, and stretch as normal — but cancel the
		# avatar-wide bounce by lerping the dragger toward the un-bounced wob
		# position instead of the bounced one.
		wobble(delta)
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
		wobble(delta)

		var length = 0.0 if did_snap else (glob.y - dragger.global_position.y)

		rotationalDrag(length,delta)
		stretch(length,delta)

	# Eye-track Rotation composes with the mic rotational sway. rotationalDrag
	# smooths into its own _micRot (not sprite.rotation), so the look-at adds
	# cleanly here rather than feeding back into it (a runaway spin).
	sprite.rotation = _micRot + _eyeTrackRotation

	# Animation rotation rides on DragOrigin (outermost on the layer), so it swings
	# the visible Sprite2D AND, for wiggle layers, the mesh + chain anchor — the
	# twitch drives the verlet chain into secondary motion. Suppressed while tracing
	# a wiggle path (the editor works over the static, un-rotated sprite).
	dragOrigin.rotation = 0.0 if _wiggleRuntime.is_editing_path() else _animRot

	if grabDelay > 0:
		grabDelay -= 1

	_update_path_editor()
	# While the path is being traced the static Sprite2D stands in for tracing and
	# the ribbon is hidden, so there's nothing to advance.
	if wiggleEnabled and not _wiggleRuntime.is_editing_path():
		_update_wiggle(delta)

	talkBlink()

	if Global.originMode and Global.heldSprite == self:
		var mouse_pos = get_global_mouse_position()
		if mouse_pos.distance_to(sprite.global_position) <= 24.0:
			Global.mouse.text = "Drag origin"

	if !blinkAnimation(delta):
		animation(delta)

# Selection chrome: the grab outline and origin handle, shown only while this is
# the held sprite on the edit page, the outline kept a constant on-screen
# thickness as we zoom. The selection outlives a switch to the player page, so the
# page has to be part of the test, not left to whoever clears the selection.
func _update_selection_gizmos():
	if Global.heldSprite == self and Global.main != null and Global.main.editMode:
		grabArea.visible = true
		originSprite.visible = true

		var cam_zoom = Global.main.camera.zoom.x
		for child in grabArea.get_children():
			if child is Line2D:
				child.width = 3.0 / cam_zoom
	else:
		grabArea.visible = false
		originSprite.visible = false


# A sprite sheet steps on elapsed time. It used to count frames against a
# divisor derived from Engine.max_fps, which held the right rate while that
# setting matched reality but collapsed to a step EVERY frame at the Unlimited
# setting, where max_fps is 0: a sheet then ran at whatever rate the machine hit.
func animation(delta):
	if frames <= 1:
		return
	if animSpeed > 0 and _advance_frame_clock(delta):
		sprite.frame = 0 if sprite.frame == frames - 1 else sprite.frame + 1
	remakePolygon()


# True once per step of the sheet. The interval is the one the app has always
# used at 60 fps: animSpeed frames every six seconds.
func _advance_frame_clock(delta: float) -> bool:
	var interval := 6.0 / float(animSpeed)
	_frameClock += minf(delta, interval)
	if _frameClock < interval:
		return false
	_frameClock -= interval
	return true

func setZIndex():
	sprite.z_index = z
	# Keep the wiggle ribbon at the same depth as the sprite it stands in for, so
	# reordering a wiggling layer re-depths the ribbon too (not just the sprite).
	_wiggleRuntime.set_z_index(z)
	_visualRuntime.set_z_index(z)

# Apply the current blend mode to the Sprite2D's material + the optional backbuffer.
# Native tier (Normal/Add/Subtract) uses a CanvasItemMaterial and needs no screen read;
# every other mode uses the shared blend shader fed by a BackBufferCopy. Safe to re-call.
func applyBlendMode():
	_visualRuntime.apply_blend_mode()

# Talk/blink visibility for this layer, delegated so the scene facade stays a
# facade. Paused motion holds it at rest too: otherwise the mic and the blink
# timer keep swapping which layers show and which dim to 20%, several times a
# second, which is movement, and which also reshuffles what a click can pick.
func talkBlink():
	var paused := Global.motion_paused()
	_visualRuntime.sync_talk_blink(
		Global.speaking and not paused, Global.blink and not paused, Global.main.editMode
	)


func blinkAnimation(delta):
	if showOnBlink != 3 or frames <= 1:
		return false

	if Global.blink and !_prevBlink:
		if _blinkAnimPlaying:
			_blinkQueue += 1
		else:
			_blinkAnimPlaying = true
			_frameClock = 0.0
			sprite.frame = 0
	_prevBlink = Global.blink

	if !_blinkAnimPlaying:
		sprite.frame = 0
		return true

	if animSpeed > 0 and _advance_frame_clock(delta):
		if sprite.frame >= frames - 1:
			if _blinkQueue > 0:
				_blinkQueue -= 1
				sprite.frame = 0
			else:
				_blinkAnimPlaying = false
				sprite.frame = 0
		else:
			sprite.frame += 1

	return true

# What this layer is called in the UI: its own name if it has been renamed, and
# otherwise the image file's name.
func displayName() -> String:
	if layerName != "":
		return layerName
	return SpriteHierarchy.display_name(path)


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
				_origin_dragging = true
				_origin_drag_captured = false
				_origin_drag_start_mouse_local = get_parent().to_local(mouse_pos)
				_origin_drag_start_offset = offset
				_origin_drag_start_pos = authoredPosition()
				get_viewport().set_input_as_handled()
		else:
			_origin_dragging = false

	elif event is InputEventMouseMotion and _origin_dragging:
		var mouse_local = get_parent().to_local(get_global_mouse_position())
		var delta = mouse_local - _origin_drag_start_mouse_local
		if not _origin_drag_captured:
			_origin_drag_captured = true
			MutationCommands.drag("origin-gizmo", func(): return true)
		# Snap the drag delta to a whole pixel ONCE and apply it equally/oppositely, so position
		# and offset stay exactly coupled. Truncating each independently (int() rounds toward
		# zero) drifted them apart by a pixel when both had the same sign — moving the artwork.
		var idelta = Vector2(roundi(delta.x), roundi(delta.y))
		setAuthoredPosition(_origin_drag_start_pos + idelta)
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
			MutationCommands.drag("move-layer", func(): return true)
		heldTicks += 1
	else:
		heldTicks = 0
		MutationCommands.end_gesture("move-layer")

	var moved = authoredPosition()
	if heldTicks > 30 or heldTicks == 1:
		var multiplier = 2
		if heldTicks == 1:
			multiplier = 1
		moved -= dir * multiplier

	setAuthoredPosition(Vector2(int(moved.x),int(moved.y)))

# A layer riding a wiggle parent has its live position rewritten every frame, so
# moves, saves, and undo act on its authored rest position instead.
func authoredPosition() -> Vector2:
	return _wiggleRestPos if _wiggleFollowing else position

func authoredRotation() -> float:
	return _wiggleRestRot if _wiggleFollowing else rotation

func setAuthoredPosition(value: Vector2) -> void:
	if not _wiggleFollowing:
		position = value
	elif _wiggleRestPos != value:
		_wiggleRestPos = value
		_wiggleBind = {}

func moveOrigin(dir):
	if dir != Vector2.ZERO:
		if origTick == 0:
			MutationCommands.drag("move-origin", func(): return true)
		origTick += 1
	else:
		origTick = 0
		MutationCommands.end_gesture("move-origin")

	if origTick > 30 or origTick == 1:
		var multiplier = 2
		if origTick == 1:
			multiplier = 1

		offset += dir * multiplier
		setAuthoredPosition(authoredPosition() - dir * multiplier)

	offset = Vector2(int(offset.x),int(offset.y))

	sprite.offset = offset
	grabArea.position = (size*-0.5) + offset
	_sync_wiggle_to_offset()

func snapOriginToMouse():
	var mouse_pos = get_global_mouse_position()
	var new_pos = get_parent().to_local(mouse_pos)
	new_pos = Vector2(int(new_pos.x), int(new_pos.y))
	var delta = new_pos - position
	setAuthoredPosition(authoredPosition() + delta)
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
		dragger.global_position = lerp(
			dragger.global_position, wob.global_position, MotionTiming.smooth(1.0 / dragSpeed, delta))
		dragOrigin.global_position = dragger.global_position

func wobble(delta):
	# Skip wobble while the NDI crop box is being dragged (frozen at worst-case-down)
	if Global.main.ndi_manager != null and Global.main.ndi_manager.crop_dragging:
		return
	# Base layer translation comes from animation clips (the legacy wobble migrates
	# into an oscillate/translation clip that reproduces sin(tick*freq)*amp exactly).
	# Eye-track then adds its offset on top, below.
	wob.position = _animTrans

	# Eye tracking then adds its own offset or tilt on top.
	SpriteEyeTracking.apply(self, delta)


# `length` is how far the layer moved since the last frame, so on its own a
# longer frame reads as a bigger movement and renders as a bigger angle: frame
# noise straight onto the artwork, which is what made dragged layers jitter. Per
# 60 fps frame it is a speed, and means the same at any frame rate.
func rotationalDrag(length, delta):
	var yvel = MotionTiming.per_frame(length, delta) * rdragStr

	#Calculate Max angle

	yvel = clamp(yvel,rLimitMin,rLimitMax)

	_micRot = lerp_angle(_micRot, deg_to_rad(yvel), MotionTiming.smooth(0.25, delta))
	sprite.rotation = _micRot

func stretch(length, delta):
	var yvel = MotionTiming.per_frame(length, delta) * stretchAmount * 0.01
	var target = Vector2(1.0-yvel,1.0+yvel)

	sprite.scale = lerp(sprite.scale, target, MotionTiming.smooth(0.5, delta))

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
	_animator.evaluate(animClips, motionTime, delta)
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
# oscillate/translation clip, on load for avatars saved before animClips existed.
# The legacy fields are left intact (older app builds still read them).
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

# Turn wiggle on/off. When on, the Sprite2D is hidden and a deformable textured
# mesh (WiggleAppendage2D) bends along the spring chain in its place. The Physics
# tab calls this; safe to call any time.
func setWiggle(on: bool):
	wiggleEnabled = on
	_set_wiggle_active(on)   # _set_wiggle_active(false) releases linked children

func _set_wiggle_active(on: bool):
	_wiggleRuntime.set_active(on)

# --- Ribbon path editor (Phase 2) ---

# Create/destroy the on-canvas path editor as Global.wigglePathMode toggles for
# this layer. Polled each frame (state-driven, like the rest of the app).
func _update_path_editor():
	var want: bool = Global.wigglePathMode and Global.heldSprite == self
	_wiggleRuntime.update_path_editor(want)

# Rebuild geometry after an external path/width/coverage change (editor commit,
# auto-fit, coverage slider). No-op when the mesh isn't built yet — the path is
# simply stored until wiggle is enabled.
func apply_wiggle_path_changed():
	_wiggleRuntime.apply_path_changed()

# The "Auto-fit" button: re-detect the spine (centerline trace) AND the band
# (silhouette fit) from the content — a full auto from scratch. Undoable (the
# Physics tab saves undo state first), so it's safe to use as a reset.
func wiggle_auto_fit_path():
	_wiggleRuntime.auto_fit_and_refresh()

# Texture-pixel -> appendage/dragOrigin local: the Sprite2D is centered and
# shifted by `offset`, so texture px maps to local (px - size/2 + offset).
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
	_wiggleRuntime.sync_to_offset()

# Per-smooth-point half-widths (px): the per-control-point widths interpolated
# along the smooth path and scaled by the thickness knob, which is how far the
# mesh band reaches perpendicular to the path. Changing thickness rebuilds it.
func _smooth_widths(smooth: PackedVector2Array) -> PackedFloat32Array:
	return WiggleGeometry.smooth_widths(smooth.size(), wigglePathWidths, wiggleThickness)

func _update_wiggle(delta: float):
	_wiggleRuntime.update(delta)

func changeCollision(enable):
	_collisionRuntime.set_monitorable(enable)


# The grab shapes exist for click-to-select, which mouse_cursor gates on edit
# mode, so outside it they are dead weight: the layer moves every frame and the
# physics server keeps re-fitting a decomposed polygon in the broadphase for a
# query that never comes. Measured on 25 layers: 23.8 ms/tick with the shapes
# live against 2.2 ms with them disabled.
func setCollisionActive(active: bool) -> void:
	_collisionRuntime.set_active(active)


# Every collision rebuild goes through here, so shapes built while the player
# page is up (loading an avatar, for one) start in the right state.
func _build_collision(polygons: Array) -> bool:
	return _collisionRuntime.build(polygons, _collision_should_be_active())

func _collision_should_be_active() -> bool:
	return Global.main == null or Global.main.editMode

func changeFrames():
	sprite.hframes = frames
	sprite.frame = 0

func remakePolygon():
	_collisionRuntime.remake_sheet(_collision_should_be_active())
	
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
	return SpriteHierarchy.direct_children(Global.sprite_nodes(), id)

func getAllDescendants() -> Array:
	return SpriteHierarchy.descendants(Global.sprite_nodes(), id)

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
	var on := SpriteVisibility.costume_visible(costumeLayers, Global.main.costume, userHidden)
	visible = on
	changeCollision(on)
