class_name GemMeshResource
extends Resource

## Defines a faceted 3D gem mesh generated from scripted cut data.

@export var cut_id: StringName = &""
@export var display_name: String = ""

var facet_vertices: Array[PackedVector3Array] = []
var facet_normals: Array[Vector3] = []
var facet_zones: PackedStringArray = PackedStringArray()
var _trace_data_cache: Dictionary = {}


func facet_count() -> int:
	return facet_vertices.size()


func add_facet(vertices: PackedVector3Array, zone: String = "") -> void:
	if vertices.size() < 3:
		return
	var oriented := PackedVector3Array(vertices)
	var normal := _compute_facet_normal(oriented)
	if normal.is_zero_approx():
		return
	var centroid := _compute_centroid(oriented)
	if normal.dot(centroid) < 0.0:
		oriented = _reverse_vertices(oriented)
		normal = -normal
	facet_vertices.append(oriented)
	facet_normals.append(normal)
	facet_zones.append(zone)
	_trace_data_cache.clear()


func create_array_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in facet_vertices.size():
		var verts := facet_vertices[i]
		if verts.size() < 3:
			continue
		var normal := facet_normals[i] if i < facet_normals.size() else _compute_facet_normal(verts)
		for j in range(1, verts.size() - 1):
			st.set_normal(normal)
			st.add_vertex(verts[0])
			st.set_normal(normal)
			st.add_vertex(verts[j])
			st.set_normal(normal)
			st.add_vertex(verts[j + 1])
	return st.commit()


func build_trace_data() -> Dictionary:
	if _trace_data_cache.has("default"):
		return _trace_data_cache["default"]
	var triangle_vertices_a: Array[Vector3] = []
	var triangle_vertices_b: Array[Vector3] = []
	var triangle_vertices_c: Array[Vector3] = []
	var triangle_normals: Array[Vector3] = []
	var triangle_bounds: Array[AABB] = []
	var triangle_centroids: Array[Vector3] = []
	var triangle_facet_indices := PackedInt32Array()
	var triangle_zones := PackedStringArray()
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	var bounding_radius := 0.0
	for facet_index in facet_vertices.size():
		var verts := facet_vertices[facet_index]
		if verts.size() < 3:
			continue
		var normal := facet_normals[facet_index] if facet_index < facet_normals.size() else _compute_facet_normal(verts)
		for vertex in verts:
			min_v.x = minf(min_v.x, vertex.x)
			min_v.y = minf(min_v.y, vertex.y)
			min_v.z = minf(min_v.z, vertex.z)
			max_v.x = maxf(max_v.x, vertex.x)
			max_v.y = maxf(max_v.y, vertex.y)
			max_v.z = maxf(max_v.z, vertex.z)
			bounding_radius = maxf(bounding_radius, vertex.length())
		for tri_index in range(1, verts.size() - 1):
			var a := verts[0]
			var b := verts[tri_index]
			var c := verts[tri_index + 1]
			triangle_vertices_a.append(a)
			triangle_vertices_b.append(b)
			triangle_vertices_c.append(c)
			triangle_normals.append(normal)
			triangle_bounds.append(_triangle_bounds(a, b, c))
			triangle_centroids.append((a + b + c) / 3.0)
			triangle_facet_indices.append(facet_index)
			triangle_zones.append(facet_zones[facet_index] if facet_index < facet_zones.size() else "")
	var bvh := _build_bvh(triangle_bounds, triangle_centroids)
	var bounds := AABB()
	if min_v.x != INF:
		bounds = AABB(min_v, max_v - min_v)
	var trace_data := {
		"triangle_vertices_a": triangle_vertices_a,
		"triangle_vertices_b": triangle_vertices_b,
		"triangle_vertices_c": triangle_vertices_c,
		"triangle_normals": triangle_normals,
		"triangle_bounds": triangle_bounds,
		"triangle_centroids": triangle_centroids,
		"triangle_facet_indices": triangle_facet_indices,
		"triangle_zones": triangle_zones,
		"bounds": bounds,
		"bounding_radius": bounding_radius,
		"bvh_triangle_indices": bvh.get("triangle_indices", []),
		"bvh_node_bounds": bvh.get("node_bounds", []),
		"bvh_node_left": bvh.get("node_left", []),
		"bvh_node_right": bvh.get("node_right", []),
		"bvh_node_start": bvh.get("node_start", []),
		"bvh_node_count": bvh.get("node_count", []),
	}
	_trace_data_cache["default"] = trace_data
	return trace_data


func trace_triangle_count() -> int:
	var trace_data := build_trace_data()
	var triangles: Array = trace_data.get("triangle_vertices_a", [])
	return triangles.size()


func compute_bounds() -> AABB:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for verts in facet_vertices:
		for vertex in verts:
			min_v.x = minf(min_v.x, vertex.x)
			min_v.y = minf(min_v.y, vertex.y)
			min_v.z = minf(min_v.z, vertex.z)
			max_v.x = maxf(max_v.x, vertex.x)
			max_v.y = maxf(max_v.y, vertex.y)
			max_v.z = maxf(max_v.z, vertex.z)
	if min_v.x == INF:
		return AABB()
	return AABB(min_v, max_v - min_v)


func compute_bounding_radius() -> float:
	var radius := 0.0
	for verts in facet_vertices:
		for vertex in verts:
			radius = maxf(radius, vertex.length())
	return radius


static func _compute_facet_normal(vertices: PackedVector3Array) -> Vector3:
	if vertices.size() < 3:
		return Vector3.ZERO
	var normal := Plane(vertices[0], vertices[1], vertices[2]).normal
	if normal.is_zero_approx():
		return Vector3.ZERO
	return normal.normalized()


static func _compute_centroid(vertices: PackedVector3Array) -> Vector3:
	var centroid := Vector3.ZERO
	for vertex in vertices:
		centroid += vertex
	return centroid / float(vertices.size())


static func _reverse_vertices(vertices: PackedVector3Array) -> PackedVector3Array:
	var reversed := PackedVector3Array()
	reversed.resize(vertices.size())
	for i in vertices.size():
		reversed[i] = vertices[vertices.size() - 1 - i]
	return reversed


static func _triangle_bounds(a: Vector3, b: Vector3, c: Vector3) -> AABB:
	var min_v := Vector3(
		minf(a.x, minf(b.x, c.x)),
		minf(a.y, minf(b.y, c.y)),
		minf(a.z, minf(b.z, c.z))
	)
	var max_v := Vector3(
		maxf(a.x, maxf(b.x, c.x)),
		maxf(a.y, maxf(b.y, c.y)),
		maxf(a.z, maxf(b.z, c.z))
	)
	return AABB(min_v, max_v - min_v)


static func _build_bvh(triangle_bounds: Array[AABB], triangle_centroids: Array[Vector3]) -> Dictionary:
	var triangle_indices: Array[int] = []
	triangle_indices.resize(triangle_bounds.size())
	for i in triangle_bounds.size():
		triangle_indices[i] = i
	var node_bounds: Array[AABB] = []
	var node_left: Array[int] = []
	var node_right: Array[int] = []
	var node_start: Array[int] = []
	var node_count: Array[int] = []
	if triangle_indices.is_empty():
		return {
			"triangle_indices": triangle_indices,
			"node_bounds": node_bounds,
			"node_left": node_left,
			"node_right": node_right,
			"node_start": node_start,
			"node_count": node_count,
		}
	_build_bvh_node(
		triangle_indices,
		0,
		triangle_indices.size(),
		triangle_bounds,
		triangle_centroids,
		node_bounds,
		node_left,
		node_right,
		node_start,
		node_count
	)
	return {
		"triangle_indices": triangle_indices,
		"node_bounds": node_bounds,
		"node_left": node_left,
		"node_right": node_right,
		"node_start": node_start,
		"node_count": node_count,
	}


static func _build_bvh_node(
	triangle_indices: Array[int],
	start: int,
	end: int,
	triangle_bounds: Array[AABB],
	triangle_centroids: Array[Vector3],
	node_bounds: Array[AABB],
	node_left: Array[int],
	node_right: Array[int],
	node_start: Array[int],
	node_count: Array[int],
) -> int:
	var count := end - start
	var bounds := _merge_bounds_for_indices(triangle_indices, start, end, triangle_bounds)
	var node_index := node_bounds.size()
	node_bounds.append(bounds)
	node_left.append(-1)
	node_right.append(-1)
	node_start.append(start)
	node_count.append(count)
	if count <= 4:
		return node_index
	var centroid_bounds := _bounds_for_centroids(triangle_indices, start, end, triangle_centroids)
	var axis := _largest_axis(centroid_bounds.size)
	if centroid_bounds.size[axis] <= 0.00001:
		return node_index
	var segment: Array[int] = triangle_indices.slice(start, end)
	segment.sort_custom(func(a: int, b: int) -> bool:
		return _axis_component(triangle_centroids[a], axis) < _axis_component(triangle_centroids[b], axis)
	)
	for i in segment.size():
		triangle_indices[start + i] = segment[i]
	var mid := start + int(floor(float(count) * 0.5))
	node_left[node_index] = _build_bvh_node(
		triangle_indices,
		start,
		mid,
		triangle_bounds,
		triangle_centroids,
		node_bounds,
		node_left,
		node_right,
		node_start,
		node_count
	)
	node_right[node_index] = _build_bvh_node(
		triangle_indices,
		mid,
		end,
		triangle_bounds,
		triangle_centroids,
		node_bounds,
		node_left,
		node_right,
		node_start,
		node_count
	)
	node_count[node_index] = 0
	return node_index


static func _merge_bounds_for_indices(
	triangle_indices: Array[int],
	start: int,
	end: int,
	triangle_bounds: Array[AABB],
) -> AABB:
	var merged := AABB()
	var initialized := false
	for i in range(start, end):
		var bounds: AABB = triangle_bounds[triangle_indices[i]]
		if not initialized:
			merged = bounds
			initialized = true
		else:
			merged = merged.merge(bounds)
	return merged


static func _bounds_for_centroids(
	triangle_indices: Array[int],
	start: int,
	end: int,
	triangle_centroids: Array[Vector3],
) -> AABB:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for i in range(start, end):
		var centroid: Vector3 = triangle_centroids[triangle_indices[i]]
		min_v.x = minf(min_v.x, centroid.x)
		min_v.y = minf(min_v.y, centroid.y)
		min_v.z = minf(min_v.z, centroid.z)
		max_v.x = maxf(max_v.x, centroid.x)
		max_v.y = maxf(max_v.y, centroid.y)
		max_v.z = maxf(max_v.z, centroid.z)
	if min_v.x == INF:
		return AABB()
	return AABB(min_v, max_v - min_v)


static func _largest_axis(size: Vector3) -> int:
	if size.y > size.x and size.y >= size.z:
		return 1
	if size.z > size.x and size.z >= size.y:
		return 2
	return 0


static func _axis_component(value: Vector3, axis: int) -> float:
	match axis:
		1:
			return value.y
		2:
			return value.z
		_:
			return value.x
