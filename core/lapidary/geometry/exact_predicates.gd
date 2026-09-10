class_name GemExactPredicates
extends RefCounted
## Filtered determinant signs with exact binary64 expansion fallback. Mesh
## inputs are binary32, so products/differences stay within binary64's exponent
## range. TwoSum/TwoProduct: Priest/Shewchuk, https://www.cs.cmu.edu/~quake/robust.html
## The deliberately conservative filter is NOT a geometric distance tolerance.
const FILTER := 1.0e-12
const SPLITTER := 134217729.0

static func orient2(a: Vector3, b: Vector3, c: Vector3, x: int, y: int) -> int:
	var ax: float = float(a[x]) - c[x]
	var ay: float = float(a[y]) - c[y]
	var bx: float = float(b[x]) - c[x]
	var by: float = float(b[y]) - c[y]
	var left := ax * by
	var right := ay * bx
	var det := left - right
	if absf(det) > FILTER * (absf(left) + absf(right)):
		return signi(int(signf(det)))
	return _sign(_add(_mul(_diff(a[x], c[x]), _diff(b[y], c[y])), _neg(_mul(_diff(a[y], c[y]), _diff(b[x], c[x])))))

static func orient3(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> int:
	var ax: float = float(a.x) - d.x
	var ay: float = float(a.y) - d.y
	var az: float = float(a.z) - d.z
	var bx: float = float(b.x) - d.x
	var by: float = float(b.y) - d.y
	var bz: float = float(b.z) - d.z
	var cx: float = float(c.x) - d.x
	var cy: float = float(c.y) - d.y
	var cz: float = float(c.z) - d.z
	var terms := [ax * by * cz, ay * bz * cx, az * bx * cy, -az * by * cx, -ay * bx * cz, -ax * bz * cy]
	var det := 0.0
	var magnitude := 0.0
	for term: float in terms:
		det += term
		magnitude += absf(term)
	if absf(det) > FILTER * magnitude:
		return int(signf(det))
	# Common coordinate planes are frequent in triangulated facets.
	if (a.x == d.x and b.x == d.x and c.x == d.x) or (a.y == d.y and b.y == d.y and c.y == d.y) or (a.z == d.z and b.z == d.z and c.z == d.z):
		return 0
	var aa := [_diff(a.x, d.x), _diff(a.y, d.y), _diff(a.z, d.z)]
	var bb := [_diff(b.x, d.x), _diff(b.y, d.y), _diff(b.z, d.z)]
	var cc := [_diff(c.x, d.x), _diff(c.y, d.y), _diff(c.z, d.z)]
	var result: Array[float] = []
	for axis in 3:
		var j := (axis + 1) % 3
		var k := (axis + 2) % 3
		result = _add(result, _mul(aa[axis], _add(_mul(bb[j], cc[k]), _neg(_mul(bb[k], cc[j])))))
	return _sign(result)

static func _diff(a: float, b: float) -> Array[float]:
	return _grow([a], -b)

static func _grow(e: Array[float], b: float) -> Array[float]:
	var result: Array[float] = []
	var q := b
	for a in e:
		var total := q + a
		var bv := total - q
		var av := total - bv
		var error := (q - av) + (a - bv)
		if error != 0.0:
			result.append(error)
		q = total
	if q != 0.0 or result.is_empty():
		result.append(q)
	return result

static func _add(a: Array[float], b: Array[float]) -> Array[float]:
	var result := a
	for value in b:
		result = _grow(result, value)
	return result

static func _neg(a: Array[float]) -> Array[float]:
	var result: Array[float] = []
	for value in a:
		result.append(-value)
	return result

static func _mul(a: Array[float], b: Array[float]) -> Array[float]:
	var result: Array[float] = []
	for x in a:
		for y in b:
			var product := x * y
			var split_x := SPLITTER * x
			var x_hi := split_x - (split_x - x)
			var x_lo := x - x_hi
			var split_y := SPLITTER * y
			var y_hi := split_y - (split_y - y)
			var y_lo := y - y_hi
			var error := x_lo * y_lo - (((product - x_hi * y_hi) - x_lo * y_hi) - x_hi * y_lo)
			result = _grow(_grow(result, error), product)
	return result

static func _sign(e: Array[float]) -> int:
	for i in range(e.size() - 1, -1, -1):
		if e[i] != 0.0:
			return int(signf(e[i]))
	return 0
