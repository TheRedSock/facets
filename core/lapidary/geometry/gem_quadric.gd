class_name GemQuadric
extends RefCounted
## Exact-form elliptical cabochon: upper ellipsoid + short elliptical girdle
## + flat base. Parameters = (x radius, y radius, dome height, base z<0).
## Floating-point intersection uses cancellation-resistant quadratic roots.
static func intersect(shape: Vector4, origin: Vector3, direction: Vector3, min_t := 0.00001) -> Dictionary:
	var closest := INF
	var surface := 0
	var scaled_o := origin / Vector3(shape.x, shape.y, shape.z)
	var scaled_d := direction / Vector3(shape.x, shape.y, shape.z)
	for t in roots(scaled_d.dot(scaled_d), 2.0 * scaled_o.dot(scaled_d), scaled_o.dot(scaled_o) - 1.0):
		if t > min_t and t < closest and origin.z + direction.z * t >= 0.0:
			closest = t
			surface = -1
	var o2 := Vector2(origin.x / shape.x, origin.y / shape.y)
	var d2 := Vector2(direction.x / shape.x, direction.y / shape.y)
	for t in roots(d2.dot(d2), 2.0 * o2.dot(d2), o2.dot(o2) - 1.0):
		var z := origin.z + direction.z * t
		if t > min_t and t < closest and z >= shape.w and z <= 0.0:
			closest = t
			surface = -2
	if absf(direction.z) > 1.0e-15:
		var t := (shape.w - origin.z) / direction.z
		var p := o2 + d2 * t
		if t > min_t and t < closest and p.length_squared() <= 1.0:
			closest = t
			surface = -3
	if surface == 0:
		return {}
	return {"t": closest, "surface": surface, "normal": normal(shape, surface, origin + direction * closest)}

static func roots(a: float, b: float, c: float) -> Array[float]:
	if absf(a) < 1.0e-20:
		return []
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return []
	var q := -0.5 * (b + (1.0 if b >= 0 else -1.0) * sqrt(discriminant))
	if absf(q) < 1.0e-30:
		return [-b / (2.0 * a)]
	var first := q / a
	var second := c / q
	return [minf(first, second), maxf(first, second)]

static func normal(shape: Vector4, surface: int, position: Vector3) -> Vector3:
	if surface == -3:
		return Vector3.FORWARD
	return Vector3(position.x / (shape.x * shape.x), position.y / (shape.y * shape.y), position.z / (shape.z * shape.z) if surface == -1 else 0.0).normalized()
