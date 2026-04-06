extends SceneTree

## Canonical 3D cut-model invariants.
## Run from command line: godot --headless --script tests/test_gem_cut_models.gd

const GemCutGenerators = preload("res://core/visuals/gem_cut_generators.gd")
const GemCutPrimitives = preload("res://core/visuals/gem_cut_primitives.gd")

const CUT_IDS: Array[StringName] = [
	&"classic_round",
	&"old_european_round",
	&"simple_octagon_step",
	&"cushion",
	&"opal_cushion",
	&"heart_brilliant",
	&"trillion",
	&"straight_trillion",
	&"princess_square",
	&"lozenge",
	&"kite_brilliant",
	&"radiant_square",
	&"radiant_octagon",
	&"hex_brilliant",
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

const FOCUSED_VISUAL_IDS: Array[StringName] = [
	&"quartz",
	&"fluorite",
	&"tourmaline",
	&"rhodolite",
	&"aquamarine",
	&"blue_garnet",
	&"diamond",
	&"opal_study",
]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	print("\n=== Gem Cut Model Tests ===\n")
	call_deferred("_run")


func _run() -> void:
	await process_frame
	test_generate_all_models()
	test_dimensional_validity()
	test_shared_edge_topology()
	test_normals_face_outward()
	test_rotation_variants_preserve_normalization()
	test_focused_visual_alignment_coverage()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_generate_all_models() -> void:
	for cut_id in CUT_IDS:
		var model = GemCutGenerators.generate_model_from_spec_id(cut_id)
		assert_true(model != null, "%s should generate a canonical model" % str(cut_id))
		if model == null:
			continue
		assert_eq(model.spec_id, cut_id, "%s should preserve spec_id" % str(cut_id))
		assert_eq(model.facet_vertices.size(), model.facet_normals.size(), "%s facet normals align" % str(cut_id))
		assert_eq(model.facet_vertices.size(), model.facet_zones.size(), "%s facet zones align" % str(cut_id))
		assert_true(model.facet_count() > 0, "%s should emit 3D facets" % str(cut_id))
		assert_true(model.outer_loop.size() >= 3, "%s should expose an outer footprint loop" % str(cut_id))


func test_dimensional_validity() -> void:
	for cut_id in CUT_IDS:
		var model = GemCutGenerators.generate_model_from_spec_id(cut_id)
		if model == null:
			continue
		var bounds: AABB = model.compute_bounds()
		assert_true(bounds.size.x > 0.30, "%s should have non-trivial X span" % str(cut_id))
		assert_true(bounds.size.y > 0.45, "%s should have non-trivial Y span" % str(cut_id))
		assert_true(bounds.size.z > 0.18, "%s should have non-trivial Z span" % str(cut_id))
		assert_true(
			model.compute_bounding_radius() > GemCutPrimitives.GEM_RADIUS - 0.01,
			"%s should preserve the canonical fit radius" % str(cut_id)
		)
		assert_true(model.crown_height > 0.0, "%s should preserve crown height" % str(cut_id))
		assert_true(model.girdle_thickness > 0.0, "%s should preserve girdle thickness" % str(cut_id))
		assert_true(model.pavilion_depth > 0.0, "%s should preserve pavilion depth" % str(cut_id))


func test_shared_edge_topology() -> void:
	for cut_id in CUT_IDS:
		var model = GemCutGenerators.generate_model_from_spec_id(cut_id)
		if model == null:
			continue
		assert_eq(model.edge_segments.size(), model.edge_facet_a.size(), "%s edge facet_a alignment" % str(cut_id))
		assert_eq(model.edge_segments.size(), model.edge_facet_b.size(), "%s edge facet_b alignment" % str(cut_id))
		for edge_index in model.edge_segments.size():
			assert_true(model.edge_facet_a[edge_index] >= 0, "%s edge %d should have a source facet" % [str(cut_id), edge_index])
			assert_true(model.edge_facet_b[edge_index] >= 0, "%s edge %d should be shared or sealed" % [str(cut_id), edge_index])


func test_normals_face_outward() -> void:
	for cut_id in CUT_IDS:
		var model = GemCutGenerators.generate_model_from_spec_id(cut_id)
		if model == null:
			continue
		for facet_index in model.facet_count():
			var centroid := _facet_centroid(model.facet_vertices[facet_index])
			assert_true(
				model.facet_normals[facet_index].dot(centroid) > 0.0,
				"%s facet %d should face outward" % [str(cut_id), facet_index]
			)


func test_rotation_variants_preserve_normalization() -> void:
	var base_model = GemCutGenerators.generate_model_from_visual_with_rotation(_make_visual(&"princess_square", 0.0))
	var rotated_model = GemCutGenerators.generate_model_from_visual_with_rotation(_make_visual(&"princess_square", 45.0))
	assert_true(base_model != null, "Princess square base model should generate")
	assert_true(rotated_model != null, "Princess square rotated model should generate")
	if base_model == null or rotated_model == null:
		return
	var base_bounds: AABB = base_model.compute_bounds()
	var rotated_bounds: AABB = rotated_model.compute_bounds()
	assert_true(
		base_model.facet_count() == rotated_model.facet_count(),
		"Rotated princess variants should preserve facet topology"
	)
	assert_true(
		base_bounds.size.x <= GemCutPrimitives.GEM_RADIUS * 2.0 + 0.01
			and base_bounds.size.y <= GemCutPrimitives.GEM_RADIUS * 2.0 + 0.01
			and rotated_bounds.size.x <= GemCutPrimitives.GEM_RADIUS * 2.0 + 0.01
			and rotated_bounds.size.y <= GemCutPrimitives.GEM_RADIUS * 2.0 + 0.01,
		"Rotated variants should remain within the canonical fit envelope"
	)


func test_focused_visual_alignment_coverage() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist for focused visual coverage")
	if registry == null:
		return
	for visual_id in FOCUSED_VISUAL_IDS:
		var visual: GemVisualResource = registry.get_visual(visual_id)
		assert_true(visual != null, "%s visual should exist for atlas regression coverage" % str(visual_id))
		if visual == null:
			continue
		var cut_model = registry.get_visual_cut_model(visual)
		var projected_cut = registry.get_visual_cut(visual)
		assert_true(cut_model != null, "%s should resolve a canonical cut model" % str(visual_id))
		assert_true(projected_cut != null, "%s should resolve a projected cut" % str(visual_id))
		if cut_model == null or projected_cut == null:
			continue
		assert_eq(cut_model.spec_id, visual.get_cut_spec_id(), "%s should resolve the visual's spec" % str(visual_id))
		var projected_bounds := _projected_bounds(projected_cut)
		assert_true(projected_bounds["min_x"] >= 0.05, "%s projected cut should stay inside the fit margin" % str(visual_id))
		assert_true(projected_bounds["max_x"] <= 0.95, "%s projected cut should stay inside the fit margin" % str(visual_id))
		assert_true(projected_cut.orthographic_axis_fit_scale > 0.0, "%s should preserve orthographic fit metadata" % str(visual_id))


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _facet_centroid(vertices: PackedVector3Array) -> Vector3:
	var centroid := Vector3.ZERO
	for vertex in vertices:
		centroid += vertex
	return centroid / float(vertices.size())


func _projected_bounds(cut) -> Dictionary:
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point in cut.silhouette:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return {
		"min_x": min_x,
		"min_y": min_y,
		"max_x": max_x,
		"max_y": max_y,
	}


func _make_visual(spec_id: StringName, rotation_degrees: float = 0.0) -> GemVisualResource:
	var visual := GemVisualResource.new()
	visual.cut_spec = load("res://data/visuals/cut_specs/%s.tres" % String(spec_id))
	visual.rotation_degrees = rotation_degrees
	return visual
