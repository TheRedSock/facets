class_name GemPavilionBuilder
extends RefCounted

## Unified pavilion construction for all crown families.
##
## Takes a crown boundary with sector annotations and solver-resolved
## parameters, and appends girdle wall + pavilion + culet facets to the model.
##
## This replaces the former family-specific pavilion builders:
##   _append_interleaved_pavilion, _append_outline_pavilion,
##   _append_outline_single_step_pavilion, _append_outline_mirror_crown_pavilion.

const GemCutPrimitivesScript = preload("res://core/visuals/gem_cut_primitives.gd")
const GIRDLE_WALL_ZONE := "girdle_band"


## Build the complete pavilion (girdle wall + pavilion facets + culet) and
## append all facets to the model.
##
## boundary_info: Dictionary with:
##   "boundary"     : Array[Vector2]  — full girdle boundary loop
##   "main_indices" : Array[int]      — indices of main sector vertices
##   "half_indices" : Array[int]      — indices of half/secondary vertices
##
## params: Dictionary from GemPavilionSolver.resolve(), containing:
##   pavilion_depth, girdle_thickness, upper_depth_ratio, lower_depth_ratio,
##   upper_scale, lower_scale, rotation_fraction, sector_count,
##   culet_style, culet_flat_size, culet_flat_sides
static func build(model, boundary_info: Dictionary, params: Dictionary) -> void:
	var boundary: Array[Vector2] = boundary_info.get("boundary", [])
	if boundary.size() < 3:
		return

	var pavilion_depth: float = params.get("pavilion_depth", 0.40)
	var girdle_thickness: float = params.get("girdle_thickness", 0.012)
	var upper_depth_ratio: float = params.get("upper_depth_ratio", 0.48)
	var lower_depth_ratio: float = params.get("lower_depth_ratio", 0.82)
	var base_upper_scale: float = params.get("upper_scale", 0.52)
	var base_lower_scale: float = params.get("lower_scale", 0.20)
	var rotation_fraction: float = params.get("rotation_fraction", 0.0)
	var sector_count: int = params.get("sector_count", 0)
	var culet_style: String = params.get("culet_style", "point")
	var culet_flat_size: float = params.get("culet_flat_size", 0.06)
	var culet_flat_sides: int = params.get("culet_flat_sides", 8)

	var rotation_angle := 0.0
	if sector_count > 0 and not is_zero_approx(rotation_fraction):
		rotation_angle = TAU / float(sector_count) * rotation_fraction

	var upper_z := -girdle_thickness - pavilion_depth * upper_depth_ratio
	var lower_z := -girdle_thickness - pavilion_depth * lower_depth_ratio
	var culet_z := -girdle_thickness - pavilion_depth

	# --- Build rings ---
	var boundary_packed := PackedVector2Array(boundary)
	var girdle_lower_ring: Array[Vector3] = []
	var upper_ring: Array[Vector3] = []
	var lower_ring: Array[Vector3] = []

	for index in boundary.size():
		var point := boundary[index]
		var sharpness := _loop_vertex_sharpness(boundary_packed, index)
		var upper_scale := clampf(base_upper_scale - sharpness * 0.04, 0.16, 0.96)
		var lower_scale := clampf(base_lower_scale - sharpness * 0.06, 0.10, upper_scale - 0.04)

		girdle_lower_ring.append(_p3(point, -girdle_thickness))
		upper_ring.append(_project_pavilion_point(point, upper_scale, upper_z, rotation_angle))
		lower_ring.append(_project_pavilion_point(point, lower_scale, lower_z, rotation_angle))

	var ring_count := boundary.size()

	# --- Girdle wall ---
	for i in ring_count:
		var next := (i + 1) % ring_count
		model.add_facet(PackedVector3Array([
			_p3(boundary[i], 0.0),
			_p3(boundary[next], 0.0),
			_p3(boundary[next], -girdle_thickness),
			_p3(boundary[i], -girdle_thickness),
		]), GIRDLE_WALL_ZONE)

	# --- Cusp merging (for pear, marquise, heart tips) ---
	var merged_lower: Array[Vector3] = []
	var lower_map: Array[int] = []
	_merge_cusp_points(lower_ring, merged_lower, lower_map)

	# --- Culet geometry ---
	if culet_style == "flat":
		_build_flat_culet_pavilion(
			model, girdle_lower_ring, upper_ring, merged_lower, lower_map,
			ring_count, culet_z, culet_flat_size, culet_flat_sides)
	else:
		_build_point_culet_pavilion(
			model, girdle_lower_ring, upper_ring, merged_lower, lower_map,
			ring_count, culet_z)


## Build pavilion with a point culet (standard modern cut).
static func _build_point_culet_pavilion(
	model,
	girdle_lower_ring: Array[Vector3],
	upper_ring: Array[Vector3],
	merged_lower: Array[Vector3],
	lower_map: Array[int],
	ring_count: int,
	culet_z: float,
) -> void:
	var culet := Vector3(0.0, 0.0, culet_z)

	for i in ring_count:
		var next := (i + 1) % ring_count

		# Upper pavilion: girdle_lower -> upper ring
		model.add_facet(PackedVector3Array([
			girdle_lower_ring[i],
			girdle_lower_ring[next],
			upper_ring[next],
			upper_ring[i],
		]), "pavilion")

		# Lower pavilion + culet
		var mi := lower_map[i]
		var mn := lower_map[next]
		if mi != mn:
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next],
				merged_lower[mn],
				merged_lower[mi],
			]), "pavilion")
			model.add_facet(PackedVector3Array([
				merged_lower[mi],
				culet,
				merged_lower[mn],
			]), "culet")
		else:
			# Converging segment at cusp: collapse to triangle, skip culet.
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next],
				merged_lower[mi],
			]), "pavilion")


## Build pavilion with a flat culet (Old European, antique styles).
##
## The pavilion is built identically to a point culet, but the tip is
## truncated by a horizontal plane, producing an N-sided flat face.
## culet_flat_size controls the truncation ratio:
##   0.0 = infinitesimal (near-point), 1.0 = truncation at the lower ring.
## culet_flat_sides controls how many sides the flat polygon has.
##   When it matches the merged lower ring count, truncation is exact.
##   Otherwise, culet vertices are interpolated by angle.
##
## Geometry: the culet ring vertices lie ON the pavilion's conical surface
## (lines from lower ring to the virtual culet point), so no protrusion.
static func _build_flat_culet_pavilion(
	model,
	girdle_lower_ring: Array[Vector3],
	upper_ring: Array[Vector3],
	merged_lower: Array[Vector3],
	lower_map: Array[int],
	ring_count: int,
	culet_z: float,
	culet_flat_size: float,
	culet_flat_sides: int,
) -> void:
	var culet_sides := maxi(culet_flat_sides, 3)
	var truncation := clampf(culet_flat_size, 0.02, 0.95)

	# The virtual point culet (where the pavilion would converge without truncation).
	var point_culet := Vector3(0.0, 0.0, culet_z)

	# Generate culet ring by truncating the pavilion cone.
	# Each culet vertex lies on the line from a lower ring vertex to the
	# virtual culet point, at position controlled by truncation ratio.
	# truncation=0 → at the point, truncation=1 → at the lower ring.
	var culet_ring: Array[Vector3] = []

	if culet_sides == merged_lower.size():
		# Exact match: one culet vertex per lower ring vertex.
		for v in merged_lower:
			culet_ring.append(v.lerp(point_culet, 1.0 - truncation))
	else:
		# Different count: generate N evenly-spaced culet vertices by angle,
		# each interpolated from the pavilion surface at that angle.
		var lower_angles := PackedFloat32Array()
		for v in merged_lower:
			lower_angles.append(atan2(v.y, v.x))

		for i in culet_sides:
			var target_angle := -PI * 0.5 + TAU * float(i) / float(culet_sides)
			# Find the two lower ring vertices bracketing this angle and interpolate.
			var surface_point := _interpolate_ring_at_angle(
				merged_lower, lower_angles, target_angle)
			culet_ring.append(surface_point.lerp(point_culet, 1.0 - truncation))

	# Precompute culet vertex angles for lower→culet mapping.
	var culet_angles := PackedFloat32Array()
	for v in culet_ring:
		culet_angles.append(atan2(v.y, v.x))

	# Map each merged lower ring vertex to its nearest culet polygon vertex.
	var lower_to_culet: Array[int] = []
	for v in merged_lower:
		var v_angle := atan2(v.y, v.x)
		var best_ci := 0
		var best_dist := INF
		for ci in culet_sides:
			var d := absf(_angle_distance(v_angle, culet_angles[ci]))
			if d < best_dist:
				best_dist = d
				best_ci = ci
		lower_to_culet.append(best_ci)

	# Upper pavilion facets (girdle_lower -> upper ring).
	for i in ring_count:
		var next := (i + 1) % ring_count
		model.add_facet(PackedVector3Array([
			girdle_lower_ring[i],
			girdle_lower_ring[next],
			upper_ring[next],
			upper_ring[i],
		]), "pavilion")

	# Middle pavilion facets (upper ring -> lower/merged ring).
	for i in ring_count:
		var next := (i + 1) % ring_count
		var mi := lower_map[i]
		var mn := lower_map[next]
		if mi != mn:
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next],
				merged_lower[mn],
				merged_lower[mi],
			]), "pavilion")
		else:
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next],
				merged_lower[mi],
			]), "pavilion")

	# Lower pavilion facets: connect merged lower ring to culet ring.
	var ml_count := merged_lower.size()
	for i in ml_count:
		var next := (i + 1) % ml_count
		var ci := lower_to_culet[i]
		var cn := lower_to_culet[next]
		if ci == cn:
			# Both lower points map to same culet vertex: triangle.
			model.add_facet(PackedVector3Array([
				merged_lower[i],
				merged_lower[next],
				culet_ring[ci],
			]), "pavilion")
		else:
			# Lower points map to different culet vertices: quad.
			model.add_facet(PackedVector3Array([
				merged_lower[i],
				merged_lower[next],
				culet_ring[cn],
				culet_ring[ci],
			]), "pavilion")

	# Fill any culet polygon edges not covered by lower→culet quads.
	var culet_edge_covered: Array[bool] = []
	culet_edge_covered.resize(culet_sides)
	for i in culet_sides:
		culet_edge_covered[i] = false
	for i in ml_count:
		var next := (i + 1) % ml_count
		var ci := lower_to_culet[i]
		var cn := lower_to_culet[next]
		if ci != cn:
			var cur := ci
			while cur != cn:
				culet_edge_covered[cur] = true
				cur = (cur + 1) % culet_sides

	for ci in culet_sides:
		if culet_edge_covered[ci]:
			continue
		var cn := (ci + 1) % culet_sides
		# Find nearest lower vertex for this uncovered culet edge.
		var best_li := 0
		var best_dist := INF
		var mid_angle := (culet_angles[ci] + culet_angles[cn]) * 0.5
		for li in ml_count:
			var la := atan2(merged_lower[li].y, merged_lower[li].x)
			var d := absf(_angle_distance(la, mid_angle))
			if d < best_dist:
				best_dist = d
				best_li = li
		model.add_facet(PackedVector3Array([
			culet_ring[ci],
			merged_lower[best_li],
			culet_ring[cn],
		]), "pavilion")

	# Culet face (flat polygon, wound for outward-facing normal = downward).
	var culet_face := PackedVector3Array()
	for i in range(culet_ring.size() - 1, -1, -1):
		culet_face.append(culet_ring[i])
	model.add_facet(culet_face, "culet")


## Merge lower-ring points that converge at shape cusps (e.g. pear tip)
## to avoid degenerate culet triangles and sliver pavilion quads.
static func _merge_cusp_points(
	lower_ring: Array[Vector3],
	out_merged: Array[Vector3],
	out_map: Array[int],
) -> void:
	var ring_count := lower_ring.size()
	out_map.resize(ring_count)

	if ring_count == 0:
		return

	# Compute median segment distance for threshold.
	var seg_dists: Array[float] = []
	for i in ring_count:
		seg_dists.append(lower_ring[i].distance_to(lower_ring[(i + 1) % ring_count]))
	seg_dists.sort()
	@warning_ignore("INTEGER_DIVISION")
	var median_dist := seg_dists[seg_dists.size() / 2] if not seg_dists.is_empty() else 0.0
	var merge_threshold := median_dist * 0.2

	out_merged.append(lower_ring[0])
	out_map[0] = 0
	for i in range(1, ring_count):
		if lower_ring[i].distance_to(out_merged.back()) > merge_threshold:
			out_merged.append(lower_ring[i])
		out_map[i] = out_merged.size() - 1

	# Wrap-around: merge trailing points close to the first merged point.
	while out_merged.size() > 1 and out_merged.back().distance_to(out_merged[0]) <= merge_threshold:
		var last_idx := out_merged.size() - 1
		out_merged[0] = (out_merged[0] + out_merged[last_idx]) * 0.5
		out_merged.resize(last_idx)
		for i in ring_count:
			if out_map[i] >= last_idx:
				out_map[i] = 0


## Compute vertex sharpness (turning angle) for pavilion scale adjustment.
## Returns 0.0 for smooth vertices, approaching 1.0 for sharp cusps.
static func _loop_vertex_sharpness(loop: PackedVector2Array, index: int) -> float:
	if loop.size() < 3:
		return 0.0
	var prev_index := (index - 1 + loop.size()) % loop.size()
	var next_index := (index + 1) % loop.size()
	var incoming := (loop[index] - loop[prev_index]).normalized()
	var outgoing := (loop[next_index] - loop[index]).normalized()
	if incoming.is_zero_approx() or outgoing.is_zero_approx():
		return 0.0
	var turn := clampf((1.0 - incoming.dot(outgoing)) * 0.5, 0.0, 1.0)
	return pow(turn, 0.7)


## Project a 2D boundary point inward toward center, with optional rotation.
static func _project_pavilion_point(
	point: Vector2,
	scale_factor: float,
	z: float,
	rotation_angle: float,
) -> Vector3:
	var delta := point - GemCutPrimitivesScript.CENTER
	var scaled := delta * scale_factor
	var cos_r := cos(rotation_angle)
	var sin_r := sin(rotation_angle)
	var rotated := Vector2(
		scaled.x * cos_r - scaled.y * sin_r,
		scaled.x * sin_r + scaled.y * cos_r
	)
	return _p3(GemCutPrimitivesScript.CENTER + rotated, z)


## Signed angular distance from angle a to angle b (positive = CCW).
static func _angle_distance(a: float, b: float) -> float:
	var d := fmod(b - a + 3.0 * PI, TAU) - PI
	return absf(d)


## Interpolate a position on a 3D ring at a target angle.
## Finds the two ring vertices bracketing the angle and lerps between them.
static func _interpolate_ring_at_angle(
	ring: Array[Vector3],
	ring_angles: PackedFloat32Array,
	target_angle: float,
) -> Vector3:
	var count := ring.size()
	if count == 0:
		return Vector3.ZERO
	if count == 1:
		return ring[0]

	# Find the segment that brackets target_angle.
	var best_i := 0
	var best_dist := INF
	for i in count:
		var d := absf(_angle_distance(target_angle, ring_angles[i]))
		if d < best_dist:
			best_dist = d
			best_i = i

	# Check the two adjacent segments to find which one brackets the target.
	var prev_i := (best_i - 1 + count) % count
	var next_i := (best_i + 1) % count
	var da_prev := _angle_distance(ring_angles[prev_i], target_angle)
	var da_next := _angle_distance(ring_angles[best_i], target_angle)
	var da_span := _angle_distance(ring_angles[prev_i], ring_angles[best_i])

	# Use the segment [prev_i, best_i] or [best_i, next_i] depending on
	# which side of best_i the target falls.
	var seg_a: int
	var seg_b: int
	if da_prev < da_span + 0.001:
		seg_a = prev_i
		seg_b = best_i
	else:
		seg_a = best_i
		seg_b = next_i

	var span := _angle_distance(ring_angles[seg_a], ring_angles[seg_b])
	if span < 0.0001:
		return ring[seg_a]
	var t := _angle_distance(ring_angles[seg_a], target_angle) / span
	t = clampf(t, 0.0, 1.0)
	return ring[seg_a].lerp(ring[seg_b], t)


## Convert 2D unit-space point to 3D model space.
static func _p3(point: Vector2, z: float) -> Vector3:
	return Vector3(point.x - 0.5, 0.5 - point.y, z)
