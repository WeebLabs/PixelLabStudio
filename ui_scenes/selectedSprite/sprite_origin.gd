extends RefCounted

## Placing a layer's origin offset from outside the layer, for the sidebar's
## numeric entry. Held here rather than on spriteObject so the scene facade stays
## a facade, the same split sprite_rest_pose.gd uses.
##
## The origin gizmo on the canvas moves `position` and `offset` together so the
## artwork stays put and the origin moves under it. This moves the artwork
## relative to the origin, which is what the offset number in the sidebar says,
## and leaves the layer's position alone.


static func set_offset(layer: Node2D, value: Vector2) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	layer.offset = Vector2(roundi(value.x), roundi(value.y))
	layer.sprite.offset = layer.offset
	layer.grabArea.position = (layer.size * -0.5) + layer.offset
	layer._sync_wiggle_to_offset()
