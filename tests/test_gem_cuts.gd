extends SceneTree

## Focused geometry regression checks for procedural gem cuts.
## Run from command line: godot --headless --script tests/test_gem_cuts.gd

const GemCutBuilders = preload("res://core/visuals/gem_cut_builders.gd")
const GemCutGenerators = preload("res://core/visuals/gem_cut_generators.gd")
const GemCutPrimitives = preload("res://core/visuals/gem_cut_primitives.gd")
const GemCutProfiles = preload("res://core/visuals/gem_cut_profiles.gd")

const CUT_IDS: Array[StringName] = [
	&"classic_round",
	&"old_european_round",
	&"cushion",
	&"heart_brilliant",
	&"trillion",
	&"straight_trillion",
	&"radiant_diamond",
	&"princess_square",
	&"radiant_octagon",
	&"hex_brilliant",
	&"pentagon_brilliant",
	&"emerald_step",
	&"asscher_step",
	&"octagon_step",
	&"baguette_step",
	&"tapered_baguette_step",
	&"oval_brilliant",
	&"marquise_brilliant",
	&"pear_brilliant",
	&"rose_round",
	&"half_dutch_rose_hex",
	&"double_rose",
	&"cross_rose",
]

const EXPECTED_FACET_COUNTS := {
	&"classic_round": 33,
	&"old_european_round": 41,
	&"cushion": 33,
	&"heart_brilliant": 41,
	&"trillion": 19,
	&"straight_trillion": 16,
	&"radiant_diamond": 13,
	&"princess_square": 13,
	&"radiant_octagon": 25,
	&"hex_brilliant": 25,
	&"pentagon_brilliant": 21,
	&"emerald_step": 17,
	&"asscher_step": 17,
	&"octagon_step": 17,
	&"baguette_step": 9,
	&"tapered_baguette_step": 9,
	&"oval_brilliant": 33,
	&"marquise_brilliant": 41,
	&"pear_brilliant": 41,
	&"rose_round": 17,
	&"half_dutch_rose_hex": 13,
	&"double_rose": 33,
	&"cross_rose": 17,
}

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== Gem Cut Tests ===\n")
	test_generate_all_cuts()
	test_expected_facet_counts()
	test_geometry_bounds_and_alignment()
	test_no_degenerate_facets()
	test_outline_sampling_stability()
	test_profile_distinctiveness()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_generate_all_cuts() -> void:
	for cut_id in CUT_IDS:
		var cut := GemCutGenerators.generate(cut_id)
		assert_true(cut != null, "%s should generate a cut resource" % str(cut_id))
		if cut == null:
			continue
		assert_eq(cut.cut_id, cut_id, "%s should preserve its cut_id" % str(cut_id))
		assert_eq(cut.facet_vertices.size(), cut.facet_normals.size(), "%s facet normals align" % str(cut_id))
		assert_eq(cut.facet_vertices.size(), cut.facet_zones.size(), "%s facet zones align" % str(cut_id))


func test_expected_facet_counts() -> void:
	for cut_id in CUT_IDS:
		var cut := GemCutGenerators.generate(cut_id)
		assert_eq(cut.facet_count(), EXPECTED_FACET_COUNTS[cut_id], "%s facet count" % str(cut_id))


func test_geometry_bounds_and_alignment() -> void:
	var target_span: float = 1.0 - 2.0 * GemCutPrimitives.FIT_MARGIN
	for cut_id in CUT_IDS:
		var cut := GemCutGenerators.generate(cut_id)
		var bounds := _cut_bounds(cut)
		assert_true(bounds["min_x"] >= GemCutPrimitives.FIT_MARGIN - 0.001, "%s min_x stays in fit box" % str(cut_id))
		assert_true(bounds["min_y"] >= GemCutPrimitives.FIT_MARGIN - 0.001, "%s min_y stays in fit box" % str(cut_id))
		assert_true(bounds["max_x"] <= 1.0 - GemCutPrimitives.FIT_MARGIN + 0.001, "%s max_x stays in fit box" % str(cut_id))
		assert_true(bounds["max_y"] <= 1.0 - GemCutPrimitives.FIT_MARGIN + 0.001, "%s max_y stays in fit box" % str(cut_id))
		assert_near(bounds["max_span"], target_span, 0.002, "%s preserves normalized outer span" % str(cut_id))
		assert_true(not cut.edge_segments.is_empty(), "%s exposes internal edges" % str(cut_id))


func test_no_degenerate_facets() -> void:
	for cut_id in CUT_IDS:
		var cut := GemCutGenerators.generate(cut_id)
		for facet in cut.facet_vertices:
			assert_true(facet.size() >= 3, "%s facet has at least 3 vertices" % str(cut_id))
			assert_true(_polygon_area(facet) > 0.00001, "%s facet area is non-zero" % str(cut_id))


func test_outline_sampling_stability() -> void:
	var profiles: Array[Dictionary] = [
		GemCutProfiles.classic_round(),
		GemCutProfiles.old_european_round(),
		GemCutProfiles.cushion(),
		GemCutProfiles.heart_brilliant(),
		GemCutProfiles.oval_brilliant(),
		GemCutProfiles.marquise_brilliant(),
		GemCutProfiles.pear_brilliant(),
	]

	for profile in profiles:
		var symmetry: int = int(profile.get("silhouette_symmetry", profile.get("sector_count", 8)))
		var low_count: int = GemCutPrimitives.detail_sample_count(symmetry, GemCutPrimitives.DETAIL_LOW, 24)
		var high_count: int = GemCutPrimitives.detail_sample_count(symmetry, GemCutPrimitives.DETAIL_HIGH, 64)
		var low_outline: PackedVector2Array = GemCutBuilders.sample_profile_outline(profile, low_count)
		var high_outline: PackedVector2Array = GemCutBuilders.sample_profile_outline(profile, high_count)
		var low_area: float = _polygon_area(low_outline)
		var high_area: float = _polygon_area(high_outline)
		var low_bounds := _points_bounds(low_outline)
		var high_bounds := _points_bounds(high_outline)
		var area_delta: float = absf(low_area - high_area) / maxf(high_area, 0.00001)
		var aspect_delta: float = absf(float(low_bounds["aspect"]) - float(high_bounds["aspect"]))
		assert_true(area_delta < 0.035, "%s outline area stays stable across sampling densities" % profile["cut_id"])
		assert_true(aspect_delta < 0.03, "%s outline aspect stays stable across sampling densities" % profile["cut_id"])


func test_profile_distinctiveness() -> void:
	var emerald_bounds := _cut_bounds(GemCutGenerators.generate(&"emerald_step"))
	var asscher_bounds := _cut_bounds(GemCutGenerators.generate(&"asscher_step"))
	assert_true(float(asscher_bounds["aspect"]) > float(emerald_bounds["aspect"]) + 0.20,
		"Asscher should read squarer than Emerald Step")

	var oval_tip_ratio := _tip_band_width_ratio(GemCutGenerators.generate(&"oval_brilliant").silhouette, 0.16)
	var marquise_tip_ratio := _tip_band_width_ratio(GemCutGenerators.generate(&"marquise_brilliant").silhouette, 0.16)
	assert_true(marquise_tip_ratio < oval_tip_ratio * 0.72,
		"Marquise should taper more sharply at the tips than Oval")


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


func _cut_bounds(cut: GemCutResource) -> Dictionary:
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
