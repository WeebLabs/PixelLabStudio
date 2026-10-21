extends RefCounted

## The two dialogs the legacy full-canvas replace path needs: the compatibility
## offer, and the refusal when the PSD was authored at different dimensions.
##
## Layout, palette and centring come from ModalDialogUI; this only declares the
## copy and the choices, so the import controller stays a controller.

const ModalDialogUI = preload("res://ui_scenes/common/modal_dialog.gd")

const PANEL_SIZE := Vector2(560, 0)

# Choices reported by the compatibility prompt.
const CHOICE_COMPAT := "compat"
const CHOICE_PLAIN := "plain"
const CHOICE_CANCEL := "cancel"


static func show_compat_prompt(ui_layer: Node, rig_canvas: Vector2, psd_canvas: Vector2, layers: int, on_choice: Callable) -> ModalDialogUI:
	var text := "Every layer in this avatar is a full %s canvas, which is how layers were imported before PSD support existed. " % _dimensions(rig_canvas)
	text += "The layers in this PSD are cropped to their own bounds instead, so %d of them need their placement recalculated " % layers
	text += "from the %s PSD canvas to land where they already sit. " % _dimensions(psd_canvas)
	text += "Without it they collapse toward the middle of the avatar."

	var dialog := ModalDialogUI.new()
	ui_layer.add_child(dialog)
	dialog.set_panel_min_size(PANEL_SIZE)
	dialog.set_title("This avatar predates PSD import")
	dialog.add_message(text)
	dialog.add_actions([
		{"text": "Use compatibility placement", "callback": func(): on_choice.call(CHOICE_COMPAT)},
		{"text": "Replace without it", "callback": func(): on_choice.call(CHOICE_PLAIN), "danger": true},
		{"text": "Cancel", "callback": func(): on_choice.call(CHOICE_CANCEL)},
	])
	return dialog


static func show_canvas_mismatch(ui_layer: Node, rig_canvas: Vector2, psd_canvas: Vector2, on_dismiss: Callable) -> ModalDialogUI:
	var text := "This avatar was built from full-canvas layers measuring %s, but this PSD's canvas is %s. " % [_dimensions(rig_canvas), _dimensions(psd_canvas)]
	text += "Cropped layers carry their placement as a position inside their own canvas, so layers from a canvas of a different size "
	text += "cannot be re-aligned to the original artwork. The replace has been cancelled.\n\n"
	text += "Re-export the PSD at %s, or resize the document to match." % _dimensions(rig_canvas)

	var dialog := ModalDialogUI.new()
	ui_layer.add_child(dialog)
	dialog.set_panel_min_size(PANEL_SIZE)
	dialog.set_title("PSD canvas does not match this avatar")
	dialog.add_message(text)
	dialog.add_actions([{"text": "OK", "callback": func(): on_dismiss.call()}])
	return dialog


static func _dimensions(size: Vector2) -> String:
	return "%d x %d" % [int(size.x), int(size.y)]
