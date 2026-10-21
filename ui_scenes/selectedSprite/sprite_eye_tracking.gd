extends RefCounted

## Eye tracking for one layer: the look-at offset (Position mode) or head tilt
## (Rotation mode) that rides on top of the layer's animated translation.
##
## Held here rather than on spriteObject so the scene facade stays a facade, the
## same split sprite_rest_pose.gd and sprite_origin.gd use. The smoothing weights
## are per-60-fps-frame values corrected for the real delta, so the look-at keeps
## its speed whatever the frame rate.

const MotionTiming = preload("res://autoload/domain/motion_timing.gd")


static func apply(layer: Node2D, delta: float) -> void:
	# Look-at target: either the cursor (mode 0) or another sprite's live position (mode 1).
	# Global.eyeTrackingGloballyEnabled is the kill switch from global-scope UI; sprite-level
	# the layer's own eyeTrack flag is the per-sprite enable. Both must be on to track.
	var target_world_pos = Vector2.ZERO
	var have_target = false
	if layer.eyeTrack and Global.eyeTrackingGloballyEnabled and not (Global.main.editMode and Global.heldSprite == layer):
		if layer.eyeTrackMode == 1:
			if layer.eyeTrackTargetId != null:
				var target_sprite := Global.sprite_by_id(layer.eyeTrackTargetId)
				if target_sprite != null and target_sprite != layer:
					target_world_pos = target_sprite.global_position
					have_target = true
		else:
			target_world_pos = Global.cursorWorldPos
			have_target = true

	if have_target:
		var rest_pos = layer.global_position
		var to_target = target_world_pos - rest_pos
		if layer.eyeTrackType == 1:
			# Rotation = LIMITED head-tilt that tracks the cursor's VERTICAL position on
			# whichever side it's on: the side nearest the cursor lifts toward an upper
			# cursor and drops toward a lower one. It's a saddle — the screen-frame
			# horizontal × vertical cursor offset — so it's 0 when the cursor is straight
			# up/down or straight to a side, peaks (±eyeTrackDistance°) at the diagonals,
			# and reverses across the artwork's center lines. Referenced from the artwork's
			# VISUAL CENTER (not the origin), so the reversal lands on the artwork's 50%
			# line wherever the origin sits. Default (no invert): cursor upper-left -> top
			# tilts right (left side lifts), upper-right -> top left; lower mirrors. Invert
			# flips the lean.
			var center_world = rest_pos
			var ur = layer.get_image_used_rect()
			if layer.imageData != null and ur.size.x > 0 and ur.size.y > 0:
				center_world = layer.dragOrigin.to_global(layer._tex_to_local(Vector2(ur.position) + Vector2(ur.size) * 0.5))
			var d = target_world_pos - center_world
			var max_rad = deg_to_rad(layer.eyeTrackDistance)
			var target_rot = 0.0
			if d.length() > 0.001:
				var u = d.normalized()
				var sgn = -1.0 if layer.eyeTrackInvert else 1.0
				target_rot = clampf(sgn * 2.0 * max_rad * u.x * u.y, -max_rad, max_rad)
			layer._eyeTrackRotation = lerp_angle(
				layer._eyeTrackRotation, target_rot, MotionTiming.smooth(layer.eyeTrackSpeed, delta))
			layer._eyeTrackOffset = layer._eyeTrackOffset.lerp(Vector2.ZERO, MotionTiming.smooth(0.15, delta))
			if layer._eyeTrackOffset.length() > 0.01:
				layer.wob.position += layer._eyeTrackOffset
		else:
			# Position mode: translate toward the target, capped at eyeTrackDistance px.
			var direction = to_target
			if layer.eyeTrackInvert:
				direction = -direction
			var target_offset = direction.normalized() * min(direction.length(), layer.eyeTrackDistance)
			var eye_weight := MotionTiming.smooth(layer.eyeTrackSpeed, delta)
			layer._eyeTrackOffset = layer._eyeTrackOffset.lerp(target_offset, eye_weight)
			layer.wob.position += layer._eyeTrackOffset
			layer._eyeTrackRotation = lerp(layer._eyeTrackRotation, 0.0, eye_weight)
	else:
		var decay := MotionTiming.smooth(0.15, delta)
		layer._eyeTrackOffset = layer._eyeTrackOffset.lerp(Vector2.ZERO, decay)
		if layer._eyeTrackOffset.length() > 0.01:
			layer.wob.position += layer._eyeTrackOffset
		layer._eyeTrackRotation = lerp(layer._eyeTrackRotation, 0.0, decay)
