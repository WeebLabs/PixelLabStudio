extends Node2D

const ValueCodec = preload("res://autoload/persistence/value_codec.gd")
const CaptureControllerScene = preload("res://main_scenes/controllers/capture_controller.gd")
const ViewportControllerScene = preload("res://main_scenes/controllers/viewport_controller.gd")
const SaveControllerScene = preload("res://main_scenes/controllers/save_controller.gd")
const AvatarControllerScene = preload("res://main_scenes/controllers/avatar_controller.gd")
const ImportControllerScene = preload("res://main_scenes/controllers/import_controller.gd")
const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

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

# The viewer control panel owns the bar popups; main only borrows the settings
# menu for its startup values and the costume-hotkey capture.
@onready var settingsMenu = controlPanel.settings_menu

@onready var pushUpdates = $UILayer/PushUpdates

@onready var shadow = $shadowSprite

var ndi_manager: Node = null

var _light_gizmo: Node2D = null
var _background_input_capture: Node = null

var capture_controller: CaptureController = null
var viewport_controller: ViewportController = null
var save_controller: AvatarSaveController = null
var avatar_controller: AvatarController = null
var import_controller: ImportController = null


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

#background input capture
signal emptiedCapture
signal pressedKey
var costumeKeys = ["1","2","3","4","5","6","7","8","9","0"]
signal spriteVisToggles(keysPressed:Array)
signal visibility_binding_armed


func _exit_tree() -> void:
	_shutdown_import_workers()
	Global.detach_main(self)

func _shutdown_import_workers() -> void:
	if import_controller != null:
		import_controller.shutdown()
	if avatar_controller != null:
		avatar_controller.shutdown()

func _ready():
	Global.attach_main(self)
	_initialize_background_input_capture()
	Global.attach_failure_overlay($Failed)
	capture_controller = CaptureControllerScene.new()
	capture_controller.name = "CaptureController"
	add_child(capture_controller)
	capture_controller.setup(self, Global, Saving)
	viewport_controller = ViewportControllerScene.new()
	viewport_controller.setup(self, Global, Saving)
	avatar_controller = AvatarControllerScene.new()
	avatar_controller.name = "AvatarController"
	add_child(avatar_controller)
	avatar_controller.setup(self, Global, Saving, UndoManager, spriteObject)
	import_controller = ImportControllerScene.new()
	import_controller.name = "ImportController"
	add_child(import_controller)
	import_controller.setup(self, Global, UndoManager, avatar_controller, spriteObject)
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

	ElgatoStreamDeck.on_key_down.connect(changeCostumeStreamDeck)

	if not Saving.is_isolated_session():
		save_controller.startup_restore()
	Saving.settings["newUser"] = false

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

func _initialize_background_input_capture() -> void:
	if not ClassDB.class_exists("BackgroundInputCapture"):
		push_warning("Global background hotkeys are unavailable because the native input extension is not installed.")
		return
	_background_input_capture = ClassDB.instantiate("BackgroundInputCapture") as Node
	if _background_input_capture == null or not _background_input_capture.has_signal("bg_key_pressed"):
		push_warning("The native background-input extension could not be initialized.")
		_background_input_capture = null
		return
	_background_input_capture.name = "BackgroundInputCapture"
	add_child(_background_input_capture)
	_background_input_capture.connect("bg_key_pressed", bgInputSprite)
	_background_input_capture.connect("bg_key_pressed", _on_background_input_capture_bg_key_pressed)

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

func _init_ndi():
	var NDIManagerScript = load("res://ndi/ndi_output_manager.gd")
	ndi_manager = Node.new()
	ndi_manager.set_script(NDIManagerScript)
	ndi_manager.name = "NDIManager"
	add_child(ndi_manager)

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
	
	if Input.is_action_just_pressed("openFolder") and not Global.is_text_entry_active():
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	
	moveSpriteMenu(delta)
	
	fileSystemOpen = isFileSystemOpen()

	import_controller.process_frame(delta)
	save_controller.process_frame(delta)
	viewport_controller.process_frame()

func _unhandled_input(event):
	viewport_controller.handle_unhandled_input(event)
	

func isFileSystemOpen():
	if save_controller != null and save_controller.is_dialog_open():
		Global.clear_selection()
		return true
	if psdImportDialog.visible:
		Global.clear_selection()
		return true
	if replaceReviewDialog.visible:
		return true
	if import_controller != null and import_controller.is_import_dialog_open():
		Global.clear_selection()
		return true
	if import_controller != null and import_controller.is_replace_dialog_open():
		return true
	# The single-PNG confirmation names one layer and replaces whatever is held
	# when it is answered, so canvas selection has to stop while it is up. Like
	# the review dialog it must NOT clear heldSprite: that is its target.
	if import_controller != null and import_controller.has_single_replace_dialog():
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
				# Come back concealed rather than mid-reveal at the last cursor position.
				controlPanel.menu_bar.snap_hidden()
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
	return avatar_controller.next_z_index()


func _next_sprite_id() -> int:
	return avatar_controller.next_sprite_id()

#Adds sprite object to scene
func add_image(path):
	avatar_controller.add_image(path)
	
func add_image_from_data(img: Image, layer_name: String, canvas_position: Vector2):
	return avatar_controller.add_image_from_data(img, layer_name, canvas_position)

# Scene-signal compatibility facades; ImportController owns worker/dialog state.
func _on_psd_dialog_file_selected(path):
	import_controller.import_psd_file(path)


func _on_psd_import_confirmed(selected_layers: Array, canvas_size: Vector2, normal_layers: Dictionary = {}):
	import_controller.apply_psd_selection(selected_layers, canvas_size, normal_layers)


func _on_psd_import_cancelled():
	import_controller.cancel_psd_import()


func _on_import_button_pressed():
	import_controller.show_import_dialog()

func _on_save_button_pressed():
	save_controller.show_save_dialog()

func _on_load_button_pressed():
	save_controller.show_load_dialog()

# Avatar loading remains scene-signal compatible while the controller owns
# validation, worker state, transactional assembly, and post-load policy.
func _on_load_dialog_file_selected(path):
	return await avatar_controller.load_avatar(path)

# The one progress dialog: save, load, PSD/APNG import, video encoding. Layout,
# palette, centring and the modal input guard all come from ModalDialogUI, which
# attaches itself to the UI layer, so callers only supply the status text.
func _create_progress_dialog(status_text: String) -> ModalDialogUI:
	var dialog := ModalDialogUI.new()
	$UILayer.add_child(dialog)
	dialog.set_title(status_text)
	dialog.add_progress_bar()
	return dialog


func onScreenshotPressed() -> void:
	if capture_controller != null:
		capture_controller.on_capture_pressed()


func onScreenshotReleased() -> void:
	if capture_controller != null:
		capture_controller.on_capture_released()


# Save/session workers call this scene-compatible snapshot facade.
func _build_avatar_save_data() -> Dictionary:
	return avatar_controller.build_save_data()

func _on_link_button_pressed():
	if Global.begin_reparenting():
		Global.notify_user("Linking sprite...")


# --- Unified Replace Flow ---

func _on_replace_button_pressed():
	import_controller.show_replace_dialog()


func _on_replace_confirmed(matched: Array, new_items: Array, orphaned_sprites: Array, canvas_size: Vector2, remove_orphans: bool):
	import_controller.apply_replace_review(matched, new_items, orphaned_sprites, canvas_size, remove_orphans)


func _on_replace_cancelled():
	import_controller.cancel_replace_review()

func _on_duplicate_button_pressed() -> void:
	avatar_controller.duplicate_selected()


func changeCostumeStreamDeck(id: String) -> void:
	avatar_controller.change_costume_from_device(id)


func changeCostume(newCostume) -> void:
	avatar_controller.change_costume(int(newCostume))


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
	

	
func _on_background_input_capture_bg_key_pressed(node, keys_pressed):
	if Global.is_z_index_editor_active():
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
	if not keyStrings.is_empty() and Global.apply_animation_key_capture(keyStrings[0]):
		return

	if settingsMenu.awaitingCostumeInput >= 0:
		
		if keyStrings[0] == "Keycode1":
			if !settingsMenu.hasMouse:
				emit_signal("pressedKey")
				return
		
		var currentButton = costumeKeys[settingsMenu.awaitingCostumeInput]
		costumeKeys[settingsMenu.awaitingCostumeInput] = keyStrings[0]
		Saving.settings["costumeKeys"] = costumeKeys
		Global.notify_user("Changed costume " + str(settingsMenu.awaitingCostumeInput+1) + " hotkey from \"" + currentButton + "\" to \"" + keyStrings[0] + "\"")
		emit_signal("pressedKey")
	
	for key in keyStrings:
		var i = costumeKeys.find(key)
		if i >= 0:
			changeCostume(i+1)

	# Animation key triggers — fire every layer's key-bound clips. Skipped while
	# binding a costume key or typing into a text field.
	if settingsMenu.awaitingCostumeInput < 0 and not Global.has_text_entry_focus():
		for key in keyStrings:
			for s in Global.sprite_nodes():
				if s.type == "sprite":
					s.triggerAnimationKey(key)
	


func bgInputSprite(node, keys_pressed):
	if Global.is_z_index_editor_active():
		return
	if fileSystemOpen:
		return
	var keyStrings = []
	
	for i in keys_pressed:
		if keys_pressed[i]:
			keyStrings.append(OS.get_keycode_string(i) if !OS.get_keycode_string(i).strip_edges().is_empty() else "Keycode" + str(i))
	
	if keyStrings.size() <= 0:
		visibility_binding_armed.emit()
		return
	
	spriteVisToggles.emit(keyStrings)

func _on_clear_avatar_pressed():
	avatar_controller.clear_avatar()

func _on_reset_avatar_pressed():
	await avatar_controller.reset_avatar()
