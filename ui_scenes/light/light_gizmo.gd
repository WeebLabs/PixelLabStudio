extends Node2D

var light_energy: float = 3.0:
	set(v):
		light_energy = v
		if _light:
			_light.energy = v

var light_color: Color = Color(1, 1, 1):
	set(v):
		light_color = v
		if _light:
			_light.color = v

var light_range: float = 15.0:
	set(v):
		light_range = v
		if _light:
			_light.texture_scale = v

var light_enabled: bool = true:
	set(v):
		light_enabled = v
		if _light:
			_light.enabled = v

var _light: PointLight2D = null
var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _hovered: bool = false

const GRAB_RADIUS = 20.0

func _ready():
	_light = PointLight2D.new()

	# Procedural radial texture with smooth quadratic falloff
	var size = 512
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size * 0.5, size * 0.5)
	var radius = size * 0.5
	for y in size:
		for x in size:
			var dist = Vector2(x, y).distance_to(center) / radius
			var a = clampf(1.0 - dist, 0.0, 1.0)
			a = a * a  # quadratic falloff
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex = ImageTexture.create_from_image(img)

	_light.texture = tex
	_light.energy = light_energy
	_light.color = light_color
	_light.texture_scale = light_range
	_light.enabled = light_enabled
	_light.height = 200

	add_child(_light)

	# Kill ambient light so only the PointLight2D illuminates normal-mapped sprites
	var modulate = CanvasModulate.new()
	modulate.color = Color.BLACK
	add_child(modulate)

func _draw():
	if !Global.main or !Global.main.editMode:
		return
	var color = Color(1.0, 0.9, 0.4, 0.9) if _hovered else Color(1.0, 0.85, 0.3, 0.7)
	draw_circle(Vector2.ZERO, 10.0, color)
	draw_arc(Vector2.ZERO, 10.0, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.5)

func _process(_delta):
	if !Global.main:
		return
	var mouse_pos = get_local_mouse_position()
	var was_hovered = _hovered
	_hovered = mouse_pos.length() <= GRAB_RADIUS and Global.main.editMode
	if was_hovered != _hovered:
		queue_redraw()

func _unhandled_input(event):
	if !Global.main or !Global.main.editMode:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var mouse_pos = get_local_mouse_position()
			if mouse_pos.length() <= GRAB_RADIUS:
				UndoManager.save_state()
				_dragging = true
				_drag_offset = global_position - get_global_mouse_position()
				get_viewport().set_input_as_handled()
		else:
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		get_viewport().set_input_as_handled()

func reset_defaults():
	position = Vector2(200, -200)
	light_energy = 3.0
	light_color = Color(1, 1, 1)
	light_range = 15.0
	light_enabled = true
