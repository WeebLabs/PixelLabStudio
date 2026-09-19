extends RefCounted

const SidebarComponent = preload("res://ui_scenes/common/sidebar_ui.gd")
const MenuBarComponent = preload("res://ui_scenes/common/menu_bar.gd")
const MicMonitor = preload("res://autoload/runtime/microphone_monitor.gd")
const LayerTreeController = preload("res://ui_scenes/spriteList/layer_tree_controller.gd")
const EyeTrackingPanel = preload("res://ui_scenes/spriteList/eye_tracking_panel.gd")
const TabStrip = preload("res://ui_scenes/common/tab_bar.gd")


class FakeLayerRow extends HBoxContainer:
	var sprite = null
	var parentTag = null
	var childrenTags: Array = []
	var indent := 0
	var collapsed := false
	var _collapse_btn := Button.new()
	var _name_label := Label.new()
	var visibility_updates := 0

	func _init() -> void:
		add_child(_collapse_btn)
		add_child(_name_label)

	func updateIndent(_available_width: float = -1.0) -> void:
		pass

	func _set_descendants_visible(value: bool) -> void:
		for child in childrenTags:
			child.visible = value

	func updateVis() -> void:
		visibility_updates += 1


class FakeEyeSprite extends RefCounted:
	var id := 0
	var path := ""
	var eyeTrack := false
	var eyeTrackType := 0
	var eyeTrackMode := 0
	var eyeTrackInvert := false
	var eyeTrackDistance := 20.0
	var eyeTrackSpeed := 0.15
	var eyeTrackTargetId: Variant = null


class FakeEyeGlobal extends Node:
	var heldSprite = null
	var sprites: Array = []

	func sprite_nodes() -> Array:
		return sprites

	func sprite_by_id(id):
		for sprite in sprites:
			if sprite.id == id:
				return sprite
		return null


func run(t) -> void:
	_test_decorative_controls_do_not_capture_input(t)
	_test_sidebar_width_contract(t)
	_test_resize_edge_contract(t)
	_test_editor_chrome_contract(t)
	_test_slider_theme_contract(t)
	_test_menu_bar_reveal_contract(t)
	_test_menu_bar_crowding_contract(t)
	_test_level_meter_alignment_contract(t)
	_test_mic_threshold_wiring(t)
	_test_modal_selection_guard(t)
	_test_shared_menu_actions(t)
	_test_settings_panel_contract(t)
	_test_sidebar_call_sites(t)
	_test_layer_tree_controller(t)
	_test_eye_tracking_policy(t)
	_test_tab_underline_slide(t)


func _test_decorative_controls_do_not_capture_input(t) -> void:
	var background := SidebarComponent.create_panel_background()
	t.assert_equal(background.mouse_filter, Control.MOUSE_FILTER_IGNORE, "sidebar backgrounds never consume canvas clicks")
	t.assert_equal(background.z_index, -1, "sidebar backgrounds render behind their controls")
	var divider := SidebarComponent.create_divider(Vector2(200, 1))
	t.assert_equal(divider.mouse_filter, Control.MOUSE_FILTER_IGNORE, "sidebar dividers never consume canvas clicks")
	t.assert_equal(divider.size, Vector2(200, 1), "sidebar dividers preserve requested bounds")
	background.free()
	divider.free()


func _test_sidebar_width_contract(t) -> void:
	t.assert_approx(SidebarComponent.clamp_panel_width(100, 1000, 220, 0.4), 220, 0.001, "sidebar width respects its minimum")
	t.assert_approx(SidebarComponent.clamp_panel_width(500, 1000, 220, 0.4), 400, 0.001, "sidebar width respects the viewport ratio")
	t.assert_approx(SidebarComponent.clamp_panel_width(250, 300, 310, 0.25), 310, 0.001, "narrow startup viewports cannot invert width clamps")


func _test_resize_edge_contract(t) -> void:
	t.assert_true(SidebarComponent.is_near_vertical_edge(Vector2(304, 50), 310, 6), "resize edge includes its grab margin")
	t.assert_false(SidebarComponent.is_near_vertical_edge(Vector2(303, 50), 310, 6), "resize edge excludes points beyond its grab margin")
	t.assert_true(SidebarComponent.is_near_vertical_edge(Vector2(-4, -8), -4, 6, -4, 100), "resize edge includes vertical endpoint margin")
	t.assert_false(SidebarComponent.is_near_vertical_edge(Vector2(-4, -11), -4, 6, -4, 100), "resize edge rejects points beyond vertical endpoint margin")


func _test_editor_chrome_contract(t) -> void:
	var viewport_size := Vector2(1280, 720)
	t.assert_true(SidebarComponent.is_over_app_chrome(Vector2(600, 10), viewport_size, true, 265, 310), "top menu blocks canvas interaction")
	t.assert_true(SidebarComponent.is_over_app_chrome(Vector2(100, 300), viewport_size, true, 265, 310), "left sidebar blocks canvas interaction")
	t.assert_true(SidebarComponent.is_over_app_chrome(Vector2(1100, 300), viewport_size, true, 265, 310), "right sidebar blocks canvas interaction")
	t.assert_false(SidebarComponent.is_over_app_chrome(Vector2(600, 300), viewport_size, true, 265, 310), "open canvas remains interactive")
	t.assert_false(SidebarComponent.is_over_app_chrome(Vector2(100, 300), viewport_size, false, 265, 310), "sidebar bounds are inactive in view mode")

	# The canvas rectangle is the same bounds: the paused-motion frame is drawn on
	# it, so its edges are exactly where clicks stop reaching the canvas.
	var canvas := SidebarComponent.edit_canvas_rect(viewport_size, 265, 310)
	t.assert_equal(canvas, Rect2(265 + 19, 28, 1280 - 310 - 7 - (265 + 19), 720 - 28), "the canvas runs between the sidebars' visual edges, below the menu bar")
	t.assert_false(SidebarComponent.is_over_app_chrome(canvas.position, viewport_size, true, 265, 310), "the canvas's top-left corner is canvas")
	t.assert_false(SidebarComponent.is_over_app_chrome(Vector2(canvas.end.x, 300), viewport_size, true, 265, 310), "and so is its right edge")
	t.assert_true(SidebarComponent.is_over_app_chrome(canvas.position - Vector2(0.5, 0), viewport_size, true, 265, 310), "half a pixel left of it is the sidebar")
	t.assert_true(SidebarComponent.is_over_app_chrome(Vector2(canvas.end.x + 0.5, 300), viewport_size, true, 265, 310), "half a pixel right of it is the other sidebar")
	t.assert_equal(SidebarComponent.edit_canvas_rect(viewport_size, -1, -1), Rect2(0, 28, 1280, 692), "with no sidebars the canvas is the window under the menu bar")

	# Viewer mode: only the part of the menu bar that has slid into view blocks
	# the canvas, so a concealed bar never steals clicks from the avatar.
	var defaults := [
		SidebarComponent.MENU_BAR_HEIGHT,
		SidebarComponent.LEFT_CHROME_PADDING,
		SidebarComponent.RIGHT_CHROME_PADDING,
	]
	t.assert_false(
		SidebarComponent.is_over_app_chrome(Vector2(600, 10), viewport_size, false, 265, 310, defaults[0], defaults[1], defaults[2], 0.0),
		"a concealed viewer bar leaves the canvas interactive",
	)
	t.assert_true(
		SidebarComponent.is_over_app_chrome(Vector2(600, 10), viewport_size, false, 265, 310, defaults[0], defaults[1], defaults[2], 28.0),
		"a revealed viewer bar blocks canvas interaction",
	)
	t.assert_false(
		SidebarComponent.is_over_app_chrome(Vector2(600, 20), viewport_size, false, 265, 310, defaults[0], defaults[1], defaults[2], 14.0),
		"a half-revealed viewer bar only blocks as far as it has slid in",
	)


func _test_menu_bar_reveal_contract(t) -> void:
	# The reveal band is a fraction of window height, clamped so it stays usable
	# on both a tall desktop window and a small avatar window.
	t.assert_approx(MenuBarComponent.reveal_band(1080, MenuBarComponent.REVEAL_BAND_RATIO), 135.0, 0.001, "the reveal band follows window height")
	t.assert_approx(MenuBarComponent.reveal_band(240, MenuBarComponent.REVEAL_BAND_RATIO), MenuBarComponent.BAND_MIN_PX, 0.001, "the reveal band has a floor on short windows")
	t.assert_approx(MenuBarComponent.reveal_band(2160, MenuBarComponent.REVEAL_BAND_RATIO), MenuBarComponent.BAND_MAX_PX, 0.001, "the reveal band has a ceiling on tall windows")
	t.assert_true(
		MenuBarComponent.HIDE_BAND_RATIO > MenuBarComponent.REVEAL_BAND_RATIO,
		"the bar is dismissed further out than it is summoned",
	)

	# Hysteresis: the same cursor position holds a revealed bar open but is not
	# close enough to summon a concealed one.
	var height := 720.0
	var between := (MenuBarComponent.reveal_band(height, MenuBarComponent.REVEAL_BAND_RATIO)
		+ MenuBarComponent.reveal_band(height, MenuBarComponent.HIDE_BAND_RATIO)) * 0.5
	t.assert_false(MenuBarComponent.should_reveal(false, true, between, height), "a concealed bar needs the tighter band")
	t.assert_true(MenuBarComponent.should_reveal(true, true, between, height), "a revealed bar keeps the wider band")
	t.assert_true(MenuBarComponent.should_reveal(false, true, 4.0, height), "the top edge always summons the bar")
	t.assert_false(MenuBarComponent.should_reveal(true, true, height - 10.0, height), "the far edge always dismisses the bar")
	t.assert_false(MenuBarComponent.should_reveal(true, false, 4.0, height), "a cursor outside the window dismisses the bar")

	# Leaving the band buys LINGER_SECONDS, and coming back restarts the window
	# from full rather than resuming it.
	var linger := MenuBarComponent.LINGER_SECONDS
	t.assert_approx(MenuBarComponent.next_linger(0.0, true, 0.016), linger, 0.0001, "wanting the bar charges the full window")
	t.assert_approx(MenuBarComponent.next_linger(linger, false, 0.5), linger - 0.5, 0.0001, "leaving the band drains the window")
	t.assert_approx(MenuBarComponent.next_linger(0.3, true, 0.016), linger, 0.0001, "re-entering restarts the window rather than resuming it")
	t.assert_approx(MenuBarComponent.next_linger(0.2, false, 0.5), 0.0, 0.0001, "the window never goes negative")

	# The bar holds for LINGER_SECONDS of frames after the cursor leaves, then
	# releases. Stepped at 60 fps, the way _process runs it.
	var held := MenuBarComponent.LINGER_SECONDS
	var frames := 0
	while held > 0.0:
		held = MenuBarComponent.next_linger(held, false, 1.0 / 60.0)
		frames += 1
	t.assert_approx(float(frames) / 60.0, MenuBarComponent.LINGER_SECONDS, 0.02, "the hold lasts its stated duration")

	# A pin holds the bar open, so releasing one leaves the same reprieve behind.
	t.assert_approx(MenuBarComponent.next_linger(0.0, true, 1.0), linger, 0.0001, "a held-open bar keeps its window charged")

	_test_menu_bar_hold(t)


# The real _process, stepped by hand. Outside a tree _wants_reveal() is false, so
# a pin stands in for "the cursor wants the bar" and releasing it stands in for
# the cursor leaving the band. This covers what the pure helper cannot: that the
# bar actually stays on screen for the whole window and only then slides away.
func _test_menu_bar_hold(t) -> void:
	var step := 1.0 / 60.0
	var bar = MenuBarComponent.new()
	bar.configure_auto_reveal(true)
	bar.set_pin(&"test", true)
	for i in 30:
		bar._process(step)
	t.assert_approx(bar.revealed_height(), MenuBarComponent.BAR_HEIGHT, 0.001, "the bar comes fully on screen while it is wanted")

	# Cursor leaves. It must still be fully up a second later.
	bar.set_pin(&"test", false)
	for i in 60:
		bar._process(step)
	t.assert_approx(bar.revealed_height(), MenuBarComponent.BAR_HEIGHT, 0.001, "one second after leaving, the bar has not moved")

	# Coming back mid-window restarts the count: another second, still up.
	bar.set_pin(&"test", true)
	bar._process(step)
	bar.set_pin(&"test", false)
	for i in 60:
		bar._process(step)
	t.assert_approx(bar.revealed_height(), MenuBarComponent.BAR_HEIGHT, 0.001, "re-entering restarts the window rather than resuming it")

	var frames := 0
	while bar.revealed_height() > 0.0 and frames < 600:
		bar._process(step)
		frames += 1
	var slide := 1.0 / MenuBarComponent.SLIDE_SPEED
	t.assert_approx(float(frames) * step, MenuBarComponent.LINGER_SECONDS - 1.0 + slide, 0.05, "the bar leaves once the window runs out, then slides")

	# A concealment request outranks whatever the bar was still owed. The pin has
	# to be released first: a bar still held open by a popup SHOULD come back.
	bar.set_pin(&"test", true)
	for i in 30:
		bar._process(step)
	bar.set_pin(&"test", false)
	bar.snap_hidden()
	for i in 30:
		bar._process(step)
	t.assert_equal(bar.revealed_height(), 0.0, "snap_hidden discards the window the bar was still owed")
	bar.free()


func _test_menu_bar_crowding_contract(t) -> void:
	# When the zones cannot clear each other, the bar's nominated collapsible item
	# yields: the viewer bar drops its mic meters rather than overlap the buttons.
	t.assert_true(MenuBarComponent.zones_fit(1600, 200, 400, 500), "a wide bar shows every zone")
	t.assert_false(MenuBarComponent.zones_fit(900, 200, 400, 500), "a narrow bar collapses its nominated item")

	# The centre strip is centred on the bar, so the WIDER side binds, not the
	# sum. These two have identical total content (920) in an identical bar: the
	# balanced one fits and the lopsided one collides.
	t.assert_true(MenuBarComponent.zones_fit(1200, 310, 300, 310), "balanced side zones leave the centre room")
	t.assert_false(MenuBarComponent.zones_fit(1200, 100, 300, 520), "a heavy side zone collides with the centred strip")

	# The threshold leaves the edge margin and a visible gap on each side.
	t.assert_false(MenuBarComponent.zones_fit(600, 200, 200, 200), "zones packed to the full width leave no room for margins")


# A mic thumb is read against the bar behind it, so the two have to share one
# coordinate space: the meter spans the grabber's travel, which center_grabber
# makes the slider's whole rect. Verified in rendered pixels; this holds the
# geometry that made them agree.
func _test_level_meter_alignment_contract(t) -> void:
	t.assert_equal(MenuBarComponent.METER_EDGE, float(MenuBarComponent.GRABBER_RADIUS), "the meter is inset by exactly the slider's own inset")
	t.assert_equal(
		MenuBarComponent.METER_WIDTH,
		MenuBarComponent.METER_TRACK_WIDTH + MenuBarComponent.METER_EDGE * 2.0,
		"the stack carries the track plus both insets, so the visible track keeps its length",
	)


# Both mic thumbs are thresholds on their own meter's scale: the Level thumb is the
# dBFS level that opens the voice gate, the Duration thumb the hold in ms.
func _test_mic_threshold_wiring(t) -> void:
	var source := FileAccess.get_file_as_string(_source_root().path_join("main_scenes/ControlPanel.gd"))
	t.assert_true(source.contains("apply.call(value)"), "a thumb applies its own position as the threshold")
	t.assert_false(source.contains("limit_range - value"), "no mirrored sensitivity mapping remains")
	t.assert_true(source.contains("SettingsSchema.MIC_LEVEL_MIN_DB"), "the level meter takes its dB floor from the persisted schema")
	t.assert_true(source.contains("SettingsSchema.MIC_LEVEL_MAX_DB"), "and its ceiling")
	t.assert_true(source.contains("SettingsSchema.MIC_DURATION_FULL_MS"), "the duration meter takes its range from the persisted schema")
	t.assert_true(source.contains("Global.micLevelDb"), "the level bar shows the smoothed voice level")
	t.assert_true(source.contains("Global.micDuration,"), "the duration bar shows the fill-and-drain value")

	# The Level thumb is the gate threshold, read against the Level bar.
	var monitor := MicMonitor.new()
	monitor.threshold_db = -30.0
	monitor.update_from_rms(pow(10.0, -25.0 / 20.0), 1.0 / 60.0)
	t.assert_true(monitor.speaking, "a level bar past the thumb opens the gate")
	var quiet := MicMonitor.new()
	quiet.threshold_db = -30.0
	quiet.update_from_rms(pow(10.0, -40.0 / 20.0), 1.0 / 60.0)
	t.assert_false(quiet.speaking, "a level bar short of the thumb does not")
	monitor.free()
	quiet.free()


# A prompt that acts on the held layer has two ways to lose it: the canvas, which
# Global.select() gates on main.fileSystemOpen, and the layer list, whose rows are
# Controls that never reach that path. The single-PNG replace prompt was outside
# both, so a click during the prompt moved the replacement onto another layer.
func _test_modal_selection_guard(t) -> void:
	var source_root := _source_root()
	var main_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd"))
	var import_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/controllers/import_controller.gd"))
	var guard := _function_body(main_source, "func isFileSystemOpen")
	# Without this the assert_false checks below would pass on an empty string.
	t.assert_true(guard.contains("return true"), "the modal guard body was located")
	t.assert_true(guard.contains("has_single_replace_dialog()"), "the single-replace prompt counts as an open modal")
	t.assert_false(guard.contains("has_single_replace_dialog():\n\t\tGlobal.clear_selection()"), "the guard does not clear the layer the prompt is about to replace")

	var confirm := _function_body(import_source, "func _on_single_replace_confirmed")
	t.assert_true(confirm.contains("replaceSprite"), "the confirm body was located")
	t.assert_true(confirm.contains("_single_replace_target"), "the confirm acts on the layer the prompt named")
	t.assert_false(confirm.contains("Global.heldSprite.replaceSprite"), "the confirm no longer replaces whatever is selected when it is answered")
	t.assert_true(
		_function_body(import_source, "func _on_single_replace_cancelled").contains("_single_replace_target = null"),
		"cancelling releases the captured layer",
	)

	var row := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/sprite_list_object.gd"))
	t.assert_true(_function_body(row, "func _select").contains("Global.main.fileSystemOpen"), "layer rows honour the same modal guard as the canvas")

	# The ribbon path editor follows Global.heldSprite, so a selection change while
	# it is open opens an editor on the newly clicked layer and auto-fits a ribbon
	# path onto it. The canvas path was guarded; the layer list was not.
	var cursor := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/mouse/mouse_cursor.gd"))
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	var lock := _function_body(global_source, "func selection_locked")
	t.assert_true(lock.contains("wigglePathMode"), "ribbon path editing locks the selection")
	t.assert_true(lock.contains("originMode"), "origin adjustment locks the selection too")
	t.assert_true(cursor.contains("Global.selection_locked()"), "canvas clicks read the shared selection lock")
	t.assert_true(
		_function_body(row, "func _gui_input").contains("Global.selection_locked()"),
		"layer rows honour the selection lock the canvas path already had",
	)


# The body of a top-level function, for assertions about one call site.
func _function_body(source: String, signature: String) -> String:
	var start := source.find(signature)
	if start < 0:
		return ""
	var body := ""
	for line in source.substr(start).split("\n"):
		if not body.is_empty() and not line.is_empty() and not line.begins_with("\t"):
			break
		body += line + "\n"
	return body


func _test_slider_theme_contract(t) -> void:
	var resources := SidebarComponent.create_slider_theme()
	var slider := HSlider.new()
	SidebarComponent.apply_slider_theme(slider, resources, true)
	t.assert_equal(slider.get_theme_stylebox("grabber_area"), resources["fill_enabled"], "enabled sliders use the shared active fill")
	t.assert_equal(slider.get_theme_icon("grabber"), resources["grab_enabled"], "enabled sliders use the shared active grabber")
	SidebarComponent.apply_slider_theme(slider, resources, false)
	t.assert_equal(slider.get_theme_stylebox("grabber_area"), resources["fill_disabled"], "disabled sliders use the shared muted fill")
	t.assert_equal(slider.get_theme_icon("grabber"), resources["grab_disabled"], "disabled sliders use the shared muted grabber")
	slider.free()


# Save / Load / Clear / Reset appear on both bars. They are declared once in
# MenuActions so the two modes cannot drift in wording, order or wiring.
func _test_shared_menu_actions(t) -> void:
	var source_root := _source_root()
	var actions := FileAccess.get_file_as_string(source_root.path_join("main_scenes/menu_actions.gd"))
	for label in ["Save", "Load", "Clear", "Reset"]:
		t.assert_true(actions.contains('"%s"' % label), "the shared file actions include %s" % label)
	t.assert_true(actions.contains('"Clear", func(): Global.main.clear_avatar(), true'), "Clear is marked danger in the shared file actions")

	for relative_path in ["main_scenes/EditControls.gd", "main_scenes/ControlPanel.gd"]:
		var source := FileAccess.get_file_as_string(source_root.path_join(relative_path))
		t.assert_true(source.contains("MenuActions.add_avatar_file_actions"), "%s takes its file actions from the shared list" % relative_path)
		for label in ["Save", "Load", "Clear", "Reset"]:
			t.assert_false(source.contains('"%s"' % label), "%s does not redeclare the %s item" % [relative_path, label])


# The settings panel is a constructed form, not a placed one, and it draws from
# the same components as the sidebars and the menu bar.
func _test_settings_panel_contract(t) -> void:
	var source_root := _source_root()
	var panel := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/settings/settings_menu.gd"))
	var scene := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/settings/settings_menu.tscn"))
	var tab_sources := []
	for filename in [
		"audio_settings_tab.gd", "display_settings_tab.gd", "motion_settings_tab.gd",
		"hotkey_settings_tab.gd", "output_settings_tab.gd",
	]:
		tab_sources.append(FileAccess.get_file_as_string(source_root.path_join("ui_scenes/settings/" + filename)))

	t.assert_true(panel.contains("AppTabBar.new()"), "the settings panel uses the shared tab strip")
	t.assert_true(panel.contains("_audio_tab.build"), "the settings facade delegates construction to tab components")
	t.assert_true(panel.split("\n").size() <= 150, "settings scene facade stays focused on frame and tab coordination")
	for source in tab_sources:
		t.assert_true(source.contains("Form.section"), "each settings component uses the shared form sections")
		t.assert_false(source.contains("Global."), "settings components use their injected application boundary")
		t.assert_false(source.contains("Saving."), "settings components use their injected persistence boundary")
	t.assert_true(panel.contains("SidebarUIFactory.DEFAULT_PANEL_COLOR"), "the settings panel uses the shared palette")
	for tab in ["Audio", "Display", "Motion", "Hotkeys", "Output"]:
		t.assert_true(panel.contains('"%s"' % tab), "the settings panel declares the %s tab" % tab)

	# The whole point of the rewrite: no child is placed by coordinate any more,
	# and the scene carries no hand-laid node tree.
	for source in [panel] + tab_sources:
		t.assert_false(source.contains(".position = Vector2("), "settings rows are laid out by containers, not coordinates")
	t.assert_false(panel.contains("NinePatchRect"), "the settings panel no longer wears the old skin")
	t.assert_true(scene.length() < 400, "the settings scene is a bare node, its content is constructed in code")

	# Microphone selection moved into the Audio tab; its old popup is gone.
	var audio_source: String = tab_sources[0]
	t.assert_true(audio_source.contains("AudioServer.get_input_device_list()"), "the Audio tab lists input devices")
	t.assert_true(audio_source.contains("_global.selectMicrophone"), "the Audio tab selects the input device")
	t.assert_false(
		FileAccess.file_exists(source_root.path_join("main_scenes/MicInputSelect.gd")),
		"the standalone microphone popup is gone",
	)


func _test_sidebar_call_sites(t) -> void:
	var source_root := _source_root()
	var left_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteEditMenu/sprite_viewer.gd"))
	var right_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/viewer.gd"))
	var tree_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/layer_tree_controller.gd"))
	var presenter_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteEditMenu/selection_presenter.gd"))
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	var mouse_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/mouse/mouse_cursor.gd"))
	for source in [left_source, right_source]:
		t.assert_true(source.contains("SidebarUIFactory.create_panel_background"), "each sidebar uses the shared click-through background")
		t.assert_true(source.contains("SidebarUIFactory.create_slider_theme"), "each sidebar uses the shared slider resources")
		t.assert_true(source.contains("SidebarUIFactory.clamp_panel_width"), "each sidebar uses the shared safe width clamp")
		t.assert_false(source.contains("Image.create(16, 16"), "sidebars no longer duplicate grabber rasterization")
	t.assert_true(global_source.contains("SidebarUIFactory.is_over_app_chrome"), "global wheel routing uses the shared app-chrome bounds")
	t.assert_true(mouse_source.contains("Global.isMouseOverSidebar()"), "sprite selection uses the same app-chrome guard as wheel routing")
	t.assert_true(left_source.split("\n").size() <= 700, "left sidebar facade stays below the componentization threshold")
	t.assert_true(right_source.split("\n").size() <= 700, "right sidebar facade stays below the componentization threshold")
	t.assert_true(right_source.contains("_layer_tree.update_data"), "right sidebar preserves hierarchy behavior through its facade")
	t.assert_true(left_source.contains("_selection_presenter.sync"), "left sidebar preserves selection refresh through its facade")
	t.assert_false(tree_source.contains("_owner._"), "layer-tree controller does not reach into facade-private state")
	t.assert_false(presenter_source.contains("Global."), "selection presenter uses its injected application boundary")

	# Both bars are built from the shared component, and neither hand-styles its
	# own chrome. This is what stops the two modes drifting apart again.
	var edit_bar_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/EditControls.gd"))
	var viewer_bar_source := FileAccess.get_file_as_string(source_root.path_join("main_scenes/ControlPanel.gd"))
	for source in [edit_bar_source, viewer_bar_source]:
		t.assert_true(source.contains("AppMenuBar.new()"), "each mode builds its bar from the shared menu bar")
		t.assert_true(source.contains("menu_bar.add_button"), "each mode adds bar items through the shared factory")
		t.assert_false(source.contains("StyleBoxEmpty.new()"), "neither bar re-styles chrome the component already owns")
		t.assert_false(source.contains("ColorRect.new()"), "neither bar draws its own bar background")
	t.assert_true(viewer_bar_source.contains("menu_bar.anchor_popup"), "viewer popups are placed through the one anchoring seam")
	t.assert_false(
		FileAccess.get_file_as_string(source_root.path_join("main_scenes/main.gd")).contains("ControlPanel/"),
		"main reaches viewer panel children through its API, not by node path",
	)


func _test_layer_tree_controller(t) -> void:
	var controller := LayerTreeController.new()
	var owner := Node2D.new()
	var container := VBoxContainer.new()
	var scroll := ScrollContainer.new()
	owner.add_child(scroll)
	scroll.add_child(container)
	controller.setup(owner, container, scroll, owner, get_script())

	var root := FakeLayerRow.new()
	root._name_label.text = "Body"
	var child := FakeLayerRow.new()
	child._name_label.text = "Body Shadow"
	child.parentTag = root
	root.childrenTags.append(child)
	var peer := FakeLayerRow.new()
	peer._name_label.text = "Hat"
	for row in [peer, child, root]:
		container.add_child(row)

	var ordered: Array = controller._flatten([peer, child, root])
	t.assert_equal(ordered, [peer, root, child], "layer-tree flattening keeps each child immediately after its parent")
	controller._apply_order_and_indentation(ordered)
	t.assert_equal(container.get_child(2), child, "layer-tree controller applies the flattened row order")
	t.assert_equal(child.indent, 1, "layer-tree controller derives indentation from ancestry")
	t.assert_equal(root._collapse_btn.text, "▼", "parents expose their collapse affordance")

	controller.filter("body shadow")
	t.assert_true(root.visible, "filter matches keep the ancestor chain visible")
	t.assert_true(child.visible, "filter matches remain visible")
	t.assert_false(peer.visible, "filter hides unrelated rows")
	controller.update_all_visible()
	t.assert_equal(child.visibility_updates, 1, "visibility refreshes are delegated to each layer row")
	owner.free()


func _test_eye_tracking_policy(t) -> void:
	var panel := EyeTrackingPanel.new()
	var global := FakeEyeGlobal.new()
	var target := FakeEyeSprite.new()
	target.id = 10
	target.path = "res://avatar/Long Eye Target.png"
	var first := FakeEyeSprite.new()
	first.id = 20
	first.eyeTrack = true
	first.eyeTrackMode = 1
	first.eyeTrackTargetId = target.id
	var second := FakeEyeSprite.new()
	second.id = 30
	second.eyeTrack = true
	second.eyeTrackMode = 1
	second.eyeTrackTargetId = target.id
	global.sprites = [target, first, second]
	panel._global = global
	t.assert_equal(panel._scope(), "global", "eye controls enter global scope when tracked layers exist without a selection")
	t.assert_equal(panel._agreed_value("eyeTrackTargetId"), target.id, "global eye controls detect agreed values")
	t.assert_equal(panel._full_target_name(), "Long Eye Target", "eye target labels resolve through the sprite registry")
	second.eyeTrackTargetId = null
	t.assert_equal(panel._agreed_value("eyeTrackTargetId"), null, "mixed global eye values resolve to neutral")
	t.assert_equal(panel._full_target_name(), "", "mixed global targets never display a misleading name")
	global.heldSprite = first
	t.assert_equal(panel._scope(), "per_layer", "a selected sprite takes precedence over global eye scope")
	t.assert_equal(panel._full_target_name(), "Long Eye Target", "per-layer target names use the selected sprite's target")
	global.free()


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""


# Picking a tab slides the pink underline across; a reflow or the owner's
# startup restore snaps it. The slide is polled rather than tweened, so the
# thing that matters most is that it stops polling once it arrives.
func _test_tab_underline_slide(t) -> void:
	var bar = TabStrip.new()
	bar.add_tab("One")
	bar.add_tab("Two")
	bar.add_tab("Three")
	bar.set_bar_size(300.0)
	var underline: ColorRect = bar._underline

	bar.set_active(2)
	t.assert_equal(underline.position.x, 200.0, "a programmatic restore snaps the underline to its tab")
	t.assert_false(bar.is_processing(), "an idle tab strip does not poll")

	bar.set_active(0, true)
	t.assert_equal(underline.position.x, 200.0, "a picked tab leaves the underline where it was, to slide from there")
	t.assert_true(bar.is_processing(), "picking a tab starts the slide")

	bar._process(1.0 / 60.0)
	var first_step: float = underline.position.x
	t.assert_true(first_step < 200.0 and first_step > 0.0, "the first frame moves part of the way, not all of it")

	for _frame in range(120):
		if not bar.is_processing():
			break
		bar._process(1.0 / 60.0)
	t.assert_equal(underline.position.x, 0.0, "the slide lands exactly on the target")
	t.assert_false(bar.is_processing(), "the slide switches its own processing off on arrival")

	# A resize mid-slide retargets rather than snapping, and the underline
	# re-widths to the new segment.
	bar.set_active(2, true)
	bar._process(1.0 / 60.0)
	bar.set_bar_size(600.0)
	t.assert_equal(underline.size.x, 200.0, "a reflow re-widths the underline to the new segment")
	t.assert_true(bar.is_processing(), "a reflow does not cancel a slide in flight")
	for _frame in range(120):
		if not bar.is_processing():
			break
		bar._process(1.0 / 60.0)
	t.assert_equal(underline.position.x, 400.0, "the slide finishes at the resized target")

	bar.free()
