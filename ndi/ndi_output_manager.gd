extends Node

## NDI Output Manager
## Creates a SubViewport with shared world_2d, Camera2D, and NDIOutput node.
## Auto-frames the avatar with transparency and outputs an NDI stream.

var ndi_viewport: SubViewport = null
var ndi_camera: Camera2D = null
var ndi_output: Node = null
var ruler: Node2D = null

var _dirty: bool = true
var _enabled: bool = false
var _plugin_available: bool = false
var ruler_dragging: bool = false

# Framing state
var _content_top: float = 0.0
var _content_bottom: float = 200.0
var _content_left: float = 0.0
var _content_right: float = 0.0

const RULER_SCENE = preload("res://ndi/ndi_ruler.gd")

func _ready():
	_plugin_available = ClassDB.class_exists("NDIOutput")
	_load_settings()
	if _enabled:
		_create_ndi_pipeline()
	get_tree().root.size_changed.connect(_on_window_resized)

func _on_window_resized():
	if _enabled:
		mark_dirty()

func _load_settings():
	if !Saving.settings.has("ndiEnabled"):
		Saving.settings["ndiEnabled"] = false
	if !Saving.settings.has("ndiWidth"):
		Saving.settings["ndiWidth"] = 512
	if !Saving.settings.has("ndiMode"):
		Saving.settings["ndiMode"] = "auto"
	if !Saving.settings.has("ndiManualWidth"):
		Saving.settings["ndiManualWidth"] = 800
	if !Saving.settings.has("ndiManualHeight"):
		Saving.settings["ndiManualHeight"] = 1200
	if !Saving.settings.has("ndiRulerY"):
		Saving.settings["ndiRulerY"] = 200.0

	_enabled = Saving.settings["ndiEnabled"]

func is_plugin_available() -> bool:
	return _plugin_available

func is_enabled() -> bool:
	return _enabled

func set_enabled(enabled: bool):
	if !_plugin_available and enabled:
		return
	_enabled = enabled
	Saving.settings["ndiEnabled"] = enabled
	if enabled:
		_create_ndi_pipeline()
	else:
		_destroy_ndi_pipeline()

func set_width(width: int):
	Saving.settings["ndiWidth"] = width
	mark_dirty()

func set_mode(mode: String):
	Saving.settings["ndiMode"] = mode
	mark_dirty()

func set_manual_size(w: int, h: int):
	Saving.settings["ndiManualWidth"] = w
	Saving.settings["ndiManualHeight"] = h
	mark_dirty()

func set_ruler_y(y: float):
	Saving.settings["ndiRulerY"] = y
	mark_dirty()

func get_ruler_y() -> float:
	return Saving.settings["ndiRulerY"]

func mark_dirty():
	_dirty = true

func _create_ndi_pipeline():
	if ndi_viewport != null:
		return

	# Create SubViewport
	ndi_viewport = SubViewport.new()
	ndi_viewport.name = "NDISubViewport"
	ndi_viewport.transparent_bg = true
	ndi_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ndi_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	ndi_viewport.size = Vector2i(512, 512)
	# Share the main viewport's world so we see the same sprites
	ndi_viewport.world_2d = Global.main.get_viewport().world_2d
	# Only render visibility layer 1 (sprites). HUD elements use layer 2.
	ndi_viewport.canvas_cull_mask = 1
	# Disable input on this viewport
	ndi_viewport.gui_disable_input = true
	ndi_viewport.handle_input_locally = false

	add_child(ndi_viewport)

	# Create Camera2D for NDI framing
	ndi_camera = Camera2D.new()
	ndi_camera.name = "NDICamera"
	ndi_viewport.add_child(ndi_camera)
	ndi_camera.make_current()

	# Create NDIOutput node (plugin)
	if _plugin_available:
		ndi_output = ClassDB.instantiate("NDIOutput")
		ndi_output.set("name", "PixelLab Studio")
		ndi_viewport.add_child(ndi_output)

	print("[NDI] Pipeline created. Viewport size: ", ndi_viewport.size, " Plugin: ", _plugin_available)

	# Create ruler (visible only in edit mode)
	_create_ruler()
	if ruler != null:
		ruler.visible = Global.main.editMode

	_dirty = true

func _destroy_ndi_pipeline():
	if ndi_viewport != null:
		ndi_viewport.queue_free()
		ndi_viewport = null
		ndi_camera = null
		ndi_output = null
	_destroy_ruler()

func _create_ruler():
	if ruler != null:
		return
	ruler = Node2D.new()
	ruler.set_script(RULER_SCENE)
	ruler.name = "NDIRuler"
	ruler.visibility_layer = 2
	Global.main.add_child(ruler)

func _destroy_ruler():
	if ruler != null:
		ruler.queue_free()
		ruler = null

func set_ruler_visible(vis: bool):
	if ruler != null:
		ruler.visible = vis

func _process(_delta):
	if !_enabled or ndi_viewport == null:
		return
	if _dirty:
		_dirty = false
		_recalculate_framing()

func _recalculate_framing():
	if ndi_viewport == null or ndi_camera == null:
		return

	var main = Global.main
	var origin = main.origin

	# Compute bounding box of all visible sprites
	var sprites = get_tree().get_nodes_in_group("saved")
	if sprites.size() == 0:
		# No sprites - use a small default viewport
		ndi_viewport.size = Vector2i(Saving.settings["ndiWidth"], Saving.settings["ndiWidth"])
		ndi_camera.position = origin.global_position
		ndi_camera.zoom = Vector2.ONE
		return

	var bbox_min = Vector2(INF, INF)
	var bbox_max = Vector2(-INF, -INF)
	var has_visible = false

	for sprite_obj in sprites:
		if !sprite_obj.visible:
			continue
		if sprite_obj.sprite.self_modulate.a < 0.1:
			continue

		has_visible = true
		var spr: Sprite2D = sprite_obj.sprite
		var tex = spr.texture
		if tex == null:
			continue

		var tex_size = tex.get_size()
		# Account for spritesheet frames
		if spr.hframes > 1:
			tex_size.x /= spr.hframes

		var half = tex_size * 0.5
		var spr_offset = spr.offset
		# Get REST position (subtract wobble offset so framing is stable)
		var center = (spr.global_position - sprite_obj.wob.position) + spr_offset

		bbox_min.x = min(bbox_min.x, center.x - half.x)
		bbox_min.y = min(bbox_min.y, center.y - half.y)
		bbox_max.x = max(bbox_max.x, center.x + half.x)
		bbox_max.y = max(bbox_max.y, center.y + half.y)

	if !has_visible:
		ndi_viewport.size = Vector2i(Saving.settings["ndiWidth"], Saving.settings["ndiWidth"])
		ndi_camera.position = origin.global_position
		ndi_camera.zoom = Vector2.ONE
		return

	# Calculate peak bounce displacement
	var bounce_vel = float(main.bounceSlider)
	var gravity = float(main.bounceGravity)
	var peak_displacement = 0.0
	if gravity > 0:
		peak_displacement = (bounce_vel * bounce_vel) / (2.0 * gravity)

	# Max wobble amplitude across sprites
	var max_y_amp = 0.0
	for sprite_obj in sprites:
		if sprite_obj.visible:
			max_y_amp = max(max_y_amp, abs(sprite_obj.yAmp))

	# Headroom: small safety margin for bounce; wobble range is handled by upward_shift
	var headroom = peak_displacement * 1.15

	# Content bounds (relative to origin)
	var ruler_y = Saving.settings["ndiRulerY"]

	# The ruler_y is an offset below origin (positive = below)
	var crop_bottom = origin.global_position.y + ruler_y

	# Top of frame = highest sprite edge - headroom (wobble can push sprites up by yAmp)
	var content_top = bbox_min.y - headroom
	var content_bottom = crop_bottom

	# Horizontal bounds with some padding
	var padding_x = 10.0
	var content_left = bbox_min.x - padding_x
	var content_right = bbox_max.x + padding_x

	var content_width = content_right - content_left
	var content_height = content_bottom - content_top

	if content_width <= 0:
		content_width = 100
	if content_height <= 0:
		content_height = 100

	# Store for reference
	_content_top = content_top
	_content_bottom = content_bottom
	_content_left = content_left
	_content_right = content_right

	var mode = Saving.settings["ndiMode"]
	if mode == "manual":
		var vp_w = int(Saving.settings["ndiManualWidth"])
		var vp_h = int(Saving.settings["ndiManualHeight"])
		ndi_viewport.size = Vector2i(vp_w, vp_h)

		# Compute zoom to fit content into manual viewport
		var zoom_x = float(vp_w) / content_width
		var zoom_y = float(vp_h) / content_height
		var z = min(zoom_x, zoom_y)
		ndi_camera.zoom = Vector2(z, z)
	else:
		# Auto mode: user picks width, height computed from aspect ratio
		var target_width = int(Saving.settings["ndiWidth"])
		var aspect = content_height / content_width
		var target_height = int(target_width * aspect)
		target_height = max(target_height, 1)
		ndi_viewport.size = Vector2i(target_width, target_height)

		# Camera zoom: fit content into viewport
		var z = float(target_width) / content_width
		ndi_camera.zoom = Vector2(z, z)

	# Camera center: horizontally centered on content, vertically centered between top and bottom
	var center_x = (content_left + content_right) * 0.5
	var center_y = (content_top + content_bottom) * 0.5

	# Shift camera upward so the artwork cutoff is never visible.
	# The ruler is placed at worst-case-down (wob = +yAmp). The full upward
	# range from there is 2*yAmp (peak-to-peak wobble) + bounce peak.
	var upward_shift = 2.0 * max_y_amp + peak_displacement
	center_y -= upward_shift

	ndi_camera.position = Vector2(center_x, center_y)
