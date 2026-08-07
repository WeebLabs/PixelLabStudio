class_name SidebarUI
extends RefCounted

const DEFAULT_PANEL_COLOR := Color(0.15, 0.15, 0.15)
const DEFAULT_DIVIDER_COLOR := Color(0.3, 0.3, 0.35)
const SLIDER_FILL_ENABLED := Color(1.0, 0.7, 0.8)
const SLIDER_FILL_DISABLED := Color(0.55, 0.4, 0.45)
const SLIDER_GRAB_ENABLED := Color(1.0, 1.0, 1.0, 1.0)
const SLIDER_GRAB_DISABLED := Color(0.45, 0.45, 0.48, 1.0)

# Chrome geometry. This file is the shared primitive layer, so the menu bar
# takes its own height from here rather than declaring a second 28.
const MENU_BAR_HEIGHT := 28.0
const LEFT_CHROME_PADDING := 19.0
const RIGHT_CHROME_PADDING := 7.0


static func create_panel_background(color := DEFAULT_PANEL_COLOR) -> ColorRect:
	var background := ColorRect.new()
	background.color = color
	background.z_index = -1
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return background


static func create_divider(size: Vector2, color := DEFAULT_DIVIDER_COLOR) -> ColorRect:
	var divider := ColorRect.new()
	divider.color = color
	divider.size = size
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return divider


static func create_slider_theme() -> Dictionary:
	var fill_enabled := StyleBoxFlat.new()
	fill_enabled.bg_color = SLIDER_FILL_ENABLED
	var fill_disabled := StyleBoxFlat.new()
	fill_disabled.bg_color = SLIDER_FILL_DISABLED
	return {
		"fill_enabled": fill_enabled,
		"fill_disabled": fill_disabled,
		"grab_enabled": circle_texture(SLIDER_GRAB_ENABLED),
		"grab_disabled": circle_texture(SLIDER_GRAB_DISABLED),
	}


static func apply_slider_theme(slider: Slider, resources: Dictionary, enabled: bool = true) -> void:
	var fill: StyleBoxFlat = resources["fill_enabled"] if enabled else resources["fill_disabled"]
	var grab: Texture2D = resources["grab_enabled"] if enabled else resources["grab_disabled"]
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	slider.add_theme_icon_override("grabber", grab)
	slider.add_theme_icon_override("grabber_highlight", grab)
	slider.add_theme_icon_override("grabber_disabled", resources["grab_disabled"])


static func is_near_vertical_edge(local: Vector2, edge_x: float, margin: float, min_y := -INF, max_y := INF) -> bool:
	return absf(local.x - edge_x) <= margin and local.y >= min_y - margin and local.y <= max_y + margin


static func clamp_panel_width(proposed: float, viewport_width: float, minimum: float, maximum_ratio: float) -> float:
	var maximum := maxf(minimum, viewport_width * maximum_ratio)
	return clampf(proposed, minimum, maximum)


# True while the cursor is over application chrome rather than the canvas.
# Edit mode: the top menu bar and both sidebars. Viewer mode: only the menu bar,
# and only as far as it has slid into view (`viewer_bar_height`), so a concealed
# bar never steals clicks from the avatar underneath it.
static func is_over_app_chrome(
	screen_position: Vector2,
	viewport_size: Vector2,
	edit_mode: bool,
	left_panel_width: float,
	right_panel_width: float,
	menu_height := MENU_BAR_HEIGHT,
	left_padding := LEFT_CHROME_PADDING,
	right_padding := RIGHT_CHROME_PADDING,
	viewer_bar_height := 0.0,
) -> bool:
	if not edit_mode:
		return viewer_bar_height > 0.0 and screen_position.y < viewer_bar_height
	if screen_position.y < menu_height:
		return true
	if left_panel_width >= 0.0 and screen_position.x < left_panel_width + left_padding:
		return true
	if right_panel_width >= 0.0 and screen_position.x > viewport_size.x - right_panel_width - right_padding:
		return true
	return false


# The one slider-grabber rasterizer in the codebase. Sidebar sliders take the
# default 16px/r6 disc; the menu bar's threshold markers ask for a larger one.
static func circle_texture(color: Color, diameter := 16, radius := 6) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := diameter / 2
	var radius_squared := radius * radius
	for x in range(diameter):
		for y in range(diameter):
			var delta := Vector2i(x - center, y - center)
			if delta.length_squared() <= radius_squared:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
