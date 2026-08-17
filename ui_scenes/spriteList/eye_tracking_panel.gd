extends RefCounted

var _owner: Node2D
var _global: Node
var _undo_manager: Node
var _sidebar_ui: Script
var _slider_theme: Dictionary

var _section: VBoxContainer
var _toggle: CheckBox
var _distance_label: Label
var _distance_slider: HSlider
var _speed_label: Label
var _speed_slider: HSlider
var _invert: CheckBox
var _type_option: OptionButton
var _mode_option: OptionButton
var _pick_button: Button
var _whip_line: Line2D
var _tooltip_label: Label
var _tooltip_timer: Timer
var _sliders_enabled := true


func build(
		owner: Node2D,
		content: VBoxContainer,
		global: Node,
		undo_manager: Node,
		sidebar_ui: Script,
		slider_theme: Dictionary,
) -> void:
	_owner = owner
	_global = global
	_undo_manager = undo_manager
	_sidebar_ui = sidebar_ui
	_slider_theme = slider_theme
	_section = VBoxContainer.new()
	_section.add_theme_constant_override("separation", _global.UI_ROW_GAP)
	_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_section)

	var label_color := Color(0.75, 0.75, 0.8)
	_build_toggle_row(label_color)
	_build_type_row(label_color)
	_build_target_row(label_color)
	_build_overlays()
	_build_sliders(label_color)


func refresh_ui() -> void:
	var scope := _scope()
	_toggle.text = "Enable (Layer)" if _global.heldSprite != null else "Enable (Global)"
	if scope == "per_layer":
		_refresh_per_layer()
	elif scope == "global":
		_refresh_global()
	else:
		_refresh_dead()
	_sync_slider_theme(scope != "dead")


func refresh_pick_whip() -> void:
	if _global.eyeTrackPickMode and _pick_button.visible:
		var anchor_global := _pick_button.global_position + _pick_button.size * 0.5
		_whip_line.clear_points()
		_whip_line.add_point(_owner.to_local(anchor_global))
		_whip_line.add_point(_owner.to_local(_owner.get_global_mouse_position()))
		_whip_line.visible = true
	else:
		_whip_line.visible = false


func _build_toggle_row(label_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_section.add_child(row)
	_toggle = CheckBox.new()
	_toggle.text = "Enable (Global)"
	_toggle.add_theme_font_size_override("font_size", 12)
	_toggle.add_theme_color_override("font_color", label_color)
	_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle.toggled.connect(_on_toggled)
	row.add_child(_toggle)
	_invert = CheckBox.new()
	_invert.text = "Invert direction"
	_invert.add_theme_font_size_override("font_size", 12)
	_invert.add_theme_color_override("font_color", label_color)
	_invert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_invert.toggled.connect(_on_invert_toggled)
	row.add_child(_invert)


func _build_type_row(label_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_section.add_child(row)
	var label := Label.new()
	label.text = "Mode:"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", label_color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_type_option = OptionButton.new()
	_type_option.add_item("Position", 0)
	_type_option.add_item("Rotation", 1)
	_type_option.add_theme_font_size_override("font_size", 12)
	_type_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_type_option.custom_minimum_size = Vector2(0, 22)
	_type_option.item_selected.connect(_on_type_selected)
	row.add_child(_type_option)


func _build_target_row(label_color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_section.add_child(row)
	var label := Label.new()
	label.text = "Target:"
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", label_color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	_mode_option = OptionButton.new()
	_mode_option.add_item("Cursor", 0)
	_mode_option.add_item("Layer", 1)
	_mode_option.add_theme_font_size_override("font_size", 12)
	_mode_option.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_mode_option.custom_minimum_size = Vector2(0, 22)
	_mode_option.item_selected.connect(_on_mode_selected)
	_mode_option.mouse_entered.connect(_on_target_hovered)
	_mode_option.mouse_exited.connect(_on_target_unhovered)
	_mode_option.gui_input.connect(_on_target_gui_input)
	row.add_child(_mode_option)
	_pick_button = Button.new()
	_pick_button.text = "Pick"
	_pick_button.flat = true
	_pick_button.add_theme_font_size_override("font_size", 12)
	_pick_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_pick_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_pick_button.custom_minimum_size = Vector2(50, 22)
	_pick_button.pressed.connect(_on_pick_pressed)
	_pick_button.visible = false
	row.add_child(_pick_button)


func _build_overlays() -> void:
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 12)
	_tooltip_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1))
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	background.content_margin_left = 6
	background.content_margin_right = 6
	background.content_margin_top = 3
	background.content_margin_bottom = 3
	background.set_corner_radius_all(3)
	_tooltip_label.add_theme_stylebox_override("normal", background)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_label.visible = false
	_tooltip_label.z_index = 4095
	_owner.add_child(_tooltip_label)
	_tooltip_timer = Timer.new()
	_tooltip_timer.one_shot = true
	_tooltip_timer.wait_time = 2.0
	_tooltip_timer.timeout.connect(_show_tooltip)
	_owner.add_child(_tooltip_timer)
	_whip_line = Line2D.new()
	_whip_line.width = 2.0
	_whip_line.default_color = Color(1.0, 0.85, 0.35, 0.9)
	_whip_line.visible = false
	_whip_line.z_index = 4090
	_owner.add_child(_whip_line)


func _build_sliders(label_color: Color) -> void:
	_distance_label = Label.new()
	_distance_label.text = "tracking distance: 20.0"
	_distance_label.add_theme_font_size_override("font_size", 12)
	_distance_label.add_theme_color_override("font_color", label_color)
	_section.add_child(_distance_label)
	_distance_slider = HSlider.new()
	_distance_slider.scrollable = false
	_distance_slider.min_value = 1.0
	_distance_slider.max_value = 200.0
	_distance_slider.step = 1.0
	_distance_slider.value = 20.0
	_distance_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_distance_slider.custom_minimum_size = Vector2(0, 16)
	_distance_slider.value_changed.connect(_on_distance_changed)
	_sidebar_ui.apply_slider_theme(_distance_slider, _slider_theme)
	_section.add_child(_distance_slider)
	_global.make_slider_resettable(_distance_slider, 20.0)
	_speed_label = Label.new()
	_speed_label.text = "tracking speed: 0.15"
	_speed_label.add_theme_font_size_override("font_size", 12)
	_speed_label.add_theme_color_override("font_color", label_color)
	_section.add_child(_speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.scrollable = false
	_speed_slider.min_value = 0.01
	_speed_slider.max_value = 1.0
	_speed_slider.step = 0.01
	_speed_slider.value = 0.15
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.custom_minimum_size = Vector2(0, 16)
	_speed_slider.value_changed.connect(_on_speed_changed)
	_sidebar_ui.apply_slider_theme(_speed_slider, _slider_theme)
	_section.add_child(_speed_slider)
	_global.make_slider_resettable(_speed_slider, 0.15)


func _on_toggled(pressed: bool) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state()
		_global.heldSprite.eyeTrack = pressed
	elif scope == "global":
		_undo_manager.save_state()
		_global.eyeTrackingGloballyEnabled = pressed


func _on_distance_changed(value: float) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state_continuous()
		_update_amount_label()
		_global.heldSprite.eyeTrackDistance = value
	elif scope == "global":
		_undo_manager.save_state_continuous()
		_update_amount_label()
		for sprite in _tracked_sprites():
			sprite.eyeTrackDistance = value


func _on_speed_changed(value: float) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state_continuous()
		_speed_label.text = "tracking speed: " + str(value)
		_global.heldSprite.eyeTrackSpeed = value
	elif scope == "global":
		_undo_manager.save_state_continuous()
		_speed_label.text = "tracking speed: " + str(value)
		for sprite in _tracked_sprites():
			sprite.eyeTrackSpeed = value


func _on_invert_toggled(pressed: bool) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state()
		_global.heldSprite.eyeTrackInvert = pressed
	elif scope == "global":
		_undo_manager.save_state()
		for sprite in _tracked_sprites():
			sprite.eyeTrackInvert = pressed


func _on_type_selected(index: int) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state()
		_global.heldSprite.eyeTrackType = index
	elif scope == "global":
		_undo_manager.save_state()
		for sprite in _tracked_sprites():
			sprite.eyeTrackType = index
	refresh_ui()


func _on_mode_selected(index: int) -> void:
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state()
		_global.heldSprite.eyeTrackMode = index
	elif scope == "global":
		_undo_manager.save_state()
		for sprite in _tracked_sprites():
			sprite.eyeTrackMode = index
	if _global.eyeTrackPickMode:
		_global.cancel_eye_track_pick()
	refresh_ui()


func _on_pick_pressed() -> void:
	var scope := _scope()
	if scope == "per_layer":
		_global.begin_eye_track_pick(_global.heldSprite)
		_global.notify_user("Click a layer to track (right-click to cancel).")
	elif scope == "global":
		_global.begin_eye_track_pick(null, true)
		_global.notify_user("Click a layer to broadcast as target (right-click to cancel).")
	refresh_pick_whip()


func _on_target_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed or _mode_option.selected != 1:
		return
	_mode_option.accept_event()
	_clear_target()


func _clear_target() -> void:
	if _full_target_name().is_empty():
		return
	var scope := _scope()
	if scope == "per_layer":
		_undo_manager.save_state()
		_global.heldSprite.eyeTrackTargetId = null
	elif scope == "global":
		_undo_manager.save_state()
		for sprite in _tracked_sprites():
			sprite.eyeTrackTargetId = null
	refresh_ui()


func _scope() -> String:
	if _global.heldSprite != null:
		return "per_layer"
	for sprite in _global.sprite_nodes():
		if sprite.eyeTrack:
			return "global"
	return "dead"


func _tracked_sprites() -> Array:
	var tracked := []
	for sprite in _global.sprite_nodes():
		if sprite.eyeTrack:
			tracked.append(sprite)
	return tracked


func _refresh_per_layer() -> void:
	var sprite = _global.heldSprite
	_toggle.disabled = false
	_toggle.set_pressed_no_signal(sprite.eyeTrack)
	_type_option.disabled = false
	_type_option.selected = sprite.eyeTrackType
	_mode_option.disabled = false
	_mode_option.selected = sprite.eyeTrackMode
	_invert.disabled = false
	_invert.set_pressed_no_signal(sprite.eyeTrackInvert)
	_distance_slider.editable = true
	_speed_slider.editable = true
	_distance_slider.set_value_no_signal(sprite.eyeTrackDistance)
	_speed_slider.set_value_no_signal(sprite.eyeTrackSpeed)
	_update_amount_label()
	_speed_label.text = "tracking speed: " + str(sprite.eyeTrackSpeed)
	_pick_button.visible = sprite.eyeTrackMode == 1
	_pick_button.disabled = false
	_update_layer_item_label()


func _refresh_global() -> void:
	_toggle.disabled = false
	_toggle.set_pressed_no_signal(_global.eyeTrackingGloballyEnabled)
	_type_option.disabled = false
	_mode_option.disabled = false
	_invert.disabled = false
	_distance_slider.editable = true
	_speed_slider.editable = true
	var agreed_type = _agreed_value("eyeTrackType")
	var agreed_mode = _agreed_value("eyeTrackMode")
	var agreed_invert = _agreed_value("eyeTrackInvert")
	var agreed_distance = _agreed_value("eyeTrackDistance")
	var agreed_speed = _agreed_value("eyeTrackSpeed")
	_type_option.selected = agreed_type if agreed_type != null else 0
	_mode_option.selected = agreed_mode if agreed_mode != null else 0
	_invert.set_pressed_no_signal(agreed_invert if agreed_invert != null else false)
	_distance_slider.set_value_no_signal(agreed_distance if agreed_distance != null else _distance_slider.min_value)
	_speed_slider.set_value_no_signal(agreed_speed if agreed_speed != null else _speed_slider.min_value)
	_update_amount_label()
	_speed_label.text = "tracking speed: " + str(_speed_slider.value)
	_pick_button.visible = _mode_option.selected == 1
	_pick_button.disabled = false
	_update_layer_item_label()


func _refresh_dead() -> void:
	_toggle.disabled = true
	_toggle.set_pressed_no_signal(false)
	_type_option.disabled = true
	_type_option.selected = 0
	_mode_option.disabled = true
	_mode_option.selected = 0
	_invert.disabled = true
	_invert.set_pressed_no_signal(false)
	_distance_slider.editable = false
	_speed_slider.editable = false
	_distance_slider.set_value_no_signal(_distance_slider.min_value)
	_speed_slider.set_value_no_signal(_speed_slider.min_value)
	_distance_label.text = "tracking distance: —"
	_speed_label.text = "tracking speed: —"
	_pick_button.visible = false
	_mode_option.set_item_text(1, "Layer")


func _agreed_value(property: String):
	var initialized := false
	var agreed = null
	for sprite in _tracked_sprites():
		if not initialized:
			agreed = sprite.get(property)
			initialized = true
		elif sprite.get(property) != agreed:
			return null
	return agreed


func _update_amount_label() -> void:
	if _type_option.selected == 1:
		_distance_label.text = "max tilt: " + str(_distance_slider.value) + "°"
	else:
		_distance_label.text = "tracking distance: " + str(_distance_slider.value)


func _full_target_name() -> String:
	if _global.heldSprite != null:
		var sprite = _global.heldSprite
		if sprite.eyeTrackMode != 1 or sprite.eyeTrackTargetId == null:
			return ""
		return _display_target_name(_global.sprite_by_id(sprite.eyeTrackTargetId))
	var target_id = null
	var initialized := false
	for sprite in _tracked_sprites():
		if not initialized:
			target_id = sprite.eyeTrackTargetId
			initialized = true
		elif sprite.eyeTrackTargetId != target_id:
			return ""
	if not initialized or target_id == null:
		return ""
	return _display_target_name(_global.sprite_by_id(target_id))


func _update_layer_item_label() -> void:
	var full_name := _full_target_name()
	if full_name.is_empty():
		_mode_option.set_item_text(1, "Layer")
		return
	_mode_option.set_item_text(1, full_name if full_name.length() <= 8 else full_name.substr(0, 8) + "…")


func _display_target_name(target_sprite) -> String:
	if not is_instance_valid(target_sprite):
		return ""
	var path: String = str(target_sprite.path)
	if path.is_empty():
		return "(unnamed)"
	var leaf := path.get_file()
	if leaf.is_empty():
		leaf = path
	var dot := leaf.rfind(".")
	return leaf.substr(0, dot) if dot > 0 else leaf


func _on_target_hovered() -> void:
	if not _full_target_name().is_empty():
		_tooltip_timer.start()


func _on_target_unhovered() -> void:
	_tooltip_timer.stop()
	_tooltip_label.visible = false


func _show_tooltip() -> void:
	var full_name := _full_target_name()
	if full_name.is_empty():
		return
	_tooltip_label.text = full_name
	var anchor_global := _mode_option.global_position + Vector2(0, _mode_option.size.y + 4)
	_tooltip_label.position = _owner.to_local(anchor_global)
	_tooltip_label.visible = true


func _sync_slider_theme(enabled: bool) -> void:
	if enabled == _sliders_enabled:
		return
	_sliders_enabled = enabled
	for slider in [_distance_slider, _speed_slider]:
		_sidebar_ui.apply_slider_theme(slider, _slider_theme, enabled)
