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
		"tilts": {"star": 22.0, "bezel": 37.0, "girdle": 44.0},
		"silhouette_mode": &"curve",
		"silhouette_symmetry": 10,
		"silhouette_detail": GemCutPrimitives.DETAIL_HIGH,
		"silhouette_min_points": 72,
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
	var girdle_segments := 4
	var table_ratio := 0.36
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
	var star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		star_points.append(center + (midpoint - center) * star_ratio)

	var star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		star_facets.append([table[i], star_points[i], table[next_index]])

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
		"star_facets": star_facets,
		"bezel_facets": bezel_facets,
		"fans": fans,
		"tilts": {"star": 18.0, "bezel": 34.0, "girdle": 42.0},
		"silhouette": silhouette,
	}


static func straight_trillion() -> Dictionary:
	var corners := GemCutPrimitives.polygon_points(3)
	var center := GemCutPrimitives.CENTER
	var girdle_segments := 3
	var table_ratio := 0.34
	var star_ratio := 0.60
	var side_midpoints: Array[Vector2] = []
	var boundary_sides: Array = []

	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		var midpoint := corners[i].lerp(corners[next_index], 0.5)
		side_midpoints.append(midpoint)
		boundary_sides.append(GemCutPrimitives.sample_line_segment(corners[i], corners[next_index], girdle_segments))

	var table := GemCutPrimitives.scale_points(corners, table_ratio)
	var star_points: Array[Vector2] = []
	for midpoint in side_midpoints:
		star_points.append(center + (midpoint - center) * star_ratio)

	var star_facets: Array = []
	for i in corners.size():
		var next_index := (i + 1) % corners.size()
		star_facets.append([table[i], star_points[i], table[next_index]])

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
		"star_facets": star_facets,
		"bezel_facets": bezel_facets,
		"fans": fans,
		"tilts": {"star": 19.0, "bezel": 34.0, "girdle": 42.0},
		"silhouette": GemCutPrimitives.pva(corners),
	}


static func radiant_diamond() -> Dictionary:
	return {
		"cut_id": &"radiant_diamond",
		"display_name": "Radiant Diamond",
		"shape_category": &"rotated_square",
		"table_ratio": 0.38,
		"break_ratio": 0.5,
		"tilts": {"star": 20.0, "bezel": 35.0},
	}


static func princess_square() -> Dictionary:
	return {
		"cut_id": &"princess_square",
		"display_name": "Princess Square",
		"shape_category": &"square",
		"outer_points": GemCutPrimitives.polygon_points(4, 1.0, -PI * 0.25),
		"table_ratio": 0.48,
		"break_ratio": 0.5,
		"tilts": {"star": 20.0, "bezel": 35.0},
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
