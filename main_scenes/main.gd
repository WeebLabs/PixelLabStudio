extends Node2D

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
# Save/Load FileDialogs are created in code (see _create_save_load_dialogs)
# rather than in the scene because scene-tree FileDialogs don't reliably
# route to the OS native dialog even with use_native_dialog=true set.
var saveDialog: FileDialog = null
var loadDialog: FileDialog = null
@onready var psdImportDialog = $PSDImportDialog

@onready var lines = $Lines

@onready var settingsMenu = $UILayer/ControlPanel/SettingsMenu

@onready var pushUpdates = $UILayer/PushUpdates

@onready var shadow = $shadowSprite

var ndi_manager: Node = null
var _ndi_label: Label = null

var _light_gizmo: Node2D = null

var _save_thread: Thread = null
var _save_progress: float = 0.0
var _save_progress_dialog: Node2D = null

var _screenshot_dialog: FileDialog = null
var _screenshot_image: Image = null

# Recording state
var _recording: bool = false
var _recording_vp: SubViewport = null
var _recording_cam: Camera2D = null
var _recording_file: FileAccess = null
var _recording_temp_path: String = ""
var _recording_frame_count: int = 0
var _recording_timer: float = 0.0
var _recording_size: Vector2i = Vector2i.ZERO
var _record_dialog: FileDialog = null
var _encode_thread: Thread = null
var _encoding: bool = false
var _encode_progress: float = 0.0
var _encode_progress_dialog: Node2D = null
var _encode_progress_path: String = ""
var _encode_total_frames: int = 0


#Scene Reference
@onready var spriteObject = preload("res://ui_scenes/selectedSprite/spriteObject.tscn")

var saveLoaded = false

#Motion
var yVel = 0
var bounceSlider = 250

# Window-resize freeze. While the window is being resized, sprites halt
# (see spriteObject._process). After the viewport size stays put for
# RESIZE_COOLDOWN_FRAMES consecutive frames we clear the flag and force one
# drag-snap so the resumed physics don't react to the cumulative position
# delta. _last_viewport_size tracks the previous frame's size for change
# detection.
const RESIZE_COOLDOWN_FRAMES = 5
var resize_active: bool = false
var _resize_cooldown: int = 0
var _last_viewport_size: Vector2 = Vector2.ZERO

# Session auto-save. Every time the user makes an undoable edit, _session_dirty
# is flipped on; after SESSION_AUTO_SAVE_INTERVAL seconds the rig is encoded
# in a background thread and written to SESSION_SAVE_PATH. On the next launch,
# if the session file is newer than the lastAvatar save, we offer to restore
# instead of loading the older one.
const SESSION_SAVE_PATH = "user://session.pngtp"
const SESSION_AUTO_SAVE_INTERVAL = 60.0
var _session_dirty: bool = false
var _session_timer: float = 0.0
var _session_thread: Thread = null
var _session_recovery_dialog: Node2D = null
var bounceGravity = 1000

#Costumes
var costume = 1
var bounceOnCostumeChange = false

#Zooming
var scaleOverall = 100

#Camera Pan
var _panning = false
var _pan_offset = Vector2.ZERO

var bounceChange = 0.0
var screen_scale = 1.0

#IMPORTANT
var fileSystemOpen = false

#background input capture
signal emptiedCapture
signal pressedKey
var costumeKeys = ["1","2","3","4","5","6","7","8","9","0"]
signal spriteVisToggles(keysPressed:Array)
signal fatfuckingballs

func _ready():
	Global.main = self
	Global.fail = $Failed

	_create_save_load_dialogs()

	screen_scale = DisplayServer.screen_get_scale()

	Global.connect("startSpeaking",onSpeak)

	$UILayer/ControlPanel/MicButtong/Button.gui_input.connect(_on_mic_button_gui_input)

	ElgatoStreamDeck.on_key_down.connect(changeCostumeStreamDeck)
	
	$UILayer/ControlPanel/VersionLabels.visible = false
	$UILayer/ControlPanel/Links.visible = false

	# Hook every undoable edit to the session-dirty flag so the auto-save tick
	# in _process knows there's unsaved work to capture.
	UndoManager.state_saved.connect(_on_undo_state_saved)

	# Startup load: if a session-recovery file exists and is newer than the
	# lastAvatar save, prompt the user to restore it instead of loading the
	# older file. Otherwise fall back to the normal lastAvatar restore.
	# (UndoManager.save_state is gated on saveLoaded, so any state captures
	# during load itself are no-ops.)
	var last_avatar_path = Saving.settings.get("lastAvatar", "")
	if _has_recoverable_session(last_avatar_path):
		_show_session_recovery_dialog(last_avatar_path)
	elif last_avatar_path != "":
		_on_load_dialog_file_selected(last_avatar_path)
	Saving.settings["newUser"] = false

	if Saving.settings.has("volume"):
		$UILayer/ControlPanel/volumeSlider.value = Saving.settings["volume"]
	if Saving.settings.has("sense"):
		$UILayer/ControlPanel/sensitiveSlider.value = Saving.settings["sense"]
	_style_control_sliders()

	if Saving.settings.has("windowSize"):
		get_window().size = str_to_var(Saving.settings["windowSize"])

	if Saving.settings.has("bounce"):
		bounceSlider = Saving.settings["bounce"]
	else:
		Saving.settings["bounce"] = 250

	if Saving.settings.has("maxFPS"):
		Engine.max_fps = Saving.settings["maxFPS"]
	else:
		Saving.settings["maxFPS"] = 60

	if Saving.settings.has("backgroundColor"):
		Global.backgroundColor = str_to_var(Saving.settings["backgroundColor"])
	else:
		Saving.settings["backgroundColor"] = var_to_str(Color(0.0,0.0,0.0,0.0))

	if Saving.settings.has("filtering"):
		Global.filtering = Saving.settings["filtering"]
	else:
		Saving.settings["filtering"] = false

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
		_light_gizmo.position = str_to_var(ld["pos"])
	if ld.has("energy"):
		_light_gizmo.light_energy = ld["energy"]
	if ld.has("color"):
		_light_gizmo.light_color = str_to_var(ld["color"])
	if ld.has("range"):
		_light_gizmo.light_range = ld["range"]
	if ld.has("enabled"):
		_light_gizmo.light_enabled = ld["enabled"]

func ndi_mark_dirty():
	if ndi_manager != null:
		ndi_manager.mark_dirty()

func _process(delta):
	_update_resize_state()

	# Freeze bounce while dragging NDI ruler
	var ruler_frozen = ndi_manager != null and ndi_manager.ruler_dragging
	if ruler_frozen:
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
	zoomScene()
	
	fileSystemOpen = isFileSystemOpen()

	_process_psd_thread(delta)
	_process_import_thread(delta)
	_process_anim_thread(delta)
	_process_save_thread(delta)
	_process_session_save(delta)
	_process_recording(delta)
	panCamera()
	followShadow()

	# NDI status indicator
	if _ndi_label != null and ndi_manager != null:
		_ndi_label.visible = !editMode and ndi_manager.is_enabled()

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
	elif event is InputEventMouseMotion and _panning:
		_pan_offset -= event.relative / camera.zoom
		onWindowSizeChange()

func panCamera():
	camera.position = origin.position + _pan_offset

func followShadow():
	shadow.visible = is_instance_valid(Global.heldSprite)
	if !shadow.visible:
		return
	
	shadow.global_position = Global.heldSprite.sprite.global_position + Vector2(6,6)
	shadow.global_rotation = Global.heldSprite.sprite.global_rotation
	shadow.offset = Global.heldSprite.sprite.offset
		
	shadow.texture = Global.heldSprite.sprite.texture
	shadow.hframes = Global.heldSprite.sprite.hframes
	shadow.frame = Global.heldSprite.sprite.frame
	

func isFileSystemOpen():
	for obj in [saveDialog, loadDialog]:
		if obj.visible:
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
	if _screenshot_dialog != null and _screenshot_dialog.visible:
		return true
	if _record_dialog != null and _record_dialog.visible:
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
			if _save_thread != null:
				_save_thread.wait_to_finish()
				_save_thread = null
			if _save_progress_dialog != null:
				_save_progress_dialog.queue_free()
				_save_progress_dialog = null
			# Belt-and-suspenders: also persist settings here in case the autoload's
			# _exit_tree doesn't fire (force-quit, certain Godot/OS paths)
			Saving.write_settings(Saving.settingsPath)
		30:
			onWindowSizeChange()

# Drives the resize-freeze: while the viewport size changes between frames,
# `resize_active` is true and sprites halt entirely. When the size has been
# stable for RESIZE_COOLDOWN_FRAMES frames we clear the flag and force a
# one-shot drag-snap on every sprite so they resume cleanly from the new
# origin without feeding the cumulative position delta into stretch().
func _update_resize_state():
	var s = get_viewport().get_visible_rect().size
	if s != _last_viewport_size:
		_last_viewport_size = s
		resize_active = true
		_resize_cooldown = RESIZE_COOLDOWN_FRAMES
		return
	if _resize_cooldown > 0:
		_resize_cooldown -= 1
		if _resize_cooldown == 0:
			resize_active = false
			for spr in get_tree().get_nodes_in_group("saved"):
				spr._force_drag_snap = true

func onWindowSizeChange():
	if !saveLoaded:
		return
	Saving.settings["windowSize"] = var_to_str(get_window().size)
	var s = get_viewport().get_visible_rect().size
	origin.position = s*0.5
	# Sprites are children of `origin` and would otherwise stretch/glitch when
	# origin teleports. We don't snap here — _update_resize_state() freezes
	# sprite _process while the window is mid-resize and force-snaps each
	# sprite once when the viewport size stabilizes.

	lines.position = s*0.5
	lines.drawLine()
	
	camera.position = origin.position + _pan_offset
	# All HUD lives on UILayer (CanvasLayer) — positions are viewport-relative
	# directly, no camera offset needed.
	controlPanel.position = s  # bottom-right anchor; children use negative offsets
	tutorial.position = controlPanel.position
	spriteList.position.y = editControls.MENU_BAR_HEIGHT + 2
	spriteList._apply_size()
	pushUpdates.position = Vector2(0, s.y)  # bottom-left anchor

func zoomScene():
	#Handles Zooming
	if Input.is_action_pressed("control"):
		if Input.is_action_just_pressed("scrollUp"):
			if scaleOverall < 400:
				camera.zoom += Vector2(0.1,0.1)
				scaleOverall += 10
				changeZoom()
		if Input.is_action_just_pressed("scrollDown"):
			if scaleOverall > 10:
				camera.zoom -= Vector2(0.1,0.1)
				scaleOverall -= 10
				changeZoom()
	
	$UILayer/ControlPanel/ZoomLabel.modulate.a = lerp($UILayer/ControlPanel/ZoomLabel.modulate.a,0.0,0.02)
	
func changeZoom():
	# HUD nodes on UILayer (CanvasLayer) don't need zoom compensation, but the
	# crosshair Lines node is in world space (it draws through the world origin)
	# and still needs to be scaled inversely so it stays a constant screen size.
	lines.scale = Vector2(1.0, 1.0) / camera.zoom

	$UILayer/ControlPanel/ZoomLabel.modulate.a = 6.0
	$UILayer/ControlPanel/ZoomLabel.text = "Zoom : " + str(scaleOverall) + "%"
	
	Global.pushUpdate("Set zoom to " + str(scaleOverall) + "%")
	onWindowSizeChange()
	
#When the user speaks!
func onSpeak():
	if origin.get_parent().position.y > -16:
		yVel = bounceSlider * -1

func updateWindowTransparency():
	var ndi_active = ndi_manager != null and ndi_manager.is_enabled()
	if ndi_active and !editMode:
		# NDI handles transparency via SubViewport — disable expensive window compositing
		get_viewport().transparent_bg = false
		get_window().transparent = false
		RenderingServer.set_default_clear_color(Global.backgroundColor if Global.backgroundColor.a != 0.0 else Color(0.3, 0.3, 0.3))
	else:
		get_viewport().transparent_bg = !editMode
		if Global.backgroundColor.a != 0.0:
			get_viewport().transparent_bg = false
		get_window().transparent = get_viewport().transparent_bg
		RenderingServer.set_default_clear_color(Global.backgroundColor)

#Swaps between edit mode and view mode
func swapMode():
	
	Global.heldSprite = null
	
	editMode = !editMode
	Global.pushUpdate("Toggled editing mode.")
	
	updateWindowTransparency()
	#processing
	editControls.set_process(editMode)
	controlPanel.set_process(!editMode)
	#visibility
	editControls.visible = editMode
	tutorial.visible = editMode
	controlPanel.visible = !editMode
	lines.visible = editMode
	spriteList.visible = editMode
	viewerArrows.visible = editMode
	if ndi_manager != null:
		ndi_manager.set_ruler_visible(editMode and ndi_manager.is_enabled())
	if _light_gizmo != null:
		_light_gizmo.queue_redraw()
	onWindowSizeChange()

func _next_z_index() -> int:
	var max_z = -1
	for s in get_tree().get_nodes_in_group("saved"):
		if s.z > max_z:
			max_z = s.z
	return max_z + 1

#Adds sprite object to scene
func add_image(path):
	UndoManager.save_state()

	var rand = RandomNumberGenerator.new()
	var id = rand.randi()

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
	var rand = RandomNumberGenerator.new()
	var id = rand.randi()

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

# Threaded sprite creation (post-PSD-import)
var _import_thread: Thread = null
var _import_layers: Array = []
var _import_canvas_size: Vector2 = Vector2.ZERO
var _import_results: Array = []
var _import_mutex: Mutex = null
var _import_completed: int = 0
var _import_normal_layers: Dictionary = {}
var _import_progress_dialog2: Node2D = null

# Threaded avatar JSON load (parallel PNG decode + polygon generation per sprite)
var _load_keys: Array = []
var _load_data_ref = null
var _load_results: Array = []

var _anim_parser = null        # GIFParser or APNGParser
var _anim_thread: Thread = null
var _anim_result = null
var _anim_progress_dialog: Node2D = null
var _anim_replace_mode: bool = false
var _anim_import_name: String = ""
var _anim_queue: Array = []

func _on_psd_dialog_file_selected(path):
	_psd_parser = PSDParser.new()
	_psd_result = null

	# Show progress bar
	_psd_progress_dialog = _create_psd_progress_dialog()
	add_child(_psd_progress_dialog)

	# Run parser in a thread
	_psd_thread = Thread.new()
	_psd_thread.start(func(): return _psd_parser.parse(path))

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
	_import_completed = 0
	_import_mutex = Mutex.new()

	# Show progress dialog for sprite creation phase
	_import_progress_dialog2 = _create_psd_progress_dialog()
	_import_progress_dialog2.get_node("StatusLabel").text = "Processing sprites..."
	add_child(_import_progress_dialog2)

	# Start coordinator thread that spawns per-layer workers
	_import_thread = Thread.new()
	_import_thread.start(_precompute_all_layers)

func _precompute_all_layers():
	var count = _import_layers.size()
	var threads: Array = []

	for i in range(count):
		var t = Thread.new()
		var layer = _import_layers[i]
		var idx = i
		t.start(func():
			var img = layer.image
			var pma = img.duplicate()
			pma.premultiply_alpha()
			var bitmap = BitMap.new()
			bitmap.create_from_image_alpha(img)
			var polygons = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, bitmap.get_size()), 4.0)
			_import_results[idx] = {
				"pma_image": pma,
				"polygons": polygons
			}
			_import_mutex.lock()
			_import_completed += 1
			_import_mutex.unlock()
		)
		threads.append(t)

	for t in threads:
		t.wait_to_finish()

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
	if _import_thread == null:
		return

	# Update progress
	var count = _import_layers.size()
	if count > 0 and _import_progress_dialog2 != null:
		_import_mutex.lock()
		var completed = _import_completed
		_import_mutex.unlock()
		_import_progress_dialog2.get_node("ProgressBar").value = float(completed) / count
		_import_progress_dialog2.get_node("StatusLabel").text = "Processing sprites... " + str(completed) + "/" + str(count)

	# Check if coordinator thread is done
	if !_import_thread.is_alive():
		_import_thread.wait_to_finish()
		_import_thread = null

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

		var rand = RandomNumberGenerator.new()
		var id = rand.randi()

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
	_import_mutex = null
	_import_normal_layers = {}

	_save_post_import_snapshot()

func _on_psd_import_cancelled():
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
	_anim_thread.start(func(): return _anim_parser.parse(path))

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

	var rand = RandomNumberGenerator.new()
	var id = rand.randi()

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
			var rand = RandomNumberGenerator.new()
			var id = rand.randi()
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
	# popup_file_dialog() is the FileDialog-specific show method that routes
	# through DisplayServer to the OS native picker when use_native_dialog=true.
	# Generic popup() / popup_centered() / setting .visible don't reliably
	# trigger the native path (see godotengine/godot#82531).
	saveDialog.popup_file_dialog()

func _on_load_button_pressed():
	loadDialog.popup_file_dialog()

#LOAD AVATAR
func _on_load_dialog_file_selected(path):
	UndoManager.save_state()
	var data = Saving.read_save(path)

	if data == null:
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

	# Build ordered key list (skip non-sprite metadata)
	_load_keys = []
	for _it in data:
		var _it_s = str(_it)
		if _it_s == "_light" or _it_s == "_eyeTrackingGloballyEnabled":
			continue
		_load_keys.append(_it)
	var _load_total = _load_keys.size()
	_load_data_ref = data
	_load_results = []
	_load_results.resize(_load_total)

	var _load_dialog: Node2D = null
	var _load_bar: ProgressBar = null
	if _load_total > 0:
		# Run PNG decode + premult + polygon generation in parallel across worker threads
		var group_id = WorkerThreadPool.add_group_task(_load_worker_decode, _load_total, -1, false, "Avatar load")
		var _load_start_ms = Time.get_ticks_msec()
		var _last_bar_ms = _load_start_ms
		# Only show the bar if decode is still running after 200 ms — fast loads skip it
		const BAR_SHOW_DELAY_MS = 200
		while !WorkerThreadPool.is_group_task_completed(group_id):
			await get_tree().process_frame
			var now = Time.get_ticks_msec()
			if _load_dialog == null and now - _load_start_ms >= BAR_SHOW_DELAY_MS:
				# _create_progress_dialog attaches the dialog to UILayer itself.
				_load_dialog = _create_progress_dialog("Loading avatar...")
				_load_bar = _load_dialog.get_node("ProgressBar")
			if _load_dialog != null and now - _last_bar_ms >= 100:
				_last_bar_ms = now
				var done = WorkerThreadPool.get_group_processed_element_count(group_id)
				_load_bar.value = float(done) / float(_load_total)
				_load_dialog.position = get_viewport().get_visible_rect().size * 0.5
		WorkerThreadPool.wait_for_group_task_completion(group_id)
		if _load_bar != null:
			_load_bar.value = 1.0

	# Spawn sprites synchronously now that decode/polygon work is prebuilt — this
	# loop is fast because each spriteObject._ready just adopts the prebuilt data
	for i in range(_load_total):
		var item = _load_keys[i]
		var sprite = spriteObject.instantiate()
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
				for _j in range(5):
					sprite.costumeLayers.append(1)
		if data[item].has("stretchAmount"):
			sprite.stretchAmount = data[item]["stretchAmount"]
		if data[item].has("ignoreBounce"):
			sprite.ignoreBounce = data[item]["ignoreBounce"]
		if data[item].has("staticElement"):
			sprite.staticElement = data[item]["staticElement"]
		if data[item].has("frames"):
			sprite.frames = data[item]["frames"]
		if data[item].has("animSpeed"):
			sprite.animSpeed = data[item]["animSpeed"]
		if data[item].has("clipped"):
			sprite.clipped = data[item]["clipped"]
		if data[item].has("toggle"):
			sprite.toggle = data[item]["toggle"]
		if data[item].has("eyeTrack"):
			sprite.eyeTrack = data[item]["eyeTrack"]
		if data[item].has("eyeTrackDistance"):
			sprite.eyeTrackDistance = data[item]["eyeTrackDistance"]
		if data[item].has("eyeTrackSpeed"):
			sprite.eyeTrackSpeed = data[item]["eyeTrackSpeed"]
		if data[item].has("eyeTrackInvert"):
			sprite.eyeTrackInvert = data[item]["eyeTrackInvert"]
		if data[item].has("eyeTrackMode"):
			sprite.eyeTrackMode = data[item]["eyeTrackMode"]
		if data[item].has("eyeTrackTargetId"):
			sprite.eyeTrackTargetId = data[item]["eyeTrackTargetId"]
		if data[item].has("ndiRefLayer"):
			sprite.ndiRefLayer = data[item]["ndiRefLayer"]
		if data[item].has("wiggleEnabled"): sprite.wiggleEnabled = data[item]["wiggleEnabled"]
		if data[item].has("wigglePath"): sprite.wigglePath = str_to_var(data[item]["wigglePath"])
		if data[item].has("wigglePathWidths"): sprite.wigglePathWidths = str_to_var(data[item]["wigglePathWidths"])
		if data[item].has("wiggleThickness"): sprite.wiggleThickness = data[item]["wiggleThickness"]
		if data[item].has("wiggleSegments"): sprite.wiggleSegments = data[item]["wiggleSegments"]
		if data[item].has("wiggleStiffness"): sprite.wiggleStiffness = data[item]["wiggleStiffness"]
		if data[item].has("wiggleDamping"): sprite.wiggleDamping = data[item]["wiggleDamping"]
		if data[item].has("wiggleWeight"): sprite.wiggleWeight = data[item]["wiggleWeight"]
		if data[item].has("wiggleMaxBend"): sprite.wiggleMaxBend = data[item]["wiggleMaxBend"]
		if data[item].has("wiggleBendFocus"): sprite.wiggleBendFocus = data[item]["wiggleBendFocus"]
		if data[item].has("wiggleShapeReturn"): sprite.wiggleShapeReturn = data[item]["wiggleShapeReturn"]
		if data[item].has("wiggleWagEnabled"): sprite.wiggleWagEnabled = data[item]["wiggleWagEnabled"]
		if data[item].has("wiggleWagAmount"): sprite.wiggleWagAmount = data[item]["wiggleWagAmount"]
		if data[item].has("wiggleWagSpeed"): sprite.wiggleWagSpeed = data[item]["wiggleWagSpeed"]
		if data[item].has("wiggleReactivity"): sprite.wiggleReactivity = data[item]["wiggleReactivity"]
		if data[item].has("wiggleMotionIntensity"): sprite.wiggleMotionIntensity = data[item]["wiggleMotionIntensity"]
		if data[item].has("wiggleChildrenFollow"): sprite.wiggleChildrenFollow = data[item]["wiggleChildrenFollow"]
		if data[item].has("normalPath"):
			sprite.normalPath = data[item]["normalPath"]

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
		sprite.position = str_to_var(data[item]["pos"])
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
	for spr in get_tree().get_nodes_in_group("saved"):
		if spr.parentId != null:
			var parents = get_tree().get_nodes_in_group(str(spr.parentId))
			if parents.size() > 0:
				spr.get_parent().remove_child(spr)
				parents[0].sprite.add_child(spr)
				spr.parentSprite = parents[0]
				spr.set_owner(parents[0].sprite)
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

	changeCostume(1)
	# The session-recovery file is ephemeral — never promote it to lastAvatar,
	# otherwise startup auto-load and Reset would pull from it instead of the
	# user's actual saved avatar.
	if path != SESSION_SAVE_PATH:
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

func _create_save_progress_dialog() -> Node2D:
	return _create_progress_dialog("Saving avatar...")

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

func takeScreenshot():
	if _screenshot_image != null:
		return  # Previous capture pending save

	# If NDI is enabled, capture the NDI crop view directly
	if ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_viewport != null:
		_screenshot_image = ndi_manager.ndi_viewport.get_texture().get_image()
	else:
		var vp_size = get_viewport().get_visible_rect().size

		var screenshot_vp = SubViewport.new()
		screenshot_vp.transparent_bg = true
		screenshot_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		screenshot_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		screenshot_vp.size = Vector2i(vp_size)
		screenshot_vp.world_2d = get_viewport().world_2d
		screenshot_vp.canvas_cull_mask = 1  # Sprites only, no UI (layer 2)
		screenshot_vp.gui_disable_input = true
		screenshot_vp.handle_input_locally = false
		add_child(screenshot_vp)

		var screenshot_cam = Camera2D.new()
		screenshot_cam.position = camera.position
		screenshot_cam.zoom = camera.zoom
		screenshot_vp.add_child(screenshot_cam)
		screenshot_cam.make_current()

		await RenderingServer.frame_post_draw

		_screenshot_image = screenshot_vp.get_texture().get_image()
		screenshot_vp.queue_free()

	if _screenshot_dialog == null:
		_create_screenshot_dialog()

	var timestamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	_screenshot_dialog.current_file = "screenshot_" + timestamp + ".png"
	_screenshot_dialog.popup_centered(Vector2i(600, 400))

func _create_save_load_dialogs():
	# OS.get_user_data_dir() resolves the absolute filesystem path that
	# `user://` maps to — the native picker needs a real path, not Godot's
	# virtual prefix. After the first navigation FileDialog tracks the user's
	# last-visited current_dir, so subsequent opens land where they left off.
	var user_dir = OS.get_user_data_dir()

	saveDialog = FileDialog.new()
	saveDialog.title = "Save Avatar"
	saveDialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	saveDialog.access = FileDialog.ACCESS_FILESYSTEM
	saveDialog.filters = PackedStringArray(["*.save;PNGTuberPlus Avatar"])
	saveDialog.use_native_dialog = true
	saveDialog.current_dir = user_dir
	saveDialog.file_selected.connect(_on_save_dialog_file_selected)
	add_child(saveDialog)

	loadDialog = FileDialog.new()
	loadDialog.title = "Load Avatar"
	loadDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	loadDialog.access = FileDialog.ACCESS_FILESYSTEM
	loadDialog.filters = PackedStringArray(["*.save;PNGTuberPlus Avatar"])
	loadDialog.use_native_dialog = true
	loadDialog.current_dir = user_dir
	loadDialog.file_selected.connect(_on_load_dialog_file_selected)
	add_child(loadDialog)

func _create_screenshot_dialog():
	_screenshot_dialog = FileDialog.new()
	_screenshot_dialog.title = "Save Screenshot"
	_screenshot_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_screenshot_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_screenshot_dialog.filters = PackedStringArray(["*.png;PNG Image"])
	_screenshot_dialog.use_native_dialog = true
	_screenshot_dialog.file_selected.connect(_on_screenshot_dialog_file_selected)
	add_child(_screenshot_dialog)

func _on_screenshot_dialog_file_selected(path: String):
	if _screenshot_image == null:
		return
	if !path.ends_with(".png"):
		path += ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err = _screenshot_image.save_png(path)
	if err == OK:
		Global.pushUpdate("Screenshot saved: " + path.get_file())
	else:
		Global.pushUpdate("Failed to save screenshot.")
	_screenshot_image = null

# --- Screenshot press/release (hold-to-record) ---

func onScreenshotPressed():
	pass  # Timing tracked in global.gd; recording starts from _process after 1s threshold

func onScreenshotReleased():
	if _recording:
		_stopRecording()
	elif Global._screenshot_press_time > 0:
		# Tap — take screenshot (existing behavior)
		takeScreenshot()

# --- Recording ---

func _process_recording(delta):
	# Start recording after 1s hold
	if !_recording and !_encoding and Global._screenshot_key_held and Global._screenshot_press_time > 0:
		if Time.get_ticks_msec() - Global._screenshot_press_time >= 1000:
			_startRecording()

	# Capture frames at configured FPS
	if _recording:
		_recording_timer += delta
		var interval = 1.0 / float(Saving.settings.get("recordingFPS", 30))
		while _recording_timer >= interval:
			_captureRecordingFrame()
			_recording_timer -= interval

	# Poll encode progress and check thread completion
	if _encoding:
		_poll_encode_progress()
		if _encode_thread != null and !_encode_thread.is_alive():
			_encode_thread.wait_to_finish()
			_encode_thread = null
			_encoding = false
			if _encode_progress_dialog != null:
				_encode_progress_dialog.queue_free()
				_encode_progress_dialog = null
			_cleanup_recording_temp()

func _startRecording():
	if _recording or _encoding:
		return
	if !_is_ffmpeg_available():
		Global.pushUpdate("FFmpeg not found. Install FFmpeg to record video.")
		return

	_recording = true
	_recording_timer = 0.0
	_recording_frame_count = 0
	var use_ndi = ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_viewport != null
	if use_ndi:
		_recording_size = ndi_manager.ndi_viewport.size
	else:
		_recording_size = Vector2i(get_viewport().get_visible_rect().size)

	# Temp file for raw RGBA frames
	var temp_dir = OS.get_cache_dir() + "/pngtuber_recording"
	DirAccess.make_dir_recursive_absolute(temp_dir)
	_recording_temp_path = temp_dir + "/frames.raw"
	_recording_file = FileAccess.open(_recording_temp_path, FileAccess.WRITE)

	# SubViewport (same pattern as NDI)
	_recording_vp = SubViewport.new()
	_recording_vp.transparent_bg = true
	_recording_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_recording_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_recording_vp.size = _recording_size
	_recording_vp.world_2d = get_viewport().world_2d
	_recording_vp.canvas_cull_mask = 1
	_recording_vp.gui_disable_input = true
	_recording_vp.handle_input_locally = false
	add_child(_recording_vp)

	_recording_cam = Camera2D.new()
	_recording_vp.add_child(_recording_cam)
	if use_ndi:
		_recording_cam.position = ndi_manager.ndi_camera.position
		_recording_cam.zoom = ndi_manager.ndi_camera.zoom
	else:
		_recording_cam.position = camera.position
		_recording_cam.zoom = camera.zoom
	_recording_cam.make_current()

	Global.pushUpdate("Recording...")

func _stopRecording():
	if !_recording:
		return
	_recording = false

	if _recording_file != null:
		_recording_file.close()
		_recording_file = null

	if _recording_vp != null:
		_recording_vp.queue_free()
		_recording_vp = null
		_recording_cam = null

	if _recording_frame_count == 0:
		Global.pushUpdate("No frames captured.")
		_cleanup_recording_temp()
		return

	Global.pushUpdate("Encoding... (" + str(_recording_frame_count) + " frames)")

	if _record_dialog == null:
		_create_record_dialog()

	var fmt = Saving.settings.get("recordingFormat", "webm")
	var ext_map = {"webm": ".webm", "apng": ".apng", "gif": ".gif"}
	var filter_map = {
		"webm": "*.webm;WebM Video",
		"apng": "*.apng;Animated PNG",
		"gif": "*.gif;GIF Image"
	}
	var ext = ext_map.get(fmt, ".webm")
	_record_dialog.filters = PackedStringArray([filter_map.get(fmt, "*.webm;WebM Video")])

	var timestamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	_record_dialog.current_file = "recording_" + timestamp + ext
	_record_dialog.popup_centered(Vector2i(600, 400))

func _captureRecordingFrame():
	if _recording_vp == null or _recording_file == null:
		return
	# Sync camera — use NDI crop view when active, otherwise main camera
	if ndi_manager != null and ndi_manager.is_enabled() and ndi_manager.ndi_camera != null:
		_recording_cam.position = ndi_manager.ndi_camera.position
		_recording_cam.zoom = ndi_manager.ndi_camera.zoom
	else:
		_recording_cam.position = camera.position
		_recording_cam.zoom = camera.zoom
	var img = _recording_vp.get_texture().get_image()
	if img != null:
		_recording_file.store_buffer(img.get_data())
		_recording_frame_count += 1

func _is_ffmpeg_available() -> bool:
	return _find_ffmpeg() != ""

func _find_ffmpeg() -> String:
	# Try common paths (GUI apps may not inherit full PATH)
	var common_paths = []
	if OS.get_name() == "Windows":
		var program_files = OS.get_environment("ProgramFiles")
		var localappdata = OS.get_environment("LOCALAPPDATA")
		common_paths = [
			OS.get_executable_path().get_base_dir() + "/ffmpeg.exe",
			program_files + "/ffmpeg/bin/ffmpeg.exe",
			localappdata + "/Microsoft/WinGet/Links/ffmpeg.exe",
			"C:/ffmpeg/bin/ffmpeg.exe",
		]
	else:
		common_paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
	for path in common_paths:
		if FileAccess.file_exists(path):
			return path
	# Fallback to PATH
	var output = []
	var cmd = "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(cmd, ["ffmpeg"], output) == 0 and output.size() > 0:
		return output[0].strip_edges()
	return ""

func _create_record_dialog():
	_record_dialog = FileDialog.new()
	_record_dialog.title = "Save Recording"
	_record_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_record_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_record_dialog.filters = PackedStringArray(["*.webm;WebM Video"])
	_record_dialog.use_native_dialog = true
	_record_dialog.file_selected.connect(_on_record_dialog_file_selected)
	_record_dialog.canceled.connect(_on_record_dialog_canceled)
	add_child(_record_dialog)

func _on_record_dialog_file_selected(path: String):
	var fmt = Saving.settings.get("recordingFormat", "webm")
	var ext_map = {"webm": ".webm", "apng": ".apng", "gif": ".gif"}
	var ext = ext_map.get(fmt, ".webm")
	if !path.ends_with(ext):
		path += ext
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	_encoding = true
	_encode_progress = 0.0
	_encode_total_frames = _recording_frame_count
	var raw_path = _recording_temp_path
	var size = _recording_size

	# Progress file for FFmpeg to write stats into
	var temp_dir = OS.get_cache_dir() + "/pngtuber_recording"
	_encode_progress_path = temp_dir + "/ffmpeg_progress.log"

	# Show progress dialog
	_encode_progress_dialog = _create_encode_progress_dialog()
	add_child(_encode_progress_dialog)

	_encode_thread = Thread.new()
	var fps = int(Saving.settings.get("recordingFPS", 30))
	_encode_thread.start(_encode_worker.bind(raw_path, size, path, _encode_progress_path, fps))

func _create_encode_progress_dialog() -> Node2D:
	var dialog = Node2D.new()
	dialog.z_index = 4095
	dialog.visibility_layer = 2
	dialog.position = camera.position

	var bg = ColorRect.new()
	bg.position = Vector2(-160, -50)
	bg.size = Vector2(320, 100)
	bg.color = Color(0.15, 0.15, 0.15, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(bg)

	var label = Label.new()
	label.name = "StatusLabel"
	label.position = Vector2(-150, -40)
	label.size = Vector2(300, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text = "Encoding video..."
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	return dialog

func _poll_encode_progress():
	if _encode_progress_dialog == null:
		return
	# Read FFmpeg progress file to extract current frame
	if _encode_progress_path != "" and FileAccess.file_exists(_encode_progress_path):
		var f = FileAccess.open(_encode_progress_path, FileAccess.READ)
		if f != null:
			var content = f.get_as_text()
			f.close()
			# Find last "frame=" line in the progress output
			var lines = content.split("\n")
			for i in range(lines.size() - 1, -1, -1):
				if lines[i].begins_with("frame="):
					var frame_str = lines[i].substr(6).strip_edges()
					if frame_str.is_valid_int() and _encode_total_frames > 0:
						_encode_progress = clampf(float(frame_str.to_int()) / float(_encode_total_frames), 0.0, 1.0)
					break
	_encode_progress_dialog.get_node("ProgressBar").value = _encode_progress
	_encode_progress_dialog.position = camera.position

func _encode_worker(raw_path: String, size: Vector2i, output_path: String, progress_path: String, fps: int = 30):
	var ffmpeg = _find_ffmpeg()
	if ffmpeg == "":
		call_deferred("_on_encode_done", false)
		return

	var base_args = [
		"-y",
		"-f", "rawvideo",
		"-pix_fmt", "rgba",
		"-s", str(size.x) + "x" + str(size.y),
		"-r", str(fps),
		"-i", raw_path,
	]

	var fmt_args = []
	if output_path.ends_with(".apng"):
		fmt_args = [
			"-c:v", "apng",
			"-pix_fmt", "rgba",
			"-plays", "0",
		]
	elif output_path.ends_with(".gif"):
		var filtergraph = "split[s0][s1];[s0]palettegen=reserve_transparent=1[p];[s1][p]paletteuse=alpha_threshold=128"
		fmt_args = [
			"-filter_complex", filtergraph,
			"-loop", "0",
		]
	else:
		# WebM VP9 (default)
		fmt_args = [
			"-c:v", "libvpx-vp9",
			"-pix_fmt", "yuva420p",
			"-auto-alt-ref", "0",
			"-crf", "30",
			"-b:v", "0",
		]

	var args = base_args + fmt_args + ["-progress", progress_path, output_path]

	var output = []
	var exit_code = OS.execute(ffmpeg, args, output)
	call_deferred("_on_encode_done", exit_code == 0)

func _on_encode_done(success: bool):
	if success:
		Global.pushUpdate("Recording saved!")
	else:
		Global.pushUpdate("FFmpeg encoding failed.")

func _on_record_dialog_canceled():
	_cleanup_recording_temp()
	Global.pushUpdate("Recording discarded.")

func _cleanup_recording_temp():
	if _recording_temp_path != "" and FileAccess.file_exists(_recording_temp_path):
		DirAccess.remove_absolute(_recording_temp_path)
	if _encode_progress_path != "" and FileAccess.file_exists(_encode_progress_path):
		DirAccess.remove_absolute(_encode_progress_path)
	_recording_temp_path = ""
	_encode_progress_path = ""
	_recording_frame_count = 0

func _process_save_thread(_delta):
	if _save_thread == null or _save_progress_dialog == null:
		return
	_save_progress_dialog.get_node("ProgressBar").value = _save_progress
	# Recenter on viewport — handles window resize while saving.
	_save_progress_dialog.position = get_viewport().get_visible_rect().size * 0.5

# Build the same Dictionary structure manual save and session auto-save both
# write out. Image references go in `_image_ref` / `_normal_image_ref` so the
# background worker can base64-encode them off the main thread (see
# `_save_worker` and `_session_save_worker`).
func _build_avatar_save_data() -> Dictionary:
	var data = {}
	var nodes = get_tree().get_nodes_in_group("saved")
	var id = 0
	for child in nodes:
		if child.type == "sprite":
			data[id] = {
				"type": "sprite",
				"path": child.path,
				"_image_ref": child.imageData,
				"identification": child.id,
				"parentId": child.parentId,
				"pos": var_to_str(child.position),
				"offset": var_to_str(child.offset),
				"zindex": child.z,
				"drag": child.dragSpeed,
				"xFrq": child.xFrq,
				"xAmp": child.xAmp,
				"yFrq": child.yFrq,
				"yAmp": child.yAmp,
				"rotDrag": child.rdragStr,
				"showTalk": child.showOnTalk,
				"showBlink": child.showOnBlink,
				"rLimitMin": child.rLimitMin,
				"rLimitMax": child.rLimitMax,
				"costumeLayers": var_to_str(child.costumeLayers),
				"stretchAmount": child.stretchAmount,
				"ignoreBounce": child.ignoreBounce,
				"staticElement": child.staticElement,
				"frames": child.frames,
				"animSpeed": child.animSpeed,
				"clipped": child.clipped,
				"toggle": child.toggle,
				"eyeTrack": child.eyeTrack,
				"eyeTrackDistance": child.eyeTrackDistance,
				"eyeTrackSpeed": child.eyeTrackSpeed,
				"eyeTrackInvert": child.eyeTrackInvert,
				"eyeTrackMode": child.eyeTrackMode,
				"eyeTrackTargetId": child.eyeTrackTargetId,
				"wiggleEnabled": child.wiggleEnabled,
				"wigglePath": var_to_str(child.wigglePath),
				"wigglePathWidths": var_to_str(child.wigglePathWidths),
				"wiggleThickness": child.wiggleThickness,
				"wiggleSegments": child.wiggleSegments,
				"wiggleStiffness": child.wiggleStiffness,
				"wiggleDamping": child.wiggleDamping,
				"wiggleWeight": child.wiggleWeight,
				"wiggleMaxBend": child.wiggleMaxBend,
				"wiggleBendFocus": child.wiggleBendFocus,
				"wiggleShapeReturn": child.wiggleShapeReturn,
				"wiggleWagEnabled": child.wiggleWagEnabled,
				"wiggleWagAmount": child.wiggleWagAmount,
				"wiggleWagSpeed": child.wiggleWagSpeed,
				"wiggleReactivity": child.wiggleReactivity,
				"wiggleMotionIntensity": child.wiggleMotionIntensity,
				"wiggleChildrenFollow": child.wiggleChildrenFollow,
				"ndiRefLayer": child.ndiRefLayer,
				"normalPath": child.normalPath,
			}
			if child.normalImageData != null:
				data[id]["_normal_image_ref"] = child.normalImageData
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
	return data

#SAVE AVATAR
func _on_save_dialog_file_selected(path):
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null
	# Wait for any in-flight session save too, so its worker doesn't race
	# against the manual save by holding references to the same image data.
	if _session_thread != null:
		_session_thread.wait_to_finish()
		_session_thread = null

	var data = _build_avatar_save_data()

	Saving.settings["lastAvatar"] = path
	# Persist immediately — _exit_tree isn't reliable across all shutdown paths
	Saving.write_settings(Saving.settingsPath)

	_save_progress = 0.0
	# _create_save_progress_dialog attaches the dialog to UILayer itself.
	_save_progress_dialog = _create_save_progress_dialog()

	_save_thread = Thread.new()
	_save_thread.start(_save_worker.bind(data, path))

func _save_worker(data: Dictionary, path: String):
	var total = data.size()
	var done = 0
	for id in data:
		# Some keys (e.g. "_eyeTrackingGloballyEnabled") hold plain values
		# rather than per-sprite dicts; skip them so .has() doesn't fail.
		var entry = data[id]
		if entry is Dictionary:
			if entry.has("_image_ref"):
				var img: Image = entry["_image_ref"]
				entry["imageData"] = Marshalls.raw_to_base64(img.save_png_to_buffer())
				entry.erase("_image_ref")
			if entry.has("_normal_image_ref"):
				var nrml_img: Image = entry["_normal_image_ref"]
				entry["normalImageData"] = Marshalls.raw_to_base64(nrml_img.save_png_to_buffer())
				entry.erase("_normal_image_ref")
		done += 1
		_save_progress = float(done) / float(total)
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_line(JSON.stringify(data))
	file.close()
	call_deferred("_on_save_finished", path, data)

func _on_save_finished(path: String, data: Dictionary):
	Saving.data = data
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null
	if _save_progress_dialog != null:
		_save_progress_dialog.queue_free()
		_save_progress_dialog = null
	Global.pushUpdate("Save complete: " + path.get_file())
	_show_save_confirmation(path.get_file())
	# The user's work is now persisted in their chosen save file; the
	# session-recovery copy is redundant and would otherwise trigger a
	# spurious "restore?" prompt on the next launch.
	_discard_session_file()
	_session_dirty = false
	_session_timer = 0.0

# --- Session auto-save -------------------------------------------------------

# Signal callback for UndoManager.state_saved. Every edit that produces an
# undoable snapshot marks the rig dirty for session purposes; the timer in
# _process_session_save() decides when to flush.
func _on_undo_state_saved():
	_session_dirty = true

# Per-frame tick: count up only while we have an avatar loaded, the rig is
# dirty, and no save (manual or session) is in flight. When the interval
# elapses, kick off a background encode + write to SESSION_SAVE_PATH.
func _process_session_save(delta):
	# Reap a finished thread first so we can start a new tick.
	if _session_thread != null and !_session_thread.is_alive():
		_session_thread.wait_to_finish()
		_session_thread = null
	if _save_thread != null or _session_thread != null:
		return
	if !saveLoaded or !_session_dirty:
		return
	_session_timer += delta
	if _session_timer < SESSION_AUTO_SAVE_INTERVAL:
		return
	_session_timer = 0.0
	_session_dirty = false  # re-armed by the next undo state save
	var data = _build_avatar_save_data()
	_session_thread = Thread.new()
	_session_thread.start(_session_save_worker.bind(data))

# Mirrors _save_worker but writes silently to SESSION_SAVE_PATH and does not
# touch the progress UI or surface a confirmation.
func _session_save_worker(data: Dictionary):
	for id in data:
		var entry = data[id]
		if entry is Dictionary:
			if entry.has("_image_ref"):
				var img: Image = entry["_image_ref"]
				entry["imageData"] = Marshalls.raw_to_base64(img.save_png_to_buffer())
				entry.erase("_image_ref")
			if entry.has("_normal_image_ref"):
				var nrml_img: Image = entry["_normal_image_ref"]
				entry["normalImageData"] = Marshalls.raw_to_base64(nrml_img.save_png_to_buffer())
				entry.erase("_normal_image_ref")
	var file = FileAccess.open(SESSION_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Session auto-save failed to open " + SESSION_SAVE_PATH)
		return
	file.store_line(JSON.stringify(data))
	file.close()

func _discard_session_file():
	if !FileAccess.file_exists(SESSION_SAVE_PATH):
		return
	var dir = DirAccess.open("user://")
	if dir != null:
		dir.remove(SESSION_SAVE_PATH.get_file())

# True if a session file exists and is newer than the user's lastAvatar save
# (or the lastAvatar is missing entirely). Used at startup to decide whether
# to prompt for recovery instead of loading the lastAvatar.
func _has_recoverable_session(last_avatar_path: String) -> bool:
	if !FileAccess.file_exists(SESSION_SAVE_PATH):
		return false
	if last_avatar_path == "" or !FileAccess.file_exists(last_avatar_path):
		return true
	var session_mod = FileAccess.get_modified_time(SESSION_SAVE_PATH)
	var avatar_mod = FileAccess.get_modified_time(last_avatar_path)
	return session_mod > avatar_mod

# Modal recovery prompt on UILayer, styled like the save-progress dialog: a
# full-viewport dimmer + click-blocker behind a centered body with a label
# and two buttons. Restore loads the session file; Discard deletes it and
# loads the lastAvatar (if any) instead.
func _show_session_recovery_dialog(last_avatar_path: String):
	var dialog = Node2D.new()
	dialog.z_index = 100
	dialog.position = get_viewport().get_visible_rect().size * 0.5

	var blocker = ColorRect.new()
	blocker.position = Vector2(-5000, -5000)
	blocker.size = Vector2(10000, 10000)
	blocker.color = Color(0, 0, 0, 0.35)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(blocker)

	var bg = ColorRect.new()
	bg.position = Vector2(-220, -75)
	bg.size = Vector2(440, 150)
	bg.color = Color(0.13, 0.13, 0.15, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(bg)

	var title = Label.new()
	title.position = Vector2(-210, -62)
	title.size = Vector2(420, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = "Recover unsaved session?"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(title)

	var body = Label.new()
	body.position = Vector2(-210, -35)
	body.size = Vector2(420, 60)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.text = "A more recent in-progress session was found. Restore it, or discard and load your last saved avatar?"
	body.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(body)

	var restore_btn = Button.new()
	restore_btn.text = "Restore"
	restore_btn.position = Vector2(-180, 38)
	restore_btn.size = Vector2(160, 28)
	restore_btn.pressed.connect(func(): _on_session_recovery_choice(true, last_avatar_path))
	dialog.add_child(restore_btn)

	var discard_btn = Button.new()
	discard_btn.text = "Discard"
	discard_btn.position = Vector2(20, 38)
	discard_btn.size = Vector2(160, 28)
	discard_btn.pressed.connect(func(): _on_session_recovery_choice(false, last_avatar_path))
	dialog.add_child(discard_btn)

	$UILayer.add_child(dialog)
	_session_recovery_dialog = dialog

func _on_session_recovery_choice(restore: bool, last_avatar_path: String):
	if _session_recovery_dialog != null and is_instance_valid(_session_recovery_dialog):
		_session_recovery_dialog.queue_free()
		_session_recovery_dialog = null
	if restore:
		_on_load_dialog_file_selected(SESSION_SAVE_PATH)
		# Keep the session file in place: the user's next manual save will
		# clear it, and crashing again before that should still recover.
	else:
		_discard_session_file()
		if last_avatar_path != "" and FileAccess.file_exists(last_avatar_path):
			_on_load_dialog_file_selected(last_avatar_path)

# Visible save-success toast on UILayer that lingers ~2 seconds, fades out
# over half a second, and dismisses on click. More prominent than the
# transient pushUpdate notification.
func _show_save_confirmation(filename: String):
	var dialog = Node2D.new()
	dialog.z_index = 100
	dialog.position = get_viewport().get_visible_rect().size * 0.5

	var bg = ColorRect.new()
	bg.position = Vector2(-200, -32)
	bg.size = Vector2(400, 64)
	bg.color = Color(0.13, 0.16, 0.13, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			dialog.queue_free()
	)
	dialog.add_child(bg)

	var label = Label.new()
	label.position = Vector2(-190, -22)
	label.size = Vector2(380, 44)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "✓ Saved: " + filename
	label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.75))
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(label)

	$UILayer.add_child(dialog)

	# Hold 2s, fade out 0.5s, free. Tween is bound to the dialog so it
	# auto-dies if the user clicks-to-dismiss earlier.
	var tween = dialog.create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(dialog, "modulate:a", 0.0, 0.5)
	tween.tween_callback(dialog.queue_free)

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
	_psd_replace_mode = true
	_psd_parser = PSDParser.new()
	_psd_result = null

	_psd_progress_dialog = _create_psd_progress_dialog()
	add_child(_psd_progress_dialog)

	_psd_thread = Thread.new()
	_psd_thread.start(func(): return _psd_parser.parse(path))

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
	var rand = RandomNumberGenerator.new()
	var id = rand.randi()
	
	var sprite = spriteObject.instantiate()
	sprite.path = Global.heldSprite.path
	sprite.loadedImage = Global.heldSprite.imageData.duplicate()
	sprite.id = id
	sprite.dragSpeed = Global.heldSprite.dragSpeed
	sprite.showOnTalk = Global.heldSprite.showOnTalk
	sprite.showOnBlink = Global.heldSprite.showOnBlink
	sprite.z = Global.heldSprite.z
	
	sprite.xFrq = Global.heldSprite.xFrq
	sprite.xAmp = Global.heldSprite.xAmp
	sprite.yFrq = Global.heldSprite.yFrq
	sprite.yAmp = Global.heldSprite.yAmp
	
	sprite.rdragStr = Global.heldSprite.rdragStr
	
	sprite.offset = Global.heldSprite.offset
	
	sprite.rLimitMin = Global.heldSprite.rLimitMin
	sprite.rLimitMax = Global.heldSprite.rLimitMax
	
	sprite.frames = Global.heldSprite.frames
	sprite.animSpeed = Global.heldSprite.animSpeed
	
	sprite.costumeLayers = Global.heldSprite.costumeLayers.duplicate()

	sprite.eyeTrack = Global.heldSprite.eyeTrack
	sprite.eyeTrackDistance = Global.heldSprite.eyeTrackDistance
	sprite.eyeTrackSpeed = Global.heldSprite.eyeTrackSpeed
	sprite.eyeTrackInvert = Global.heldSprite.eyeTrackInvert
	sprite.eyeTrackMode = Global.heldSprite.eyeTrackMode
	sprite.eyeTrackTargetId = Global.heldSprite.eyeTrackTargetId

	sprite.wiggleEnabled = Global.heldSprite.wiggleEnabled
	sprite.wigglePath = Global.heldSprite.wigglePath.duplicate()
	sprite.wigglePathWidths = Global.heldSprite.wigglePathWidths.duplicate()
	sprite.wiggleThickness = Global.heldSprite.wiggleThickness
	sprite.wiggleSegments = Global.heldSprite.wiggleSegments
	sprite.wiggleStiffness = Global.heldSprite.wiggleStiffness
	sprite.wiggleDamping = Global.heldSprite.wiggleDamping
	sprite.wiggleWeight = Global.heldSprite.wiggleWeight
	sprite.wiggleMaxBend = Global.heldSprite.wiggleMaxBend
	sprite.wiggleBendFocus = Global.heldSprite.wiggleBendFocus
	sprite.wiggleShapeReturn = Global.heldSprite.wiggleShapeReturn
	sprite.wiggleWagEnabled = Global.heldSprite.wiggleWagEnabled
	sprite.wiggleWagAmount = Global.heldSprite.wiggleWagAmount
	sprite.wiggleWagSpeed = Global.heldSprite.wiggleWagSpeed
	sprite.wiggleReactivity = Global.heldSprite.wiggleReactivity
	sprite.wiggleMotionIntensity = Global.heldSprite.wiggleMotionIntensity
	sprite.wiggleChildrenFollow = Global.heldSprite.wiggleChildrenFollow

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
		if sprite.costumeLayers[newCostume-1] == 1:
			sprite.visible = true
			sprite.changeCollision(true)
		else:
			sprite.visible = false
			sprite.changeCollision(false)
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
