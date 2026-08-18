extends RefCounted
## Validation for compiled convex plane sets (KERNEL_CONTRACT.md).
## Pure CPU, headless-safe. The compiler calls this on every compile:
## unbounded hulls are hard failures; dead planes are EXACTLY detected (face
## polygon clipping, not sampling) so the compiler can prune them — removing
## a half-space whose face is empty provably never changes the solid.

## A hull is bounded iff plane normals positively span all directions:
## for every direction u some plane has n·u >= eps. 26 sampled directions
## (axes, edge diagonals, corner diagonals) suffice for our facet programs.
const BOUND_EPS := 0.02
## Interior margin for the face test: a face thinner than this counts as dead
## (the kernel cannot resolve it and jitter owns error at that scale anyway).
const FACE_MARGIN := 1.0e-6
const MIN_FACE_AREA := 1.0e-9
## Same-facing planes closer than this are treated as one plane during the
## face test (else each would erase the other and pruning would eat the face).
const DUP_NORMAL_COS := 0.9999995
const DUP_OFFSET := 1.0e-4
## Half-extent of the seed quad in the plane's 2D frame; hulls live in the
## unit stone space so 8 covers everything.
const SEED_EXTENT := 8.0


static func check_bounded(planes: PackedFloat32Array) -> bool:
	var count := planes.size() / 8
	if count < 4:
		return false
	for u in _support_directions():
		var best := -1.0
		for i in count:
			var dot := planes[i * 8] * u.x + planes[i * 8 + 1] * u.y + planes[i * 8 + 2] * u.z
			best = maxf(best, dot)
			if best >= BOUND_EPS:
				break
		if best < BOUND_EPS:
			return false
	return true


## Exact face check: plane i contributes a face iff clipping a large quad on
## plane i by every other half-space leaves a polygon with real area. Returns
## indices of planes with empty faces, ascending. Exactness matters: the
## compiler PRUNES these, and pruning a live plane would dent the hull.
static func find_dead_planes(planes: PackedFloat32Array) -> PackedInt32Array:
	var dead := PackedInt32Array()
	var count := planes.size() / 8
	for i in count:
		if not _face_alive(planes, count, i):
			dead.append(i)
	return dead


static func _face_alive(planes: PackedFloat32Array, count: int, i: int) -> bool:
	var n := Vector3(planes[i * 8], planes[i * 8 + 1], planes[i * 8 + 2])
	var d := planes[i * 8 + 3]
	var t1 := n.cross(Vector3(0, 0, 1))
	if t1.length_squared() < 1.0e-6:
		t1 = n.cross(Vector3(1, 0, 0))
	t1 = t1.normalized()
	var t2 := n.cross(t1)
	var p0 := n * d
	var poly := PackedVector2Array([
		Vector2(-SEED_EXTENT, -SEED_EXTENT), Vector2(SEED_EXTENT, -SEED_EXTENT),
		Vector2(SEED_EXTENT, SEED_EXTENT), Vector2(-SEED_EXTENT, SEED_EXTENT),
	])
	for j in count:
		if j == i:
			continue
		var nj := Vector3(planes[j * 8], planes[j * 8 + 1], planes[j * 8 + 2])
		var dj := planes[j * 8 + 3]
		if n.dot(nj) > DUP_NORMAL_COS and absf(d - dj) < DUP_OFFSET:
			continue	# coincident twin: treat as the same plane
		# Half-space j on plane i's frame: a*x + b*y <= c.
		var a := nj.dot(t1)
		var b := nj.dot(t2)
		var c := dj - nj.dot(p0) - FACE_MARGIN
		if Vector2(a, b).length_squared() < 1.0e-18:
			if c < 0.0:
				return false	# parallel plane fully covers this face
			continue
		poly = _clip(poly, Vector2(a, b), c)
		if poly.size() < 3:
			return false
	return _polygon_area(poly) > MIN_FACE_AREA


## Sutherland–Hodgman clip of a convex polygon by half-plane n2·p <= c.
static func _clip(poly: PackedVector2Array, n2: Vector2, c: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var m := poly.size()
	for k in m:
		var pa := poly[k]
		var pb := poly[(k + 1) % m]
		var da := n2.dot(pa) - c
		var db := n2.dot(pb) - c
		if da <= 0.0:
			out.append(pa)
			if db > 0.0:
				out.append(pa + (pb - pa) * (da / (da - db)))
		elif db <= 0.0:
			out.append(pa + (pb - pa) * (da / (da - db)))
	return out


static func _polygon_area(poly: PackedVector2Array) -> float:
	var m := poly.size()
	if m < 3:
		return 0.0
	var acc := 0.0
	for k in m:
		acc += poly[k].cross(poly[(k + 1) % m])
	return absf(acc) * 0.5


static func is_outline_convex(outline: PackedVector2Array) -> bool:
	var n := outline.size()
	if n < 3:
		return false
	for i in n:
		var a := outline[i]
		var b := outline[(i + 1) % n]
		var c := outline[(i + 2) % n]
		var e0 := (b - a)
		var e1 := (c - b)
		if e0.length() < 1.0e-9 or e1.length() < 1.0e-9:
			continue
		# CCW outline: allow collinear (0) within tolerance, reject reflex.
		if e0.normalized().cross(e1.normalized()) < -1.0e-4:
			return false
	return true


static func _support_directions() -> Array[Vector3]:
	var dirs: Array[Vector3] = []
	for x in [-1, 0, 1]:
		for y in [-1, 0, 1]:
			for z in [-1, 0, 1]:
				if x == 0 and y == 0 and z == 0:
					continue
				dirs.append(Vector3(x, y, z).normalized())
	return dirs
