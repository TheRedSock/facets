class_name GemCutProfiles
extends RefCounted

## Shape profile definitions for all built-in gem cuts.


# ===========================================================================
#  Radial Brilliant Family
# ===========================================================================


static func classic_round() -> Dictionary:
	return {
		"cut_id": &"classic_round",
		"display_name": "Classic Round Brilliant",
		"shape_category": &"round",
		"sector_count": 8,
		"boundary_mode": &"circle",
		"table_ratio": 0.58,
		"star_length": 0.52,
		"tilts": {"star": 18.0, "bezel": 34.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 8,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 64,
	}


static func old_european_round() -> Dictionary:
	return {
		"cut_id": &"old_european_round",
		"display_name": "Old European Round",
		"shape_category": &"round",
		"sector_count": 10,
		"boundary_mode": &"circle",
		"table_ratio": 0.44,
		"star_length": 0.40,
		"crown_height": 0.24,
		"star_height_ratio": 0.68,
		"pavilion_depth": 0.50,
		"pavilion_ring_height_ratio": 0.56,
		"pavilion_ring_radius_scale": 0.28,
		"tilts": {"star": 22.0, "bezel": 37.0, "girdle": 44.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 72,
	}


static func simple_octagon_step() -> Dictionary:
	var sector_count := 8
	var table := GemCutPrimitives.polygon_points(sector_count, 0.56, -PI * 0.375)
	var outer_angles := GemCutPrimitives.regular_angles(sector_count, -PI * 0.375)
	var arc_segments := 4
	var bezel_facets: Array = []
	var silhouette := GemCutPrimitives.sample_closed_curve(
		GemCutPrimitives.detail_sample_count(sector_count, GemCutPrimitives.DETAIL_HIGH, 64),
		func(angle: float) -> Vector2:
			return GemCutPrimitives.radial_point(1.0, angle)
	)

	for i in sector_count:
		var next_index := (i + 1) % sector_count
		var start_angle: float = outer_angles[i]
		var end_angle: float = outer_angles[next_index]
		if end_angle <= start_angle:
			end_angle += TAU
		var arc_points: Array[Vector2] = []
		for step in arc_segments + 1:
			var t := float(step) / float(arc_segments)
			var angle := start_angle + (end_angle - start_angle) * t
			arc_points.append(GemCutPrimitives.radial_point(1.0, angle))
		arc_points.reverse()
		bezel_facets.append([table[i], table[next_index]] + arc_points)

	return {
		"cut_id": &"simple_octagon_step",
		"display_name": "Simple Round Octagon",
		"shape_category": &"round",
		"table": table,
		"star_facets": [],
		"bezel_facets": bezel_facets,
		"fans": [],
		"tilts": {"bezel": 34.0},
		"silhouette": silhouette,
		"pavilion_rotation_fraction": 0.0,
	}


static func cushion() -> Dictionary:
	return {
		"cut_id": &"cushion",
		"display_name": "Cushion",
		"shape_category": &"square",
		"sector_count": 8,
		"boundary_mode": &"superellipse",
		"boundary_params": {"exponent": 3.6},
		"table_ratio": 0.46,
		"star_length": 0.58,
		"tilts": {"star": 20.0, "bezel": 33.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 8,
		"silhouette_detail": GemCutPrimitives.DETAIL_MEDIUM,
		"silhouette_min_points": 48,
	}


static func opal_cushion() -> Dictionary:
	return {
		"cut_id": &"opal_cushion",
		"display_name": "Opal Cushion",
		"shape_category": &"rectangle",
		"sector_count": 12,
		"boundary_mode": &"superellipse",
		"boundary_params": {
			"exponent": 4.4,
			"aspect_x": 0.90,
			"aspect_y": 1.08,
		},
		"table_ratio": 0.48,
		"star_length": 0.60,
		"half_radius_scale": 0.96,
		"tilts": {"star": 18.0, "bezel": 30.0, "girdle": 44.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 12,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 72,
	}


static func heart_brilliant() -> Dictionary:
	return {
		"cut_id": &"heart_brilliant",
		"display_name": "Heart Brilliant",
		"shape_category": &"heart",
		"sector_count": 10,
		"boundary_mode": &"heart",
		"boundary_params": {
			"width_scale": 0.92,
			"height_scale": 1.02,
		},
		"table_ratio": 0.48,
		"star_length": 0.50,
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 80,
	}


static func trillion() -> Dictionary:
	var corners := GemCutPrimitives.polygon_points(3)
	var center := GemCutPrimitives.CENTER
	var bow_distance := GemCutPrimitives.GEM_RADIUS * 0.22
	var girdle_segments := 8
	var table_ratio := 0.36
	var mid_star_ratio := 0.50
	var star_ratio := 0.64
	var side_midpoints: Array[Vector2] = []
	var boundary_sides: Array = []
	var silhouette := PackedVector2Array()
	var silhouette_segments := int(
		GemCutPrimitives.detail_sample_count(3, GemCutPrimitives.DETAIL_HIGH, 48) / 3.0
	)

	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		var midpoint := corners[i].lerp(corners[next_index], 0.5)
		var control := midpoint + (midpoint - center).normalized() * bow_distance
		side_midpoints.append(GemCutPrimitives.quadratic_bezier_point(corners[i], control, corners[next_index], 0.5))
		boundary_sides.append(GemCutPrimitives.sample_quadratic_bezier(corners[i], control, corners[next_index], girdle_segments))
		for point in GemCutPrimitives.sample_quadratic_bezier(corners[i], control, corners[next_index], silhouette_segments, false):
			silhouette.append(point)

	var table := GemCutPrimitives.scale_points(corners, table_ratio)
	var mid_star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		mid_star_points.append(center + (midpoint - center) * mid_star_ratio)
	var star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		star_points.append(center + (midpoint - center) * star_ratio)

	# Inner star ring: shallow tilt, between table edge and mid-star line.
	var inner_star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		inner_star_facets.append([table[i], mid_star_points[i], table[next_index]])

	# Outer star ring: steeper tilt, between mid-star and star points.
	var star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		star_facets.append([table[i], star_points[i], mid_star_points[i]])
		star_facets.append([mid_star_points[i], star_points[i], table[next_index]])

	var bezel_facets: Array = []
	for i in corners.size():
		var prev_index := (i - 1 + corners.size()) % corners.size()
		bezel_facets.append([star_points[prev_index], table[i], star_points[i], corners[i]])

	var fans: Array = []
	for i in corners.size():
		fans.append({
			"apex": star_points[i],
			"boundary": boundary_sides[i],
		})

	return {
		"cut_id": &"trillion",
		"display_name": "Trillion",
		"shape_category": &"triangle",
		"table": table,
		"inner_star_facets": inner_star_facets,
		"star_facets": star_facets,
		"bezel_facets": bezel_facets,
		"fans": fans,
		"tilts": {"inner_star": 11.0, "star": 21.0, "bezel": 34.0, "girdle": 42.0},
		"silhouette": silhouette,
	}


static func straight_trillion() -> Dictionary:
	var corners := GemCutPrimitives.polygon_points(3)
	var center := GemCutPrimitives.CENTER
	var girdle_segments := 3
	var table_ratio := 0.34
	var mid_star_ratio := 0.47
	var star_ratio := 0.60
	var side_midpoints: Array[Vector2] = []
	var boundary_sides: Array = []

	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		var midpoint := corners[i].lerp(corners[next_index], 0.5)
		side_midpoints.append(midpoint)
		boundary_sides.append(GemCutPrimitives.sample_line_segment(corners[i], corners[next_index], girdle_segments))

	var table := GemCutPrimitives.scale_points(corners, table_ratio)
	var mid_star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		mid_star_points.append(center + (midpoint - center) * mid_star_ratio)
	var star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		star_points.append(center + (midpoint - center) * star_ratio)

	# Inner star ring: shallow tilt (12 deg), sits between table edge and
	# the mid-star line.  These facets are nearly table-flat, so they catch
	# specular at a very different angle than the outer star ring.
	var inner_star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		inner_star_facets.append([table[i], mid_star_points[i], table[next_index]])

	# Outer star ring: steeper tilt (22 deg), between mid-star and star
	# points.  Two triangles per side to fill the quad region.
	var star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		star_facets.append([table[i], star_points[i], mid_star_points[i]])
		star_facets.append([mid_star_points[i], star_points[i], table[next_index]])

	var bezel_facets: Array = []
	for i in corners.size():
		var prev_index := (i - 1 + corners.size()) % corners.size()
		bezel_facets.append([star_points[prev_index], table[i], star_points[i], corners[i]])

	var fans: Array = []
	for i in corners.size():
		fans.append({
			"apex": star_points[i],
			"boundary": boundary_sides[i],
		})

	return {
		"cut_id": &"straight_trillion",
		"display_name": "Straight Trillion",
		"shape_category": &"triangle",
		"table": table,
		"inner_star_facets": inner_star_facets,
		"star_facets": star_facets,
		"bezel_facets": bezel_facets,
		"fans": fans,
		"tilts": {"inner_star": 12.0, "star": 22.0, "bezel": 34.0, "girdle": 42.0},
		"silhouette": GemCutPrimitives.pva(corners),
	}


static func princess_square() -> Dictionary:
	return {
		"cut_id": &"princess_square",
		"display_name": "Princess Square",
		"shape_category": &"square",
		"outer_points": GemCutPrimitives.rect_points(GemCutPrimitives.GEM_RADIUS, GemCutPrimitives.GEM_RADIUS),
		"table_ratio": 0.38,
		"edge_trim": 0.2,
		"tilts": {"star": 18.0, "bezel": 35.0, "girdle": 42.0, "corner": 46.0},
		"orientation_fit_axis_aligned_scale": 0.94,
	}


static func lozenge() -> Dictionary:
	var x_radius := 0.56
	var y_radius := 1.0
	var rings := [
		GemCutPrimitives.diamond_points(x_radius, y_radius),
		GemCutPrimitives.diamond_points(x_radius * 0.78, y_radius * 0.78),
		GemCutPrimitives.diamond_points(x_radius * 0.60, y_radius * 0.60),
		GemCutPrimitives.diamond_points(x_radius * 0.42, y_radius * 0.42),
		GemCutPrimitives.diamond_points(x_radius * 0.26, y_radius * 0.26),
	]
	return {
		"cut_id": &"lozenge",
		"display_name": "Lozenge",
		"shape_category": &"diamond",
		"rings": rings,
		"ring_tilts": [41.0, 30.0, 20.0, 11.0, 0.0],
		"ring_zones": ["girdle", "step", "step", "step", "table"],
		"silhouette": GemCutPrimitives.pva(rings[0]),
		"pavilion_rotation_fraction": 0.0,
	}


static func kite_brilliant() -> Dictionary:
	return {
		"cut_id": &"kite_brilliant",
		"display_name": "Kite Brilliant",
		"shape_category": &"kite",
		"sector_count": 8,
		"boundary_mode": &"kite",
		"boundary_params": {"aspect_x": 0.62, "aspect_y": 1.0, "shoulder": 0.30},
		"table_ratio": 0.46,
		"star_length": 0.54,
		"tilts": {"star": 20.0, "bezel": 35.0, "girdle": 43.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 8,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 48,
	}


static func radiant_square() -> Dictionary:
	return {
		"cut_id": &"radiant_square",
		"display_name": "Radiant Square",
		"shape_category": &"square",
		"outer_points": GemCutPrimitives.chamfered_rect_points(
			GemCutPrimitives.GEM_RADIUS * 0.96,
			GemCutPrimitives.GEM_RADIUS * 0.96,
			0.14
		),
		"table_ratio": 0.44,
		"break_ratio": 0.52,
		"tilts": {"star": 18.0, "bezel": 35.0},
		"orientation_fit_axis_aligned_scale": 0.95,
	}


static func radiant_octagon() -> Dictionary:
	return {
		"cut_id": &"radiant_octagon",
		"display_name": "Radiant Octagon",
		"shape_category": &"octagon",
		"outer_points": GemCutPrimitives.chamfered_rect_points(
			GemCutPrimitives.GEM_RADIUS * 0.88,
			GemCutPrimitives.GEM_RADIUS,
			0.26
		),
		"table_ratio": 0.46,
		"break_ratio": 0.5,
		"tilts": {"star": 19.0, "bezel": 34.0},
	}


static func hex_brilliant() -> Dictionary:
	return {
		"cut_id": &"hex_brilliant",
		"display_name": "Hex Brilliant",
		"shape_category": &"hexagon",
		"sector_count": 6,
		"boundary_mode": &"circle",
		"table_ratio": 0.52,
		"star_length": 0.48,
		"half_radius_scale": cos(PI / 6.0),
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"polygon",
	}


static func pentagon_brilliant() -> Dictionary:
	return {
		"cut_id": &"pentagon_brilliant",
		"display_name": "Pentagon Brilliant",
		"shape_category": &"pentagon",
		"sector_count": 5,
		"boundary_mode": &"circle",
		"table_ratio": 0.52,
		"star_length": 0.48,
		"half_radius_scale": cos(PI / 5.0),
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"polygon",
	}


static func emerald_step() -> Dictionary:
	return _step_profile_from_chamfered_rect(
		&"emerald_step",
		"Emerald Step",
		&"rectangle",
		1.35,
		0.24,
		[1.0, 0.68, 0.40],
		[40.0, 24.0, 0.0]
	)


static func asscher_step() -> Dictionary:
	return _step_profile_from_chamfered_rect(
		&"asscher_step",
		"Asscher Step",
		&"square",
		1.0,
		0.22,
		[1.0, 0.74, 0.45],
		[38.0, 22.0, 0.0]
	)


static func octagon_step() -> Dictionary:
	return _step_profile_from_chamfered_rect(
		&"octagon_step",
		"Octagon Step",
		&"octagon",
		1.18,
		0.30,
		[1.0, 0.74, 0.46],
		[39.0, 23.0, 0.0]
	)


static func baguette_step() -> Dictionary:
	return _step_profile_from_rect(
		&"baguette_step",
		"Baguette Step",
		&"rectangle",
		GemCutPrimitives.GEM_RADIUS / 2.8,
		GemCutPrimitives.GEM_RADIUS,
		[1.0, 0.72, 0.44],
		[38.0, 22.0, 0.0]
	)


static func tapered_baguette_step() -> Dictionary:
	var rings := [
		GemCutPrimitives.tapered_rect_points(
			GemCutPrimitives.GEM_RADIUS / 4.0,
			GemCutPrimitives.GEM_RADIUS / 2.2,
			GemCutPrimitives.GEM_RADIUS
		),
		GemCutPrimitives.tapered_rect_points(
			GemCutPrimitives.GEM_RADIUS / 5.6,
			GemCutPrimitives.GEM_RADIUS / 3.1,
			GemCutPrimitives.GEM_RADIUS * 0.72
		),
		GemCutPrimitives.tapered_rect_points(
			GemCutPrimitives.GEM_RADIUS / 8.8,
			GemCutPrimitives.GEM_RADIUS / 4.6,
			GemCutPrimitives.GEM_RADIUS * 0.44
		),
	]
	return {
		"cut_id": &"tapered_baguette_step",
		"display_name": "Tapered Baguette Step",
		"shape_category": &"tapered_rectangle",
		"rings": rings,
		"ring_tilts": [38.0, 22.0, 0.0],
		"ring_zones": ["girdle", "step", "table"],
		"silhouette": GemCutPrimitives.pva(rings[0]),
	}


static func oval_brilliant() -> Dictionary:
	return {
		"cut_id": &"oval_brilliant",
		"display_name": "Oval Brilliant",
		"shape_category": &"oval",
		"sector_count": 8,
		"boundary_mode": &"ellipse",
		"boundary_params": {"aspect_x": 0.80, "aspect_y": 1.10},
		"table_ratio": 0.56,
		"star_length": 0.53,
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 8,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 64,
	}


static func antique_oval() -> Dictionary:
	return {
		"cut_id": &"antique_oval",
		"display_name": "Antique Oval",
		"shape_category": &"oval",
		"sector_count": 10,
		"boundary_mode": &"ellipse",
		"boundary_params": {"aspect_x": 0.76, "aspect_y": 1.14},
		"table_ratio": 0.46,
		"star_length": 0.44,
		"tilts": {"star": 20.0, "bezel": 35.0, "girdle": 43.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 72,
	}


static func marquise_brilliant() -> Dictionary:
	return {
		"cut_id": &"marquise_brilliant",
		"display_name": "Marquise Brilliant",
		"shape_category": &"marquise",
		"sector_count": 10,
		"boundary_mode": &"marquise",
		"boundary_params": {
			"half_width": 0.60,
			"half_height": 1.20,
			"shoulder_roundness": 0.90,
			"tip_power": 0.70,
		},
		"table_ratio": 0.48,
		"star_length": 0.50,
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 80,
	}


static func pear_brilliant() -> Dictionary:
	return {
		"cut_id": &"pear_brilliant",
		"display_name": "Pear Brilliant",
		"shape_category": &"pear",
		"sector_count": 10,
		"boundary_mode": &"pear",
		"boundary_params": {
			"shoulder_bias": 0.80,
			"tip_power": 0.74,
			"y_stretch": 1.17,
			"shift_y": 0.055,
		},
		"table_ratio": 0.50,
		"star_length": 0.52,
		"tilts": {"star": 18.0, "bezel": 32.0, "girdle": 42.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 64,
	}


# ===========================================================================
#  Rose Family
# ===========================================================================


static func rose_round() -> Dictionary:
	var rings := [
		GemCutPrimitives.polygon_points(8),
		GemCutPrimitives.polygon_points(8, 0.34, -PI * 0.5 + PI / 8.0),
	]
	return {
		"cut_id": &"rose_round",
		"display_name": "Rose Round",
		"shape_category": &"round",
		"rings": rings,
		"band_tilts": [36.0],
		"center_tilt": 10.0,
		"silhouette": GemCutPrimitives.circle_outline(64),
	}


static func half_dutch_rose_hex() -> Dictionary:
	var rings := [
		GemCutPrimitives.polygon_points(6),
		GemCutPrimitives.polygon_points(6, 0.40, -PI * 0.5 + PI / 6.0),
	]
	return {
		"cut_id": &"half_dutch_rose_hex",
		"display_name": "Half Dutch Rose Hex",
		"shape_category": &"hexagon",
		"rings": rings,
		"band_tilts": [35.0],
		"center_tilt": 9.0,
		"silhouette": GemCutPrimitives.pva(rings[0]),
	}


static func double_rose() -> Dictionary:
	var rings := [
		GemCutPrimitives.polygon_points(8),
		GemCutPrimitives.polygon_points(8, 0.58, -PI * 0.5 + PI / 8.0),
		GemCutPrimitives.polygon_points(8, 0.24),
	]
	return {
		"cut_id": &"double_rose",
		"display_name": "Double Rose",
		"shape_category": &"round",
		"rings": rings,
		"band_tilts": [34.0, 20.0],
		"center_tilt": 10.0,
		"silhouette": GemCutPrimitives.circle_outline(64),
	}


static func cross_rose() -> Dictionary:
	var rings := [
		GemCutPrimitives.polygon_points(8),
		GemCutPrimitives.alternating_ring_points(8, 0.36, 0.22),
	]
	return {
		"cut_id": &"cross_rose",
		"display_name": "Cross Rose",
		"shape_category": &"round",
		"rings": rings,
		"band_tilts": [35.0],
		"center_tilt": 9.0,
		"silhouette": GemCutPrimitives.circle_outline(64),
	}


# ===========================================================================
#  Helpers
# ===========================================================================


static func _step_profile_from_chamfered_rect(
	cut_id: StringName,
	display_name: String,
	shape_category: StringName,
	aspect: float,
	chamfer_ratio: float,
	ring_scales: Array[float],
	ring_tilts: Array[float],
) -> Dictionary:
	var half_width := GemCutPrimitives.GEM_RADIUS / aspect
	var half_height := GemCutPrimitives.GEM_RADIUS
	var rings: Array = []
	for scale in ring_scales:
		rings.append(GemCutPrimitives.chamfered_rect_points(
			half_width * scale,
			half_height * scale,
			chamfer_ratio
		))
	return {
		"cut_id": cut_id,
		"display_name": display_name,
		"shape_category": shape_category,
		"rings": rings,
		"ring_tilts": ring_tilts,
		"ring_zones": ["girdle", "step", "table"],
		"silhouette": GemCutPrimitives.pva(rings[0]),
	}


static func _step_profile_from_rect(
	cut_id: StringName,
	display_name: String,
	shape_category: StringName,
	half_width: float,
	half_height: float,
	ring_scales: Array[float],
	ring_tilts: Array[float],
) -> Dictionary:
	var rings: Array = []
	for scale in ring_scales:
		rings.append(GemCutPrimitives.rect_points(half_width * scale, half_height * scale))
	return {
		"cut_id": cut_id,
		"display_name": display_name,
		"shape_category": shape_category,
		"rings": rings,
		"ring_tilts": ring_tilts,
		"ring_zones": ["girdle", "step", "table"],
		"silhouette": GemCutPrimitives.pva(rings[0]),
	}
