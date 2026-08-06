class_name SpriteCollisionBuilder
extends RefCounted

const POLYGON_SIMPLIFICATION := 4.0


static func alpha_polygons(image: Image) -> Array[PackedVector2Array]:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image)
	return bitmap.opaque_to_polygons(
		Rect2(Vector2.ZERO, bitmap.get_size()),
		POLYGON_SIMPLIFICATION,
	)


static func fallback_frame_rect(image_size: Vector2, frame_count: int) -> Rect2:
	var safe_frames := maxi(frame_count, 1)
	var frame_size := Vector2(image_size.x / float(safe_frames), image_size.y)
	return Rect2(Vector2.ZERO, frame_size.max(Vector2.ONE))


static func populate_polygons(grab_area: Area2D, outline_scene: PackedScene, polygons: Array) -> bool:
	var added := false
	for polygon in polygons:
		if not polygon is PackedVector2Array or polygon.size() < 3:
			continue
		added = true
		var collider := CollisionPolygon2D.new()
		collider.polygon = polygon
		grab_area.add_child(collider)

		var outline: Line2D = outline_scene.instantiate()
		outline.points = polygon
		outline.add_point(outline.points[0])
		outline.visibility_layer = 2
		grab_area.add_child(outline)
	return added


static func replace_with_fallback(grab_area: Area2D, outline_scene: PackedScene, image_size: Vector2, frame_count: int) -> void:
	clear(grab_area)
	var rect := fallback_frame_rect(image_size, frame_count)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collider.shape = shape
	collider.position = rect.get_center()
	grab_area.add_child(collider)

	var outline: Line2D = outline_scene.instantiate()
	outline.visibility_layer = 2
	var half_size := rect.size * 0.5
	outline.points = PackedVector2Array([
		-half_size,
		Vector2(half_size.x, -half_size.y),
		half_size,
		Vector2(-half_size.x, half_size.y),
		-half_size,
	])
	outline.position = rect.get_center()
	grab_area.add_child(outline)


static func clear(grab_area: Area2D) -> void:
	for child in grab_area.get_children():
		grab_area.remove_child(child)
		child.queue_free()
