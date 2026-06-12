extends Node

## NDI Output Manager
## Creates a SubViewport with shared world_2d, Camera2D, and NDIOutput node.
## Frames the user-drawn crop box (see ndi_crop_box.gd) with transparency and
## outputs an NDI stream. The output bottom is pinned above the box's bottom
## edge by the avatar's worst-case upward travel (bounce peak + reference
## layer wobble/eye-track), so below-box content never pops into frame.

var ndi_viewport: SubViewport = null
var ndi_camera: Camera2D = null
var ndi_output: Node = null
var crop_box: Node2D = null

var _dirty: bool = true
var _enabled: bool = false
var _plugin_available: bool = false
var crop_dragging: bool = false
var _debounce_timer: Timer = null
const DEBOUNCE_DELAY = 1.0

const CROP_BOX_SCRIPT = preload("res://ndi/ndi_crop_box.gd")

func _ready():
	_plugin_available = ClassDB.class_exists("NDIOutput")
	_load_settings()
	_debounce_timer = Timer.new()
	_debounce_timer.one_shot = true
	_debounce_timer.timeout.connect(_on_debounce_timeout)
	add_child(_debounce_timer)
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
	if !Saving.settings.has("ndiCropRect"):
		# Migrate from the old crop line: its Y becomes the box bottom
		var bottom = float(Saving.settings.get("ndiRulerY", 200.0))
		Saving.settings["ndiCropRect"] = [-500.0, bottom - 1000.0, 500.0, bottom]
	if !Saving.settings.has("ndiSourceName"):
		Saving.settings["ndiSourceName"] = "PixelLab Studio"

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

func set_source_name(name: String):
	var clean = name.strip_edges()
	if clean == "":
		clean = "PixelLab Studio"
	if Saving.settings.get("ndiSourceName", "") == clean:
		return
	Saving.settings["ndiSourceName"] = clean
	# NDI source name can only be set at output creation, so recycle the pipeline
	if _enabled:
		_destroy_ndi_pipeline()
		_create_ndi_pipeline()

# Crop box edges, origin-relative: [left, top, right, bottom]
func get_crop_edges() -> Array:
	var a = Saving.settings.get("ndiCropRect", [-500.0, -800.0, 500.0, 200.0])
	return [float(a[0]), float(a[1]), float(a[2]), float(a[3])]

func set_crop_edges(e: Array):
	Saving.settings["ndiCropRect"] = [float(e[0]), float(e[1]), float(e[2]), float(e[3])]
	mark_dirty()

func mark_dirty():
	_debounce_timer.start(DEBOUNCE_DELAY)

func _on_debounce_timeout():
	_dirty = true

# Cancel any pending debounce and run framing recomputation synchronously now.
# Used by the avatar load path so the work happens behind the progress bar
# instead of as a hitch ~1 second after the avatar appears.
func recalculate_now():
	_debounce_timer.stop()
	_dirty = false
	if _enabled and ndi_viewport != null:
		_recalculate_framing()

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
		ndi_output.set("name", Saving.settings.get("ndiSourceName", "PixelLab Studio"))
		ndi_viewport.add_child(ndi_output)

	print("[NDI] Pipeline created. Viewport size: ", ndi_viewport.size, " Plugin: ", _plugin_available)

	# Create crop box (visible only in edit mode)
	_create_crop_box()
	if crop_box != null:
		crop_box.visible = Global.main.editMode

	_dirty = true

func _destroy_ndi_pipeline():
	if ndi_viewport != null:
		ndi_viewport.queue_free()
		ndi_viewport = null
		ndi_camera = null
		ndi_output = null
	_destroy_crop_box()

func _create_crop_box():
	if crop_box != null:
		return
	crop_box = Node2D.new()
	crop_box.set_script(CROP_BOX_SCRIPT)
	crop_box.name = "NDICropBox"
	crop_box.visibility_layer = 2
	Global.main.add_child(crop_box)

func _destroy_crop_box():
	if crop_box != null:
		crop_box.queue_free()
		crop_box = null

func set_crop_visible(vis: bool):
	if crop_box != null:
		crop_box.visible = vis

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

	# Rest origin position (subtract current bounce offset)
	var bounce_offset = origin.get_parent().position.y
	var rest_origin_pos = origin.global_position - Vector2(0, bounce_offset)

	# Bounce peak displacement
	# Bounce re-triggers at 16px above rest, so actual peak is up to 16px higher
	var bounce_vel = float(main.bounceSlider)
	var gravity = float(main.bounceGravity)
	var peak_displacement = 0.0
	if gravity > 0:
		peak_displacement = (bounce_vel * bounce_vel) / (2.0 * gravity) + 16.0

	# Find reference sprite's vertical amplitude (or fallback to global max)
	var sprites = get_tree().get_nodes_in_group("saved")
	var ref_y_amp = 0.0
	var ref_eye = 0.0
	var ref_sprite = null
	for sprite_obj in sprites:
		if sprite_obj.visible and sprite_obj.ndiRefLayer:
			ref_sprite = sprite_obj
			ref_y_amp = abs(sprite_obj.yAmp)
			ref_eye = sprite_obj.eyeTrackDistance if sprite_obj.eyeTrack else 0.0
			break
	if ref_sprite == null:
		for sprite_obj in sprites:
			if sprite_obj.visible:
				ref_y_amp = max(ref_y_amp, abs(sprite_obj.yAmp))

	# The frame is the user-drawn crop box (origin-relative), placed in world space
	var e = get_crop_edges()
	var content_min = rest_origin_pos + Vector2(e[0], e[1])
	var content_max = rest_origin_pos + Vector2(e[2], e[3])

	# Pin the output bottom above the box's bottom edge by enough margin that
	# below-box content never becomes visible during wobble or bounce — the user
	# places the bottom edge flush with the bottom of the desired avatar part,
	# exactly like the old crop line.
	var bottom_margin = ref_y_amp + ref_eye + peak_displacement
	content_max.y -= bottom_margin

	# Content area
	var content_width = content_max.x - content_min.x
	var content_height = content_max.y - content_min.y
	if content_width <= 0: content_width = 100
	if content_height <= 0: content_height = 100

	# Viewport sizing
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

	# Camera center
	ndi_camera.position = Vector2(
		(content_min.x + content_max.x) * 0.5,
		(content_min.y + content_max.y) * 0.5
	)
