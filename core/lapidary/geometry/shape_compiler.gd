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
	for face in planes.size() / 8:
		var polygon := _clip_face64(planes, face)
		var ring := PackedInt32Array()
		for vertex: Dictionary in polygon:
			var point: Array = vertex["point"]
			var index := _weld(mesh, Vector3(point[0], point[1], point[2]), cells)
			if not ring.has(index):
				ring.append(index)
		if ring.size() < 3:
			continue
		var center := Vector3.ZERO
		for index in ring:
			center += mesh.vertices[index] / ring.size()
		var center_index := mesh.vertices.size()
		mesh.vertices.append(center)
		var facet := identities[face] if identities.size() == planes.size() / 8 else face
		for edge in ring.size():
			mesh.add_triangle(center_index, ring[edge], ring[(edge + 1) % ring.size()], facet)
	return mesh

## Scalar float64 clipping retains the support planes of each edge. Shared
## corners are computed from exactly the same plane triple on both faces,
## avoiding independent float32 frame projections and proximity-based guesses.
static func _clip_face64(planes: PackedFloat32Array, face: int) -> Array[Dictionary]:
	var offset := face * 8
	var normal := Vector3(planes[offset], planes[offset + 1], planes[offset + 2])
	var tangent := normal.cross(Vector3.BACK)
	if tangent.length_squared() < 1.0e-6:
		tangent = normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var second := normal.cross(tangent).normalized()
	var n2: float = planes[offset] * planes[offset] + planes[offset + 1] * planes[offset + 1] + planes[offset + 2] * planes[offset + 2]
	var extent := 8.0
	for i in planes.size() / 8:
		extent = maxf(extent, absf(planes[i * 8 + 3]) * 8.0)
	var polygon: Array[Dictionary] = []
	for corner in 4:
		var x := -extent if corner == 0 or corner == 3 else extent
		var y := -extent if corner < 2 else extent
		var point := []
		for axis in 3:
			point.append(planes[offset + axis] * planes[offset + 3] / n2 + tangent[axis] * x + second[axis] * y)
		polygon.append({"point": point, "supports": Vector2i(-1 - ((corner + 3) % 4), -1 - corner)})
	for clip in planes.size() / 8:
		if clip == face:
			continue
		var clipped: Array[Dictionary] = []
		for edge in polygon.size():
			var a := polygon[edge]
			var b := polygon[(edge + 1) % polygon.size()]
			var da := _distance64(planes, clip, a["point"])
			var db := _distance64(planes, clip, b["point"])
			if da <= 0.0:
				clipped.append(a)
			if (da <= 0.0 and db > 0.0) or (da > 0.0 and db <= 0.0):
				var sa: Vector2i = a["supports"]
				var sb: Vector2i = b["supports"]
				var shared := sa.x if sa.x == sb.x or sa.x == sb.y else sa.y
				var point := _triple64(planes, face, shared, clip) if shared >= 0 else []
				if point.is_empty():
					for axis in 3:
						point.append(a["point"][axis] + (b["point"][axis] - a["point"][axis]) * da / (da - db))
				clipped.append({"point": point, "supports": Vector2i(shared, clip)})
		polygon = clipped
		if polygon.size() < 3:
			return []
	return polygon

static func _distance64(planes: PackedFloat32Array, plane: int, point: Array) -> float:
	var i := plane * 8
	return planes[i] * point[0] + planes[i + 1] * point[1] + planes[i + 2] * point[2] - planes[i + 3]

static func _triple64(planes: PackedFloat32Array, first: int, second: int, third: int) -> Array:
	var ids := [first, second, third]
	ids.sort()
	var a: int = ids[0] * 8
	var b: int = ids[1] * 8
	var c: int = ids[2] * 8
	var bc := _cross64(planes, b, c)
	var determinant := planes[a] * bc[0] + planes[a + 1] * bc[1] + planes[a + 2] * bc[2]
	if absf(determinant) < 1.0e-18:
		return []
	var ca := _cross64(planes, c, a)
	var ab := _cross64(planes, a, b)
	var point := []
	for axis in 3:
		point.append((planes[a + 3] * bc[axis] + planes[b + 3] * ca[axis] + planes[c + 3] * ab[axis]) / determinant)
	return point

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
