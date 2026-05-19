extends Node2D

var menu_buttons: Dictionary = {}
var _duplicate_btn: Button
var menu_bar_bg: ColorRect
var _menu_hbox: HBoxContainer
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
	menu_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_bar_bg.z_index = 100
	add_child(menu_bar_bg)

	_menu_hbox = HBoxContainer.new()
	_menu_hbox.position = Vector2(8, 4)
	_menu_hbox.add_theme_constant_override("separation", 2)
	_menu_hbox.z_index = 100
	add_child(_menu_hbox)

	_add_btn(_menu_hbox, "Exit", _on_exit, true)
	_add_sep(_menu_hbox)
	_add_btn(_menu_hbox, "Import", _on_import)
	_duplicate_btn = _add_btn(_menu_hbox, "Duplicate", _on_duplicate)
	_add_btn(_menu_hbox, "Replace", _on_replace)
	_add_sep(_menu_hbox)
	_add_btn(_menu_hbox, "Save", _on_save)
	_add_btn(_menu_hbox, "Load", _on_load)
	_add_sep(_menu_hbox)
	_add_btn(_menu_hbox, "Clear", _on_clear, true)
	_add_btn(_menu_hbox, "Reset", _on_reset)

	# Center the bar horizontally — recompute on layout pass (button sizes settle)
	# and on window resize (handled in _notification below)
	_menu_hbox.sort_children.connect(_center_menu_hbox)

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
	_duplicate_btn.disabled = no_sprite
	if no_sprite:
		_duplicate_btn.add_theme_color_override("font_color", COLOR_DISABLED)
		_duplicate_btn.add_theme_color_override("font_hover_color", COLOR_DISABLED)
	else:
		_duplicate_btn.add_theme_color_override("font_color", COLOR_NORMAL)
		_duplicate_btn.add_theme_color_override("font_hover_color", COLOR_HOVER)

func _on_exit(): Global.main.swapMode()
func _on_import(): Global.main._on_import_button_pressed()
func _on_replace(): Global.main._on_replace_button_pressed()
func _on_duplicate(): Global.main._on_duplicate_button_pressed()
func _on_save(): Global.main._on_save_button_pressed()
func _on_load(): Global.main._on_load_button_pressed()
func _on_clear(): Global.main._on_clear_avatar_pressed()
func _on_reset(): Global.main._on_reset_avatar_pressed()

func _center_menu_hbox():
	if _menu_hbox == null:
		return
	var vp_w = get_viewport().get_visible_rect().size.x
	_menu_hbox.position.x = max(0.0, (vp_w - _menu_hbox.size.x) * 0.5)
	_menu_hbox.position.y = max(0.0, (MENU_BAR_HEIGHT - _menu_hbox.size.y) * 0.5)

func _notification(what):
	if what == 30:
		$MoveMenuDown.position.y = get_window().size.y
		if menu_bar_bg:
			menu_bar_bg.size.x = get_viewport().get_visible_rect().size.x
		_center_menu_hbox()
