extends RefCounted

## Swapping a layer's artwork: a replace from a file or from a PSD layer, and undo
## or redo putting an earlier image back. Held here rather than on spriteObject so
## the scene facade stays a facade, the split sprite_rest_pose.gd uses. All three
## used to carry their own copy of the rebuild; there is one now.

const CollisionBuilder = preload("res://ui_scenes/selectedSprite/sprite_collision_builder.gd")
const LegacyCompat = preload("res://autoload/domain/legacy_canvas_compat.gd")


# `canvas_shift` is set only for a legacy full-canvas layer being replaced by a
# cropped PSD layer: it is that layer's centre relative to the source canvas
# centre, and applying it to `offset` keeps the artwork where it already sat.
# See LegacyCanvasCompat for the derivation.
static func replace_from_psd(layer: Node2D, img: Image, layer_name: String, canvas_shift = null) -> void:
	var previous_size := Vector2(layer.size)
	_take(layer, img, "psd://" + layer_name)
	if canvas_shift != null:
		layer.offset = LegacyCompat.offset_after_replace(layer.offset, canvas_shift)
		# The wiggle rest path is texture-space data, so it moves with the crop.
		layer._wiggleRuntime.remap_path(
			-LegacyCompat.texture_origin_shift(previous_size, Vector2(layer.size), canvas_shift)
		)
	_rebuild(layer, true)


# Take `img` as the layer's artwork under `source_path`. A replace says when it
# drops a normal map the new image no longer fits; undo and redo do not, because
# the snapshot's own normal map is applied straight after.
static func adopt(layer: Node2D, img: Image, source_path: String, announce_normal_drop: bool) -> void:
	_take(layer, img, source_path)
	_rebuild(layer, announce_normal_drop)


static func _take(layer: Node2D, img: Image, source_path: String) -> void:
	layer.path = source_path
	layer.imageData = img
	layer.imageSize = img.get_size()
	layer.size = layer.imageSize


# Everything derived from imageData: the texture, the collision and the handles.
static func _rebuild(layer: Node2D, announce_normal_drop: bool) -> void:
	var img: Image = layer.imageData
	layer.invalidate_used_rect_cache()
	layer.tex = layer._make_premultiplied_texture(img)
	if layer.hasNormalMap() and layer.normalImageData.get_size() != img.get_size():
		layer.clearNormalMap()
		if announce_normal_drop:
			Global.notify_user("Normal map cleared (size mismatch after replace).")
	else:
		layer._rebuild_sprite_texture()

	var polygons := CollisionBuilder.alpha_polygons(img)
	var has_collision: bool = layer._collisionRuntime.replace(polygons, layer._collision_should_be_active())
	layer.sprite.offset = layer.offset
	layer.grabArea.position = (layer.size * -0.5) + layer.offset
	layer.remadePolygon = false
	if not has_collision:
		layer.remakePolygon()
