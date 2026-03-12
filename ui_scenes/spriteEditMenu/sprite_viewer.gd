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

# Normal map section
var _normal_section: Control
var _normal_status: Label
var _normal_import_btn: Button
var _normal_clear_btn: Button
var _normal_dialog: FileDialog

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
	# Pull Wobble and Rotational Limits up to sit just below checkboxes
	for node in [$WobbleControl, $RotationalLimits]:
		node.position.y -= 83
	# Increase spacing after section dividers
	for node in [$Animation, $Slider, $Rotation, $Buttons, $WobbleControl, $RotationalLimits]:
		node.position.y += 8
	for node in [$WobbleControl, $RotationalLimits]:
		node.position.y += 8
	$RotationalLimits.position.y += 8

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
	var ndi_ref_check = CheckBox.new()
	ndi_ref_check.name = "NdiRefLayer"
	ndi_ref_check.text = "NDI reference layer"
	ndi_ref_check.add_theme_font_size_override("font_size", 12)
	ndi_ref_check.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	$Buttons.add_child(ndi_ref_check)
	ndi_ref_check.toggled.connect(_on_ndi_ref_layer_toggled)

	_buttons = [
		$Buttons/Speaking/speaking, $Buttons/Blinking/blinking,
		$Buttons/Trash/trash, $Buttons/Unlink/unlink,
		$Buttons/CheckBox, $Buttons/ClipLinked, ndi_ref_check,
	]
	# Sections to dim when no sprite is selected
	_sections = [
		_preview,
		$Position, $Buttons, $Slider, $WobbleControl,
		$Rotation, $RotationalLimits, $Animation,
	]
	$WobbleControl/xAmp.max_value = 512.0
	$WobbleControl/yAmp.max_value = 512.0

	_set_controls_enabled(false)
	setImage()

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

	# Normal Map section — below preview, above Position
	var _nrml_y = 133
	_normal_section = Control.new()
	_normal_section.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_normal_section)

	_normal_status = Label.new()
	_normal_status.text = "(none)"
	_normal_status.add_theme_font_size_override("font_size", 11)
	_normal_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_normal_status.position = Vector2(10, _nrml_y)
	_normal_status.size = Vector2(panel_width - 100, 20)
	_normal_status.clip_text = true
	_normal_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_normal_status)

	_normal_import_btn = Button.new()
	_normal_import_btn.text = "Normal"
	_normal_import_btn.custom_minimum_size = Vector2(70, 22)
	_normal_import_btn.position = Vector2(panel_width - 155, _nrml_y - 1)
	_normal_import_btn.add_theme_font_size_override("font_size", 11)
	_normal_import_btn.pressed.connect(_on_normal_import)
	add_child(_normal_import_btn)

	_normal_clear_btn = Button.new()
	_normal_clear_btn.text = "Clear"
	_normal_clear_btn.custom_minimum_size = Vector2(60, 22)
	_normal_clear_btn.position = Vector2(panel_width - 80, _nrml_y - 1)
	_normal_clear_btn.add_theme_font_size_override("font_size", 11)
	_normal_clear_btn.disabled = true
	_normal_clear_btn.pressed.connect(_on_normal_clear)
	add_child(_normal_clear_btn)

	_sections.append(_normal_section)
	_sections.append(_normal_status)
	_buttons.append(_normal_import_btn)
	_buttons.append(_normal_clear_btn)

	# Push everything below preview down to make room for normal row
	var _nrml_shift = 26
	for node in [$Position, $Animation, $Slider, $Rotation, $Buttons, $WobbleControl, $RotationalLimits]:
		node.position.y += _nrml_shift

	# Add section dividers
	_create_divider(141 + _nrml_shift)   # between Normal row and Position Info
	_create_divider(274 + _nrml_shift)   # between Position Info and Animation
	_create_divider(564 + _nrml_shift)   # between Buttons/Checkboxes and Wobble
	_create_divider(773 + _nrml_shift)   # between Wobble and Rotational Limits circle

	_replace_rot_display_textures()

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
	
func _replace_rot_display_textures():
	var size = 260
	var cx = 130.0
	var cy = 130.0
	var radius = 105.0
	var fill_color = Color(0.18, 0.18, 0.18)
	var border_color = Color(0.4, 0.4, 0.4, 0.6)
	var border_width = 2.0

	# Dark grey filled circle with clean border for RotBack
	var back_img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	for x in range(size):
		for y in range(size):
			var dist = Vector2(x, y).distance_to(Vector2(cx, cy))
			if dist <= radius - border_width:
				back_img.set_pixel(x, y, fill_color)
			elif dist <= radius:
				back_img.set_pixel(x, y, border_color)
	$RotationalLimits/RotBack.texture = ImageTexture.create_from_image(back_img)

	# Clean thin line for rotation markers (spans from center to circle edge)
	var line_w = int(radius)
	var line_h = 4
	var line_img = Image.create(line_w, line_h, false, Image.FORMAT_RGBA8)
	var line_color = Color(0.75, 0.75, 0.8, 0.6)
	for x in range(line_w):
		line_img.set_pixel(x, 1, line_color)
		line_img.set_pixel(x, 2, line_color)
	var line_tex = ImageTexture.create_from_image(line_img)
	var pointer_img = Image.create(line_w, line_h, false, Image.FORMAT_RGBA8)
	var pointer_color = Color(0.85, 0.85, 0.9, 0.9)
	for x in range(line_w):
		pointer_img.set_pixel(x, 1, pointer_color)
		pointer_img.set_pixel(x, 2, pointer_color)
	var pointer_tex = ImageTexture.create_from_image(pointer_img)
	for node in [$RotationalLimits/RotBack/RotLineDisplay,
				$RotationalLimits/RotBack/RotLineDisplay2]:
		node.texture = line_tex
		node.offset = Vector2(radius / 2.0, 0)
	$RotationalLimits/RotBack/RotLineDisplay3.texture = pointer_tex
	$RotationalLimits/RotBack/RotLineDisplay3.offset = Vector2(radius / 2.0, 0)

	# Reorder children: fill → lines → sprite → dot (later = on top)
	var rot_back = $RotationalLimits/RotBack
	rot_back.move_child($RotationalLimits/RotBack/rotLimitBar, 0)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay, 1)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay2, 2)
	rot_back.move_child($RotationalLimits/RotBack/RotLineDisplay3, 3)
	rot_back.move_child($RotationalLimits/RotBack/SpriteDisplay, 4)
	# White dot to indicate origin point
	var dot_size = 8
	var dot_img = Image.create(dot_size, dot_size, false, Image.FORMAT_RGBA8)
	var dot_center = dot_size / 2.0
	for x in range(dot_size):
		for y in range(dot_size):
			if Vector2(x, y).distance_to(Vector2(dot_center, dot_center)) <= dot_center:
				dot_img.set_pixel(x, y, Color(1, 1, 1))
	var origin_dot = Sprite2D.new()
	origin_dot.texture = ImageTexture.create_from_image(dot_img)
	rot_back.add_child(origin_dot)
	$RotationalLimits/RotBack/SpriteDisplay.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay2.position = Vector2.ZERO
	$RotationalLimits/RotBack/RotLineDisplay3.position = Vector2.ZERO
	# Resize rotLimitBar to fill circle radius, change to light blue
	var bar = $RotationalLimits/RotBack/rotLimitBar
	var bar_size = int(radius) * 2
	var fill_img = Image.create(bar_size, bar_size, false, Image.FORMAT_RGBA8)
	fill_img.fill(Color(0.55, 0.78, 1.0))
	bar.texture_progress = ImageTexture.create_from_image(fill_img)
	bar.offset_left = -radius
	bar.offset_top = -radius
	bar.offset_right = radius
	bar.offset_bottom = radius
	bar.pivot_offset = Vector2(radius, radius)

	# Move circle up to reduce gap with previous section
	$RotationalLimits/RotBack.position.y = 698
	$RotationalLimits/RotBorder.position.y = 698

	# Move labels and sliders below the circle
	var controls_top = 698 + radius + 20
	$RotationalLimits/RotLimitMin.offset_top = controls_top
	$RotationalLimits/RotLimitMin.offset_bottom = controls_top + 26
	$RotationalLimits/rotLimitMin.offset_top = controls_top + 24
	$RotationalLimits/rotLimitMin.offset_bottom = controls_top + 44
	$RotationalLimits/RotLimitMax.offset_top = controls_top + 49
	$RotationalLimits/RotLimitMax.offset_bottom = controls_top + 75
	$RotationalLimits/rotLimitMax.offset_top = controls_top + 73
	$RotationalLimits/rotLimitMax.offset_bottom = controls_top + 93

func setImage():
	if Global.heldSprite == null:
		_preview.texture = null
		_parent_label.text = ""
		$Position/Label.text = ""
		$Position/Label2.text = ""
		$Position/Label3.text = ""
		$Slider/Label.text = ""
		spriteRotDisplay.texture = null
		spriteRotDisplay.rotation_degrees = 0
		$RotationalLimits/RotBack/RotLineDisplay3.rotation_degrees = 0
		$RotationalLimits/rotLimitMin.set_value_no_signal(-180)
		$RotationalLimits/rotLimitMax.set_value_no_signal(180)
		$RotationalLimits/RotLimitMin.text = "rotational limit min: -180"
		$RotationalLimits/RotLimitMax.text = "rotational limit max: 180"
		$RotationalLimits/RotBack/rotLimitBar.value = 360
		$RotationalLimits/RotBack/rotLimitBar.rotation_degrees = -180 + 90
		$RotationalLimits/RotBack/RotLineDisplay.rotation_degrees = -180
		$RotationalLimits/RotBack/RotLineDisplay2.rotation_degrees = 180
		_update_normal_display()
		return

	# Crop to opaque content of the first frame so the sprite fills the preview
	var img = Global.heldSprite.imageData
	var img_size = img.get_size()
	var frame_w = int(img_size.x / Global.heldSprite.frames)
	var frame_h = int(img_size.y)

	# Find bounding rect of non-transparent pixels in first frame (native C++)
	var used: Rect2i
	if Global.heldSprite.frames <= 1:
		used = img.get_used_rect()
	else:
		used = img.get_region(Rect2i(0, 0, frame_w, frame_h)).get_used_rect()

	if used.size.x > 0 and used.size.y > 0:
		var content_rect = Rect2(used)
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
	# Scale so opaque area occupies 50% of circle radius
	var rot_img = Global.heldSprite.imageData
	var rot_used = rot_img.get_used_rect()
	var target_size = 105.0  # 50% of radius (105) = 52.5 per side from center
	if rot_used.size.x > 0 and rot_used.size.y > 0:
		var rot_scale = target_size / max(rot_used.size.x, rot_used.size.y)
		spriteRotDisplay.scale = Vector2(rot_scale, rot_scale)
	else:
		spriteRotDisplay.scale = Vector2(1, 1) * (target_size / rot_img.get_size().y)

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
	$Buttons/NdiRefLayer.set_pressed_no_signal(Global.heldSprite.ndiRefLayer)

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

	_update_normal_display()

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
	var bg_top = max(round(position.y) - 2, menu_bar_bottom)
	_bg.position = Vector2(-19, bg_top - round(position.y))
	_bg.size = Vector2(panel_width + 19, round(s.y) - bg_top)

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
	if s.y > 1200:
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
	var min_y = s.y - 1150
	position.y = clamp(position.y, min_y, top_y)
	get_viewport().set_input_as_handled()

func _process(delta):
	_apply_size()

	coverCollider.disabled = Global.heldSprite == null

	var should_enable = Global.heldSprite != null
	if should_enable != _controls_enabled:
		_set_controls_enabled(should_enable)
		if !should_enable:
			setImage()

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
	Global.main.ndi_mark_dirty()


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
	Global.main.ndi_mark_dirty()


func _on_r_drag_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$Rotation/rDragLabel.text = "rotational drag: " + str(value)
	Global.heldSprite.rdragStr = value
	Global.main.ndi_mark_dirty()


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
	Global.unlinkChildren(Global.heldSprite)
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
	Global.main.ndi_mark_dirty()

	changeRotLimit()

func _on_rot_limit_max_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$RotationalLimits/RotLimitMax.text = "rotational limit max: " + str(value)
	Global.heldSprite.rLimitMax = value
	Global.main.ndi_mark_dirty()

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

func _on_ndi_ref_layer_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	if button_pressed:
		for spr in get_tree().get_nodes_in_group("saved"):
			if spr != Global.heldSprite:
				spr.ndiRefLayer = false
	Global.heldSprite.ndiRefLayer = button_pressed
	Global.main.ndi_mark_dirty()

func _on_eye_track_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrack = button_pressed
	Global.main.ndi_mark_dirty()

func _on_eye_track_dist_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(value)
	Global.heldSprite.eyeTrackDistance = value
	Global.main.ndi_mark_dirty()

func _on_eye_track_speed_value_changed(value):
	if Global.heldSprite == null: return
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(value)
	Global.heldSprite.eyeTrackSpeed = value

func _on_eye_track_invert_toggled(button_pressed):
	if Global.heldSprite == null: return
	UndoManager.save_state()
	Global.heldSprite.eyeTrackInvert = button_pressed

func _update_normal_display():
	if _normal_status == null:
		return
	if Global.heldSprite == null or !Global.heldSprite.hasNormalMap():
		_normal_status.text = "(none)"
		_normal_clear_btn.disabled = true
	else:
		var nname = Global.heldSprite.normalPath.get_file()
		if nname == "":
			nname = "(embedded)"
		_normal_status.text = nname
		_normal_clear_btn.disabled = false

func _on_normal_import():
	if _normal_dialog == null:
		_normal_dialog = FileDialog.new()
		_normal_dialog.title = "Select Normal Map"
		_normal_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_normal_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_normal_dialog.filters = PackedStringArray(["*.png;PNG Image"])
		_normal_dialog.use_native_dialog = true
		_normal_dialog.file_selected.connect(_on_normal_file_selected)
		add_child(_normal_dialog)
	_normal_dialog.popup_centered(Vector2i(600, 400))

func _on_normal_file_selected(path: String):
	if Global.heldSprite == null:
		return
	var img = Image.new()
	if img.load(path) != OK:
		Global.pushUpdate("Failed to load normal map.")
		return
	UndoManager.save_state()
	Global.heldSprite.setNormalMap(img, path)
	UndoManager.invalidate_normal(Global.heldSprite.id)
	_update_normal_display()

func _on_normal_clear():
	if Global.heldSprite == null or !Global.heldSprite.hasNormalMap():
		return
	UndoManager.save_state()
	Global.heldSprite.clearNormalMap()
	UndoManager.invalidate_normal(Global.heldSprite.id)
	_update_normal_display()
