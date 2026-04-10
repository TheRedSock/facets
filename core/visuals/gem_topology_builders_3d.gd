class_name GemTopologyBuilders3D
extends RefCounted

## Explicit 3D topology builders for the canonical cut pipeline.

const GemCutModelResourceScript = preload("res://resources/visuals/gem_cut_model_resource.gd")
const GemCutPrimitivesScript = preload("res://core/visuals/gem_cut_primitives.gd")
const GIRDLE_WALL_ZONE := "girdle_band"


static func build(spec):
	if spec == null:
		return null
	match spec.family:
		&"radial_brilliant":
			return _build_radial_brilliant(spec)
		&"step":
			return _build_step(spec)
		&"rose":
			return _build_rose(spec)
		&"fan":
			return _build_fan(spec)
		&"radiant":
			return _build_radiant(spec)
		&"princess":
			return _build_princess(spec)
		&"fan_step":
			return _build_fan_step(spec)
	return null


static func _build_radial_brilliant(spec):
	var model = _make_model(spec)
	var main_angles = _to_float_array(spec.get_main_angles())
	if main_angles.is_empty():
		main_angles = GemCutPrimitivesScript.regular_angles(
			spec.get_symmetry_sector_count(),
			spec.get_symmetry_rotation()
		)
	var half_angles = _to_float_array(spec.get_half_angles())
	if half_angles.is_empty():
		half_angles = GemCutPrimitivesScript.half_angles(main_angles)
	var rings = _sample_radial_rings(spec, main_angles, half_angles)

	var table_z = spec.get_crown_height()
	var star_z = spec.get_crown_height() * spec.get_star_height_ratio()
	var girdle_z = 0.0

	var table_v = rings["table_v"]
	var star_v = rings["star_v"]
	var girdle_m = rings["girdle_m"]
	var girdle_h = rings["girdle_h"]
	var patched_loops = _apply_named_loop_patches(spec, {
		"table": table_v,
		"star": star_v,
		"girdle_main": girdle_m,
		"girdle_half": girdle_h,
	})
	table_v = patched_loops.get("table", table_v)
	star_v = patched_loops.get("star", star_v)
	girdle_m = patched_loops.get("girdle_main", girdle_m)
	girdle_h = patched_loops.get("girdle_half", girdle_h)
	var count = table_v.size()

	var interleaved_girdle: Array[Vector2] = []
	for i in girdle_m.size():
		interleaved_girdle.append(girdle_m[i])
		if i < girdle_h.size():
			interleaved_girdle.append(girdle_h[i])
	model.outer_loop = _loop_to_mesh(interleaved_girdle, 0.0)
	model.add_facet(_polygon3(table_v, table_z), "table")

	for i in count:
		var next_index = (i + 1) % count
		model.add_facet(PackedVector3Array([
			_p3(table_v[i], table_z),
			_p3(star_v[i], star_z),
			_p3(table_v[next_index], table_z),
		]), "star")

	for i in count:
		var prev_index = (i - 1 + count) % count
		model.add_facet(PackedVector3Array([
			_p3(star_v[prev_index], star_z),
			_p3(table_v[i], table_z),
			_p3(star_v[i], star_z),
			_p3(girdle_m[i], girdle_z),
		]), "bezel")

	for i in count:
		var next_index = (i + 1) % count
		model.add_facet(PackedVector3Array([
			_p3(star_v[i], star_z),
			_p3(girdle_m[i], girdle_z),
			_p3(girdle_h[i], girdle_z),
		]), "girdle")
		model.add_facet(PackedVector3Array([
			_p3(star_v[i], star_z),
			_p3(girdle_h[i], girdle_z),
			_p3(girdle_m[next_index], girdle_z),
		]), "girdle")

	_append_interleaved_pavilion(model, girdle_m, girdle_h, spec)
	model.finalize_model()
	return model


static func _build_step(spec):
	var model = _make_model(spec)
	var rings = spec.get_ring_point_loops()
	if rings.is_empty():
		model.finalize_model()
		return model

	var heights = _resolve_ring_heights(spec, rings.size())
	var ring_patches := {}
	for ring_index in rings.size():
		var ring_name := "ring_%02d" % ring_index
		if ring_index < spec.rings.size() and typeof(spec.rings[ring_index]) == TYPE_DICTIONARY:
			ring_name = String(spec.rings[ring_index].get("name", ring_name))
		ring_patches[ring_name] = rings[ring_index]
		if ring_index == 0:
			ring_patches["outer"] = rings[ring_index]
		if ring_index == rings.size() - 1:
			ring_patches["table"] = rings[ring_index]
	ring_patches = _apply_named_loop_patches(spec, ring_patches)
	for ring_index in rings.size():
		var ring_name := "ring_%02d" % ring_index
		if ring_index < spec.rings.size() and typeof(spec.rings[ring_index]) == TYPE_DICTIONARY:
			ring_name = String(spec.rings[ring_index].get("name", ring_name))
		rings[ring_index] = ring_patches.get(ring_name, rings[ring_index])
	model.outer_loop = _loop_to_mesh(rings[0], 0.0)
	var ring_zones = spec.get_ring_zones()
	var table_index = rings.size() - 1
	model.add_facet(_polygon3(rings[table_index], heights[table_index]), "table")

	var subdivisions: int = maxi(int(spec.crown.get("step_edge_subdivisions", 1)), 1)

	for ring_index in rings.size() - 1:
		var outer = rings[ring_index]
		var inner = rings[ring_index + 1]
		var zone = ring_zones[ring_index] if ring_index < ring_zones.size() else "step"
		for i in outer.size():
			var next_index = (i + 1) % outer.size()
			if subdivisions <= 1:
				model.add_facet(PackedVector3Array([
					_p3(inner[i], heights[ring_index + 1]),
					_p3(inner[next_index], heights[ring_index + 1]),
					_p3(outer[next_index], heights[ring_index]),
					_p3(outer[i], heights[ring_index]),
				]), zone)
			else:
				for s in subdivisions:
					var t0 := float(s) / float(subdivisions)
					var t1 := float(s + 1) / float(subdivisions)
					var o0: Vector2 = Vector2(outer[i]).lerp(Vector2(outer[next_index]), t0)
					var o1: Vector2 = Vector2(outer[i]).lerp(Vector2(outer[next_index]), t1)
					var i0: Vector2 = Vector2(inner[i]).lerp(Vector2(inner[next_index]), t0)
					var i1: Vector2 = Vector2(inner[i]).lerp(Vector2(inner[next_index]), t1)
					model.add_facet(PackedVector3Array([
						_p3(i0, heights[ring_index + 1]),
						_p3(i1, heights[ring_index + 1]),
						_p3(o1, heights[ring_index]),
						_p3(o0, heights[ring_index]),
					]), zone)

	# Pavilion uses original (non-subdivided) boundary so girdle wall
	# edges match the crown's outermost ring vertices.
	_append_outline_pavilion(model, _ensure_loop_array(rings[0]), spec)
	model.finalize_model()
	return model


static func _build_rose(spec):
	var model = _make_model(spec)
	var rings = spec.get_ring_point_loops()
	if rings.is_empty():
		model.finalize_model()
		return model

	var heights = _resolve_rose_heights(spec, rings.size())
	var rose_patches := {}
	for ring_index in rings.size():
		var ring_name := "ring_%02d" % ring_index
		if ring_index < spec.rings.size() and typeof(spec.rings[ring_index]) == TYPE_DICTIONARY:
			ring_name = String(spec.rings[ring_index].get("name", ring_name))
		rose_patches[ring_name] = rings[ring_index]
		if ring_index == 0:
			rose_patches["outer"] = rings[ring_index]
		if ring_index == rings.size() - 1:
			rose_patches["table"] = rings[ring_index]
	rose_patches = _apply_named_loop_patches(spec, rose_patches)
	for ring_index in rings.size():
		var ring_name := "ring_%02d" % ring_index
		if ring_index < spec.rings.size() and typeof(spec.rings[ring_index]) == TYPE_DICTIONARY:
			ring_name = String(spec.rings[ring_index].get("name", ring_name))
		rings[ring_index] = rose_patches.get(ring_name, rings[ring_index])
	model.outer_loop = _loop_to_mesh(rings[0], 0.0)
	if rings.size() == 1:
		var center_point = spec.get_center_point()
		var outer_ring = rings[0]
		for i in outer_ring.size():
			var next_index = (i + 1) % outer_ring.size()
			model.add_facet(PackedVector3Array([
				_p3(center_point, heights[0]),
				_p3(outer_ring[i], 0.0),
				_p3(outer_ring[next_index], 0.0),
			]), "rose")
	else:
		for band_index in rings.size() - 1:
			var outer_ring = rings[band_index]
			var inner_ring = rings[band_index + 1]
			for i in outer_ring.size():
				var next_index = (i + 1) % outer_ring.size()
				model.add_facet(PackedVector3Array([
					_p3(inner_ring[i], heights[band_index + 1]),
					_p3(outer_ring[i], heights[band_index]),
					_p3(outer_ring[next_index], heights[band_index]),
				]), "rose")
				model.add_facet(PackedVector3Array([
					_p3(inner_ring[i], heights[band_index + 1]),
					_p3(outer_ring[next_index], heights[band_index]),
					_p3(inner_ring[next_index], heights[band_index + 1]),
				]), "rose")
		model.add_facet(_polygon3(rings[rings.size() - 1], heights[heights.size() - 1]), "rose_center")

	_append_outline_pavilion(model, _ensure_loop_array(rings[0]), spec)
	model.finalize_model()
	return model


static func _build_fan(spec):
	var model = _make_model(spec)
	var table = spec.get_table_points()
	var inner_star_facets = spec.get_inner_star_facets()
	var star_facets = spec.get_star_facets()
	var bezel_facets = spec.get_bezel_facets()
	var fans = spec.get_fans()
	var silhouette = spec.get_silhouette_points()
	var crown_boundary = _stitch_boundary_loop_from_fans(fans)

	var table_z = spec.get_crown_height()
	var inner_star_z = spec.get_crown_height() * spec.get_inner_star_height_ratio()
	var star_z = spec.get_crown_height() * spec.get_star_height_ratio()
	var point_heights = {}
	_register_height_points(point_heights, table, table_z)
	for facet_points in inner_star_facets:
		var points = facet_points
		for point in points:
			if not _point_height_exists(point_heights, point):
				_set_point_height(point_heights, point, inner_star_z)
	for fan in fans:
		var apex = fan.get("apex", GemCutPrimitivesScript.CENTER)
		_set_point_height(point_heights, apex, star_z)
		var boundary = _ensure_loop_array(fan.get("boundary", []))
		_register_height_points(point_heights, boundary, 0.0)
	for facet_points in star_facets:
		var points = facet_points
		for point in points:
			if not _point_height_exists(point_heights, point):
				_set_point_height(point_heights, point, star_z)
	for facet_points in bezel_facets:
		var points = facet_points
		for point in points:
			if not _point_height_exists(point_heights, point):
				_set_point_height(point_heights, point, 0.0)

	model.outer_loop = _loop_to_mesh(_packed_to_array(silhouette), 0.0)
	model.add_facet(_polygon3(table, table_z), "table")
	for facet_points in inner_star_facets:
		model.add_facet(_polygon3_from_height_map(facet_points, point_heights, inner_star_z), "star")
	for facet_points in star_facets:
		model.add_facet(_polygon3_from_height_map(facet_points, point_heights, star_z), "star")
	for facet_points in bezel_facets:
		model.add_facet(_polygon3_from_height_map(facet_points, point_heights, 0.0), "bezel")
	for fan in fans:
		var apex = fan.get("apex", GemCutPrimitivesScript.CENTER)
		var boundary = _ensure_loop_array(fan.get("boundary", []))
		for i in boundary.size() - 1:
			model.add_facet(PackedVector3Array([
				_p3(apex, star_z),
				_p3(boundary[i], 0.0),
				_p3(boundary[i + 1], 0.0),
			]), "girdle")

	_append_outline_pavilion(model, crown_boundary, spec)
	model.finalize_model()
	return model


static func _build_radiant(spec):
	var model = _make_model(spec)
	var outer = spec.get_outer_points()
	var count = outer.size()
	if count < 4:
		model.finalize_model()
		return model
	var table = GemCutPrimitivesScript.scale_points(outer, spec.get_table_ratio())
	var patched_loops = _apply_named_loop_patches(spec, {
		"outer": outer,
		"table": table,
	})
	outer = patched_loops.get("outer", outer)
	table = patched_loops.get("table", table)
	var break_ratio = spec.get_break_ratio()
	var outer_breaks = []
	for i in count:
		var next_index = (i + 1) % count
		outer_breaks.append(GemCutPrimitivesScript.point_on_segment(outer[i], outer[next_index], break_ratio))

	var table_z = spec.get_crown_height()
	var break_z = spec.get_crown_height() * spec.get_star_height_ratio()
	model.outer_loop = _loop_to_mesh(outer, 0.0)
	model.add_facet(_polygon3(table, table_z), "table")
	for i in count:
		var next_index = (i + 1) % count
		var prev_index = (i - 1 + count) % count
		model.add_facet(PackedVector3Array([
			_p3(table[i], table_z),
			_p3(table[next_index], table_z),
			_p3(outer_breaks[i], break_z),
		]), "star")
		model.add_facet(PackedVector3Array([
			_p3(outer[i], 0.0),
			_p3(outer[next_index], 0.0),
			_p3(outer_breaks[i], break_z),
		]), "girdle")
		model.add_facet(PackedVector3Array([
			_p3(table[i], table_z),
			_p3(outer_breaks[prev_index], break_z),
			_p3(outer[i], 0.0),
			_p3(outer_breaks[i], break_z),
		]), "bezel")

	_append_outline_pavilion(model, outer, spec)
	model.finalize_model()
	return model


static func _build_princess(spec):
	var model = _make_model(spec)
	var outer = spec.get_outer_points()
	if outer.size() != 4:
		model.finalize_model()
		return model
	var table = GemCutPrimitivesScript.scale_points(outer, spec.get_table_ratio())
	var patched_loops = _apply_named_loop_patches(spec, {
		"outer": outer,
		"table": table,
	})
	outer = patched_loops.get("outer", outer)
	table = patched_loops.get("table", table)
	var edge_trim = clampf(spec.get_edge_trim(), 0.08, 0.36)
	var trim_start = []
	var trim_end = []
	for i in outer.size():
		var next_index = (i + 1) % outer.size()
		trim_start.append(GemCutPrimitivesScript.point_on_segment(outer[i], outer[next_index], edge_trim))
		trim_end.append(GemCutPrimitivesScript.point_on_segment(outer[i], outer[next_index], 1.0 - edge_trim))

	var table_z = spec.get_crown_height()
	var star_z = spec.get_crown_height() * spec.get_star_height_ratio()
	model.outer_loop = _loop_to_mesh(outer, 0.0)
	model.add_facet(_polygon3(table, table_z), "table")
	for i in outer.size():
		var next_index = (i + 1) % outer.size()
		var prev_side = (i - 1 + outer.size()) % outer.size()
		model.add_facet(PackedVector3Array([
			_p3(table[i], table_z),
			_p3(trim_end[prev_side], star_z),
			_p3(trim_start[i], star_z),
		]), "star")
		model.add_facet(PackedVector3Array([
			_p3(table[i], table_z),
			_p3(table[next_index], table_z),
			_p3(trim_end[i], star_z),
			_p3(trim_start[i], star_z),
		]), "bezel")
		model.add_facet(PackedVector3Array([
			_p3(trim_start[i], star_z),
			_p3(trim_end[i], star_z),
			_p3(outer[next_index], 0.0),
			_p3(outer[i], 0.0),
		]), "girdle")
		model.add_facet(PackedVector3Array([
			_p3(outer[i], 0.0),
			_p3(trim_start[i], star_z),
			_p3(trim_end[prev_side], star_z),
		]), "girdle")

	_append_outline_pavilion(model, outer, spec)
	model.finalize_model()
	return model


static func _build_fan_step(spec):
	var model = _make_model(spec)
	var table = spec.get_table_points()
	var bezel_facets = spec.get_bezel_facets()
	var silhouette = spec.get_silhouette_points()
	var crown_boundary = _stitch_boundary_loop_from_bezel_facets(bezel_facets)
	var table_z = spec.get_crown_height()
	var shoulder_scale = clampf(spec.get_outer_shoulder_scale(), 0.7, 1.0)
	var shoulder_height_ratio = clampf(spec.get_outer_shoulder_height_ratio(), 0.0, 0.95)
	var shoulder_z = table_z * shoulder_height_ratio
	var shoulder_boundary = crown_boundary
	var boundary_point_map := {}
	if shoulder_scale < 0.999 and shoulder_z > 0.0001 and not crown_boundary.is_empty():
		shoulder_boundary = _scale_loop_about_center(crown_boundary, shoulder_scale)
		for i in crown_boundary.size():
			boundary_point_map[_point_key(crown_boundary[i])] = shoulder_boundary[i]
	model.outer_loop = _loop_to_mesh(_packed_to_array(silhouette), 0.0)
	model.add_facet(_polygon3(table, table_z), "table")
	for polygon in bezel_facets:
		var points = polygon
		var facet = PackedVector3Array()
		for point in points:
			var target_point = point
			var z = table_z if table.has(point) else 0.0
			if z <= 0.0 and boundary_point_map.has(_point_key(point)):
				target_point = boundary_point_map[_point_key(point)]
				z = shoulder_z
			facet.append(_p3(target_point, z))
		model.add_facet(facet, "bezel")
	if shoulder_boundary != crown_boundary:
		for i in crown_boundary.size():
			var next_index = (i + 1) % crown_boundary.size()
			model.add_facet(PackedVector3Array([
				_p3(shoulder_boundary[i], shoulder_z),
				_p3(shoulder_boundary[next_index], shoulder_z),
				_p3(crown_boundary[next_index], 0.0),
				_p3(crown_boundary[i], 0.0),
			]), "girdle")
	_append_outline_pavilion(model, crown_boundary, spec)
	model.finalize_model()
	return model


static func _append_interleaved_pavilion(
	model,
	girdle_main: Array[Vector2],
	girdle_half: Array[Vector2],
	spec,
) -> void:
	var count = girdle_main.size()
	if count == 0 or girdle_half.size() != count:
		return
	var boundary_ring: Array[Vector2] = []
	for i in count:
		boundary_ring.append(girdle_main[i])
		boundary_ring.append(girdle_half[i])
	var girdle_lower_ring = []
	var upper_ring = []
	var lower_ring = []
	var pavilion_sector_count: int = spec.get_pavilion_sector_count()
	var rotation_angle = TAU / float(maxi(pavilion_sector_count, 1)) * spec.get_pavilion_rotation_fraction() if pavilion_sector_count > 0 else 0.0
	var upper_z = -spec.get_girdle_thickness() - spec.get_pavilion_depth() * spec.get_pavilion_upper_depth_ratio()
	var lower_z = -spec.get_girdle_thickness() - spec.get_pavilion_depth() * spec.get_pavilion_lower_depth_ratio()
	for point in boundary_ring:
		girdle_lower_ring.append(_p3(point, -spec.get_girdle_thickness()))
		upper_ring.append(_project_pavilion_point(point, spec.get_pavilion_upper_scale(), upper_z, rotation_angle))
		lower_ring.append(_project_pavilion_point(point, spec.get_pavilion_lower_scale(), lower_z, rotation_angle))
	var ring_count = boundary_ring.size()
	var culet = Vector3(0.0, 0.0, -spec.get_girdle_thickness() - spec.get_pavilion_depth())

	# Merge lower-ring points that converge at shape cusps (e.g. pear tip)
	# to avoid degenerate culet triangles and sliver pavilion quads.
	var lower_seg_dists: Array[float] = []
	for i in ring_count:
		lower_seg_dists.append(lower_ring[i].distance_to(lower_ring[(i + 1) % ring_count]))
	lower_seg_dists.sort()
	@warning_ignore("INTEGER_DIVISION")
	var median_lower_dist := lower_seg_dists[lower_seg_dists.size() / 2] if not lower_seg_dists.is_empty() else 0.0
	var merge_threshold := median_lower_dist * 0.2

	var merged_lower: Array[Vector3] = []
	var lower_map: Array[int] = []
	lower_map.resize(ring_count)
	merged_lower.append(lower_ring[0])
	lower_map[0] = 0
	for i in range(1, ring_count):
		if lower_ring[i].distance_to(merged_lower.back()) > merge_threshold:
			merged_lower.append(lower_ring[i])
		lower_map[i] = merged_lower.size() - 1
	# Wrap-around: merge trailing points that are close to the first merged point.
	while merged_lower.size() > 1 and merged_lower.back().distance_to(merged_lower[0]) <= merge_threshold:
		var last_idx := merged_lower.size() - 1
		merged_lower[0] = (merged_lower[0] + merged_lower[last_idx]) * 0.5
		merged_lower.resize(last_idx)
		for i in ring_count:
			if lower_map[i] >= last_idx:
				lower_map[i] = 0

	for i in ring_count:
		var next_index = (i + 1) % ring_count
		model.add_facet(PackedVector3Array([
			_p3(boundary_ring[i], 0.0),
			_p3(boundary_ring[next_index], 0.0),
			girdle_lower_ring[next_index],
			girdle_lower_ring[i],
		]), GIRDLE_WALL_ZONE)
		model.add_facet(PackedVector3Array([
			girdle_lower_ring[i],
			girdle_lower_ring[next_index],
			upper_ring[next_index],
			upper_ring[i],
		]), "pavilion")
		var mi := lower_map[i]
		var mn := lower_map[next_index]
		if mi != mn:
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next_index],
				merged_lower[mn],
				merged_lower[mi],
			]), "pavilion")
			model.add_facet(PackedVector3Array([
				merged_lower[mi],
				culet,
				merged_lower[mn],
			]), "culet")
		else:
			# Converging segment: collapse lower quad to triangle, skip culet.
			model.add_facet(PackedVector3Array([
				upper_ring[i],
				upper_ring[next_index],
				merged_lower[mi],
			]), "pavilion")


static func _append_outline_pavilion(
	model,
	boundary: Array[Vector2],
	spec,
) -> void:
	if boundary.size() < 3:
		return
	var pavilion_sector_count: int = spec.get_pavilion_sector_count()
	var rotation_angle = TAU / float(maxi(pavilion_sector_count, 1)) * spec.get_pavilion_rotation_fraction() if pavilion_sector_count > 0 else 0.0
	var pavilion_style := String(spec.pavilion.get("style", "outline"))
	if pavilion_style == "single_step":
		_append_outline_single_step_pavilion(model, boundary, spec, rotation_angle)
		return
	if pavilion_style == "mirror_crown":
		_append_outline_mirror_crown_pavilion(model, boundary, spec)
		return
	var upper_z = -spec.get_girdle_thickness() - spec.get_pavilion_depth() * spec.get_pavilion_upper_depth_ratio()
	var lower_z = -spec.get_girdle_thickness() - spec.get_pavilion_depth() * spec.get_pavilion_lower_depth_ratio()
	var outer_ring = []
	var upper_ring = []
	var lower_ring = []
	for index in boundary.size():
		var point = boundary[index]
		var sharpness = _loop_vertex_sharpness(PackedVector2Array(boundary), index)
		var upper_scale = clampf(spec.get_pavilion_upper_scale() - sharpness * 0.04, 0.16, 0.96)
		var lower_scale = clampf(spec.get_pavilion_lower_scale() - sharpness * 0.06, 0.10, upper_scale - 0.04)
		model.add_facet(PackedVector3Array([
			_p3(point, 0.0),
			_p3(boundary[(index + 1) % boundary.size()], 0.0),
			_p3(boundary[(index + 1) % boundary.size()], -spec.get_girdle_thickness()),
			_p3(point, -spec.get_girdle_thickness()),
		]), GIRDLE_WALL_ZONE)
		outer_ring.append(_p3(point, -spec.get_girdle_thickness()))
		upper_ring.append(_project_pavilion_point(point, upper_scale, upper_z, rotation_angle))
		lower_ring.append(_project_pavilion_point(point, lower_scale, lower_z, rotation_angle))
	var culet = Vector3(0.0, 0.0, -spec.get_girdle_thickness() - spec.get_pavilion_depth())
	for index in outer_ring.size():
		var next_index = (index + 1) % outer_ring.size()
		model.add_facet(PackedVector3Array([
			outer_ring[index],
			outer_ring[next_index],
			upper_ring[next_index],
			upper_ring[index],
		]), "pavilion")
		model.add_facet(PackedVector3Array([
			upper_ring[index],
			upper_ring[next_index],
			lower_ring[next_index],
			lower_ring[index],
		]), "pavilion")
		model.add_facet(PackedVector3Array([
			lower_ring[index],
			lower_ring[next_index],
			culet,
		]), "culet")


static func _append_outline_single_step_pavilion(
	model,
	boundary: Array[Vector2],
	spec,
	rotation_angle: float,
) -> void:
	if boundary.size() < 3:
		return
	var upper_z = -spec.get_girdle_thickness() - spec.get_pavilion_depth() * spec.get_pavilion_upper_depth_ratio()
	var outer_ring = []
	var upper_ring = []
	for index in boundary.size():
		var point = boundary[index]
		var sharpness = _loop_vertex_sharpness(PackedVector2Array(boundary), index)
		var upper_scale = clampf(spec.get_pavilion_upper_scale() - sharpness * 0.03, 0.18, 0.96)
		model.add_facet(PackedVector3Array([
			_p3(point, 0.0),
			_p3(boundary[(index + 1) % boundary.size()], 0.0),
			_p3(boundary[(index + 1) % boundary.size()], -spec.get_girdle_thickness()),
			_p3(point, -spec.get_girdle_thickness()),
		]), GIRDLE_WALL_ZONE)
		outer_ring.append(_p3(point, -spec.get_girdle_thickness()))
		upper_ring.append(_project_pavilion_point(point, upper_scale, upper_z, rotation_angle))
	var culet = Vector3(0.0, 0.0, -spec.get_girdle_thickness() - spec.get_pavilion_depth())
	for index in outer_ring.size():
		var next_index = (index + 1) % outer_ring.size()
		model.add_facet(PackedVector3Array([
			outer_ring[index],
			outer_ring[next_index],
			upper_ring[next_index],
			upper_ring[index],
		]), "pavilion")
		model.add_facet(PackedVector3Array([
			upper_ring[index],
			upper_ring[next_index],
			culet,
		]), "culet")


static func _append_outline_mirror_crown_pavilion(
	model,
	boundary: Array[Vector2],
	spec,
) -> void:
	if boundary.size() < 3:
		return
	var table: Array[Vector2] = _ensure_loop_array(spec.get_table_points())
	var bezel_facets: Array = spec.get_bezel_facets()
	if table.is_empty() or bezel_facets.is_empty():
		_append_outline_single_step_pavilion(model, boundary, spec, 0.0)
		return
	var girdle_z: float = -spec.get_girdle_thickness()
	var mirrored_table_z: float = girdle_z - spec.get_pavilion_depth()
	for index in boundary.size():
		var point = boundary[index]
		model.add_facet(PackedVector3Array([
			_p3(point, 0.0),
			_p3(boundary[(index + 1) % boundary.size()], 0.0),
			_p3(boundary[(index + 1) % boundary.size()], girdle_z),
			_p3(point, girdle_z),
		]), GIRDLE_WALL_ZONE)
	for polygon in bezel_facets:
		var facet = PackedVector3Array()
		for point in _reverse_loop(_ensure_loop_array(polygon)):
			facet.append(_p3(point, mirrored_table_z if table.has(point) else girdle_z))
		model.add_facet(facet, "pavilion")
	model.add_facet(_polygon3(_reverse_loop(table), mirrored_table_z), "culet")


static func _resolve_ring_heights(spec, ring_count: int) -> PackedFloat32Array:
	var heights = PackedFloat32Array()
	heights.resize(ring_count)
	var ratios = spec.get_crown_ring_height_ratios()
	for i in ring_count:
		var ratio = float(i) / float(maxi(ring_count - 1, 1))
		if i < ratios.size():
			ratio = ratios[i]
		heights[i] = spec.get_crown_height() * ratio
	return heights


static func _resolve_rose_heights(spec, ring_count: int) -> PackedFloat32Array:
	var heights = PackedFloat32Array()
	heights.resize(ring_count)
	var ratios = spec.get_rose_band_height_ratios()
	for i in ring_count:
		var ratio = float(i) / float(maxi(ring_count - 1, 1))
		if i < ratios.size():
			ratio = ratios[i]
		heights[i] = spec.get_crown_height() * ratio
	if ring_count > 0:
		heights[ring_count - 1] = spec.get_crown_height() * spec.get_center_height_ratio()
	return heights


static func _make_model(spec):
	var model = GemCutModelResourceScript.new()
	model.spec_id = spec.spec_id
	model.cut_id = spec.compatibility_cut_id
	model.display_name = spec.display_name
	model.shape_category = spec.shape_category
	model.geometry_signature = spec.build_geometry_signature()
	model.orthographic_top_roll_degrees = spec.get_orthographic_top_roll_degrees()
	model.orthographic_side_yaw_degrees = spec.get_orthographic_side_yaw_degrees()
	model.orthographic_axis_fit_scale = spec.get_orthographic_axis_fit_scale()
	model.crown_height = spec.get_crown_height()
	model.girdle_thickness = spec.get_girdle_thickness()
	model.pavilion_depth = spec.get_pavilion_depth()
	return model


static func _polygon3(points: Array[Vector2], z: float) -> PackedVector3Array:
	var polygon = PackedVector3Array()
	polygon.resize(points.size())
	for i in points.size():
		polygon[i] = _p3(points[i], z)
	return polygon


static func _polygon3_from_height_map(
	points: Array,
	point_heights: Dictionary,
	default_z: float,
) -> PackedVector3Array:
	var polygon = PackedVector3Array()
	polygon.resize(points.size())
	for i in points.size():
		var point = points[i]
		polygon[i] = _p3(point, float(point_heights.get(_point_key(point), default_z)))
	return polygon


static func _loop_to_mesh(points: Array[Vector2], z: float) -> PackedVector3Array:
	var loop = PackedVector3Array()
	loop.resize(points.size())
	for i in points.size():
		loop[i] = _p3(points[i], z)
	return loop


static func _reverse_loop(points: Array[Vector2]) -> Array[Vector2]:
	var reversed_points := points.duplicate()
	reversed_points.reverse()
	return reversed_points


static func _to_float_array(source: Array) -> Array[float]:
	var result: Array[float] = []
	for value in source:
		result.append(float(value))
	return result


static func _ensure_loop_array(points) -> Array[Vector2]:
	var loop: Array[Vector2] = []
	for point in points:
		loop.append(point)
	return loop


static func _packed_to_array(points: PackedVector2Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(point)
	return result


static func _subdivide_loop(loop: Array[Vector2], subdivisions: int) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in loop.size():
		var next := (i + 1) % loop.size()
		for s in subdivisions:
			var t := float(s) / float(subdivisions)
			result.append(loop[i].lerp(loop[next], t))
	return result


static func _scale_loop_about_center(points: Array[Vector2], scale: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(GemCutPrimitivesScript.CENTER + (point - GemCutPrimitivesScript.CENTER) * scale)
	return result


static func _translate_loop(points: Array[Vector2], offset: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(point + offset)
	return result


static func _rotate_loop_about_center(points: Array[Vector2], degrees: float) -> Array[Vector2]:
	var radians := deg_to_rad(degrees)
	var cos_r := cos(radians)
	var sin_r := sin(radians)
	var result: Array[Vector2] = []
	for point in points:
		var delta := point - GemCutPrimitivesScript.CENTER
		result.append(GemCutPrimitivesScript.CENTER + Vector2(
			delta.x * cos_r - delta.y * sin_r,
			delta.x * sin_r + delta.y * cos_r
		))
	return result


static func _apply_named_loop_patches(spec, named_loops: Dictionary) -> Dictionary:
	if spec == null or typeof(spec.patches) != TYPE_ARRAY or spec.patches.is_empty():
		return named_loops
	var patched := {}
	for key in named_loops.keys():
		patched[key] = _ensure_loop_array(named_loops[key])
	for raw_patch in spec.patches:
		if typeof(raw_patch) != TYPE_DICTIONARY:
			continue
		var patch: Dictionary = raw_patch
		var operation := StringName(patch.get("operation", patch.get("op", &"")))
		var targets: Array = patch.get("targets", [])
		if targets.is_empty() and patch.has("target"):
			targets = [patch.get("target")]
		for raw_target in targets:
			var target := String(raw_target)
			if not patched.has(target):
				continue
			match operation:
				&"scale_loop":
					patched[target] = _scale_loop_about_center(
						patched[target],
						float(patch.get("factor", 1.0))
					)
				&"translate_loop":
					patched[target] = _translate_loop(
						patched[target],
						patch.get("offset", Vector2.ZERO)
					)
				&"rotate_loop":
					patched[target] = _rotate_loop_about_center(
						patched[target],
						float(patch.get("degrees", 0.0))
					)
	return patched


static func _stitch_boundary_loop_from_fans(fans: Array) -> Array[Vector2]:
	var segments: Array = []
	for fan in fans:
		segments.append(fan.get("boundary", []))
	return _stitch_boundary_segments(segments)


static func _stitch_boundary_loop_from_bezel_facets(bezel_facets: Array) -> Array[Vector2]:
	var segments: Array = []
	for facet in bezel_facets:
		if facet.size() < 4:
			continue
		var boundary_segment: Array[Vector2] = []
		for i in range(2, facet.size()):
			boundary_segment.append(facet[i])
		boundary_segment.reverse()
		segments.append(boundary_segment)
	return _stitch_boundary_segments(segments)


static func _stitch_boundary_segments(segments: Array) -> Array[Vector2]:
	var loop: Array[Vector2] = []
	for segment in segments:
		if segment.is_empty():
			continue
		for point in segment:
			if loop.is_empty() or not _points_match(loop[loop.size() - 1], point):
				loop.append(point)
	if loop.size() >= 2 and _points_match(loop[0], loop[loop.size() - 1]):
		loop.remove_at(loop.size() - 1)
	return loop


static func _points_match(a: Vector2, b: Vector2, tolerance: float = 0.0001) -> bool:
	return a.distance_squared_to(b) <= tolerance * tolerance


static func _p3(point: Vector2, z: float) -> Vector3:
	return Vector3(point.x - 0.5, 0.5 - point.y, z)


static func _project_pavilion_point(
	point: Vector2,
	scale_factor: float,
	z: float,
	rotation_angle: float,
) -> Vector3:
	var delta = point - GemCutPrimitivesScript.CENTER
	var scaled = delta * scale_factor
	var cos_r = cos(rotation_angle)
	var sin_r = sin(rotation_angle)
	var rotated = Vector2(
		scaled.x * cos_r - scaled.y * sin_r,
		scaled.x * sin_r + scaled.y * cos_r
	)
	return _p3(GemCutPrimitivesScript.CENTER + rotated, z)


static func _register_height_points(point_heights: Dictionary, points: Array[Vector2], z: float) -> void:
	for point in points:
		_set_point_height(point_heights, point, z)


static func _set_point_height(point_heights: Dictionary, point: Vector2, z: float) -> void:
	point_heights[_point_key(point)] = z


static func _point_height_exists(point_heights: Dictionary, point: Vector2) -> bool:
	return point_heights.has(_point_key(point))


static func _point_key(point: Vector2) -> String:
	return "%d:%d" % [
		int(round(point.x * 100000.0)),
		int(round(point.y * 100000.0)),
	]


static func _loop_vertex_sharpness(loop: PackedVector2Array, index: int) -> float:
	if loop.size() < 3:
		return 0.0
	var prev_index = (index - 1 + loop.size()) % loop.size()
	var next_index = (index + 1) % loop.size()
	var incoming = (loop[index] - loop[prev_index]).normalized()
	var outgoing = (loop[next_index] - loop[index]).normalized()
	if incoming.is_zero_approx() or outgoing.is_zero_approx():
		return 0.0
	var turn = clampf((1.0 - incoming.dot(outgoing)) * 0.5, 0.0, 1.0)
	return pow(turn, 0.7)


static func _sample_radial_rings(spec, main_angles: Array[float], half_angles: Array[float]) -> Dictionary:
	var table_ratio = spec.get_table_ratio()
	var star_ratio = lerpf(table_ratio, 1.0, spec.get_star_length())
	return {
		"table_v": _sample_boundary_points(spec, main_angles, table_ratio, false),
		"star_v": _sample_boundary_points(spec, half_angles, star_ratio, true),
		"girdle_m": _sample_boundary_points(spec, main_angles, 1.0, false),
		"girdle_h": _sample_boundary_points(spec, half_angles, 1.0, true),
	}


static func _sample_boundary_points(
	spec,
	angles: Array[float],
	scale: float,
	is_half_point: bool,
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for angle in angles:
		points.append(_sample_boundary_point(spec, scale, angle, is_half_point))
	return points


static func _sample_boundary_point(
	spec,
	scale: float,
	angle: float,
	is_half_point: bool,
) -> Vector2:
	var radius_scale = scale
	if is_half_point:
		radius_scale *= spec.get_half_radius_scale()
	var mode = spec.get_boundary_mode()
	var params = spec.get_boundary_params()
	match mode:
		&"ellipse":
			return GemCutPrimitivesScript.ellipse_point(
				radius_scale * params.get("aspect_x", 1.0),
				radius_scale * params.get("aspect_y", 1.0),
				angle
			)
		&"marquise":
			return GemCutPrimitivesScript.marquise_point(radius_scale, angle, params)
		&"superellipse":
			return GemCutPrimitivesScript.superellipse_point(
				radius_scale,
				angle,
				params.get("exponent", 3.5),
				params.get("aspect_x", 1.0),
				params.get("aspect_y", 1.0)
			)
		&"heart":
			return GemCutPrimitivesScript.heart_point(radius_scale, angle, params)
		&"pear":
			return GemCutPrimitivesScript.pear_point(radius_scale, angle, params)
		&"kite":
			return GemCutPrimitivesScript.kite_point(
				radius_scale * params.get("aspect_x", 1.0),
				radius_scale * params.get("aspect_y", 1.0),
				angle,
				params.get("shoulder", 0.5)
			)
		_:
			return GemCutPrimitivesScript.radial_point(radius_scale, angle)
