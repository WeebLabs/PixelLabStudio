extends Node2D

var editMode = true

#Node Reference
@onready var origin = $OriginMotion/Origin
@onready var camera = $Camera2D
@onready var controlPanel = $ControlPanel
@onready var editControls = $EditControls
@onready var tutorial = $Tutorial
@onready var spriteViewer = $EditControls/SpriteViewer
@onready var viewerArrows = $ViewerArrows
@onready var spriteList = $EditControls/SpriteList

@onready var replaceReviewDialog = $ReplaceReviewDialog
@onready var saveDialog = $SaveDialog
@onready var loadDialog = $LoadDialog
@onready var psdImportDialog = $PSDImportDialog

@onready var lines = $Lines

@onready var settingsMenu = $ControlPanel/SettingsMenu

@onready var pushUpdates = $PushUpdates

@onready var shadow = $shadowSprite

var ndi_manager: Node = null
var _ndi_label: Label = null

var _save_thread: Thread = null


#Scene Reference
@onready var spriteObject = preload("res://ui_scenes/selectedSprite/spriteObject.tscn")

var saveLoaded = false

#Motion
var yVel = 0
var bounceSlider = 250
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

	screen_scale = DisplayServer.screen_get_scale()

	Global.connect("startSpeaking",onSpeak)

	$ControlPanel/MicButtong/Button.gui_input.connect(_on_mic_button_gui_input)

	ElgatoStreamDeck.on_key_down.connect(changeCostumeStreamDeck)
	
	if Saving.settings["newUser"]:
		_on_load_dialog_file_selected("default")
		Saving.settings["newUser"] = false
		saveLoaded = true
	else:
		_on_load_dialog_file_selected(Saving.settings["lastAvatar"])
		
		$ControlPanel/volumeSlider.value = Saving.settings["volume"]
		$ControlPanel/sensitiveSlider.value = Saving.settings["sense"]
		
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

	# Put HUD elements on visibility layer 2 so they're excluded from NDI output
	# (NDI SubViewport only renders layer 1)
	for hud_node in [controlPanel, editControls, tutorial, viewerArrows, lines, pushUpdates, shadow, $Failed, $MouseCursor]:
		hud_node.visibility_layer = 2

func _init_ndi():
	var NDIManagerScript = load("res://ndi/ndi_output_manager.gd")
	ndi_manager = Node.new()
	ndi_manager.set_script(NDIManagerScript)
	ndi_manager.name = "NDIManager"
	add_child(ndi_manager)

	# NDI status label in ControlPanel
	_ndi_label = Label.new()
	_ndi_label.name = "NDILabel"
	_ndi_label.text = "NDI"
	_ndi_label.add_theme_font_size_override("font_size", 12)
	_ndi_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	_ndi_label.position = Vector2(-80, -38)
	_ndi_label.visible = false
	controlPanel.add_child(_ndi_label)

func ndi_mark_dirty():
	if ndi_manager != null:
		ndi_manager.mark_dirty()

func _process(delta):
	# Freeze bounce while dragging NDI ruler
	var ruler_frozen = ndi_manager != null and ndi_manager.ruler_dragging
	if ruler_frozen:
		origin.get_parent().position.y = 0
		yVel = 0
		bounceChange = 0
	else:
		var hold = origin.get_parent().position.y

		origin.get_parent().position.y += yVel * 0.0166
		if origin.get_parent().position.y > 0:
			origin.get_parent().position.y = 0
		bounceChange = hold - origin.get_parent().position.y

		yVel += bounceGravity*0.0166
	
	if Input.is_action_just_pressed("openFolder"):
		OS.shell_open(ProjectSettings.globalize_path("user://"))
	
	moveSpriteMenu(delta)
	zoomScene()
	
	fileSystemOpen = isFileSystemOpen()

	_process_psd_thread(delta)
	_process_anim_thread(delta)
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
		30:
			onWindowSizeChange()

func onWindowSizeChange():
	if !saveLoaded:
		return
	Saving.settings["windowSize"] = var_to_str(get_window().size)
	var s = get_viewport().get_visible_rect().size
	origin.position = s*0.5
	
	lines.position = s*0.5
	lines.drawLine()
	
	camera.position = origin.position + _pan_offset
	controlPanel.position = camera.position + (s/(camera.zoom*2.0))
	tutorial.position = controlPanel.position
	editControls.position = camera.position - (s/(camera.zoom*2.0))
	viewerArrows.position = editControls.position
	spriteList.position.y = editControls.MENU_BAR_HEIGHT + 2
	spriteList._apply_size()
	pushUpdates.position.y = controlPanel.position.y
	pushUpdates.position.x = editControls.position.x

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
	
	$ControlPanel/ZoomLabel.modulate.a = lerp($ControlPanel/ZoomLabel.modulate.a,0.0,0.02)
	
func changeZoom():
	var newZoom = Vector2(1.0,1.0) / camera.zoom
	controlPanel.scale = newZoom
	tutorial.scale = newZoom
	editControls.scale = newZoom
	viewerArrows.scale = newZoom
	lines.scale = newZoom
	pushUpdates.scale = newZoom
	Global.mouse.scale = newZoom

	$ControlPanel/ZoomLabel.modulate.a = 6.0
	$ControlPanel/ZoomLabel.text = "Zoom : " + str(scaleOverall) + "%"
	
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
	onWindowSizeChange()

#Adds sprite object to scene
func add_image(path):
	UndoManager.save_state()

	var rand = RandomNumberGenerator.new()
	var id = rand.randi()
	
	var sprite = spriteObject.instantiate()
	sprite.path = path
	sprite.id = id
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

var _anim_parser = null        # GIFParser or APNGParser
var _anim_thread: Thread = null
var _anim_result = null
var _anim_progress_dialog: Node2D = null
var _anim_replace_mode: bool = false

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

func _on_psd_import_confirmed(selected_layers: Array, canvas_size: Vector2):
	UndoManager.save_state()
	var canvas_center = canvas_size * 0.5
	var sprites_added = []

	for layer in selected_layers:
		var layer_center = Vector2(
			(layer.left + layer.right) * 0.5,
			(layer.top + layer.bottom) * 0.5
		)
		var pos = layer_center - canvas_center
		var sprite = add_image_from_data(layer.image, layer.name, pos)
		sprites_added.append(sprite)

	Global.spriteList.updateData(true)
	Global.pushUpdate("Imported " + str(sprites_added.size()) + " layers from PSD.")

func _on_psd_import_cancelled():
	Global.pushUpdate("PSD import cancelled.")

# --- Animated GIF/APNG Import ---

func _start_animated_import(path: String, is_replace: bool):
	_anim_replace_mode = is_replace
	_anim_result = null

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
			return

		_finish_animated_import(result)

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
	sprite.path = "animated://import"
	sprite.id = id
	sprite.frames = frame_count
	sprite.animSpeed = anim_speed
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
	var count = 0
	for path in paths:
		if path.get_extension().to_lower() == "png" and APNGParser.is_apng(path):
			_start_animated_import(path, false)
		else:
			var rand = RandomNumberGenerator.new()
			var id = rand.randi()
			var sprite = spriteObject.instantiate()
			sprite.path = path
			sprite.id = id
			origin.add_child(sprite)
			sprite.position = Vector2.ZERO
		count += 1
	Global.spriteList.updateData()
	ndi_mark_dirty()
	if count == 1:
		Global.pushUpdate("Added new sprite.")
	else:
		Global.pushUpdate("Imported " + str(count) + " sprites.")

func _on_save_button_pressed():
	$SaveDialog.visible = true
	

func _on_load_button_pressed():
	$LoadDialog.visible = true

#LOAD AVATAR
func _on_load_dialog_file_selected(path):
	UndoManager.save_state()
	var data = Saving.read_save(path)

	if data == null:
		return

	Global.heldSprite = null
	origin.queue_free()
	var new = Node2D.new()
	$OriginMotion.add_child(new)
	origin = new
	
	for item in data:
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
				for i in range(5):
					sprite.costumeLayers.append(1)

		if data[item].has("stretchAmount"):
			sprite.stretchAmount = data[item]["stretchAmount"]
		
		if data[item].has("ignoreBounce"):
			sprite.ignoreBounce = data[item]["ignoreBounce"]
		
		if data[item].has("frames"):
			sprite.frames = data[item]["frames"]
		if data[item].has("animSpeed"):
			sprite.animSpeed = data[item]["animSpeed"]
		if data[item].has("imageData"):
			sprite.loadedImageData = data[item]["imageData"]
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

		origin.add_child(sprite)
		sprite.position = str_to_var(data[item]["pos"])
	
	changeCostume(1)
	Saving.settings["lastAvatar"] = path
	Global.spriteList.updateData()

	Global.pushUpdate("Loaded avatar at: " + path)

	onWindowSizeChange()
	ndi_mark_dirty()
	
#SAVE AVATAR
func _on_save_dialog_file_selected(path):
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null

	var data = {}
	var nodes = get_tree().get_nodes_in_group("saved")
	var id = 0
	for child in nodes:

		if child.type == "sprite":
			data[id] = {}
			data[id]["type"] = "sprite"
			data[id]["path"] = child.path
			data[id]["_image_ref"] = child.imageData
			data[id]["identification"] = child.id
			data[id]["parentId"] = child.parentId

			data[id]["pos"] = var_to_str(child.position)
			data[id]["offset"] = var_to_str(child.offset)
			data[id]["zindex"] = child.z

			data[id]["drag"] = child.dragSpeed

			data[id]["xFrq"] = child.xFrq
			data[id]["xAmp"] = child.xAmp
			data[id]["yFrq"] = child.yFrq
			data[id]["yAmp"] = child.yAmp

			data[id]["rotDrag"] = child.rdragStr

			data[id]["showTalk"] = child.showOnTalk
			data[id]["showBlink"] = child.showOnBlink

			data[id]["rLimitMin"] = child.rLimitMin
			data[id]["rLimitMax"] = child.rLimitMax

			data[id]["costumeLayers"] = var_to_str(child.costumeLayers)

			data[id]["stretchAmount"] = child.stretchAmount

			data[id]["ignoreBounce"] = child.ignoreBounce

			data[id]["frames"] = child.frames
			data[id]["animSpeed"] = child.animSpeed

			data[id]["clipped"] = child.clipped

			data[id]["toggle"] = child.toggle

			data[id]["eyeTrack"] = child.eyeTrack
			data[id]["eyeTrackDistance"] = child.eyeTrackDistance
			data[id]["eyeTrackSpeed"] = child.eyeTrackSpeed
			data[id]["eyeTrackInvert"] = child.eyeTrackInvert

		id += 1

	Saving.settings["lastAvatar"] = path
	Global.pushUpdate("Saving avatar...")

	_save_thread = Thread.new()
	_save_thread.start(_save_worker.bind(data, path))

func _save_worker(data: Dictionary, path: String):
	for id in data:
		if data[id].has("_image_ref"):
			var img: Image = data[id]["_image_ref"]
			data[id]["imageData"] = Marshalls.raw_to_base64(img.save_png_to_buffer())
			data[id].erase("_image_ref")
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_line(JSON.stringify(data))
	file.close()
	call_deferred("_on_save_finished", path, data)

func _on_save_finished(path: String, data: Dictionary):
	Saving.data = data
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null
	Global.pushUpdate("Saved avatar at: " + path)

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
	sprite.parentId = Global.heldSprite.parentId

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
	
	sprite.costumeLayers = Global.heldSprite.costumeLayers

	sprite.eyeTrack = Global.heldSprite.eyeTrack
	sprite.eyeTrackDistance = Global.heldSprite.eyeTrackDistance
	sprite.eyeTrackSpeed = Global.heldSprite.eyeTrackSpeed
	sprite.eyeTrackInvert = Global.heldSprite.eyeTrackInvert

	origin.add_child(sprite)
	sprite.position = Global.heldSprite.position + Vector2(16,16)
	
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

	var windowLength = 1124

	$ViewerArrows/Arrows.visible = false
	$ViewerArrows/Arrows2.visible = false

	if !Global.spriteEdit.visible:
		return

	if size.y > windowLength+50:
		Global.spriteEdit.position.y = topY
		return

	if Global.spriteEdit.position.y > topY:
		Global.spriteEdit.position.y = topY
	elif Global.spriteEdit.position.y < size.y-windowLength:
		Global.spriteEdit.position.y = size.y-windowLength
	

	
#UNAMED BUT THIS IS THE MICROPHONE MENU BUTTON
func _on_button_pressed():
	$ControlPanel/MicInputSelect.visible = !$ControlPanel/MicInputSelect.visible
	settingsMenu.visible = false

func _on_mic_button_gui_input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		Global.micMuted = !Global.micMuted
		if Global.micMuted:
			$ControlPanel/MicButtong.modulate = Color(1, 0.3, 0.3)
			Global.pushUpdate("Microphone muted.")
		else:
			$ControlPanel/MicButtong.modulate = Color(1, 1, 1)
			Global.pushUpdate("Microphone unmuted.")


func _on_settings_buttons_pressed():
	settingsMenu.visible = !settingsMenu.visible


func _on_background_input_capture_bg_key_pressed(node, keys_pressed):
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
