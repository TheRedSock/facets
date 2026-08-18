class_name GemSurfaceDamageGenerator
extends RefCounted

## Surface wear generator — material mask approach.
##
## This intentionally does not edit mesh topology. Scratches, abrasion, edge
## wear, and dirt are stored as deterministic per-facet primitives in
## GemMeshResource.surface_wear_entries and evaluated by the native tracer at
## hit time as exterior-only frosted dielectric material.

const WEAR_TYPE_SCRATCH := 0
const WEAR_TYPE_ABRASION := 1
const WEAR_TYPE_EDGE_WEAR := 2
const WEAR_TYPE_DIRT := 3

const SNAP_SCALE := 100000.0
const MAX_SCRATCH_SEGMENTS := 12


static func generate_and_merge(mesh: Resource, profile: Resource, bounding_radius: float, seed_base: int = 42) -> void:
	if mesh == null or profile == null:
		return
	if typeof(mesh.get("surface_wear_entries")) != TYPE_ARRAY:
		push_error("GemSurfaceDamageGenerator requires GemMeshResource.surface_wear_entries")
		return
	if bounding_radius <= 0.0:
		bounding_radius = 0.5

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base + profile.seed_offset

	var surface := _collect_surface_facets(mesh, profile.target_zones)
	if surface.indices.is_empty():
		return
	var adjacency := _build_edge_adjacency(mesh, surface)

	var entries: Array[Dictionary] = []
	entries.append_array(_compute_scratch_entries(rng, mesh, surface, profile, adjacency))
	entries.append_array(_compute_abrasion_entries(rng, mesh, surface, profile))
	entries.append_array(_compute_edge_wear_entries(rng, mesh, surface, profile, adjacency))
	entries.append_array(_compute_dirt_entries(rng, mesh, surface, profile))
	if entries.is_empty():
		return

	mesh.surface_wear_entries.append_array(entries)
	mesh._trace_data_cache.clear()


static func _collect_surface_facets(mesh: Resource, target_zones: Array[StringName]) -> Dictionary:
	var indices: Array[int] = []
	var areas: Array[float] = []
	var total_area := 0.0
	var index_set := {}
	var has_zone_filter := not target_zones.is_empty()

	for i in mesh.facet_vertices.size():
		var zone := String(mesh.facet_zones[i] if i < mesh.facet_zones.size() else "")
		if zone == "inclusion":
			continue
		if has_zone_filter:
			var matched := false
			for target_zone in target_zones:
				if _zone_matches_target(zone, String(target_zone)):
					matched = true
					break
			if not matched:
				continue
		var area := _polygon_area_3d(mesh.facet_vertices[i])
		if area <= 0.0:
			continue
		indices.append(i)
		areas.append(area)
		total_area += area
		index_set[i] = true

	return {"indices": indices, "areas": areas, "total_area": total_area, "index_set": index_set}


static func _zone_matches_target(zone: String, target_zone: String) -> bool:
	var target := target_zone.strip_edges().to_lower()
	var z := zone.to_lower()
	if target.is_empty() or target == "all" or target == "surface" or target == "exterior":
		return true
	if z == target:
		return true
	match target:
		"crown":
			return z in ["table", "step", "star", "bezel", "kite", "upper_girdle", "crown"]
		"table":
			return z == "table" or z.begins_with("table_")
		"step":
			return z == "step" or z.begins_with("step_") or z.ends_with("_step")
		"girdle":
			return z == "girdle" or z == "girdle_band" or z.begins_with("girdle_")
		"pavilion":
			return z == "pavilion" or z == "culet" or z.begins_with("pavilion_") or z.ends_with("_pavilion")
	return false


static func _build_edge_adjacency(mesh: Resource, surface: Dictionary) -> Dictionary:
	var adjacency := {}
	for facet_index in surface.indices:
		var verts: PackedVector3Array = mesh.facet_vertices[facet_index]
		var zone := String(mesh.facet_zones[facet_index] if facet_index < mesh.facet_zones.size() else "")
		for vertex_index in verts.size():
			var v0 := verts[vertex_index]
			var v1 := verts[(vertex_index + 1) % verts.size()]
			var key := _edge_key(v0, v1)
			if not adjacency.has(key):
				adjacency[key] = []
			adjacency[key].append({"facet": facet_index, "v0": v0, "v1": v1, "zone": zone})
	return adjacency


static func _compute_scratch_entries(
	rng: RandomNumberGenerator,
	mesh: Resource,
	surface: Dictionary,
	profile: Resource,
	adjacency: Dictionary,
) -> Array[Dictionary]:
	var total_count: int = rng.randi_range(profile.scratch_count_range.x, profile.scratch_count_range.y)
	if total_count <= 0:
		return []

	var cluster_size: int = maxi(profile.scratch_cluster_size, 1)
	var cluster_count: int = ceili(float(total_count) / float(cluster_size))
	var spread_rad := deg_to_rad(profile.scratch_cluster_spread_degrees)
	var width_jitter: float = clampf(profile.scratch_width_jitter, 0.0, 0.8)
	var taper_ratio: float = clampf(profile.scratch_taper_ratio, 0.0, 1.0)
	var entries: Array[Dictionary] = []
	var generated := 0

	for _cluster_index in cluster_count:
		if generated >= total_count:
			break
		var sp := _pick_surface_point(rng, mesh, surface)
		var cluster_center: Vector3 = sp.point
		var cluster_normal: Vector3 = sp.normal
		var cluster_facet: int = sp.facet_index
		var primary_dir := _random_tangent(rng, cluster_normal)
		var perp_dir := cluster_normal.cross(primary_dir).normalized()
		var scratches_this_cluster: int = mini(cluster_size, total_count - generated)

		for _scratch_index in scratches_this_cluster:
			var start: Vector3 = cluster_center \
				+ perp_dir * rng.randf_range(-2.0, 2.0) * profile.scratch_width \
				+ primary_dir * rng.randf_range(-0.5, 0.5) * profile.scratch_length_min
			var dir: Vector3 = primary_dir.rotated(cluster_normal, rng.randf_range(-spread_rad, spread_rad)).normalized()
			var length: float = lerpf(profile.scratch_length_min, profile.scratch_length_max, rng.randf())
			var jitter_mult: float = 1.0 + rng.randf_range(-width_jitter, width_jitter)
			var width: float = float(profile.scratch_width) * jitter_mult
			entries.append_array(_walk_scratch_entries(
				start,
				dir,
				cluster_normal,
				length,
				width,
				cluster_facet,
				mesh,
				surface,
				adjacency,
				profile.scratch_facet_crossing_ratio,
				taper_ratio,
				rng
			))
			generated += 1

	return entries


static func _walk_scratch_entries(
	start: Vector3,
	direction: Vector3,
	normal: Vector3,
	length: float,
	width: float,
	facet_idx: int,
	mesh: Resource,
	surface: Dictionary,
	adjacency: Dictionary,
	crossing_ratio: float,
	taper_ratio: float,
	rng: RandomNumberGenerator,
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var current_pos := _project_point_to_facet(start, facet_idx, mesh, normal)
	var current_dir := _project_direction_onto_plane(direction, normal)
	var current_normal := normal
	var current_facet := facet_idx
	var remaining_length := length
	var total_segments: int = maxi(ceili(length / 0.035), 2)
	var segment_length := length / float(total_segments)
	var segments_walked := 0

	for _segment_index in MAX_SCRATCH_SEGMENTS:
		if remaining_length <= 0.001:
			break
		var step := minf(segment_length, remaining_length)
		var next_pos := current_pos + current_dir * step

		# Width taper: lens profile peaks at mid-length, narrows toward ends.
		# norm_t = segment midpoint position along full length in [0, 1].
		var norm_t: float = clampf((float(segments_walked) + 0.5) / float(total_segments), 0.0, 1.0)
		var taper: float = 1.0 - abs(norm_t * 2.0 - 1.0) * taper_ratio
		var segment_radius: float = width * 0.5 * taper

		if _point_on_facet(next_pos, current_facet, mesh, current_normal):
			entries.append(_make_capsule_entry(
				WEAR_TYPE_SCRATCH,
				current_facet,
				current_pos,
				next_pos,
				current_normal,
				segment_radius,
				1.0,
				rng
			))
			current_pos = next_pos
			remaining_length -= step
			segments_walked += 1
			continue

		var crossed := {"success": false}
		if rng.randf() < crossing_ratio:
			crossed = _try_cross_facet(current_pos, current_dir, current_facet, mesh, surface, adjacency)
		if not crossed.get("success", false):
			var clipped_pos: Vector3 = _closest_boundary_point(current_pos, current_dir, current_facet, mesh)
			if current_pos.distance_squared_to(clipped_pos) > 1e-8:
				entries.append(_make_capsule_entry(
					WEAR_TYPE_SCRATCH,
					current_facet,
					current_pos,
					clipped_pos,
					current_normal,
					segment_radius,
					0.85,
					rng
				))
			break

		var boundary_pos: Vector3 = crossed.boundary_point
		if current_pos.distance_squared_to(boundary_pos) > 1e-8:
			entries.append(_make_capsule_entry(
				WEAR_TYPE_SCRATCH,
				current_facet,
				current_pos,
				boundary_pos,
				current_normal,
				segment_radius,
				1.0,
				rng
			))
			remaining_length -= current_pos.distance_to(boundary_pos)
		current_facet = crossed.facet_index
		current_normal = crossed.normal
		current_dir = _project_direction_onto_plane(current_dir, current_normal)
		current_dir = current_dir.rotated(current_normal, rng.randf_range(-0.18, 0.18)).normalized()
		current_pos = boundary_pos + current_dir * 0.0001
		segments_walked += 1

	return entries


static func _compute_abrasion_entries(rng: RandomNumberGenerator, mesh: Resource, surface: Dictionary, profile: Resource) -> Array[Dictionary]:
	# Abrasion is emitted as clusters of SHORT scratch segments (WEAR_TYPE_SCRATCH)
	# seeded at facet edges. This reuses the scratch shading path entirely and
	# produces natural-looking abrasion that aligns with the cut geometry,
	# instead of a disc-shaped stamp on the surface.
	var cluster_count: int = rng.randi_range(profile.abrasion_count_range.x, profile.abrasion_count_range.y)
	if cluster_count <= 0:
		return []
	var entries: Array[Dictionary] = []
	var seg_len_min: float = float(profile.abrasion_segment_length_range.x)
	var seg_len_max: float = float(profile.abrasion_segment_length_range.y)
	var seg_width: float = float(profile.abrasion_segment_width)
	var edge_bias: float = clampf(profile.abrasion_edge_bias, 0.0, 1.0)
	var density: float = clampf(profile.abrasion_density, 0.0, 1.0)
	# Translate density into a count of segments per cluster. At density=0.4 we
	# want ~5 segments; at density=1.0 we want ~10; minimum 3 so a cluster
	# always reads as a group.
	var segments_per_cluster: int = maxi(3, roundi(lerpf(3.0, 10.0, density)))

	var edge_pool := _build_facet_edge_pool(mesh, surface)

	for _cluster_index in cluster_count:
		var seed_point: Vector3
		var seed_normal: Vector3
		var seed_facet: int
		var edge_tangent := Vector3.ZERO
		var picked_edge := false

		if not edge_pool.is_empty() and rng.randf() < edge_bias:
			var edge := edge_pool[rng.randi_range(0, edge_pool.size() - 1)]
			var t_along: float = rng.randf()
			seed_point = edge.v0.lerp(edge.v1, t_along)
			seed_facet = int(edge.facet)
			seed_normal = mesh.facet_normals[seed_facet]
			edge_tangent = (edge.v1 - edge.v0).normalized()
			# Offset slightly into the facet interior so clusters sit beside the
			# edge rather than on top of the shared ridge.
			var inward := seed_normal.cross(edge_tangent).normalized()
			# Ensure inward points into the facet (away from neighboring facet
			# centroid if we can infer it). Cheap test: flip if it takes the
			# point outside the tri barycentric hull.
			var test_inside := seed_point + inward * float(profile.abrasion_radius) * 0.2
			if not _point_on_facet(test_inside, seed_facet, mesh, seed_normal):
				inward = -inward
			seed_point += inward * float(profile.abrasion_radius) * rng.randf_range(0.05, 0.45)
			picked_edge = true
		else:
			var sp := _pick_surface_point(rng, mesh, surface)
			seed_point = sp.point
			seed_normal = sp.normal
			seed_facet = int(sp.facet_index)

		# Primary in-plane direction for the cluster. Edge-seeded clusters align
		# with the edge; interior seeds pick a random tangent.
		var primary_dir: Vector3
		if picked_edge and edge_tangent.length_squared() > 1e-8:
			primary_dir = _project_direction_onto_plane(edge_tangent, seed_normal)
		else:
			primary_dir = _random_tangent(rng, seed_normal)
		var perp_dir := seed_normal.cross(primary_dir).normalized()

		# Scatter radius inside the cluster footprint.
		var footprint: float = float(profile.abrasion_radius)

		for _segment_index in segments_per_cluster:
			# Random offset within the cluster footprint (elliptical to keep
			# the cluster elongated along the seed edge).
			var along_offset: float = rng.randf_range(-footprint, footprint)
			var perp_offset: float = rng.randf_range(-footprint * 0.55, footprint * 0.55)
			var seg_start: Vector3 = seed_point + primary_dir * along_offset + perp_dir * perp_offset
			# Direction biased around primary with ±25° variance.
			var spread: float = deg_to_rad(25.0)
			var seg_dir: Vector3 = primary_dir.rotated(seed_normal, rng.randf_range(-spread, spread)).normalized()
			var seg_length: float = lerpf(seg_len_min, seg_len_max, rng.randf())
			var seg_end: Vector3 = seg_start + seg_dir * seg_length
			# Project both endpoints to the facet and clip if one lies outside.
			seg_start = _project_point_to_facet(seg_start, seed_facet, mesh, seed_normal)
			seg_end = _project_point_to_facet(seg_end, seed_facet, mesh, seed_normal)
			if not _point_on_facet(seg_end, seed_facet, mesh, seed_normal):
				seg_end = _closest_boundary_point(seg_start, seg_dir, seed_facet, mesh)
			if seg_start.distance_squared_to(seg_end) < 1e-8:
				continue
			var seg_jitter: float = rng.randf_range(0.6, 1.25)
			entries.append(_make_capsule_entry(
				WEAR_TYPE_SCRATCH,
				seed_facet,
				seg_start,
				seg_end,
				seed_normal,
				seg_width * 0.5 * seg_jitter,
				rng.randf_range(0.8, 1.0),
				rng
			))

	return entries


## Build a flat pool of (facet, v0, v1) edges for edge-biased cluster seeding.
## Edges are weighted by length in the sense that longer edges appear
## proportionally more often when we uniform-pick from the pool: long edges
## are subdivided into multiple pool entries.
static func _build_facet_edge_pool(mesh: Resource, surface: Dictionary) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for facet_index in surface.indices:
		var verts: PackedVector3Array = mesh.facet_vertices[facet_index]
		if verts.size() < 2:
			continue
		for vertex_index in verts.size():
			var v0: Vector3 = verts[vertex_index]
			var v1: Vector3 = verts[(vertex_index + 1) % verts.size()]
			var edge_len: float = v0.distance_to(v1)
			if edge_len < 1e-6:
				continue
			pool.append({"facet": facet_index, "v0": v0, "v1": v1, "length": edge_len})
	return pool


static func _compute_edge_wear_entries(
	rng: RandomNumberGenerator,
	mesh: Resource,
	surface: Dictionary,
	profile: Resource,
	adjacency: Dictionary,
) -> Array[Dictionary]:
	if profile.edge_wear_count <= 0:
		return []

	var table_boost: float = maxf(profile.edge_wear_table_boost, 1.0)
	var candidate_edges: Array[Dictionary] = []
	var weights: Array[float] = []
	var total_weight := 0.0
	for key in adjacency:
		var entries: Array = adjacency[key]
		if entries.size() < 2:
			continue
		var zones_differ := false
		var preferred_zone := false
		var is_table_perimeter := false
		var adjacent_zones_set := {}
		for a_idx in entries.size():
			var zone_a := String(entries[a_idx].zone).to_lower()
			adjacent_zones_set[zone_a] = true
			if zone_a in ["table", "step", "girdle", "girdle_band"] or zone_a.begins_with("step_"):
				preferred_zone = true
			for b_idx in range(a_idx + 1, entries.size()):
				if entries[a_idx].zone != entries[b_idx].zone:
					zones_differ = true
		# Table-perimeter edges: the table faces light the most directly and
		# shows worn edges most prominently on a face-up gem.
		if adjacent_zones_set.has("table") and adjacent_zones_set.size() > 1:
			is_table_perimeter = true
		if not zones_differ:
			# Same-zone shared ridges still need a low-density halo on step cuts.
			preferred_zone = preferred_zone or String(entries[0].zone).to_lower() == "step"
		var edge_len: float = entries[0].v0.distance_to(entries[0].v1)
		if edge_len <= 0.0:
			continue
		var weight := edge_len
		if zones_differ:
			weight *= 1.4
		if preferred_zone:
			weight *= 1.6
		if is_table_perimeter:
			weight *= table_boost
		if not zones_differ:
			weight *= 0.35
		candidate_edges.append({"v0": entries[0].v0, "v1": entries[0].v1, "facets": entries})
		weights.append(weight)
		total_weight += weight

	if candidate_edges.is_empty():
		return []

	var wear_entries: Array[Dictionary] = []
	for _i in profile.edge_wear_count:
		var edge := _weighted_edge_pick(rng, candidate_edges, weights, total_weight)
		var t := rng.randf()
		var center: Vector3 = edge.v0.lerp(edge.v1, t)
		var edge_dir: Vector3 = (edge.v1 - edge.v0).normalized()
		var half_len: float = profile.edge_wear_size * rng.randf_range(0.7, 1.5)
		var p0: Vector3 = center - edge_dir * half_len
		var p1: Vector3 = center + edge_dir * half_len
		# Determine the two (or more) facets that share this edge so each
		# emitted wear entry knows the opposite facet normal for ridge-bevel
		# shading.
		var edge_facet_list: Array = edge.facets
		var facet_normals_by_index := {}
		for facet_entry in edge_facet_list:
			var fi: int = facet_entry.facet
			if surface.index_set.has(fi):
				facet_normals_by_index[fi] = mesh.facet_normals[fi]
		for facet_entry in edge_facet_list:
			var facet_index: int = facet_entry.facet
			if not surface.index_set.has(facet_index):
				continue
			var normal: Vector3 = mesh.facet_normals[facet_index]
			# Adjacent normal: pick any other facet sharing this edge.
			var adjacent_normal := normal
			for other_idx in facet_normals_by_index:
				if other_idx != facet_index:
					adjacent_normal = facet_normals_by_index[other_idx]
					break
			var entry := _make_capsule_entry(
				WEAR_TYPE_EDGE_WEAR,
				facet_index,
				_project_point_to_facet(p0, facet_index, mesh, normal),
				_project_point_to_facet(p1, facet_index, mesh, normal),
				normal,
				profile.edge_wear_size * 0.8,
				0.8,
				rng
			)
			entry["adjacent_normal"] = adjacent_normal
			wear_entries.append(entry)
	return wear_entries


static func _compute_dirt_entries(
	rng: RandomNumberGenerator,
	mesh: Resource,
	surface: Dictionary,
	profile: Resource,
) -> Array[Dictionary]:
	var count: int = rng.randi_range(profile.dirt_count_range.x, profile.dirt_count_range.y)
	if count <= 0:
		return []
	var opacity: float = clampf(profile.dirt_opacity, 0.0, 1.0)
	if opacity <= 0.0:
		return []
	var entries: Array[Dictionary] = []
	for _i in count:
		var sp := _pick_surface_point(rng, mesh, surface)
		var tangent: Vector3 = _random_tangent(rng, sp.normal)
		var radius: float = lerpf(profile.dirt_radius_min, profile.dirt_radius_max, rng.randf())
		entries.append({
			"type": WEAR_TYPE_DIRT,
			"facet_index": int(sp.facet_index),
			"p0": sp.point,
			"p1": sp.point + tangent * radius,
			"normal": sp.normal,
			"adjacent_normal": sp.normal,
			"radius": radius,
			"intensity": opacity * rng.randf_range(0.7, 1.0),
			"seed": rng.randf() * 4096.0,
		})
	return entries


static func _make_capsule_entry(
	wear_type: int,
	facet_index: int,
	p0: Vector3,
	p1: Vector3,
	normal: Vector3,
	radius: float,
	intensity: float,
	rng: RandomNumberGenerator,
) -> Dictionary:
	return {
		"type": wear_type,
		"facet_index": facet_index,
		"p0": p0,
		"p1": p1,
		"normal": normal,
		"radius": radius,
		"intensity": intensity,
		"seed": rng.randf() * 4096.0,
	}


static func _weighted_edge_pick(rng: RandomNumberGenerator, edges: Array[Dictionary], lengths: Array[float], total_length: float) -> Dictionary:
	var r := rng.randf() * total_length
	var cumulative := 0.0
	for i in edges.size():
		cumulative += lengths[i]
		if r <= cumulative:
			return edges[i]
	return edges[edges.size() - 1]


static func _point_on_facet(point: Vector3, facet_idx: int, mesh: Resource, normal: Vector3) -> bool:
	if facet_idx < 0 or facet_idx >= mesh.facet_vertices.size():
		return false
	var verts: PackedVector3Array = mesh.facet_vertices[facet_idx]
	var on_plane := _project_point_to_plane(point, normal, verts[0])
	var basis := _build_basis(normal, verts[0])
	return Geometry2D.is_point_in_polygon(_to_2d(on_plane, basis), _polygon_to_2d(verts, basis))


static func _try_cross_facet(pos: Vector3, direction: Vector3, facet_idx: int, mesh: Resource, surface: Dictionary, adjacency: Dictionary) -> Dictionary:
	var verts: PackedVector3Array = mesh.facet_vertices[facet_idx]
	var best_dist := INF
	var best_edge_v0 := Vector3.ZERO
	var best_edge_v1 := Vector3.ZERO
	var exit_point := pos + direction * 0.05

	for j in verts.size():
		var v0 := verts[j]
		var v1 := verts[(j + 1) % verts.size()]
		var closest := _closest_point_on_segment(exit_point, v0, v1)
		var distance := exit_point.distance_to(closest)
		if distance < best_dist:
			best_dist = distance
			best_edge_v0 = v0
			best_edge_v1 = v1

	var key := _edge_key(best_edge_v0, best_edge_v1)
	if not adjacency.has(key):
		return {"success": false}
	for entry in adjacency[key]:
		if entry.facet != facet_idx and surface.index_set.has(entry.facet):
			return {
				"success": true,
				"facet_index": int(entry.facet),
				"normal": mesh.facet_normals[entry.facet],
				"boundary_point": _closest_point_on_segment(pos, best_edge_v0, best_edge_v1),
			}
	return {"success": false}


static func _closest_boundary_point(pos: Vector3, direction: Vector3, facet_idx: int, mesh: Resource) -> Vector3:
	var verts: PackedVector3Array = mesh.facet_vertices[facet_idx]
	var exit_point := pos + direction * 0.05
	var best := pos
	var best_dist := INF
	for j in verts.size():
		var closest := _closest_point_on_segment(exit_point, verts[j], verts[(j + 1) % verts.size()])
		var distance := exit_point.distance_to(closest)
		if distance < best_dist:
			best_dist = distance
			best = closest
	return best


static func _project_point_to_facet(point: Vector3, facet_idx: int, mesh: Resource, normal: Vector3) -> Vector3:
	if facet_idx < 0 or facet_idx >= mesh.facet_vertices.size():
		return point
	return _project_point_to_plane(point, normal, mesh.facet_vertices[facet_idx][0])


static func _project_point_to_plane(point: Vector3, normal: Vector3, origin: Vector3) -> Vector3:
	return point - normal * normal.dot(point - origin)


static func _build_basis(normal: Vector3, origin: Vector3 = Vector3.ZERO) -> Dictionary:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var tangent := up.cross(normal).normalized()
	var bitangent := normal.cross(tangent).normalized()
	return {"origin": origin, "tangent": tangent, "bitangent": bitangent, "normal": normal}


static func _to_2d(point_3d: Vector3, basis: Dictionary) -> Vector2:
	var relative: Vector3 = point_3d - basis.origin
	return Vector2(relative.dot(basis.tangent), relative.dot(basis.bitangent))


static func _polygon_to_2d(verts_3d: PackedVector3Array, basis: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	for vertex in verts_3d:
		result.append(_to_2d(vertex, basis))
	return result


static func _project_direction_onto_plane(dir: Vector3, normal: Vector3) -> Vector3:
	var projected := dir - normal * dir.dot(normal)
	if projected.length_squared() <= 1e-12:
		var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		return up.cross(normal).normalized()
	return projected.normalized()


static func _pick_surface_point(rng: RandomNumberGenerator, mesh: Resource, surface: Dictionary) -> Dictionary:
	var facet_idx := _area_weighted_sample(rng, surface)
	var verts: PackedVector3Array = mesh.facet_vertices[facet_idx]
	var normal: Vector3 = mesh.facet_normals[facet_idx]
	var point: Vector3
	if verts.size() == 3:
		point = _random_point_on_triangle(rng, verts)
	else:
		var tri_idx := rng.randi_range(0, verts.size() - 3)
		point = _random_point_on_triangle(rng, PackedVector3Array([verts[0], verts[tri_idx + 1], verts[tri_idx + 2]]))
	return {"point": point, "normal": normal, "facet_index": facet_idx}


static func _area_weighted_sample(rng: RandomNumberGenerator, surface: Dictionary) -> int:
	var r: float = rng.randf() * float(surface.total_area)
	var cumulative := 0.0
	var indices: Array = surface.indices
	var areas: Array = surface.areas
	for i in indices.size():
		cumulative += float(areas[i])
		if r <= cumulative:
			return indices[i]
	return indices[indices.size() - 1]


static func _random_point_on_triangle(rng: RandomNumberGenerator, verts: PackedVector3Array) -> Vector3:
	var u := rng.randf()
	var v := rng.randf()
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var w := 1.0 - u - v
	return verts[0] * w + verts[1] * u + verts[2] * v


static func _random_tangent(rng: RandomNumberGenerator, normal: Vector3) -> Vector3:
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var tangent := up.cross(normal).normalized()
	var bitangent := normal.cross(tangent).normalized()
	var angle := rng.randf() * TAU
	return (tangent * cos(angle) + bitangent * sin(angle)).normalized()


static func _closest_point_on_segment(point: Vector3, seg_a: Vector3, seg_b: Vector3) -> Vector3:
	var ab := seg_b - seg_a
	var len_sq := ab.length_squared()
	if len_sq < 1e-12:
		return seg_a
	var t := clampf((point - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	return seg_a + ab * t


static func _polygon_area_3d(verts: PackedVector3Array) -> float:
	if verts.size() < 3:
		return 0.0
	var total := Vector3.ZERO
	for i in range(1, verts.size() - 1):
		total += (verts[i] - verts[0]).cross(verts[i + 1] - verts[0])
	return total.length() * 0.5


static func _vertex_key(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * SNAP_SCALE), roundi(v.y * SNAP_SCALE), roundi(v.z * SNAP_SCALE)]


static func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := _vertex_key(a)
	var kb := _vertex_key(b)
	return ka + "|" + kb if ka < kb else kb + "|" + ka
