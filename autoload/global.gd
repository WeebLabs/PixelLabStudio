extends Node

#Global Node Reference
var main = null
var spriteEdit = null
var fail = null
var mouse = null
var spriteList = null
var chain = null

var animationTick = 0

var cursorWorldPos = Vector2.ZERO
var _cursorScreenToWorldOffset: Vector2 = Vector2.ZERO

var filtering = false
var _text_field_active: bool = false
var _z_overlay: Node2D = null
var _z_input: LineEdit = null
var _z_style_normal: StyleBoxFlat = null
var _z_style_focus: StyleBoxFlat = null
var _z_input_active: bool = false
var _suppress_keys_frame: int = -1

var _screenshot_key_held: bool = false
var _screenshot_press_time: int = 0

#Object Selection
var heldSprite = null
var lastArray = []
var i = 0

var reparentMode = false
var originMode = false
var awaitingToggleBind = false
var _origin_press_time = 0
var scrollSelection = 0
var _scroll_input = 0

var backgroundColor = Color(0.0,0.0,0.0,0.0) 

#Blink
var blinkSpeed = 1.0
var blinkChance = 200
var blink = false
var blinkTick = 0

#Audio Listener

var currentMicrophone = null

var speaking = false
var micMuted = false
var spectrum
var volume = 0
var volumeSensitivity = 0.0

var volumeLimit = 0.0
var senseLimit = 0.0

#Speak Signals
signal startSpeaking
signal stopSpeaking

var updatePusherNode = null

var rand = RandomNumberGenerator.new()

func _ready():
	spectrum = AudioServer.get_bus_effect_instance(1, 1)
	
	if !Saving.settings.has("useStreamDeck"):
		Saving.settings["useStreamDeck"] = false

	if Saving.settings.has("audioDevice") and Saving.settings["audioDevice"] != "":
		var saved_device = Saving.settings["audioDevice"]
		if saved_device in AudioServer.get_input_device_list():
			AudioServer.input_device = saved_device

	createMicrophone()

func createMicrophone():
	deleteAllMics()
	var playa = AudioStreamPlayer.new()
	var mic = AudioStreamMicrophone.new()
	playa.stream = mic
	playa.bus = "MIC"
	add_child(playa)
	playa.play()
	currentMicrophone = playa

func deleteAllMics():
	for child in get_children():
		child.queue_free()
	currentMicrophone = null


func _process(delta):
	_text_field_active = _is_any_field_focused()
	animationTick += 1

	if main != null:
		cursorWorldPos = Vector2(DisplayServer.mouse_get_position()) + _cursorScreenToWorldOffset

	volume = spectrum.get_magnitude_for_frequency_range(20, 20000).length()
	if currentMicrophone != null:
		volumeSensitivity = lerp(volumeSensitivity,0.0,delta*2)
	
	if volume>volumeLimit:
		volumeSensitivity = 1.0
	
	var prev = speaking
	speaking = volumeSensitivity > senseLimit

	if micMuted:
		speaking = false

	if Input.is_action_pressed("simMic"):
		speaking = true

	if prev != speaking:
		if speaking:
			emit_signal("startSpeaking")
		else:
			emit_signal("stopSpeaking")
	
	if main != null and heldSprite != null and !_text_field_active:
		if Input.is_action_just_pressed("zDown"):
			UndoManager.save_state()
			heldSprite.z -= 1
			heldSprite.setZIndex()
			pushUpdate("Moved sprite layer.")
		if Input.is_action_just_pressed("zUp"):
			UndoManager.save_state()
			heldSprite.z += 1
			heldSprite.setZIndex()
			pushUpdate("Moved sprite layer.")
		if main.editMode:
			if Input.is_action_just_pressed("reparent"):
				reparentMode = !reparentMode
				originMode = false
				Global.chain.enable(reparentMode)
			if Input.is_action_just_pressed("origin"):
				_origin_press_time = Time.get_ticks_msec()
			if Input.is_action_pressed("origin") and !originMode:
				if Time.get_ticks_msec() - _origin_press_time >= 300:
					originMode = true
					reparentMode = false
					chain.enable(false)
					pushUpdate("Origin adjustment mode.")
			if Input.is_action_just_released("origin"):
				if Time.get_ticks_msec() - _origin_press_time < 300:
					if heldSprite != null:
						UndoManager.save_state()
						heldSprite.snapOriginToMouse()
						pushUpdate("Snapped origin to cursor.")
				else:
					if originMode:
						originMode = false
						pushUpdate("Exited origin adjustment mode.")

	else:
		reparentMode = false
		originMode = false
		Global.chain.enable(reparentMode)
	
	if main.editMode:
		if reparentMode:
			RenderingServer.set_default_clear_color(Color(0.18, 0.25, 0.35))
		elif originMode:
			RenderingServer.set_default_clear_color(Color(0.25, 0.18, 0.3))
		else:
			RenderingServer.set_default_clear_color(Color(0.3, 0.3, 0.3))

	
	blinking()
	scrollSprites()

	# Screenshot/record key release (outside control block so release is caught
	# even if Ctrl is released before K)
	if _screenshot_key_held and Input.is_action_just_released("screenshot"):
		main.onScreenshotReleased()
		_screenshot_key_held = false

	if !main.fileSystemOpen and !_text_field_active:

		if Input.is_action_just_pressed("refresh"):
			refresh()
		if Input.is_action_just_pressed("unlink"):
			UndoManager.save_state()
			unlinkSprite()

		if Input.is_action_pressed("control"):
			if Input.is_action_just_pressed("saveImages"):
				saveImagesFromData()
			if Input.is_action_just_pressed("undo"):
				UndoManager.undo()
			if Input.is_action_just_pressed("redo"):
				UndoManager.redo()
			if Input.is_action_just_pressed("screenshot"):
				_screenshot_key_held = true
				_screenshot_press_time = Time.get_ticks_msec()
				main.onScreenshotPressed()
	
	
func _is_any_field_focused() -> bool:
	if _suppress_keys_frame == Engine.get_process_frames():
		return true
	var focused = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

# --- Z-Index input overlay ---

func _build_z_overlay():
	_z_overlay = Node2D.new()
	_z_overlay.z_index = 4095
	_z_overlay.visible = false
	main.add_child(_z_overlay)

	var panel = Panel.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.13, 0.15, 0.97)
	panel_style.set_corner_radius_all(8)
	panel_style.border_color = Color(0.3, 0.3, 0.35, 0.6)
	panel_style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.position = Vector2(-110, -40)
	panel.size = Vector2(220, 80)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_z_overlay.add_child(panel)

	var title = Label.new()
	title.text = "Set Z-Index"
	title.position = Vector2(-100, -32)
	title.size = Vector2(200, 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_z_overlay.add_child(title)

	_z_input = LineEdit.new()
	_z_input.position = Vector2(-90, -4)
	_z_input.size = Vector2(180, 32)
	_z_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_z_input.add_theme_font_size_override("font_size", 16)
	_z_input.caret_blink = true
	_z_input.caret_blink_interval = 0.5
	var fs_normal = StyleBoxFlat.new()
	fs_normal.bg_color = Color(0.08, 0.08, 0.08)
	fs_normal.set_corner_radius_all(4)
	fs_normal.content_margin_left = 8
	fs_normal.content_margin_right = 8
	fs_normal.content_margin_top = 4
	fs_normal.content_margin_bottom = 4
	var fs_focus = fs_normal.duplicate()
	fs_focus.border_color = Color(0.45, 0.45, 0.5)
	fs_focus.set_border_width_all(1)
	_z_input.add_theme_stylebox_override("normal", fs_normal)
	_z_input.add_theme_stylebox_override("focus", fs_focus)
	_z_input.text_submitted.connect(_on_z_input_submitted)
	_z_input.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				_on_z_input_submitted(_z_input.text)
				_z_input.accept_event()
	)
	_z_overlay.add_child(_z_input)

	# Store normal style for flash effect
	_z_style_normal = fs_normal
	_z_style_focus = fs_focus

func _show_z_input():
	if heldSprite == null or main == null:
		return
	if _z_overlay == null:
		_build_z_overlay()
	var vp_size = get_viewport().get_visible_rect().size / main.camera.zoom
	_z_overlay.position = main.camera.position + Vector2(0, vp_size.y * 0.5 - 80)
	_z_overlay.visible = true
	_z_input.text = str(heldSprite.z)
	_z_input.select_all()
	_z_input.grab_focus()
	_z_input_active = true

func _hide_z_input():
	if _z_overlay != null:
		_z_overlay.visible = false
		_z_input.release_focus()
	_z_input_active = false
	_suppress_keys_frame = Engine.get_process_frames()

func _on_z_input_submitted(_text: String):
	_apply_z_input()

func _apply_z_input():
	var text = _z_input.text.strip_edges()
	if heldSprite == null or !text.is_valid_int():
		return
	UndoManager.save_state()
	heldSprite.z = text.to_int()
	heldSprite.setZIndex()
	pushUpdate("Set z-index to " + str(heldSprite.z) + ".")
	spriteList.updateData()
	_z_input.select_all()
	_flash_z_confirm()

var _z_flash_tween: Tween = null

func _flash_z_confirm():
	if _z_flash_tween != null and _z_flash_tween.is_valid():
		_z_flash_tween.kill()
	var flash_style = _z_style_focus.duplicate()
	_z_input.add_theme_stylebox_override("normal", flash_style)
	_z_input.add_theme_stylebox_override("focus", flash_style)
	var bg_from = _z_style_focus.bg_color
	var bg_peak = Color(0.22, 0.12, 0.15)
	var border_from = _z_style_focus.border_color
	var border_peak = Color(1.0, 0.7, 0.8)
	_z_flash_tween = create_tween()
	_z_flash_tween.tween_method(func(t: float):
		flash_style.bg_color = bg_from.lerp(bg_peak, t)
		flash_style.border_color = border_from.lerp(border_peak, t)
	, 0.0, 1.0, 0.15)
	_z_flash_tween.tween_method(func(t: float):
		flash_style.bg_color = bg_peak.lerp(bg_from, t)
		flash_style.border_color = border_peak.lerp(border_from, t)
	, 0.0, 1.0, 0.35)
	_z_flash_tween.tween_callback(_reset_z_style)

func _reset_z_style():
	if _z_input != null:
		_z_input.add_theme_stylebox_override("normal", _z_style_normal)
		_z_input.add_theme_stylebox_override("focus", _z_style_focus)

func _input(event):
	# Refresh screen-to-world offset whenever the cursor is inside the window,
	# so out-of-window tracking can extrapolate from DisplayServer.mouse_get_position().
	if event is InputEventMouseMotion and main != null:
		_cursorScreenToWorldOffset = main.get_global_mouse_position() - Vector2(DisplayServer.mouse_get_position())

	# Z-index overlay: Escape to cancel, click outside to dismiss, N to open
	if event is InputEventKey and event.pressed and !event.echo:
		if _z_input_active:
			if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
				_hide_z_input()
				get_viewport().set_input_as_handled()
				return
		elif main != null and !main.fileSystemOpen and heldSprite != null and main.editMode:
			if event.physical_keycode == KEY_N and !_is_any_field_focused():
				_show_z_input()
				get_viewport().set_input_as_handled()
				return
	if _z_input_active and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local = _z_overlay.to_local(main.get_global_mouse_position())
		if abs(local.x) > 110 or abs(local.y) > 40:
			_hide_z_input()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if reparentMode:
			reparentMode = false
			chain.enable(false)
			pushUpdate("Linking cancelled.")
			get_viewport().set_input_as_handled()
			return
	if !Input.is_action_pressed("control"):
		# Skip scroll accumulation when cursor is over the left sidebar
		if event is InputEventMouseButton:
			if main != null and main.editMode and spriteEdit != null and spriteEdit.visible:
				if event.position.x < spriteEdit.panel_width + 19:
					return
		if event.is_action_pressed("scrollUp"):
			_scroll_input += 1
		if event.is_action_pressed("scrollDown"):
			_scroll_input -= 1

func select(areas):
	
	if main.fileSystemOpen:
		return
	
	for area in areas:
		if area.is_in_group("penis"):
			return
	
	var prevSpr = heldSprite
	if areas.size() <= 0:
		heldSprite = null
		originMode = false
		i = 0
		lastArray = []
		return
	
	if areas != lastArray:
		heldSprite = areas[0].get_parent().get_parent().get_parent()
		i = 0
	else:
		i += 1
		
		if i >= areas.size():
			i = 0
		
		heldSprite = areas[i].get_parent().get_parent().get_parent()
	
	var count = heldSprite.path.get_slice_count("/") - 1
	var i1 = heldSprite.path.get_slice("/",count)
	pushUpdate("Selected sprite \"" + i1 + "\"" + ".")
	
	heldSprite.set_physics_process(true)
	
	if reparentMode:
		if prevSpr == heldSprite:
			reparentMode = false
			return
		if heldSprite.parentId == prevSpr.id:
			return
		
		UndoManager.save_state()
		linkSprite(prevSpr,heldSprite)
		Global.chain.enable(reparentMode)
	
	lastArray = areas.duplicate()
	
	spriteEdit.setImage()

func linkSprite(sprite,newParent):
	if sprite == newParent:
		reparentMode = false

		return
	if newParent.parentId == sprite.id:
		reparentMode = false
		return

	if sprite.is_ancestor_of(newParent):
		pushUpdate("Can't link to own child sprite!")
		reparentMode = false
		return

	# Zero all ancestor wobbles for stable reparent position
	var saved_wobbles = []
	var current = sprite
	while current != null:
		saved_wobbles.append([current, current.wob.position])
		current.wob.position = Vector2.ZERO
		current = current.parentSprite
	current = newParent
	while current != null:
		var already_saved = false
		for entry in saved_wobbles:
			if entry[0] == current:
				already_saved = true
				break
		if not already_saved:
			saved_wobbles.append([current, current.wob.position])
			current.wob.position = Vector2.ZERO
		current = current.parentSprite

	sprite.reparent(newParent.sprite,true)

	for entry in saved_wobbles:
		entry[0].wob.position = entry[1]

	sprite.parentId = newParent.id
	sprite.parentSprite = newParent
	
	reparentMode = false

	Global.spriteList._pending_scroll_target = newParent
	Global.spriteList.refreshHierarchy()
	
	var count = sprite.path.get_slice_count("/") - 1
	var i1 = sprite.path.get_slice("/",count)
	
	count = newParent.path.get_slice_count("/") - 1
	var i2 = newParent.path.get_slice("/",count)
	
	pushUpdate("Linked sprite \"" + i1 + "\" to sprite \"" + i2 + "\".")
	newParent.set_physics_process(true)

func scrollSprites():
	var scroll = _scroll_input
	_scroll_input = 0

	if originMode:
		return

	if Input.is_action_pressed("control"):
		return

	if !main.editMode:
		return

	if main.fileSystemOpen:
		return

	if get_viewport().gui_get_hovered_control() != null and !_z_input_active:
		return

	if heldSprite == null:
		scrollSelection = 0

	if scroll == 0:
		return
	
	
	var obj = get_tree().get_nodes_in_group("saved")
	
	if obj.size() <= 0:
		return
	
	scrollSelection += scroll
	if scrollSelection >= obj.size():
		scrollSelection = 0
	elif scrollSelection < 0:
		scrollSelection = obj.size() - 1
	
	heldSprite = obj[scrollSelection]
	
	var count = heldSprite.path.get_slice_count("/") - 1
	var i1 = heldSprite.path.get_slice("/",count)
	pushUpdate("Selected sprite \"" + i1 + "\"" + ".")
	
	heldSprite.set_physics_process(true)

	spriteEdit.setImage()

	if _z_input_active and heldSprite != null:
		_z_input.text = str(heldSprite.z)
		_z_input.grab_focus()
		_z_input.select_all()

func blinking():
	# Floor scales with blinkChance so the slider actually moves the gap between blinks
	var floor_frames = 2 * blinkChance * blinkSpeed
	blinkTick += 1
	if blinkTick == 0:
		blink = false
		if rand.randf_range(-1.0,1.0) > 0.5:
			blinkTick = floor_frames + 1
	if blinkTick > floor_frames:
		if rand.randi() % int(blinkChance) == 0:
			blink = true

			blinkTick = -12
	
func epicFail(err):
	print(fail)
	if fail == null:
		return
	
	fail.get_node("type").text = ""
	match err:
		ERR_FILE_CORRUPT:
			fail.get_node("type").text = "FILE CORRUPT"
		ERR_FILE_NOT_FOUND:
			fail.get_node("type").text = "FILE NOT FOUND"
		ERR_FILE_CANT_OPEN:
			fail.get_node("type").text = "FILE CANT OPEN"
		ERR_FILE_ALREADY_IN_USE:
			fail.get_node("type").text = "FILE IN USE"
		ERR_FILE_NO_PERMISSION:
			fail.get_node("type").text = "MISSING PERMISSION"
		ERR_INVALID_DATA:
			fail.get_node("type").text = "DATA INVALID"
		ERR_FILE_CANT_READ:
			fail.get_node("type").text = "CANT READ FILE"
	
	fail.visible = true
	await get_tree().create_timer(2.5).timeout
	fail.visible = false

func refresh():
	var objs = get_tree().get_nodes_in_group("saved")
	for object in objs:
		object.replaceSprite(object.path)
		object.sprite.frame = 0
		object.remadePolygon = false
	pushUpdate("Refreshed all sprites.")

func unlinkChildren(parentSpr):
	var children = parentSpr.getAllLinkedSprites()
	if children.size() == 0:
		return
	var saved_wob = parentSpr.wob.position
	parentSpr.wob.position = Vector2.ZERO
	for child in children:
		var glob = child.global_position
		child.get_parent().remove_child(child)
		main.origin.add_child(child)
		child.parentId = null
		child.parentSprite = null
		child.position = glob - main.origin.position
	parentSpr.wob.position = saved_wob

func unlinkSprite():
	if heldSprite == null:
		return
	if heldSprite.parentId == null:
		return

	# Zero all ancestor wobbles for stable position calculation
	var saved_wobbles = []
	var current = heldSprite
	while current != null:
		saved_wobbles.append([current, current.wob.position])
		current.wob.position = Vector2.ZERO
		current = current.parentSprite

	var glob = heldSprite.global_position
	glob = Vector2(int(glob.x),int(glob.y))

	heldSprite.get_parent().remove_child(heldSprite)
	main.origin.add_child(heldSprite)
	heldSprite.set_owner(main.origin)
	heldSprite.parentId = null
	heldSprite.parentSprite = null
	heldSprite.position = glob - main.origin.position

	for entry in saved_wobbles:
		entry[0].wob.position = entry[1]

	Global.spriteList.refreshHierarchy()
	pushUpdate("Unlinked sprite.")

func saveImagesFromData():
	var sprites = get_tree().get_nodes_in_group("saved")
	if sprites.size() <= 0:
		return
	for sprite in sprites:
		var img = sprite.imageData
		var array = sprite.path.split("/",false)
		var length = sprite.path.length() - array[array.size()-1].length()
		
		DirAccess.make_dir_recursive_absolute(sprite.path.left(length-1))
		img.save_png(sprite.path)
	
	pushUpdate("Saved all avatar images to computer.")
	
func pushUpdate(text):
	if is_instance_valid(updatePusherNode):
		updatePusherNode.pushUpdate(text)
