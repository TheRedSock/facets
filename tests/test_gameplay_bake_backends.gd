extends SceneTree

## Integration and timing checks for the offline traced gameplay texture backend.

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const CELL_SIZE := Vector2i(64, 64)
const MAX_WAIT_FRAMES := 2500

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gameplay Bake Backend Test ===\n")
	await process_frame

	await _run_offline_traced_case()
	await _run_scoped_preview_case()
	await _run_manifest_reload_case()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func _run_offline_traced_case() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist")
	if registry == null:
		return

	registry.invalidate_render_cache()
	var job = OfflineGemBakeJobScript.new()
	job.run_batch(
		registry,
		[&"quartz"],
		CELL_SIZE,
		{
			"output_root": "user://traced_bakes",
			"draw_size": CELL_SIZE,
			"sample_count": 1,
			"lighting_grid_size": Vector2i(1, 1),
			"rotation_base_view_count": 1,
		}
	)
	registry.ensure_gameplay_texture_cache(CELL_SIZE, [&"quartz"])
	await _wait_for_cache(registry, &"offline_traced", [&"quartz"])

	var report: Dictionary = registry.get_last_gameplay_bake_report()
	var backend_counts: Dictionary = report.get("backend_counts", {})
	var quartz_texture = registry.get_gameplay_texture(&"quartz", 1)
	var total_elapsed_ms := float(report.get("total_elapsed_ms", 0.0))
	var requires_real_textures := DisplayServer.get_name() != "headless"

	print("offline_traced total bake time: %.2fms  backends=%s" % [total_elapsed_ms, backend_counts])

	if requires_real_textures:
		assert_true(quartz_texture != null, "offline_traced should produce a quartz texture")
	assert_true(total_elapsed_ms > 0.0, "offline_traced should record bake timings")

	assert_true(int(backend_counts.get(&"offline_traced", 0)) > 0, "offline_traced should load traced variants from manifest")
	assert_true(
		int(backend_counts.get(&"viewport_3d_preview", 0)) == 0 and int(backend_counts.get(&"procedural_2d", 0)) == 0,
		"offline gameplay cache should not use deprecated runtime bake backends"
	)
	assert_true(
		registry.is_gameplay_texture_cache_current(CELL_SIZE, [&"quartz"]),
		"offline traced cache should stay scoped to traced preset coverage"
	)


func _run_scoped_preview_case() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist for scoped cache case")
	if registry == null:
		return

	registry.invalidate_render_cache()
	registry.ensure_gameplay_texture_cache(CELL_SIZE, [&"quartz"])
	await _wait_for_cache(registry, &"scoped_quartz_preview", [&"quartz"])

	var profile: Dictionary = registry.get_gameplay_texture_profile()
	var scoped_texture = registry.get_gameplay_texture(&"quartz", 1)

	assert_true(
		registry.is_gameplay_texture_cache_current(CELL_SIZE, [&"quartz"]),
		"scoped cache should be current for quartz preview scope"
	)
	assert_true(
		not registry.is_gameplay_texture_cache_current(CELL_SIZE),
		"scoped preview cache should not count as a full gameplay cache"
	)
	assert_true(
		profile.get("tile_scope", PackedStringArray()) == PackedStringArray(["quartz"]),
		"scoped cache profile should record the quartz-only scope"
	)
	if DisplayServer.get_name() != "headless":
		assert_true(scoped_texture != null, "scoped cache should still produce a quartz texture")


func _run_manifest_reload_case() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist for manifest reload case")
	if registry == null:
		return

	var job = OfflineGemBakeJobScript.new()
	job.run_batch(
		registry,
		[&"quartz"],
		CELL_SIZE,
		{
			"output_root": "user://traced_bakes",
			"draw_size": CELL_SIZE,
			"sample_count": 1,
			"lighting_grid_preset": &"performance",
			"lighting_runtime_grid_size": Vector2i(1, 1),
			"lighting_bins": [Vector2i(1, 1)],
			"rotation_axes": [&"pitch"],
			"rotation_axis_steps": 1,
			"rotation_step_degrees": 12.0,
			"rotation_bins": [0],
		}
	)
	registry.reload_offline_traced_manifest(false)
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_preset"), &"performance", "Reloading the traced manifest should preserve the baked lighting preset")
	assert_eq(settings.get("lighting_grid_size"), Vector2i(3, 3), "Reloading the traced manifest should update the active lighting grid")
	assert_eq(settings.get("lighting_runtime_grid_size"), Vector2i(1, 1), "Reloading the traced manifest should update the virtual runtime lighting grid")
	assert_eq(settings.get("rotation_bin_count"), 8, "Reloading the traced manifest should update the active rotation suite")

	# Manifest content checks: verify new fields are present
	var manifest: Dictionary = registry.get_offline_traced_manifest()
	if not manifest.is_empty():
		assert_true(
			manifest.has("samples_per_pixel"),
			"Traced manifest should contain samples_per_pixel field"
		)


func _wait_for_cache(registry: Node, preference: StringName, tile_scope = []) -> void:
	var frame_count := 0
	while not registry.is_gameplay_texture_cache_current(CELL_SIZE, tile_scope) and frame_count < MAX_WAIT_FRAMES:
		await process_frame
		frame_count += 1
		if frame_count % 60 == 0:
			var partial_report: Dictionary = registry.get_last_gameplay_bake_report()
			var tile_metrics: Array = partial_report.get("tile_metrics", [])
			print("%s progress: %d frames, %d baked tiles" % [
				preference,
				frame_count,
				tile_metrics.size(),
			])
	assert_true(
		registry.is_gameplay_texture_cache_current(CELL_SIZE, tile_scope),
		"%s bake should complete within %d frames" % [String(preference), MAX_WAIT_FRAMES]
	)


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])
