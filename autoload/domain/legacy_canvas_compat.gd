extends RefCounted

## Backwards compatibility for rigs built before PSD import existed.
##
## Pre-PSD avatars were assembled from one full-canvas PNG per layer: every image
## carried the whole document's dimensions with the artwork sitting inside its own
## transparent padding, so the layers lined up by construction and each sprite sat
## at the same position. PSD layers are cropped to their own bounding box instead,
## so replacing a legacy layer with one throws away the padding that was carrying
## its placement and the artwork collapses toward the layer origin.
##
## The correction is arithmetic, not re-padding. The layer's Sprite2D is centred,
## so the artwork's centre sits at local `offset` and the node's own origin (the
## rotation/drag pivot) lands at texture pixel `size/2 - offset`. Holding
## `position` still and re-deriving `offset` keeps that pivot on the canvas
## coordinate it already occupied:
##
##     pivot_in_canvas = canvas/2 - offset_old          (the swap cannot move it)
##     offset_new      = new_size/2 - (pivot_in_canvas - layer_top_left)
##                     = offset_old + (layer_centre - canvas_centre)
##
## The right-hand term is the per-layer `position` ImportMatcher already computes.
## Compensating with `position` instead would drag the pivot onto a different part
## of the artwork and carry every linked child layer along with it.
##
## Pure functions, no scene access, so the decision stays testable.


# Layer state is read defensively: the rig can contain members that predate a
# property or are mid-deletion, and a missing property reads as null.
static func _frames(sprite) -> int:
	var value: Variant = sprite.get("frames")
	return int(value) if value != null else 1


static func _size(sprite) -> Vector2:
	var value: Variant = sprite.get("size")
	return Vector2(value) if value is Vector2 or value is Vector2i else Vector2.ZERO


# The texture footprint of one layer. Animated layers hold a horizontal sheet, so
# their raw size is the frame footprint multiplied by the frame count.
static func layer_size(sprite) -> Vector2:
	var raw := _size(sprite)
	var frames := _frames(sprite)
	if frames > 1:
		raw.x /= float(frames)
	return raw


# A layer the compatibility placement applies to: one still image that spans the
# whole legacy canvas. Animated layers are excluded — replacing a sheet with a
# single PSD layer is already a separate, unrelated mismatch.
static func is_legacy_layer(sprite, canvas: Vector2) -> bool:
	if canvas == Vector2.ZERO:
		return false
	if _frames(sprite) > 1:
		return false
	return _size(sprite) == canvas


# The size every still layer shares, or ZERO when they disagree. Uniform sizing is
# the signature of the full-canvas import: cropped rigs vary layer by layer.
static func uniform_canvas(sprites: Array) -> Vector2:
	var canvas := Vector2.ZERO
	for sprite in sprites:
		if sprite == null or _frames(sprite) > 1:
			continue
		var current := _size(sprite)
		if current == Vector2.ZERO:
			continue
		if canvas == Vector2.ZERO:
			canvas = current
		elif current != canvas:
			return Vector2.ZERO
	return canvas


# Corroborating signal: legacy layers were imported from PNG files on disk, so
# they keep a filesystem path, where PSD-imported layers carry `psd://Name`.
static func has_file_backed_layers(sprites: Array) -> bool:
	for sprite in sprites:
		var path := String(sprite.get("path") if sprite.get("path") != null else "")
		if not path.is_empty() and not path.begins_with("psd://") and not path.begins_with("animated://"):
			return true
	return false


## Verdict for one replace operation.
##   legacy   — the rig looks full-canvas and the compatibility placement applies
##   canvas   — the legacy canvas size the rig was authored against
##   mismatch — the PSD was authored at different dimensions, so no placement of
##              the cropped layers can reproduce the original alignment
##   layers   — how many live layers the placement would move
static func evaluate(sprites: Array, psd_canvas: Vector2) -> Dictionary:
	var canvas := uniform_canvas(sprites)
	var legacy := canvas != Vector2.ZERO and has_file_backed_layers(sprites)
	var affected := 0
	if legacy:
		for sprite in sprites:
			if is_legacy_layer(sprite, canvas):
				affected += 1
	return {
		"legacy": legacy,
		"canvas": canvas,
		"mismatch": legacy and canvas != psd_canvas,
		"layers": affected,
	}


# `item_position` is the replacement layer's centre relative to the PSD canvas
# centre, which is exactly the offset correction (see the derivation above).
static func offset_after_replace(current_offset: Vector2, item_position: Vector2) -> Vector2:
	return current_offset + item_position


# Where the replacement layer's top-left sits inside the texture it replaces.
# Data stored in texture pixels — the wiggle path — moves by the negation of this.
static func texture_origin_shift(previous_size: Vector2, new_size: Vector2, item_position: Vector2) -> Vector2:
	return item_position + (previous_size - new_size) * 0.5
