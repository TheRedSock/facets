class_name GemCutBuilders
extends RefCounted

## Shared topology builders for procedural gem cuts.

const GemCutPrimitives = preload("res://core/visuals/gem_cut_primitives.gd")


static func build_radial_brilliant(profile: Dictionary) -> GemCutResource:
	var cut := _make_cut(profile)
	var main_angles: Array[float] = profile.get("main_angles", GemCutPrimitives.regular_angles(
		profile.get("sector_count", 8),
		profile.get("rotation", -PI * 0.5)
	))
	var half_ring_angles: Array[float] = profile.get("half_angles", GemCutPrimitives.half_angles(main_angles))
	var rings := _sample_radial_rings(profile, main_angles, half_ring_angles)
	_add_standard_brilliant_facets(cut, rings, profile.get("tilts", {}))
	cut.silhouette = _build_radial_silhouette(profile, rings["girdle_m"])
	return finalize_cut(cut)


static func build_step_cut(profile: Dictionary) -> GemCutResource:
	var cut := _make_cut(profile)
	var rings: Array = profile.get("rings", [])
	var ring_tilts: Array = profile.get("ring_tilts", [])
	var ring_zones: Array = profile.get("ring_zones", [])
	if rings.is_empty():
		return cut

	var table_ring: Array[Vector2] = rings[rings.size() - 1]
	var table_zone: String = ring_zones[rings.size() - 1] if ring_zones.size() >= rings.size() else "table"
	cut.add_facet(GemCutPrimitives.pva(table_ring), Vector3(0, 0, 1), table_zone)

	for ring_index in rings.size() - 1:
		var outer: Array[Vector2] = rings[ring_index]
		var inner: Array[Vector2] = rings[ring_index + 1]
		var tilt: float = ring_tilts[ring_index] if ring_index < ring_tilts.size() else 0.0
		var zone: String = ring_zones[ring_index] if ring_index < ring_zones.size() else "step"
		for i in outer.size():
			var next_index := (i + 1) % outer.size()
			var quad := GemCutPrimitives.pva([inner[i], inner[next_index], outer[next_index], outer[i]])
			cut.add_facet(quad, GemCutPrimitives.normal_for(GemCutPrimitives.centroid_pva(quad), tilt), zone)

	cut.silhouette = profile.get("silhouette", GemCutPrimitives.pva(rings[0]))
	return finalize_cut(cut)


static func build_fan_cut(profile: Dictionary) -> GemCutResource:
	var cut := _make_cut(profile)
	var table: Array[Vector2] = profile.get("table", [])
	var star_facets: Array = profile.get("star_facets", [])
	var bezel_facets: Array = profile.get("bezel_facets", [])
	var fans: Array = profile.get("fans", [])
	var tilts: Dictionary = profile.get("tilts", {})

	cut.add_facet(GemCutPrimitives.pva(table), Vector3(0, 0, 1), "table")

	for facet_points in star_facets:
		var facet := GemCutPrimitives.pva(facet_points)
		cut.add_facet(facet, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(facet),
			tilts.get("star", 18.0)
		), "star")

	for facet_points in bezel_facets:
		var facet := GemCutPrimitives.pva(facet_points)
		cut.add_facet(facet, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(facet),
			tilts.get("bezel", 32.0)
		), "bezel")

	for fan in fans:
		var apex: Vector2 = fan["apex"]
		var boundary: Array[Vector2] = fan["boundary"]
		for i in boundary.size() - 1:
			var tri := GemCutPrimitives.pva([apex, boundary[i], boundary[i + 1]])
			cut.add_facet(tri, GemCutPrimitives.normal_for(
				GemCutPrimitives.centroid_pva(tri),
				tilts.get("girdle", 42.0)
			), "girdle")

	cut.silhouette = profile.get("silhouette", PackedVector2Array())
	return finalize_cut(cut)


static func build_radiant_cut(profile: Dictionary) -> GemCutResource:
	var cut := _make_cut(profile)
	var outer: Array[Vector2] = []
	if profile.has("outer_points"):
		outer = profile["outer_points"]
	else:
		outer = GemCutPrimitives.diamond_points(profile.get("x_radius", 1.0), profile.get("y_radius", 1.0))
	var table := GemCutPrimitives.scale_points(outer, profile.get("table_ratio", 0.36))
	var break_ratio: float = profile.get("break_ratio", 0.5)
	var outer_breaks: Array[Vector2] = []
	var table_breaks: Array[Vector2] = []
	var count := outer.size()
	var tilts: Dictionary = profile.get("tilts", {})

	for i in count:
		var next_index := (i + 1) % count
		outer_breaks.append(GemCutPrimitives.point_on_segment(outer[i], outer[next_index], break_ratio))
		table_breaks.append(GemCutPrimitives.point_on_segment(table[i], table[next_index], break_ratio))

	cut.add_facet(GemCutPrimitives.pva(table), Vector3(0, 0, 1), "table")

	for i in count:
		var prev_index := (i - 1 + count) % count
		var kite := GemCutPrimitives.pva([table[i], outer_breaks[prev_index], outer[i], outer_breaks[i]])
		cut.add_facet(kite, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(kite),
			tilts.get("bezel", 34.0)
		), "bezel")

		var left_star := GemCutPrimitives.pva([table_breaks[prev_index], table[i], outer_breaks[prev_index]])
		cut.add_facet(left_star, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(left_star),
			tilts.get("star", 20.0)
		), "star")

		var right_star := GemCutPrimitives.pva([table_breaks[i], outer_breaks[i], table[i]])
		cut.add_facet(right_star, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(right_star),
			tilts.get("star", 20.0)
		), "star")

	cut.silhouette = profile.get("silhouette", GemCutPrimitives.pva(outer))
	return finalize_cut(cut)


static func build_rose_cut(profile: Dictionary) -> GemCutResource:
	var cut := _make_cut(profile)
	var rings: Array = profile.get("rings", [])
	var band_tilts: Array = profile.get("band_tilts", [])
	var center_tilt: float = profile.get("center_tilt", 8.0)
	if rings.is_empty():
		return cut

	if rings.size() == 1:
		var center_point: Vector2 = profile.get("center_point", GemCutPrimitives.CENTER)
		var outer_ring: Array[Vector2] = rings[0]
		for i in outer_ring.size():
			var next_index := (i + 1) % outer_ring.size()
			var tri := GemCutPrimitives.pva([center_point, outer_ring[i], outer_ring[next_index]])
			cut.add_facet(tri, GemCutPrimitives.normal_for(
				GemCutPrimitives.centroid_pva(tri),
				band_tilts[0] if not band_tilts.is_empty() else 36.0
			), "rose")
	else:
		for band_index in rings.size() - 1:
			var outer_ring: Array[Vector2] = rings[band_index]
			var inner_ring: Array[Vector2] = rings[band_index + 1]
			var tilt: float = band_tilts[band_index] if band_index < band_tilts.size() else 36.0
			if outer_ring.size() != inner_ring.size():
				push_warning("GemCutBuilders: Rose bands require matching point counts")
				continue
			for i in outer_ring.size():
				var next_index := (i + 1) % outer_ring.size()
				var tri_a := GemCutPrimitives.pva([inner_ring[i], outer_ring[i], outer_ring[next_index]])
				cut.add_facet(tri_a, GemCutPrimitives.normal_for(
					GemCutPrimitives.centroid_pva(tri_a),
					tilt
				), "rose")
				var tri_b := GemCutPrimitives.pva([inner_ring[i], outer_ring[next_index], inner_ring[next_index]])
				cut.add_facet(tri_b, GemCutPrimitives.normal_for(
					GemCutPrimitives.centroid_pva(tri_b),
					tilt
				), "rose")

		var center_ring: Array[Vector2] = rings[rings.size() - 1]
		if center_ring.size() >= 3:
			var center_facet := GemCutPrimitives.pva(center_ring)
			cut.add_facet(center_facet, GemCutPrimitives.normal_for(
				GemCutPrimitives.centroid_pva(center_facet),
				center_tilt
			), "rose_center")

	cut.silhouette = profile.get("silhouette", GemCutPrimitives.pva(rings[0]))
	return finalize_cut(cut)


static func finalize_cut(cut: GemCutResource) -> GemCutResource:
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


static func sample_profile_outline(profile: Dictionary, sample_count: int) -> PackedVector2Array:
	return GemCutPrimitives.sample_closed_curve(
		sample_count,
		func(angle: float) -> Vector2:
			return _sample_boundary_point(profile, 1.0, angle, false),
		profile.get("rotation", -PI * 0.5)
	)


static func _make_cut(profile: Dictionary) -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = profile.get("cut_id", &"")
	cut.display_name = profile.get("display_name", "")
	cut.shape_category = profile.get("shape_category", &"")
	return cut


static func _sample_radial_rings(profile: Dictionary, main_angles: Array[float], half_angles: Array[float]) -> Dictionary:
	var table_ratio: float = profile.get("table_ratio", 0.5)
	var star_ratio: float = profile.get("star_ratio", lerpf(table_ratio, 1.0, profile.get("star_length", 0.55)))
	return {
		"table_v": _sample_boundary_points(profile, main_angles, table_ratio, false),
		"star_v": _sample_boundary_points(profile, half_angles, star_ratio, true),
		"girdle_m": _sample_boundary_points(profile, main_angles, 1.0, false),
		"girdle_h": _sample_boundary_points(profile, half_angles, 1.0, true),
	}


static func _sample_boundary_points(
	profile: Dictionary,
	angles: Array[float],
	scale: float,
	is_half_point: bool,
) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for angle in angles:
		points.append(_sample_boundary_point(profile, scale, angle, is_half_point))
	return points


static func _sample_boundary_point(
	profile: Dictionary,
	scale: float,
	angle: float,
	is_half_point: bool,
) -> Vector2:
	if is_half_point and profile.has("half_point_sampler"):
		return profile["half_point_sampler"].call(scale, angle)
	if profile.has("point_sampler"):
		return profile["point_sampler"].call(scale, angle)

	var radius_scale := scale
	if is_half_point:
		radius_scale *= profile.get("half_radius_scale", 1.0)

	var mode: StringName = profile.get("boundary_mode", &"circle")
	var params: Dictionary = profile.get("boundary_params", {})
	match mode:
		&"ellipse":
			return GemCutPrimitives.ellipse_point(
				radius_scale * params.get("aspect_x", 1.0),
				radius_scale * params.get("aspect_y", 1.0),
				angle
			)
		&"marquise":
			return GemCutPrimitives.marquise_point(radius_scale, angle, params)
		&"superellipse":
			return GemCutPrimitives.superellipse_point(radius_scale, angle, params.get("exponent", 3.5))
		&"heart":
			return GemCutPrimitives.heart_point(radius_scale, angle, params)
		&"pear":
			return GemCutPrimitives.pear_point(radius_scale, angle, params)
		_:
			return GemCutPrimitives.radial_point(radius_scale, angle)


static func _build_radial_silhouette(profile: Dictionary, main_ring: Array[Vector2]) -> PackedVector2Array:
	var mode: StringName = profile.get("silhouette_mode", &"polygon")
	if mode == &"polygon":
		return GemCutPrimitives.pva(main_ring)

	var symmetry_points: int = profile.get("silhouette_symmetry", max(3, main_ring.size()))
	var detail: int = profile.get("silhouette_detail", GemCutPrimitives.DETAIL_HIGH)
	var minimum: int = profile.get("silhouette_min_points", 24)
	var sample_count := GemCutPrimitives.detail_sample_count(symmetry_points, detail, minimum)
	return sample_profile_outline(profile, sample_count)


static func _add_standard_brilliant_facets(cut: GemCutResource, rings: Dictionary, tilts: Dictionary) -> void:
	var table_v: Array[Vector2] = rings["table_v"]
	var star_v: Array[Vector2] = rings["star_v"]
	var girdle_m: Array[Vector2] = rings["girdle_m"]
	var girdle_h: Array[Vector2] = rings["girdle_h"]
	var count := table_v.size()

	cut.add_facet(GemCutPrimitives.pva(table_v), Vector3(0, 0, 1), "table")

	for i in count:
		var next_index := (i + 1) % count
		var star := GemCutPrimitives.pva([table_v[i], star_v[i], table_v[next_index]])
		cut.add_facet(star, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(star),
			tilts.get("star", 18.0)
		), "star")

	for i in count:
		var prev_index := (i - 1 + count) % count
		var bezel := GemCutPrimitives.pva([star_v[prev_index], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(bezel, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(bezel),
			tilts.get("bezel", 32.0)
		), "bezel")

	for i in count:
		var next_index := (i + 1) % count
		var left_girdle := GemCutPrimitives.pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(left_girdle, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(left_girdle),
			tilts.get("girdle", 42.0)
		), "girdle")

		var right_girdle := GemCutPrimitives.pva([star_v[i], girdle_h[i], girdle_m[next_index]])
		cut.add_facet(right_girdle, GemCutPrimitives.normal_for(
			GemCutPrimitives.centroid_pva(right_girdle),
			tilts.get("girdle", 42.0)
		), "girdle")


static func _normalize_to_fit(cut: GemCutResource) -> void:
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)

	for poly in cut.facet_vertices:
		for vertex in poly:
			min_pt = Vector2(minf(min_pt.x, vertex.x), minf(min_pt.y, vertex.y))
			max_pt = Vector2(maxf(max_pt.x, vertex.x), maxf(max_pt.y, vertex.y))
	for vertex in cut.silhouette:
		min_pt = Vector2(minf(min_pt.x, vertex.x), minf(min_pt.y, vertex.y))
		max_pt = Vector2(maxf(max_pt.x, vertex.x), maxf(max_pt.y, vertex.y))
	for segment in cut.edge_segments:
		for vertex in segment:
			min_pt = Vector2(minf(min_pt.x, vertex.x), minf(min_pt.y, vertex.y))
			max_pt = Vector2(maxf(max_pt.x, vertex.x), maxf(max_pt.y, vertex.y))

	if min_pt.x >= max_pt.x or min_pt.y >= max_pt.y:
		return

	var current_center := (min_pt + max_pt) * 0.5
	var extent := max_pt - min_pt
	var target_size := 1.0 - 2.0 * GemCutPrimitives.FIT_MARGIN
	var scale_factor := target_size / maxf(extent.x, extent.y)
	var transform := func(vertex: Vector2) -> Vector2:
		return (vertex - current_center) * scale_factor + GemCutPrimitives.CENTER

	for i in cut.facet_vertices.size():
		var poly := cut.facet_vertices[i]
		var new_poly := PackedVector2Array()
		new_poly.resize(poly.size())
		for j in poly.size():
			new_poly[j] = transform.call(poly[j])
		cut.facet_vertices[i] = new_poly

	var new_silhouette := PackedVector2Array()
	new_silhouette.resize(cut.silhouette.size())
	for i in cut.silhouette.size():
		new_silhouette[i] = transform.call(cut.silhouette[i])
	cut.silhouette = new_silhouette

	var new_edges: Array[PackedVector2Array] = []
	for segment in cut.edge_segments:
		var new_segment := PackedVector2Array()
		new_segment.resize(segment.size())
		for i in segment.size():
			new_segment[i] = transform.call(segment[i])
		new_edges.append(new_segment)
	cut.edge_segments = new_edges


static func _collect_edges(cut: GemCutResource) -> void:
	var seen := {}
	for facet_index in cut.facet_count():
		var vertices := cut.facet_vertices[facet_index]
		for i in vertices.size():
			var a := vertices[i]
			var b := vertices[(i + 1) % vertices.size()]
			var key := _edge_key(a, b)
			if not seen.has(key):
				seen[key] = true
				cut.add_edge(a, b)


static func _edge_key(a: Vector2, b: Vector2) -> String:
	var ax: float = snapped(a.x, 0.0001)
	var ay: float = snapped(a.y, 0.0001)
	var bx: float = snapped(b.x, 0.0001)
	var by: float = snapped(b.y, 0.0001)
	if ax < bx or (ax == bx and ay < by):
		return "%s,%s-%s,%s" % [ax, ay, bx, by]
	return "%s,%s-%s,%s" % [bx, by, ax, ay]
