extends RefCounted

const Form = preload("res://ui_scenes/common/form_ui.gd")

var _global: Node
var _saving: Node
var _bounce_force: HSlider
var _bounce_gravity: HSlider
var _costume_bounce_check: CheckBox
var _blink_speed: HSlider
var _blink_chance: HSlider


func build(body: VBoxContainer, global: Node, saving: Node, slider_theme: Dictionary) -> void:
	_global = global
	_saving = saving
	var bounce := Form.section(body, "Bounce")
	_bounce_force = Form.slider_row(bounce, "Force", 0, 500, 1, slider_theme)["slider"]
	_bounce_force.value_changed.connect(_on_bounce_force)
	_global.make_slider_resettable(_bounce_force, 250)
	_bounce_gravity = Form.slider_row(bounce, "Gravity", 0, 3000, 1, slider_theme)["slider"]
	_bounce_gravity.value_changed.connect(_on_bounce_gravity)
	_global.make_slider_resettable(_bounce_gravity, 1000)
	_costume_bounce_check = Form.check_row(bounce, "Bounce on costume change")
	_costume_bounce_check.toggled.connect(_on_costume_bounce)
	var blink := Form.section(body, "Blink")
	_blink_speed = Form.slider_row(blink, "Speed", 0, 20, 1, slider_theme)["slider"]
	_blink_speed.value_changed.connect(_on_blink_speed)
	_global.make_slider_resettable(_blink_speed, 1)
	_blink_chance = Form.slider_row(
		blink, "Chance", 1, 300, 1, slider_theme,
		func(value: float) -> String: return "1 in %d" % int(value),
	)["slider"]
	_blink_chance.value_changed.connect(_on_blink_chance)
	_global.make_slider_resettable(_blink_chance, 200)


func refresh() -> void:
	_bounce_force.value = _saving.settings["bounce"]
	_bounce_gravity.value = _saving.settings["gravity"]
	_costume_bounce_check.set_pressed_no_signal(_global.main.bounceOnCostumeChange)
	_blink_speed.value = int(1.0 / _global.blinkSpeed) if _global.blinkSpeed > 0.0 else 0
	_blink_chance.value = _global.blinkChance


func _on_bounce_force(value: float) -> void:
	_global.main.bounceSlider = value
	_saving.settings["bounce"] = value
	_global.main.ndi_mark_dirty()


func _on_bounce_gravity(value: float) -> void:
	_global.main.bounceGravity = value
	_saving.settings["gravity"] = value
	_global.main.ndi_mark_dirty()


func _on_costume_bounce(pressed: bool) -> void:
	_global.main.bounceOnCostumeChange = pressed
	_saving.settings["bounceOnCostumeChange"] = pressed


func _on_blink_speed(value: float) -> void:
	var speed := 0.0 if value == 0 else 1.0 / value
	_global.blinkSpeed = speed
	_saving.settings["blinkSpeed"] = speed


func _on_blink_chance(value: float) -> void:
	_global.blinkChance = int(value)
	_saving.settings["blinkChance"] = int(value)
