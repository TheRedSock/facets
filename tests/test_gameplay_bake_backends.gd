extends SceneTree

## Integration and timing checks for the offline traced gameplay texture backend.

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const CELL_SIZE := Vector2i(112, 112)
const MAX_WAIT_FRAMES := 2500
const PREFERENCES: Array[StringName] = [
	&"offline_traced",
]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gameplay Bake Backend Test ===\n")
	await process_frame

	for preference in PREFERENCES:
		await _run_preference_case(preference)
	await _run_scoped_preview_case()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func _run_preference_case(preference: StringName) -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist")
	if registry == null:
		return

	registry.invalidate_render_cache()
	var job = OfflineGemBakeJobScript.new()
	job.run_batch(
		registry,
		[&"quartz", &"diamond"],
		CELL_SIZE,
		{
			"output_root": "user://traced_bakes",
			"draw_size": CELL_SIZE,
			"sample_count": 1,
			"lighting_bins": [Vector2i(2, 2)],
			"rotation_bins": [0],
		}
	)
	registry.set_gameplay_bake_backend_preference(preference)
	registry.ensure_gameplay_texture_cache(CELL_SIZE, [&"quartz", &"diamond"])
	await _wait_for_cache(registry, preference, [&"quartz", &"diamond"])

	var report: Dictionary = registry.get_last_gameplay_bake_report()
	var backend_counts: Dictionary = report.get("backend_counts", {})
	var quartz_texture = registry.get_gameplay_texture(&"quartz", 1)
	var diamond_texture = registry.get_gameplay_texture(&"diamond", 8)
	var total_elapsed_ms := float(report.get("total_elapsed_ms", 0.0))
	var requires_real_textures := DisplayServer.get_name() != "headless"

	print("%s total bake time: %.2fms  backends=%s" % [preference, total_elapsed_ms, backend_counts])

	if requires_real_textures:
		assert_true(quartz_texture != null, "%s should produce a quartz texture" % String(preference))
		assert_true(diamond_texture != null, "%s should produce a diamond texture" % String(preference))
	assert_true(total_elapsed_ms > 0.0, "%s should record bake timings" % String(preference))

	assert_true(int(backend_counts.get(&"offline_traced", 0)) > 0, "offline_traced should load traced variants from manifest")
	assert_true(
		int(backend_counts.get(&"viewport_3d_preview", 0)) == 0 and int(backend_counts.get(&"procedural_2d", 0)) == 0,
		"offline gameplay cache should not use deprecated runtime bake backends"
	)
	assert_true(
		registry.is_gameplay_texture_cache_current(CELL_SIZE, [&"quartz", &"diamond"]),
		"offline traced cache should stay scoped to traced preset coverage"
	)


func _run_scoped_preview_case() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist for scoped cache case")
	if registry == null:
		return

	registry.invalidate_render_cache()
	registry.set_gameplay_bake_backend_preference(&"2d_only")
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
