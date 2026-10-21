extends RefCounted

# Edit-mode motion pause: put a layer back to the rest pose its rig is authored
# against, rather than freezing it wherever the motion happened to be. Held here
# rather than on spriteObject so the scene facade stays a facade; the layer calls
# apply() once per frame while Global.motion_paused() is true.
#
# Everything a motion system leaves on the node is reset: animation clips,
# eye tracking, the drag lag, rotational drag, stretch, frame animation and the
# wiggle chain.


static func apply(layer: Node2D) -> void:
	if layer._animator != null:
		layer._animator.reset()
	layer._animRot = 0.0
	layer._animTrans = Vector2.ZERO
	layer._eyeTrackOffset = Vector2.ZERO
	layer._eyeTrackRotation = 0.0
	layer._micRot = 0.0

	layer.wob.position = Vector2.ZERO
	layer.dragger.global_position = layer.wob.global_position
	layer.dragOrigin.global_position = layer.dragger.global_position
	layer.dragOrigin.rotation = 0.0
	layer.sprite.rotation = 0.0
	layer.sprite.scale = Vector2.ONE
	# Unpausing must not read the pause as one enormous frame of movement: arm the
	# snap so the first live frame teleports the dragger instead of feeding that
	# jump into rotational drag and stretch.
	layer._force_drag_snap = true

	if layer.frames > 1:
		layer.sprite.frame = 0
	layer._blinkAnimPlaying = false
	layer._frameClock = 0.0
	layer._blinkQueue = 0

	# The path editor works over the static Sprite2D, so there is no chain to rest.
	if layer.wiggleEnabled and not layer._wiggleRuntime.is_editing_path():
		layer._wiggleRuntime.rest()
