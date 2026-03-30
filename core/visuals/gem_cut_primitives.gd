class_name GemCutPrimitives
extends RefCounted

## Shared math helpers for procedural gem cut generation.

const CENTER := Vector2(0.5, 0.5)
const GEM_RADIUS := 0.43
const FIT_MARGIN := 0.07

const DETAIL_LOW := 4
const DETAIL_MEDIUM := 6
const DETAIL_HIGH := 8


static func regular_angles(count: int, rotation: float = -PI * 0.5) -> Array[float]:
	var angles: Array[float] = []
	var step := TAU / float(count)
	for i in count:
		angles.append(rotation + step * float(i))
	return angles


static func half_angles(main_angles: Array[float]) -> Array[float]:
	var angles: Array[float] = []
	var count := main_angles.size()
	for i in count:
		var current := main_angles[i]
		var next := main_angles[(i + 1) % count]
		var delta := next - current
		if delta <= 0.0:
			delta += TAU
		angles.append(current + delta * 0.5)
	return angles


static func detail_sample_count(symmetry_points: int, detail: int = DETAIL_HIGH, minimum: int = 24) -> int:
	return maxi(symmetry_points * detail, minimum)


static func radial_point(radius_factor: float, angle: float) -> Vector2:
	return CENTER + Vector2(cos(angle), sin(angle)) * radius_factor * GEM_RADIUS


static func ellipse_point(rx: float, ry: float, angle: float) -> Vector2:
	return CENTER + Vector2(cos(angle) * rx, sin(angle) * ry) * GEM_RADIUS


static func superellipse_point(radius_factor: float, angle: float, exponent: float) -> Vector2:
	var ca := cos(angle)
	var sa := sin(angle)
	var abs_ca := absf(ca)
	var abs_sa := absf(sa)
	var rr := 1.0
	if abs_ca > 0.001 or abs_sa > 0.001:
		rr = pow(pow(abs_ca, exponent) + pow(abs_sa, exponent), -1.0 / exponent)
	return CENTER + Vector2(ca, sa) * rr * GEM_RADIUS * radius_factor


static func pear_point(radius_factor: float, angle: float, params: Dictionary = {}) -> Vector2:
	var vertical := sin(angle)
	var t := clampf((-vertical + 1.0) * 0.5, 0.0, 1.0)
	var shoulder_bias: float = params.get("shoulder_bias", 0.82)
	var tip_power: float = params.get("tip_power", 0.72)
	var y_stretch: float = params.get("y_stretch", 1.15)
	var shift_y: float = params.get("shift_y", 0.06)
	var shaped_t := pow(t, shoulder_bias)
	var width_f := pow(maxf(cos(shaped_t * PI * 0.5), 0.0), tip_power)
	var x := cos(angle) * width_f * radius_factor * GEM_RADIUS
	var y := sin(angle) * y_stretch * radius_factor * GEM_RADIUS
	return CENTER + Vector2(x, y + shift_y * radius_factor * GEM_RADIUS)


static func marquise_point(radius_factor: float, angle: float, params: Dictionary = {}) -> Vector2:
	var vertical := absf(sin(angle))
	var shoulder_roundness: float = params.get("shoulder_roundness", 0.88)
	var tip_power: float = params.get("tip_power", 0.74)
	var half_width: float = params.get("half_width", 0.62)
	var half_height: float = params.get("half_height", 1.18)
	var shaped_vertical := pow(vertical, shoulder_roundness)
	var width_f := pow(maxf(cos(shaped_vertical * PI * 0.5), 0.0), tip_power)
	var x := cos(angle) * width_f * half_width * radius_factor * GEM_RADIUS
	var y := sin(angle) * half_height * radius_factor * GEM_RADIUS
	return CENTER + Vector2(x, y)


static func heart_point(radius_factor: float, angle: float, params: Dictionary = {}) -> Vector2:
	var t := angle + PI
	var raw_x := 16.0 * pow(sin(t), 3.0)
	var raw_y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
	var width_scale: float = params.get("width_scale", 0.92)
	var height_scale: float = params.get("height_scale", 1.02)
	var normalized := Vector2(raw_x / 18.0, -raw_y / 17.0)
	normalized.x *= width_scale
	normalized.y *= height_scale
	return CENTER + normalized * radius_factor * GEM_RADIUS


static func sample_points(angles: Array[float], sampler: Callable) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for angle in angles:
		points.append(sampler.call(angle))
	return points


static func sample_closed_curve(sample_count: int, sampler: Callable, rotation: float = -PI * 0.5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(sample_count)
	for i in sample_count:
		var angle := rotation + TAU * float(i) / float(sample_count)
		pts[i] = sampler.call(angle)
	return pts


static func quadratic_bezier_point(start: Vector2, control: Vector2, end: Vector2, t: float) -> Vector2:
	var inv_t := 1.0 - t
	return inv_t * inv_t * start + 2.0 * inv_t * t * control + t * t * end


static func sample_quadratic_bezier(
	start: Vector2,
	control: Vector2,
	end: Vector2,
	segments: int,
	include_last: bool = true,
) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var point_count := segments + 1 if include_last else segments
	for i in point_count:
		var t := float(i) / float(segments)
		pts.append(quadratic_bezier_point(start, control, end, t))
	return pts


static func sample_line_segment(
	start: Vector2,
	finish: Vector2,
	segments: int,
	include_last: bool = true,
) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var point_count := segments + 1 if include_last else segments
	for i in point_count:
		pts.append(start.lerp(finish, float(i) / float(segments)))
	return pts


static func polygon_points(side_count: int, radius_factor: float = 1.0, rotation: float = -PI * 0.5) -> Array[Vector2]:
	return sample_points(
		regular_angles(side_count, rotation),
		func(angle: float) -> Vector2:
			return radial_point(radius_factor, angle)
	)


static func alternating_ring_points(
	point_count: int,
	outer_radius: float,
	inner_radius: float,
	rotation: float = -PI * 0.5,
) -> Array[Vector2]:
	var angles := regular_angles(point_count, rotation)
	var points: Array[Vector2] = []
	for i in point_count:
		var radius := outer_radius if i % 2 == 0 else inner_radius
		points.append(radial_point(radius, angles[i] + TAU / float(point_count) * 0.5))
	return points


static func diamond_points(x_radius: float, y_radius: float) -> Array[Vector2]:
	return [
		CENTER + Vector2(0.0, -y_radius * GEM_RADIUS),
		CENTER + Vector2(x_radius * GEM_RADIUS, 0.0),
		CENTER + Vector2(0.0, y_radius * GEM_RADIUS),
		CENTER + Vector2(-x_radius * GEM_RADIUS, 0.0),
	]


static func rect_points(half_width: float, half_height: float) -> Array[Vector2]:
	return [
		CENTER + Vector2(-half_width, -half_height),
		CENTER + Vector2(half_width, -half_height),
		CENTER + Vector2(half_width, half_height),
		CENTER + Vector2(-half_width, half_height),
	]


static func scale_points(points: Array[Vector2], scale_x: float, scale_y: float = -1.0, origin: Vector2 = CENTER) -> Array[Vector2]:
	var sy := scale_y if scale_y >= 0.0 else scale_x
	var scaled: Array[Vector2] = []
	for point in points:
		var offset := point - origin
		scaled.append(origin + Vector2(offset.x * scale_x, offset.y * sy))
	return scaled


static func chamfered_rect_points(half_width: float, half_height: float, chamfer_ratio: float) -> Array[Vector2]:
	var chamfer := minf(half_width, half_height) * chamfer_ratio
	return [
		CENTER + Vector2(-half_width + chamfer, -half_height),
		CENTER + Vector2(half_width - chamfer, -half_height),
		CENTER + Vector2(half_width, -half_height + chamfer),
		CENTER + Vector2(half_width, half_height - chamfer),
		CENTER + Vector2(half_width - chamfer, half_height),
		CENTER + Vector2(-half_width + chamfer, half_height),
		CENTER + Vector2(-half_width, half_height - chamfer),
		CENTER + Vector2(-half_width, -half_height + chamfer),
	]


static func tapered_rect_points(
	top_half_width: float,
	bottom_half_width: float,
	half_height: float,
) -> Array[Vector2]:
	return [
		CENTER + Vector2(-top_half_width, -half_height),
		CENTER + Vector2(top_half_width, -half_height),
		CENTER + Vector2(bottom_half_width, half_height),
		CENTER + Vector2(-bottom_half_width, half_height),
	]


static func point_on_segment(start: Vector2, finish: Vector2, t: float) -> Vector2:
	return start.lerp(finish, t)


static func circle_outline(sample_count: int) -> PackedVector2Array:
	return sample_closed_curve(
		sample_count,
		func(angle: float) -> Vector2:
			return radial_point(1.0, angle)
	)


static func centroid_pva(vertices: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for vertex in vertices:
		sum += vertex
	return sum / float(vertices.size())


static func centroid(points: Array[Vector2]) -> Vector2:
	var sum := Vector2.ZERO
	for point in points:
		sum += point
	return sum / float(points.size())


static func normal_for(centroid_point: Vector2, tilt_deg: float) -> Vector3:
	if tilt_deg < 0.01:
		return Vector3(0.0, 0.0, 1.0)
	var radial := centroid_point - CENTER
	if radial.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	radial = radial.normalized()
	var tilt := deg_to_rad(tilt_deg)
	return Vector3(radial.x * sin(tilt), radial.y * sin(tilt), cos(tilt)).normalized()


static func pva(points: Array) -> PackedVector2Array:
	var packed := PackedVector2Array()
	packed.resize(points.size())
	for i in points.size():
		packed[i] = points[i]
	return packed
