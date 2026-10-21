extends RefCounted

const CollisionBuilder = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")

var _owner: Node2D


func setup(owner: Node2D) -> void:
	_owner = owner


func set_monitorable(enabled: bool) -> void:
	_owner.grabArea.monitorable = enabled


func set_active(active: bool) -> void:
	for child in _owner.grabArea.get_children():
		if child is CollisionPolygon2D or child is CollisionShape2D:
			child.disabled = not active


func build(polygons: Array, active: bool) -> bool:
	var bounds := Rect2(Vector2.ZERO, Vector2(_owner.imageData.get_size()))
	var has_collision: bool = CollisionBuilder.populate_polygons(
		_owner.grabArea,
		_owner.outlineScene,
		polygons,
		bounds,
	)
	set_active(active)
	return has_collision


func replace(polygons: Array, active: bool) -> bool:
	CollisionBuilder.clear(_owner.grabArea)
	return build(polygons, active)


func remake_sheet(active: bool) -> void:
	if _owner.remadePolygon:
		return
	CollisionBuilder.replace_with_fallback(
		_owner.grabArea,
		_owner.outlineScene,
		_owner.imageSize,
		_owner.frames,
	)
	set_active(active)
	_owner.remadePolygon = true
