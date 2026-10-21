class_name NDIOutputGeometry
extends RefCounted

const MIN_OUTPUT_SIZE := 64
const MAX_OUTPUT_SIZE := 8192
const DEFAULT_EDGES := [-500.0, -800.0, 500.0, 200.0]

static func normalize_edges(value: Variant) -> Array:
	if not value is Array or value.size() != 4:
		return DEFAULT_EDGES.duplicate()
	var edges := [float(value[0]), float(value[1]), float(value[2]), float(value[3])]
	for edge in edges:
		if not is_finite(edge):
			return DEFAULT_EDGES.duplicate()
	if edges[2] - edges[0] < 1.0 or edges[3] - edges[1] < 1.0:
		return DEFAULT_EDGES.duplicate()
	return edges

static func calculate(edges_value: Variant, mode: String, auto_width: int, manual_width: int, manual_height: int) -> Dictionary:
	var edges := normalize_edges(edges_value)
	var content_size := Vector2(edges[2] - edges[0], edges[3] - edges[1])
	var viewport_size: Vector2i
	if mode == "manual":
		viewport_size = Vector2i(
			clampi(manual_width, MIN_OUTPUT_SIZE, MAX_OUTPUT_SIZE),
			clampi(manual_height, MIN_OUTPUT_SIZE, MAX_OUTPUT_SIZE)
		)
	else:
		var width := clampi(auto_width, MIN_OUTPUT_SIZE, MAX_OUTPUT_SIZE)
		var height := clampi(roundi(width * content_size.y / content_size.x), 1, MAX_OUTPUT_SIZE)
		viewport_size = Vector2i(width, height)
	var zoom := minf(
		float(viewport_size.x) / content_size.x,
		float(viewport_size.y) / content_size.y
	)
	return {
		"edges": edges,
		"viewport_size": viewport_size,
		"zoom": zoom,
		"center": Vector2((edges[0] + edges[2]) * 0.5, (edges[1] + edges[3]) * 0.5),
	}
