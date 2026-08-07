extends RefCounted

const SidebarComponent = preload("res://ui_scenes/common/sidebar_ui.gd")
const MenuBarComponent = preload("res://ui_scenes/common/menu_bar.gd")


func run(t) -> void:
	_test_decorative_controls_do_not_capture_input(t)
	_test_sidebar_width_contract(t)
	_test_resize_edge_contract(t)
	_test_editor_chrome_contract(t)
	_test_slider_theme_contract(t)
	_test_menu_bar_reveal_contract(t)
	_test_menu_bar_crowding_contract(t)
	_test_shared_menu_actions(t)
	_test_sidebar_call_sites(t)


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
	t.assert_true(actions.contains('"Clear", func(): Global.main._on_clear_avatar_pressed(), true'), "Clear is marked danger in the shared file actions")

	for relative_path in ["main_scenes/EditControls.gd", "main_scenes/ControlPanel.gd"]:
		var source := FileAccess.get_file_as_string(source_root.path_join(relative_path))
		t.assert_true(source.contains("MenuActions.add_avatar_file_actions"), "%s takes its file actions from the shared list" % relative_path)
		for label in ["Save", "Load", "Clear", "Reset"]:
			t.assert_false(source.contains('"%s"' % label), "%s does not redeclare the %s item" % [relative_path, label])


func _test_sidebar_call_sites(t) -> void:
	var source_root := _source_root()
	var left_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteEditMenu/sprite_viewer.gd"))
	var right_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/spriteList/viewer.gd"))
	var global_source := FileAccess.get_file_as_string(source_root.path_join("autoload/global.gd"))
	var mouse_source := FileAccess.get_file_as_string(source_root.path_join("ui_scenes/mouse/mouse_cursor.gd"))
	for source in [left_source, right_source]:
		t.assert_true(source.contains("SidebarUIFactory.create_panel_background"), "each sidebar uses the shared click-through background")
		t.assert_true(source.contains("SidebarUIFactory.create_slider_theme"), "each sidebar uses the shared slider resources")
		t.assert_true(source.contains("SidebarUIFactory.clamp_panel_width"), "each sidebar uses the shared safe width clamp")
		t.assert_false(source.contains("Image.create(16, 16"), "sidebars no longer duplicate grabber rasterization")
	t.assert_true(global_source.contains("SidebarUIFactory.is_over_app_chrome"), "global wheel routing uses the shared app-chrome bounds")
	t.assert_true(mouse_source.contains("Global.isMouseOverSidebar()"), "sprite selection uses the same app-chrome guard as wheel routing")

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


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
