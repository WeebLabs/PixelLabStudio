extends Node2D

var awaitingCostumeInput = -1

var hasMouse = false

# NDI UI references (built in code)
var _ndi_section: Node2D = null
var _ndi_toggle: CheckBox = null
var _ndi_status_label: Label = null
var _ndi_width_option: OptionButton = null
var _ndi_mode_option: OptionButton = null
var _ndi_manual_w: SpinBox = null
var _ndi_manual_h: SpinBox = null
var _ndi_manual_container: HBoxContainer = null

func setvalues():
	
	$Background/ColorPickerButton.color = Global.backgroundColor
	if Global.backgroundColor == Color(0.0,0.0,0.0,0.0):
		$Background/ColorPickerButton.color = Color(1.0,1.0,1.0,1.0)
	
	
	$MaxFPS/fpslabel.text = str(Engine.max_fps)
	$MaxFPS/fpsDrag.value = Engine.max_fps
	if Engine.max_fps == 0:
		$MaxFPS/fpslabel.text = "Unlimited"
		$MaxFPS/fpsDrag.value = 241
	
	$BounceForce/bounce.text = str(Saving.settings["bounce"])
	$BounceForce/bounceForce.value = Saving.settings["bounce"]
	$BounceGravity/bounce.text = str(Saving.settings["gravity"])
	$BounceGravity/bounceGravity.value = Saving.settings["gravity"]
	
	_on_check_box_toggled(Global.filtering)
	
	$BlinkSpeed/blinkSpeed.value = int(1.0/Global.blinkSpeed)
	$BlinkSpeed/Label.text = "blink speed: " + str(int(1.0/Global.blinkSpeed))
	
	$BlinkChance/blinkChance.value = Global.blinkChance
	$BlinkChance/Label.text = "blink chance: 1 in " + str(Global.blinkChance) 
	
	$bounceOnCostume/costumeCheck.button_pressed = Global.main.bounceOnCostumeChange

	_build_ndi_section()
	_update_ndi_ui()

	var costumeLabels = [$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton1/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton2/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton3/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton4/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton5/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton6/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton7/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton8/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton9/Label,$CostumeInputs/ScrollContainer/VBoxContainer/costumeButton10/Label,]
	var tag = 1
	for label in costumeLabels:
		label.text = "costume " + str(tag) + " key: \"" + Global.main.costumeKeys[tag-1] + "\""
		tag += 1
	
func _on_color_picker_button_color_changed(color):
	get_viewport().transparent_bg = false
	RenderingServer.set_default_clear_color(color)
	Global.backgroundColor = color
	Saving.settings["backgroundColor"] = var_to_str(color)
	
	Global.pushUpdate("Background color set to CUSTOM COLOR.")

func _on_button_pressed():
	get_viewport().transparent_bg = true
	Global.backgroundColor = Color(0.0,0.0,0.0,0.0)
	Saving.settings["backgroundColor"] = var_to_str(Color(0.0,0.0,0.0,0.0))
	
	Global.pushUpdate("Background color set to TRANSPARENT.")

func _on_color_picker_button_picker_created():
	get_viewport().transparent_bg = false
	RenderingServer.set_default_clear_color($Background/ColorPickerButton.color)
	
func _on_fps_drag_value_changed(value):
	if $MaxFPS/fpsDrag.value == 241:
		$MaxFPS/fpslabel.text = "Unlimited"
		return
	$MaxFPS/fpslabel.text = str(value)


func _on_confirm_pressed():
	if $MaxFPS/fpsDrag.value == 241:
		Engine.max_fps = 0
		Saving.settings["maxFPS"] = 0
		Global.pushUpdate("Max fps set to unlimited.")
		return
	Engine.max_fps = $MaxFPS/fpsDrag.value
	Saving.settings["maxFPS"] = $MaxFPS/fpsDrag.value
	
	Global.pushUpdate("Max fps set to " + str(Engine.max_fps) + ".")

func _on_green_button_pressed():
	get_viewport().transparent_bg = false
	Global.backgroundColor = Color(0.0,1.0,0.0,1.0)
	Saving.settings["backgroundColor"] = var_to_str(Color(0.0,1.0,0.0,1.0))
	RenderingServer.set_default_clear_color(Color(0.0,1.0,0.0,1.0))
	
	Global.pushUpdate("Background color set to GREEN.")

func _on_blue_button_pressed():
	get_viewport().transparent_bg = false
	Global.backgroundColor = Color(0.0,0.0,1.0,1.0)
	Saving.settings["backgroundColor"] = var_to_str(Color(0.0,0.0,1.0,1.0))
	RenderingServer.set_default_clear_color(Color(0.0,0.0,1.0,1.0))
	
	Global.pushUpdate("Background color set to BLUE.")

func _on_magenta_button_pressed():
	get_viewport().transparent_bg = false
	Global.backgroundColor = Color(1.0,0.0,1.0,1.0)
	Saving.settings["backgroundColor"] = var_to_str(Color(1.0,0.0,1.0,1.0))
	RenderingServer.set_default_clear_color(Color(1.0,0.0,1.0,1.0))
	
	Global.pushUpdate("Background color set to MAGENTA.")

func _on_check_box_toggled(button_pressed):
	var new = 0
	if button_pressed:
		new = 2
	var nodes = get_tree().get_nodes_in_group("saved")
	for sprite in nodes:
		sprite.sprite.texture_filter = new
	Global.filtering = button_pressed
	Saving.settings["filtering"] = button_pressed
	$AntiAliasing/CheckBox.button_pressed = button_pressed
	
	Global.pushUpdate("Texture filtering set to: " + str(button_pressed))

func _on_bounce_force_value_changed(value):
	$BounceForce/bounce.text = str(value)
	Global.main.bounceSlider = value
	Saving.settings["bounce"] = value
	Global.main.ndi_mark_dirty()

	Global.pushUpdate("Bounce force value changed.")

func _on_bounce_gravity_value_changed(value):
	$BounceGravity/bounce.text = str(value)
	Global.main.bounceGravity = value
	Saving.settings["gravity"] = value
	Global.main.ndi_mark_dirty()

	Global.pushUpdate("Bounce gravity value changed.")

func costumeButtonsPressed(label,id):
	label.text = "AWAITING INPUT"
	await Global.main.emptiedCapture
	awaitingCostumeInput = id - 1
	
	
	await Global.main.pressedKey
	label.text = "costume " + str(id) + " key: \"" + Global.main.costumeKeys[id - 1] + "\""
	await Global.main.emptiedCapture
	awaitingCostumeInput = -1

func _on_costume_button_1_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton1/Label
	costumeButtonsPressed(label,1)
func _on_costume_button_2_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton2/Label
	costumeButtonsPressed(label,2)
func _on_costume_button_3_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton3/Label
	costumeButtonsPressed(label,3)
func _on_costume_button_4_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton4/Label
	costumeButtonsPressed(label,4)
func _on_costume_button_5_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton5/Label
	costumeButtonsPressed(label,5)
func _on_costume_button_6_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton6/Label
	costumeButtonsPressed(label,6)
func _on_costume_button_7_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton7/Label
	costumeButtonsPressed(label,7)
func _on_costume_button_8_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton8/Label
	costumeButtonsPressed(label,8)
func _on_costume_button_9_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton9/Label
	costumeButtonsPressed(label,9)
func _on_costume_button_10_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton10/Label
	costumeButtonsPressed(label,10)


func _on_blink_speed_value_changed(value):
	if value == 0:
		Global.blinkSpeed = 0.0
		Saving.settings["blinkSpeed"] = 0.0
		$BlinkSpeed/Label.text = "blink speed: 0"
		return
	Global.blinkSpeed = 1.0/float(value)
	Saving.settings["blinkSpeed"] = 1.0/float(value)
	$BlinkSpeed/Label.text = "blink speed: " + str(value)


func _on_blink_chance_value_changed(value):
	Global.blinkChance = value
	Saving.settings["blinkChance"] = value
	$BlinkChance/Label.text = "blink chance: 1 in " + str(value)


func _on_costume_check_toggled(button_pressed):
	Global.main.bounceOnCostumeChange = button_pressed
	Saving.settings["bounceOnCostumeChange"] = button_pressed


func _process(delta):
	var g = to_local(get_global_mouse_position())
	if g.x < 0 or g.y < 0 or g.x > $NinePatchRect.size.x or g.y > $NinePatchRect.size.y:
		hasMouse = false
	else:
		hasMouse = true

func deleteKey(label,id):
	Global.main.costumeKeys[id-1] = "null"
	label.text = "costume " + str(id) + " key: \"" + Global.main.costumeKeys[id-1] + "\""
	Global.pushUpdate("Deleted costume hotkey " + str(id) + ".")
	
func _on_delete_1_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton1/Label
	deleteKey(label,1)

func _on_delete_2_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton2/Label
	deleteKey(label,2)

func _on_delete_3_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton3/Label
	deleteKey(label,3)

func _on_delete_4_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton4/Label
	deleteKey(label,4)

func _on_delete_5_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton5/Label
	deleteKey(label,5)

func _on_delete_6_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton6/Label
	deleteKey(label,6)

func _on_delete_7_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton7/Label
	deleteKey(label,7)

func _on_delete_8_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton8/Label
	deleteKey(label,8)

func _on_delete_9_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton9/Label
	deleteKey(label,9)

func _on_delete_10_pressed():
	var label = $CostumeInputs/ScrollContainer/VBoxContainer/costumeButton10/Label
	deleteKey(label,10)

# --- NDI Settings ---

func _build_ndi_section():
	if _ndi_section != null:
		return

	# Expand background to fit NDI section and shift menu up so it doesn't cover the settings icon
	$NinePatchRect.offset_bottom += 160
	position.y -= 160

	_ndi_section = Node2D.new()
	_ndi_section.name = "NDISettings"
	_ndi_section.position = Vector2(22, 405)
	add_child(_ndi_section)

	# Separator line
	var sep = ColorRect.new()
	sep.position = Vector2(-4, 0)
	sep.size = Vector2(380, 2)
	sep.color = Color(0.5, 0.5, 0.5, 0.4)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ndi_section.add_child(sep)

	# Title label
	var title = Label.new()
	title.position = Vector2(0, 6)
	title.text = "NDI Output"
	title.add_theme_font_size_override("font_size", 14)
	_ndi_section.add_child(title)

	# Status label (shows "plugin not installed" if needed)
	_ndi_status_label = Label.new()
	_ndi_status_label.position = Vector2(100, 6)
	_ndi_status_label.add_theme_font_size_override("font_size", 11)
	_ndi_status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	_ndi_section.add_child(_ndi_status_label)

	# Enable toggle
	var toggle_label = Label.new()
	toggle_label.position = Vector2(0, 30)
	toggle_label.text = "enabled"
	_ndi_section.add_child(toggle_label)

	_ndi_toggle = CheckBox.new()
	_ndi_toggle.position = Vector2(130, 32)
	_ndi_toggle.size = Vector2(24, 24)
	_ndi_toggle.toggled.connect(_on_ndi_toggle)
	_ndi_section.add_child(_ndi_toggle)

	# Width preset
	var width_label = Label.new()
	width_label.position = Vector2(0, 58)
	width_label.text = "width"
	_ndi_section.add_child(width_label)

	_ndi_width_option = OptionButton.new()
	_ndi_width_option.position = Vector2(77, 58)
	_ndi_width_option.size = Vector2(100, 26)
	_ndi_width_option.add_item("512", 0)
	_ndi_width_option.add_item("720", 1)
	_ndi_width_option.add_item("1080", 2)
	_ndi_width_option.add_item("1920", 3)
	_ndi_width_option.item_selected.connect(_on_ndi_width_selected)
	_ndi_section.add_child(_ndi_width_option)

	# Mode selector
	var mode_label = Label.new()
	mode_label.position = Vector2(195, 58)
	mode_label.text = "mode"
	_ndi_section.add_child(mode_label)

	_ndi_mode_option = OptionButton.new()
	_ndi_mode_option.position = Vector2(240, 58)
	_ndi_mode_option.size = Vector2(110, 26)
	_ndi_mode_option.add_item("auto", 0)
	_ndi_mode_option.add_item("manual", 1)
	_ndi_mode_option.item_selected.connect(_on_ndi_mode_selected)
	_ndi_section.add_child(_ndi_mode_option)

	# Manual resolution inputs
	_ndi_manual_container = HBoxContainer.new()
	_ndi_manual_container.position = Vector2(0, 90)
	_ndi_manual_container.visible = false
	_ndi_section.add_child(_ndi_manual_container)

	var mw_label = Label.new()
	mw_label.text = "w:"
	_ndi_manual_container.add_child(mw_label)

	_ndi_manual_w = SpinBox.new()
	_ndi_manual_w.min_value = 128
	_ndi_manual_w.max_value = 3840
	_ndi_manual_w.step = 1
	_ndi_manual_w.custom_minimum_size = Vector2(80, 0)
	_ndi_manual_w.value_changed.connect(_on_ndi_manual_size_changed)
	_ndi_manual_container.add_child(_ndi_manual_w)

	var mh_label = Label.new()
	mh_label.text = "  h:"
	_ndi_manual_container.add_child(mh_label)

	_ndi_manual_h = SpinBox.new()
	_ndi_manual_h.min_value = 128
	_ndi_manual_h.max_value = 3840
	_ndi_manual_h.step = 1
	_ndi_manual_h.custom_minimum_size = Vector2(80, 0)
	_ndi_manual_h.value_changed.connect(_on_ndi_manual_size_changed)
	_ndi_manual_container.add_child(_ndi_manual_h)

func _update_ndi_ui():
	if _ndi_section == null:
		return

	var ndi = Global.main.ndi_manager
	if ndi == null:
		return

	var plugin_ok = ndi.is_plugin_available()

	if !plugin_ok:
		_ndi_status_label.text = "(plugin not installed)"
		_ndi_toggle.disabled = true
		_ndi_toggle.button_pressed = false
		_ndi_width_option.disabled = true
		_ndi_mode_option.disabled = true
		return

	_ndi_status_label.text = ""
	_ndi_toggle.disabled = false
	_ndi_toggle.button_pressed = ndi.is_enabled()

	# Width preset
	var widths = [512, 720, 1080, 1920]
	var current_w = Saving.settings["ndiWidth"]
	var idx = widths.find(current_w)
	if idx >= 0:
		_ndi_width_option.selected = idx
	else:
		_ndi_width_option.selected = 0

	# Mode
	var mode = Saving.settings["ndiMode"]
	_ndi_mode_option.selected = 1 if mode == "manual" else 0
	_ndi_manual_container.visible = mode == "manual"

	if mode == "manual":
		_ndi_manual_w.value = Saving.settings["ndiManualWidth"]
		_ndi_manual_h.value = Saving.settings["ndiManualHeight"]

	var enabled = ndi.is_enabled()
	_ndi_width_option.disabled = !enabled
	_ndi_mode_option.disabled = !enabled

func _on_ndi_toggle(pressed: bool):
	var ndi = Global.main.ndi_manager
	if ndi == null:
		return
	ndi.set_enabled(pressed)
	_update_ndi_ui()
	# Update ruler visibility
	if Global.main.editMode:
		ndi.set_ruler_visible(pressed)
	# Refresh window transparency (NDI disables it for performance)
	Global.main.updateWindowTransparency()
	if pressed:
		Global.pushUpdate("NDI output enabled.")
	else:
		Global.pushUpdate("NDI output disabled.")

func _on_ndi_width_selected(idx: int):
	var widths = [512, 720, 1080, 1920]
	if idx < widths.size():
		var ndi = Global.main.ndi_manager
		if ndi:
			ndi.set_width(widths[idx])
		Global.pushUpdate("NDI width set to " + str(widths[idx]) + ".")

func _on_ndi_mode_selected(idx: int):
	var mode = "auto" if idx == 0 else "manual"
	var ndi = Global.main.ndi_manager
	if ndi:
		ndi.set_mode(mode)
	_ndi_manual_container.visible = mode == "manual"
	Global.pushUpdate("NDI mode set to " + mode + ".")

func _on_ndi_manual_size_changed(_value: float):
	var ndi = Global.main.ndi_manager
	if ndi and _ndi_manual_w and _ndi_manual_h:
		ndi.set_manual_size(int(_ndi_manual_w.value), int(_ndi_manual_h.value))
