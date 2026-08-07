extends Node2D

# Edit mode's top menu bar. All items sit in the bar's center zone, which the
# shared component renders as one centered strip. Chrome, styling and resize
# behaviour come from AppMenuBar; this file only declares what is on the bar.

const MENU_BAR_HEIGHT = AppMenuBar.BAR_HEIGHT

var menu_bar: AppMenuBar = null
var menu_buttons: Dictionary = {}
var _duplicate_btn: Button = null
var _duplicate_disabled := false


func _ready():
	menu_bar = AppMenuBar.new()
	menu_bar.name = "AppMenuBar"
	add_child(menu_bar)

	var zone := menu_bar.center
	_add("Exit", _on_exit, true)
	menu_bar.add_separator(zone)
	_add("Import", _on_import)
	_duplicate_btn = _add("Duplicate", _on_duplicate)
	_add("Replace", _on_replace)
	menu_bar.add_separator(zone)
	_add("Save", _on_save)
	_add("Load", _on_load)
	menu_bar.add_separator(zone)
	_add("Clear", _on_clear, true)
	_add("Reset", _on_reset)


func _add(label: String, callback: Callable, danger := false) -> Button:
	var button := menu_bar.add_button(menu_bar.center, label, callback, danger)
	menu_buttons[label] = button
	return button


func _process(_delta):
	var no_sprite = Global.heldSprite == null
	if no_sprite == _duplicate_disabled:
		return
	_duplicate_disabled = no_sprite
	menu_bar.set_button_enabled(_duplicate_btn, not no_sprite)


func _on_exit(): Global.main.swapMode()
func _on_import(): Global.main._on_import_button_pressed()
func _on_replace(): Global.main._on_replace_button_pressed()
func _on_duplicate(): Global.main._on_duplicate_button_pressed()
func _on_save(): Global.main._on_save_button_pressed()
func _on_load(): Global.main._on_load_button_pressed()
func _on_clear(): Global.main._on_clear_avatar_pressed()
func _on_reset(): Global.main._on_reset_avatar_pressed()


func _notification(what):
	# The bar itself is anchored and needs no resize handling. This only keeps the
	# sprite-menu scroll trigger pinned to the bottom of the window. NOTIFICATION_DRAW
	# (30) is what the original code hooked; NOTIFICATION_WM_SIZE_CHANGED is the
	# reliable signal, so both are honoured.
	if what != NOTIFICATION_DRAW and what != NOTIFICATION_WM_SIZE_CHANGED:
		return
	if not is_inside_tree():
		return
	$MoveMenuDown.position.y = get_window().size.y
