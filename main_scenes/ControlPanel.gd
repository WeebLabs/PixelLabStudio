extends Node2D

# Viewer mode's control surface. Everything the streamer needs while live sits
# on a single top menu bar built from the same shared component edit mode uses,
# so the two modes read as one application.
#
# The bar conceals itself off the top edge and slides back in while the cursor
# is near the top of the window (see AppMenuBar's auto-reveal constants), which
# keeps it out of the way of the avatar and out of a capture.
#
# This node also owns the two bar popups (settings, microphone device list) and
# the transient zoom readout. The popups are still their original scenes; only
# their placement is owned here, through AppMenuBar.anchor_popup, so the planned
# popup redesign has one seam to work against.


const LEVEL_COLOR := Color(0.55, 0.78, 1.0)
const DURATION_COLOR := Color(1.0, 0.7, 0.8)

# The zoom readout is deliberately NOT on the bar: it is transient feedback for
# a canvas gesture, and the cursor is nowhere near the top edge when zooming.
const ZOOM_SIZE := Vector2(266, 26)
const ZOOM_MARGIN := Vector2(74, 51)
const ZOOM_FADE := 0.02
const ZOOM_HOLD := 6.0

@onready var settings_menu: Node2D = $SettingsMenu
@onready var mic_select: Node2D = $MicInputSelect

var menu_bar: AppMenuBar = null

var _mic_button: Button = null
var _settings_button: Button = null
var _zoom_label: Label = null
var _meters: Array = []
var _active := false


func _ready() -> void:
	menu_bar = AppMenuBar.new()
	menu_bar.name = "AppMenuBar"
	menu_bar.configure_auto_reveal(true)
	add_child(menu_bar)

	_build_actions()
	_build_right_zone()
	_build_zoom_readout()


# --- Bar contents -------------------------------------------------------------

# Mode switch at the far left, avatar file actions in the middle, and the mic
# meters plus Settings at the far right. The two mode bars therefore agree on
# where the mode switch and the file actions live.
func _build_actions() -> void:
	menu_bar.add_button(menu_bar.left, "Switch to Editor", _on_edit_pressed)
	MenuActions.add_avatar_file_actions(menu_bar, menu_bar.center)

	# The Mic entry point is hidden pending its move into the settings panel. The
	# device popup and the right-click mute stay wired so that becomes a
	# relocation rather than a rewrite. An invisible child costs no bar space.
	_mic_button = menu_bar.add_button(menu_bar.left, "Mic", _on_mic_pressed)
	_mic_button.gui_input.connect(_on_mic_gui_input)
	_mic_button.tooltip_text = "Left click: choose input device. Right click: mute."
	_mic_button.visible = false
	_refresh_mic_tone()


# Right zone: the mic meters, then Settings closing the bar opposite the mode
# switch.
func _build_right_zone() -> void:
	_build_mic_meters()
	_settings_button = menu_bar.add_button(menu_bar.right, "Settings", _on_settings_pressed)


# The two microphone controls are the same widget with different wiring, so they
# are declared once and built in a loop. "Level" is the raw signal against the
# threshold that starts a trigger; "Duration" is the decay that ends it, so its
# marker sets how long the mouth stays open after a trigger.
func _build_mic_meters() -> void:
	var specs := [
		{
			"caption": "Duration",
			"fill": DURATION_COLOR,
			"range": 1.0,
			"step": 0.005,
			"setting": "sense",
			"default": 0.25,
			"source": func() -> float: return Global.volumeSensitivity,
			"apply": func(limit: float) -> void: Global.senseLimit = limit,
		},
		{
			"caption": "Level",
			"fill": LEVEL_COLOR,
			"range": 0.2,
			"step": 0.001,
			"setting": "volume",
			"default": 0.185,
			"source": func() -> float: return Global.volume,
			"apply": func(limit: float) -> void: Global.volumeLimit = limit,
		},
	]

	# The meters share one group so they can yield together when the bar is too
	# narrow for everything; the buttons around them stay reachable.
	var meters := menu_bar.add_group(menu_bar.right, AppMenuBar.GROUP_SEPARATION)
	menu_bar.set_collapsible(meters)

	for spec in specs:
		var control := menu_bar.add_level_meter(
			meters,
			spec["caption"],
			spec["fill"],
			spec["range"],
			spec["range"],
			spec["step"],
		)
		var slider: HSlider = control["slider"]
		var limit_range: float = spec["range"]
		var setting: String = spec["setting"]
		var apply: Callable = spec["apply"]

		# The slider reads as "sensitivity": dragging right lowers the limit.
		slider.value_changed.connect(func(value: float) -> void:
			apply.call(limit_range - value)
			Saving.settings[setting] = value
		)
		# The cursor leaves the reveal band while dragging, so hold the bar open.
		slider.drag_started.connect(func() -> void: menu_bar.set_pin(&"drag", true))
		slider.drag_ended.connect(func(_changed: bool) -> void: menu_bar.set_pin(&"drag", false))

		slider.value = Saving.settings.get(setting, spec["default"])
		apply.call(limit_range - slider.value)
		Global.make_slider_resettable(slider, spec["default"])

		_meters.append({"meter": control["meter"], "source": spec["source"]})


func _build_zoom_readout() -> void:
	_zoom_label = Label.new()
	_zoom_label.name = "ZoomLabel"
	_zoom_label.text = "Zoom : 100%"
	_zoom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_zoom_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_zoom_label.offset_left = -(ZOOM_MARGIN.x + ZOOM_SIZE.x)
	_zoom_label.offset_right = -ZOOM_MARGIN.x
	_zoom_label.offset_top = -(ZOOM_MARGIN.y + ZOOM_SIZE.y)
	_zoom_label.offset_bottom = -ZOOM_MARGIN.y
	_zoom_label.modulate.a = 0.0
	add_child(_zoom_label)


# --- Public surface ------------------------------------------------------------

# Viewer mode on/off. Processing is tied to visibility so a concealed bar is not
# tracking the cursor while the editor is up.
func set_active(active: bool) -> void:
	_active = active
	visible = active
	set_process(active)
	menu_bar.set_process(active)
	if not active:
		menu_bar.snap_hidden()
		settings_menu.visible = false
		mic_select.visible = false


# How much of the bar is on screen, for canvas hit-testing.
func chrome_height() -> float:
	return menu_bar.revealed_height() if _active else 0.0


func show_zoom(percent: int) -> void:
	_zoom_label.text = "Zoom : %d%%" % percent
	if _active:
		_zoom_label.modulate.a = ZOOM_HOLD


func _process(_delta: float) -> void:
	for entry in _meters:
		entry["meter"].value = entry["source"].call()
	menu_bar.set_pin(&"popup", settings_menu.visible or mic_select.visible)
	_zoom_label.modulate.a = lerpf(_zoom_label.modulate.a, 0.0, ZOOM_FADE)


# --- Bar actions ----------------------------------------------------------------

func _on_edit_pressed() -> void:
	Global.main.swapMode()


func _on_mic_pressed() -> void:
	settings_menu.visible = false
	_toggle_popup(mic_select, _mic_button, mic_select.get_node("ScrollContainer").size)


func _on_mic_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
		return
	Global.micMuted = not Global.micMuted
	_refresh_mic_tone()
	Global.pushUpdate("Microphone muted." if Global.micMuted else "Microphone unmuted.")


func _on_settings_pressed() -> void:
	mic_select.visible = false
	_toggle_popup(settings_menu, _settings_button, settings_menu.get_node("NinePatchRect").size)


func _toggle_popup(popup: Node2D, opener: Control, popup_size: Vector2) -> void:
	popup.visible = not popup.visible
	if popup.visible:
		menu_bar.anchor_popup(opener, popup, popup_size)


func _refresh_mic_tone() -> void:
	if Global.micMuted:
		menu_bar.set_button_tone(_mic_button, AppMenuBar.COLOR_DANGER, AppMenuBar.COLOR_DANGER_HOVER)
	else:
		menu_bar.set_button_tone(_mic_button, AppMenuBar.COLOR_NORMAL, AppMenuBar.COLOR_HOVER)
