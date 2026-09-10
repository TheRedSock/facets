class_name GemBvh
extends RefCounted
## Deterministic balanced BVH over procedural triangles. Packing is independent
## of Godot rendering meshes; the GPU consumes these buffers directly.
## Ray/triangle intersection uses ray-aligned shear and edge functions
## (PBRT4, Triangle Meshes), including shared edges rather than culling them.
var mesh: GemMesh
var nodes: Array[Dictionary] = []
var triangle_order := PackedInt32Array()
const LEAF_SIZE := 4

static func build(source: GemMesh) -> GemBvh:
	var bvh := GemBvh.new()
	bvh.mesh = source
	var triangles: Array[int] = []
	for index in source.triangle_count():
		triangles.append(index)
	if not triangles.is_empty():
		bvh._build_node(triangles)
	return bvh

func _build_node(triangles: Array[int]) -> int:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var centroid_min := minimum
	var centroid_max := maximum
	for triangle in triangles:
		var centroid := Vector3.ZERO
		for corner in 3:
			var vertex := mesh.vertices[mesh.indices[triangle * 3 + corner]]
			minimum = minimum.min(vertex)
			maximum = maximum.max(vertex)
			centroid += vertex / 3.0
		centroid_min = centroid_min.min(centroid)
		centroid_max = centroid_max.max(centroid)
	var index := nodes.size()
	nodes.append({"min": minimum, "max": maximum, "left": -1, "right": -1, "first": 0, "count": 0})
	if triangles.size() <= LEAF_SIZE:
		nodes[index]["first"] = triangle_order.size()
		nodes[index]["count"] = triangles.size()
		triangle_order.append_array(PackedInt32Array(triangles))
		return index
	var axis := (centroid_max - centroid_min).max_axis_index()
	triangles.sort_custom(func(a: int, b: int) -> bool:
		var ca := _centroid(a)[axis]
		var cb := _centroid(b)[axis]
		return ca < cb if ca != cb else a < b)
	var middle := triangles.size() / 2
	nodes[index]["left"] = _build_node(triangles.slice(0, middle))
	nodes[index]["right"] = _build_node(triangles.slice(middle))
	return index

func _centroid(triangle: int) -> Vector3:
	return (mesh.vertices[mesh.indices[triangle * 3]] + mesh.vertices[mesh.indices[triangle * 3 + 1]] + mesh.vertices[mesh.indices[triangle * 3 + 2]]) / 3.0

func intersect(origin: Vector3, direction: Vector3, min_t := 1.0e-6, max_t := INF) -> Dictionary:
	if nodes.is_empty() or direction.length_squared() < 1.0e-20:
		return {}
	var stack: Array[int] = [0]
	var nearest := max_t
	var hit := -1
	while not stack.is_empty():
		var node: Dictionary = nodes[stack.pop_back()]
		if not _box_hit(node, origin, direction, min_t, nearest):
			continue
		if int(node["count"]) == 0:
			stack.append(node["left"])
			stack.append(node["right"])
			continue
		for offset in int(node["count"]):
			var triangle := triangle_order[int(node["first"]) + offset]
			var t := triangle_hit(mesh, triangle, origin, direction)
			if t > min_t and t < nearest:
				nearest = t
				hit = triangle
	if hit < 0:
		return {}
	var a := mesh.vertices[mesh.indices[hit * 3]]
	var b := mesh.vertices[mesh.indices[hit * 3 + 1]]
	var c := mesh.vertices[mesh.indices[hit * 3 + 2]]
	return {"t": nearest, "triangle": hit, "facet": mesh.facet_ids[hit], "region": mesh.region_ids[hit], "normal": (b - a).cross(c - a).normalized()}

static func _box_hit(node: Dictionary, origin: Vector3, direction: Vector3, min_t: float, max_t: float) -> bool:
	var lo := min_t
	var hi := max_t
	for axis in 3:
		if absf(direction[axis]) < 1.0e-15:
			if origin[axis] < node["min"][axis] or origin[axis] > node["max"][axis]:
				return false
			continue
		var a: float = (node["min"][axis] - origin[axis]) / direction[axis]
		var b: float = (node["max"][axis] - origin[axis]) / direction[axis]
		lo = maxf(lo, minf(a, b))
		hi = minf(hi, maxf(a, b))
		if lo > hi:
			return false
	return true

static func triangle_hit(source: GemMesh, triangle: int, origin: Vector3, direction: Vector3) -> float:
	var kz := direction.abs().max_axis_index()
	if absf(direction[kz]) < 1.0e-20:
		return INF
	var kx := (kz + 1) % 3
	var ky := (kx + 1) % 3
	if direction[kz] < 0.0:
		var swap := kx
		kx = ky
		ky = swap
	var sx := -direction[kx] / direction[kz]
	var sy := -direction[ky] / direction[kz]
	var a := source.vertices[source.indices[triangle * 3]] - origin
	var b := source.vertices[source.indices[triangle * 3 + 1]] - origin
	var c := source.vertices[source.indices[triangle * 3 + 2]] - origin
	var pa := Vector2(a[kx] + sx * a[kz], a[ky] + sy * a[kz])
	var pb := Vector2(b[kx] + sx * b[kz], b[ky] + sy * b[kz])
	var pc := Vector2(c[kx] + sx * c[kz], c[ky] + sy * c[kz])
	var ea := pb.cross(pc)
	var eb := pc.cross(pa)
	var ec := pa.cross(pb)
	if (ea < 0 or eb < 0 or ec < 0) and (ea > 0 or eb > 0 or ec > 0):
		return INF
	var determinant := ea + eb + ec
	if determinant == 0.0:
		return INF
	return (ea * a[kz] + eb * b[kz] + ec * c[kz]) / (direction[kz] * determinant)

## Node: vec4 bounds_min, vec4 bounds_max, ivec4 left/right/first/count (48B).
func pack_nodes(node_offset := 0, triangle_offset := 0) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	for node in nodes:
		for key in ["min", "max"]:
			var value: Vector3 = node[key]
			for component in [value.x, value.y, value.z, 0.0]:
				buffer.put_float(component)
		buffer.put_32(int(node["left"]) + node_offset if int(node["left"]) >= 0 else -1)
		buffer.put_32(int(node["right"]) + node_offset if int(node["right"]) >= 0 else -1)
		buffer.put_32(int(node["first"]) + triangle_offset)
		buffer.put_32(node["count"])
	return buffer.data_array

## Triangle: three vec4 vertices, ivec4 facet/reserved/reserved/region (64B).
func pack_triangles() -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	for triangle in triangle_order:
		for corner in 3:
			var value := mesh.vertices[mesh.indices[triangle * 3 + corner]]
			for component in [value.x, value.y, value.z, 0.0]:
				buffer.put_float(component)
		for value in [mesh.facet_ids[triangle], 0, 0, mesh.region_ids[triangle]]:
			buffer.put_32(value)
	return buffer.data_array
