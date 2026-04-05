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


static func superellipse_point(
	radius_factor: float,
	angle: float,
	exponent: float,
	aspect_x: float = 1.0,
	aspect_y: float = 1.0,
) -> Vector2:
	var ca := cos(angle)
	var sa := sin(angle)
	var abs_ca := absf(ca)
	var abs_sa := absf(sa)
	var rr := 1.0
	if abs_ca > 0.001 or abs_sa > 0.001:
		rr = pow(pow(abs_ca, exponent) + pow(abs_sa, exponent), -1.0 / exponent)
	return CENTER + Vector2(ca * aspect_x, sa * aspect_y) * rr * GEM_RADIUS * radius_factor


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


static func kite_point(rx: float, ry: float, angle: float, shoulder: float = 0.5) -> Vector2:
	var ca := cos(angle)
	var sa := sin(angle)

	# Symmetric rhombus: closed-form polar distance (fast path).
	if absf(shoulder - 0.5) < 0.001:
		var abs_ca := absf(ca)
		var abs_sa := absf(sa)
		var denom := ry * abs_ca + rx * abs_sa
		if denom < 0.001:
			denom = 0.001
		return CENTER + Vector2(ca, sa) * (rx * ry / denom) * GEM_RADIUS

	# Asymmetric kite via ray–edge intersection.
	# Vertices: Top(0,-ry), Right(rx,sy), Bottom(0,ry), Left(-rx,sy)
	# where sy shifts the shoulder above or below center.
	var sy := ry * (2.0 * shoulder - 1.0)
	var rxry := rx * ry
	var best_t := rx + ry  # safe upper bound

	# Edge 0: Top(0,-ry) → Right(rx,sy)
	var det0 := sa * rx - ca * (sy + ry)
	if absf(det0) > 0.0001:
		var t0 := -rxry / det0
		var s0 := -ry * ca / det0
		if t0 > 0.0001 and s0 >= -0.001 and s0 <= 1.001 and t0 < best_t:
			best_t = t0

	# Edge 1: Right(rx,sy) → Bottom(0,ry)
	var det1 := -sa * rx - ca * (ry - sy)
	if absf(det1) > 0.0001:
		var t1 := -rxry / det1
		var s1 := (ca * sy - sa * rx) / det1
		if t1 > 0.0001 and s1 >= -0.001 and s1 <= 1.001 and t1 < best_t:
			best_t = t1

	# Edge 2: Bottom(0,ry) → Left(-rx,sy)
	var det2 := -sa * rx - ca * (sy - ry)
	if absf(det2) > 0.0001:
		var t2 := -rxry / det2
		var s2 := ca * ry / det2
		if t2 > 0.0001 and s2 >= -0.001 and s2 <= 1.001 and t2 < best_t:
			best_t = t2

	# Edge 3: Left(-rx,sy) → Top(0,-ry)
	var det3 := sa * rx + ca * (ry + sy)
	if absf(det3) > 0.0001:
		var t3 := -rxry / det3
		var s3 := (ca * sy + sa * rx) / det3
		if t3 > 0.0001 and s3 >= -0.001 and s3 <= 1.001 and t3 < best_t:
			best_t = t3

	return CENTER + Vector2(ca, sa) * best_t * GEM_RADIUS


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


# ===========================================================================
#  Polygon clipping (Sutherland-Hodgman)
# ===========================================================================


## Clips the subject polygon to the interior of the clip polygon.
## Returns the intersection, or an empty array if they don't overlap.
## Both polygons must be convex (or at least the clip polygon must be).
static func clip_polygon(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	var clean_subject := _sanitize_polygon(subject)
	var clean_clip := _sanitize_polygon(clip)
	if clean_subject.size() < 3 or clean_clip.size() < 3:
		return PackedVector2Array()
	var clip_area := polygon_signed_area(clean_clip)
	if absf(clip_area) < 0.000001:
		return PackedVector2Array()
	var clip_winding := 1.0 if clip_area >= 0.0 else -1.0
	var output := clean_subject
	for i in clean_clip.size():
		if output.size() < 3:
			return PackedVector2Array()
		var input := output
		output = PackedVector2Array()
		var edge_a := clean_clip[i]
		var edge_b := clean_clip[(i + 1) % clean_clip.size()]
		for j in input.size():
			var current := input[j]
			var previous := input[(j - 1 + input.size()) % input.size()]
			var curr_in := _inside_edge(current, edge_a, edge_b, clip_winding)
			var prev_in := _inside_edge(previous, edge_a, edge_b, clip_winding)
			if curr_in:
				if not prev_in:
					_append_unique_point(output, _edge_intersect(previous, current, edge_a, edge_b))
				_append_unique_point(output, current)
			elif prev_in:
				_append_unique_point(output, _edge_intersect(previous, current, edge_a, edge_b))
		output = _sanitize_polygon(output)
	if output.size() < 3 or absf(polygon_signed_area(output)) < 0.000001:
		return PackedVector2Array()
	return output


## Returns true if the point is on the interior side of the directed edge a→b.
static func _inside_edge(point: Vector2, a: Vector2, b: Vector2, winding: float) -> bool:
	var cross := (b.x - a.x) * (point.y - a.y) - (b.y - a.y) * (point.x - a.x)
	return cross * winding >= -0.00001


## Returns the intersection point of line segments a→b and c→d.
static func _edge_intersect(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> Vector2:
	var a1 := b.y - a.y
	var b1 := a.x - b.x
	var c1 := a1 * a.x + b1 * a.y
	var a2 := d.y - c.y
	var b2 := c.x - d.x
	var c2 := a2 * c.x + b2 * c.y
	var det := a1 * b2 - a2 * b1
	if absf(det) < 0.00001:
		return (a + b) * 0.5
	return Vector2((c1 * b2 - c2 * b1) / det, (a1 * c2 - a2 * c1) / det)


static func polygon_signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		var next_index := (i + 1) % points.size()
		area += points[i].x * points[next_index].y - points[next_index].x * points[i].y
	return area * 0.5


static func _sanitize_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for point in points:
		_append_unique_point(cleaned, point)
	if cleaned.size() >= 2 and cleaned[0].distance_squared_to(cleaned[cleaned.size() - 1]) <= 0.00000001:
		cleaned.remove_at(cleaned.size() - 1)
	return cleaned


static func _append_unique_point(points: PackedVector2Array, point: Vector2) -> void:
	if not points.is_empty() and points[points.size() - 1].distance_squared_to(point) <= 0.00000001:
		return
	points.append(point)
