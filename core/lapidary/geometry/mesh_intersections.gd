class_name GemMeshIntersections
extends RefCounted
## Exact triangle contact tests after BVH broad phase. Shared indexed edges and
## vertices are legal only when the intersection is precisely that simplex.
const P := preload("res://core/lapidary/geometry/exact_predicates.gd")

static func first_invalid(mesh: GemMesh) -> Vector2i:
	var bvh := GemBvh.build(mesh)
	if bvh.nodes.is_empty():
		return Vector2i(-1, -1)
	var stack: Array[Vector2i] = [Vector2i(0, 0)]
	while not stack.is_empty():
		var pair: Vector2i = stack.pop_back()
		var a: Dictionary = bvh.nodes[pair.x]
		var b: Dictionary = bvh.nodes[pair.y]
		if not _boxes_overlap(a, b):
			continue
		if pair.x == pair.y and int(a.count) == 0:
			stack.append(Vector2i(a.left, a.left))
			stack.append(Vector2i(a.left, a.right))
			stack.append(Vector2i(a.right, a.right))
		elif int(a.count) > 0 and int(b.count) > 0:
			for i in int(a.count):
				var ta := bvh.triangle_order[int(a.first) + i]
				for j in int(b.count):
					var tb := bvh.triangle_order[int(b.first) + j]
					if pair.x == pair.y and ta >= tb:
						continue
					if invalid_pair(mesh, ta, tb) if mesh.region_ids[ta] == mesh.region_ids[tb] else coincident_area(mesh, ta, tb):
						return Vector2i(ta, tb)
		elif int(a.count) == 0:
			stack.append(Vector2i(a.left, pair.y))
			stack.append(Vector2i(a.right, pair.y))
		else:
			stack.append(Vector2i(pair.x, b.left))
			stack.append(Vector2i(pair.x, b.right))
	return Vector2i(-1, -1)

static func _boxes_overlap(a: Dictionary, b: Dictionary) -> bool:
	for axis in 3:
		if a.min[axis] > b.max[axis] or b.min[axis] > a.max[axis]:
			return false
	return true

static func invalid_pair(mesh: GemMesh, ta: int, tb: int) -> bool:
	var ai := [mesh.indices[ta * 3], mesh.indices[ta * 3 + 1], mesh.indices[ta * 3 + 2]]
	var bi := [mesh.indices[tb * 3], mesh.indices[tb * 3 + 1], mesh.indices[tb * 3 + 2]]
	var a: Array[Vector3] = [mesh.vertices[ai[0]], mesh.vertices[ai[1]], mesh.vertices[ai[2]]]
	var b: Array[Vector3] = [mesh.vertices[bi[0]], mesh.vertices[bi[1]], mesh.vertices[bi[2]]]
	# Leaf boxes may contain several separated triangles.
	for axis in 3:
		if minf(a[0][axis], minf(a[1][axis], a[2][axis])) > maxf(b[0][axis], maxf(b[1][axis], b[2][axis])) or minf(b[0][axis], minf(b[1][axis], b[2][axis])) > maxf(a[0][axis], maxf(a[1][axis], a[2][axis])):
			return false
	var shared: Array[int] = []
	for index: int in ai:
		if index in bi:
			shared.append(index)
	if shared.size() == 3:
		return true
	if shared.size() == 2:
		var p := mesh.vertices[shared[0]]
		var q := mesh.vertices[shared[1]]
		var r := Vector3.ZERO
		var s := Vector3.ZERO
		for k in 3:
			if ai[k] not in shared:
				r = a[k]
			if bi[k] not in shared:
				s = b[k]
		if P.orient3(p, q, r, s) != 0:
			return false
		var axes := projection(p, q, r)
		return P.orient2(p, q, r, axes.x, axes.y) == P.orient2(p, q, s, axes.x, axes.y)
	for k in 3:
		var next := (k + 1) % 3
		if shared.is_empty() or (ai[k] != shared[0] and ai[next] != shared[0]):
			if segment_triangle(a[k], a[next], b):
				return true
		if shared.is_empty() or (bi[k] != shared[0] and bi[next] != shared[0]):
			if segment_triangle(b[k], b[next], a):
				return true
	return false

## Crossing priority regions are legal; coincident interface patches are not.
## For coplanar convex triangles, strict SAT detects positive-area overlap.
static func coincident_area(mesh: GemMesh, ta: int, tb: int) -> bool:
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for k in 3:
		a.append(mesh.vertices[mesh.indices[ta * 3 + k]])
		b.append(mesh.vertices[mesh.indices[tb * 3 + k]])
	for vertex in b:
		if P.orient3(a[0], a[1], a[2], vertex) != 0:
			return false
	var axes := projection(a[0], a[1], a[2])
	for pair in [[a,b],[b,a]]:
		var orientation := P.orient2(pair[0][0], pair[0][1], pair[0][2], axes.x, axes.y)
		for k in 3:
			var interior := false
			for vertex: Vector3 in pair[1]:
				interior = interior or P.orient2(pair[0][k], pair[0][(k+1)%3], vertex, axes.x, axes.y) == orientation
			if not interior:
				return false
	return true

static func projection(a: Vector3, b: Vector3, c: Vector3) -> Vector2i:
	for axes in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 0)]:
		if P.orient2(a, b, c, axes.x, axes.y) != 0:
			return axes
	return Vector2i(-1, -1)

static func segment_triangle(p: Vector3, q: Vector3, t: Array[Vector3]) -> bool:
	var p_side := P.orient3(t[0], t[1], t[2], p)
	var q_side := P.orient3(t[0], t[1], t[2], q)
	if p_side * q_side > 0:
		return false
	if p_side == 0 and q_side == 0:
		var axes := projection(t[0], t[1], t[2])
		if _point_in_triangle(p, t, axes) or _point_in_triangle(q, t, axes):
			return true
		for k in 3:
			if _segments2(p, q, t[k], t[(k + 1) % 3], axes):
				return true
		return false
	var signs := Vector3i(P.orient3(p, q, t[0], t[1]), P.orient3(p, q, t[1], t[2]), P.orient3(p, q, t[2], t[0]))
	return (signs.x >= 0 and signs.y >= 0 and signs.z >= 0) or (signs.x <= 0 and signs.y <= 0 and signs.z <= 0)

static func _point_in_triangle(p: Vector3, t: Array[Vector3], axes: Vector2i) -> bool:
	var signs := Vector3i(P.orient2(t[0], t[1], p, axes.x, axes.y), P.orient2(t[1], t[2], p, axes.x, axes.y), P.orient2(t[2], t[0], p, axes.x, axes.y))
	return (signs.x >= 0 and signs.y >= 0 and signs.z >= 0) or (signs.x <= 0 and signs.y <= 0 and signs.z <= 0)

static func _segments2(a: Vector3, b: Vector3, c: Vector3, d: Vector3, axes: Vector2i) -> bool:
	for axis in [axes.x, axes.y]:
		if minf(a[axis], b[axis]) > maxf(c[axis], d[axis]) or minf(c[axis], d[axis]) > maxf(a[axis], b[axis]):
			return false
	return P.orient2(a, b, c, axes.x, axes.y) * P.orient2(a, b, d, axes.x, axes.y) <= 0 and P.orient2(c, d, a, axes.x, axes.y) * P.orient2(c, d, b, axes.x, axes.y) <= 0

## Signed +X ray crossings with a half-open projected triangle convention.
## Shared projected edges are counted once, without displacing the query point.
static func contains(mesh: GemMesh, triangles: Array[int], point: Vector3) -> bool:
	var winding := 0
	for triangle in triangles:
		var a := mesh.vertices[mesh.indices[triangle * 3]]
		var b := mesh.vertices[mesh.indices[triangle * 3 + 1]]
		var c := mesh.vertices[mesh.indices[triangle * 3 + 2]]
		var area := P.orient2(a, b, c, 1, 2)
		if area == 0 or P.orient3(a, b, c, point) != area:
			continue
		if area < 0:
			var temporary := b
			b = c
			c = temporary
		if _half_open_edge(a, b, point) and _half_open_edge(b, c, point) and _half_open_edge(c, a, point):
			winding += area
	return winding != 0

static func _half_open_edge(a: Vector3, b: Vector3, p: Vector3) -> bool:
	var side := P.orient2(a, b, p, 1, 2)
	return side > 0 or (side == 0 and (b.z > a.z or (b.z == a.z and b.y < a.y)))
