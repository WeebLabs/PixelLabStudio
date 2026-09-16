extends Node2D

# Edit mode's top menu bar. The editing actions sit in the center zone as one
# strip; the mode switch sits at the left, matching the viewer bar. Chrome,
# styling and resize behaviour come from AppMenuBar; this file only declares what
# is on the bar.

const MENU_BAR_HEIGHT = AppMenuBar.BAR_HEIGHT

# A paused avatar that is simply sitting still looks the same as a broken one, so
# the toggle changes colour and wording while it is on.
const PAUSE_ACTIVE := Color(1.0, 0.78, 0.35)
const PAUSE_ACTIVE_HOVER := Color(1.0, 0.88, 0.6)

var menu_bar: AppMenuBar = null
var _duplicate_btn: Button = null
var _duplicate_disabled := false
var _pause_btn: Button = null


func _ready():
	menu_bar = AppMenuBar.new()
	menu_bar.name = "AppMenuBar"
	add_child(menu_bar)

	# The mode switch leads the left zone, the same place the viewer bar puts it.
	# Everything else stays in the center zone as one strip.
	menu_bar.add_button(menu_bar.left, "Switch to Player", _on_exit)

	var zone := menu_bar.center
	menu_bar.add_button(zone, "Import", _on_import)
	_duplicate_btn = menu_bar.add_button(zone, "Duplicate", _on_duplicate)
	menu_bar.add_button(zone, "Replace", _on_replace)
	menu_bar.add_separator(zone)
	MenuActions.add_avatar_file_actions(menu_bar, zone)

	# Pause closes the bar opposite the mode switch, on its own. It changes how the
	# canvas behaves rather than changing the avatar, so it does not belong in the
	# center strip with the file and layer actions, and unlike those it stays
	# usable with no layer selected.
	_pause_btn = menu_bar.add_button(menu_bar.right, "", _on_pause)
	_pause_btn.toggle_mode = true
	_pause_btn.tooltip_text = "Hold bounce, wobble, animation, eye tracking and wiggle at their rest pose"
	_apply_pause_state()


func _process(_delta):
	# The pause is gated on edit mode, so it can also be cleared from elsewhere;
	# keep the button showing the flag rather than the last click.
	if _pause_btn.button_pressed != Global.motionPaused:
		_pause_btn.button_pressed = Global.motionPaused
		_apply_pause_state()

	var no_sprite = Global.heldSprite == null
	if no_sprite == _duplicate_disabled:
		return
	_duplicate_disabled = no_sprite
	menu_bar.set_button_enabled(_duplicate_btn, not no_sprite)


func _on_exit(): Global.main.swapMode()
func _on_import(): Global.main.open_import_dialog()
func _on_replace(): Global.main.open_replace_dialog()
func _on_duplicate(): Global.main.duplicate_selected_layer()


func _on_pause():
	Global.motionPaused = _pause_btn.button_pressed
	_apply_pause_state()


func _apply_pause_state():
	if _pause_btn.button_pressed:
		_pause_btn.text = "Motion Paused"
		menu_bar.set_button_tone(_pause_btn, PAUSE_ACTIVE, PAUSE_ACTIVE_HOVER)
	else:
		_pause_btn.text = "Pause Motion"
		menu_bar.set_button_tone(
			_pause_btn, _pause_btn.get_meta("base_color"), _pause_btn.get_meta("hover_color")
		)


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
