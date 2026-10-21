class_name UpdateController
extends Node

## Checks GitHub releases for a newer build, offers it, and installs it.
##
## Release choice, asset names and checksum parsing are pure and live in
## UpdateFeed. This node owns the HTTP request, the prompt and the handoff:
## an installed Windows copy downloads the setup, verifies it against the
## release's SHA256SUMS.txt, saves the session, starts the installer silently
## (it closes this process and relaunches the new build) and quits. A portable
## copy, or another platform, opens the release page instead.
##
## Automatic checks run at most once a day and never in editor runs or the
## isolated automated sessions. "--update-feed=<url>" after "--" replaces the
## GitHub API URL, which is how the flow is exercised against a local feed.

signal status_changed(text: String)

const UpdateFeed = preload("res://autoload/runtime/update_feed.gd")
const AppVersion = preload("res://autoload/runtime/app_version.gd")
const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

const FEED_ARGUMENT := "--update-feed="
const DOWNLOAD_DIR := "user://updates"
const REQUEST_TIMEOUT_SECONDS := 30.0
const DOWNLOAD_TIMEOUT_SECONDS := 600.0
const PROMPT_SIZE := Vector2(540, 150)

var status_text := ""

var _main: Node2D = null
var _global: Node = null
var _saving: Node = null
var _save_controller: Node = null
var _request: HTTPRequest = null
var _busy := false
var _dialog: ModalDialogUI = null
var _download_size := 0


func setup(main_node: Node2D, global_service: Node, saving_service: Node, save_controller: Node) -> void:
	_main = main_node
	_global = global_service
	_saving = saving_service
	_save_controller = save_controller
	_request = HTTPRequest.new()
	_request.name = "UpdateRequest"
	_request.use_threads = true
	add_child(_request)
	_set_status("Version %s." % AppVersion.current())
	_clear_downloads()


func _exit_tree() -> void:
	if _request != null:
		_request.cancel_request()


func process_frame() -> void:
	if is_instance_valid(_dialog) and not _request.download_file.is_empty():
		var total := _download_size if _download_size > 0 else _request.get_body_size()
		if total > 0:
			_dialog.set_progress(float(_request.get_downloaded_bytes()) / float(total))


func is_busy() -> bool:
	return _busy


## The update prompt or download progress is up; main.gd stops canvas input.
func is_dialog_open() -> bool:
	return is_instance_valid(_dialog)


## Whether an update would install itself (true) or only open the release page.
func can_self_install() -> bool:
	return UpdateFeed.is_installed_copy(OS.get_executable_path(), OS.get_name() == "Windows") and not OS.has_feature("editor")


## The once-a-day background check from startup. Quiet unless it finds something.
func startup_check() -> void:
	if OS.has_feature("editor") or OS.has_feature("web") or _saving.is_isolated_session():
		return
	if not UpdateFeed.should_check(bool(_saving.settings.get("updateChecks", true)), int(Time.get_unix_time_from_system()), int(_saving.settings.get("updateLastCheck", 0))):
		return
	check(false)


## `manual` is the Settings button: it always reports the outcome and ignores
## a version the user chose to skip.
func check(manual: bool) -> void:
	if _busy:
		return
	_busy = true
	_set_status("Checking for updates...")
	var response := await _fetch(_feed_url(), _headers(true), UpdateFeed.MAX_FEED_BYTES, REQUEST_TIMEOUT_SECONDS)
	_busy = false
	if not response["ok"]:
		_set_status("Could not check for updates: %s" % response["error"])
		if manual:
			_global.notify_user(status_text)
		return
	_saving.settings["updateLastCheck"] = int(Time.get_unix_time_from_system())
	var releases: Variant = JSON.parse_string(PackedByteArray(response["body"]).get_string_from_utf8())
	var current := AppVersion.current()
	var include_prereleases := UpdateFeed.include_prereleases(bool(_saving.settings.get("updateIncludePrereleases", false)), current)
	var update := UpdateFeed.pick_update(releases, current, include_prereleases, can_self_install())
	if update.is_empty():
		_set_status("PixelLab Studio %s is the latest version." % current)
		if manual:
			_global.notify_user(status_text)
		return
	_set_status("Version %s is available." % update["version"])
	if not manual and String(_saving.settings.get("updateSkippedVersion", "")) == update["version"]:
		return
	# A background result waits for the recovery prompt, a save or an avatar
	# load to finish rather than stacking a second modal on top.
	while _save_controller.is_dialog_open() or _main.avatar_controller.is_loading():
		await get_tree().create_timer(0.5).timeout
	_show_prompt(update)


func _show_prompt(update: Dictionary) -> void:
	_close_dialog()
	_dialog = ModalDialogUI.new()
	_main.get_node("UILayer").add_child(_dialog)
	_dialog.set_panel_min_size(PROMPT_SIZE)
	_dialog.set_title("Update available")
	var kind := "pre-release " if update["prerelease"] else ""
	_dialog.add_message("PixelLab Studio %s is available as a %supdate. You have %s." % [update["version"], kind, AppVersion.current()])
	var primary: Dictionary
	if can_self_install():
		_dialog.add_message("Updating closes the app, installs the new version and opens it again. Unsaved changes are kept for recovery.")
		primary = {"text": "Update now", "callback": func(): _install(update)}
	else:
		primary = {"text": "Open download page", "callback": func(): _open_page(update)}
	_dialog.add_actions([
		primary,
		{"text": "Later", "callback": _close_dialog},
		{"text": "Skip this version", "callback": func(): _skip(update), "danger": true},
	])


func _skip(update: Dictionary) -> void:
	_saving.settings["updateSkippedVersion"] = update["version"]
	_close_dialog()
	_global.notify_user("Skipped version %s." % update["version"])


func _open_page(update: Dictionary) -> void:
	_close_dialog()
	OS.shell_open(update["page_url"])


func _install(update: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	_close_dialog()
	_dialog = ModalDialogUI.new()
	_main.get_node("UILayer").add_child(_dialog)
	_dialog.set_title("Downloading PixelLab Studio %s..." % update["version"])
	_dialog.add_progress_bar()
	_set_status("Downloading version %s..." % update["version"])

	var sums := await _fetch(update["checksums_url"], _headers(false), UpdateFeed.MAX_FEED_BYTES, REQUEST_TIMEOUT_SECONDS)
	if not sums["ok"]:
		_fail("Could not download the update's checksums: %s" % sums["error"])
		return
	var expected := UpdateFeed.checksum_for(PackedByteArray(sums["body"]).get_string_from_utf8(), update["setup_name"])
	if expected.is_empty():
		_fail("The update's checksum file does not list %s." % update["setup_name"])
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOWNLOAD_DIR))
	var setup_path := ProjectSettings.globalize_path(DOWNLOAD_DIR.path_join(update["setup_name"]))
	_download_size = int(update["setup_size"])
	_request.download_file = setup_path
	var download := await _fetch(update["setup_url"], _headers(false), UpdateFeed.MAX_INSTALLER_BYTES, DOWNLOAD_TIMEOUT_SECONDS)
	_request.download_file = ""
	_download_size = 0
	if not download["ok"]:
		DirAccess.remove_absolute(setup_path)
		_fail("Could not download the update: %s" % download["error"])
		return
	if FileAccess.get_sha256(setup_path) != expected:
		DirAccess.remove_absolute(setup_path)
		_fail("The downloaded update did not match its checksum, so it was not installed.")
		return

	_dialog.set_title("Installing PixelLab Studio %s..." % update["version"])
	_save_controller.save_session_now()
	_saving.settings["updateSkippedVersion"] = ""
	if not _saving.write_settings(_saving.settingsPath):
		push_warning(_saving.last_error)
	var pid := OS.create_process(setup_path, UpdateFeed.installer_arguments())
	if pid <= 0:
		_fail("Could not start the installer.")
		return
	# Leave through the one shutdown path, without the unsaved-changes prompt:
	# the session just written is offered back after the update. The installer
	# waits for this process before replacing its files.
	_main.quit_controller.quit_app(true)


func _fail(message: String) -> void:
	_busy = false
	_close_dialog()
	_set_status(message)
	_global.notify_user(message)


func _close_dialog() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _fetch(url: String, headers: PackedStringArray, max_bytes: int, timeout: float) -> Dictionary:
	if url.is_empty():
		return {"ok": false, "error": "no address"}
	_request.body_size_limit = max_bytes
	_request.timeout = timeout
	var error := _request.request(url, headers)
	if error != OK:
		return {"ok": false, "error": error_string(error)}
	var response: Array = await _request.request_completed
	var result: int = response[0]
	var code: int = response[1]
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": _result_message(result)}
	if code < 200 or code >= 300:
		return {"ok": false, "error": "the server answered %d" % code}
	return {"ok": true, "body": response[3]}


func _headers(api: bool) -> PackedStringArray:
	var headers := PackedStringArray(["User-Agent: PixelLabStudio/%s" % AppVersion.current()])
	if api:
		headers.append("Accept: application/vnd.github+json")
	return headers


func _feed_url() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(FEED_ARGUMENT):
			return argument.trim_prefix(FEED_ARGUMENT)
	return UpdateFeed.RELEASES_API


func _set_status(text: String) -> void:
	status_text = text
	status_changed.emit(text)


# Installers from earlier updates are only needed until they have run.
func _clear_downloads() -> void:
	var directory := DirAccess.open(DOWNLOAD_DIR)
	if directory == null:
		return
	for file in directory.get_files():
		directory.remove(file)


static func _result_message(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "no connection"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "secure connection failed"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "the download was larger than expected"
		HTTPRequest.RESULT_TIMEOUT:
			return "timed out"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "could not write the download"
	return "request failed (%d)" % result
