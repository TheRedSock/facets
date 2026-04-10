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
## The pavilion tip is truncated with an N-sided polygon.
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
	# Generate culet polygon vertices.
	var culet_sides := maxi(culet_flat_sides, 3)
	var culet_radius := GemCutPrimitivesScript.GEM_RADIUS * culet_flat_size
	var culet_ring: Array[Vector3] = []
	for i in culet_sides:
		var angle := -PI * 0.5 + TAU * float(i) / float(culet_sides)
		var x := culet_radius * cos(angle)
		var y := culet_radius * sin(angle)
		culet_ring.append(Vector3(x, y, culet_z))

	# Upper pavilion facets (girdle_lower -> upper ring)
	for i in ring_count:
		var next := (i + 1) % ring_count
		model.add_facet(PackedVector3Array([
			girdle_lower_ring[i],
			girdle_lower_ring[next],
			upper_ring[next],
			upper_ring[i],
		]), "pavilion")

	# Lower pavilion facets (upper ring -> lower ring)
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

	# Connect lower ring to culet polygon.
	# Map each merged_lower vertex to the nearest culet polygon vertex,
	# then stitch quads/triangles between the two rings.
	_stitch_to_culet_ring(model, merged_lower, culet_ring)

	# Culet face (flat polygon, wound for outward-facing normal = downward).
	var culet_face := PackedVector3Array()
	for i in range(culet_ring.size() - 1, -1, -1):
		culet_face.append(culet_ring[i])
	model.add_facet(culet_face, "culet")


## Stitch the merged lower ring to the culet polygon ring.
## Uses angle-based mapping: each lower vertex maps to the culet segment
## it falls within, producing quads and triangles as needed.
static func _stitch_to_culet_ring(
	model,
	lower_ring: Array[Vector3],
	culet_ring: Array[Vector3],
) -> void:
	if lower_ring.is_empty() or culet_ring.is_empty():
		return

	var lower_count := lower_ring.size()
	var culet_count := culet_ring.size()

	# Compute angles for both rings relative to the XY center (0,0).
	var lower_angles := PackedFloat32Array()
	for v in lower_ring:
		lower_angles.append(atan2(v.y, v.x))
	var culet_angles := PackedFloat32Array()
	for v in culet_ring:
		culet_angles.append(atan2(v.y, v.x))

	# For each lower edge, find the culet vertices that fall within it,
	# and for each culet edge, find the lower vertices that fall within it.
	# Use a merge-walk by angle to produce a triangle strip.
	var li := 0
	var ci := 0
	var steps := lower_count + culet_count
	var emitted := 0
	while emitted < steps:
		var ln := (li + 1) % lower_count
		var cn := (ci + 1) % culet_count
		var lower_advance := _angle_distance(lower_angles[li], lower_angles[ln])
		var culet_advance := _angle_distance(culet_angles[ci], culet_angles[cn])
		if lower_advance <= culet_advance:
			# Emit triangle: lower[li], lower[ln], culet[ci]
			model.add_facet(PackedVector3Array([
				lower_ring[li],
				lower_ring[ln],
				culet_ring[ci],
			]), "pavilion")
			li = ln
		else:
			# Emit triangle: culet[ci], lower[li], culet[cn]
			model.add_facet(PackedVector3Array([
				culet_ring[ci],
				lower_ring[li],
				culet_ring[cn],
			]), "pavilion")
			ci = cn
		emitted += 1


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


## Convert 2D unit-space point to 3D model space.
static func _p3(point: Vector2, z: float) -> Vector3:
	return Vector3(point.x - 0.5, 0.5 - point.y, z)
