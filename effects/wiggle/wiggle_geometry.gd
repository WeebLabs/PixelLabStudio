extends RefCounted

const WiggleAppendage = preload("res://effects/wiggle/wiggle_appendage.gd")

const WIDTH_MIN := 4.0
const WIDTH_MARGIN := 3.0
const WIDTH_GROW := 1.08


static func smooth_widths(point_count: int, control_widths: PackedFloat32Array, thickness: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var width_count := control_widths.size()
	var scale := maxf(thickness, 0.01)
	for i in point_count:
		if width_count == 0:
			out.append(16.0 * scale)
		elif width_count == 1 or point_count <= 1:
			out.append(control_widths[0] * scale)
		else:
			var f := float(i) / float(point_count - 1) * float(width_count - 1)
			var a := int(f)
			var b := mini(a + 1, width_count - 1)
			out.append(lerp(control_widths[a], control_widths[b], f - float(a)) * scale)
	return out


static func mesh_rest_path(path: PackedVector2Array, segments: int) -> PackedVector2Array:
	var smooth: PackedVector2Array = WiggleAppendage.smooth_path(path, 10) if path.size() >= 3 else path
	if smooth.size() < 2:
		return smooth
	var joints: PackedVector2Array = WiggleAppendage.resample_equal_arc(smooth, clampi(segments, 2, 48) + 1)
	if joints.size() < 3:
		return joints
	var segment_count := maxi(joints.size() - 1, 1)
	var points_per_segment := clampi(
		int(ceil(float(WiggleAppendage.RENDER_POINTS) / float(segment_count))),
		4,
		48,
	)
	return WiggleAppendage.smooth_path(joints, points_per_segment)


static func auto_fit(image: Image, image_size: Vector2, offset: Vector2, segments: int) -> Dictionary:
	if image == null:
		return {"path": PackedVector2Array(), "widths": PackedFloat32Array()}
	var path := trace_centerline(image)
	if path.size() < 2:
		var used_rect := image.get_used_rect()
		if used_rect.size.x <= 0 or used_rect.size.y <= 0:
			used_rect = Rect2i(0, 0, int(image_size.x), int(image_size.y))
		var center := Vector2(used_rect.position) + Vector2(used_rect.size) * 0.5
		var horizontal := used_rect.size.x >= used_rect.size.y
		var half_length := (float(used_rect.size.x) if horizontal else float(used_rect.size.y)) * 0.5
		var axis := Vector2.RIGHT if horizontal else Vector2.DOWN
		path = PackedVector2Array([center - axis * half_length, center, center + axis * half_length])
	path = extend_ends(image, path)
	path = orient_to_origin(path, image_size * 0.5 - offset)
	return {
		"path": path,
		"widths": fit_widths_to_content(image, path, segments),
	}


static func orient_to_origin(path: PackedVector2Array, origin_texture_position: Vector2) -> PackedVector2Array:
	if path.size() < 2:
		return path
	if path[path.size() - 1].distance_squared_to(origin_texture_position) >= path[0].distance_squared_to(origin_texture_position):
		return path
	var reversed := PackedVector2Array()
	for i in range(path.size() - 1, -1, -1):
		reversed.append(path[i])
	return reversed


static func extend_ends(image: Image, path: PackedVector2Array) -> PackedVector2Array:
	if image == null or path.size() < 2:
		return path
	var reach := maxf(float(image.get_width()), float(image.get_height()))
	var out := path.duplicate()
	var last_index := out.size() - 1
	var start_direction := out[0] - out[1]
	if start_direction.length() > 0.001:
		start_direction = start_direction.normalized()
		var start_overhang := content_reach(image, out[0], start_direction, reach, 0.05)
		if start_overhang > 0.5:
			out[0] += start_direction * (start_overhang + 1.0)
	var end_direction := out[last_index] - out[last_index - 1]
	if end_direction.length() > 0.001:
		end_direction = end_direction.normalized()
		var end_overhang := content_reach(image, out[last_index], end_direction, reach, 0.05)
		if end_overhang > 0.5:
			out[last_index] += end_direction * (end_overhang + 1.0)
	return out


static func trace_centerline(image: Image) -> PackedVector2Array:
	if image == null:
		return PackedVector2Array()
	var width := image.get_width()
	var height := image.get_height()
	var reach := float(maxi(width, height))
	var stride := maxi(1, int(reach / 200.0))
	var total := Vector2.ZERO
	var count := 0
	var samples: Array = []
	for y in range(0, height, stride):
		for x in range(0, width, stride):
			if alpha_at(image, x, y) > 0.5:
				var point := Vector2(x, y)
				samples.append(point)
				total += point
				count += 1
	if count < 6:
		return PackedVector2Array()
	var centroid: Vector2 = total / float(count)
	var covariance_xx := 0.0
	var covariance_xy := 0.0
	var covariance_yy := 0.0
	for point in samples:
		var delta: Vector2 = point - centroid
		covariance_xx += delta.x * delta.x
		covariance_xy += delta.x * delta.y
		covariance_yy += delta.y * delta.y
	var axis := Vector2(
		cos(0.5 * atan2(2.0 * covariance_xy, covariance_xx - covariance_yy)),
		sin(0.5 * atan2(2.0 * covariance_xy, covariance_xx - covariance_yy)),
	)
	var trace_step := maxf(reach * 0.02, 4.0)
	var start := centroid
	var best_distance := INF
	for point in samples:
		var distance: float = point.distance_to(centroid)
		if distance < best_distance:
			best_distance = distance
			start = point
	start = spine_center(image, start, axis, reach)[0]
	var forward := spine_walk(image, start, axis, trace_step, reach)
	var backward := spine_walk(image, start, -axis, trace_step, reach)
	var raw := PackedVector2Array()
	for i in range(backward.size() - 1, -1, -1):
		raw.append(backward[i])
	raw.append(start)
	for point in forward:
		raw.append(point)
	return simplify_path(raw, clampf(reach * 0.025, 5.0, 14.0))


static func spine_walk(image: Image, start: Vector2, initial_direction: Vector2, trace_step: float, reach: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var point := start
	var direction := initial_direction.normalized()
	for _step in 500:
		var next_point: Vector2 = point + direction * trace_step
		var centered := spine_center(image, next_point, direction, reach)
		if not centered[1]:
			break
		next_point = centered[0]
		var movement: Vector2 = next_point - point
		if movement.length() > trace_step * 3.0:
			break
		if movement.length() > 0.001:
			direction = movement.normalized()
		out.append(next_point)
		point = next_point
	return out


static func spine_center(image: Image, point: Vector2, direction: Vector2, reach: float) -> Array:
	var perpendicular := direction.orthogonal()
	var positive := content_reach(image, point, perpendicular, reach)
	var negative := content_reach(image, point, -perpendicular, reach)
	var on_content := alpha_at(image, int(round(point.x)), int(round(point.y))) > 0.25 or positive > 0.0 or negative > 0.0
	return [point + perpendicular * (positive - negative) * 0.5, on_content]


static func alpha_at(image: Image, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return 0.0
	return image.get_pixel(x, y).a


static func simplify_path(points: PackedVector2Array, epsilon: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep: Dictionary = {0: true, points.size() - 1: true}
	_simplify_segment(points, 0, points.size() - 1, epsilon, keep)
	var indices := keep.keys()
	indices.sort()
	var out := PackedVector2Array()
	for index in indices:
		out.append(points[index])
	return out


static func _simplify_segment(points: PackedVector2Array, low: int, high: int, epsilon: float, keep: Dictionary) -> void:
	if high <= low + 1:
		return
	var start: Vector2 = points[low]
	var end: Vector2 = points[high]
	var segment := end - start
	var length_squared := segment.length_squared()
	var furthest_distance := 0.0
	var furthest_index := -1
	for i in range(low + 1, high):
		var fraction := 0.0 if length_squared < 0.001 else clampf((points[i] - start).dot(segment) / length_squared, 0.0, 1.0)
		var distance: float = points[i].distance_to(start + segment * fraction)
		if distance > furthest_distance:
			furthest_distance = distance
			furthest_index = i
	if furthest_distance > epsilon and furthest_index > 0:
		keep[furthest_index] = true
		_simplify_segment(points, low, furthest_index, epsilon, keep)
		_simplify_segment(points, furthest_index, high, epsilon, keep)


static func fit_widths_to_content(image: Image, path: PackedVector2Array, segments: int) -> PackedFloat32Array:
	if image == null or path.is_empty():
		return PackedFloat32Array()
	var reach := maxf(float(image.get_width()), float(image.get_height()))
	var smooth := mesh_rest_path(path, segments)
	if smooth.size() < 2:
		smooth = path
	var sample_count := smooth.size()
	var sample_widths := PackedFloat32Array()
	sample_widths.resize(sample_count)
	for i in sample_count:
		var before: Vector2 = smooth[maxi(i - 1, 0)]
		var after: Vector2 = smooth[mini(i + 1, sample_count - 1)]
		var tangent := after - before
		if tangent.length() < 0.001:
			tangent = Vector2.RIGHT
		var perpendicular := tangent.normalized().orthogonal()
		var center: Vector2 = smooth[i]
		var extent := maxf(
			content_reach(image, center, perpendicular, reach, 0.08),
			content_reach(image, center, -perpendicular, reach, 0.08),
		)
		sample_widths[i] = maxf((extent + WIDTH_MARGIN) * WIDTH_GROW, WIDTH_MIN)
	var out := PackedFloat32Array()
	var control_count := path.size()
	out.resize(control_count)
	for i in control_count:
		out[i] = WIDTH_MIN
	if control_count == 1:
		for width in sample_widths:
			out[0] = maxf(out[0], width)
		return out
	for i in sample_count:
		var fraction := float(i) / float(sample_count - 1) * float(control_count - 1)
		var before := int(fraction)
		var after := mini(before + 1, control_count - 1)
		out[before] = maxf(out[before], sample_widths[i])
		out[after] = maxf(out[after], sample_widths[i])
	return out


static func content_reach(image: Image, start: Vector2, direction: Vector2, reach: float, threshold := 0.25) -> float:
	var last_opaque := 0.0
	var transparent_gap := 0.0
	var width := image.get_width()
	var height := image.get_height()
	var distance := 1.0
	while distance <= reach:
		var point := start + direction * distance
		var x := int(round(point.x))
		var y := int(round(point.y))
		var alpha := 0.0
		if x >= 0 and y >= 0 and x < width and y < height:
			alpha = image.get_pixel(x, y).a
		if alpha > threshold:
			last_opaque = distance
			transparent_gap = 0.0
		else:
			transparent_gap += 1.0
			if transparent_gap >= 8.0 and last_opaque > 0.0:
				break
		distance += 1.0
	return last_opaque


static func project_fraction(path: PackedVector2Array, point: Vector2) -> float:
	var point_count := path.size()
	if point_count < 2:
		return 0.0
	var lengths := PackedFloat32Array()
	var total_length := 0.0
	for i in point_count - 1:
		var length := path[i].distance_to(path[i + 1])
		lengths.append(length)
		total_length += length
	if total_length < 0.0001:
		return 0.0
	var best_fraction := 0.0
	var best_distance := INF
	var accumulated := 0.0
	for i in point_count - 1:
		var start: Vector2 = path[i]
		var end: Vector2 = path[i + 1]
		var segment := end - start
		var segment_length := maxf(segment.length(), 0.0001)
		var local_fraction := clampf((point - start).dot(segment) / (segment_length * segment_length), 0.0, 1.0)
		var projected := start + segment * local_fraction
		var distance := point.distance_squared_to(projected)
		if distance < best_distance:
			best_distance = distance
			best_fraction = (accumulated + local_fraction * segment_length) / total_length
		accumulated += lengths[i]
	return best_fraction


static func tangent(path: PackedVector2Array, fraction: float) -> Vector2:
	var point_count := path.size()
	if point_count < 2:
		return Vector2.RIGHT
	var index := clampi(int(fraction * float(point_count - 1)), 0, point_count - 2)
	return path[index + 1] - path[index]
