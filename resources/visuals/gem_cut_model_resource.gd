class_name GemCutModelResource
extends Resource

## Canonical fully-3D faceted geometry for a gemstone cut.
##
## This is the source of truth for traced meshes and projected 2D fallback data.

@export var spec_id: StringName = &""
@export var cut_id: StringName = &""
@export var display_name: String = ""
@export var shape_category: StringName = &""
var geometry_signature: String = ""

## Orthographic framing metadata used by the gameplay rotation suite.
var orthographic_top_roll_degrees: float = 0.0
var orthographic_side_yaw_degrees: float = 0.0
var orthographic_axis_fit_scale: float = 1.0

## Normalized dimensional ratios after the compiler/normalizer pass.
var crown_height: float = 0.0
var girdle_thickness: float = 0.0
var pavilion_depth: float = 0.0

## Full 3D polygon facets with explicit topology and zone tags.
var facet_vertices: Array[PackedVector3Array] = []
var facet_normals: Array[Vector3] = []
var facet_zones: PackedStringArray = PackedStringArray()

## Shared-edge topology rebuilt from the facet polygons.
var edge_segments: Array[PackedVector3Array] = []
var edge_facet_a: PackedInt32Array = PackedInt32Array()
var edge_facet_b: PackedInt32Array = PackedInt32Array()

## Explicit projected outer footprint ring in model space.
var outer_loop: PackedVector3Array = PackedVector3Array()

## Precomputed per-facet constants used by projected rendering.
var facet_centroids: PackedVector3Array = PackedVector3Array()
var facet_jitter: PackedFloat32Array = PackedFloat32Array()
var zone_brilliance_weights: PackedFloat32Array = PackedFloat32Array()


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


func duplicate_model():
	var copy = get_script().new()
	copy.spec_id = spec_id
	copy.cut_id = cut_id
	copy.display_name = display_name
	copy.shape_category = shape_category
	copy.geometry_signature = geometry_signature
	copy.orthographic_top_roll_degrees = orthographic_top_roll_degrees
	copy.orthographic_side_yaw_degrees = orthographic_side_yaw_degrees
	copy.orthographic_axis_fit_scale = orthographic_axis_fit_scale
	copy.crown_height = crown_height
	copy.girdle_thickness = girdle_thickness
	copy.pavilion_depth = pavilion_depth
	copy.outer_loop = outer_loop.duplicate()
	for polygon in facet_vertices:
		copy.facet_vertices.append(polygon.duplicate())
	copy.facet_normals = facet_normals.duplicate()
	copy.facet_zones = facet_zones.duplicate()
	for segment in edge_segments:
		copy.edge_segments.append(segment.duplicate())
	copy.edge_facet_a = edge_facet_a.duplicate()
	copy.edge_facet_b = edge_facet_b.duplicate()
	copy.facet_centroids = facet_centroids.duplicate()
	copy.facet_jitter = facet_jitter.duplicate()
	copy.zone_brilliance_weights = zone_brilliance_weights.duplicate()
	return copy


func finalize_model() -> void:
	_recompute_facet_normals()
	_rebuild_edge_topology()
	_precompute_facet_constants()


func compute_bounds() -> AABB:
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for polygon in facet_vertices:
		for vertex in polygon:
			min_v.x = minf(min_v.x, vertex.x)
			min_v.y = minf(min_v.y, vertex.y)
			min_v.z = minf(min_v.z, vertex.z)
			max_v.x = maxf(max_v.x, vertex.x)
			max_v.y = maxf(max_v.y, vertex.y)
			max_v.z = maxf(max_v.z, vertex.z)
	for vertex in outer_loop:
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
	for polygon in facet_vertices:
		for vertex in polygon:
			radius = maxf(radius, vertex.length())
	for vertex in outer_loop:
		radius = maxf(radius, vertex.length())
	return radius


func _rebuild_edge_topology() -> void:
	edge_segments.clear()
	edge_facet_a = PackedInt32Array()
	edge_facet_b = PackedInt32Array()
	var seen := {}
	for facet_index in facet_count():
		var polygon := facet_vertices[facet_index]
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			var key := _edge_key(a, b)
			if not seen.has(key):
				seen[key] = edge_segments.size()
				edge_segments.append(PackedVector3Array([a, b]))
				edge_facet_a.append(facet_index)
				edge_facet_b.append(-1)
			else:
				var edge_index: int = seen[key]
				edge_facet_b[edge_index] = facet_index


func _recompute_facet_normals() -> void:
	facet_normals.resize(facet_count())
	for facet_index in facet_count():
		var polygon: PackedVector3Array = facet_vertices[facet_index]
		var normal := _compute_facet_normal(polygon)
		if normal.is_zero_approx():
			facet_normals[facet_index] = Vector3.ZERO
			continue
		var centroid := _compute_centroid(polygon)
		if normal.dot(centroid) < 0.0:
			polygon = _reverse_vertices(polygon)
			facet_vertices[facet_index] = polygon
			normal = -normal
		facet_normals[facet_index] = normal


func _precompute_facet_constants() -> void:
	var count := facet_count()
	facet_centroids.resize(count)
	facet_jitter.resize(count)
	zone_brilliance_weights.resize(count)
	for i in count:
		var centroid := _compute_centroid(facet_vertices[i])
		facet_centroids[i] = centroid
		var hash_val := sin(centroid.x * 127.1 + centroid.y * 311.7 + centroid.z * 181.9) * 43758.5453
		hash_val = hash_val - floorf(hash_val)
		facet_jitter[i] = (hash_val - 0.5) * 0.08
		zone_brilliance_weights[i] = _zone_brilliance_weight(
			facet_zones[i] if i < facet_zones.size() else ""
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


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ax := snappedf(a.x, 0.0001)
	var ay := snappedf(a.y, 0.0001)
	var az := snappedf(a.z, 0.0001)
	var bx := snappedf(b.x, 0.0001)
	var by := snappedf(b.y, 0.0001)
	var bz := snappedf(b.z, 0.0001)
	var a_key := "%s,%s,%s" % [ax, ay, az]
	var b_key := "%s,%s,%s" % [bx, by, bz]
	if a_key < b_key:
		return "%s-%s" % [a_key, b_key]
	return "%s-%s" % [b_key, a_key]
