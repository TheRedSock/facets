extends SceneTree

## Projection-focused regression checks for the canonical 3D cut pipeline.
## Run from command line: godot --headless --script tests/test_gem_cuts.gd

const GemCutGenerators = preload("res://core/visuals/gem_cut_generators.gd")
const GemCutPrimitives = preload("res://core/visuals/gem_cut_primitives.gd")

const CUT_IDS: Array[StringName] = [
	&"classic_round",
	&"old_european_round",
	&"simple_octagon_step",
	&"cushion",
	&"opal_cushion",
	&"patterned_cushion",
	&"heart_brilliant",
	&"trillion",
	&"straight_trillion",
	&"princess_square",
	&"lozenge",
	&"lozenge_radiant",
	&"kite_brilliant",
	&"shield_brilliant",
	&"radiant_square",
	&"radiant_octagon",
	&"hex_brilliant",
	&"hexagon_step",
	&"pentagon_brilliant",
	&"emerald_step",
	&"asscher_step",
	&"octagon_step",
	&"baguette_step",
	&"tapered_baguette_step",
	&"oval_brilliant",
	&"antique_oval",
	&"marquise_brilliant",
	&"pear_brilliant",
	&"rose_round",
	&"half_dutch_rose_hex",
	&"double_rose",
	&"cross_rose",
]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== Gem Cut Projection Tests ===\n")
	test_generate_all_projected_cuts()
	test_geometry_bounds_and_alignment()
	test_no_degenerate_facets()
	test_pavilion_overlay_integrity()
	test_projection_distinctiveness()
	test_rotation_variant_size_compensation()
	test_clip_polygon_winding_independence()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_generate_all_projected_cuts() -> void:
	for cut_id in CUT_IDS:
		var cut = GemCutGenerators.generate_from_spec_id(cut_id)
		assert_true(cut != null, "%s should generate a projected cut resource" % str(cut_id))
		if cut == null:
			continue
		assert_eq(cut.spec_id, cut_id, "%s should preserve its spec_id" % str(cut_id))
		assert_eq(cut.facet_vertices.size(), cut.facet_normals.size(), "%s facet normals align" % str(cut_id))
		assert_eq(cut.facet_vertices.size(), cut.facet_zones.size(), "%s facet zones align" % str(cut_id))
		assert_eq(cut.pavilion_vertices.size(), cut.pavilion_normals.size(), "%s pavilion normals align" % str(cut_id))
		assert_eq(cut.pavilion_vertices.size(), cut.pavilion_source_indices.size(), "%s pavilion source indices align" % str(cut_id))
		assert_eq(cut.pavilion_vertices.size(), cut.pavilion_target_indices.size(), "%s pavilion target indices align" % str(cut_id))
		assert_true(cut.facet_count() > 0, "%s should expose top-visible facets" % str(cut_id))


func test_geometry_bounds_and_alignment() -> void:
	var target_span: float = 1.0 - 2.0 * GemCutPrimitives.FIT_MARGIN
	for cut_id in CUT_IDS:
		var cut = GemCutGenerators.generate_from_spec_id(cut_id)
		var bounds = _cut_bounds(cut)
		assert_true(bounds["min_x"] >= GemCutPrimitives.FIT_MARGIN - 0.001, "%s min_x stays in fit box" % str(cut_id))
		assert_true(bounds["min_y"] >= GemCutPrimitives.FIT_MARGIN - 0.001, "%s min_y stays in fit box" % str(cut_id))
		assert_true(bounds["max_x"] <= 1.0 - GemCutPrimitives.FIT_MARGIN + 0.001, "%s max_x stays in fit box" % str(cut_id))
		assert_true(bounds["max_y"] <= 1.0 - GemCutPrimitives.FIT_MARGIN + 0.001, "%s max_y stays in fit box" % str(cut_id))
		assert_near(bounds["max_span"], target_span, 0.0025, "%s preserves normalized outer span" % str(cut_id))
		assert_true(not cut.edge_segments.is_empty(), "%s exposes internal edges" % str(cut_id))
		assert_true(cut.silhouette.size() >= 3, "%s exposes a silhouette" % str(cut_id))


func test_no_degenerate_facets() -> void:
	for cut_id in CUT_IDS:
		var cut = GemCutGenerators.generate_from_spec_id(cut_id)
		for facet in cut.facet_vertices:
			assert_true(facet.size() >= 3, "%s facet has at least 3 vertices" % str(cut_id))
			assert_true(_polygon_area(facet) > 0.00001, "%s facet area is non-zero" % str(cut_id))


func test_pavilion_overlay_integrity() -> void:
	var min_bound := GemCutPrimitives.FIT_MARGIN - 0.001
	var max_bound := 1.0 - GemCutPrimitives.FIT_MARGIN + 0.001
	for cut_id in CUT_IDS:
		var cut = GemCutGenerators.generate_from_spec_id(cut_id)
		assert_true(cut.pavilion_count() > 0, "%s should generate pavilion overlay fragments" % str(cut_id))
		for i in cut.pavilion_count():
			var fragment: PackedVector2Array = cut.pavilion_vertices[i]
			assert_true(fragment.size() >= 3, "%s pavilion fragment has at least 3 vertices" % str(cut_id))
			assert_true(_polygon_area(fragment) > 0.000005, "%s pavilion fragment area is non-zero" % str(cut_id))
			var target_index = cut.pavilion_target_indices[i]
			assert_true(target_index >= 0 and target_index < cut.facet_count(),
				"%s pavilion fragment target index is valid" % str(cut_id))
			assert_true(cut.facet_zones[target_index] != "table",
				"%s pavilion fragment should not clip onto the table" % str(cut_id))
			var bounds = _points_bounds(fragment)
			assert_true(bounds["min_x"] >= min_bound, "%s pavilion min_x stays in fit box" % str(cut_id))
			assert_true(bounds["min_y"] >= min_bound, "%s pavilion min_y stays in fit box" % str(cut_id))
			assert_true(bounds["max_x"] <= max_bound, "%s pavilion max_x stays in fit box" % str(cut_id))
			assert_true(bounds["max_y"] <= max_bound, "%s pavilion max_y stays in fit box" % str(cut_id))


func test_projection_distinctiveness() -> void:
	var emerald_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"emerald_step"))
	var asscher_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"asscher_step"))
	assert_true(float(asscher_bounds["aspect"]) > float(emerald_bounds["aspect"]) + 0.20,
		"Asscher should read squarer than Emerald Step")

	var cushion_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"cushion"))
	var opal_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"opal_cushion"))
	assert_true(float(opal_bounds["aspect"]) < float(cushion_bounds["aspect"]) - 0.08,
		"Opal cushion should read more elongated than the base cushion")

	var oval_tip_ratio := _tip_band_width_ratio(GemCutGenerators.generate_from_spec_id(&"oval_brilliant").silhouette, 0.16)
	var marquise_tip_ratio := _tip_band_width_ratio(GemCutGenerators.generate_from_spec_id(&"marquise_brilliant").silhouette, 0.16)
	assert_true(marquise_tip_ratio < oval_tip_ratio * 0.72,
		"Marquise should taper more sharply at the tips than Oval")

	var lozenge_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"lozenge"))
	assert_true(float(lozenge_bounds["aspect"]) < 0.62,
		"Lozenge should stay clearly more elongated than a square")

	var kite_bounds := _cut_bounds(GemCutGenerators.generate_from_spec_id(&"kite_brilliant"))
	assert_true(float(kite_bounds["aspect"]) < 0.65,
		"Kite brilliant should read as an elongated diamond")


func test_rotation_variant_size_compensation() -> void:
	var straight = GemCutGenerators.generate_visual_with_rotation(_make_visual(&"princess_square", 0.0))
	var diagonal = GemCutGenerators.generate_visual_with_rotation(_make_visual(&"princess_square", 45.0))
	var straight_bounds = _cut_bounds(straight)
	var diagonal_bounds = _cut_bounds(diagonal)
	assert_true(straight_bounds["max_span"] < 1.0 - 2.0 * GemCutPrimitives.FIT_MARGIN - 0.01,
		"Princess straight orientation should scale down slightly versus the fit box")
	assert_near(diagonal_bounds["max_span"], 1.0 - 2.0 * GemCutPrimitives.FIT_MARGIN, 0.0025,
		"Princess diagonal orientation should keep the full normalized outer span")


func test_clip_polygon_winding_independence() -> void:
	var subject := GemCutPrimitives.pva([
		Vector2(0.10, 0.10),
		Vector2(0.90, 0.10),
		Vector2(0.90, 0.90),
		Vector2(0.10, 0.90),
	])
	var clip_ccw := GemCutPrimitives.pva([
		Vector2(0.25, 0.20),
		Vector2(0.75, 0.20),
		Vector2(0.75, 0.80),
		Vector2(0.25, 0.80),
	])
	var clip_cw := GemCutPrimitives.pva([
		Vector2(0.25, 0.80),
		Vector2(0.75, 0.80),
		Vector2(0.75, 0.20),
		Vector2(0.25, 0.20),
	])
	var clipped_ccw := GemCutPrimitives.clip_polygon(subject, clip_ccw)
	var clipped_cw := GemCutPrimitives.clip_polygon(subject, clip_cw)
	assert_true(clipped_ccw.size() >= 3, "clip_polygon should work for CCW clip polygons")
	assert_true(clipped_cw.size() >= 3, "clip_polygon should work for CW clip polygons")
	assert_near(_polygon_area(clipped_ccw), _polygon_area(clipped_cw), 0.00001,
		"clip_polygon should be winding-independent")


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	assert_true(absf(actual - expected) <= tolerance, "%s (expected %.5f, got %.5f)" % [message, expected, actual])


func _cut_bounds(cut) -> Dictionary:
	var all_points := PackedVector2Array()
	for facet in cut.facet_vertices:
		for point in facet:
			all_points.append(point)
	for point in cut.silhouette:
		all_points.append(point)
	return _points_bounds(all_points)


func _points_bounds(points: PackedVector2Array) -> Dictionary:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	var width := max_x - min_x
	var height := max_y - min_y
	return {
		"min_x": min_x,
		"min_y": min_y,
		"max_x": max_x,
		"max_y": max_y,
		"max_span": maxf(width, height),
		"aspect": width / maxf(height, 0.00001),
	}


func _polygon_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		var next_index := (i + 1) % points.size()
		area += points[i].x * points[next_index].y - points[next_index].x * points[i].y
	return absf(area) * 0.5


func _tip_band_width_ratio(points: PackedVector2Array, band_portion: float) -> float:
	var bounds := _points_bounds(points)
	var min_y: float = bounds["min_y"]
	var max_y: float = bounds["max_y"]
	var full_width: float = bounds["max_x"] - bounds["min_x"]
	var band_limit := min_y + (max_y - min_y) * band_portion
	var band_min_x := INF
	var band_max_x := -INF
	for point in points:
		if point.y <= band_limit:
			band_min_x = minf(band_min_x, point.x)
			band_max_x = maxf(band_max_x, point.x)
	if band_min_x == INF or band_max_x == -INF:
		return 0.0
	return (band_max_x - band_min_x) / maxf(full_width, 0.00001)


func _make_visual(spec_id: StringName, rotation_degrees: float = 0.0) -> GemVisualResource:
	var visual := GemVisualResource.new()
	visual.cut_spec = load("res://data/visuals/cut_specs/%s.tres" % String(spec_id))
	visual.rotation_degrees = rotation_degrees
	return visual
