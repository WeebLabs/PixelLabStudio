extends Node2D

#Node Reference
@onready var spriteSpin = $SubViewportContainer/SubViewport/Node3D/Sprite3D

@onready var parentSpin = $SubViewportContainer2/SubViewport/Node3D/Sprite3D

@onready var spriteRotDisplay = $RotationalLimits/RotBack/SpriteDisplay


@onready var coverCollider = $Area2D/CollisionShape2D


func _ready():
	Global.spriteEdit = self
	$Buttons/Speaking.visible = false
	$Buttons/Blinking.visible = false
	$Buttons/Trash.visible = false
	$Buttons/Unlink.visible = false
	
func setImage():
	if Global.heldSprite == null:
		return

	spriteSpin.texture = Global.heldSprite.tex
	spriteSpin.pixel_size = 1.5 / Global.heldSprite.imageData.get_size().y
	spriteSpin.hframes = Global.heldSprite.frames

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

	$Position/fileTitle.text = Global.heldSprite.path

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

	if Global.heldSprite.parentId == null:
		parentSpin.visible = false
	else:
		var nodes = get_tree().get_nodes_in_group(str(Global.heldSprite.parentId))

		if nodes.size()<=0:
			return

		parentSpin.texture = nodes[0].tex
		parentSpin.pixel_size = 1.5 / nodes[0].imageData.get_size().y
		parentSpin.hframes = nodes[0].frames
		parentSpin.visible = true
	
func _process(delta):

	coverCollider.disabled = Global.heldSprite == null

	if Global.heldSprite == null:
		return

	var obj = Global.heldSprite
	spriteSpin.rotate_y(delta*4.0)
	parentSpin.rotate_y(delta*4.0)
	
	$Position/Label.text = "position     X : "+str(obj.position.x)+"     Y: " + str(obj.position.y)
	$Position/Label2.text = "offset         X : "+str(obj.offset.x)+"     Y: " + str(obj.offset.y)
	$Position/Label3.text = "layer : "+str(obj.z)
	
	#Sprite Rotational Limit Display
		
	var size = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	var minimum = Global.heldSprite.rLimitMin
		
	spriteRotDisplay.rotation_degrees = sin(Global.animationTick*0.05)*(size/2.0)+(minimum+(size/2.0))
	$RotationalLimits/RotBack/RotLineDisplay3.rotation_degrees = spriteRotDisplay.rotation_degrees


func _on_drag_slider_value_changed(value):
	UndoManager.save_state_continuous()
	if Global.heldSprite != null:
		$Slider/Label.text = "drag: " + str(value)
		Global.heldSprite.dragSpeed = value


func _on_x_frq_value_changed(value):
	UndoManager.save_state_continuous()
	$WobbleControl/xFrqLabel.text = "x frequency: " + str(value)
	Global.heldSprite.xFrq = value
	

func _on_x_amp_value_changed(value):
	UndoManager.save_state_continuous()
	$WobbleControl/xAmpLabel.text = "x amplitude: " + str(value)
	Global.heldSprite.xAmp = value


func _on_y_frq_value_changed(value):
	UndoManager.save_state_continuous()
	$WobbleControl/yFrqLabel.text = "y frequency: " + str(value)
	Global.heldSprite.yFrq = value

func _on_y_amp_value_changed(value):
	UndoManager.save_state_continuous()
	$WobbleControl/yAmpLabel.text = "y amplitude: " + str(value)
	Global.heldSprite.yAmp = value


func _on_r_drag_value_changed(value):
	UndoManager.save_state_continuous()
	$Rotation/rDragLabel.text = "rotational drag: " + str(value)
	Global.heldSprite.rdragStr = value


func _on_speaking_pressed():
	UndoManager.save_state()
	var f = $Buttons/Speaking.frame
	f = (f+1) % 3
	
	$Buttons/Speaking.frame = f
	Global.heldSprite.showOnTalk = f


func _on_blinking_pressed():
	UndoManager.save_state()
	var f = $Buttons/Blinking.frame
	f = (f+1) % 4

	$Buttons/Blinking.frame = f
	Global.heldSprite.showOnBlink = f


func _on_trash_pressed():
	UndoManager.save_state()
	Global.heldSprite.queue_free()
	Global.heldSprite = null
	
	Global.spriteList.updateData()

func _on_unlink_pressed():
	UndoManager.save_state()
	if Global.heldSprite.parentId == null:
		return
	Global.unlinkSprite()
	setImage()
	

func _on_rot_limit_min_value_changed(value):
	UndoManager.save_state_continuous()
	$RotationalLimits/RotLimitMin.text = "rotational limit min: " + str(value)
	Global.heldSprite.rLimitMin = value
	
	changeRotLimit()

func _on_rot_limit_max_value_changed(value):
	UndoManager.save_state_continuous()
	$RotationalLimits/RotLimitMax.text = "rotational limit max: " + str(value)
	Global.heldSprite.rLimitMax = value
	
	changeRotLimit()

func changeRotLimit():
	$RotationalLimits/RotBack/rotLimitBar.value = Global.heldSprite.rLimitMax - Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/rotLimitBar.rotation_degrees = Global.heldSprite.rLimitMin + 90
	
	$RotationalLimits/RotBack/RotLineDisplay.rotation_degrees = Global.heldSprite.rLimitMin
	$RotationalLimits/RotBack/RotLineDisplay2.rotation_degrees = Global.heldSprite.rLimitMax

func setLayerButtons():
	var a = Global.heldSprite.costumeLayers.duplicate()
	
	$Layers/Layer1.frame = 1-a[0]
	$Layers/Layer2.frame = 1-a[1]
	$Layers/Layer3.frame = 1-a[2]
	$Layers/Layer4.frame = 1-a[3]
	$Layers/Layer5.frame = 1-a[4]
	$Layers/Layer6.frame = 1-a[5]
	$Layers/Layer7.frame = 1-a[6]
	$Layers/Layer8.frame = 1-a[7]
	$Layers/Layer9.frame = 1-a[8]
	$Layers/Layer10.frame = 1-a[9]
	
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
	UndoManager.save_state_continuous()
	$Rotation/squashlabel.text = "squash: " + str(value)
	Global.heldSprite.stretchAmount = value


func _on_check_box_toggled(button_pressed):
	UndoManager.save_state()
	Global.heldSprite.ignoreBounce = button_pressed


func _on_anim_speed_value_changed(value):
	UndoManager.save_state_continuous()
	$Animation/animSpeedLabel.text = "animation speed: " + str(value)
	Global.heldSprite.animSpeed = value

func _on_anim_frames_value_changed(value):
	UndoManager.save_state_continuous()
	$Animation/animFramesLabel.text = "sprite frames: " + str(value)
	Global.heldSprite.frames = value
	spriteSpin.hframes = Global.heldSprite.frames
	Global.heldSprite.changeFrames()


func _on_clip_linked_toggled(button_pressed):
	UndoManager.save_state()
	Global.heldSprite.setClip(button_pressed)


func _on_delete_pressed():
	UndoManager.save_state()
	Global.heldSprite.toggle = "null"
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""
	Global.heldSprite.makeVis()

func _on_set_toggle_pressed():
	UndoManager.save_state()
	$VisToggle/setToggle/Label.text = "toggle: AWAITING INPUT"
	await Global.main.fatfuckingballs

	var keys = await Global.main.spriteVisToggles
	var key = keys[0]
	Global.heldSprite.toggle = key
	$VisToggle/setToggle/Label.text = "toggle: \"" + Global.heldSprite.toggle +  "\""

func _on_eye_track_toggled(button_pressed):
	UndoManager.save_state()
	Global.heldSprite.eyeTrack = button_pressed

func _on_eye_track_dist_value_changed(value):
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackDistLabel.text = "tracking distance: " + str(value)
	Global.heldSprite.eyeTrackDistance = value

func _on_eye_track_speed_value_changed(value):
	UndoManager.save_state_continuous()
	$EyeTracking/eyeTrackSpeedLabel.text = "tracking speed: " + str(value)
	Global.heldSprite.eyeTrackSpeed = value

func _on_eye_track_invert_toggled(button_pressed):
	UndoManager.save_state()
	Global.heldSprite.eyeTrackInvert = button_pressed
