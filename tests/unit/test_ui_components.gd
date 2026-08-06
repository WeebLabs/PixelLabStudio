extends RefCounted

const SidebarComponent = preload("res://ui_scenes/common/sidebar_ui.gd")


func run(t) -> void:
	_test_decorative_controls_do_not_capture_input(t)
	_test_sidebar_width_contract(t)
	_test_resize_edge_contract(t)
	_test_editor_chrome_contract(t)
	_test_slider_theme_contract(t)
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
	t.assert_true(SidebarComponent.is_over_editor_chrome(Vector2(600, 10), viewport_size, true, 265, 310), "top menu blocks canvas interaction")
	t.assert_true(SidebarComponent.is_over_editor_chrome(Vector2(100, 300), viewport_size, true, 265, 310), "left sidebar blocks canvas interaction")
	t.assert_true(SidebarComponent.is_over_editor_chrome(Vector2(1100, 300), viewport_size, true, 265, 310), "right sidebar blocks canvas interaction")
	t.assert_false(SidebarComponent.is_over_editor_chrome(Vector2(600, 300), viewport_size, true, 265, 310), "open canvas remains interactive")
	t.assert_false(SidebarComponent.is_over_editor_chrome(Vector2(100, 300), viewport_size, false, 265, 310), "editor chrome guard is inactive in view mode")


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
	t.assert_true(global_source.contains("SidebarUIFactory.is_over_editor_chrome"), "global wheel routing uses the shared editor-chrome bounds")
	t.assert_true(mouse_source.contains("Global.isMouseOverSidebar()"), "sprite selection uses the same editor-chrome guard as wheel routing")


func _source_root() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source-root="):
			return argument.trim_prefix("--source-root=").simplify_path()
	return ""
