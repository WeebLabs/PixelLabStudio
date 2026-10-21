extends RefCounted

const Form = preload("res://ui_scenes/common/form_ui.gd")
const NDI_WIDTHS := [512, 720, 1080, 1920]
const RECORDING_FORMATS := ["webm", "apng", "gif"]
const RECORDING_FORMAT_NAMES := ["Video (WebM)", "Animated PNG", "GIF"]
const RECORDING_FPS := [15, 30, 60]

var _global: Node
var _saving: Node
var _ndi_status: Label
var _ndi_toggle: CheckBox
var _ndi_width: OptionButton
var _ndi_mode: OptionButton
var _ndi_manual_row: HBoxContainer
var _ndi_manual_w: SpinBox
var _ndi_manual_h: SpinBox
var _ndi_source_name: LineEdit
var _recording_format: OptionButton
var _recording_fps: OptionButton


func build(body: VBoxContainer, global: Node, saving: Node) -> void:
	_global = global
	_saving = saving
	var ndi := Form.section(body, "NDI output")
	_ndi_status = Label.new()
	_ndi_status.add_theme_font_size_override("font_size", Form.LABEL_FONT_SIZE)
	_ndi_status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	_ndi_status.visible = false
	ndi.add_child(_ndi_status)
	_ndi_toggle = Form.check_row(ndi, "Enabled")
	_ndi_toggle.toggled.connect(_on_ndi_toggle)
	_ndi_width = Form.option_row(ndi, "Width", NDI_WIDTHS)
	_ndi_width.item_selected.connect(_on_ndi_width_selected)
	_ndi_mode = Form.option_row(ndi, "Mode", ["auto", "manual"])
	_ndi_mode.item_selected.connect(_on_ndi_mode_selected)
	var manual := Form.spin_row(ndi, "Manual size", 128, 3840)
	_ndi_manual_w = manual[0]
	_ndi_manual_h = manual[1]
	_ndi_manual_row = _ndi_manual_w.get_parent()
	_ndi_manual_row.visible = false
	for spin in manual:
		spin.value_changed.connect(_on_ndi_manual_size_changed)
	_ndi_source_name = Form.text_row(ndi, "Source name", "PixelLab Studio")
	_ndi_source_name.text_submitted.connect(_on_source_name_committed)
	_ndi_source_name.focus_exited.connect(_on_source_name_focus_exited)
	var recording := Form.section(body, "Recording")
	_recording_format = Form.option_row(recording, "Format", RECORDING_FORMAT_NAMES)
	_recording_format.item_selected.connect(_on_recording_format_selected)
	_recording_fps = Form.option_row(recording, "Frame rate", RECORDING_FPS)
	_recording_fps.item_selected.connect(_on_recording_fps_selected)


func refresh() -> void:
	_refresh_ndi()
	_recording_format.selected = maxi(
		RECORDING_FORMATS.find(_saving.settings.get("recordingFormat", "webm")), 0,
	)
	var fps_index := RECORDING_FPS.find(_saving.settings.get("recordingFPS", 30))
	_recording_fps.selected = fps_index if fps_index >= 0 else 1


func _refresh_ndi() -> void:
	var ndi = _global.main.ndi_manager
	if ndi == null:
		return
	if not ndi.is_plugin_available():
		_ndi_status.text = "Plugin not installed."
		_ndi_status.visible = true
		_ndi_toggle.set_pressed_no_signal(false)
		for control in [_ndi_toggle, _ndi_width, _ndi_mode]:
			control.disabled = true
		_ndi_source_name.editable = false
		return
	_ndi_status.visible = false
	_ndi_toggle.disabled = false
	_ndi_toggle.set_pressed_no_signal(ndi.is_enabled())
	_ndi_source_name.editable = true
	_ndi_source_name.text = _saving.settings.get("ndiSourceName", "PixelLab Studio")
	_ndi_width.selected = maxi(NDI_WIDTHS.find(_saving.settings["ndiWidth"]), 0)
	var mode: String = _saving.settings["ndiMode"]
	_ndi_mode.selected = 1 if mode == "manual" else 0
	_ndi_manual_row.visible = mode == "manual"
	if mode == "manual":
		_ndi_manual_w.value = _saving.settings["ndiManualWidth"]
		_ndi_manual_h.value = _saving.settings["ndiManualHeight"]
	var enabled: bool = ndi.is_enabled()
	_ndi_width.disabled = not enabled
	_ndi_mode.disabled = not enabled


func _on_ndi_toggle(pressed: bool) -> void:
	var ndi = _global.main.ndi_manager
	if ndi == null:
		return
	ndi.set_enabled(pressed)
	_refresh_ndi()
	if _global.main.editMode:
		ndi.set_crop_visible(pressed)
	_global.main.updateWindowTransparency()
	_global.notify_user("NDI output enabled." if pressed else "NDI output disabled.")


func _on_ndi_width_selected(index: int) -> void:
	var ndi = _global.main.ndi_manager
	if ndi != null:
		ndi.set_width(NDI_WIDTHS[index])
	_global.notify_user("NDI width set to " + str(NDI_WIDTHS[index]) + ".")


func _on_ndi_mode_selected(index: int) -> void:
	var mode := "auto" if index == 0 else "manual"
	var ndi = _global.main.ndi_manager
	if ndi != null:
		ndi.set_mode(mode)
	_ndi_manual_row.visible = mode == "manual"
	_global.notify_user("NDI mode set to " + mode + ".")


func _on_ndi_manual_size_changed(_value: float) -> void:
	var ndi = _global.main.ndi_manager
	if ndi != null:
		ndi.set_manual_size(int(_ndi_manual_w.value), int(_ndi_manual_h.value))


func _on_source_name_committed(new_text: String) -> void:
	_apply_source_name(new_text)
	_ndi_source_name.release_focus()


func _on_source_name_focus_exited() -> void:
	_apply_source_name(_ndi_source_name.text)


func _apply_source_name(new_text: String) -> void:
	var ndi = _global.main.ndi_manager
	if ndi == null:
		return
	var previous: String = _saving.settings.get("ndiSourceName", "PixelLab Studio")
	ndi.set_source_name(new_text)
	var applied: String = _saving.settings.get("ndiSourceName", "PixelLab Studio")
	_ndi_source_name.text = applied
	if applied != previous:
		_global.notify_user("NDI source name set to \"" + applied + "\".")


func _on_recording_format_selected(index: int) -> void:
	var format: String = RECORDING_FORMATS[index]
	_saving.settings["recordingFormat"] = format
	_saving.settings["recordingFPS"] = 15 if format != "webm" else 30
	refresh()
	_global.notify_user("Recording format set to " + RECORDING_FORMAT_NAMES[index] + ".")


func _on_recording_fps_selected(index: int) -> void:
	_saving.settings["recordingFPS"] = RECORDING_FPS[index]
	_global.notify_user("Recording FPS set to " + str(RECORDING_FPS[index]) + ".")
