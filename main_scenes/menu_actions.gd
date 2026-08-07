class_name MenuActions
extends RefCounted

# Menu bar actions that both modes offer. Declared once here so the edit bar and
# the viewer bar cannot drift in wording, order, grouping or wiring.

# Avatar file actions: "Save Load | Clear Reset". Emitted without a leading
# separator so each bar decides how the group joins what precedes it. Clear is
# marked danger because it discards the rig; Reset only reloads the last save.
static func add_avatar_file_actions(bar: AppMenuBar, zone: Container) -> void:
	bar.add_button(zone, "Save", func(): Global.main._on_save_button_pressed())
	bar.add_button(zone, "Load", func(): Global.main._on_load_button_pressed())
	bar.add_separator(zone)
	bar.add_button(zone, "Clear", func(): Global.main._on_clear_avatar_pressed(), true)
	bar.add_button(zone, "Reset", func(): Global.main._on_reset_avatar_pressed())
