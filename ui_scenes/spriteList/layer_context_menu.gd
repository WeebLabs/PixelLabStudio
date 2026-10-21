extends RefCounted

## The right-click menu on a layer row, and what each item opens.
##
## Duplicate acts immediately, rename opens the row's own name field, and delete
## asks first, because it is the one action that can take more of the rig than
## the layer the user clicked.
##
## Layout and palette come from ModalDialogUI, so this only declares the copy and
## the choices.

const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

const ITEM_DUPLICATE := 0
const ITEM_RENAME := 1
const ITEM_REPLACE := 2
const ITEM_DELETE := 3

const DELETE_PANEL := Vector2(420, 0)

# Menus are built per click and freed on close, so a menu never outlives the row
# it belongs to.
static func open(list: Node, sprite) -> PopupMenu:
	if sprite == null or not is_instance_valid(sprite):
		return null
	# Rename and replace name one layer and act on it, so they are not offered
	# for a group: the menu only shows what it can actually do to everything
	# selected.
	var selected: Array = Global.selected_sprites()
	var group: bool = selected.size() > 1 and selected.has(sprite)
	var menu := PopupMenu.new()
	menu.add_item("Duplicate %d layers" % selected.size() if group else "Duplicate", ITEM_DUPLICATE)
	if not group:
		menu.add_item("Rename", ITEM_RENAME)
		menu.add_item("Replace", ITEM_REPLACE)
	menu.add_separator()
	menu.add_item("Delete %d layers..." % selected.size() if group else "Delete...", ITEM_DELETE)
	menu.id_pressed.connect(func(id: int): _activate(list, sprite, id))
	menu.popup_hide.connect(func(): menu.queue_free())
	list.get_tree().root.add_child(menu)
	menu.popup(Rect2i(_cursor_position(list), Vector2i(0, 0)))
	return menu


# Where to put the menu, which depends on who is drawing it. Godot embeds
# subwindows in the main viewport by default, and an embedded popup is placed in
# the VIEWPORT's coordinates, not the screen's. Handing it screen pixels put the
# menu far to the right of the viewport, where it was clamped into the top-right
# corner. Only a popup that is a real OS window wants screen pixels.
static func _cursor_position(list: Node) -> Vector2i:
	var root := list.get_tree().root
	if root.gui_embed_subwindows:
		return Vector2i(root.get_mouse_position())
	return DisplayServer.mouse_get_position()


static func _activate(list: Node, sprite, id: int) -> void:
	if not is_instance_valid(sprite):
		return
	match id:
		ITEM_DUPLICATE:
			if not Global.is_sprite_selected(sprite):
				Global.select_sprite(sprite)
			Global.spriteEdit.setImage()
			Global.main.duplicate_selected_layer()
		ITEM_RENAME:
			begin_rename(list, sprite)
		ITEM_REPLACE:
			Global.main.replace_layer(sprite)
		ITEM_DELETE:
			confirm_delete(list, sprite)


# Renaming happens on the row itself rather than in a prompt, so the menu item
# only has to open that field. The menu is still closing when the item fires and
# takes the keyboard focus with it on the way out, so the field grabs focus a
# frame later.
static func begin_rename(list: Node, sprite) -> void:
	if not is_instance_valid(sprite) or list == null:
		return
	list.call_deferred("beginRename", sprite)


static func confirm_delete(list: Node, sprite) -> void:
	var targets: Array = Global.selected_sprites()
	if not (targets.size() > 1 and targets.has(sprite)):
		targets = [sprite]
	var children := 0
	for target in targets:
		for descendant in target.getAllDescendants():
			if not targets.has(descendant):
				children += 1

	var dialog := ModalDialogUI.new()
	_ui_layer(list).add_child(dialog)
	dialog.set_panel_min_size(DELETE_PANEL)
	if targets.size() > 1:
		dialog.set_title("Delete %d layers?" % targets.size())
	else:
		dialog.set_title("Delete \"%s\"?" % sprite.displayName())

	if children > 0:
		dialog.add_message(
			"%d layer%s sit%s under %s. They are kept by default and move up to the deleted layer's own parent."
			% [
				children, "" if children == 1 else "s", "s" if children == 1 else "",
				"this layer" if targets.size() == 1 else "these layers",
			]
		)
	else:
		dialog.add_message("Nothing is linked under %s." % ("this layer" if targets.size() == 1 else "these layers"))
	# The checkbox is always on the prompt, greyed when there is nothing under
	# this layer, so the choice reads the same way every time.
	var with_children := dialog.add_checkbox("Also delete the layers under it", false)
	with_children.disabled = children == 0

	dialog.add_actions([
		{
			"text": "Delete",
			"danger": true,
			"callback": func():
				var include := with_children.button_pressed
				dialog.queue_free()
				Global.main.delete_layers(targets, include),
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
