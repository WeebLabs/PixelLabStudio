extends RefCounted

const Animator = preload("res://effects/animation/layer_animator.gd")
const BlendModes = preload("res://effects/blend/blend_mode.gd")
const Settings = preload("res://autoload/persistence/settings_schema.gd")
const WiggleGeometry = preload("res://effects/wiggle/wiggle_geometry.gd")
const SpriteVisibility = preload("res://ui_scenes/selectedSprite/sprite_visibility_policy.gd")
const SpriteHierarchy = preload("res://ui_scenes/selectedSprite/sprite_hierarchy.gd")
const LegacyCompat = preload("res://autoload/domain/legacy_canvas_compat.gd")

class FakeCanvasLayer extends RefCounted:
	var path: String
	var size: Vector2
	var frames: int
	func _init(layer_path: String, layer_size: Vector2, frame_count: int = 1) -> void:
		path = layer_path
		size = layer_size
		frames = frame_count

class FakeLayer extends RefCounted:
	var id: int
	var parentId: Variant
	func _init(layer_id: int, parent_id: Variant) -> void:
		id = layer_id
		parentId = parent_id

func run(t) -> void:
	_test_animation_curves(t)
	_test_oscillation(t)
	_test_blend_registry(t)
	_test_wiggle_geometry(t)
	_test_sprite_policies(t)
	_test_settings_source_contract(t)
	_test_legacy_canvas_compat(t)

func _test_animation_curves(t) -> void:
	t.assert_approx(Animator.envelope("smooth", 0.0), 0.0, 0.00001, "smooth curve starts at rest")
	t.assert_approx(Animator.envelope("smooth", 0.5), 1.0, 0.00001, "smooth curve reaches its peak")
	t.assert_approx(Animator.envelope("smooth", 1.0), 0.0, 0.00001, "smooth curve returns to rest")
	t.assert_approx(Animator.envelope("pulse", 0.5), 1.0, 0.00001, "pulse curve peaks halfway")
	t.assert_approx(Animator.envelope("unknown", 0.5), 1.0, 0.00001, "unknown curves retain the legacy smooth fallback")

func _test_oscillation(t) -> void:
	var animator = Animator.new()
	var clips := [{
		"shape": "oscillate",
		"channel": "translation",
		"freqX": PI * 0.5,
		"freqY": 0.0,
		"ampX": 10.0,
		"ampY": 0.0,
	}]
	animator.evaluate(clips, 1, 1.0 / 60.0)
	t.assert_approx(animator.trans.x, 10.0, 0.0001, "legacy oscillation reaches the expected X amplitude")
	t.assert_approx(animator.trans.y, 0.0, 0.0001, "legacy oscillation preserves an inactive Y axis")

func _test_blend_registry(t) -> void:
	t.assert_equal(BlendModes.count(), 14, "persisted blend mode registry remains append-only")
	t.assert_equal(BlendModes.display_name(BlendModes.Mode.NORMAL), "Normal", "normal blend mode keeps persisted index zero")
	t.assert_equal(BlendModes.display_name(999), "Normal", "invalid blend modes display as Normal")
	t.assert_true(BlendModes.is_native(BlendModes.Mode.ADD), "Add uses native compositing")
	t.assert_true(BlendModes.needs_backbuffer(BlendModes.Mode.MULTIPLY), "Multiply retains its screen-read requirement")


func _test_wiggle_geometry(t) -> void:
	var widths := WiggleGeometry.smooth_widths(3, PackedFloat32Array([4.0, 8.0]), 2.0)
	t.assert_equal(widths, PackedFloat32Array([8.0, 12.0, 16.0]), "wiggle widths interpolate and apply thickness in one pure boundary")
	var fallback := WiggleGeometry.smooth_widths(2, PackedFloat32Array(), 0.5)
	t.assert_equal(fallback, PackedFloat32Array([8.0, 8.0]), "missing wiggle widths retain the compatible default")

	var path := PackedVector2Array([Vector2(10, 0), Vector2(5, 0), Vector2.ZERO])
	var oriented := WiggleGeometry.orient_to_origin(path, Vector2.ZERO)
	t.assert_equal(oriented[0], Vector2.ZERO, "wiggle path roots at the endpoint nearest the authored origin")
	t.assert_approx(WiggleGeometry.project_fraction(oriented, Vector2(7.5, 2.0)), 0.75, 0.0001, "path projection returns stable arc fraction")
	t.assert_equal(WiggleGeometry.tangent(oriented, 0.25), Vector2(5, 0), "path tangent follows the oriented rest geometry")

	var joints := PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(20, 0)])
	var beside := Vector2(12, -6)
	var bind := WiggleGeometry.bind_to_chain(beside, joints)
	var at_rest := WiggleGeometry.follow_chain(bind, joints)
	t.assert_approx((at_rest["position"] as Vector2).distance_to(beside), 0.0, 0.0001, "a child beside the wiggle chain stays put while the chain is at rest")
	t.assert_approx(float(at_rest["rotation"]), 0.0, 0.0001, "an at-rest wiggle chain adds no child rotation")
	var bent := PackedVector2Array([Vector2.ZERO, Vector2(10, 0), Vector2(10, 10)])
	var riding := WiggleGeometry.follow_chain(bind, bent)
	t.assert_approx((riding["position"] as Vector2).distance_to(Vector2(16, 2)), 0.0, 0.0001, "a bound child keeps its sideways offset as its segment turns")
	t.assert_approx(float(riding["rotation"]), PI / 2.0, 0.0001, "a bound child turns with its chain segment")

	var image := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(2, 6):
		for x in range(2, 14):
			image.set_pixel(x, y, Color.WHITE)
	t.assert_approx(WiggleGeometry.content_reach(image, Vector2(8, 4), Vector2.RIGHT, 16.0), 5.0, 0.001, "content reach stops at the opaque silhouette edge")
	var fitted := WiggleGeometry.auto_fit(image, Vector2(16, 8), Vector2(6, 0), 8)
	var fitted_path: PackedVector2Array = fitted["path"]
	var fitted_widths: PackedFloat32Array = fitted["widths"]
	t.assert_true(fitted_path.size() >= 2, "auto-fit returns a usable ribbon centerline")
	t.assert_equal(fitted_widths.size(), fitted_path.size(), "auto-fit returns one coverage width per control point")
	t.assert_true(fitted_path[0].distance_to(Vector2(2, 4)) <= fitted_path[-1].distance_to(Vector2(2, 4)), "auto-fit preserves the authored root end")
	var widths_valid := true
	for width in fitted_widths:
		widths_valid = widths_valid and width >= WiggleGeometry.WIDTH_MIN
	t.assert_true(widths_valid, "auto-fit enforces the minimum ribbon coverage")


func _test_sprite_policies(t) -> void:
	var hidden := SpriteVisibility.talk_blink_visual(2, 0, false, false, false, 0.75, false)
	t.assert_false(hidden["normally_visible"], "talk/blink policy hides talk-only artwork while idle")
	t.assert_equal(hidden["modulate"], Color(0, 0, 0, 0), "hidden view-mode artwork is fully transparent")
	var preview := SpriteVisibility.talk_blink_visual(2, 0, false, false, true, 0.75, false)
	t.assert_equal(preview["modulate"], Color(0.15, 0.15, 0.15, 0.15), "edit preview composes fade and layer opacity")
	t.assert_equal(preview["visibility_layer"], 2, "edit-only preview is excluded from NDI output")
	var path_edit := SpriteVisibility.talk_blink_visual(2, 0, false, false, false, 0.25, true)
	t.assert_equal(path_edit["modulate"], Color.WHITE, "path editing exposes the full source artwork")
	t.assert_false(SpriteVisibility.costume_visible([1, 0], 2, false), "disabled costume slots remain hidden")
	t.assert_false(SpriteVisibility.costume_visible([1, 1], 1, true), "manual hiding overrides costume membership")
	t.assert_false(SpriteVisibility.costume_visible([1], 3, false), "invalid costume indexes fail closed")

	var root := FakeLayer.new(1, null)
	var child := FakeLayer.new(2, 1)
	var grandchild := FakeLayer.new(3, 2)
	var cycle := FakeLayer.new(1, 3)
	t.assert_equal(SpriteHierarchy.direct_children([root, child, grandchild], 1), [child], "hierarchy policy resolves direct children")
	t.assert_equal(SpriteHierarchy.descendants([root, child, grandchild], 1), [child, grandchild], "hierarchy policy resolves descendants without tree walks")
	t.assert_equal(SpriteHierarchy.descendants([root, child, grandchild, cycle], 1).size(), 2, "hierarchy traversal terminates safely on a reused cyclic identifier")

func _test_settings_source_contract(t) -> void:
	var defaults := Settings.defaults()
	for key in ["volume", "sense", "maxFPS", "costumeKeys", "ndiEnabled", "ndiCropRect", "recordingFormat", "recordingFPS"]:
		t.assert_true(defaults.has(key), "settings schema declares %s" % key)
	t.assert_equal(defaults["costumeKeys"].size(), 10, "ten costume binding slots remain available")


# Rigs imported before PSD support carry one full-canvas image per layer. The
# replace path has to recognise that shape and re-anchor each cropped layer onto
# the canvas coordinate its predecessor occupied.
func _test_legacy_canvas_compat(t) -> void:
	var canvas := Vector2(1000, 800)
	var legacy_rig := [
		FakeCanvasLayer.new("/avatars/Head.png", canvas),
		FakeCanvasLayer.new("/avatars/Body.png", canvas),
	]
	var verdict := LegacyCompat.evaluate(legacy_rig, canvas)
	t.assert_true(verdict["legacy"], "a rig of equally sized file-backed layers reads as a full-canvas import")
	t.assert_equal(verdict["canvas"], canvas, "the shared layer size is reported as the rig's canvas")
	t.assert_false(verdict["mismatch"], "a PSD authored at the rig's canvas size is accepted")
	t.assert_equal(verdict["layers"], 2, "every full-canvas layer is counted as affected")

	t.assert_true(
		LegacyCompat.evaluate(legacy_rig, Vector2(1200, 800))["mismatch"],
		"a PSD authored at other dimensions is reported as a mismatch",
	)

	var cropped_rig := [
		FakeCanvasLayer.new("psd://Head", Vector2(200, 180)),
		FakeCanvasLayer.new("psd://Body", Vector2(400, 520)),
	]
	t.assert_false(LegacyCompat.evaluate(cropped_rig, canvas)["legacy"], "a rig of cropped PSD layers is left alone")
	t.assert_false(
		LegacyCompat.evaluate([FakeCanvasLayer.new("psd://Head", canvas)], canvas)["legacy"],
		"uniform sizing alone does not convict a rig imported from a PSD",
	)

	# Animated layers hold a horizontal sheet, so their raw size is not a canvas
	# and the placement never applies to them.
	var animated := FakeCanvasLayer.new("animated://Mouth", Vector2(3000, 800), 3)
	t.assert_equal(LegacyCompat.layer_size(animated), Vector2(1000, 800), "sheet layers report their frame footprint")
	t.assert_false(LegacyCompat.is_legacy_layer(animated, canvas), "sheet layers are excluded from the placement")
	t.assert_true(
		LegacyCompat.evaluate([legacy_rig[0], legacy_rig[1], animated], canvas)["legacy"],
		"a sheet layer does not break detection for the still layers around it",
	)

	# A layer whose replacement sits at canvas pixels (300, 200) with a 200x180
	# crop: its centre is 100 left and 210 above the canvas centre.
	var item_position := Vector2(300 + 100, 200 + 90) - canvas * 0.5
	t.assert_equal(
		LegacyCompat.offset_after_replace(Vector2(40, -20), item_position),
		Vector2(40, -20) + item_position,
		"the pivot correction is the replacement's placement inside the source canvas",
	)
	t.assert_equal(
		LegacyCompat.texture_origin_shift(canvas, Vector2(200, 180), item_position),
		Vector2(300, 200),
		"texture-space data moves by the replacement's top-left inside the texture it supersedes",
	)
	t.assert_equal(
		LegacyCompat.texture_origin_shift(canvas, canvas, Vector2.ZERO),
		Vector2.ZERO,
		"a replacement that spans the whole canvas leaves texture-space data untouched",
	)
	t.assert_equal(
		LegacyCompat.offset_after_replace(Vector2(40, -20), Vector2.ZERO),
		Vector2(40, -20),
		"a replacement that spans the whole canvas is a no-op",
	)
