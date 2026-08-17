extends RefCounted


func rebuild(rotation_back: Sprite2D, radius: float) -> void:
	var canvas_size := int(radius * 2.0 + 50.0)
	var center := Vector2(canvas_size / 2.0, canvas_size / 2.0)
	var border_width := 2.0
	var background := Image.create(canvas_size, canvas_size, false, Image.FORMAT_RGBA8)
	for x in canvas_size:
		for y in canvas_size:
			var distance := Vector2(x, y).distance_to(center)
			if distance <= radius - border_width:
				background.set_pixel(x, y, Color(0.18, 0.18, 0.18))
			elif distance <= radius:
				background.set_pixel(x, y, Color(0.4, 0.4, 0.4, 0.6))
	rotation_back.texture = ImageTexture.create_from_image(background)

	var line_texture := _line_texture(int(radius), Color(0.75, 0.75, 0.8, 0.6))
	var pointer_texture := _line_texture(int(radius), Color(0.85, 0.85, 0.9, 0.9))
	for line in [rotation_back.get_node("RotLineDisplay"), rotation_back.get_node("RotLineDisplay2")]:
		line.texture = line_texture
		line.offset = Vector2(radius / 2.0, 0)
	var pointer: Sprite2D = rotation_back.get_node("RotLineDisplay3")
	pointer.texture = pointer_texture
	pointer.offset = Vector2(radius / 2.0, 0)

	var progress: TextureProgressBar = rotation_back.get_node("rotLimitBar")
	rotation_back.move_child(progress, 0)
	rotation_back.move_child(rotation_back.get_node("RotLineDisplay"), 1)
	rotation_back.move_child(rotation_back.get_node("RotLineDisplay2"), 2)
	rotation_back.move_child(pointer, 3)
	rotation_back.move_child(rotation_back.get_node("SpriteDisplay"), 4)
	var origin_dot := Sprite2D.new()
	origin_dot.texture = _origin_texture(8)
	rotation_back.add_child(origin_dot)

	for child_name in ["SpriteDisplay", "RotLineDisplay", "RotLineDisplay2", "RotLineDisplay3"]:
		rotation_back.get_node(child_name).position = Vector2.ZERO
	var progress_size := int(radius) * 2
	var fill := Image.create(progress_size, progress_size, false, Image.FORMAT_RGBA8)
	fill.fill(Color(0.55, 0.78, 1.0))
	progress.texture_progress = ImageTexture.create_from_image(fill)
	progress.offset_left = -radius
	progress.offset_top = -radius
	progress.offset_right = radius
	progress.offset_bottom = radius
	progress.pivot_offset = Vector2(radius, radius)


func _line_texture(width: int, color: Color) -> ImageTexture:
	var image := Image.create(width, 4, false, Image.FORMAT_RGBA8)
	for x in width:
		image.set_pixel(x, 1, color)
		image.set_pixel(x, 2, color)
	return ImageTexture.create_from_image(image)


func _origin_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for x in size:
		for y in size:
			if Vector2(x, y).distance_to(center) <= center.x:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)
