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
var _debounce_timer: Timer = null
const DEBOUNCE_DELAY = 1.0

# Framing state
var _content_top: float = 0.0
var _content_bottom: float = 200.0
var _content_left: float = 0.0
var _content_right: float = 0.0

const RULER_SCENE = preload("res://ndi/ndi_ruler.gd")

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
	_debounce_timer.start(DEBOUNCE_DELAY)

func _on_debounce_timeout():
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

func _get_opaque_rect_local(sprite_obj) -> Rect2:
	var img = sprite_obj.imageData
	if img == null:
		return Rect2()
	var used = img.get_used_rect()
	if used.size.x == 0 or used.size.y == 0:
		return Rect2()
	var tex_size = Vector2(img.get_size())
	var frame_w = tex_size.x
	if sprite_obj.frames > 1:
		frame_w = tex_size.x / sprite_obj.frames
		# Clamp used rect to single-frame width (conservative union across frames)
		used = used.intersection(Rect2i(0, 0, int(frame_w), int(tex_size.y)))
		if used.size.x == 0 or used.size.y == 0:
			return Rect2()
	# Convert to centered coords (Godot draws textures centered) + user offset
	return Rect2(
		Vector2(used.position) - Vector2(frame_w, tex_size.y) * 0.5 + sprite_obj.offset,
		Vector2(used.size)
	)

func _rotation_expanded_aabb(rect: Rect2, min_angle: float, max_angle: float) -> Rect2:
	var result = rect
	for angle in [min_angle, max_angle]:
		if is_zero_approx(angle):
			continue
		var cos_a = cos(angle)
		var sin_a = sin(angle)
		var corners = [rect.position, Vector2(rect.end.x, rect.position.y),
					   Vector2(rect.position.x, rect.end.y), rect.end]
		var rmin = Vector2(INF, INF)
		var rmax = Vector2(-INF, -INF)
		for c in corners:
			var rc = Vector2(c.x * cos_a - c.y * sin_a, c.x * sin_a + c.y * cos_a)
			rmin = Vector2(min(rmin.x, rc.x), min(rmin.y, rc.y))
			rmax = Vector2(max(rmax.x, rc.x), max(rmax.y, rc.y))
		result = result.merge(Rect2(rmin, rmax - rmin))
	return result

func _get_rest_position(sprite_obj, rest_origin_pos: Vector2) -> Vector2:
	if sprite_obj.parentSprite == null or sprite_obj.parentId == null:
		return rest_origin_pos + sprite_obj.position
	return _get_rest_position(sprite_obj.parentSprite, rest_origin_pos) + sprite_obj.position

func _compute_sprite_envelope(sprite_obj, crop_bottom: float, rest_origin_pos: Vector2) -> Rect2:
	var opaque = _get_opaque_rect_local(sprite_obj)
	if opaque.size == Vector2.ZERO:
		return Rect2()

	# Rotation expansion
	var expanded = opaque
	if sprite_obj.rdragStr > 0:
		expanded = _rotation_expanded_aabb(opaque,
			deg_to_rad(sprite_obj.rLimitMin), deg_to_rad(sprite_obj.rLimitMax))

	# Own wobble + eye tracking
	var eye_dist = sprite_obj.eyeTrackDistance if sprite_obj.eyeTrack else 0.0
	var ex = abs(sprite_obj.xAmp) + eye_dist
	var ey = abs(sprite_obj.yAmp) + eye_dist
	expanded = expanded.grow_individual(ex, ey, ex, ey)

	# Parent chain contributions
	var parent = sprite_obj.parentSprite
	var child_offset_from_parent = sprite_obj.position
	while parent != null:
		var p_eye = parent.eyeTrackDistance if parent.eyeTrack else 0.0
		var px = abs(parent.xAmp) + p_eye
		var py = abs(parent.yAmp) + p_eye
		expanded = expanded.grow_individual(px, py, px, py)
		# Parent rotation swings child in arc around parent center
		if parent.rdragStr > 0:
			var p_rot_max = max(abs(parent.rLimitMin), abs(parent.rLimitMax))
			if p_rot_max > 0:
				var dist = child_offset_from_parent.length()
				var angle = deg_to_rad(min(p_rot_max, 90.0))
				var arc_x = dist * sin(angle)
				var arc_y = dist * (1.0 - cos(angle))
				expanded = expanded.grow_individual(arc_x, arc_y, arc_x, arc_y)
		child_offset_from_parent += parent.position
		parent = parent.parentSprite

	# Place in global space
	var rest_pos = _get_rest_position(sprite_obj, rest_origin_pos)
	var global_env = Rect2(rest_pos + expanded.position, expanded.size)

	# Crop clamp
	if global_env.position.y >= crop_bottom:
		return Rect2()  # Entirely below crop
	if global_env.end.y > crop_bottom:
		global_env.size.y = crop_bottom - global_env.position.y
	return global_env

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

	# Crop bottom at rest position
	var ruler_y = Saving.settings["ndiRulerY"]
	var crop_bottom = rest_origin_pos.y + ruler_y

	# Compute per-sprite envelopes
	var sprites = get_tree().get_nodes_in_group("saved")
	var content_min = Vector2(INF, INF)
	var content_max = Vector2(-INF, -INF)
	var has_content = false

	for sprite_obj in sprites:
		if !sprite_obj.visible:
			continue
		if sprite_obj.sprite.self_modulate.a < 0.1:
			continue
		var env = _compute_sprite_envelope(sprite_obj, crop_bottom, rest_origin_pos)
		if env.size == Vector2.ZERO:
			continue
		has_content = true
		content_min.x = min(content_min.x, env.position.x)
		content_min.y = min(content_min.y, env.position.y)
		content_max.x = max(content_max.x, env.end.x)
		content_max.y = max(content_max.y, env.end.y)

	if !has_content:
		ndi_viewport.size = Vector2i(Saving.settings["ndiWidth"], Saving.settings["ndiWidth"])
		ndi_camera.position = rest_origin_pos
		ndi_camera.zoom = Vector2.ONE
		return

	# Find reference sprite's vertical amplitude (or fallback to global max)
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

	# Extend top by bounce peak so sprites don't clip out during bounce
	content_min.y -= peak_displacement

	# Pin viewport bottom above crop line by enough margin that below-crop
	# content never becomes visible during wobble or bounce
	var bottom_margin = ref_y_amp + ref_eye + peak_displacement
	content_max.y = crop_bottom - bottom_margin

	# Content area
	var content_width = content_max.x - content_min.x
	var content_height = content_max.y - content_min.y
	if content_width <= 0: content_width = 100
	if content_height <= 0: content_height = 100

	_content_top = content_min.y
	_content_bottom = content_max.y
	_content_left = content_min.x
	_content_right = content_max.x

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
