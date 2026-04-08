class_name GemCutProjector
extends RefCounted

## Derives a 2D render packet from the canonical 3D cut model.

const GemProjectedCutResourceScript = preload("res://resources/visuals/gem_projected_cut_resource.gd")
const GemCutPrimitivesScript = preload("res://core/visuals/gem_cut_primitives.gd")

const EXCLUDED_TOP_ZONES := {
	"pavilion": true,
	"culet": true,
	"girdle_band": true,
}
const TARGET_HORIZONTAL_SPAN := GemCutPrimitivesScript.GEM_RADIUS * 2.0


static func project(model):
	if model == null:
		return null
	var projected = GemProjectedCutResourceScript.new()
	projected.spec_id = model.spec_id
	projected.cut_id = model.cut_id
	projected.display_name = model.display_name
	projected.shape_category = model.shape_category
	projected.geometry_signature = model.geometry_signature
	projected.orthographic_top_roll_degrees = model.orthographic_top_roll_degrees
	projected.orthographic_side_yaw_degrees = model.orthographic_side_yaw_degrees
	projected.orthographic_axis_fit_scale = model.orthographic_axis_fit_scale

	var top_source_indices: Array[int] = []
	var top_polygons: Array[PackedVector2Array] = []
	var top_normals: Array[Vector3] = []
	var outer_loop = PackedVector2Array()
	for vertex in model.outer_loop:
		outer_loop.append(_project_point(vertex))
	for facet_index in model.facet_count():
		var zone = model.facet_zones[facet_index] if facet_index < model.facet_zones.size() else ""
		if EXCLUDED_TOP_ZONES.has(zone):
			continue
		var polygon = PackedVector2Array()
		for vertex in model.facet_vertices[facet_index]:
			polygon.append(_project_point(vertex))
		if polygon.size() < 3:
			continue
		if absf(GemCutPrimitivesScript.polygon_signed_area(polygon)) <= 0.000001:
			continue
		top_source_indices.append(facet_index)
		top_polygons.append(polygon)
		top_normals.append(model.facet_normals[facet_index] if facet_index < model.facet_normals.size() else Vector3.UP)

	var transform = _build_unit_transform()
	var normalized_outer = _transform_polygon(outer_loop, transform)
	projected.silhouette = normalized_outer
	for polygon_index in top_polygons.size():
		var normalized = _transform_polygon(top_polygons[polygon_index], transform)
		projected.add_facet(
			normalized,
			top_normals[polygon_index],
			model.facet_zones[top_source_indices[polygon_index]]
		)

	_collect_edges(projected)
	_build_projected_pavilion(projected, model, top_source_indices, transform)
	_precompute_facet_constants(projected)
	return projected


static func _build_projected_pavilion(
	projected,
	model,
	_top_source_indices: Array[int],
	transform: Callable,
) -> void:
	projected.clear_pavilion()
	var target_polygons: Array[PackedVector2Array] = projected.facet_vertices
	for source_index in model.facet_count():
		var zone = model.facet_zones[source_index] if source_index < model.facet_zones.size() else ""
		if zone != "pavilion" and zone != "culet":
			continue
		var pav_poly = PackedVector2Array()
		for vertex in model.facet_vertices[source_index]:
			pav_poly.append(_project_point(vertex))
		pav_poly = _transform_polygon(pav_poly, transform)
		if pav_poly.size() < 3:
			continue
		for target_index in target_polygons.size():
			if target_index >= projected.facet_zones.size():
				continue
			if projected.facet_zones[target_index] == "table":
				continue
			var clipped = GemCutPrimitivesScript.clip_polygon(pav_poly, target_polygons[target_index])
			var clipped_area = absf(GemCutPrimitivesScript.polygon_signed_area(clipped))
			if clipped.size() >= 3 and clipped_area > 0.000005:
				projected.add_pavilion_fragment(
					clipped,
					model.facet_normals[source_index] if source_index < model.facet_normals.size() else Vector3.DOWN,
					source_index,
					target_index
				)


static func _collect_bounds(polygons: Array[PackedVector2Array], outer_loop: PackedVector2Array) -> Dictionary:
	var min_pt = Vector2(INF, INF)
	var max_pt = Vector2(-INF, -INF)
	for polygon in polygons:
		for point in polygon:
			min_pt.x = minf(min_pt.x, point.x)
			min_pt.y = minf(min_pt.y, point.y)
			max_pt.x = maxf(max_pt.x, point.x)
			max_pt.y = maxf(max_pt.y, point.y)
	for point in outer_loop:
		min_pt.x = minf(min_pt.x, point.x)
		min_pt.y = minf(min_pt.y, point.y)
		max_pt.x = maxf(max_pt.x, point.x)
		max_pt.y = maxf(max_pt.y, point.y)
	return {
		"min": min_pt,
		"max": max_pt,
	}


static func _build_unit_transform() -> Callable:
	var target_size = 1.0 - 2.0 * GemCutPrimitivesScript.FIT_MARGIN
	var scale_factor = target_size / maxf(TARGET_HORIZONTAL_SPAN, 0.00001)
	return func(point: Vector2) -> Vector2:
		return point * scale_factor + GemCutPrimitivesScript.CENTER


static func _transform_polygon(points: PackedVector2Array, transform: Callable) -> PackedVector2Array:
	var polygon = PackedVector2Array()
	polygon.resize(points.size())
	for i in points.size():
		polygon[i] = transform.call(points[i])
	return polygon


static func _collect_edges(projected) -> void:
	projected.edge_segments.clear()
	projected.edge_facet_a = PackedInt32Array()
	projected.edge_facet_b = PackedInt32Array()
	var seen = {}
	for facet_index in projected.facet_count():
		var polygon = projected.facet_vertices[facet_index]
		for i in polygon.size():
			var a = polygon[i]
			var b = polygon[(i + 1) % polygon.size()]
			var key = _edge_key(a, b)
			if not seen.has(key):
				seen[key] = projected.edge_segments.size()
				projected.add_edge(a, b, facet_index, -1)
			else:
				var edge_index: int = seen[key]
				projected.edge_facet_b[edge_index] = facet_index


static func _precompute_facet_constants(projected) -> void:
	var count = projected.facet_count()
	projected.facet_centroids.resize(count)
	projected.facet_jitter.resize(count)
	projected.zone_brilliance_weights.resize(count)
	for i in count:
		var verts = projected.facet_vertices[i]
		var cx = 0.0
		var cy = 0.0
		for vertex in verts:
			cx += vertex.x
			cy += vertex.y
		cx /= maxf(float(verts.size()), 1.0)
		cy /= maxf(float(verts.size()), 1.0)
		projected.facet_centroids[i] = Vector2(cx, cy)
		var hash_val = sin(cx * 127.1 + cy * 311.7) * 43758.5453
		hash_val = hash_val - floorf(hash_val)
		projected.facet_jitter[i] = (hash_val - 0.5) * 0.08
		projected.zone_brilliance_weights[i] = _zone_brilliance_weight(
			projected.facet_zones[i] if i < projected.facet_zones.size() else ""
		)


static func _zone_brilliance_weight(zone: String) -> float:
	match zone:
		"table":
			return 0.5
		"star":
			return 0.25
		"girdle":
			return -0.4
		"step":
			return -0.2
		_:
			return 0.0


static func _project_point(point: Vector3) -> Vector2:
	return Vector2(point.x, -point.y)


static func _edge_key(a: Vector2, b: Vector2) -> String:
	var ax = snappedf(a.x, 0.0001)
	var ay = snappedf(a.y, 0.0001)
	var bx = snappedf(b.x, 0.0001)
	var by = snappedf(b.y, 0.0001)
	var a_key = "%s,%s" % [ax, ay]
	var b_key = "%s,%s" % [bx, by]
	if a_key < b_key:
		return "%s-%s" % [a_key, b_key]
	return "%s-%s" % [b_key, a_key]
