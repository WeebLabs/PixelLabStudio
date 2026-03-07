extends Control

var micName = ""
var _active_dot: Label

func _ready():
	_active_dot = Label.new()
	_active_dot.text = "\u25CF"
	_active_dot.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	_active_dot.add_theme_font_size_override("font_size", 22)
	_active_dot.position = Vector2(273, 10)
	_active_dot.visible = false
	add_child(_active_dot)

	var display_name = micName
	if display_name.length() > 30:
		display_name = display_name.left(27) + "..."
	$Label.text = display_name
	if micName == AudioServer.input_device:
		_active_dot.visible = true


func _on_button_pressed():
	
	if !get_parent().get_parent().get_parent().visible:
		return
	
	AudioServer.input_device = micName
	Saving.settings["audioDevice"] = micName
	Global.deleteAllMics()
	Global.currentMicrophone = null

	Global.get_tree().create_timer(1.0).timeout.connect(Global.createMicrophone)

	get_parent().get_parent().get_parent().showMicMenu()
	
	
