class_name QuitController
extends Node

# Leaving the app. A window close asks first when the rig has unsaved changes:
# Save, Discard Changes or Cancel. Every exit, prompted or not, goes through
# quit_app(), so threads are joined, the session file is settled and settings
# are written in one place.

const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

const PROMPT_SIZE := Vector2(440, 150)
const BUSY_POLL_SECONDS := 0.25

var _main: Node2D = null
var _saving: Node = null
var _undo_manager: Node = null
var _save_controller: Node = null
var _avatar_controller: Node = null

var _prompt: ModalDialogUI = null
var _waiting := false
var _quit_after_save := false
var _quitting := false


func setup(main_node: Node2D, saving_service: Node, undo_service: Node, save_service: Node, avatar_service: Node) -> void:
	_main = main_node
	_saving = saving_service
	_undo_manager = undo_service
	_save_controller = save_service
	_avatar_controller = avatar_service
	_save_controller.save_finished.connect(_on_save_finished)
	_save_controller.save_dialog.canceled.connect(_on_save_cancelled)
	# Closing the window now only asks; request_quit() decides.
	_main.get_tree().set_auto_accept_quit(false)


func is_dialog_open() -> bool:
	return is_instance_valid(_prompt)


# The window's close button, Alt+F4 or the taskbar. A second request while one
# is being answered is ignored.
func request_quit() -> void:
	if _quitting or _waiting or is_instance_valid(_prompt):
		return
	# A save started from the prompt is still covered: the request waits for it
	# and then finds the rig clean.
	_quit_after_save = false
	match close_action(_undo_manager.has_unsaved_changes(), _is_busy(), _save_controller.is_recovery_pending()):
		"wait":
			_wait_then_retry()
		"prompt":
			_show_prompt()
		_:
			quit_app()


# The one way out. `keep_session` leaves the session file for the next launch to
# offer back, which only the updater wants; otherwise a deliberate quit has
# either saved or discarded the work, so a leftover session would only raise a
# needless recovery prompt. A recovery prompt still unanswered keeps it too.
func quit_app(keep_session := false) -> void:
	if _quitting:
		return
	_quitting = true
	_save_controller.shutdown()
	if not keep_session and not _save_controller.is_recovery_pending() and not _saving.is_isolated_session():
		_save_controller.discard_session_file()
	if not _saving.write_settings(_saving.settingsPath):
		push_warning(_saving.last_error)
	_main.get_tree().quit()


# What a close request does: "wait" while a save or load is still writing or
# building the rig, "prompt" when there are unsaved changes, else "quit". An
# unanswered recovery prompt means nothing has been edited yet.
static func close_action(unsaved: bool, busy: bool, recovery_pending: bool) -> String:
	if busy:
		return "wait"
	if unsaved and not recovery_pending:
		return "prompt"
	return "quit"


func _is_busy() -> bool:
	return _save_controller.is_saving() or _avatar_controller.is_loading()


func _wait_then_retry() -> void:
	_waiting = true
	while _is_busy():
		await _main.get_tree().create_timer(BUSY_POLL_SECONDS).timeout
	_waiting = false
	request_quit()


func _show_prompt() -> void:
	_bring_window_forward()
	var dialog := ModalDialogUI.new()
	_main.get_node("UILayer").add_child(dialog)
	dialog.set_panel_min_size(PROMPT_SIZE)
	dialog.set_title("Save changes before closing?")
	var path: String = _save_controller.current_avatar_path()
	if path.is_empty():
		dialog.add_message("This avatar has not been saved yet.")
	else:
		dialog.add_message("Your changes to %s have not been saved." % path.get_file())
	dialog.add_actions([
		{"text": "Save", "callback": _on_prompt_save},
		{"text": "Discard Changes", "callback": _on_prompt_discard, "danger": true},
		{"text": "Cancel", "callback": _close_prompt},
	])
	_prompt = dialog


# A close from the taskbar can arrive while the window is minimised, where the
# prompt would wait unseen.
func _bring_window_forward() -> void:
	var window := _main.get_window()
	if window.mode == Window.MODE_MINIMIZED:
		window.mode = Window.MODE_WINDOWED
	window.move_to_foreground()


func _close_prompt() -> void:
	if is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = null


func _on_prompt_save() -> void:
	_close_prompt()
	_quit_after_save = true
	_save_controller.save_current()


func _on_prompt_discard() -> void:
	_close_prompt()
	quit_app()


# A failed save keeps the app open with the error showing; the work is still
# there to save another way.
func _on_save_finished(ok: bool) -> void:
	if not _quit_after_save:
		return
	_quit_after_save = false
	if ok:
		quit_app()


func _on_save_cancelled() -> void:
	_quit_after_save = false


func _input(event: InputEvent) -> void:
	if not is_instance_valid(_prompt):
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		_close_prompt()
		get_viewport().set_input_as_handled()
