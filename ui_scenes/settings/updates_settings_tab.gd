extends RefCounted

# Settings → Updates: the running version, the automatic check and pre-release
# opt-in, and a manual check. The work itself is main.gd's UpdateController,
# which does not exist yet when the settings panel is built, so it is looked
# up through the injected global's main scene whenever it is needed.

const Form = preload("res://ui_scenes/common/form_ui.gd")
const AppVersion = preload("res://autoload/runtime/app_version.gd")

var _global: Node
var _saving: Node
var _version_label: Label
var _status_label: Label
var _auto_check: CheckBox
var _prerelease_check: CheckBox
var _connected := false


func build(body: VBoxContainer, global: Node, saving: Node) -> void:
	_global = global
	_saving = saving
	var version := Form.section(body, "Version")
	_version_label = Form.value_row(version, "Installed", AppVersion.current())

	var updates := Form.section(body, "Updates")
	_auto_check = Form.check_row(updates, "Check daily")
	_auto_check.toggled.connect(_on_auto_toggled)
	_prerelease_check = Form.check_row(updates, "Pre-releases")
	_prerelease_check.toggled.connect(_on_prerelease_toggled)
	Form.button(Form.row(updates, ""), "Check for updates now", _on_check_now)
	_status_label = Form.value_row(updates, "Status")


func refresh() -> void:
	_auto_check.set_pressed_no_signal(bool(_saving.settings.get("updateChecks", true)))
	# Someone running a pre-release is always offered the next one, so the box
	# reads as on and cannot be turned off until they are on a release build.
	var running_prerelease := AppVersion.is_prerelease(AppVersion.current())
	_prerelease_check.disabled = running_prerelease
	_prerelease_check.tooltip_text = "Always on while you run a pre-release." if running_prerelease else ""
	_prerelease_check.set_pressed_no_signal(running_prerelease or bool(_saving.settings.get("updateIncludePrereleases", false)))
	var updater := _updater()
	if updater == null:
		return
	_version_label.text = "%s (%s)" % [AppVersion.current(), "installed" if updater.can_self_install() else "portable"]
	_status_label.text = updater.status_text
	if not _connected:
		updater.status_changed.connect(func(text: String): _status_label.text = text)
		_connected = true


func _on_auto_toggled(pressed: bool) -> void:
	_saving.settings["updateChecks"] = pressed


func _on_prerelease_toggled(pressed: bool) -> void:
	_saving.settings["updateIncludePrereleases"] = pressed


func _on_check_now() -> void:
	var updater := _updater()
	if updater != null:
		updater.check(true)


func _updater() -> Node:
	if _global.main == null:
		return null
	return _global.main.get("update_controller")
