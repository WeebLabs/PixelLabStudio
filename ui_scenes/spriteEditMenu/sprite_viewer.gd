extends Node2D

#Node Reference
@onready var spriteRotDisplay = $RotationalLimits/RotBack/SpriteDisplay

var _preview: Sprite2D
var _parent_label: Label


@onready var coverCollider = $Area2D/CollisionShape2D

var _bg: ColorRect
var panel_width: float = 265
var panel_height: float = 630
var _controls_enabled: bool = false
var _sliders: Array = []
var _buttons: Array = []
var _sections: Array = []

var _slider_fill_enabled: StyleBoxFlat
var _slider_fill_disabled: StyleBoxFlat
var _slider_grabber_enabled: ImageTexture
var _slider_grabber_disabled: ImageTexture

func _ready():
	Global.spriteEdit = self
	$Buttons/Speaking.visible = false
	$Buttons/Blinking.visible = false
	$Buttons/Trash.visible = false
	$Buttons/Unlink.visible = false

	# Hide individual panel backgrounds to integrate into unified sidebar
	$Border.visible = false
	$WobbleControl/animationBox.visible = false
	$RotationalLimits/RotBorder.visible = false
	$VisToggle/setToggle/rect.visible = false

	# Hide 3D SubViewport previews — replaced by static 2D preview
	$SubViewportContainer.visible = false
	$SubViewportContainer2.visible = false

	# Create static 2D sprite preview
	_preview = Sprite2D.new()
	_preview.position = Vector2(123, 65)
	add_child(_preview)

	# Create parent label in the Position section (above position label)
	_parent_label = Label.new()
	_parent_label.offset_left = 10.0
	_parent_label.offset_top = 155.0
	_parent_label.offset_right = 236.0
	_parent_label.offset_bottom = 179.0
	_parent_label.text = "Root Element"
	$Position.add_child(_parent_label)

	# Shift position/offset/layer labels down for parent label
	$Position/Label.offset_top = 179.0
	$Position/Label.offset_bottom = 205.0
	$Position/Label2.offset_top = 203.0
	$Position/Label2.offset_bottom = 229.0
	$Position/Label3.offset_top = 225.0
	$Position/Label3.offset_bottom = 251.0

	# Shift all sections below Position down to accommodate parent label
	for node in [$Animation, $Slider, $Rotation, $Buttons, $WobbleControl, $RotationalLimits]:
		node.position.y += 24

	# Hide sections moved to right sidebar
	$Layers.visible = false
	$EyeTracking.visible = false
	$VisToggle.visible = false

	# Collect interactive controls for enable/disable toggling
	_sliders = [
		$Slider/DragSlider,
		$WobbleControl/xFrq, $WobbleControl/xAmp,
		$WobbleControl/yFrq, $WobbleControl/yAmp,
		$Rotation/rDrag, $Rotation/squash,
		$RotationalLimits/rotLimitMin, $RotationalLimits/rotLimitMax,
		$Animation/animSpeed, $Animation/animFrames,
	]
	_buttons = [
		$Buttons/Speaking/speaking, $Buttons/Blinking/blinking,
		$Buttons/Trash/trash, $Buttons/Unlink/unlink,
		$Buttons/CheckBox, $Buttons/ClipLinked,
	]
	# Sections to dim when no sprite is selected
	_sections = [
		_preview,
		$Position, $Buttons, $Slider, $WobbleControl,
		$Rotation, $RotationalLimits, $Animation,
	]
	_set_controls_enabled(false)

	# Build slider style resources (matching right sidebar)
	_slider_fill_enabled = StyleBoxFlat.new()
	_slider_fill_enabled.bg_color = Color(1.0, 0.7, 0.8)
	_slider_fill_disabled = StyleBoxFlat.new()
	_slider_fill_disabled.bg_color = Color(0.55, 0.4, 0.45)

	var grabber_img_on = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	grabber_img_on.fill(Color(0, 0, 0, 0))
	var grabber_img_off = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	grabber_img_off.fill(Color(0, 0, 0, 0))
	for px in range(16):
		for py in range(16):
			var dx = px - 8
			var dy = py - 8
			if dx * dx + dy * dy <= 36:
				grabber_img_on.set_pixel(px, py, Color(1.0, 1.0, 1.0, 1.0))
				grabber_img_off.set_pixel(px, py, Color(0.45, 0.45, 0.48, 1.0))
	_slider_grabber_enabled = ImageTexture.create_from_image(grabber_img_on)
	_slider_grabber_disabled = ImageTexture.create_from_image(grabber_img_off)

	for slider in _sliders:
		slider.theme = null
		slider.add_theme_stylebox_override("grabber_area", _slider_fill_enabled)
		slider.add_theme_stylebox_override("grabber_area_highlight", _slider_fill_enabled)
		slider.add_theme_icon_override("grabber", _slider_grabber_enabled)
		slider.add_theme_icon_override("grabber_highlight", _slider_grabber_enabled)
		slider.add_theme_icon_override("grabber_disabled", _slider_grabber_disabled)

	# Restyle labels to match right sidebar
	var _labels = [
		$Slider/Label,
		$WobbleControl/xFrqLabel, $WobbleControl/xAmpLabel,
		$WobbleControl/yFrqLabel, $WobbleControl/yAmpLabel,
		$Rotation/rDragLabel, $Rotation/squashlabel,
		$RotationalLimits/RotLimitMin, $RotationalLimits/RotLimitMax,
		$Animation/animFramesLabel, $Animation/animSpeedLabel,
		$Position/Label, $Position/Label2, $Position/Label3,
		_parent_label,
	]
	for label in _labels:
		label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		label.add_theme_font_size_override("font_size", 12)

	$Position/fileTitle.visible = false

	# Restyle checkboxes
	for cb in [$Buttons/CheckBox, $Buttons/ClipLinked]:
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))

	# Add section dividers
	_create_divider(141)   # between 3D Preview and Position Info
	_create_divider(274)   # between Position Info and Animation
	_create_divider(486)   # between Rotation and Buttons row
	_create_divider(639)   # between Buttons/Checkboxes and Wobble
	_create_divider(979)   # between Wobble and Rotational Limits

	# Create dark gray background panel
	_bg = ColorRect.new()
	_bg.color = Color(0.15, 0.15, 0.15)
	_bg.z_index = -1
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	move_child(_bg, 0)
	_apply_size()

func _set_controls_enabled(enabled: bool):
	_controls_enabled = enabled
	var dim = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.35)
	for section in _sections:
		section.modulate = dim
	for slider in _sliders:
		slider.editable = enabled
	for button in _buttons:
		button.disabled = !enabled
	var fill = _slider_fill_enabled if enabled else _slider_fill_disabled
	var grab = _slider_grabber_enabled if enabled else _slider_grabber_disabled
	for slider in _sliders:
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
		slider.add_theme_icon_override("grabber", grab)
		slider.add_theme_icon_override("grabber_highlight", grab)
	
func setImage():
	if Global.heldSprite == null:
		return

	# Crop to opaque content of the first frame so the sprite fills the preview
	var img = Global.heldSprite.imageData
	var img_size = img.get_size()
	var frame_w = int(img_size.x / Global.heldSprite.frames)
	var frame_h = int(img_size.y)

	# Find bounding rect of non-transparent pixels in first frame
	var min_x = frame_w
	var min_y = frame_h
	var max_x = 0
	var max_y = 0
	for py in range(frame_h):
		for px in range(frame_w):
			if img.get_pixel(px, py).a > 0.01:
				min_x = min(min_x, px)
				min_y = min(min_y, py)
				max_x = max(max_x, px)
				max_y = max(max_y, py)

	if max_x >= min_x and max_y >= min_y:
		var content_rect = Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
		var atlas = AtlasTexture.new()
		atlas.atlas = Global.heldSprite.tex
		atlas.region = content_rect
		_preview.texture = atlas
		_preview.hframes = 1
		var preview_scale = min(240.0 / content_rect.size.x, 120.0 / content_rect.size.y)
		_preview.scale = Vector2(preview_scale, preview_scale)
	else:
		_preview.texture = Global.heldSprite.tex
		_preview.hframes = Global.heldSprite.frames
		var preview_scale = min(240.0 / frame_w, 120.0 / frame_h)
		_preview.scale = Vector2(preview_scale, preview_scale)

	# Update parent label
	if Global.heldSprite.parentId != null:
		var nodes = get_tree().get_nodes_in_group(str(Global.heldSprite.parentId))
		if nodes.size() > 0:
			var count = nodes[0].path.get_slice_count("/") - 1
			_parent_label.text = "Parent: " + nodes[0].path.get_slice("/", count)
		else:
			_parent_label.text = "Root Element"
	else:
		_parent_label.text = "Root Element"

	spriteRotDisplay.texture = Global.heldSprite.tex
	spriteRotDisplay.offset = Global.heldSprite.offset
	var displaySize = Global.heldSprite.imageData.get_size().y
	spriteRotDisplay.scale = Vector2(1,1) * (150.0/displaySize)

	$Slider/Label.text = "drag: " + str(Global.heldSprite.dragSpeed)
	$Slider/DragSlider.set_value_no_signal(Global.heldSprite.dragSpeed)

	$WobbleControl/xFrqLabel.text = "x frequency: " + str(Global.heldSprite.xFrq)
	$WobbleControl/xAmpLabel.text = "x amplitude: " + str(Global.heldSprite.xAmp)

	$WobbleControl/xFrq.set_value_no_signal(Global.heldSprite.xFrq)
	$WobbleControl/xAmp.set_value_no_signal(Global.heldSprite.xAmp)

	$WobbleControl/yFrqLabel.text = "y frequency: " + str(Global.heldSprite.yFrq)
	$WobbleControl/yAmpLabel.text = "y amplitude: " + str(Global.heldSprite.yAmp)

	$WobbleControl/yFrq.set_value_no_signal(Global.heldSprite.yFrq)
	$WobbleControl/yAmp.set_value_no_signal(Global.heldSprite.yAmp)

	$Rotation/rDragLabel.text = "rotational drag: " + str(Global.heldSprite.rdragStr)
	$Rotation/rDrag.set_value_no_signal(Global.heldSprite.rdragStr)

	$Buttons/Speaking.frame = Global.heldSprite.showOnTalk
	$Buttons/Blinking.frame = Global.heldSprite.showOnBlink

	$RotationalLimits/rotLimitMin.set_value_no_signal(Global.heldSprite.rLimitMin)
	$RotationalLimits/RotLimitMin.text = "rotational limit min: " + str(Global.heldSprite.rLimitMin)
	$RotationalLimits/rotLimitMax.set_value_no_signal(Global.heldSprite.rLimitMax)
	$RotationalLimits/RotLimitMax.text = "rotational limit max: " + str(Global.heldSprite.rLimitMax)

	$Rotation/squashlabel.text = "squash: " + str(Global.heldSprite.stretchAmount)
	$Rotation/squash.set_value_no_signal(Global.heldSprite.stretchAmount)

	$Buttons/CheckBox.set_pressed_no_signal(Global.heldSprite.ignoreBounce)
	$Buttons/ClipLinked.set_pressed_no_signal(Global.heldSprite.clipped)

	$Animation/animSpeedLabel.text = "animation speed: " + str(Global.heldSprite.animSpeed)
	$Animation/animSpeed.set_value_no_signal(Global.heldSprite.animSpeed)

	$Animation/animFramesLabel.text = "sprite frames: " + str(Global.heldSprite.frames)
	$Animation/animFrames.set_value_no_signal(Global.heldSprite.frames)

	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""

	$EyeTracking/EyeTrackToggle.set_pressed_no_signal(Global.heldSprite.eyeTrack)
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(Global.heldSprite.eyeTrackDistance)
	$EyeTracking/eyeTrackDist.set_value_no_signal(Global.heldSprite.eyeTrackDistance)
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(Global.heldSprite.eyeTrackSpeed)
	$EyeTracking/eyeTrackSpeed.set_value_no_signal(Global.heldSprite.eyeTrackSpeed)
	$EyeTracking/EyeTrackInvert.set_pressed_no_signal(Global.heldSprite.eyeTrackInvert)

	changeRotLimit()

	setLayerButtons()

	if Global.spriteList:
		Global.spriteList.updateControls()
		Global.spriteList.scroll_to_selected()

	
func _create_divider(y_pos: float) -> ColorRect:
	var div = ColorRect.new()
	div.color = Color(0.3, 0.3, 0.35)
	div.size = Vector2(panel_width - 16, 1)
	div.position = Vector2(8, y_pos)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(div)
	return div

func _apply_size():
	var s = get_viewport().get_visible_rect().size
	panel_height = s.y
	# Clamp bg top to menu bar bottom so it never overlaps the menu bar
	var menu_bar_bottom = 28  # MENU_BAR_HEIGHT
	var bg_top = max(position.y - 2, menu_bar_bottom)
	_bg.position = Vector2(-19, bg_top - position.y)
	_bg.size = Vector2(panel_width + 19, s.y - bg_top)

func _input(event):
	if Global.main == null or !Global.main.editMode or !visible:
		return
	if !(event is InputEventMouseButton and event.pressed):
		return
	# Only handle when cursor is over the sidebar (use viewport coords)
	if event.position.x > panel_width + 19:
		return
	# Only scroll when window is short enough to need it
	var s = get_viewport().get_visible_rect().size
	if s.y > 1174:
		return
	var step = 50
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		position.y += step
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		position.y -= step
	else:
		return
	# Clamp to same bounds as moveSpriteMenu()
	var top_y = 30  # MENU_BAR_HEIGHT + 2
	var min_y = s.y - 1124
	position.y = clamp(position.y, min_y, top_y)
	get_viewport().set_input_as_handled()

func _process(delta):
	_apply_size()

	coverCollider.disabled = Global.heldSprite == null

	var should_enable = Global.heldSprite != null
	if should_enable != _controls_enabled:
		_set_controls_enabled(should_enable)

	if Global.heldSprite == null:
		return

	var obj = Global.heldSprite
	
	$Position/Label.text = "position     X : "+str(obj.position.x)+"     Y: " + str(obj.position.y)
	$Position/Label2.text = "offset         X : "+str(obj.offset.x)+"     Y: " + str(obj.offset.y)
	$Position/Label3.text = "layer : "+str(obj.z)
	
	#Sprite Rotational Limit Display
		
	var size = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	var minimum = Global.heldSprite.rLimitMin
		
	spriteRotDisplay.rotation_degrees = sin(Global.animationTick*0.05)*(size/2.0)+(minimum+(size/2.0))
	$RotationalLimits/RotBack/RotLineDisplay3.rotation_degrees = spriteRotDisplay.rotation_degrees


func _on_drag_slider_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Slider/Label.text = "drag: " + str(value)
	Global.heldSprite.dragSpeed = value


func _on_x_frq_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$WobbleControl/xFrqLabel.text = "x frequency: " + str(value)
	Global.heldSprite.xFrq = value


func _on_x_amp_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$WobbleControl/xAmpLabel.text = "x amplitude: " + str(value)
	Global.heldSprite.xAmp = value


func _on_y_frq_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$WobbleControl/yFrqLabel.text = "y frequency: " + str(value)
	Global.heldSprite.yFrq = value

func _on_y_amp_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$WobbleControl/yAmpLabel.text = "y amplitude: " + str(value)
	Global.heldSprite.yAmp = value


func _on_r_drag_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Rotation/rDragLabel.text = "rotational drag: " + str(value)
	Global.heldSprite.rdragStr = value


func _on_speaking_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	var f = $Buttons/Speaking.frame
	f = (f+1) % 3

	$Buttons/Speaking.frame = f
	Global.heldSprite.showOnTalk = f


func _on_blinking_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	var f = $Buttons/Blinking.frame
	f = (f+1) % 4

	$Buttons/Blinking.frame = f
	Global.heldSprite.showOnBlink = f


func _on_trash_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.queue_free()
	Global.heldSprite = null

	Global.spriteList.updateData()

func _on_unlink_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	if Global.heldSprite.parentId == null:
		return
	Global.unlinkSprite()
	setImage()


func _on_rot_limit_min_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$RotationalLimits/RotLimitMin.text = "rotational limit min: " + str(value)
	Global.heldSprite.rLimitMin = value

	changeRotLimit()

func _on_rot_limit_max_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$RotationalLimits/RotLimitMax.text = "rotational limit max: " + str(value)
	Global.heldSprite.rLimitMax = value

	changeRotLimit()

func changeRotLimit():
	if Global.heldSprite == null: return
	$RotationalLimits/RotBack/rotLimitBar.value = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/rotLimitBar.rotation_degrees = Global.heldSprite.rLimitMin + 90

	$RotationalLimits/RotBack/RotLineDisplay.rotation_degrees = Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/RotLineDisplay2.rotation_degrees = Global.heldSprite.rLimitMax

func setLayerButtons():
	if Global.heldSprite == null: return
	var a = Global.heldSprite.costumeLayers.duplicate()
	
	var active_mod = Color(1, 1, 1, 1)
	var inactive_mod = Color(0.5, 0.5, 0.5, 0.7)
	$Layers/Layer1.self_modulate = active_mod if a[0] == 1 else inactive_mod
	$Layers/Layer2.self_modulate = active_mod if a[1] == 1 else inactive_mod
	$Layers/Layer3.self_modulate = active_mod if a[2] == 1 else inactive_mod
	$Layers/Layer4.self_modulate = active_mod if a[3] == 1 else inactive_mod
	$Layers/Layer5.self_modulate = active_mod if a[4] == 1 else inactive_mod
	$Layers/Layer6.self_modulate = active_mod if a[5] == 1 else inactive_mod
	$Layers/Layer7.self_modulate = active_mod if a[6] == 1 else inactive_mod
	$Layers/Layer8.self_modulate = active_mod if a[7] == 1 else inactive_mod
	$Layers/Layer9.self_modulate = active_mod if a[8] == 1 else inactive_mod
	$Layers/Layer10.self_modulate = active_mod if a[9] == 1 else inactive_mod
	
	var nodes = get_tree().get_nodes_in_group("saved")
	for sprite in nodes:
		if sprite.costumeLayers[Global.main.costume - 1] == 1:
			sprite.visible = true
			sprite.changeCollision(true)
		else:
			sprite.visible = false
			sprite.changeCollision(false)
		


func _on_layer_button_1_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[0] == 0:
		Global.heldSprite.costumeLayers[0] = 1
	else:
		Global.heldSprite.costumeLayers[0] = 0
	setLayerButtons()


func _on_layer_button_2_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[1] == 0:
		Global.heldSprite.costumeLayers[1] = 1
	else:
		Global.heldSprite.costumeLayers[1] = 0
	setLayerButtons()


func _on_layer_button_3_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[2] == 0:
		Global.heldSprite.costumeLayers[2] = 1
	else:
		Global.heldSprite.costumeLayers[2] = 0
	setLayerButtons()


func _on_layer_button_4_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[3] == 0:
		Global.heldSprite.costumeLayers[3] = 1
	else:
		Global.heldSprite.costumeLayers[3] = 0
	setLayerButtons()


func _on_layer_button_5_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[4] == 0:
		Global.heldSprite.costumeLayers[4] = 1
	else:
		Global.heldSprite.costumeLayers[4] = 0
	setLayerButtons()

func _on_layer_button_6_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[5] == 0:
		Global.heldSprite.costumeLayers[5] = 1
	else:
		Global.heldSprite.costumeLayers[5] = 0
	setLayerButtons()

func _on_layer_button_7_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[6] == 0:
		Global.heldSprite.costumeLayers[6] = 1
	else:
		Global.heldSprite.costumeLayers[6] = 0
	setLayerButtons()

func _on_layer_button_8_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[7] == 0:
		Global.heldSprite.costumeLayers[7] = 1
	else:
		Global.heldSprite.costumeLayers[7] = 0
	setLayerButtons()

func _on_layer_button_9_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[8] == 0:
		Global.heldSprite.costumeLayers[8] = 1
	else:
		Global.heldSprite.costumeLayers[8] = 0
	setLayerButtons()

func _on_layer_button_10_pressed():
	UndoManager.save_state()
	if Global.heldSprite.costumeLayers[9] == 0:
		Global.heldSprite.costumeLayers[9] = 1
	else:
		Global.heldSprite.costumeLayers[9] = 0
	setLayerButtons()

func layerSelected():
	var newPos = Vector2.ZERO
	match Global.main.costume:
		1:
			newPos = $Layers/Layer1.position
		2:
			newPos = $Layers/Layer2.position
		3:
			newPos = $Layers/Layer3.position
		4:
			newPos = $Layers/Layer4.position
		5:
			newPos = $Layers/Layer5.position
		6:
			newPos = $Layers/Layer6.position
		7:
			newPos = $Layers/Layer7.position
		8:
			newPos = $Layers/Layer8.position
		9:
			newPos = $Layers/Layer9.position
		10:
			newPos = $Layers/Layer10.position
	$Layers/Select.position = newPos


func _on_squash_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Rotation/squashlabel.text = "squash: " + str(value)
	Global.heldSprite.stretchAmount = value


func _on_check_box_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.ignoreBounce = button_pressed


func _on_anim_speed_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Animation/animSpeedLabel.text = "animation speed: " + str(value)
	Global.heldSprite.animSpeed = value

func _on_anim_frames_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Animation/animFramesLabel.text = "sprite frames: " + str(value)
	Global.heldSprite.frames = value
	Global.heldSprite.changeFrames()
	setImage()


func _on_clip_linked_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.setClip(button_pressed)


func _on_delete_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.toggle = "null"
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""
	Global.heldSprite.makeVis()

func _on_set_toggle_pressed():
	if Global.heldSprite == null: return
	UndoManager.save_state()
	$VisToggle/setToggle/Label.text = "toggle: AWAITING INPUT"
	Global.awaitingToggleBind = true
	await Global.main.fatfuckingballs

	var keys = await Global.main.spriteVisToggles
	Global.awaitingToggleBind = false
	var key = keys[0]
	if Global.heldSprite == null: return
	Global.heldSprite.toggle = key
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""

func _on_eye_track_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrack = button_pressed

func _on_eye_track_dist_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(value)
	Global.heldSprite.eyeTrackDistance = value

func _on_eye_track_speed_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(value)
	Global.heldSprite.eyeTrackSpeed = value

func _on_eye_track_invert_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrackInvert = button_pressed
