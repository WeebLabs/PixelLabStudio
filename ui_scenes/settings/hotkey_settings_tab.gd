extends RefCounted

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")
const Form = preload("res://ui_scenes/common/form_ui.gd")
const COSTUME_COUNT := 10

var awaiting_input := -1
var _global: Node
var _buttons: Array[Button] = []


func build(body: VBoxContainer, global: Node) -> void:
	_global = global
	var group := Form.section(body, "Costume hotkeys")
	for slot in range(1, COSTUME_COUNT + 1):
		var line := Form.row(group, "Costume %d" % slot)
		var bind := Button.new()
		bind.flat = true
		bind.focus_mode = Control.FOCUS_NONE
		bind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bind.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
		bind.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
		bind.add_theme_color_override("font_hover_color", Color.WHITE)
		Form.apply_field_style(bind)
		bind.pressed.connect(_on_rebind.bind(slot))
		line.add_child(bind)
		_buttons.append(bind)
		Form.button(line, "x", _on_cleared.bind(slot), true)


func refresh() -> void:
	for slot in range(1, COSTUME_COUNT + 1):
		_write_label(slot)


func _write_label(slot: int) -> void:
	_buttons[slot - 1].text = _global.main.costumeKeys[slot - 1]


func _on_rebind(slot: int) -> void:
	_buttons[slot - 1].text = "press a key..."
	await _global.main.emptiedCapture
	awaiting_input = slot - 1
	await _global.main.pressedKey
	_write_label(slot)
	await _global.main.emptiedCapture
	awaiting_input = -1


func _on_cleared(slot: int) -> void:
	_global.main.costumeKeys[slot - 1] = "null"
	_write_label(slot)
	_global.notify_user("Deleted costume hotkey " + str(slot) + ".")
