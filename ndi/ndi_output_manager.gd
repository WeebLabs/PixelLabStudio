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
const OutputGeometry = preload("res://ndi/ndi_output_geometry.gd")

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

func _exit_tree() -> void:
	var root := get_tree().root
	if root != null and root.size_changed.is_connected(_on_window_resized):
		root.size_changed.disconnect(_on_window_resized)
	if _debounce_timer != null:
		_debounce_timer.stop()
	_destroy_ndi_pipeline(true)

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

	_enabled = bool(Saving.settings["ndiEnabled"]) and _plugin_available
	if bool(Saving.settings["ndiEnabled"]) and not _plugin_available:
		Saving.settings["ndiEnabled"] = false

func is_plugin_available() -> bool:
	return _plugin_available

func is_enabled() -> bool:
	return _enabled

func set_enabled(enabled: bool):
	if !_plugin_available and enabled:
		_enabled = false
		Saving.settings["ndiEnabled"] = false
		return
	_enabled = enabled
	Saving.settings["ndiEnabled"] = enabled
	if enabled:
		_create_ndi_pipeline()
	else:
		_destroy_ndi_pipeline()

func set_width(width: int):
	Saving.settings["ndiWidth"] = clampi(width, OutputGeometry.MIN_OUTPUT_SIZE, OutputGeometry.MAX_OUTPUT_SIZE)
	mark_dirty()

func set_mode(mode: String):
	Saving.settings["ndiMode"] = mode if mode in ["auto", "manual"] else "auto"
	mark_dirty()

func set_manual_size(w: int, h: int):
	Saving.settings["ndiManualWidth"] = clampi(w, OutputGeometry.MIN_OUTPUT_SIZE, OutputGeometry.MAX_OUTPUT_SIZE)
	Saving.settings["ndiManualHeight"] = clampi(h, OutputGeometry.MIN_OUTPUT_SIZE, OutputGeometry.MAX_OUTPUT_SIZE)
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
	return OutputGeometry.normalize_edges(Saving.settings.get("ndiCropRect", OutputGeometry.DEFAULT_EDGES))

func set_crop_edges(e: Array):
	Saving.settings["ndiCropRect"] = OutputGeometry.normalize_edges(e)
	mark_dirty()

func mark_dirty():
	if _debounce_timer != null:
		_debounce_timer.start(DEBOUNCE_DELAY)
	else:
		_dirty = true

func _on_debounce_timeout():
	_dirty = true

# Cancel any pending debounce and run framing recomputation synchronously now.
# Used by the avatar load path so the work happens behind the progress bar
# instead of as a hitch ~1 second after the avatar appears.
func recalculate_now():
	if _debounce_timer != null:
		_debounce_timer.stop()
	_dirty = false
	if _enabled and ndi_viewport != null:
		_recalculate_framing()

func _create_ndi_pipeline():
	if ndi_viewport != null or not _plugin_available:
		return
	if Global.main == null or not is_instance_valid(Global.main) or Global.main.get_viewport() == null:
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
	ndi_output = ClassDB.instantiate("NDIOutput")
	if ndi_output == null:
		push_warning("NDIOutput was registered but could not be instantiated.")
		_destroy_ndi_pipeline()
		return
	ndi_output.set("name", Saving.settings.get("ndiSourceName", "PixelLab Studio"))
	ndi_viewport.add_child(ndi_output)

	print("[NDI] Pipeline created. Viewport size: ", ndi_viewport.size, " Plugin: ", _plugin_available)

	# Create crop box (visible only in edit mode)
	_create_crop_box()
	if crop_box != null:
		crop_box.visible = Global.main.editMode

	_dirty = true

func _destroy_ndi_pipeline(immediate: bool = false):
	if ndi_output != null and is_instance_valid(ndi_output):
		if immediate:
			ndi_output.free()
		else:
			ndi_output.queue_free()
	ndi_output = null
	ndi_camera = null
	if ndi_viewport != null and is_instance_valid(ndi_viewport):
		if immediate:
			ndi_viewport.free()
		else:
			ndi_viewport.queue_free()
	ndi_viewport = null
	_destroy_crop_box(immediate)

func _create_crop_box():
	if crop_box != null:
		return
	crop_box = Node2D.new()
	crop_box.set_script(CROP_BOX_SCRIPT)
	crop_box.name = "NDICropBox"
	crop_box.visibility_layer = 2
	Global.main.add_child(crop_box)

func _destroy_crop_box(immediate: bool = false):
	if crop_box != null:
		if is_instance_valid(crop_box):
			if immediate:
				crop_box.free()
			else:
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

	var origin = Global.main.origin

	# Rest origin position (subtract current bounce offset) so the frame is fixed at the
	# avatar's resting pose; the avatar then visibly bounces WITHIN the frame.
	var bounce_offset = origin.get_parent().position.y
	var rest_origin_pos = origin.global_position - Vector2(0, bounce_offset)

	# The frame is exactly the user-drawn crop box (origin-relative), placed in world
	# space: one-to-one with the rectangle OBS receives, on all four edges. No bounce
	# headroom is subtracted from the bottom now. The crop ships pre-configured per
	# avatar, so it's WYSIWYG: whoever sets it up bakes any desired margin into the box
	# itself, just like the top and sides.
	var geometry := OutputGeometry.calculate(
		get_crop_edges(),
		str(Saving.settings.get("ndiMode", "auto")),
		int(Saving.settings.get("ndiWidth", 512)),
		int(Saving.settings.get("ndiManualWidth", 800)),
		int(Saving.settings.get("ndiManualHeight", 1200))
	)
	var e: Array = geometry["edges"]
	var content_min = rest_origin_pos + Vector2(e[0], e[1])
	var content_max = rest_origin_pos + Vector2(e[2], e[3])

	ndi_viewport.size = geometry["viewport_size"]
	var zoom: float = geometry["zoom"]
	ndi_camera.zoom = Vector2(zoom, zoom)

	# Camera center
	ndi_camera.position = Vector2(
		(content_min.x + content_max.x) * 0.5,
		(content_min.y + content_max.y) * 0.5
	)
