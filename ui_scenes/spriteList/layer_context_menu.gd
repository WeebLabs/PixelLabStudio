extends RefCounted

## The right-click menu on a layer row, and the two prompts it opens.
##
## Duplicate and rename act immediately; delete asks first, because it is the one
## action that can take more of the rig than the layer the user clicked.
##
## Layout and palette come from ModalDialogUI, so this only declares the copy and
## the choices.

const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")
const MutationCommands = preload("res://autoload/domain/mutation_commands.gd")

const ITEM_DUPLICATE := 0
const ITEM_RENAME := 1
const ITEM_DELETE := 2

const RENAME_PANEL := Vector2(360, 0)
const DELETE_PANEL := Vector2(420, 0)

# Menus are built per click and freed on close, so a menu never outlives the row
# it belongs to.
static func open(list: Node, sprite) -> PopupMenu:
	if sprite == null or not is_instance_valid(sprite):
		return null
	var menu := PopupMenu.new()
	menu.add_item("Duplicate", ITEM_DUPLICATE)
	menu.add_item("Rename...", ITEM_RENAME)
	menu.add_separator()
	menu.add_item("Delete...", ITEM_DELETE)
	menu.id_pressed.connect(func(id: int): _activate(list, sprite, id))
	menu.popup_hide.connect(func(): menu.queue_free())
	list.get_tree().root.add_child(menu)
	# The OS cursor position, not the Control's: the viewport is stretched
	# (window/stretch/scale), so control coordinates are not screen pixels and a
	# popup placed from them lands short of the cursor.
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i(0, 0)))
	return menu


static func _activate(list: Node, sprite, id: int) -> void:
	if not is_instance_valid(sprite):
		return
	match id:
		ITEM_DUPLICATE:
			Global.select_sprite(sprite)
			Global.spriteEdit.setImage()
			Global.main.duplicate_selected_layer()
		ITEM_RENAME:
			confirm_rename(list, sprite)
		ITEM_DELETE:
			confirm_delete(list, sprite)


static func confirm_rename(list: Node, sprite) -> void:
	var dialog := ModalDialogUI.new()
	_ui_layer(list).add_child(dialog)
	dialog.set_panel_min_size(RENAME_PANEL)
	dialog.set_title("Rename layer")
	var field: LineEdit = null
	var commit := func():
		if is_instance_valid(sprite) and field != null:
			MutationCommands.set_layer_property(sprite, "layerName", field.text.strip_edges())
			Global.spriteList.refreshNames()
		dialog.queue_free()
	field = dialog.add_text_field(sprite.displayName(), commit)
	dialog.add_actions([
		{"text": "Rename", "callback": commit},
		{"text": "Cancel", "callback": func(): dialog.queue_free()},
	])


static func confirm_delete(list: Node, sprite) -> void:
	var children: int = sprite.getAllDescendants().size()
	var dialog := ModalDialogUI.new()
	_ui_layer(list).add_child(dialog)
	dialog.set_panel_min_size(DELETE_PANEL)
	dialog.set_title("Delete \"%s\"?" % sprite.displayName())

	var with_children: CheckBox = null
	if children > 0:
		dialog.add_message(
			"This layer has %d layer%s under it. They are kept by default and move up to this layer's own parent."
			% [children, "" if children == 1 else "s"]
		)
		with_children = dialog.add_checkbox("Also delete the layers under it", false)

	dialog.add_actions([
		{
			"text": "Delete",
			"danger": true,
			"callback": func():
				var include := with_children != null and with_children.button_pressed
				dialog.queue_free()
				if is_instance_valid(sprite):
					Global.main.delete_layer(sprite, include),
		},
		{"text": "Cancel", "callback": func(): dialog.queue_free()},
	])


static func _ui_layer(list: Node) -> Node:
	# Dialogs belong on the UI layer, which is excluded from NDI output; the list
	# itself lives under it.
	var node: Node = list
	while node != null and not (node is CanvasLayer):
		node = node.get_parent()
	return node if node != null else list
