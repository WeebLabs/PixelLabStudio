extends Node2D

# The layer the grab areas sit on. Taking it from the cursor's own Area2D meant
# that node had to carry a matching mask, which made the physics server pair the
# cursor with every layer in the rig, every tick, for a query that reads the
# layer bit and nothing else. The constant lets that mask go to zero.
const SELECT_MASK := 1

# How far off an opaque pixel a click may land and still pick that layer, in
# screen pixels. The alpha test samples one texel of a moving target, so on a
# bouncing rig a click aimed at a thin or soft-edged layer regularly lands on a
# transparent texel and the whole click resolves to nothing, which clears the
# selection. The exact pixel is always tried first and decides the answer
# whenever it hits something, so this only rescues clicks that would otherwise
# have selected nothing at all.
const PICK_TOLERANCE_PX := 3.0

var text = ""
var _click_pending = false

@onready var label = $Tooltip/Label
@onready var area = $Area2D

func _ready():
	Global.attach_mouse(self)


func _exit_tree() -> void:
	Global.detach_mouse(self)

func _unhandled_input(event):
	if event.is_action_pressed("mouse_left"):
		_click_pending = true

func _process(delta):
	if Global.main.editMode:
		if text != "":
			label.text = text
			visible = true
		else:
			visible = false
		# MouseCursor lives on UILayer (CanvasLayer), so get_global_mouse_position()
		# returns viewport-space coords — exactly what we want for screen-space
		# cursor positioning.
		global_position = get_global_mouse_position()
		if _click_pending:
			_click_pending = false
			if !Global.originMode and !Global.wigglePathMode:
				var areas = _query_areas_at_mouse()
				# Sprite areas live in world space, so hit-test with the world
				# mouse rather than the viewport coords above.
				var world_mouse = _world_mouse_position()
				var opaque = _opaque_candidates(areas, world_mouse)
				_sort_top_first(opaque)
				# A click over a sidebar/menu panel must never select avatar
				# elements behind it (including the gaps between layer-list rows).
				# Only clicks that land on open canvas reach selection; clicking a
				# panel leaves the current selection untouched.
				if !_is_over_panel():
					Global.select(opaque)
	else:
		_click_pending = false
		visible = false

	text = ""

# Convert the viewport mouse to world space via the canvas transform — used
# for sprite-pick queries since sprites live in world space but this node is
# on a CanvasLayer.
func _world_mouse_position() -> Vector2:
	var vp = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()

# The layers under the click, opaque ones only. The exact cursor pixel decides
# the answer whenever it hits anything; only a click that would otherwise select
# nothing falls back to the tolerance ring (see PICK_TOLERANCE_PX).
func _opaque_candidates(areas: Array, world_mouse: Vector2) -> Array:
	var opaque = _opaque_at(areas, world_mouse)
	if !opaque.is_empty():
		return opaque

	var reach = PICK_TOLERANCE_PX / maxf(Global.main.camera.zoom.x, 0.001)
	for step in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
			Vector2(1, 1).normalized(), Vector2(1, -1).normalized(),
			Vector2(-1, 1).normalized(), Vector2(-1, -1).normalized()]:
		opaque = _opaque_at(areas, world_mouse + step * reach)
		if !opaque.is_empty():
			return opaque
	return []


func _opaque_at(areas: Array, world_pos: Vector2) -> Array:
	var opaque = []
	for a in areas:
		if !a.is_in_group("canvas_input_blocker") and _is_pixel_opaque(a, world_pos):
			opaque.append(a)
	return opaque


# Order the candidates the way the user sees them, topmost first: visible layers
# before faded ones, then higher z, then later in draw order.
#
# The ordering has to be TOTAL, not just correct on z. Godot's sort is not
# stable, and the physics query hands back its hits in whatever order the
# broadphase holds them, which shifts as the avatar moves. Rigs routinely leave
# several layers at the same z, and with only z to compare, those layers came
# back in a different order from one click to the next: six distinct orders over
# twelve clicks, measured on a moving rig. That made both the topmost pick and
# the cycle below it arbitrary. Draw order is the real tie-break, since Godot
# draws equal z_index in tree order, so the layer later in the tree is the one
# actually on top.
func _sort_top_first(areas: Array) -> void:
	if areas.size() < 2:
		return
	var draw_order = _draw_order()
	areas.sort_custom(func(a: Area2D, b: Area2D) -> bool:
		var obj_a = Global.sprite_from_hit_area(a)
		var obj_b = Global.sprite_from_hit_area(b)
		var spr_a = obj_a.get("sprite") if obj_a != null else null
		var spr_b = obj_b.get("sprite") if obj_b != null else null
		# Visible (alpha > 0.5) before faded/hidden
		var vis_a = spr_a.self_modulate.a > 0.5 if spr_a != null else false
		var vis_b = spr_b.self_modulate.a > 0.5 if spr_b != null else false
		if vis_a != vis_b:
			return vis_a
		# Within same visibility group, higher z first
		var z_a = obj_a.get("z") if obj_a != null else 0
		var z_b = obj_b.get("z") if obj_b != null else 0
		if z_a != z_b:
			return z_a > z_b
		return draw_order.get(obj_a, -1) > draw_order.get(obj_b, -1)
	)


# Depth-first index of every layer under the avatar root, which is the order
# Godot draws them in within one z_index.
func _draw_order() -> Dictionary:
	var order := {}
	if Global.main != null and Global.main.origin != null:
		_index_layers(Global.main.origin, order)
	return order


func _index_layers(node: Node, order: Dictionary) -> void:
	for child in node.get_children():
		if child.is_in_group("saved"):
			order[child] = order.size()
		_index_layers(child, order)

func _is_pixel_opaque(hit_area: Area2D, world_pos: Vector2) -> bool:
	var sprite_obj = Global.sprite_from_hit_area(hit_area)
	if sprite_obj == null or !sprite_obj.visible:
		return false
	var spr = sprite_obj.get("sprite")
	var img = sprite_obj.get("imageData")
	if spr == null or img == null:
		return false

	# Use Sprite2D.get_rect() for correct frame rect in local space
	var rect = spr.get_rect()
	var local = spr.to_local(world_pos)

	# Convert to pixel coords within current frame
	var px = local.x - rect.position.x
	var py = local.y - rect.position.y

	if px < 0 or px >= rect.size.x or py < 0 or py >= rect.size.y:
		return false

	# Map to full image coords for sprite sheets
	var img_x = int(px) + spr.frame * int(rect.size.x)
	var img_y = int(py)

	if img_x < 0 or img_x >= img.get_width() or img_y < 0 or img_y >= img.get_height():
		return false

	return img.get_pixel(img_x, img_y).a > 0.1

func _is_over_panel() -> bool:
	return Global.isMouseOverSidebar()

func _query_areas_at_mouse() -> Array:
	var space = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	# Sprite Area2Ds live in world space, so query with world-mouse coords.
	params.position = _world_mouse_position()
	params.collision_mask = SELECT_MASK
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results = space.intersect_point(params)
	var found = []
	for r in results:
		if r.collider is Area2D:
			found.append(r.collider)
	return found
