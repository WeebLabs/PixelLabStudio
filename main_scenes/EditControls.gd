extends Node2D

# Edit mode's top menu bar. All items sit in the bar's center zone, which the
# shared component renders as one centered strip. Chrome, styling and resize
# behaviour come from AppMenuBar; this file only declares what is on the bar.

const MENU_BAR_HEIGHT = AppMenuBar.BAR_HEIGHT

var menu_bar: AppMenuBar = null
var _duplicate_btn: Button = null
var _duplicate_disabled := false


func _ready():
	menu_bar = AppMenuBar.new()
	menu_bar.name = "AppMenuBar"
	add_child(menu_bar)

	var zone := menu_bar.center
	menu_bar.add_button(zone, "Exit", _on_exit, true)
	menu_bar.add_separator(zone)
	menu_bar.add_button(zone, "Import", _on_import)
	_duplicate_btn = menu_bar.add_button(zone, "Duplicate", _on_duplicate)
	menu_bar.add_button(zone, "Replace", _on_replace)
	menu_bar.add_separator(zone)
	MenuActions.add_avatar_file_actions(menu_bar, zone)


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
