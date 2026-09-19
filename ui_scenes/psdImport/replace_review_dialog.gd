extends Node2D

const SidebarUIFactory = preload("res://ui_scenes/common/sidebar_ui.gd")

signal replace_confirmed(matched: Array, new_items: Array, orphaned_sprites: Array, canvas_size: Vector2, remove_orphans: bool)
signal replace_cancelled

var _matched: Array = []
var _new_items: Array = []
var _orphaned_sprites: Array = []
var _canvas_size: Vector2 = Vector2.ZERO

var _new_checkboxes: Array = []  # Array of {checkbox: CheckBox, item: Dictionary}
# Matched layers are ticked by default, so confirming without touching them
# replaces every match as before. Unticking one leaves that layer as it is.
var _matched_checkboxes: Array = []  # Array of {checkbox: CheckBox, entry: Dictionary}
var _remove_orphans_check: CheckBox = null

var _layerList: VBoxContainer
var _titleLabel: Label
var _summaryLabel: Label
var _blocker: Area2D
var _orphan_section: VBoxContainer
var _remove_orphan_row: HBoxContainer
var _warning_label: Label

func _ready():
	z_index = 4095
	visibility_layer = 2
	_build_ui()
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed():
	if visible and Global.main != null:
		position = Global.main.camera.position

func _build_ui():
	# Blocker Area2D
	_blocker = Area2D.new()
	_blocker.add_to_group("canvas_input_blocker")
	var col = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(3840, 2160)
	col.shape = shape
	_blocker.add_child(col)
	add_child(_blocker)

	# Panel background
	var panel_bg = ColorRect.new()
	panel_bg.position = Vector2(-260, -250)
	panel_bg.size = Vector2(520, 500)
	panel_bg.color = SidebarUIFactory.DEFAULT_PANEL_COLOR
	panel_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel_bg)

	# Title
	_titleLabel = Label.new()
	_titleLabel.position = Vector2(-250, -240)
	_titleLabel.size = Vector2(500, 30)
	_titleLabel.text = "Replace"
	_titleLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titleLabel.add_theme_font_size_override("font_size", 18)
	add_child(_titleLabel)

	# Summary
	_summaryLabel = Label.new()
	_summaryLabel.position = Vector2(-250, -210)
	_summaryLabel.size = Vector2(500, 24)
	_summaryLabel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summaryLabel.add_theme_font_size_override("font_size", 12)
	_summaryLabel.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	add_child(_summaryLabel)

	# Warning label (shown when 0 matches)
	_warning_label = Label.new()
	_warning_label.position = Vector2(-250, -185)
	_warning_label.size = Vector2(500, 24)
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_label.add_theme_font_size_override("font_size", 13)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_warning_label.text = "No matching sprites found — layers will be added as new."
	_warning_label.visible = false
	add_child(_warning_label)

	# Scroll container for layer list
	var scroll = ScrollContainer.new()
	scroll.position = Vector2(-250, -160)
	scroll.size = Vector2(500, 310)
	add_child(scroll)

	_layerList = VBoxContainer.new()
	_layerList.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_layerList)

	# Replace / Cancel buttons
	var buttons = HBoxContainer.new()
	buttons.position = Vector2(-120, 180)
	buttons.size = Vector2(240, 40)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	add_child(buttons)

	var replaceBtn = Button.new()
	replaceBtn.text = "Replace"
	replaceBtn.custom_minimum_size = Vector2(100, 32)
	replaceBtn.pressed.connect(_on_replace)
	buttons.add_child(replaceBtn)

	var cancelBtn = Button.new()
	cancelBtn.text = "Cancel"
	cancelBtn.custom_minimum_size = Vector2(100, 32)
	cancelBtn.pressed.connect(_on_cancel)
	buttons.add_child(cancelBtn)

func setup(matched: Array, new_items: Array, orphaned_sprites: Array, canvas_size: Vector2):
	_matched = matched
	_new_items = new_items
	_orphaned_sprites = orphaned_sprites
	_canvas_size = canvas_size
	_new_checkboxes.clear()
	_matched_checkboxes.clear()

	# Clear existing entries
	for child in _layerList.get_children():
		child.queue_free()

	# Summary text
	var parts = []
	if matched.size() > 0:
		parts.append(str(matched.size()) + " matched")
	if new_items.size() > 0:
		parts.append(str(new_items.size()) + " new")
	if orphaned_sprites.size() > 0:
		parts.append(str(orphaned_sprites.size()) + " orphaned")
	_summaryLabel.text = ", ".join(parts)

	# Warning for 0 matches
	_warning_label.visible = matched.size() == 0

	# --- Will Be Replaced section ---
	if matched.size() > 0:
		_add_section_header("Will Be Replaced", _matched_checkboxes)
		for entry in matched:
			_add_matched_entry(entry)

	# --- New (not in project) section ---
	if new_items.size() > 0:
		_add_section_header("New (not in project)", _new_checkboxes)
		for item in new_items:
			_add_new_entry(item)

	# --- Orphaned section ---
	if orphaned_sprites.size() > 0:
		_add_section_header("In Project, Not in Source")
		for sprite in orphaned_sprites:
			_add_orphan_entry(sprite)

		# Remove orphans checkbox
		_remove_orphan_row = HBoxContainer.new()
		_remove_orphan_row.custom_minimum_size.y = 32
		_remove_orphans_check = CheckBox.new()
		_remove_orphans_check.button_pressed = false
		_remove_orphans_check.text = "Remove sprites not found in source"
		_remove_orphans_check.add_theme_font_size_override("font_size", 12)
		_remove_orphan_row.add_child(_remove_orphans_check)
		_layerList.add_child(_remove_orphan_row)
	else:
		_remove_orphans_check = null

# `toggles` is the section's checkbox list when its rows can be ticked. It is
# filled after the header is built, and read when a button is pressed, so the
# buttons act on every row the section ends up with.
func _add_section_header(text: String, toggles = null):
	var sep = HSeparator.new()
	sep.custom_minimum_size.y = 8
	_layerList.add_child(sep)

	var header = HBoxContainer.new()
	_layerList.add_child(header)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_HEADING)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)

	if toggles == null:
		return
	# A PSD can bring well over a hundred layers, and picking a few out of them
	# one checkbox at a time is not workable.
	for choice in [["All", true], ["None", false]]:
		var button = Button.new()
		button.text = choice[0]
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
		button.pressed.connect(_set_all.bind(toggles, choice[1]))
		header.add_child(button)


func _set_all(toggles: Array, ticked: bool) -> void:
	for row in toggles:
		row["checkbox"].button_pressed = ticked

func _add_matched_entry(entry: Dictionary):
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 48

	var check = CheckBox.new()
	check.button_pressed = true
	check.custom_minimum_size = Vector2(24, 24)
	row.add_child(check)
	_matched_checkboxes.append({"checkbox": check, "entry": entry})

	# Thumbnail
	var thumb_rect = _make_thumbnail(entry["image"])
	row.add_child(thumb_rect)

	# Info
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# The rig's own name leads, because that is what the user sees in the layer
	# list; the source layer it matched is named underneath whenever the two
	# differ, so a renamed layer is still identifiable against the file.
	var name_label = Label.new()
	name_label.text = _layer_name(entry["sprite"], entry["name"])
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)

	var source_note := _source_note(entry["sprite"])
	if source_note != "":
		info.add_child(_make_source_label(source_note))

	var dims = entry["image"].get_size()
	var dims_label = Label.new()
	dims_label.text = str(int(dims.x)) + " x " + str(int(dims.y))
	dims_label.add_theme_font_size_override("font_size", 11)
	dims_label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	info.add_child(dims_label)

	row.add_child(info)
	_layerList.add_child(row)

func _add_new_entry(item: Dictionary):
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 48

	# Checkbox
	var check = CheckBox.new()
	check.button_pressed = false
	check.custom_minimum_size = Vector2(24, 24)
	row.add_child(check)
	_new_checkboxes.append({"checkbox": check, "item": item})

	# Thumbnail
	var thumb_rect = _make_thumbnail(item["image"])
	row.add_child(thumb_rect)

	# Info
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label = Label.new()
	name_label.text = item["name"]
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)

	var dims = item["image"].get_size()
	var dims_label = Label.new()
	dims_label.text = str(int(dims.x)) + " x " + str(int(dims.y))
	dims_label.add_theme_font_size_override("font_size", 11)
	dims_label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	info.add_child(dims_label)

	row.add_child(info)
	_layerList.add_child(row)

func _add_orphan_entry(sprite_node):
	var row = HBoxContainer.new()
	row.custom_minimum_size.y = 32

	var warn_label = Label.new()
	warn_label.text = "⚠"
	warn_label.add_theme_font_size_override("font_size", 14)
	warn_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	warn_label.custom_minimum_size = Vector2(24, 24)
	row.add_child(warn_label)

	# An orphan is the one row the user has to make a decision about, so it is
	# named the way the layer list names it, with its source name alongside when
	# it has been renamed.
	var info = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label = Label.new()
	name_label.text = _layer_name(sprite_node, "")
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)

	var source_note := _source_note(sprite_node)
	if source_note != "":
		info.add_child(_make_source_label(source_note))

	row.add_child(info)
	_layerList.add_child(row)


# What to call this layer: its own name, falling back to the source name the
# match was made on for anything that cannot answer.
static func _layer_name(sprite_node, fallback: String) -> String:
	if sprite_node != null and is_instance_valid(sprite_node) and sprite_node.has_method("displayName"):
		var shown: String = sprite_node.displayName()
		if shown != "":
			return shown
	return fallback


# The line under the name, or "" when the layer still carries its source name and
# the note would only repeat it. A matched row's own name is the name it matched
# on either way, so the note only has to supply the one the user cannot see.
static func _source_note(sprite_node) -> String:
	if sprite_node == null or not is_instance_valid(sprite_node):
		return ""
	var source := _extract_sprite_name(sprite_node.path)
	if _layer_name(sprite_node, source).to_lower() == source.to_lower():
		return ""
	return "imported as \"%s\"" % source


static func _make_source_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", SidebarUIFactory.TEXT_BODY)
	return label

func _make_thumbnail(img: Image) -> TextureRect:
	var thumb_rect = TextureRect.new()
	var thumb_img = img.duplicate()
	if thumb_img.get_width() > 40 or thumb_img.get_height() > 40:
		var scale = 40.0 / max(thumb_img.get_width(), thumb_img.get_height())
		thumb_img.resize(int(thumb_img.get_width() * scale), int(thumb_img.get_height() * scale), Image.INTERPOLATE_BILINEAR)
	var thumb_tex = ImageTexture.create_from_image(thumb_img)
	thumb_rect.texture = thumb_tex
	thumb_rect.custom_minimum_size = Vector2(40, 40)
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return thumb_rect

static func _extract_sprite_name(sprite_path: String) -> String:
	if sprite_path.begins_with("psd://"):
		return sprite_path.substr(6)
	if sprite_path.begins_with("animated://"):
		return sprite_path.substr(11)
	var filename = sprite_path.get_file()
	var ext = filename.get_extension()
	if ext != "":
		filename = filename.substr(0, filename.length() - ext.length() - 1)
	return filename

func _on_replace():
	# Only the ticked rows go through. An unticked match is left alone, and is not
	# an orphan either: the layer is in the source, the user chose not to update it.
	var selected_matched = []
	for row in _matched_checkboxes:
		if row["checkbox"].button_pressed:
			selected_matched.append(row["entry"])
	var selected_new = []
	for entry in _new_checkboxes:
		if entry["checkbox"].button_pressed:
			selected_new.append(entry["item"])

	var remove_orphans = _remove_orphans_check != null and _remove_orphans_check.button_pressed

	visible = false
	replace_confirmed.emit(selected_matched, selected_new, _orphaned_sprites, _canvas_size, remove_orphans)

func _on_cancel():
	visible = false
	replace_cancelled.emit()
