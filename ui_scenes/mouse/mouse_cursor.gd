extends Node2D

var text = ""
var _click_pending = false

@onready var label = $Tooltip/Label
@onready var area = $Area2D

func _ready():
	Global.mouse = self

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
		global_position = get_global_mouse_position()
		if _click_pending:
			_click_pending = false
			if !Global.originMode:
				var areas = _query_areas_at_mouse()
				var mouse_pos = get_global_mouse_position()
				var opaque = []
				var has_blocker = false
				for a in areas:
					if a.is_in_group("penis"):
						has_blocker = true
					elif _is_pixel_opaque(a, mouse_pos):
						opaque.append(a)
				# Sort frontmost (highest z_index) first
				opaque.sort_custom(_compare_z_descending)
				# Only block click if on UI panel with no visible sprite
				if !opaque.is_empty() or !has_blocker:
					Global.select(opaque)
	else:
		_click_pending = false
		visible = false

	text = ""

func _compare_z_descending(a: Area2D, b: Area2D) -> bool:
	var obj_a = a.get_parent().get_parent().get_parent()
	var obj_b = b.get_parent().get_parent().get_parent()
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
	return z_a > z_b

func _is_pixel_opaque(hit_area: Area2D, world_pos: Vector2) -> bool:
	var sprite_obj = hit_area.get_parent().get_parent().get_parent()
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

func _query_areas_at_mouse() -> Array:
	var space = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = get_global_mouse_position()
	params.collision_mask = area.collision_mask
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results = space.intersect_point(params)
	var found = []
	for r in results:
		if r.collider is Area2D:
			found.append(r.collider)
	return found
