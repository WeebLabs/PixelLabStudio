extends RefCounted

const WiggleAppendage = preload("res://effects/wiggle/wiggle_appendage.gd")
const WigglePathEditor = preload("res://effects/wiggle/wiggle_path_editor.gd")
const WiggleGeometry = preload("res://effects/wiggle/wiggle_geometry.gd")

var appendage: WiggleAppendage2D = null
var path_editor = null
var smooth_path := PackedVector2Array()

var _owner: Node2D
var _path_edit_previous_visible := false


func setup(owner: Node2D) -> void:
	_owner = owner


func has_appendage() -> bool:
	return appendage != null


func is_editing_path() -> bool:
	return path_editor != null


func refresh_texture() -> void:
	if appendage == null:
		return
	appendage.texture = _owner.sprite.texture
	apply_geometry()


func set_z_index(value: int) -> void:
	if appendage != null:
		appendage.z_index = value


func set_material(value: Material) -> void:
	if appendage != null:
		appendage.material = value


func set_visual(modulate: Color, visibility_layer: int) -> void:
	if appendage == null:
		return
	appendage.self_modulate = modulate
	appendage.visibility_layer = visibility_layer


func set_active(active: bool) -> void:
	_owner._last_visual_key = -1
	if active:
		if _owner.wigglePath.size() < 2:
			auto_fit_path()
		if appendage == null:
			appendage = WiggleAppendage.new()
			appendage.z_as_relative = false
			_owner.dragOrigin.add_child(appendage)
		appendage.texture = _owner.sprite.texture
		appendage.texture_filter = _owner.sprite.texture_filter
		appendage.material = _owner.sprite.material
		appendage.z_index = _owner.z
		apply_geometry()
		appendage.configure(parameters())
		appendage.reset()
		_owner.sprite.visible = false
	else:
		release_children()
		if appendage != null:
			appendage.queue_free()
			appendage = null
		_owner.sprite.visible = true
		_owner.sprite.rotation = 0.0
		_owner.sprite.scale = Vector2.ONE


func update_path_editor(wanted: bool) -> void:
	if wanted and path_editor == null:
		enter_path_edit()
	elif not wanted and path_editor != null:
		exit_path_edit()


func enter_path_edit() -> void:
	if _owner.wigglePath.size() < 2:
		auto_fit_path()
	path_editor = WigglePathEditor.new()
	_owner.dragOrigin.add_child(path_editor)
	path_editor.setup(_owner)
	_path_edit_previous_visible = _owner.sprite.visible
	_owner.sprite.visible = true
	if appendage != null:
		appendage.visible = false


func exit_path_edit() -> void:
	if path_editor != null:
		path_editor.queue_free()
		path_editor = null
	if appendage != null:
		apply_geometry()
		appendage.reset()
		appendage.visible = true
		_owner.sprite.visible = false
	else:
		_owner.sprite.visible = _path_edit_previous_visible


func apply_path_changed() -> void:
	if appendage != null:
		apply_geometry()
		appendage.reset()


func auto_fit_path() -> void:
	var fitted := WiggleGeometry.auto_fit(
		_owner.imageData,
		Vector2(_owner.size),
		_owner.offset,
		int(_owner.wiggleSegments),
	)
	_owner.wigglePath = fitted["path"]
	_owner.wigglePathWidths = fitted["widths"]


func auto_fit_and_refresh() -> void:
	auto_fit_path()
	apply_path_changed()
	if path_editor != null:
		path_editor.queue_redraw()


func apply_geometry() -> void:
	if appendage == null or _owner.imageData == null or _owner.wigglePath.size() < 2:
		return
	smooth_path = WiggleAppendage.smooth_path(_owner.wigglePath, 10)
	if smooth_path.size() < 2:
		smooth_path = _owner.wigglePath
	rebuild_chain()
	var widths := WiggleGeometry.smooth_widths(
		smooth_path.size(),
		_owner.wigglePathWidths,
		_owner.wiggleThickness,
	)
	appendage.build_mesh(widths, smooth_path[0])


func rebuild_chain() -> void:
	if appendage == null or smooth_path.size() < 2:
		return
	var root_local: Vector2 = _owner._tex_to_local(smooth_path[0])
	appendage.position = root_local
	var relative_rest := PackedVector2Array()
	for point in smooth_path:
		relative_rest.append(_owner._tex_to_local(point) - root_local)
	appendage.set_geometry(relative_rest, clampi(int(_owner.wiggleSegments), 2, 48))


func sync_to_offset() -> void:
	if appendage != null and not smooth_path.is_empty():
		appendage.position = _owner._tex_to_local(smooth_path[0])


func update(delta: float) -> void:
	if appendage == null:
		set_active(true)
		return
	_owner.sprite.rotation = 0.0
	_owner.sprite.scale = Vector2.ONE
	if appendage.segment_count != clampi(int(_owner.wiggleSegments), 2, 48):
		apply_geometry()
	appendage.configure(parameters())
	appendage.tick(delta, _owner.tick)
	attach_children()
	apply_to_children()


func parameters() -> Dictionary:
	return {
		"stiffness": _owner.wiggleStiffness,
		"damping": _owner.wiggleDamping,
		"max_angular_momentum": clampf(_owner.wiggleStiffness * 0.45, 2.0, 30.0),
		"stiffness_decay": _owner.wiggleStiffness * 0.05,
		"stiffness_decay_exponent": 1.3,
		"max_angle": deg_to_rad(_owner.wiggleMaxBend),
		"comeback_speed": _owner.wiggleBendFocus,
		"rest_return": _owner.wiggleShapeReturn,
		"gravity": Vector2(0.0, _owner.wiggleWeight),
		"subdivision": 4,
		"root_follow_smoothness": clampf(0.6 + _owner.wiggleReactivity * 0.3, 0.5, 1.0),
		"motion_intensity": _owner.wiggleMotionIntensity,
		"auto_wag": _owner.wiggleWagEnabled,
		"wag_speed": _owner.wiggleWagSpeed,
		"wag_amount": deg_to_rad(_owner.wiggleWagAmount),
	}


func apply_to_children() -> void:
	if appendage == null or smooth_path.size() < 2:
		return
	for child in _owner.getAllLinkedSprites():
		if not child._wiggleFollowing:
			child._wiggleRestPos = child.position
			child._wiggleRestRot = child.rotation
			child._wiggleFollowing = true
		var texture_position: Vector2 = _owner._local_to_tex(child._wiggleRestPos)
		var fraction := WiggleGeometry.project_fraction(smooth_path, texture_position)
		var point: Vector2 = appendage.sample_local(fraction) + appendage.position
		var next_point: Vector2 = appendage.sample_local(minf(fraction + 0.04, 1.0)) + appendage.position
		child.position = point
		var current_tangent := next_point - point
		var rest_tangent := WiggleGeometry.tangent(smooth_path, fraction)
		if current_tangent.length() > 0.001 and rest_tangent.length() > 0.001:
			child.rotation = child._wiggleRestRot + (current_tangent.angle() - rest_tangent.angle())


func attach_children() -> void:
	for child in _owner.getAllLinkedSprites():
		if child.get_parent() == _owner.sprite:
			child._wiggleRestPos = child.position
			child._wiggleRestRot = child.rotation
			child._wiggleFollowing = true
			child.reparent(_owner.dragOrigin, true)


func release_children() -> void:
	for child in _owner.getAllLinkedSprites():
		if child._wiggleFollowing:
			if child.get_parent() == _owner.dragOrigin:
				child.reparent(_owner.sprite, false)
			child.position = child._wiggleRestPos
			child.rotation = child._wiggleRestRot
			child._wiggleFollowing = false
