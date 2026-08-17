extends RefCounted

const BlendModes = preload("res://effects/blend/blend_mode.gd")

var _owner: Node2D
var _blend_backbuffer: BackBufferCopy = null


func setup(owner: Node2D) -> void:
	_owner = owner


static func premultiplied_texture(image: Image) -> ImageTexture:
	var premultiplied := image.duplicate()
	premultiplied.premultiply_alpha()
	return ImageTexture.create_from_image(premultiplied)


func rebuild_texture() -> void:
	if _owner.normalTex != null:
		var canvas_texture := CanvasTexture.new()
		canvas_texture.diffuse_texture = _owner.tex
		canvas_texture.normal_texture = _owner.normalTex
		_owner.sprite.texture = canvas_texture
	else:
		_owner.sprite.texture = _owner.tex
	_owner._wiggleRuntime.refresh_texture()


func set_normal_map(image: Image, path: String) -> bool:
	if _owner.imageData != null and image.get_size() != _owner.imageData.get_size():
		return false
	_owner.normalImageData = image
	_owner.normalPath = path
	_owner.normalTex = ImageTexture.create_from_image(image)
	rebuild_texture()
	return true


func clear_normal_map() -> void:
	_owner.normalImageData = null
	_owner.normalTex = null
	_owner.normalPath = ""
	_owner.loadedNormalImage = null
	_owner.loadedNormalData = ""
	rebuild_texture()


func has_normal_map() -> bool:
	return _owner.normalTex != null


func apply_blend_mode() -> void:
	if BlendModes.needs_backbuffer(_owner.blendMode):
		var shader_material: ShaderMaterial
		if _owner.sprite.material is ShaderMaterial:
			shader_material = _owner.sprite.material
		else:
			shader_material = ShaderMaterial.new()
			shader_material.shader = BlendModes.SHADER
			_owner.sprite.material = shader_material
		shader_material.set_shader_parameter("blend_mode", _owner.blendMode)
		_set_blend_backbuffer(true)
	else:
		var canvas_material: CanvasItemMaterial
		if _owner.sprite.material is CanvasItemMaterial:
			canvas_material = _owner.sprite.material
		else:
			canvas_material = CanvasItemMaterial.new()
			_owner.sprite.material = canvas_material
		canvas_material.blend_mode = BlendModes.native_blend(_owner.blendMode)
		_set_blend_backbuffer(false)
	_owner._wiggleRuntime.set_material(_owner.sprite.material)


func set_z_index(value: int) -> void:
	if _blend_backbuffer != null:
		_blend_backbuffer.z_index = value


func _set_blend_backbuffer(enabled: bool) -> void:
	if enabled:
		if _blend_backbuffer == null:
			_blend_backbuffer = BackBufferCopy.new()
			_blend_backbuffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
			_blend_backbuffer.z_as_relative = false
			_blend_backbuffer.z_index = _owner.z
			_owner.dragOrigin.add_child(_blend_backbuffer)
			_owner.dragOrigin.move_child(_blend_backbuffer, 0)
	elif _blend_backbuffer != null:
		_blend_backbuffer.queue_free()
		_blend_backbuffer = null
