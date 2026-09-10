class_name GemFractureCompiler
extends RefCounted
## A two-sided aperture field with a welded zero-opening front. Clipping in
## parameter space produces irregular contact holes and disconnected pockets
## without placing independent geometric bubbles. Both walls share a height
## field; no elastic contact pressure, recrystallization or hydraulic flow solve.
## Rough-surface aperture motivation: Drazer & Koplik (2000),
## https://arxiv.org/abs/cond-mat/0006287 . Statistics here are authored, not fitted.
var _mesh := GemMesh.new()
var _defect: GemDefect
var _profile: GemFractureProfile
var _size_mm := 1.0
var _positions := PackedVector2Array()
var _gaps := PackedFloat64Array()
var _grid_vertices := {}
var _edge_vertices := {}

static func compile(defect: GemDefect, size_mm: float) -> GemMesh:
	var compiler := GemFractureCompiler.new()
	compiler._defect = defect
	compiler._profile = defect.fracture_profile
	compiler._size_mm = size_mm
	return compiler._build()

func _build() -> GemMesh:
	if _profile == null or not _profile.validate().is_empty() or _size_mm <= 0 or not is_finite(_size_mm):
		return _mesh
	if _profile.closure_mm >= 2.0 * _defect.half_extent_mm.z:
		return _mesh # Even the maximum possible opening is closed.
	var n := _profile.resolution
	for y in range(n + 1):
		for x in range(n + 1):
			var p := Vector2((2.0 * x / n - 1) * 1.125, (2.0 * y / n - 1) * 1.125)
			_positions.append(p)
			var gap := _half_aperture(p)
			# Avoid exact nodal zeros (four-way topological ambiguity). This is
			# below geometric precision, not a visible minimum fracture opening.
			_gaps.append(-1e-12 if absf(gap) < 1e-12 else gap)
	for y in n:
		for x in n:
			var a := y * (n + 1) + x
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			# Alternating diagonals reduce directional grid bias.
			if (x + y) % 2:
				_triangle([a, b, c])
				_triangle([b, d, c])
			else:
				_triangle([a, b, d])
				_triangle([a, d, c])
	return _mesh

func _half_aperture(p: Vector2) -> float:
	var front_noise := _field(p * 1.7, _defect.seed + 31, 3)
	var radius := 1.0 - _defect.irregularity * 0.2 * (0.5 + 0.5 * front_noise)
	var front := 1.0 - p.length_squared() / (radius * radius)
	if front <= 0:
		return _defect.half_extent_mm.z * front - _profile.closure_mm * 0.5
	var physical := p * Vector2(_defect.half_extent_mm.x, _defect.half_extent_mm.y)
	var modulation := 0.5 + 0.5 * _field(physical / _profile.correlation_mm, _defect.seed + 71, 5)
	return _defect.half_extent_mm.z * sqrt(front) * lerpf(1.0, modulation, _profile.aperture_variation) - 0.5 * _profile.closure_mm

func _mid_surface(p: Vector2) -> float:
	var physical := p * Vector2(_defect.half_extent_mm.x, _defect.half_extent_mm.y)
	return _profile.roughness_mm * _field(physical / _profile.correlation_mm, _defect.seed + 113, 5)

func _triangle(vertices: Array) -> void:
	var top := PackedInt32Array()
	var bottom := PackedInt32Array()
	for index in 3:
		var a: int = vertices[index]
		var b: int = vertices[(index + 1) % 3]
		if _gaps[a] > 0:
			var pair := _vertex(a)
			top.append(pair.x)
			bottom.append(pair.y)
		if (_gaps[a] > 0) != (_gaps[b] > 0):
			var edge := _edge(a, b)
			top.append(edge)
			bottom.append(edge)
	for index in range(1, top.size() - 1):
		_mesh.add_triangle(top[0], top[index], top[index + 1], 0)
		_mesh.add_triangle(bottom[0], bottom[index + 1], bottom[index], 1)

func _vertex(index: int) -> Vector2i:
	if _grid_vertices.has(index):
		return _grid_vertices[index]
	var p := _positions[index]
	var middle := _mid_surface(p)
	var first := _mesh.vertices.size()
	_mesh.vertices.append(_transform(p, middle + _gaps[index]))
	_mesh.vertices.append(_transform(p, middle - _gaps[index]))
	var result := Vector2i(first, first + 1)
	_grid_vertices[index] = result
	return result

func _edge(a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if _edge_vertices.has(key):
		return _edge_vertices[key]
	var t := _gaps[key.x] / (_gaps[key.x] - _gaps[key.y])
	# A contour arbitrarily close to a grid node makes numerically unusable
	# sliver faces. Bound the displacement by a small fraction of one cell,
	# derived from GemMesh's minimum cross-product area in normalized units.
	# This is an explicit meshing regularization, not a physical aperture floor.
	var cell_size := 2.25 * minf(_defect.half_extent_mm.x, _defect.half_extent_mm.y) / (_profile.resolution * _size_mm)
	var margin := clampf(2.0 * sqrt(1e-9) / cell_size, 1e-5, 0.1)
	t = clampf(t, margin, 1.0 - margin)
	var p := _positions[key.x].lerp(_positions[key.y], t)
	var result := _mesh.vertices.size()
	_mesh.vertices.append(_transform(p, _mid_surface(p)))
	_edge_vertices[key] = result
	return result

func _transform(p: Vector2, z: float) -> Vector3:
	return (_defect.center_mm + _defect.orientation * Vector3(p.x * _defect.half_extent_mm.x, p.y * _defect.half_extent_mm.y, z)) / _size_mm

func _field(p: Vector2, seed_value: int, octaves: int) -> float:
	var result := 0.0
	var total := 0.0
	var amplitude := 1.0
	for octave in octaves:
		result += amplitude * _noise(p, seed_value + octave * 7919)
		total += amplitude
		amplitude *= pow(0.5, _profile.hurst)
		p = Vector2(0.8 * p.x - 0.6 * p.y, 0.6 * p.x + 0.8 * p.y) * 2.0
	return result / total

static func _noise(p: Vector2, seed_value: int) -> float:
	var cell := Vector2i(floori(p.x), floori(p.y))
	var u := p - Vector2(cell)
	u = u * u * u * (u * (u * 6.0 - Vector2.ONE * 15.0) + Vector2.ONE * 10.0)
	var a := _hash(cell, seed_value)
	var b := _hash(cell + Vector2i.RIGHT, seed_value)
	var c := _hash(cell + Vector2i.DOWN, seed_value)
	var d := _hash(cell + Vector2i.ONE, seed_value)
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

static func _hash(cell: Vector2i, seed_value: int) -> float:
	var value := (cell.x * 73856093 + cell.y * 19349663 + seed_value * 83492791) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 2246822519) & 0x7fffffff
	return float(value) / 1073741824.0 - 1.0
