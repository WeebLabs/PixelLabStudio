extends RefCounted

const Form = preload("res://ui_scenes/common/form_ui.gd")
const UNLIMITED_FPS := 241
const BACKGROUND_PRESETS := [
	{"name": "Transparent", "color": Color(0.0, 0.0, 0.0, 0.0)},
	{"name": "Green", "color": Color(0.0, 1.0, 0.0, 1.0)},
	{"name": "Blue", "color": Color(0.0, 0.0, 1.0, 1.0)},
	{"name": "Magenta", "color": Color(1.0, 0.0, 1.0, 1.0)},
]

var _global: Node
var _saving: Node
var _viewport: Viewport
var _color_picker: ColorPickerButton
var _filtering_check: CheckBox
var _fps_slider: HSlider


func build(body: VBoxContainer, global: Node, saving: Node, viewport: Viewport, slider_theme: Dictionary) -> void:
	_global = global
	_saving = saving
	_viewport = viewport
	var background := Form.section(body, "Background")
	var presets := Form.row(background, "")
	for preset in BACKGROUND_PRESETS:
		var swatch := Form.button(presets, preset["name"], _apply_background.bind(preset["color"]))
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var custom := Form.row(background, "Custom colour")
	_color_picker = ColorPickerButton.new()
	_color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_color_picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_color_picker.custom_minimum_size = Vector2(0, Form.CONTROL_HEIGHT)
	_color_picker.color_changed.connect(_apply_background)
	custom.add_child(_color_picker)
	var rendering := Form.section(body, "Rendering")
	_filtering_check = Form.check_row(rendering, "Texture filtering")
	_filtering_check.toggled.connect(_on_filtering_toggled)
	var fps := Form.slider_row(
		rendering, "Max FPS", 1, UNLIMITED_FPS, 1, slider_theme,
		func(value: float) -> String:
			return "Unlimited" if int(value) == UNLIMITED_FPS else str(int(value)),
	)
	_fps_slider = fps["slider"]
	_global.make_slider_resettable(_fps_slider, 60)
	Form.button(Form.row(rendering, ""), "Apply frame limit", _on_apply_fps)


func refresh() -> void:
	var background: Color = _global.backgroundColor
	_color_picker.color = Color.WHITE if background.a == 0.0 else background
	_filtering_check.set_pressed_no_signal(_global.filtering)
	_fps_slider.value = UNLIMITED_FPS if Engine.max_fps == 0 else Engine.max_fps


func _apply_background(color: Color) -> void:
	_viewport.transparent_bg = color.a == 0.0
	_global.backgroundColor = color
	_saving.settings["backgroundColor"] = var_to_str(color)
	RenderingServer.set_default_clear_color(color)
	_global.notify_user("Background colour updated.")


func _on_filtering_toggled(pressed: bool) -> void:
	var mode := 2 if pressed else 0
	for sprite in _global.sprite_nodes():
		sprite.sprite.texture_filter = mode
	_global.filtering = pressed
	_saving.settings["filtering"] = pressed
	_global.notify_user("Texture filtering set to: " + str(pressed))


func _on_apply_fps() -> void:
	var value := int(_fps_slider.value)
	Engine.max_fps = 0 if value == UNLIMITED_FPS else value
	_saving.settings["maxFPS"] = Engine.max_fps
	_global.notify_user("Max fps set to " + ("unlimited" if Engine.max_fps == 0 else str(Engine.max_fps)) + ".")
