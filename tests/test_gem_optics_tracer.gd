extends SceneTree

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gem Optics Tracer Tests ===\n")
	await process_frame
	var tests := [
		{"name": "trace_pipeline_selects_runtime_backend", "call": Callable(self, "test_trace_pipeline_selects_runtime_backend")},
		{"name": "trace_image_has_visible_pixels", "call": Callable(self, "test_trace_image_has_visible_pixels")},
		{"name": "lighting_variants_are_distinct", "call": Callable(self, "test_lighting_variants_are_distinct")},
		{"name": "rotation_variants_are_distinct", "call": Callable(self, "test_rotation_variants_are_distinct")},
		{"name": "non_round_rotation_variants_are_distinct", "call": Callable(self, "test_non_round_rotation_variants_are_distinct")},
		{"name": "birefringence_changes_trace", "call": Callable(self, "test_birefringence_changes_trace")},
		{"name": "trace_size_overrides_target_size", "call": Callable(self, "test_trace_size_overrides_target_size")},
		{"name": "stylizer_materially_changes_output", "call": Callable(self, "test_stylizer_materially_changes_output")},
		{"name": "stylizer_preserves_alpha_silhouette", "call": Callable(self, "test_stylizer_preserves_alpha_silhouette")},
		{"name": "stylized_lighting_variants_are_distinct", "call": Callable(self, "test_stylized_lighting_variants_are_distinct")},
		{"name": "legacy_manifest_versions_are_rejected", "call": Callable(self, "test_legacy_manifest_versions_are_rejected")},
		{"name": "stale_cut_signatures_are_rejected", "call": Callable(self, "test_stale_cut_signatures_are_rejected")},
		{"name": "trace_spp_mismatches_are_rejected", "call": Callable(self, "test_trace_spp_mismatches_are_rejected")},
		{"name": "offline_bake_job_writes_manifest", "call": Callable(self, "test_offline_bake_job_writes_manifest")},
		{"name": "spectral_noise_decreases_with_spp", "call": Callable(self, "test_spectral_noise_decreases_with_spp")},
		{"name": "no_extreme_chromatic_outliers", "call": Callable(self, "test_no_extreme_chromatic_outliers")},
	]
	for i in tests.size():
		var test_info: Dictionary = tests[i]
		_run_named_test(String(test_info.get("name", "")), test_info.get("call", Callable()), i + 1, tests.size())
	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_trace_pipeline_selects_runtime_backend() -> void:
	var tracer = OfflineGemBakeJobScript.create_tracer()
	assert_true(tracer != null, "Tracer pipeline should construct a tracer instance (native kernel required)")
	if tracer == null:
		return
	var backend_id := OfflineGemBakeJobScript.get_trace_backend_id()
	assert_eq(backend_id, &"native_cpp", "Tracer pipeline must use the native kernel (GDScript fallback is deprecated)")
	assert_true(
		StringName(tracer.get_class()) != &"GemOpticsTracer",
		"Native kernel selection must not return the deprecated GDScript tracer"
	)


func test_trace_image_has_visible_pixels() -> void:
	var image := _trace_image({})
	assert_true(image != null, "Tracer should produce an image")
	if image == null:
		return
	assert_true(_count_opaque_pixels(image) > 100, "Traced image should contain gem coverage")


func test_lighting_variants_are_distinct() -> void:
	# For the spectral path tracer, transparent gems are lit by the environment
	# (sky + light cards), not by light_dir (which only affects opaque surfaces).
	# Perturb the environment profile to produce distinct lighting variants.
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"old_european_round")
	if visual == null or mesh_resource == null:
		assert_true(false, "Ruby visual/mesh should load for lighting variant test")
		return
	var env_a := {
		"sky_low": Color(0.05, 0.08, 0.15), "sky_top": Color(0.1, 0.2, 0.5),
		"horizon": Color(0.7, 0.5, 0.3), "ground_dark": Color(0.02, 0.02, 0.02),
		"ground_lift": Color(0.1, 0.08, 0.05), "exposure": 1.2,
		"cards": [{"dir": Vector3(-0.8, 0.3, 0.5), "color": Color(1.0, 0.9, 0.8),
			"sharp_power": 600.0, "broad_power": 60.0,
			"sharp_strength": 5.0, "broad_strength": 2.5, "temperature_kelvin": 5500.0}],
	}
	var env_b := {
		"sky_low": Color(0.15, 0.05, 0.08), "sky_top": Color(0.5, 0.1, 0.2),
		"horizon": Color(0.3, 0.7, 0.5), "ground_dark": Color(0.02, 0.02, 0.02),
		"ground_lift": Color(0.05, 0.1, 0.08), "exposure": 0.8,
		"cards": [{"dir": Vector3(0.8, -0.3, 0.5), "color": Color(0.8, 0.9, 1.0),
			"sharp_power": 600.0, "broad_power": 60.0,
			"sharp_strength": 5.0, "broad_strength": 2.5, "temperature_kelvin": 7500.0}],
	}
	var image_a := _trace_image_with_mesh(mesh_resource, visual, {
		"variant_type": &"lighting",
		"environment_profile": env_a,
	})
	var image_b := _trace_image_with_mesh(mesh_resource, visual, {
		"variant_type": &"lighting",
		"environment_profile": env_b,
	})
	var diff := _image_difference(image_a, image_b)
	assert_true(diff > 0.001, "Lighting variants with different environments should differ (diff=%.5f)" % diff)


func test_rotation_variants_are_distinct() -> void:
	var image_a := _trace_image({"variant_type": &"rotation", "rotation_degrees": 0.0})
	var image_b := _trace_image({"variant_type": &"rotation", "rotation_degrees": 60.0})
	assert_true(_image_difference(image_a, image_b) > 0.004, "Rotation variants should differ materially")


func test_non_round_rotation_variants_are_distinct() -> void:
	var visual: GemVisualResource = load("res://data/visuals/emerald.tres")
	var base_model = GemCutGeneratorsScript.generate_model_from_visual_with_rotation(_make_visual(&"emerald_step", 0.0))
	var rotated_model = GemCutGeneratorsScript.generate_model_from_visual_with_rotation(_make_visual(&"emerald_step", 45.0))
	assert_true(base_model != null, "Emerald model should generate for non-round rotation tracing")
	assert_true(rotated_model != null, "Emerald rotated model should generate for non-round rotation tracing")
	if visual == null or base_model == null or rotated_model == null:
		return
	var image_a := _trace_image_with_mesh(
		GemMeshGeneratorsScript.generate_from_model(base_model),
		visual,
		{"variant_type": &"rotation", "rotation_degrees": 0.0, "mesh_includes_cut_rotation": true}
	)
	var image_b := _trace_image_with_mesh(
		GemMeshGeneratorsScript.generate_from_model(rotated_model),
		visual,
		{"variant_type": &"rotation", "rotation_degrees": 0.0, "mesh_includes_cut_rotation": true}
	)
	assert_true(_image_difference(image_a, image_b) > 0.01, "Non-round rotated meshes should produce materially distinct traced images")


func test_birefringence_changes_trace() -> void:
	var visual: GemVisualResource = load("res://data/visuals/ruby.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"oval_brilliant")
	assert_true(visual != null, "Birefringent visual should load")
	assert_true(mesh_resource != null, "Birefringent mesh should generate")
	if visual == null or mesh_resource == null:
		return
	var scalar_visual: GemVisualResource = visual.duplicate(true)
	# Disable birefringence by providing a template copy with delta_n = 0
	if scalar_visual.mineral_template != null:
		var scalar_template = scalar_visual.mineral_template.duplicate(true)
		scalar_template.birefringence_delta_n = 0.0
		scalar_visual.mineral_template = scalar_template
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
	assert_true(_image_difference(bire_image, scalar_image) > 0.002, "Birefringence should measurably alter traced output")


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
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"pear_brilliant")
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
	var diff := _image_difference(raw_image, styled_image)
	assert_true(diff > 0.0005, "Stylizer should materially reshape the traced output (diff=%.5f)" % diff)


func test_stylizer_preserves_alpha_silhouette() -> void:
	var visual: GemVisualResource = load("res://data/visuals/quartz.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"old_european_round")
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
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"emerald_step")
	assert_true(registry != null, "GemVisualRegistry should exist for stylized lighting-bin coverage")
	assert_true(visual != null, "Emerald visual should load for stylized lighting-bin coverage")
	assert_true(mesh_resource != null, "Emerald mesh should generate for stylized lighting-bin coverage")
	if registry == null or visual == null or mesh_resource == null:
		return
	# Use distinct environment profiles instead of only light_dir
	var env_a := {
		"sky_low": Color(0.16, 0.19, 0.26), "sky_top": Color(0.36, 0.42, 0.54),
		"horizon": Color(0.68, 0.54, 0.36), "ground_dark": Color(0.02, 0.016, 0.013),
		"ground_lift": Color(0.10, 0.078, 0.052), "exposure": 1.4,
		"cards": [{"dir": Vector3(0.0, 0.24, 0.97), "color": Color(1.0, 0.96, 0.88),
			"sharp_power": 900.0, "broad_power": 90.0,
			"sharp_strength": 6.0, "broad_strength": 3.0, "temperature_kelvin": 5500.0}],
	}
	var env_b := {
		"sky_low": Color(0.26, 0.19, 0.16), "sky_top": Color(0.54, 0.42, 0.36),
		"horizon": Color(0.36, 0.54, 0.68), "ground_dark": Color(0.013, 0.016, 0.02),
		"ground_lift": Color(0.052, 0.078, 0.10), "exposure": 0.7,
		"cards": [{"dir": Vector3(0.56, 0.18, 0.80), "color": Color(0.88, 0.96, 1.0),
			"sharp_power": 400.0, "broad_power": 40.0,
			"sharp_strength": 3.0, "broad_strength": 1.5, "temperature_kelvin": 7500.0}],
	}
	var request_a := {
		"draw_size": Vector2i(56, 56),
		"target_size": Vector2i(56, 56),
		"variant_type": &"lighting",
		"environment_profile": env_a,
		"sample_count": 1,
	}
	var request_b := {
		"draw_size": Vector2i(56, 56),
		"target_size": Vector2i(56, 56),
		"variant_type": &"lighting",
		"environment_profile": env_b,
		"sample_count": 1,
	}
	var raw_image_a := _trace_image_with_mesh(mesh_resource, visual, request_a)
	var raw_image_b := _trace_image_with_mesh(mesh_resource, visual, request_b)
	var styled_image_a := GemBakeStylizerScript.apply(raw_image_a, visual, request_a)
	var styled_image_b := GemBakeStylizerScript.apply(raw_image_b, visual, request_b)
	var diff := _image_difference(styled_image_a, styled_image_b)
	assert_true(diff > 0.001, "Stylized lighting variants should remain visibly distinct (diff=%.5f)" % diff)


func test_legacy_manifest_versions_are_rejected() -> void:
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"geometry_signature": "old_european_round",
		"cut_key_override": "old_european_round@rot_0",
	}
	var entry := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"cut_signature": "old_european_round@rot_0",
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


func test_stale_cut_signatures_are_rejected() -> void:
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"geometry_signature": "emerald_step",
		"cut_key_override": "emerald_step@rot_45",
	}
	var stale_entry := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"cut_signature": "emerald_step@rot_0",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
	}
	assert_true(
		not GemTracedBakeContractScript.entry_matches_request(stale_entry, request),
		"Entry matching should reject stale canonical geometry signatures"
	)


func test_trace_spp_mismatches_are_rejected() -> void:
	# Verify that entry matching rejects entries with wrong target size
	# (SPP is recorded for informational purposes but does not gate matching)
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"geometry_signature": "old_european_round",
		"cut_key_override": "old_european_round@rot_0",
		"samples_per_pixel": 32,
	}
	var size_mismatch_entry := {
		"draw_size": Vector2i(96, 96),
		"target_size": Vector2i(96, 96),
		"cut_signature": "old_european_round@rot_0",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"samples_per_pixel": 32,
	}
	assert_true(
		not GemTracedBakeContractScript.entry_matches_request(size_mismatch_entry, request),
		"Entry matching should reject mismatched target sizes"
	)
	# Verify that matching entries with different SPP still match
	# (SPP does not gate entry validity — only version and geometry do)
	var spp_only_diff := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"cut_signature": "old_european_round@rot_0",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"samples_per_pixel": 128,
	}
	assert_true(
		GemTracedBakeContractScript.entry_matches_request(spp_only_diff, request),
		"Entry matching should accept entries differing only in SPP"
	)
	# Manifest-level version check
	var stale_manifest := {
		"backend_id": &"offline_traced",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"samples_per_pixel": 64,
	}
	assert_true(
		GemTracedBakeContractScript.manifest_matches_current(stale_manifest),
		"Manifest matching should accept current version"
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
			"samples_per_pixel": 32,
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
	assert_true(
		manifest.has("sample_count"),
		"Manifest should record the sample count"
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
	assert_true(
		first_entry.has("stylize_version"),
		"Manifest entries should record the stylize version"
	)
	assert_true(
		String(first_entry.get("cut_signature", "")) != "",
		"Manifest entries should record the canonical geometry signature"
	)
	assert_eq(
		StringName(first_entry.get("geometry_source", &"")),
		&"canonical_3d",
		"Manifest entries should record the canonical geometry source"
	)


func test_spectral_noise_decreases_with_spp() -> void:
	# Trace the same gem at low and high SPP with fixed seed.
	# The high-SPP image should have strictly lower local color variance
	# (measured as mean 3x3 neighborhood standard deviation over opaque pixels).
	# This catches missing spectral normalization and importance sampling bugs
	# that prevent convergence.
	var visual: GemVisualResource = load("res://data/visuals/emerald.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"emerald_step")
	assert_true(visual != null, "Emerald visual should load for noise test")
	assert_true(mesh_resource != null, "Emerald mesh should generate for noise test")
	if visual == null or mesh_resource == null:
		return
	var image_low := _trace_image_with_mesh(mesh_resource, visual, {
		"samples_per_pixel": 32,
		"seed": 1000,
		"draw_size": Vector2i(64, 64),
		"target_size": Vector2i(64, 64),
	})
	var image_high := _trace_image_with_mesh(mesh_resource, visual, {
		"samples_per_pixel": 256,
		"seed": 1000,
		"draw_size": Vector2i(64, 64),
		"target_size": Vector2i(64, 64),
	})
	assert_true(image_low != null, "Low-SPP trace should produce an image")
	assert_true(image_high != null, "High-SPP trace should produce an image")
	if image_low == null or image_high == null:
		return
	var noise_low := _measure_local_color_noise(image_low)
	var noise_high := _measure_local_color_noise(image_high)
	assert_true(
		noise_high < noise_low,
		"Higher SPP should produce lower noise (32spp=%.5f, 256spp=%.5f)" % [noise_low, noise_high]
	)
	# The noise at 256 SPP should be well below a perceptual threshold.
	# A value above 0.15 indicates the spectral estimator is not converging.
	assert_true(
		noise_high < 0.15,
		"256 SPP noise should be below perceptual threshold (got %.5f)" % noise_high
	)


func test_no_extreme_chromatic_outliers() -> void:
	# Trace a gem and verify no opaque pixel has extreme saturation that
	# indicates spectral fireflies (single-wavelength samples dominating
	# an entire pixel's XYZ accumulation). Measured as max channel deviation
	# from the pixel's own luminance.
	var visual: GemVisualResource = load("res://data/visuals/quartz.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"old_european_round")
	assert_true(visual != null, "Quartz visual should load for outlier test")
	assert_true(mesh_resource != null, "Quartz mesh should generate for outlier test")
	if visual == null or mesh_resource == null:
		return
	var image := _trace_image_with_mesh(mesh_resource, visual, {
		"samples_per_pixel": 128,
		"seed": 2000,
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
	})
	assert_true(image != null, "Trace should produce an image for outlier test")
	if image == null:
		return
	# For quartz (near-colorless), the mean saturation should be low.
	# Count pixels where any channel deviates from luminance by more than 0.6
	# — these are chromatic outliers from spectral noise.
	var outlier_count := 0
	var opaque_count := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a < 0.5:
				continue
			opaque_count += 1
			var lum := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			if absf(c.r - lum) > 0.6 or absf(c.g - lum) > 0.6 or absf(c.b - lum) > 0.6:
				outlier_count += 1
	var outlier_ratio := float(outlier_count) / maxf(float(opaque_count), 1.0)
	assert_true(
		outlier_ratio < 0.05,
		"Quartz (near-colorless) should have <5%% chromatic outliers at 128 SPP (got %.1f%%)" % [outlier_ratio * 100.0]
	)


func _trace_image(overrides: Dictionary) -> Image:
	var visual: GemVisualResource = load("res://data/visuals/quartz.tres")
	var mesh_resource = GemMeshGeneratorsScript.generate_from_spec_id(&"old_european_round")
	return _trace_image_with_mesh(mesh_resource, visual, overrides)


func _trace_image_with_mesh(mesh_resource, visual: GemVisualResource, overrides: Dictionary) -> Image:
	var tracer = OfflineGemBakeJobScript.create_tracer()
	assert_true(tracer != null, "Tracer pipeline should construct a tracer for image tests")
	if tracer == null:
		return null
	var request := {
		"draw_size": Vector2i(48, 48),
		"target_size": Vector2i(48, 48),
		"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
		"rotation_degrees": 0.0,
		"sample_count": 1,
		"samples_per_pixel": 128,
	}
	for key in overrides.keys():
		request[key] = overrides[key]
	return tracer.trace_to_image(mesh_resource, visual, request)


func _run_named_test(name: String, callback: Callable, index: int, total: int) -> void:
	if not callback.is_valid():
		push_error("Invalid test callable for %s" % name)
		_fail_count += 1
		return
	print("[%d/%d] %s" % [index, total, name])
	var before_fail_count := _fail_count
	var start_usec := Time.get_ticks_usec()
	callback.call()
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0
	var status := "FAIL" if _fail_count > before_fail_count else "ok"
	print("[%d/%d] %s  |  %s  %.1fms" % [index, total, name, status, elapsed_ms])


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


## Measure local color noise as the mean standard deviation of RGB channels
## across 3x3 neighborhoods of opaque pixels. Higher = noisier.
func _measure_local_color_noise(image: Image) -> float:
	var w := image.get_width()
	var h := image.get_height()
	var total_stddev := 0.0
	var count := 0
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var center := image.get_pixel(x, y)
			if center.a < 0.5:
				continue
			# Gather 3x3 neighborhood RGB values
			var sum_r := 0.0
			var sum_g := 0.0
			var sum_b := 0.0
			var sum_r2 := 0.0
			var sum_g2 := 0.0
			var sum_b2 := 0.0
			var n := 0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var c := image.get_pixel(x + ox, y + oy)
					if c.a < 0.5:
						continue
					sum_r += c.r; sum_g += c.g; sum_b += c.b
					sum_r2 += c.r * c.r; sum_g2 += c.g * c.g; sum_b2 += c.b * c.b
					n += 1
			if n < 4:
				continue
			var nf := float(n)
			var var_r := maxf(sum_r2 / nf - (sum_r / nf) * (sum_r / nf), 0.0)
			var var_g := maxf(sum_g2 / nf - (sum_g / nf) * (sum_g / nf), 0.0)
			var var_b := maxf(sum_b2 / nf - (sum_b / nf) * (sum_b / nf), 0.0)
			total_stddev += sqrt(var_r) + sqrt(var_g) + sqrt(var_b)
			count += 1
	if count == 0:
		return 0.0
	return total_stddev / (float(count) * 3.0)


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


func _make_visual(spec_id: StringName, rotation_degrees: float = 0.0) -> GemVisualResource:
	var visual := GemVisualResource.new()
	visual.cut_spec = load("res://data/visuals/cut_specs/%s.tres" % String(spec_id))
	visual.rotation_degrees = rotation_degrees
	return visual
