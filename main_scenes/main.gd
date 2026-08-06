extends Node2D

const AvatarSave = preload("res://autoload/persistence/avatar_save_schema.gd")
const ValueCodec = preload("res://autoload/persistence/value_codec.gd")
const SpriteState = preload("res://autoload/domain/sprite_state.gd")
const CaptureControllerScene = preload("res://main_scenes/controllers/capture_controller.gd")
const ViewportControllerScene = preload("res://main_scenes/controllers/viewport_controller.gd")
const SaveControllerScene = preload("res://main_scenes/controllers/save_controller.gd")

var editMode = true

#Node Reference
@onready var origin = $OriginMotion/Origin
@onready var camera = $Camera2D
@onready var controlPanel = $UILayer/ControlPanel
@onready var editControls = $UILayer/EditControls
@onready var tutorial = $UILayer/Tutorial
@onready var spriteViewer = $UILayer/EditControls/SpriteViewer
@onready var viewerArrows = $UILayer/ViewerArrows
@onready var spriteList = $UILayer/EditControls/SpriteList

@onready var replaceReviewDialog = $ReplaceReviewDialog
@onready var psdImportDialog = $PSDImportDialog

@onready var lines = $Lines

@onready var settingsMenu = $UILayer/ControlPanel/SettingsMenu

@onready var pushUpdates = $UILayer/PushUpdates

@onready var shadow = $shadowSprite

var ndi_manager: Node = null
var _ndi_label: Label = null

var _light_gizmo: Node2D = null

var capture_controller: CaptureController = null
var viewport_controller: ViewportController = null
var save_controller: AvatarSaveController = null


#Scene Reference
@onready var spriteObject = preload("res://ui_scenes/selectedSprite/spriteObject.tscn")

var saveLoaded = false

#Motion
var yVel = 0
var bounceSlider = 250

# Compatibility-facing flag polled by spriteObject while ViewportController
# owns the resize cooldown and one-shot drag snap.
var resize_active: bool = false

var bounceGravity = 1000

#Costumes
var costume = 1
var bounceOnCostumeChange = false

var bounceChange = 0.0
var screen_scale = 1.0

#IMPORTANT
var fileSystemOpen = false
var _sprite_id_random := RandomNumberGenerator.new()

#background input capture
signal emptiedCapture
signal pressedKey
var costumeKeys = ["1","2","3","4","5","6","7","8","9","0"]
signal spriteVisToggles(keysPressed:Array)
signal fatfuckingballs


func _exit_tree() -> void:
	_shutdown_import_workers()
	Global.detach_main(self)

func _shutdown_import_workers() -> void:
	if _psd_parser != null:
		_psd_parser.cancel()
	if _anim_parser != null and _anim_parser.has_method("cancel"):
		_anim_parser.cancel()
	for worker in [_psd_thread, _anim_thread]:
		if worker != null and worker.is_started():
			worker.wait_to_finish()
	if _import_group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_import_group_id)
		_import_group_id = -1
	if _load_group_id >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_load_group_id)
		_load_group_id = -1
	_psd_thread = null
	_anim_thread = null
	_psd_parser = null
	_anim_parser = null
	_anim_queue.clear()

func _ready():
	_sprite_id_random.randomize()
	Global.attach_main(self)
	Global.fail = $Failed
	capture_controller = CaptureControllerScene.new()
	capture_controller.name = "CaptureController"
	add_child(capture_controller)
	capture_controller.setup(self, Global, Saving)
	viewport_controller = ViewportControllerScene.new()
	viewport_controller.setup(self, Global, Saving)
	save_controller = SaveControllerScene.new()
	save_controller.name = "AvatarSaveController"
	add_child(save_controller)
	save_controller.setup(self, Global, Saving, UndoManager)

	screen_scale = DisplayServer.screen_get_scale()

	# DPI-aware UI scale. The project stretch scale (window/stretch/scale=1.5) is a flat
	# content multiplier tuned for macOS Retina, where it composes with Retina rendering
	# and the screen_scale-driven window sizing below. screen_get_scale() is macOS-only
	# (returns 1.0 on Windows/Linux), so off macOS that flat 1.5 was the ONLY scaling
	# applied and the UI came out oversized (1.5x at 100% display scaling). Off macOS,
	# drive content_scale_factor from the display's real DPI instead: 96dpi(100%)->1.0,
	# 120(125%)->1.25, 144(150%)->1.5, etc. NDI output is a separate SubViewport and is
	# unaffected.
	if OS.get_name() != "macOS":
		var _dpi := DisplayServer.screen_get_dpi(DisplayServer.window_get_current_screen())
		var _ui_scale := clampf(snappedf(float(_dpi) / 96.0, 0.25), 1.0, 3.0)
		get_window().content_scale_factor = _ui_scale

	Global.connect("startSpeaking",onSpeak)

	$UILayer/ControlPanel/MicButtong/Button.gui_input.connect(_on_mic_button_gui_input)

	ElgatoStreamDeck.on_key_down.connect(changeCostumeStreamDeck)
	
	$UILayer/ControlPanel/VersionLabels.visible = false
	$UILayer/ControlPanel/Links.visible = false

	save_controller.startup_restore()
	Saving.settings["newUser"] = false

	if Saving.settings.has("volume"):
		$UILayer/ControlPanel/volumeSlider.value = Saving.settings["volume"]
	if Saving.settings.has("sense"):
		$UILayer/ControlPanel/sensitiveSlider.value = Saving.settings["sense"]
	_style_control_sliders()

	if Saving.settings.has("windowSize"):
		get_window().size = ValueCodec.vector2i_value(Saving.settings["windowSize"], Vector2i(1280, 720))

	if Saving.settings.has("bounce"):
		bounceSlider = Saving.settings["bounce"]
	else:
		Saving.settings["bounce"] = 250

	if Saving.settings.has("maxFPS"):
		Engine.max_fps = Saving.settings["maxFPS"]
	else:
		Saving.settings["maxFPS"] = 60

	if Saving.settings.has("backgroundColor"):
		Global.backgroundColor = ValueCodec.color_value(Saving.settings["backgroundColor"], Color.TRANSPARENT)
	else:
		Saving.settings["backgroundColor"] = var_to_str(Color(0.0,0.0,0.0,0.0))

	if Saving.settings.has("filtering"):
		Global.filtering = Saving.settings["filtering"]
	else:
		Saving.settings["filtering"] = true

	if Saving.settings.has("gravity"):
		bounceGravity = Saving.settings["gravity"]
	else:
		Saving.settings["gravity"] = 1000

	if Saving.settings.has("costumeKeys"):
		costumeKeys = Saving.settings["costumeKeys"]
	else:
		Saving.settings["costumeKeys"] = costumeKeys

	if Saving.settings.has("blinkSpeed"):
		Global.blinkSpeed = Saving.settings["blinkSpeed"]
	else:
		Saving.settings["blinkSpeed"] = 1.0

	if Saving.settings.has("blinkChance"):
		Global.blinkChance = Saving.settings["blinkChance"]
	else:
		Saving.settings["blinkChance"] = 200

	if Saving.settings.has("bounceOnCostumeChange"):
		bounceOnCostumeChange = Saving.settings["bounceOnCostumeChange"]
	else:
		Saving.settings["bounceOnCostumeChange"] = false

	saveLoaded = true

	if screen_scale > 1.0:
		var logical_size = Vector2(get_window().size) / screen_scale
		if logical_size.x < 1280 or logical_size.y < 720:
			get_window().size = Vector2i(
				int(max(logical_size.x, 1280) * screen_scale),
				int(max(logical_size.y, 720) * screen_scale)
			)

	RenderingServer.set_default_clear_color(Global.backgroundColor)

	# NDI output (must be before setvalues so settings UI can reference ndi_manager)
	_init_ndi()

	swapMode()
	settingsMenu.setvalues()
	changeCostume(1)

	var s = get_viewport().get_visible_rect().size
	origin.position = s*0.5
	camera.position = origin.position

	_create_light_gizmo()

	# Put HUD elements on visibility layer 2 so they're excluded from NDI output
	# (NDI SubViewport only renders layer 1)
	for hud_node in [controlPanel, editControls, tutorial, viewerArrows, lines, pushUpdates, shadow, $Failed, $UILayer/MouseCursor]:
		hud_node.visibility_layer = 2

	# Pre-compile the blend-mode shader pipeline during startup so the first time a layer
	# switches to a screen-reading blend mode there's no one-frame compile hitch.
	_prewarm_blend_shader()

# Render the blend shader once, invisibly, to force Metal to build its pipeline now — the
# compile otherwise lands on the render thread the first time a backbuffer blend mode draws.
# One fully-transparent draw warms the whole shader (every mode shares a single program); a
# BackBufferCopy alongside warms the screen-read path too. Both are freed after a frame.
func _prewarm_blend_shader():
	var img = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var warm = Sprite2D.new()
	warm.texture = ImageTexture.create_from_image(img)
	warm.modulate.a = 0.0       # invisible — outputs nothing, but the draw still compiles the pipeline
	warm.visibility_layer = 2   # keep it out of NDI output just in case
	var mat = ShaderMaterial.new()
	mat.shader = BlendMode.SHADER
	mat.set_shader_parameter("blend_mode", BlendMode.Mode.MULTIPLY)
	warm.material = mat
	var bbc = BackBufferCopy.new()
	bbc.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	# Parented to origin so it sits at screen centre (actually rasterized, not frustum-culled);
	# BackBufferCopy first so the sprite's screen read is valid when it draws.
	origin.add_child(bbc)
	origin.add_child(warm)
	warm.position = Vector2.ZERO
	await get_tree().process_frame
	await get_tree().process_frame
	warm.queue_free()
	bbc.queue_free()

func _style_control_sliders():
	# White circle grabber (20x20, radius ~8)
	var sz = 20
	var center = sz / 2
	var radius_sq = 64  # 8*8
	var grabber_img = Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	grabber_img.fill(Color(0, 0, 0, 0))
	for px in range(sz):
		for py in range(sz):
			var dx = px - center
			var dy = py - center
			if dx * dx + dy * dy <= radius_sq:
				grabber_img.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
	var grabber_tex = ImageTexture.create_from_image(grabber_img)

	for s in [$UILayer/ControlPanel/volumeSlider, $UILayer/ControlPanel/sensitiveSlider]:
		s.add_theme_icon_override("grabber", grabber_tex)
		s.add_theme_icon_override("grabber_highlight", grabber_tex)
		s.add_theme_icon_override("grabber_disabled", grabber_tex)
		s.add_theme_constant_override("grabber_offset", 0)
		s.add_theme_constant_override("center_grabber", 1)

	# Right-click resets to factory defaults from autoload/saving.gd
	Global.make_slider_resettable($UILayer/ControlPanel/volumeSlider, 0.185)
	Global.make_slider_resettable($UILayer/ControlPanel/sensitiveSlider, 0.25)

	# Align sliders vertically with their meter bars, and inset horizontally by the
	# grabber radius so the disc stops at each end of the bar instead of overshooting
	$UILayer/ControlPanel/volumeSlider.offset_top = -40
	$UILayer/ControlPanel/volumeSlider.offset_bottom = -8
	$UILayer/ControlPanel/volumeSlider.offset_left = -574
	$UILayer/ControlPanel/volumeSlider.offset_right = -82
	$UILayer/ControlPanel/sensitiveSlider.offset_top = -64
	$UILayer/ControlPanel/sensitiveSlider.offset_bottom = -32
	$UILayer/ControlPanel/sensitiveSlider.offset_left = -574
	$UILayer/ControlPanel/sensitiveSlider.offset_right = -82

	# Replace level meter textures with clean shapes
	var bar_w = 512
	var bar_h = 8

	var under_img = Image.create(bar_w, bar_h, false, Image.FORMAT_RGBA8)
	under_img.fill(Color(0.2, 0.2, 0.22))
	var under_tex = ImageTexture.create_from_image(under_img)

	var pink_img = Image.create(bar_w, bar_h, false, Image.FORMAT_RGBA8)
	pink_img.fill(Color(1.0, 0.7, 0.8))
	var pink_tex = ImageTexture.create_from_image(pink_img)

	var blue_img = Image.create(bar_w, bar_h, false, Image.FORMAT_RGBA8)
	blue_img.fill(Color(0.55, 0.78, 1.0))
	var blue_tex = ImageTexture.create_from_image(blue_img)

	for bar in [$UILayer/ControlPanel/VolumeBar, $UILayer/ControlPanel/Sensitive]:
		bar.texture_under = under_tex
		bar.texture_over = null
	$UILayer/ControlPanel/Sensitive.texture_progress = pink_tex
	$UILayer/ControlPanel/VolumeBar.texture_progress = blue_tex

func _init_ndi():
	var NDIManagerScript = load("res://ndi/ndi_output_manager.gd")
	ndi_manager = Node.new()
	ndi_manager.set_script(NDIManagerScript)
	ndi_manager.name = "NDIManager"
	add_child(ndi_manager)

	# NDI status label above settings icon
	_ndi_label = Label.new()
	_ndi_label.name = "NDILabel"
	_ndi_label.text = "NDI\nON"
	_ndi_label.add_theme_font_size_override("font_size", 11)
	_ndi_label.add_theme_constant_override("line_spacing", -4)
	_ndi_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_ndi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ndi_label.position = Vector2(-52, -168)
	_ndi_label.size = Vector2(34, 28)
	_ndi_label.visible = false
	controlPanel.add_child(_ndi_label)

func _create_light_gizmo():
	# Lighting test disabled
	return
	var LightGizmoScript = load("res://ui_scenes/light/light_gizmo.gd")
	_light_gizmo = Node2D.new()
	_light_gizmo.set_script(LightGizmoScript)
	_light_gizmo.name = "LightGizmo"
	_light_gizmo.position = Vector2(200, -200)
	origin.add_child(_light_gizmo)

func _apply_light_data(ld: Dictionary):
	if _light_gizmo == null:
		return
	if ld.has("pos"):
		_light_gizmo.position = ValueCodec.vector2_value(ld["pos"])
	if ld.has("energy"):
		_light_gizmo.light_energy = ld["energy"]
	if ld.has("color"):
		_light_gizmo.light_color = ValueCodec.color_value(ld["color"], Color.WHITE)
	if ld.has("range"):
		_light_gizmo.light_range = ld["range"]
	if ld.has("enabled"):
		_light_gizmo.light_enabled = ld["enabled"]

func ndi_mark_dirty():
	if ndi_manager != null:
		ndi_manager.mark_dirty()

func _process(delta):
	# Freeze bounce while dragging the NDI crop box
	var crop_frozen = ndi_manager != null and ndi_manager.crop_dragging
	if crop_frozen:
		origin.get_parent().position.y = 0
		yVel = 0
		bounceChange = 0
	else:
		var hold = origin.get_parent().position.y

		origin.get_parent().position.y += yVel * 0.0166
		var p = origin.get_parent().position.y
		if p > 0.0:
			# Soft landing: ease the avatar into rest instead of a dead stop at the
			# bottom of the bounce. The hard clamp slammed the velocity to zero in
			# one frame, which dependent wiggle layers over-followed (a sharp jolt
			# only on the way down). Now the impact velocity bleeds and the position
			# eases back to rest over a few frames (a small settle-dip), so the
			# landing reads as smoothly as the rise. Snap to exact rest once tiny so
			# there's no sub-pixel jitter; gravity only applies while airborne.
			yVel = lerp(yVel, 0.0, 0.72)
			p = lerp(p, 0.0, 0.45)
			if p < 0.4 and absf(yVel) < 6.0:
				p = 0.0
				yVel = 0.0
			origin.get_parent().position.y = p
		elif p < 0.0:
			yVel += bounceGravity*0.0166
		bounceChange = hold - origin.get_parent().position.y
	
	if Input.is_action_just_pressed("openFolder") and !Global._text_field_active:
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	
	moveSpriteMenu(delta)
	
	fileSystemOpen = isFileSystemOpen()

	_process_psd_thread(delta)
	_process_import_thread(delta)
	_process_anim_thread(delta)
	save_controller.process_frame(delta)
	viewport_controller.process_frame()

	# NDI status indicator
	if _ndi_label != null and ndi_manager != null:
		_ndi_label.visible = !editMode and ndi_manager.is_enabled()

func _unhandled_input(event):
	viewport_controller.handle_unhandled_input(event)
	

func isFileSystemOpen():
	if save_controller != null and save_controller.is_dialog_open():
		Global.heldSprite = null
		return true
	if psdImportDialog.visible:
		Global.heldSprite = null
		return true
	if replaceReviewDialog.visible:
		return true
	if _import_dialog != null and _import_dialog.visible:
		Global.heldSprite = null
		return true
	if _replace_dialog != null and _replace_dialog.visible:
		return true
	if capture_controller != null and capture_controller.is_dialog_open():
		return true
	return false

#Displays control panel whether or not application is focused
func _notification(what):
	if controlPanel == null or pushUpdates == null:
		return
	match what:
		SceneTree.NOTIFICATION_APPLICATION_FOCUS_OUT:
			controlPanel.visible = false
			pushUpdates.visible = false
		SceneTree.NOTIFICATION_APPLICATION_FOCUS_IN:
			if !editMode:
				controlPanel.visible = true
			pushUpdates.visible = true
		NOTIFICATION_WM_CLOSE_REQUEST:
			if save_controller != null:
				save_controller.shutdown()
			# Belt-and-suspenders: also persist settings here in case the autoload's
			# _exit_tree doesn't fire (force-quit, certain Godot/OS paths)
			Saving.write_settings(Saving.settingsPath)
		30:
			onWindowSizeChange()

func onWindowSizeChange() -> void:
	viewport_controller.window_size_changed()


func onSpeak() -> void:
	if origin.get_parent().position.y > -16:
		yVel = bounceSlider * -1


func updateWindowTransparency() -> void:
	viewport_controller.update_window_transparency()


func swapMode() -> void:
	viewport_controller.swap_mode()


func _next_z_index() -> int:
	return Global.maximum_sprite_z() + 1


func _next_sprite_id() -> int:
	var candidate := _sprite_id_random.randi()
	while Global.sprite_by_id(candidate) != null:
		candidate = _sprite_id_random.randi()
	return candidate

#Adds sprite object to scene
func add_image(path):
	UndoManager.save_state()

	var id := _next_sprite_id()

	var sprite = spriteObject.instantiate()
	sprite.path = path
	sprite.id = id
	sprite.z = _next_z_index()
	origin.add_child(sprite)
	sprite.position = Vector2.ZERO

	Global.spriteList.updateData()
	ndi_mark_dirty()

	Global.pushUpdate("Added new sprite.")
	
func add_image_from_data(img: Image, layer_name: String, canvas_position: Vector2):
	var id := _next_sprite_id()

	var sprite = spriteObject.instantiate()
	sprite.loadedImage = img
	sprite.path = "psd://" + layer_name
	sprite.id = id
	origin.add_child(sprite)
	sprite.position = canvas_position

	return sprite

var _psd_parser: PSDParser = null
var _psd_thread: Thread = null
var _psd_result = null
var _psd_progress_dialog: Node2D = null
var _psd_replace_mode: bool = false

# Worker-pool sprite preparation (post-PSD-import)
var _import_group_id := -1
var _import_layers: Array = []
var _import_canvas_size: Vector2 = Vector2.ZERO
var _import_results: Array = []
var _import_normal_layers: Dictionary = {}
var _import_progress_dialog2: Node2D = null

# Threaded avatar JSON load (parallel PNG decode + polygon generation per sprite)
var _load_keys: Array = []
var _load_data_ref = null
var _load_results: Array = []
var _load_group_id := -1

var _anim_parser: APNGParser = null
var _anim_thread: Thread = null
var _anim_result = null
var _anim_progress_dialog: Node2D = null
var _anim_replace_mode: bool = false
var _anim_import_name: String = ""
var _anim_queue: Array = []

func _on_psd_dialog_file_selected(path):
	_begin_psd_parse(path, false)

func _begin_psd_parse(path: String, replace_mode: bool) -> void:
	if _psd_thread != null:
		Global.pushUpdate("A PSD import is already running.")
		return
	_psd_replace_mode = replace_mode
	_psd_parser = PSDParser.new()
	_psd_result = null

	# Show progress bar
	_psd_progress_dialog = _create_psd_progress_dialog()
	add_child(_psd_progress_dialog)

	# Run parser in a thread
	_psd_thread = Thread.new()
	var start_error := _psd_thread.start(func(): return _psd_parser.parse(path))
	if start_error != OK:
		_psd_thread = null
		_psd_parser = null
		_psd_progress_dialog.queue_free()
		_psd_progress_dialog = null
		_psd_replace_mode = false
		Global.pushUpdate("Could not start the PSD import worker.")
		Global.epicFail(start_error)

func _create_psd_progress_dialog() -> Node2D:
	var dialog = Node2D.new()
	dialog.z_index = 4095
	dialog.visibility_layer = 2
	dialog.position = camera.position

	var bg = ColorRect.new()
	bg.position = Vector2(-160, -50)
	bg.size = Vector2(320, 100)
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	dialog.add_child(bg)

	var label = Label.new()
	label.name = "StatusLabel"
	label.position = Vector2(-150, -40)
	label.size = Vector2(300, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Loading PSD..."
	dialog.add_child(label)

	var bar = ProgressBar.new()
	bar.name = "ProgressBar"
	bar.position = Vector2(-140, 0)
	bar.size = Vector2(280, 24)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	dialog.add_child(bar)

	var blocker = Area2D.new()
	blocker.add_to_group("penis")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	blocker.add_child(col)
	dialog.add_child(blocker)

	dialog.set_process(true)
	return dialog

func _process_psd_thread(_delta):
	if _psd_thread == null or _psd_parser == null:
		return
	if _psd_progress_dialog == null:
		return

	# Update progress bar
	_psd_progress_dialog.get_node("ProgressBar").value = _psd_parser.progress
	_psd_progress_dialog.get_node("StatusLabel").text = _psd_parser.status_text

	# Check if thread is done
	if !_psd_thread.is_alive():
		_psd_result = _psd_thread.wait_to_finish()
		_psd_thread = null

		# Remove progress dialog
		_psd_progress_dialog.queue_free()
		_psd_progress_dialog = null

		var result = _psd_result
		_psd_result = null
		_psd_parser = null

		if result.error != "":
			_psd_replace_mode = false
			if result.error != "Import cancelled.":
				Global.pushUpdate("PSD Error: " + result.error)
				Global.epicFail(ERR_INVALID_DATA)
			return

		if _psd_replace_mode:
			_psd_replace_mode = false
			_show_replace_review_from_psd(result)
		else:
			psdImportDialog.setup(result)
			psdImportDialog.visible = true

func _on_psd_import_confirmed(selected_layers: Array, canvas_size: Vector2, normal_layers: Dictionary = {}):
	_import_layers = selected_layers
	_import_canvas_size = canvas_size
	_import_normal_layers = normal_layers
	_import_results = []
	_import_results.resize(selected_layers.size())
	if selected_layers.is_empty():
		_import_layers = []
		_import_normal_layers = {}
		Global.pushUpdate("No PSD layers were selected.")
		return

	# Show progress dialog for sprite creation phase
	_import_progress_dialog2 = _create_psd_progress_dialog()
	_import_progress_dialog2.get_node("StatusLabel").text = "Processing sprites..."
	add_child(_import_progress_dialog2)

	# Use the bounded engine pool instead of creating one OS thread per layer.
	_import_group_id = WorkerThreadPool.add_group_task(
		_precompute_import_layer, selected_layers.size(), -1, false, "PSD layer preparation"
	)
	if _import_group_id < 0:
		_import_progress_dialog2.queue_free()
		_import_progress_dialog2 = null
		Global.pushUpdate("Could not start the PSD processing worker.")
		Global.epicFail(ERR_CANT_CREATE)

func _precompute_import_layer(index: int) -> void:
	var image: Image = _import_layers[index].image
	var premultiplied := image.duplicate()
	premultiplied.premultiply_alpha()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image)
	_import_results[index] = {
		"pma_image": premultiplied,
		"polygons": bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()), 4.0),
	}

func _load_worker_decode(idx: int):
	# Runs on a worker thread. Decodes the PNG, premultiplies alpha, and builds the
	# polygon outline for one sprite. Each task writes to its own _load_results slot,
	# so no mutex is needed for the result writes.
	var key = _load_keys[idx]
	var item_data = _load_data_ref[key]
	var img = Image.new()
	var has_image = false

	if item_data.has("path"):
		var err = img.load(item_data["path"])
		if err == OK:
			has_image = true
	if !has_image and item_data.has("imageData"):
		var raw = Marshalls.base64_to_raw(item_data["imageData"])
		if img.load_png_from_buffer(raw) == OK:
			has_image = true

	var result = {"ok": has_image}
	if has_image:
		var pma = img.duplicate()
		pma.premultiply_alpha()
		var bitmap = BitMap.new()
		bitmap.create_from_image_alpha(img)
		var polygons = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()), 4.0)
		result["image"] = img
		result["pma_image"] = pma
		result["polygons"] = polygons

		if item_data.has("normalImageData"):
			var nrml_raw = Marshalls.base64_to_raw(item_data["normalImageData"])
			var nrml = Image.new()
			if nrml.load_png_from_buffer(nrml_raw) == OK:
				result["normal_image"] = nrml

	_load_results[idx] = result

func _process_import_thread(_delta):
	if _import_group_id < 0:
		return

	# Update progress
	var count = _import_layers.size()
	if count > 0 and _import_progress_dialog2 != null:
		var completed := WorkerThreadPool.get_group_processed_element_count(_import_group_id)
		_import_progress_dialog2.get_node("ProgressBar").value = float(completed) / count
		_import_progress_dialog2.get_node("StatusLabel").text = "Processing sprites... " + str(completed) + "/" + str(count)

	if WorkerThreadPool.is_group_task_completed(_import_group_id):
		WorkerThreadPool.wait_for_group_task_completion(_import_group_id)
		_import_group_id = -1

		if _import_progress_dialog2 != null:
			_import_progress_dialog2.queue_free()
			_import_progress_dialog2 = null

		_finalize_psd_import()

func _finalize_psd_import():
	UndoManager.save_state()
	var canvas_center = _import_canvas_size * 0.5
	var layer_z = _next_z_index()
	var count = _import_layers.size()

	for i in range(count):
		var layer = _import_layers[i]
		var result = _import_results[i]

		var id := _next_sprite_id()

		var sprite = spriteObject.instantiate()
		sprite.loadedImage = layer.image
		sprite.path = "psd://" + layer.name
		sprite.id = id
		sprite._prebuilt_pma_image = result["pma_image"]
		sprite._prebuilt_polygons = result["polygons"]
		sprite.z = layer_z

		var layer_center = Vector2(
			(layer.left + layer.right) * 0.5,
			(layer.top + layer.bottom) * 0.5
		)
		# Check for matching normal map layer
		var layer_base = layer.name.to_lower()
		if _import_normal_layers.has(layer_base):
			var nrml_layer = _import_normal_layers[layer_base]
			sprite.loadedNormalImage = nrml_layer.image
			sprite.normalPath = "psd://" + nrml_layer.name

		origin.add_child(sprite)
		sprite.position = layer_center - canvas_center
		sprite.setZIndex()
		layer_z += 1

	Global.spriteList.updateData(true)
	Global.pushUpdate("Imported " + str(count) + " layers from PSD.")

	_import_layers = []
	_import_results = []
	_import_normal_layers = {}

	_save_post_import_snapshot()

func _on_psd_import_cancelled():
	if _psd_parser != null:
		_psd_parser.cancel()
	Global.pushUpdate("PSD import cancelled.")

func _save_post_import_snapshot():
	# Wait for spriteObject._ready() reparent timers (0.1s) to settle
	await get_tree().create_timer(0.2).timeout
	UndoManager.save_state()

# --- Animated GIF/APNG Import ---

func _start_animated_import(path: String, is_replace: bool):
	if _anim_thread != null:
		_anim_queue.append({"path": path, "replace": is_replace})
		return

	_anim_replace_mode = is_replace
	_anim_result = null
	_anim_import_name = path.get_file().get_basename()

	_anim_parser = APNGParser.new()

	_anim_progress_dialog = _create_anim_progress_dialog()
	add_child(_anim_progress_dialog)

	_anim_thread = Thread.new()
	var start_error := _anim_thread.start(func(): return _anim_parser.parse(path))
	if start_error != OK:
		_anim_thread = null
		_anim_parser = null
		_anim_progress_dialog.queue_free()
		_anim_progress_dialog = null
		Global.pushUpdate("Could not start the animated-image worker.")
		Global.epicFail(start_error)
		_process_anim_queue()

func _create_anim_progress_dialog() -> Node2D:
	var dialog = Node2D.new()
	dialog.z_index = 4095
	dialog.visibility_layer = 2
	dialog.position = camera.position

	var bg = ColorRect.new()
	bg.position = Vector2(-160, -50)
	bg.size = Vector2(320, 100)
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	dialog.add_child(bg)

	var label = Label.new()
	label.name = "StatusLabel"
	label.position = Vector2(-150, -40)
	label.size = Vector2(300, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Loading animated image..."
	dialog.add_child(label)

	var bar = ProgressBar.new()
	bar.name = "ProgressBar"
	bar.position = Vector2(-140, 0)
	bar.size = Vector2(280, 24)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	dialog.add_child(bar)

	var blocker = Area2D.new()
	blocker.add_to_group("penis")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	blocker.add_child(col)
	dialog.add_child(blocker)

	dialog.set_process(true)
	return dialog

func _process_anim_thread(_delta):
	if _anim_thread == null or _anim_parser == null:
		return
	if _anim_progress_dialog == null:
		return

	_anim_progress_dialog.get_node("ProgressBar").value = _anim_parser.progress
	_anim_progress_dialog.get_node("StatusLabel").text = _anim_parser.status_text

	if !_anim_thread.is_alive():
		_anim_result = _anim_thread.wait_to_finish()
		_anim_thread = null

		_anim_progress_dialog.queue_free()
		_anim_progress_dialog = null

		var result = _anim_result
		_anim_result = null
		_anim_parser = null

		if result.error != "":
			if result.error != "Import cancelled.":
				Global.pushUpdate("Import Error: " + result.error)
				Global.epicFail(ERR_INVALID_DATA)
			_process_anim_queue()
			return

		_finish_animated_import(result)
		_process_anim_queue()

func _process_anim_queue():
	if _anim_queue.size() > 0:
		var next = _anim_queue.pop_front()
		_start_animated_import(next["path"], next["replace"])

func _finish_animated_import(result):
	var frame_count = result.frames.size()
	var w = result.width
	var h = result.height

	# Cap frame count if sprite sheet would exceed max texture size
	var max_width = 16384
	if w * frame_count > max_width:
		frame_count = max_width / w
		Global.pushUpdate("Warning: Capped to " + str(frame_count) + " frames (texture size limit)")

	# Single-frame: import as static sprite
	if frame_count <= 1:
		if _anim_replace_mode:
			_replace_with_animated(result.frames[0].image, 1, 0)
		else:
			_add_animated_sprite(result.frames[0].image, 1, 0)
		return

	# Build horizontal sprite sheet
	var sheet = Image.create(w * frame_count, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	for i in range(frame_count):
		sheet.blit_rect(result.frames[i].image, Rect2i(0, 0, w, h), Vector2i(w * i, 0))

	# Calculate animation speed from average delay
	var total_delay: float = 0.0
	for i in range(frame_count):
		total_delay += result.frames[i].delay_ms
	var avg_delay_ms = total_delay / float(frame_count)
	var fps = 1000.0 / avg_delay_ms
	var anim_speed = int(round(fps * 6.0))
	if anim_speed <= 0:
		anim_speed = 60

	if _anim_replace_mode:
		_replace_with_animated(sheet, frame_count, anim_speed)
	else:
		_add_animated_sprite(sheet, frame_count, anim_speed)

func _add_animated_sprite(sheet: Image, frame_count: int, anim_speed: int):
	UndoManager.save_state()

	var id := _next_sprite_id()

	var sprite = spriteObject.instantiate()
	sprite.loadedImage = sheet
	sprite.path = "animated://" + _anim_import_name
	sprite.id = id
	sprite.frames = frame_count
	sprite.animSpeed = anim_speed
	sprite.z = _next_z_index()
	origin.add_child(sprite)
	sprite.position = Vector2.ZERO

	Global.spriteList.updateData()
	Global.pushUpdate("Imported animated sprite (" + str(frame_count) + " frames)")

func _replace_with_animated(sheet: Image, frame_count: int, anim_speed: int):
	if Global.heldSprite == null:
		return

	UndoManager.save_state()

	Global.heldSprite.imageData = sheet
	var pma = sheet.duplicate()
	pma.premultiply_alpha()
	var texture = ImageTexture.create_from_image(pma)
	Global.heldSprite.tex = texture
	Global.heldSprite.sprite.texture = texture
	Global.heldSprite.path = "animated://import"
	Global.heldSprite.frames = frame_count
	Global.heldSprite.animSpeed = anim_speed
	Global.heldSprite.changeFrames()
	Global.heldSprite.remadePolygon = false
	Global.heldSprite.remakePolygon()

	UndoManager.invalidate_image(Global.heldSprite.id)
	Global.spriteList.updateData()
	Global.pushUpdate("Replaced with animated sprite (" + str(frame_count) + " frames)")

# --- Unified Import Dialog ---

var _import_dialog: FileDialog = null

func _create_import_dialog():
	_import_dialog = FileDialog.new()
	_import_dialog.title = "Import"
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.png;PNG Files", "*.psd;PSD Files"])
	_import_dialog.use_native_dialog = true
	_import_dialog.files_selected.connect(_on_import_files_selected)
	add_child(_import_dialog)

func _on_import_button_pressed():
	if _import_dialog == null:
		_create_import_dialog()
	_import_dialog.popup_centered(Vector2i(600, 400))

func _on_import_files_selected(paths: PackedStringArray):
	if paths.size() == 0:
		return

	var psd_paths: Array = []
	var png_paths: Array = []
	for p in paths:
		match p.get_extension().to_lower():
			"psd": psd_paths.append(p)
			"png": png_paths.append(p)

	if psd_paths.size() > 0 and png_paths.size() > 0:
		Global.pushUpdate("Cannot mix PSD and PNG files. Select one type.")
		return
	if psd_paths.size() > 1:
		Global.pushUpdate("Select only one PSD file at a time.")
		return

	if psd_paths.size() == 1:
		_on_psd_dialog_file_selected(psd_paths[0])
	else:
		_import_png_files(png_paths)

func _import_png_files(paths: Array):
	UndoManager.save_state()

	# Separate normal maps from diffuse files
	var diffuse_paths = []
	var normal_map = {}  # base_name (lower) -> normal_path
	for path in paths:
		var filename = path.get_file().get_basename()
		if filename.to_lower().ends_with("_nrml"):
			var base = filename.substr(0, filename.length() - 5)
			normal_map[base.to_lower()] = path
		else:
			diffuse_paths.append(path)

	var count = 0
	for path in diffuse_paths:
		if path.get_extension().to_lower() == "png" and APNGParser.is_apng(path):
			_start_animated_import(path, false)
		else:
			var id := _next_sprite_id()
			var sprite = spriteObject.instantiate()
			sprite.path = path
			sprite.id = id
			sprite.z = _next_z_index()

			# Check for matching normal map
			var diffuse_base = path.get_file().get_basename().to_lower()
			if normal_map.has(diffuse_base):
				var nrml_img = Image.new()
				if nrml_img.load(normal_map[diffuse_base]) == OK:
					sprite.loadedNormalImage = nrml_img
					sprite.normalPath = normal_map[diffuse_base]
				normal_map.erase(diffuse_base)

			origin.add_child(sprite)
			sprite.position = Vector2.ZERO
		count += 1

	# Import remaining unmatched normals: try to pair with existing sprites
	for base in normal_map:
		var matched = false
		for spr in get_tree().get_nodes_in_group("saved"):
			var spr_base = spr.path.get_file().get_basename().to_lower()
			if spr_base == base:
				var nrml_img = Image.new()
				if nrml_img.load(normal_map[base]) == OK:
					spr.setNormalMap(nrml_img, normal_map[base])
					UndoManager.invalidate_normal(spr.id)
				matched = true
				break
		if !matched:
			Global.pushUpdate("No match for normal: " + normal_map[base].get_file())

	Global.spriteList.updateData()
	ndi_mark_dirty()
	if count == 1:
		Global.pushUpdate("Added new sprite.")
	elif count > 1:
		Global.pushUpdate("Imported " + str(count) + " sprites.")
	_save_post_import_snapshot()

func _on_save_button_pressed():
	save_controller.show_save_dialog()

func _on_load_button_pressed():
	save_controller.show_load_dialog()

#LOAD AVATAR
func _on_load_dialog_file_selected(path):
	UndoManager.save_state()
	var data = Saving.read_save(path)

	if data == null:
		Global.pushUpdate(Saving.last_error)
		return

	Global.heldSprite = null
	# Hide the old avatar immediately so it doesn't linger on screen during load
	origin.visible = false
	origin.queue_free()
	var new = Node2D.new()
	# Match the position onWindowSizeChange() will set later — otherwise panCamera()
	# would re-center the camera on (0,0) every frame and the UI would visibly drift
	new.position = get_viewport().get_visible_rect().size * 0.5
	# Keep the new avatar hidden while sprites stream in (and start transparent for fade-in)
	# Premult-alpha sprites need RGB and A scaled together — fading via modulate.a alone
	# leaves RGB at full brightness and the avatar reads as too bright mid-fade
	new.visible = false
	new.modulate = Color(0, 0, 0, 0)
	$OriginMotion.add_child(new)
	origin = new

	# Build the ordered sprite list from validated entries. Metadata is selected
	# by shape rather than a hard-coded name list so schema additions remain safe.
	_load_keys = []
	for _it in data:
		var _entry: Variant = data[_it]
		if _entry is Dictionary and _entry.get("type") == "sprite":
			_load_keys.append(_it)
	var _load_total = _load_keys.size()
	_load_data_ref = data
	_load_results = []
	_load_results.resize(_load_total)

	var _load_dialog: Node2D = null
	var _load_bar: ProgressBar = null
	if _load_total > 0:
		# Run PNG decode + premult + polygon generation in parallel across worker threads
		_load_group_id = WorkerThreadPool.add_group_task(_load_worker_decode, _load_total, -1, false, "Avatar load")
		if _load_group_id < 0:
			Global.pushUpdate("Avatar worker pool unavailable; using synchronous image setup.")
		var _load_start_ms = Time.get_ticks_msec()
		var _last_bar_ms = _load_start_ms
		# Only show the bar if decode is still running after 200 ms — fast loads skip it
		const BAR_SHOW_DELAY_MS = 200
		while _load_group_id >= 0 and !WorkerThreadPool.is_group_task_completed(_load_group_id):
			await get_tree().process_frame
			var now = Time.get_ticks_msec()
			if _load_dialog == null and now - _load_start_ms >= BAR_SHOW_DELAY_MS:
				# _create_progress_dialog attaches the dialog to UILayer itself.
				_load_dialog = _create_progress_dialog("Loading avatar...")
				_load_bar = _load_dialog.get_node("ProgressBar")
			if _load_dialog != null and now - _last_bar_ms >= 100:
				_last_bar_ms = now
				var done = WorkerThreadPool.get_group_processed_element_count(_load_group_id)
				_load_bar.value = float(done) / float(_load_total)
				_load_dialog.position = get_viewport().get_visible_rect().size * 0.5
		if _load_group_id >= 0:
			WorkerThreadPool.wait_for_group_task_completion(_load_group_id)
			_load_group_id = -1
		if _load_bar != null:
			_load_bar.value = 1.0

	# Spawn sprites synchronously now that decode/polygon work is prebuilt — this
	# loop is fast because each spriteObject._ready just adopts the prebuilt data
	for i in range(_load_total):
		var item = _load_keys[i]
		var sprite = spriteObject.instantiate()
		SpriteState.apply_before_ready(sprite, data[item])

		# Hand off the thread-decoded results, or fall back to the JSON-base64 path
		# if decode failed for some reason (sprite._ready will retry from base64)
		var r = _load_results[i] if i < _load_results.size() else null
		if r != null and r.get("ok", false):
			sprite.loadedImage = r["image"]
			sprite._prebuilt_pma_image = r["pma_image"]
			sprite._prebuilt_polygons = r["polygons"]
			if r.has("normal_image"):
				sprite.loadedNormalImage = r["normal_image"]
		else:
			if data[item].has("imageData"):
				sprite.loadedImageData = data[item]["imageData"]
			if data[item].has("normalImageData"):
				sprite.loadedNormalData = data[item]["normalImageData"]

		# Reparent is done synchronously below — don't fire the per-sprite 0.1s timer cascade
		sprite._skip_ready_reparent = true

		origin.add_child(sprite)
		sprite.position = ValueCodec.vector2_value(data[item]["pos"])
		# No physics ticks until the avatar is revealed
		sprite.set_process(false)

	# Release thread-state references so the result images can be freed once consumed
	_load_keys = []
	_load_data_ref = null
	_load_results = []

	# Single pass over every spawned sprite:
	#   - reparent to declared parent (replaces the per-sprite 0.1s _ready timer cascade)
	#   - pre-warm remakePolygon for animated sprites (so first-tick rebuild is a no-op)
	#   - re-enable physics so the first _process tick (drag snap, wobble) lands before reveal
	for spr in Global.sprite_nodes():
		if spr.parentId != null:
			var parent_sprite := Global.sprite_by_id(spr.parentId)
			if parent_sprite != null:
				spr.get_parent().remove_child(spr)
				parent_sprite.sprite.add_child(spr)
				spr.parentSprite = parent_sprite
				spr.set_owner(parent_sprite.sprite)
				spr._force_drag_snap = true
			else:
				spr.parentId = null
				spr.parentSprite = null
		if spr.frames > 1:
			spr.remakePolygon()
		spr.set_process(true)

	# Do remaining heavy post-load setup while the avatar is still hidden and the bar is
	# at 100% — this keeps the upcoming fade-in free of frame stutters
	_create_light_gizmo()
	if data.has("_light"):
		_apply_light_data(data["_light"])

	# Restore the global eye-tracking kill switch (legacy avatars default to on)
	Global.eyeTrackingGloballyEnabled = bool(data.get("_eyeTrackingGloballyEnabled", true))

	# Restore the per-avatar NDI crop box so the avatar arrives pre-framed.
	# Absent in old/third-party saves; keep the current crop in that case rather
	# than snapping to a default. recalculate_now() below reframes off this value.
	if data.has("_ndiCropRect"):
		var _cr = data["_ndiCropRect"]
		if _cr is Array and _cr.size() == 4:
			Saving.settings["ndiCropRect"] = [float(_cr[0]), float(_cr[1]), float(_cr[2]), float(_cr[3])]
	elif data.has("_ndiRulerY"):
		# Legacy crop-line-only save: keep the current box, snap its bottom to the line
		var _b = float(data["_ndiRulerY"])
		var _cur = Saving.settings.get("ndiCropRect", [-500.0, _b - 1000.0, 500.0, _b])
		Saving.settings["ndiCropRect"] = [float(_cur[0]), minf(float(_cur[1]), _b - 64.0), float(_cur[2]), _b]

	changeCostume(1)
	# The session-recovery file is ephemeral — never promote it to lastAvatar,
	# otherwise startup auto-load and Reset would pull from it instead of the
	# user's actual saved avatar.
	if path != AvatarSaveController.SESSION_SAVE_PATH:
		Saving.settings["lastAvatar"] = path
		# Persist immediately — _exit_tree isn't reliable across all shutdown paths
		Saving.write_settings(Saving.settingsPath)
	await Global.spriteList.updateData()

	onWindowSizeChange()

	# NDI reference auto-detect: now that all sprites are parented correctly we can
	# pick the ref layer here, behind the progress bar, instead of via a T+1s timer
	var has_ref = false
	for spr in get_tree().get_nodes_in_group("saved"):
		if spr.ndiRefLayer:
			has_ref = true
			break
	if !has_ref:
		# Prefer "Neck", fall back to "Body" — name must start with the keyword
		# (e.g. "Neck", "Body 2" match but "Sputnik Body" does not)
		var ref_candidates = ["neck", "body"]
		for keyword in ref_candidates:
			var found = false
			for spr in get_tree().get_nodes_in_group("saved"):
				var filename = spr.path.get_file().strip_edges().to_lower()
				while filename.contains("."):
					filename = filename.get_basename()
				if filename == keyword or filename.begins_with(keyword + " "):
					spr.ndiRefLayer = true
					found = true
					break
			if found:
				break

	# Force the NDI viewport's framing recomputation synchronously now instead of
	# waiting for the 1s debounce — eliminates the framing hitch ~1s after reveal
	if ndi_manager != null:
		ndi_manager.recalculate_now()

	if _load_dialog != null:
		_load_dialog.queue_free()

	Global.pushUpdate("Loaded avatar at: " + path)

	# Reveal the finished avatar and fade it in — scale RGB and A together for premult-alpha
	origin.visible = true
	var fade = create_tween()
	fade.tween_property(origin, "modulate", Color(1, 1, 1, 1), 0.3)

func _create_progress_dialog(status_text: String) -> Node2D:
	# Builds a modal progress dialog on UILayer (viewport-space), with a
	# fullscreen dimmer + click-blocker behind it. Centered on the viewport.
	# Caller does NOT need to add_child or update position — this function
	# attaches to UILayer; recentering on resize is handled in _process.
	var dialog = Node2D.new()
	dialog.z_index = 100
	dialog.position = get_viewport().get_visible_rect().size * 0.5

	# Backdrop dimmer + input blocker covering the whole viewport.
	# Oversized so it covers any plausible viewport without needing resize updates.
	var blocker = ColorRect.new()
	blocker.position = Vector2(-5000, -5000)
	blocker.size = Vector2(10000, 10000)
	blocker.color = Color(0, 0, 0, 0.35)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(blocker)

	var bg = ColorRect.new()
	bg.position = Vector2(-180, -55)
	bg.size = Vector2(360, 110)
	bg.color = Color(0.13, 0.13, 0.15, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(bg)

	var label = Label.new()
	label.name = "StatusLabel"
	label.position = Vector2(-170, -42)
	label.size = Vector2(340, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = status_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(label)

	var bar = ProgressBar.new()
	bar.name = "ProgressBar"
	bar.position = Vector2(-160, 5)
	bar.size = Vector2(320, 24)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = 0.0
	dialog.add_child(bar)

	$UILayer.add_child(dialog)
	return dialog

func onScreenshotPressed() -> void:
	if capture_controller != null:
		capture_controller.on_capture_pressed()


func onScreenshotReleased() -> void:
	if capture_controller != null:
		capture_controller.on_capture_released()


# Build the same Dictionary structure manual save and session auto-save both
# write out. Image references go in `_image_ref` / `_normal_image_ref` so the
# AvatarSaveController can base64-encode them off the main thread.
func _build_avatar_save_data() -> Dictionary:
	var data = {}
	var nodes = get_tree().get_nodes_in_group("saved")
	var id = 0
	for child in nodes:
		if child.type == "sprite":
			data[id] = SpriteState.capture_save(child)
		id += 1

	if _light_gizmo != null:
		data["_light"] = {
			"pos": var_to_str(_light_gizmo.position),
			"energy": _light_gizmo.light_energy,
			"color": var_to_str(_light_gizmo.light_color),
			"range": _light_gizmo.light_range,
			"enabled": _light_gizmo.light_enabled,
		}
	data["_eyeTrackingGloballyEnabled"] = Global.eyeTrackingGloballyEnabled
	data["_schemaVersion"] = AvatarSave.CURRENT_VERSION
	# Per-avatar NDI crop box (origin-relative [left, top, right, bottom]). Travels
	# with the avatar so a purchased/shared avatar arrives pre-framed and never needs
	# manual re-cropping. The legacy "_ndiRulerY" (box bottom) is written too so the
	# save still pre-frames on older builds.
	var _crop = Saving.settings.get("ndiCropRect", [-500.0, -800.0, 500.0, 200.0])
	data["_ndiCropRect"] = _crop
	data["_ndiRulerY"] = float(_crop[3])
	return data

func _on_link_button_pressed():
	Global.reparentMode = true
	Global.chain.enable(Global.reparentMode)
	
	Global.pushUpdate("Linking sprite...")


func _on_kofi_pressed():
	OS.shell_open("https://ko-fi.com/kaiakairos")
	Global.pushUpdate("Support me on ko-fi!")


func _on_twitter_pressed():
	OS.shell_open("https://twitter.com/kaiakairos")
	Global.pushUpdate("Follow me on twitter!")


# --- Unified Replace Flow ---

var _replace_dialog: FileDialog = null

func _create_replace_dialog():
	_replace_dialog = FileDialog.new()
	_replace_dialog.title = "Replace"
	_replace_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_replace_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_replace_dialog.filters = PackedStringArray(["*.psd;PSD Files", "*.png;PNG Files"])
	_replace_dialog.use_native_dialog = true
	_replace_dialog.file_selected.connect(_on_replace_file_selected)
	add_child(_replace_dialog)

func _on_replace_button_pressed():
	if _replace_dialog == null:
		_create_replace_dialog()
	_replace_dialog.popup_centered(Vector2i(600, 400))

func _on_replace_file_selected(path: String):
	if path.get_extension().to_lower() == "psd":
		_handle_replace_from_psd(path)
	elif path.get_extension().to_lower() == "png":
		_handle_replace_single_png(path)
	else:
		Global.pushUpdate("Unsupported file type: " + path.get_extension())

static func _extract_sprite_name(sprite_path: String) -> String:
	if sprite_path.begins_with("psd://"):
		return sprite_path.substr(6)
	if sprite_path.begins_with("animated://"):
		return sprite_path.substr(11)
	var filename = sprite_path.get_file()
	var ext = filename.get_extension()
	if ext != "":
		filename = filename.substr(0, filename.length() - ext.length() - 1)
	return filename

func _handle_replace_from_psd(path: String):
	_begin_psd_parse(path, true)

func _show_replace_review_from_psd(psd_result):
	var sprites = get_tree().get_nodes_in_group("saved")

	# Build sprite name lookup (case-insensitive) -> array of sprites
	var sprite_lookup: Dictionary = {}
	for s in sprites:
		var sname = _extract_sprite_name(s.path).to_lower()
		if !sprite_lookup.has(sname):
			sprite_lookup[sname] = []
		sprite_lookup[sname].append(s)

	# Build PSD layer lookup (case-insensitive, skip invalid layers)
	var layer_lookup: Dictionary = {}
	for layer in psd_result.layers:
		if layer.width <= 0 or layer.height <= 0:
			continue
		if layer.image == null:
			continue
		layer_lookup[layer.name.to_lower()] = layer

	# Compute matched, new, orphaned
	var matched: Array = []
	var matched_sprite_ids: Dictionary = {}
	var matched_layer_names: Dictionary = {}

	for lname in layer_lookup:
		var layer = layer_lookup[lname]
		if sprite_lookup.has(lname):
			for s in sprite_lookup[lname]:
				matched.append({"sprite": s, "name": layer.name, "image": layer.image})
				matched_sprite_ids[s.get_instance_id()] = true
			matched_layer_names[lname] = true

	# New items: layers not matched to any sprite
	var new_items: Array = []
	var canvas_center = Vector2(psd_result.width, psd_result.height) * 0.5
	for lname in layer_lookup:
		if !matched_layer_names.has(lname):
			var layer = layer_lookup[lname]
			var layer_center = Vector2(
				(layer.left + layer.right) * 0.5,
				(layer.top + layer.bottom) * 0.5
			)
			var pos = layer_center - canvas_center
			new_items.append({"name": layer.name, "image": layer.image, "position": pos})

	# Orphaned sprites: in project but not in source
	var orphaned: Array = []
	for s in sprites:
		if !matched_sprite_ids.has(s.get_instance_id()):
			orphaned.append(s)

	var canvas_size = Vector2(psd_result.width, psd_result.height)
	replaceReviewDialog.setup(matched, new_items, orphaned, canvas_size)
	replaceReviewDialog.visible = true

func _handle_replace_from_folder(folder_path: String):
	var items: Array = []
	var dir = DirAccess.open(folder_path)
	if dir == null:
		Global.pushUpdate("Cannot open folder: " + folder_path)
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if !dir.current_is_dir() and file_name.get_extension().to_lower() == "png":
			var full_path = folder_path.path_join(file_name)
			var img = Image.new()
			if img.load(full_path) == OK:
				var name = file_name.substr(0, file_name.length() - file_name.get_extension().length() - 1)
				items.append({"name": name, "image": img, "position": Vector2.ZERO})
		file_name = dir.get_next()
	dir.list_dir_end()

	if items.size() == 0:
		Global.pushUpdate("No PNG files found in folder.")
		return

	_show_replace_review_from_items(items, Vector2.ZERO)

func _show_replace_review_from_items(items: Array, canvas_size: Vector2):
	var sprites = get_tree().get_nodes_in_group("saved")

	# Build sprite name lookup (case-insensitive)
	var sprite_lookup: Dictionary = {}
	for s in sprites:
		var sname = _extract_sprite_name(s.path).to_lower()
		if !sprite_lookup.has(sname):
			sprite_lookup[sname] = []
		sprite_lookup[sname].append(s)

	var matched: Array = []
	var matched_sprite_ids: Dictionary = {}
	var matched_item_names: Dictionary = {}

	for item in items:
		var iname = item["name"].to_lower()
		if sprite_lookup.has(iname):
			for s in sprite_lookup[iname]:
				matched.append({"sprite": s, "name": item["name"], "image": item["image"]})
				matched_sprite_ids[s.get_instance_id()] = true
			matched_item_names[iname] = true

	# New items: not matched
	var new_items: Array = []
	for item in items:
		if !matched_item_names.has(item["name"].to_lower()):
			new_items.append(item)

	# Orphaned sprites
	var orphaned: Array = []
	for s in sprites:
		if !matched_sprite_ids.has(s.get_instance_id()):
			orphaned.append(s)

	replaceReviewDialog.setup(matched, new_items, orphaned, canvas_size)
	replaceReviewDialog.visible = true

func _handle_replace_single_png(path: String):
	if Global.heldSprite == null:
		Global.pushUpdate("Select a sprite first to replace with a single PNG.")
		return

	# Check for APNG
	if APNGParser.is_apng(path):
		_start_animated_import(path, true)
		return

	# Show simple confirmation dialog
	var sprite_name = _extract_sprite_name(Global.heldSprite.path)
	var file_name = path.get_file()
	_show_single_replace_confirm(path, sprite_name, file_name)

var _single_replace_dialog: Node2D = null
var _single_replace_path: String = ""

func _show_single_replace_confirm(path: String, sprite_name: String, file_name: String):
	_single_replace_path = path

	_single_replace_dialog = Node2D.new()
	_single_replace_dialog.z_index = 4095
	_single_replace_dialog.visibility_layer = 2
	_single_replace_dialog.position = camera.position

	var blocker = Area2D.new()
	blocker.add_to_group("penis")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	blocker.add_child(col)
	_single_replace_dialog.add_child(blocker)

	var bg = ColorRect.new()
	bg.position = Vector2(-180, -60)
	bg.size = Vector2(360, 120)
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	_single_replace_dialog.add_child(bg)

	var label = Label.new()
	label.position = Vector2(-170, -50)
	label.size = Vector2(340, 48)
	label.text = "Replace \"" + sprite_name + "\" with \"" + file_name + "\"?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	_single_replace_dialog.add_child(label)

	var buttons = HBoxContainer.new()
	buttons.position = Vector2(-100, 10)
	buttons.size = Vector2(200, 40)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	_single_replace_dialog.add_child(buttons)

	var replaceBtn = Button.new()
	replaceBtn.text = "Replace"
	replaceBtn.custom_minimum_size = Vector2(80, 32)
	replaceBtn.pressed.connect(_on_single_replace_confirmed)
	buttons.add_child(replaceBtn)

	var cancelBtn = Button.new()
	cancelBtn.text = "Cancel"
	cancelBtn.custom_minimum_size = Vector2(80, 32)
	cancelBtn.pressed.connect(_on_single_replace_cancelled)
	buttons.add_child(cancelBtn)

	add_child(_single_replace_dialog)

func _on_single_replace_confirmed():
	if _single_replace_dialog != null:
		_single_replace_dialog.queue_free()
		_single_replace_dialog = null

	if Global.heldSprite == null:
		return

	var path = _single_replace_path
	UndoManager.save_state()
	Global.heldSprite.replaceSprite(path)
	UndoManager.invalidate_image(Global.heldSprite.id)
	Global.spriteList.updateData()
	Global.pushUpdate("Replaced sprite with: " + path.get_file())

func _on_single_replace_cancelled():
	if _single_replace_dialog != null:
		_single_replace_dialog.queue_free()
		_single_replace_dialog = null
	Global.pushUpdate("Replace cancelled.")

# --- Replace Review Dialog Handlers ---

func _on_replace_confirmed(matched: Array, new_items: Array, orphaned_sprites: Array, canvas_size: Vector2, remove_orphans: bool):
	UndoManager.save_state()
	var replaced = 0
	var added = 0
	var removed = 0

	# Replace matched sprites
	for entry in matched:
		entry["sprite"].replaceSpriteFromData(entry["image"], entry["name"])
		UndoManager.invalidate_image(entry["sprite"].id)
		replaced += 1

	# Add new items (user-selected via checkboxes)
	for item in new_items:
		add_image_from_data(item["image"], item["name"], item["position"])
		added += 1

	# Remove orphans (if opted in)
	if remove_orphans:
		for s in orphaned_sprites:
			if is_instance_valid(s):
				if Global.heldSprite == s:
					Global.heldSprite = null
				s.queue_free()
				removed += 1

	Global.spriteList.updateData()
	ndi_mark_dirty()

	var msg = "Replaced " + str(replaced) + " layers"
	if added > 0:
		msg += ", added " + str(added) + " new"
	if removed > 0:
		msg += ", removed " + str(removed) + " orphaned"
	Global.pushUpdate(msg + ".")

func _on_replace_cancelled():
	Global.pushUpdate("Replace cancelled.")


func _on_duplicate_button_pressed():
	if Global.heldSprite == null:
		return
	UndoManager.save_state()
	var id := _next_sprite_id()
	
	var sprite = spriteObject.instantiate()
	SpriteState.copy_for_duplicate(Global.heldSprite, sprite)
	sprite.id = id

	origin.add_child(sprite)

	if Global.heldSprite.parentId != null and Global.heldSprite.parentSprite != null:
		sprite._skip_ready_reparent = true
		var newParent = Global.heldSprite.parentSprite
		sprite.get_parent().remove_child(sprite)
		newParent.sprite.add_child(sprite)
		sprite.parentId = Global.heldSprite.parentId
		sprite.parentSprite = newParent
		sprite.position = Global.heldSprite.position
	else:
		sprite.position = Global.heldSprite.position

	Global.heldSprite = sprite

	Global.spriteList.updateData()

	Global.pushUpdate("Duplicated sprite.")

func changeCostumeStreamDeck(id: String):
	match id:
		"1":changeCostume(1)
		"2":changeCostume(2)
		"3":changeCostume(3)
		"4":changeCostume(4)
		"5":changeCostume(5)
		"6":changeCostume(6)
		"7":changeCostume(7)
		"8":changeCostume(8)
		"9":changeCostume(9)
		"10":changeCostume(10)

func changeCostume(newCostume):
	costume = newCostume
	Global.heldSprite = null
	var nodes = get_tree().get_nodes_in_group("saved")
	for sprite in nodes:
		sprite.applyCostumeVisibility()   # costume membership, honoring a manual hide
	Global.spriteEdit.layerSelected()
	spriteList.updateAllVisible()
	
	if bounceOnCostumeChange:
		onSpeak()

	ndi_mark_dirty()
	Global.pushUpdate("Change costume: " + str(newCostume))
	
func moveSpriteMenu(delta):

	#moves sprite viewer editor thing around

	var size = get_viewport().get_visible_rect().size
	var topY = editControls.MENU_BAR_HEIGHT + 2

	# Total panel content extent — computed by sprite_viewer's layout pass.
	# Falls back to a sane default until the panel finishes its first layout.
	var windowLength = Global.spriteEdit.content_height if Global.spriteEdit.content_height > 0 else 1150

	viewerArrows.get_node("Arrows").visible = false
	viewerArrows.get_node("Arrows2").visible = false

	if !Global.spriteEdit.visible:
		return

	if size.y > windowLength+50:
		Global.spriteEdit.position.y = topY
		return

	if Global.spriteEdit.position.y > topY:
		Global.spriteEdit.position.y = round(topY)
	elif Global.spriteEdit.position.y < size.y-windowLength:
		Global.spriteEdit.position.y = round(size.y-windowLength)
	

	
#UNAMED BUT THIS IS THE MICROPHONE MENU BUTTON
func _on_button_pressed():
	$UILayer/ControlPanel/MicInputSelect.visible = !$UILayer/ControlPanel/MicInputSelect.visible
	settingsMenu.visible = false

func _on_mic_button_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		Global.micMuted = !Global.micMuted
		if Global.micMuted:
			$UILayer/ControlPanel/MicButtong.modulate = Color(1, 0.3, 0.3)
			Global.pushUpdate("Microphone muted.")
		else:
			$UILayer/ControlPanel/MicButtong.modulate = Color(1, 1, 1)
			Global.pushUpdate("Microphone unmuted.")


func _on_settings_buttons_pressed():
	settingsMenu.visible = !settingsMenu.visible


func _on_background_input_capture_bg_key_pressed(node, keys_pressed):
	if Global._z_input_active:
		return
	var keyStrings = []

	for i in keys_pressed:
		if keys_pressed[i]:
			keyStrings.append(OS.get_keycode_string(i) if !OS.get_keycode_string(i).strip_edges().is_empty() else "Keycode" + str(i))

	if fileSystemOpen:
		return
	
	if keyStrings.size() <= 0:
		emit_signal("emptiedCapture")
		return

	# Animation tab "Bind key": capture the next key into the target clip instead
	# of triggering anything.
	if Global.awaitingAnimKeyBind and Global.animKeyBindClip != null:
		Global.animKeyBindClip["key"] = keyStrings[0]
		Global.awaitingAnimKeyBind = false
		Global.animKeyBindClip = null
		return

	if settingsMenu.awaitingCostumeInput >= 0:
		
		if keyStrings[0] == "Keycode1":
			if !settingsMenu.hasMouse:
				emit_signal("pressedKey")
				return
		
		var currentButton = costumeKeys[settingsMenu.awaitingCostumeInput]
		costumeKeys[settingsMenu.awaitingCostumeInput] = keyStrings[0]
		Saving.settings["costumeKeys"] = costumeKeys
		Global.pushUpdate("Changed costume " + str(settingsMenu.awaitingCostumeInput+1) + " hotkey from \"" + currentButton + "\" to \"" + keyStrings[0] + "\"")
		emit_signal("pressedKey")
	
	for key in keyStrings:
		var i = costumeKeys.find(key)
		if i >= 0:
			changeCostume(i+1)

	# Animation key triggers — fire every layer's key-bound clips. Skipped while
	# binding a costume key or typing into a text field.
	if settingsMenu.awaitingCostumeInput < 0 and not Global._is_any_field_focused():
		for key in keyStrings:
			for s in get_tree().get_nodes_in_group("saved"):
				if s.type == "sprite":
					s.triggerAnimationKey(key)
	


func bgInputSprite(node, keys_pressed):
	if Global._z_input_active:
		return
	if fileSystemOpen:
		return
	var keyStrings = []
	
	for i in keys_pressed:
		if keys_pressed[i]:
			keyStrings.append(OS.get_keycode_string(i) if !OS.get_keycode_string(i).strip_edges().is_empty() else "Keycode" + str(i))
	
	if keyStrings.size() <= 0:
		emit_signal("fatfuckingballs")
		return
	
	spriteVisToggles.emit(keyStrings)

func _on_clear_avatar_pressed():
	UndoManager.save_state()
	Global.heldSprite = null
	origin.queue_free()
	var new = Node2D.new()
	$OriginMotion.add_child(new)
	origin = new
	Global.spriteList.updateData()
	onWindowSizeChange()
	ndi_mark_dirty()
	Global.pushUpdate("Cleared avatar.")

func _on_reset_avatar_pressed():
	var path = Saving.settings["lastAvatar"]
	if path == null or path == "":
		Global.pushUpdate("No avatar to reset.")
		return
	_on_load_dialog_file_selected(path)
	Global.pushUpdate("Reset avatar to last saved state.")
