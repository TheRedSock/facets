class_name GemShapeCompiler
extends RefCounted
const Silhouettes := preload("res://core/lapidary/cut/silhouettes.gd")
const Validator := preload("res://core/lapidary/cut/hull_validator.gd")
const WELD_EPS := 2.0e-6

static func from_hull(planes: PackedFloat32Array, identities := PackedInt32Array()) -> GemMesh:
	var mesh := GemMesh.new()
	if not Validator.check_bounded(planes):
		return mesh
	var cells := {}
	var faces: Array[Dictionary] = []
	for face in planes.size() / 8:
		var frame := []
		var polygon := Validator._face_polygon(planes, planes.size() / 8, face, frame, 0.0)
		var ring := PackedInt32Array()
		for point in polygon:
			var position: Vector3 = frame[2] + frame[0] * point.x + frame[1] * point.y
			position = _canonical_vertex(planes, position)
			var index := _weld(mesh, position, cells)
			if ring.is_empty() or ring[-1] != index:
				ring.append(index)
		if ring.size() > 1 and ring[0] == ring[-1]:
			ring.remove_at(ring.size() - 1)
		var facet := identities[face] if identities.size() == planes.size() / 8 else face
		if ring.size() >= 3:
			faces.append({"ring": ring, "facet": facet})
	var corner_count := mesh.vertices.size()
	for face: Dictionary in faces:
		var original: PackedInt32Array = face["ring"]
		var ring := PackedInt32Array()
		# A nearly vanishing facet can introduce a collinear corner on only
		# one neighbor's clipped polygon. Split both sides at every shared
		# corner before triangulation, so no T-junction remains.
		for edge in original.size():
			var a := original[edge]
			var b := original[(edge + 1) % original.size()]
			var delta := mesh.vertices[b] - mesh.vertices[a]
			var candidates := []
			for index in corner_count:
				if index == a or index == b:
					continue
				var t := (mesh.vertices[index] - mesh.vertices[a]).dot(delta) / delta.length_squared()
				if t <= 0.0 or t >= 1.0:
					continue
				if mesh.vertices[index].distance_squared_to(mesh.vertices[a] + delta * t) < WELD_EPS * WELD_EPS:
					candidates.append([t, index])
			candidates.sort_custom(func(a_value: Array, b_value: Array) -> bool: return a_value[0] < b_value[0])
			ring.append(a)
			for candidate: Array in candidates:
				ring.append(candidate[1])
		var center := Vector3.ZERO
		for index in ring:
			center += mesh.vertices[index] / ring.size()
		var center_index := mesh.vertices.size()
		mesh.vertices.append(center)
		for edge in ring.size():
			mesh.add_triangle(center_index, ring[edge], ring[(edge + 1) % ring.size()], face["facet"])
	return mesh

## Independently clipped faces accumulate float32 frame error. Resolve each
## corner from a common, well-conditioned triple of nearby support planes
## with scalar float64 arithmetic before welding. All incident faces then
## refer to the same physical intersection, rather than their own projection.
static func _canonical_vertex(planes: PackedFloat32Array, approximate: Vector3) -> Vector3:
	var nearby: Array[int] = []
	for index in planes.size() / 8:
		var offset := index * 8
		var distance := planes[offset] * approximate.x + planes[offset + 1] * approximate.y + planes[offset + 2] * approximate.z - planes[offset + 3]
		if absf(distance) < 0.00002:
			nearby.append(index)
	var best := 0.0
	var result := approximate
	for ai in nearby.size():
		for bi in range(ai + 1, nearby.size()):
			for ci in range(bi + 1, nearby.size()):
				var a := nearby[ai] * 8
				var b := nearby[bi] * 8
				var c := nearby[ci] * 8
				var bc := _cross64(planes, b, c)
				var determinant := planes[a] * bc[0] + planes[a + 1] * bc[1] + planes[a + 2] * bc[2]
				if absf(determinant) <= maxf(best, 1.0e-12):
					continue
				best = absf(determinant)
				var ca := _cross64(planes, c, a)
				var ab := _cross64(planes, a, b)
				for axis in 3:
					result[axis] = (planes[a + 3] * bc[axis] + planes[b + 3] * ca[axis] + planes[c + 3] * ab[axis]) / determinant
	return result

static func _cross64(planes: PackedFloat32Array, a: int, b: int) -> Array[float]:
	return [planes[a + 1] * planes[b + 2] - planes[a + 2] * planes[b + 1],
		planes[a + 2] * planes[b] - planes[a] * planes[b + 2],
		planes[a] * planes[b + 1] - planes[a + 1] * planes[b]]

static func _weld(mesh: GemMesh, position: Vector3, cells: Dictionary) -> int:
	var key := Vector3i((position / WELD_EPS).floor())
	for z in range(-1, 2):
		for y in range(-1, 2):
			for x in range(-1, 2):
				for index: int in cells.get(key + Vector3i(x, y, z), []):
					if mesh.vertices[index].distance_squared_to(position) <= WELD_EPS * WELD_EPS:
						return index
	var index := mesh.vertices.size()
	mesh.vertices.append(position)
	if not cells.has(key):
		cells[key] = []
	cells[key].append(index)
	return index

static func outline(shape: GemShape) -> PackedVector2Array:
	if not shape.outline_points.is_empty():
		return shape.outline_points.duplicate()
	var profile: Silhouettes.Silhouette = Silhouettes.make(shape.outline, shape)
	var points := PackedVector2Array()
	if profile == null:
		return points
	for i in shape.radial_segments:
		points.append(profile.point(TAU * i / shape.radial_segments))
	return points

static func compile(shape: GemShape) -> GemMesh:
	var points := outline(shape)
	var sections := shape.loft_sections.duplicate()
	if shape.mode == "cabochon":
		sections = PackedVector2Array([Vector2(-0.04, 1), Vector2(0, 1)])
		for ring in range(1, shape.dome_rings):
			var angle := (PI * 0.5) * ring / shape.dome_rings
			sections.append(Vector2(shape.dome_height * sin(angle), cos(angle)))
		sections.append(Vector2(shape.dome_height, 0.0))
	return loft(points, sections)

static func loft(points: PackedVector2Array, sections: PackedVector2Array) -> GemMesh:
	var mesh := GemMesh.new()
	if points.size() < 3 or sections.size() < 2:
		return mesh
	for i in points.size():
		var next := (i + 1) % points.size()
		if not points[i].is_finite() or points[i].distance_squared_to(points[next]) < 1.0e-14:
			return mesh
		for j in range(i + 1, points.size()):
			var j_next := (j + 1) % points.size()
			if j == next or j_next == i:
				continue
			if Geometry2D.segment_intersects_segment(points[i], points[next], points[j], points[j_next]) != null:
				return mesh
	var polygon_area := 0.0
	for i in points.size():
		polygon_area += points[i].cross(points[(i + 1) % points.size()])
	if polygon_area <= 1.0e-10:
		return mesh # CCW, simple outline required
	var cap := Geometry2D.triangulate_polygon(points)
	if cap.is_empty():
		return mesh
	var rings: Array[PackedInt32Array] = []
	var last_height := -INF
	for section in sections:
		if not section.is_finite() or section.x <= last_height or section.y < 0.0:
			return GemMesh.new()
		last_height = section.x
		var ring := PackedInt32Array()
		if section.y == 0.0:
			ring.append(mesh.vertices.size())
			mesh.vertices.append(Vector3(0, 0, section.x))
		else:
			for point in points:
				ring.append(mesh.vertices.size())
				mesh.vertices.append(Vector3(point.x * section.y, point.y * section.y, section.x))
		rings.append(ring)
	for level in rings.size() - 1:
		var lower := rings[level]
		var upper := rings[level + 1]
		if lower.size() == 1 and upper.size() == 1:
			return GemMesh.new()
		for i in points.size():
			var next := (i + 1) % points.size()
			var facet := level * points.size() + i
			if lower.size() == 1:
				mesh.add_triangle(lower[0], upper[next], upper[i], facet)
			elif upper.size() == 1:
				mesh.add_triangle(lower[i], lower[next], upper[0], facet)
			else:
				mesh.add_triangle(lower[i], lower[next], upper[next], facet)
				mesh.add_triangle(lower[i], upper[next], upper[i], facet)
	for index in cap.size() / 3:
		var a := cap[index * 3]
		var b := cap[index * 3 + 1]
		var c := cap[index * 3 + 2]
		if rings[0].size() > 1:
			mesh.add_triangle(rings[0][c], rings[0][b], rings[0][a], -1)
		if rings[-1].size() > 1:
			mesh.add_triangle(rings[-1][a], rings[-1][b], rings[-1][c], -2)
	return mesh
