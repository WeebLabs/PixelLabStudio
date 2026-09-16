extends RefCounted

## The "Visibility Toggle" section of the right sidebar: the key binding that
## shows and hides a layer while the avatar is live.
##
## Built here rather than in the sidebar so the sidebar stays a layout facade,
## the same split the blend strip and the physics tab already use.

const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const LABEL_COLOR := Color(0.75, 0.75, 0.8)
const TEXT_COLOR := Color(0.85, 0.85, 0.9)
const TEXT_DISABLED := Color(0.35, 0.35, 0.4)
const AWAITING_COLOR := Color(1.0, 0.7, 0.8)

var section: VBoxContainer = null

var _set_key_btn: Button = null
var _label: Label = null
var _clear_btn: Button = null


func build(owner: Node) -> VBoxContainer:
	section = VBoxContainer.new()
	section.add_theme_constant_override("separation", Global.UI_ROW_GAP)
	owner.add_child(section)

	var header := Label.new()
	header.text = "Visibility Toggle"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", LABEL_COLOR)
	section.add_child(header)

	# Control row: [Set Key] [toggle: "..."]  ...  [x]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	section.add_child(row)

	_set_key_btn = Button.new()
	_set_key_btn.text = "Set Key"
	_set_key_btn.flat = true
	_set_key_btn.add_theme_font_size_override("font_size", 12)
	_set_key_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_set_key_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	_set_key_btn.pressed.connect(_on_set_key)
	row.add_child(_set_key_btn)

	_label = Label.new()
	_label.text = "toggle: \"null\""
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)

	_clear_btn = Button.new()
	_clear_btn.text = "x"
	_clear_btn.flat = true
	_clear_btn.add_theme_font_size_override("font_size", 11)
	_clear_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_clear_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.45, 0.5))
	_clear_btn.custom_minimum_size = Vector2(20, 0)
	_clear_btn.pressed.connect(_on_clear)
	row.add_child(_clear_btn)
	return section


func set_enabled(enabled: bool) -> void:
	if _label == null:
		return
	_set_key_btn.disabled = not enabled
	_clear_btn.disabled = not enabled
	if not enabled:
		_label.add_theme_color_override("font_color", TEXT_DISABLED)
	elif not Global.awaitingToggleBind:
		_label.add_theme_color_override("font_color", TEXT_COLOR)


# Read the held layer's binding back into the label.
func refresh() -> void:
	if _label != null and Global.heldSprite != null:
		_label.text = "toggle: \"" + Global.heldSprite.toggle + "\""


# Capture the next key the app sees and bind it to the held layer.
func _on_set_key() -> void:
	if Global.heldSprite == null:
		return
	_label.text = "toggle: AWAITING INPUT"
	_label.add_theme_color_override("font_color", AWAITING_COLOR)
	Global.begin_visibility_key_capture()
	await Global.main.visibility_binding_armed
	var keys = await Global.main.spriteVisToggles
	Global.finish_visibility_key_capture()
	if Global.heldSprite == null:
		return
	MutationCommands.set_layer_property(Global.heldSprite, "toggle", keys[0])
	refresh()
	_label.add_theme_color_override("font_color", TEXT_COLOR)


func _on_clear() -> void:
	if Global.heldSprite == null:
		return
	MutationCommands.set_layer_property(Global.heldSprite, "toggle", "null")
	refresh()
	Global.heldSprite.makeVis()
