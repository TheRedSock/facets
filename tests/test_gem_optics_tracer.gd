extends SceneTree

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")
const GemOpticsTracerScript = preload("res://core/visuals/gem_optics_tracer.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemCutBuildersScript = preload("res://core/visuals/gem_cut_builders.gd")
const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gem Optics Tracer Tests ===\n")
	await process_frame
	test_trace_image_has_visible_pixels()
	test_lighting_variants_are_distinct()
	test_rotation_variants_are_distinct()
	test_non_round_rotation_variants_are_distinct()
	test_ruby_trace_has_contrast_range()
	test_ruby_lighting_bins_are_distinct()
	test_ruby_birefringence_changes_trace()
	test_trace_size_overrides_target_size()
	test_stylizer_materially_changes_output()
	test_stylizer_preserves_alpha_silhouette()
	test_stylized_lighting_variants_are_distinct()
	test_legacy_manifest_versions_are_rejected()
	test_offline_bake_job_writes_manifest()
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_trace_image_has_visible_pixels() -> void:
	var image := _trace_image({})
	assert_true(image != null, "Tracer should produce an image")
	if image == null:
		return
	assert_true(_count_opaque_pixels(image) > 100, "Traced image should contain gem coverage")


func test_lighting_variants_are_distinct() -> void:
	var image_a := _trace_image({
		"variant_type": &"lighting",
		"light_dir": Vector3(-0.96, -0.18, 0.08).normalized(),
	})
	var image_b := _trace_image({
		"variant_type": &"lighting",
		"light_dir": Vector3(0.82, 0.56, 0.12).normalized(),
	})
	var diff := _image_difference(image_a, image_b)
	assert_true(diff > 0.004, "Lighting variants should differ materially")


func test_rotation_variants_are_distinct() -> void:
	var image_a := _trace_image({"variant_type": &"rotation", "rotation_degrees": 0.0})
	var image_b := _trace_image({"variant_type": &"rotation", "rotation_degrees": 60.0})
	assert_true(_image_difference(image_a, image_b) > 0.004, "Rotation variants should differ materially")


func test_non_round_rotation_variants_are_distinct() -> void:
	var visual: GemVisualResource = load("res://data/visuals/emerald.tres")
	var base_cut = GemCutGeneratorsScript.generate(&"emerald_step")
	assert_true(base_cut != null, "Emerald cut should generate for non-round rotation tracing")
	if visual == null or base_cut == null:
		return
	var rotated_cut = GemCutBuildersScript.create_visual_variant(base_cut, 45.0)
	var image_a := _trace_image_with_mesh(
		GemMeshGeneratorsScript.generate_from_cut(base_cut),
		visual,
		{"variant_type": &"rotation", "rotation_degrees": 0.0, "mesh_includes_cut_rotation": true}
	)
	var image_b := _trace_image_with_mesh(
		GemMeshGeneratorsScript.generate_from_cut(rotated_cut),
		visual,
		{"variant_type": &"rotation", "rotation_degrees": 0.0, "mesh_includes_cut_rotation": true}
	)
	assert_true(_image_difference(image_a, image_b) > 0.01, "Non-round rotated meshes should produce materially distinct traced images")


func test_ruby_trace_has_contrast_range() -> void:
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"oval_brilliant")
	assert_true(visual != null, "Ruby visual should load")
	assert_true(mesh_resource != null, "Ruby cut should generate a mesh resource")
	if visual == null or mesh_resource == null:
		return
	var image := _trace_image_with_mesh(
		mesh_resource,
		visual,
		{
			"variant_type": &"lighting",
			"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
		}
	)
	var stats := _opaque_luma_stats(image)
	assert_true(stats.get("count", 0) > 100, "Ruby trace should cover a meaningful image area")
	assert_true(stats.get("min", 1.0) < 0.28, "Ruby trace should retain dark extinction regions")
	assert_true(stats.get("max", 0.0) > 0.58, "Ruby trace should retain bright glare regions")
	assert_true(stats.get("range", 0.0) > 0.44, "Ruby trace should show strong internal contrast")


func test_ruby_lighting_bins_are_distinct() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"oval_brilliant")
	assert_true(registry != null, "GemVisualRegistry should exist for ruby lighting-bin coverage")
	assert_true(visual != null, "Ruby visual should load for lighting-bin coverage")
	assert_true(mesh_resource != null, "Ruby mesh should generate for lighting-bin coverage")
	if registry == null or visual == null or mesh_resource == null:
		return
	var grid: Vector2i = registry.get_gameplay_variant_settings().get("lighting_grid_size", Vector2i(5, 5))
	var image_a := _trace_image_with_mesh(
		mesh_resource,
		visual,
		{
			"variant_type": &"lighting",
			"light_dir": registry.compute_gameplay_light_dir(Vector2i(0, 0)),
			"lighting_uv": _lighting_bin_to_centered(Vector2i(0, 0), grid),
		}
	)
	var image_b := _trace_image_with_mesh(
		mesh_resource,
		visual,
		{
			"variant_type": &"lighting",
			"light_dir": registry.compute_gameplay_light_dir(Vector2i(4, 4)),
			"lighting_uv": _lighting_bin_to_centered(Vector2i(4, 4), grid),
		}
	)
	assert_true(_image_difference(image_a, image_b) > 0.012, "Ruby lighting bins should produce visibly distinct traced frames")


func test_ruby_birefringence_changes_trace() -> void:
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"oval_brilliant")
	assert_true(visual != null, "Ruby visual should load for birefringence coverage")
	assert_true(mesh_resource != null, "Ruby mesh should generate for birefringence coverage")
	if visual == null or mesh_resource == null:
		return
	var scalar_visual: GemVisualResource = visual.duplicate(true)
	scalar_visual.optics_birefringence_strength = 0.0
	var bire_image := _trace_image_with_mesh(
		mesh_resource,
		visual,
		{
			"variant_type": &"rotation",
			"rotation_degrees": 30.0,
		}
	)
	var scalar_image := _trace_image_with_mesh(
		mesh_resource,
		scalar_visual,
		{
			"variant_type": &"rotation",
			"rotation_degrees": 30.0,
		}
	)
	assert_true(_image_difference(bire_image, scalar_image) > 0.002, "Ruby birefringence should measurably alter traced output")


func test_trace_size_overrides_target_size() -> void:
	var image := _trace_image({
		"draw_size": Vector2i(96, 96),
		"target_size": Vector2i(48, 48),
	})
	assert_true(image != null, "Tracer should produce an image when draw_size exceeds target_size")
	if image == null:
		return
	assert_eq(image.get_width(), 96, "Tracer should render at draw_size by default")
	assert_eq(image.get_height(), 96, "Tracer should render at draw_size by default")


func test_stylizer_materially_changes_output() -> void:
	var visual: GemVisualResource = load("res://data/visuals/diamond.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"pear_brilliant")
	assert_true(visual != null, "Diamond visual should load for stylizer coverage")
	assert_true(mesh_resource != null, "Diamond mesh should generate for stylizer coverage")
	if visual == null or mesh_resource == null:
		return
	var request := {
		"draw_size": Vector2i(64, 64),
		"target_size": Vector2i(64, 64),
		"variant_type": &"lighting",
		"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
		"sample_count": 1,
	}
	var raw_image := _trace_image_with_mesh(mesh_resource, visual, request)
	var styled_image := GemBakeStylizerScript.apply(raw_image, visual, request)
	assert_true(_image_difference(raw_image, styled_image) > 0.003, "Stylizer should materially reshape the traced output")


func test_stylizer_preserves_alpha_silhouette() -> void:
	var visual: GemVisualResource = load("res://data/visuals/quartz.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"old_european_round")
	assert_true(visual != null, "Quartz visual should load for stylizer silhouette coverage")
	assert_true(mesh_resource != null, "Quartz mesh should generate for stylizer silhouette coverage")
	if visual == null or mesh_resource == null:
		return
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"variant_type": &"lighting",
		"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
		"sample_count": 1,
	}
	var raw_image := _trace_image_with_mesh(mesh_resource, visual, request)
	var styled_image := GemBakeStylizerScript.apply(raw_image, visual, request)
	assert_eq(
		_count_opaque_pixels(styled_image),
		_count_opaque_pixels(raw_image),
		"Stylizer should preserve traced alpha coverage"
	)


func test_stylized_lighting_variants_are_distinct() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	var visual: GemVisualResource = load("res://data/visuals/emerald.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"emerald_step")
	assert_true(registry != null, "GemVisualRegistry should exist for stylized lighting-bin coverage")
	assert_true(visual != null, "Emerald visual should load for stylized lighting-bin coverage")
	assert_true(mesh_resource != null, "Emerald mesh should generate for stylized lighting-bin coverage")
	if registry == null or visual == null or mesh_resource == null:
		return
	var grid: Vector2i = registry.get_gameplay_variant_settings().get("lighting_grid_size", Vector2i(5, 5))
	var request_a := {
		"draw_size": Vector2i(56, 56),
		"target_size": Vector2i(56, 56),
		"variant_type": &"lighting",
		"light_dir": registry.compute_gameplay_light_dir(Vector2i(1, 1)),
		"lighting_uv": _lighting_bin_to_centered(Vector2i(1, 1), grid),
		"sample_count": 1,
	}
	var request_b := {
		"draw_size": Vector2i(56, 56),
		"target_size": Vector2i(56, 56),
		"variant_type": &"lighting",
		"light_dir": registry.compute_gameplay_light_dir(Vector2i(4, 3)),
		"lighting_uv": _lighting_bin_to_centered(Vector2i(4, 3), grid),
		"sample_count": 1,
	}
	var raw_image_a := _trace_image_with_mesh(mesh_resource, visual, request_a)
	var raw_image_b := _trace_image_with_mesh(mesh_resource, visual, request_b)
	var styled_image_a := GemBakeStylizerScript.apply(raw_image_a, visual, request_a)
	var styled_image_b := GemBakeStylizerScript.apply(raw_image_b, visual, request_b)
	assert_true(_image_difference(styled_image_a, styled_image_b) > 0.01, "Stylized lighting variants should remain visibly distinct")


func test_legacy_manifest_versions_are_rejected() -> void:
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
	}
	var entry := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION - 1,
	}
	var manifest := {
		"backend_id": &"offline_traced",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION - 1,
	}
	assert_true(
		not GemTracedBakeContractScript.entry_matches_request(entry, request),
		"Legacy manifest entries should be rejected by the traced bake contract"
	)
	assert_true(
		not GemTracedBakeContractScript.manifest_matches_current(manifest),
		"Legacy manifests should be rejected by the traced bake contract"
	)


func test_offline_bake_job_writes_manifest() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist")
	if registry == null:
		return
	var job = OfflineGemBakeJobScript.new()
	var result: Dictionary = job.run_batch(
		registry,
		[&"quartz"],
		Vector2i(48, 48),
		{
			"output_root": "user://traced_bakes_test",
			"draw_size": Vector2i(48, 48),
			"sample_count": 1,
			"lighting_bins": [Vector2i(2, 2)],
			"rotation_bins": [0],
		}
	)
	assert_eq(result.get("status", ""), "ok", "Offline bake job should complete")
	assert_true(int(result.get("entry_count", 0)) >= 2, "Offline bake job should emit requested variants")
	var manifest_path := String(result.get("manifest_path", ""))
	assert_true(FileAccess.file_exists(manifest_path), "Manifest file should exist")
	if not FileAccess.file_exists(manifest_path):
		return
	var file := FileAccess.open(manifest_path, FileAccess.READ)
	assert_true(file != null, "Manifest file should be readable")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "Manifest file should contain a dictionary payload")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var manifest: Dictionary = parsed
	assert_eq(
		int(manifest.get("stylize_version", 0)),
		GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"Manifest should record the current stylized bake version"
	)
	var entries: Array = manifest.get("entries", [])
	assert_true(not entries.is_empty(), "Manifest should include traced entries")
	if entries.is_empty():
		return
	var first_entry: Dictionary = entries[0]
	assert_eq(
		int(first_entry.get("stylize_version", 0)),
		GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"Manifest entries should record the current stylized bake version"
	)


func _trace_image(overrides: Dictionary) -> Image:
	var visual: GemVisualResource = load("res://data/visuals/quartz.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate(&"old_european_round")
	return _trace_image_with_mesh(mesh_resource, visual, overrides)


func _trace_image_with_mesh(mesh_resource, visual: GemVisualResource, overrides: Dictionary) -> Image:
	var tracer = GemOpticsTracerScript.new()
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
		"rotation_degrees": 0.0,
		"sample_count": 1,
	}
	for key in overrides.keys():
		request[key] = overrides[key]
	return tracer.trace_to_image(mesh_resource, visual, request)


func _count_opaque_pixels(image: Image) -> int:
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.01:
				count += 1
	return count


func _image_difference(image_a: Image, image_b: Image) -> float:
	if image_a == null or image_b == null:
		return 0.0
	var total := 0.0
	var pixel_count := 0.0
	for y in mini(image_a.get_height(), image_b.get_height()):
		for x in mini(image_a.get_width(), image_b.get_width()):
			var a := image_a.get_pixel(x, y)
			var b := image_b.get_pixel(x, y)
			if a.a <= 0.01 and b.a <= 0.01:
				continue
			total += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			pixel_count += 4.0
	if pixel_count <= 0.0:
		return 0.0
	return total / pixel_count


func _opaque_luma_stats(image: Image) -> Dictionary:
	if image == null:
		return {}
	var count := 0
	var min_luma := 1.0
	var max_luma := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.01:
				continue
			var luma := pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			min_luma = minf(min_luma, luma)
			max_luma = maxf(max_luma, luma)
			count += 1
	return {
		"count": count,
		"min": min_luma,
		"max": max_luma,
		"range": max_luma - min_luma,
	}


func _lighting_bin_to_centered(lighting_bin: Vector2i, grid: Vector2i) -> Vector2:
	var centered := Vector2.ZERO
	if grid.x > 1:
		centered.x = (float(lighting_bin.x) / float(grid.x - 1)) * 2.0 - 1.0
	if grid.y > 1:
		centered.y = (float(lighting_bin.y) / float(grid.y - 1)) * 2.0 - 1.0
	return centered


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
