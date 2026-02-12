extends Node2D

var menu_buttons: Dictionary = {}
var _replace_btn: Button
var _duplicate_btn: Button
var menu_bar_bg: ColorRect
const MENU_BAR_HEIGHT = 28

const COLOR_NORMAL = Color(0.75, 0.75, 0.8)
const COLOR_HOVER = Color(1.0, 1.0, 1.0)
const COLOR_DISABLED = Color(0.35, 0.35, 0.4)
const COLOR_DANGER = Color(0.9, 0.45, 0.5)
const COLOR_DANGER_HOVER = Color(1.0, 0.6, 0.65)

func _ready():
	menu_bar_bg = ColorRect.new()
	menu_bar_bg.color = Color(0.15, 0.15, 0.15)
	menu_bar_bg.size = Vector2(get_viewport().get_visible_rect().size.x, MENU_BAR_HEIGHT)
	add_child(menu_bar_bg)

	var hbox = HBoxContainer.new()
	hbox.position = Vector2(8, 4)
	hbox.add_theme_constant_override("separation", 2)
	add_child(hbox)

	_add_btn(hbox, "Exit", _on_exit, true)
	_add_sep(hbox)
	_add_btn(hbox, "Add", _on_add)
	_replace_btn = _add_btn(hbox, "Replace", _on_replace)
	_duplicate_btn = _add_btn(hbox, "Duplicate", _on_duplicate)
	_add_sep(hbox)
	_add_btn(hbox, "Import PSD", _on_import_psd)
	_add_sep(hbox)
	_add_btn(hbox, "Save", _on_save)
	_add_btn(hbox, "Load", _on_load)
	_add_sep(hbox)
	_add_btn(hbox, "Clear", _on_clear, true)
	_add_btn(hbox, "Reset", _on_reset)

func _add_btn(parent: HBoxContainer, label: String, callback: Callable, danger: bool = false) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.flat = true
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_constant_override("h_separation", 0)

	var style = StyleBoxEmpty.new()
	style.content_margin_left = 6
	style.content_margin_right = 6
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)

	var base_color = COLOR_DANGER if danger else COLOR_NORMAL
	var hover_color = COLOR_DANGER_HOVER if danger else COLOR_HOVER
	btn.add_theme_color_override("font_color", base_color)
	btn.add_theme_color_override("font_hover_color", hover_color)
	btn.add_theme_color_override("font_pressed_color", hover_color)
	btn.add_theme_color_override("font_focus_color", base_color)

	btn.pressed.connect(callback)
	btn.set_meta("danger", danger)
	btn.set_meta("base_color", base_color)
	btn.set_meta("hover_color", hover_color)

	parent.add_child(btn)
	menu_buttons[label] = btn
	return btn

func _add_sep(parent: HBoxContainer):
	var sep = Label.new()
	sep.text = "|"
	sep.add_theme_font_size_override("font_size", 14)
	sep.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	parent.add_child(sep)

func _process(_delta):
	var no_sprite = Global.heldSprite == null
	for btn in [_replace_btn, _duplicate_btn]:
		btn.disabled = no_sprite
		if no_sprite:
			btn.add_theme_color_override("font_color", COLOR_DISABLED)
			btn.add_theme_color_override("font_hover_color", COLOR_DISABLED)
		else:
			btn.add_theme_color_override("font_color", COLOR_NORMAL)
			btn.add_theme_color_override("font_hover_color", COLOR_HOVER)

func _on_exit(): Global.main.swapMode()
func _on_add(): Global.main._on_add_button_pressed()
func _on_replace(): Global.main._on_replace_button_pressed()
func _on_duplicate(): Global.main._on_duplicate_button_pressed()
func _on_import_psd(): Global.main._on_psd_import_button_pressed()
func _on_save(): Global.main._on_save_button_pressed()
func _on_load(): Global.main._on_load_button_pressed()
func _on_clear(): Global.main._on_clear_avatar_pressed()
func _on_reset(): Global.main._on_reset_avatar_pressed()

func _notification(what):
	if what == 30:
		$MoveMenuDown.position.y = get_window().size.y
		if menu_bar_bg:
			menu_bar_bg.size.x = get_viewport().get_visible_rect().size.x
