class_name GemCutInspection
extends RefCounted
## Inspection consumes the compiled hull: no second geometry implementation.
const Compiler := preload("res://core/lapidary/cut/cut_compiler.gd")
const Hull := preload("res://core/lapidary/cut/hull_validator.gd")

static func inspect(stone: GemStone) -> Dictionary:
	var error := GemJobValidator.specimen_error(stone)
	if not error.is_empty(): return {"error": error}
	if stone.shape.mode != "faceted": return {"error": "Facet inspection requires an explicit faceted program"}
	var tolerance := stone.condition.workmanship.normalized_tolerances(stone.size_mm) if stone.condition != null and stone.condition.workmanship != null else Vector4.ZERO
	var geometry := Compiler.compile(stone.cut, stone.shape, stone.seed, tolerance)
	if geometry.has("compilation_error"): return {"error": geometry.compilation_error}
	var minimum := Vector3(INF, INF, INF); var maximum := -minimum
	var facets := []
	for index in geometry.planes.size() / 8:
		var polygon := GemShapeCompiler._clip_face64(geometry.planes, index)
		var points := PackedVector3Array()
		for vertex: Dictionary in polygon:
			var point := Vector3(vertex.point[0], vertex.point[1], vertex.point[2]) * stone.size_mm
			points.append(point); minimum = minimum.min(point); maximum = maximum.max(point)
		facets.append({"name": geometry.facet_names[index], "id": geometry.facet_ids[index], "points_mm": points,
			"normal": Vector3(geometry.planes[index*8], geometry.planes[index*8+1], geometry.planes[index*8+2]),
			"anchor_mm": geometry.anchors[index] * stone.size_mm, "zone": int(geometry.planes[index*8+4]), "meet_contacts": geometry.meet_contacts[index]})
	if not minimum.is_finite() or not maximum.is_finite(): return {"error": "Inspection has no finite facets"}
	return {"error": "", "facets": facets, "bounds_min_mm": minimum, "bounds_max_mm": maximum,
		"dimensions_mm": maximum-minimum, "geometry": geometry, "physical_scale_mm": stone.size_mm}

static func section(geometry: Dictionary, normal: Vector3, offset: float, scale_mm: float) -> Dictionary:
	if not normal.is_finite() or normal.length_squared() < 1e-12 or not is_finite(offset) or not is_finite(scale_mm) or scale_mm <= 0: return {"error": "Invalid section plane or physical scale"}
	var planes: PackedFloat32Array = geometry.planes.duplicate()
	var count := planes.size() / 8
	var n := normal.normalized()
	planes.append_array(PackedFloat32Array([n.x, n.y, n.z, offset, 0, 0, 0, 0]))
	var frame := []
	var polygon := Hull._face_polygon(planes, count+1, count, frame, 0.0)
	var points := PackedVector3Array()
	for p in polygon: points.append((frame[2] + frame[0]*p.x + frame[1]*p.y) * scale_mm)
	return {"error": "", "points_mm": points, "area_mm2": absf(Hull._polygon_area(polygon)) * scale_mm * scale_mm}
