class_name ModalDialog
extends Control

# The one modal dialog in the application: session recovery, save/load progress,
# import progress, video encoding. Before this there were two near-identical
# builders with hand-placed children and drifting colors.
#
# Constructed, not placed: the dialog fills the viewport and a CenterContainer
# holds the panel, so it stays centred at any window size with no per-frame
# repositioning. Palette comes from the shared UI factory, so it matches the
# sidebars and the menu bar.
#
# Build it after adding it to the tree:
#
#     var dialog := ModalDialog.new()
#     ui_layer.add_child(dialog)
#     dialog.set_title("Loading avatar...")
#     dialog.add_progress_bar()

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

const SCRIM_COLOR := Color(0, 0, 0, 0.35)
const PANEL_MIN_SIZE := Vector2(360, 0)
const PANEL_PADDING := 16
const PANEL_CORNER_RADIUS := 4
const COLUMN_SEPARATION := 12

const TITLE_FONT_SIZE := 14
const BODY_FONT_SIZE := 12

const BUTTON_MIN_SIZE := Vector2(160, 28)
const BUTTON_SEPARATION := 16
const BUTTON_DANGER_HOVER := Color(1.0, 0.6, 0.65)

const PROGRESS_HEIGHT := 20
const PROGRESS_TRACK_COLOR := Color(0.2, 0.2, 0.22)
const PROGRESS_FILL_COLOR := SidebarUIFactory.SLIDER_FILL_ENABLED
const PROGRESS_CORNER_RADIUS := 3

var panel: PanelContainer = null
var column: VBoxContainer = null

var _title: Label = null
var _progress: ProgressBar = null


func _ready() -> void:
	# Dialogs live on the UI layer, which is excluded from NDI output.
	visibility_layer = 2
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# A full-rect STOP scrim is the modal guard: it consumes clicks before they
	# reach mouse_cursor's _unhandled_input, so the canvas cannot be touched.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = SCRIM_COLOR
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = PANEL_MIN_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = SidebarUIFactory.DEFAULT_PANEL_COLOR
	style.border_color = SidebarUIFactory.DEFAULT_DIVIDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	style.set_content_margin_all(PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", COLUMN_SEPARATION)
	panel.add_child(column)

	get_window().size_changed.connect(_fit_to_viewport)
	_fit_to_viewport()


func _exit_tree() -> void:
	var window := get_window()
	if window != null and window.size_changed.is_connected(_fit_to_viewport):
		window.size_changed.disconnect(_fit_to_viewport)


# The dialog covers the viewport by explicit size rather than anchors. Anchors
# resolve once against the parent's anchorable rect and do not follow the window
# here, which left dialogs frozen at whatever the viewport measured when they
# were built: the recovery prompt captured the pre-startup-resize size and every
# later dialog captured a different one, so none of them sat centred.
func _fit_to_viewport() -> void:
	if not is_inside_tree():
		return
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


# The heading, also used as the live status line on progress dialogs.
func set_title(text: String) -> void:
	if _title == null:
		_title = Label.new()
		_title.name = "StatusLabel"
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		_title.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
		column.add_child(_title)
		column.move_child(_title, 0)
	_title.text = text


func add_message(text: String) -> Label:
	var message := Label.new()
	message.text = text
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD
	message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	message.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	column.add_child(message)
	return message


func add_progress_bar() -> ProgressBar:
	_progress = ProgressBar.new()
	_progress.name = "ProgressBar"
	_progress.custom_minimum_size = Vector2(0, PROGRESS_HEIGHT)
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.add_theme_stylebox_override("background", _progress_box(PROGRESS_TRACK_COLOR))
	_progress.add_theme_stylebox_override("fill", _progress_box(PROGRESS_FILL_COLOR))
	_progress.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	_progress.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	column.add_child(_progress)
	return _progress


func set_progress(value: float) -> void:
	if _progress != null:
		_progress.value = value


# Each action is {"text": String, "callback": Callable, "danger": bool}.
func add_actions(actions: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", BUTTON_SEPARATION)
	column.add_child(row)

	for action in actions:
		var button := Button.new()
		button.text = action["text"]
		button.custom_minimum_size = BUTTON_MIN_SIZE
		if action.get("danger", false):
			button.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
			button.add_theme_color_override("font_hover_color", BUTTON_DANGER_HOVER)
		button.pressed.connect(action["callback"])
		row.add_child(button)
	return row


func set_panel_min_size(minimum: Vector2) -> void:
	panel.custom_minimum_size = minimum


func _progress_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(PROGRESS_CORNER_RADIUS)
	return box
