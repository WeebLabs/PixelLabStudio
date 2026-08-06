extends Node2D

signal import_confirmed(selected_layers: Array, canvas_size: Vector2, normal_layers: Dictionary)
signal import_cancelled

var psd_file = null
var layer_entries: Array = []  # Array of {layer, checkbox}
var normal_layers: Dictionary = {}  # base_name (lower) -> layer

var layerList: VBoxContainer
var titleLabel: Label
var blocker: Area2D
var _filter_field: LineEdit

func _ready():
	z_index = 4095
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed():
	if visible and Global.main != null:
		# Center dialog on camera/viewport
		var cam = Global.main.camera
		position = cam.position

func _build_ui():
	# Blocker Area2D to prevent sprite interaction
	blocker = Area2D.new()
	blocker.add_to_group("canvas_input_blocker")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	blocker.add_child(col)
	add_child(blocker)

	# Panel background
	var panel_bg = ColorRect.new()
	panel_bg.position = Vector2(-250, -230)
	panel_bg.size = Vector2(500, 460)
	panel_bg.color = Color(0.15, 0.15, 0.15, 1.0)
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_bg)

	# Title
	titleLabel = Label.new()
	titleLabel.position = Vector2(-240, -220)
	titleLabel.size = Vector2(480, 30)
	titleLabel.text = "Import PSD"
	titleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titleLabel.add_theme_font_size_override("font_size", 18)
	add_child(titleLabel)

	# Filter field
	_filter_field = LineEdit.new()
	_filter_field.placeholder_text = "Filter layers..."
	_filter_field.position = Vector2(-240, -185)
	_filter_field.size = Vector2(480, 28)
	_filter_field.add_theme_font_size_override("font_size", 13)
	_filter_field.clear_button_enabled = true
	_filter_field.caret_blink = true
	_filter_field.caret_blink_interval = 0.5
	_filter_field.text_changed.connect(_on_filter_changed)
	var fs_normal = StyleBoxFlat.new()
	fs_normal.bg_color = Color(0.1, 0.1, 0.1)
	fs_normal.set_corner_radius_all(3)
	fs_normal.content_margin_left = 6
	fs_normal.content_margin_right = 6
	fs_normal.content_margin_top = 4
	fs_normal.content_margin_bottom = 4
	var fs_focus = fs_normal.duplicate()
	fs_focus.border_color = Color(0.45, 0.45, 0.5)
	fs_focus.set_border_width_all(1)
	_filter_field.add_theme_stylebox_override("normal", fs_normal)
	_filter_field.add_theme_stylebox_override("focus", fs_focus)
	add_child(_filter_field)

	# Scroll container for layer list
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(-240, -149)
	scroll.size = Vector2(480, 254)
	add_child(scroll)

	layerList = VBoxContainer.new()
	layerList.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(layerList)

	# Options row
	var options = HBoxContainer.new()
	options.position = Vector2(-240, 115)
	options.size = Vector2(480, 32)
	add_child(options)

	var selectAllBtn = Button.new()
	selectAllBtn.text = "Select All"
	selectAllBtn.pressed.connect(_on_select_all)
	options.add_child(selectAllBtn)

	var selectNoneBtn = Button.new()
	selectNoneBtn.text = "Select None"
	selectNoneBtn.pressed.connect(_on_select_none)
	options.add_child(selectNoneBtn)

	# Import / Cancel buttons
	var buttons = HBoxContainer.new()
	buttons.position = Vector2(-120, 160)
	buttons.size = Vector2(240, 40)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(buttons)

	var importBtn = Button.new()
	importBtn.text = "Import"
	importBtn.custom_minimum_size = Vector2(100, 32)
	importBtn.pressed.connect(_on_import)
	buttons.add_child(importBtn)

	var cancelBtn = Button.new()
	cancelBtn.text = "Cancel"
	cancelBtn.custom_minimum_size = Vector2(100, 32)
	cancelBtn.pressed.connect(_on_cancel)
	buttons.add_child(cancelBtn)

func setup(psd):
	psd_file = psd
	_filter_field.text = ""

	# Clear existing entries
	for child in layerList.get_children():
		child.queue_free()
	layer_entries.clear()
	normal_layers.clear()

	var count = 0
	var nrml_count = 0
	for layer in psd.layers:
		# Skip zero-size layers (group dividers, adjustment layers)
		if layer.width <= 0 or layer.height <= 0:
			continue
		if layer.image == null:
			continue

		# Detect normal map layers — don't show in selection, track for pairing
		if layer.name.to_lower().ends_with("_nrml"):
			var base = layer.name.substr(0, layer.name.length() - 5)
			normal_layers[base.to_lower()] = layer
			nrml_count += 1
			continue

		count += 1

		var entry = HBoxContainer.new()
		entry.custom_minimum_size.y = 56

		# Checkbox
		var check = CheckBox.new()
		check.button_pressed = layer.visible
		check.custom_minimum_size = Vector2(24, 24)
		entry.add_child(check)

		# Thumbnail
		var thumb_rect = TextureRect.new()
		var thumb_img = layer.image.duplicate()
		if thumb_img.get_width() > 48 or thumb_img.get_height() > 48:
			thumb_img.resize(48, 48, Image.INTERPOLATE_BILINEAR)
		var thumb_tex = ImageTexture.create_from_image(thumb_img)
		thumb_rect.texture = thumb_tex
		thumb_rect.custom_minimum_size = Vector2(48, 48)
		thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		entry.add_child(thumb_rect)

		# Info container
		var info = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label = Label.new()
		name_label.text = layer.name
		name_label.add_theme_font_size_override("font_size", 14)
		info.add_child(name_label)

		var dims_label = Label.new()
		dims_label.text = str(layer.width) + " x " + str(layer.height)
		dims_label.add_theme_font_size_override("font_size", 11)
		dims_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		info.add_child(dims_label)

		entry.add_child(info)

		layerList.add_child(entry)
		layer_entries.append({"layer": layer, "checkbox": check, "entry": entry, "name": layer.name})

	if nrml_count > 0:
		titleLabel.text = "Import PSD (" + str(count) + " layers, " + str(nrml_count) + " normals detected)"
	else:
		titleLabel.text = "Import PSD (" + str(count) + " layers)"

func _on_select_all():
	for entry in layer_entries:
		entry["checkbox"].button_pressed = true

func _on_select_none():
	for entry in layer_entries:
		entry["checkbox"].button_pressed = false

func _on_import():
	var selected = []
	for entry in layer_entries:
		if entry["checkbox"].button_pressed:
			selected.append(entry["layer"])

	if selected.size() == 0:
		return

	visible = false
	var canvas_size = Vector2(psd_file.width, psd_file.height)
	import_confirmed.emit(selected, canvas_size, normal_layers)

func _on_cancel():
	visible = false
	import_cancelled.emit()

func _input(event):
	if event is InputEventMouseButton and event.pressed and _filter_field.has_focus():
		var local = get_local_mouse_position()
		var field_rect = Rect2(_filter_field.position, _filter_field.size)
		if not field_rect.has_point(local):
			_filter_field.release_focus()

func _on_filter_changed(text: String):
	var filter = text.to_lower()
	for item in layer_entries:
		if filter == "":
			item["entry"].visible = true
		else:
			item["entry"].visible = item["name"].to_lower().begins_with(filter)
