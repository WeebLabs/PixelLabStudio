extends RefCounted

var _owner: Node
var _global: Node
var _undo_manager: Node
var _section: HBoxContainer
var _status: Label
var _import_button: Button
var _clear_button: Button
var _dialog: FileDialog


func build(owner: Node, global: Node, undo_manager: Node, panel_width: float) -> Control:
	_owner = owner
	_global = global
	_undo_manager = undo_manager
	_section = HBoxContainer.new()
	_section.position = Vector2(10, 132)
	_section.size = Vector2(panel_width - 20, 24)
	_section.add_theme_constant_override("separation", 4)
	owner.add_child(_section)
	_status = Label.new()
	_status.text = "(none)"
	_status.add_theme_font_size_override("font_size", 11)
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_section.add_child(_status)
	_import_button = Button.new()
	_import_button.text = "Normal"
	_import_button.custom_minimum_size = Vector2(70, 22)
	_import_button.add_theme_font_size_override("font_size", 11)
	_import_button.pressed.connect(_on_import_pressed)
	_section.add_child(_import_button)
	_clear_button = Button.new()
	_clear_button.text = "Clear"
	_clear_button.custom_minimum_size = Vector2(60, 22)
	_clear_button.add_theme_font_size_override("font_size", 11)
	_clear_button.pressed.connect(_on_clear_pressed)
	_section.add_child(_clear_button)
	sync()
	return _section


func buttons() -> Array:
	return [_import_button, _clear_button]


func sync() -> void:
	var sprite = _global.heldSprite
	_import_button.disabled = sprite == null
	if sprite == null or not sprite.hasNormalMap():
		_status.text = "(none)"
		_clear_button.disabled = true
		return
	var normal_name: String = sprite.normalPath.get_file()
	_status.text = normal_name if not normal_name.is_empty() else "(embedded)"
	_clear_button.disabled = false


func _on_import_pressed() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.title = "Select Normal Map"
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.filters = PackedStringArray(["*.png;PNG Image"])
		_dialog.use_native_dialog = true
		_dialog.file_selected.connect(_on_file_selected)
		_owner.add_child(_dialog)
	_dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	if _global.heldSprite == null:
		return
	var image := Image.new()
	if image.load(path) != OK:
		_global.notify_user("Failed to load normal map.")
		return
	_undo_manager.save_state()
	_global.heldSprite.setNormalMap(image, path)
	_undo_manager.invalidate_normal(_global.heldSprite.id)
	sync()


func _on_clear_pressed() -> void:
	if _global.heldSprite == null or not _global.heldSprite.hasNormalMap():
		return
	_undo_manager.save_state()
	_global.heldSprite.clearNormalMap()
	_undo_manager.invalidate_normal(_global.heldSprite.id)
	sync()
