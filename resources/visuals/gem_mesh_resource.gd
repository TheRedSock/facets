class_name GemMeshResource
extends Resource

## Defines a faceted 3D gem mesh generated from scripted cut data.

@export var spec_id: StringName = &""
@export var cut_id: StringName = &""
@export var display_name: String = ""
var geometry_signature: String = ""

var facet_vertices: Array[PackedVector3Array] = []
var facet_normals: Array[Vector3] = []
var facet_zones: PackedStringArray = PackedStringArray()
var _trace_data_cache: Dictionary = {}


func facet_count() -> int:
	return facet_vertices.size()


func add_facet(vertices: PackedVector3Array, zone: String = "", orient_center = null) -> void:
	if vertices.size() < 3:
		return
	var oriented := PackedVector3Array(vertices)
	var normal := _compute_facet_normal(oriented)
	if normal.is_zero_approx():
		return
	var centroid := _compute_centroid(oriented)
	# Orient normal outward from the reference center. For gem facets this is the
	# origin (default). For inclusion facets, pass the inclusion center so normals
	# point outward from the inclusion, not from the gem center.
	var orient_dir: Vector3 = centroid - orient_center if orient_center != null else centroid
	if normal.dot(orient_dir) < 0.0:
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


## Maximum dihedral angle (radians) between facet normals for edge rounding to apply.
const EDGE_ROUNDING_MAX_ANGLE := 0.50  # ~28 degrees — covers crown/girdle and pavilion/girdle junctions

## Zone-pair allow-list: smoothing only fires across these zone boundaries.
## Keeps intentional intra-zone facet junctions (pavilion-pavilion, bezel-bezel) sharp
## while softening polished gem edges at zone transitions.
const EDGE_ROUNDING_ZONE_PAIRS := {
	&"bezel,girdle": true, &"girdle,bezel": true,
	&"girdle,girdle_band": true, &"girdle_band,girdle": true,
	&"girdle_band,pavilion": true, &"pavilion,girdle_band": true,
	&"table,star": true, &"star,table": true,
	&"star,bezel": true, &"bezel,star": true,
	&"culet,pavilion": true, &"pavilion,culet": true,
}


func build_trace_data_with_rounding(edge_rounding: float) -> Dictionary:
	if edge_rounding <= 0.0:
		return build_trace_data()

	var cache_key := "rounding_" + str(edge_rounding)
	if _trace_data_cache.has(cache_key):
		return _trace_data_cache[cache_key]

	var base := build_trace_data()
	var tri_a: Array = base["triangle_vertices_a"]
	var tri_b: Array = base["triangle_vertices_b"]
	var tri_c: Array = base["triangle_vertices_c"]
	var tri_normals: Array = base["triangle_normals"]
	var tri_facet_idx: PackedInt32Array = base["triangle_facet_indices"]
	var tri_count := tri_a.size()

	if tri_count == 0:
		_trace_data_cache[cache_key] = base
		return base

	# --- Build vertex-to-facet lookup ---
	# Key: snapped vertex position string -> Array of facet indices that share that vertex
	# Inclusion-zone facets are excluded — their edges should remain sharp
	# (they represent crystalline internal structures, not polished surfaces).
	var vert_to_facets: Dictionary = {}
	for facet_index in facet_vertices.size():
		if facet_index < facet_zones.size() and facet_zones[facet_index] == "inclusion":
			continue
		var verts := facet_vertices[facet_index]
		for v in verts:
			var key := _snap_vertex_key(v)
			if not vert_to_facets.has(key):
				vert_to_facets[key] = []
			var facet_list: Array = vert_to_facets[key]
			# Avoid duplicates (a facet can share a vertex position more than once in degenerate cases)
			if facet_list.find(facet_index) == -1:
				facet_list.append(facet_index)

	# --- Precompute smoothed normal per (facet, vertex_key) pair ---
	# For each facet's vertex, blend its face normal with neighbor facets sharing that vertex.
	var smoothed_cache: Dictionary = {}  # "facet_idx,vertex_key" -> Vector3

	for facet_index in facet_vertices.size():
		if facet_index < facet_zones.size() and facet_zones[facet_index] == "inclusion":
			continue
		var face_normal: Vector3 = facet_normals[facet_index]
		var source_zone: String = facet_zones[facet_index] if facet_index < facet_zones.size() else ""
		var verts := facet_vertices[facet_index]
		for v in verts:
			var vkey := _snap_vertex_key(v)
			var cache_entry_key := str(facet_index) + "," + vkey
			if smoothed_cache.has(cache_entry_key):
				continue

			# Start with the face's own normal (weight 1.0)
			var blended := face_normal
			var sharing_facets: Array = vert_to_facets.get(vkey, [])
			for neighbor_idx in sharing_facets:
				if neighbor_idx == facet_index:
					continue
				var neighbor_zone: String = facet_zones[neighbor_idx] if neighbor_idx < facet_zones.size() else ""
				# Only smooth across allowed zone-pair boundaries.
				# If either zone is empty (legacy geometry), skip — no rounding.
				if source_zone.is_empty() or neighbor_zone.is_empty():
					continue
				if source_zone == neighbor_zone:
					continue  # same-zone edges stay sharp
				var zone_pair_key := StringName(source_zone + "," + neighbor_zone)
				if not EDGE_ROUNDING_ZONE_PAIRS.has(zone_pair_key):
					continue
				var neighbor_normal: Vector3 = facet_normals[neighbor_idx]
				var cos_angle := face_normal.dot(neighbor_normal)
				# Clamp for numerical safety
				cos_angle = clampf(cos_angle, -1.0, 1.0)
				var dihedral := acos(cos_angle)
				if dihedral < EDGE_ROUNDING_MAX_ANGLE:
					var weight := edge_rounding * (1.0 - dihedral / EDGE_ROUNDING_MAX_ANGLE)
					blended += neighbor_normal * weight

			smoothed_cache[cache_entry_key] = blended.normalized()

	# --- Pack per-vertex normals for each triangle ---
	var vertex_normals_a: Array[Vector3] = []
	var vertex_normals_b: Array[Vector3] = []
	var vertex_normals_c: Array[Vector3] = []
	vertex_normals_a.resize(tri_count)
	vertex_normals_b.resize(tri_count)
	vertex_normals_c.resize(tri_count)

	for tri_idx in tri_count:
		var facet_index: int = tri_facet_idx[tri_idx]
		var a: Vector3 = tri_a[tri_idx]
		var b: Vector3 = tri_b[tri_idx]
		var c: Vector3 = tri_c[tri_idx]

		var key_a := str(facet_index) + "," + _snap_vertex_key(a)
		var key_b := str(facet_index) + "," + _snap_vertex_key(b)
		var key_c := str(facet_index) + "," + _snap_vertex_key(c)

		var fallback: Vector3 = tri_normals[tri_idx]
		vertex_normals_a[tri_idx] = smoothed_cache.get(key_a, fallback)
		vertex_normals_b[tri_idx] = smoothed_cache.get(key_b, fallback)
		vertex_normals_c[tri_idx] = smoothed_cache.get(key_c, fallback)

	# --- Build result dict (shallow copy of base + vertex normal arrays) ---
	var result := {}
	for key in base:
		result[key] = base[key]
	result["triangle_vertex_normals_a"] = vertex_normals_a
	result["triangle_vertex_normals_b"] = vertex_normals_b
	result["triangle_vertex_normals_c"] = vertex_normals_c

	_trace_data_cache[cache_key] = result
	return result


static func _snap_vertex_key(v: Vector3) -> String:
	return "%s,%s,%s" % [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


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
