extends RefCounted

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const Form = preload("res://ui_scenes/common/form_ui.gd")

var _global: Node
var _saving: Node
var _device_list: VBoxContainer
var _mute_check: CheckBox


func build(body: VBoxContainer, global: Node, saving: Node) -> void:
	_global = global
	_saving = saving
	var input_group := Form.section(body, "Input device")
	_device_list = Form.column(input_group, 2)
	var behaviour := Form.section(body, "Behaviour")
	_mute_check = Form.check_row(behaviour, "Mute microphone")
	_mute_check.toggled.connect(_on_mute_toggled)


func refresh() -> void:
	for child in _device_list.get_children():
		child.queue_free()
	var devices := AudioServer.get_input_device_list()
	if devices.is_empty():
		var empty := Label.new()
		empty.text = "No input devices found."
		empty.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
		empty.add_theme_color_override("font_color", SidebarUIFactory.TEXT_DISABLED)
		_device_list.add_child(empty)
	for device in devices:
		_add_device_row(device)
	_mute_check.set_pressed_no_signal(_global.micMuted)


func _add_device_row(device: String) -> void:
	var active := device == AudioServer.input_device
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", Form.ROW_SEPARATION)
	_device_list.add_child(line)
	var marker := Label.new()
	marker.text = "●" if active else ""
	marker.custom_minimum_size = Vector2(12, 0)
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	marker.add_theme_color_override("font_color", SidebarUIFactory.SLIDER_FILL_ENABLED)
	line.add_child(marker)
	var pick := Button.new()
	pick.text = device
	pick.flat = true
	pick.focus_mode = Control.FOCUS_NONE
	pick.clip_text = true
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	pick.add_theme_color_override(
		"font_color", SidebarUIFactory.TEXT_HEADING if active else SidebarUIFactory.TEXT_BODY,
	)
	pick.add_theme_color_override("font_hover_color", Color.WHITE)
	pick.pressed.connect(_on_device_selected.bind(device))
	line.add_child(pick)


func _on_device_selected(device: String) -> void:
	if _global.selectMicrophone(device, 1.0):
		_saving.settings["audioDevice"] = device
	else:
		_global.notify_user("Microphone is no longer available.")
	refresh()


func _on_mute_toggled(pressed: bool) -> void:
	_global.micMuted = pressed
	_global.notify_user("Microphone muted." if pressed else "Microphone unmuted.")
