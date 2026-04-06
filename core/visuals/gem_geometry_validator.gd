class_name GemGeometryValidator
extends RefCounted

const EDGE_EPSILON := 0.0001
const AREA_EPSILON := 0.000001
const BOUNDARY_TOLERANCE := 0.003


static func validate_model(model, spec = null) -> Dictionary:
	var report := {
		"errors": PackedStringArray(),
		"warnings": PackedStringArray(),
	}
	if model == null:
		report["errors"].append("Model is null")
		return report
	if model.facet_count() <= 0:
		report["errors"].append("Model has no facets")
		return report

	var outer_polygon := PackedVector2Array()
	for vertex in model.outer_loop:
		outer_polygon.append(Vector2(vertex.x + 0.5, 0.5 - vertex.y))
	var edge_counts: Dictionary = {}
	var min_interior_angle_degrees := 4.0
	var max_edge_ratio := 45.0
	if spec != null and typeof(spec.constraints) == TYPE_DICTIONARY:
		min_interior_angle_degrees = float(spec.constraints.get("min_interior_angle_degrees", min_interior_angle_degrees))
		max_edge_ratio = float(spec.constraints.get("max_edge_ratio", max_edge_ratio))

	for facet_index in model.facet_count():
		var vertices: PackedVector3Array = model.facet_vertices[facet_index]
		if vertices.size() < 3:
			report["errors"].append("Facet %d has fewer than 3 vertices" % facet_index)
			continue
		var area := _polygon_area_3d(vertices)
		if area <= AREA_EPSILON:
			report["errors"].append("Facet %d is degenerate" % facet_index)
		var normal: Vector3 = model.facet_normals[facet_index] if facet_index < model.facet_normals.size() else Vector3.ZERO
		var centroid := _facet_centroid(vertices)
		if normal.is_zero_approx():
			report["errors"].append("Facet %d has a zero normal" % facet_index)
		elif normal.dot(centroid) <= 0.0:
			report["errors"].append("Facet %d normal faces inward" % facet_index)
		var edge_lengths := PackedFloat32Array()
		for vertex_index in vertices.size():
			var next_index := (vertex_index + 1) % vertices.size()
			var edge_length := vertices[vertex_index].distance_to(vertices[next_index])
			edge_lengths.append(edge_length)
			if edge_length <= EDGE_EPSILON:
				report["errors"].append("Facet %d contains duplicate vertices" % facet_index)
			var edge_key := _edge_key(vertices[vertex_index], vertices[next_index])
			edge_counts[edge_key] = int(edge_counts.get(edge_key, 0)) + 1
		if not edge_lengths.is_empty():
			var longest := 0.0
			var shortest := INF
			for edge_length in edge_lengths:
				longest = maxf(longest, edge_length)
				shortest = minf(shortest, edge_length)
			if shortest <= EDGE_EPSILON:
				report["errors"].append("Facet %d collapses to zero-width edges" % facet_index)
			elif longest / shortest > max_edge_ratio:
				report["warnings"].append("Facet %d is extremely skinny" % facet_index)
		var min_angle := _min_interior_angle_degrees(vertices)
		if min_angle < min_interior_angle_degrees:
			report["warnings"].append("Facet %d falls below the minimum interior-angle threshold" % facet_index)
		var zone := StringName(model.facet_zones[facet_index] if facet_index < model.facet_zones.size() else &"")
		if outer_polygon.size() >= 3 and (zone == &"pavilion" or zone == &"culet"):
			for vertex in vertices:
				var point_2d := Vector2(vertex.x + 0.5, 0.5 - vertex.y)
				if not Geometry2D.is_point_in_polygon(point_2d, outer_polygon) and not _point_near_polygon_boundary(point_2d, outer_polygon, BOUNDARY_TOLERANCE):
					report["warnings"].append("Facet %d extends beyond the crown footprint" % facet_index)
					break

	for edge_key in edge_counts.keys():
		var count := int(edge_counts.get(edge_key, 0))
		if count != 2:
			report["errors"].append("Edge %s is shared %d times" % [String(edge_key), count])

	if spec != null and int(spec.get_symmetry_sector_count()) <= 0:
		report["warnings"].append("Spec does not declare positive symmetry sectors")
	return report


static func validate_or_reject(model, spec = null):
	var report := validate_model(model, spec)
	var errors: PackedStringArray = report.get("errors", PackedStringArray())
	var warnings: PackedStringArray = report.get("warnings", PackedStringArray())
	for warning in warnings:
		push_warning("GemGeometryValidator: %s" % warning)
	if not errors.is_empty():
		for error_message in errors:
			push_error("GemGeometryValidator: %s" % error_message)
		return null
	return model


static func _facet_centroid(vertices: PackedVector3Array) -> Vector3:
	var centroid := Vector3.ZERO
	for vertex in vertices:
		centroid += vertex
	return centroid / float(maxi(vertices.size(), 1))


static func _polygon_area_3d(vertices: PackedVector3Array) -> float:
	if vertices.size() < 3:
		return 0.0
	var area := 0.0
	for index in range(1, vertices.size() - 1):
		area += (vertices[index] - vertices[0]).cross(vertices[index + 1] - vertices[0]).length() * 0.5
	return area


static func _min_interior_angle_degrees(vertices: PackedVector3Array) -> float:
	var min_angle := 180.0
	for index in vertices.size():
		var prev := vertices[(index - 1 + vertices.size()) % vertices.size()]
		var current := vertices[index]
		var next := vertices[(index + 1) % vertices.size()]
		var a := (prev - current).normalized()
		var b := (next - current).normalized()
		if a.is_zero_approx() or b.is_zero_approx():
			return 0.0
		min_angle = minf(min_angle, rad_to_deg(acos(clampf(a.dot(b), -1.0, 1.0))))
	return min_angle


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var key_a := _vertex_key(a)
	var key_b := _vertex_key(b)
	return "%s|%s" % [key_a, key_b] if key_a < key_b else "%s|%s" % [key_b, key_a]


static func _vertex_key(vertex: Vector3) -> String:
	return "%d:%d:%d" % [
		int(round(vertex.x / EDGE_EPSILON)),
		int(round(vertex.y / EDGE_EPSILON)),
		int(round(vertex.z / EDGE_EPSILON)),
	]


static func _point_near_polygon_boundary(point: Vector2, polygon: PackedVector2Array, tolerance: float) -> bool:
	for index in polygon.size():
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) <= tolerance:
			return true
	return false
