extends RefCounted

const VISIBLE_TALK_BLINK_STATES := {
	0: true, 1: true, 3: true, 4: true,
	10: true, 12: true, 13: true, 15: true,
	20: true, 21: true, 26: true, 27: true,
	30: true, 32: true, 36: true, 38: true,
}


static func talk_blink_visual(
	show_on_talk: int,
	show_on_blink: int,
	speaking: bool,
	blinking: bool,
	edit_mode: bool,
	opacity: float,
	path_editor_active: bool,
) -> Dictionary:
	var faded := 0.2 * int(edit_mode)
	var blink_value := show_on_blink if show_on_blink != 3 else 0
	var state := show_on_talk + blink_value * 3 + int(speaking) * 10 + int(blinking) * 20
	var normally_visible := VISIBLE_TALK_BLINK_STATES.has(state)
	var alpha := maxf(float(int(normally_visible)), faded) * opacity
	var modulate := Color(alpha, alpha, alpha, alpha)
	var visibility_layer := 2 if not normally_visible and faded > 0.0 else 1
	if path_editor_active:
		modulate = Color.WHITE
		visibility_layer = 2
	return {
		"state": state,
		"cache_key": state | (int(faded > 0.0) << 8),
		"opacity": alpha,
		"modulate": modulate,
		"visibility_layer": visibility_layer,
		"normally_visible": normally_visible,
	}


static func costume_visible(costume_layers: Array, costume: int, user_hidden: bool) -> bool:
	var index := costume - 1
	return not user_hidden and index >= 0 and index < costume_layers.size() and costume_layers[index] == 1


# A linked child is a real node descendant of its parent, so Godot's inherited
# visibility hides it whenever an ancestor is off for the current costume,
# whatever the child's own costume bit says. `chain` is that layer's ancestors'
# costumeLayers, nearest parent first; the result says whether the chain lets
# the costume through, so the UI can show the state the viewer actually gets.
static func costume_allowed_by_ancestors(chain: Array, costume: int) -> bool:
	var index := costume - 1
	if index < 0:
		return false
	for layers in chain:
		if index >= layers.size() or layers[index] != 1:
			return false
	return true
