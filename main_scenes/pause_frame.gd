extends Node2D

## A frame around the canvas while motion is paused.
##
## A paused avatar sitting still looks the same as a broken one, and the pause
## button's colour is easy to miss at the edge of the menu bar. The frame sits in
## the canvas, where the user is looking. It lives under EditControls, so it is
## only on the edit page (the only page the pause acts on) and, like the rest of
## the UI layer, never reaches NDI output or recordings. It draws nothing that
## takes input.

const SidebarUI = preload("res://ui_scenes/common/sidebar_ui.gd")

# The pause button's own active tone, so the two read as one signal.
const COLOR := Color(1.0, 0.78, 0.35, 0.95)
const WIDTH := 3.0
# Pausing and resuming fade the frame in and out rather than switching it.
const FADE_SECONDS := 0.25

var _rect := Rect2()
var _shown := false
# Linear progress of the fade, 0 hidden to 1 shown; the drawn alpha eases it.
var _fade := 0.0


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func _process(delta: float) -> void:
	_shown = Global.motion_paused()
	# The rect only follows the canvas while shown; fading out keeps the last one,
	# so the frame does not jump as it goes.
	if _shown:
		var rect := canvas_rect()
		if rect != _rect:
			_rect = rect
			queue_redraw()
	var target := 1.0 if _shown else 0.0
	if _fade == target:
		return
	_fade = move_toward(_fade, target, delta / FADE_SECONDS)
	modulate.a = smoothstep(0.0, 1.0, _fade)
	visible = _fade > 0.0


func canvas_rect() -> Rect2:
	var left := -1.0 if Global.spriteEdit == null else float(Global.spriteEdit.panel_width)
	var right := -1.0 if Global.spriteList == null else float(Global.spriteList.panel_width)
	return SidebarUI.edit_canvas_rect(get_viewport().get_visible_rect().size, left, right)


# Whether the pause asks for the frame, which leads what is drawn by the fade.
func is_shown() -> bool:
	return _shown


func opacity() -> float:
	return modulate.a if visible else 0.0


func drawn_rect() -> Rect2:
	return _rect


func _draw() -> void:
	if _rect.size.x <= 0.0 or _rect.size.y <= 0.0:
		return
	# The stroke is centred on the rect's edge, so it is inset by half its width to
	# sit wholly inside the canvas.
	draw_rect(_rect.grow(-WIDTH * 0.5), COLOR, false, WIDTH)
