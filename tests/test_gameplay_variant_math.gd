extends SceneTree

## Focused checks for gameplay sprite variant blending math.

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gameplay Variant Math Tests ===\n")
	await process_frame
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist")
	if registry != null:
		test_variant_settings(registry)
		test_lighting_blend_center_and_corner(registry)
		test_lighting_blend_weights_sum(registry)
		test_rotation_blend_weights_sum(registry)
		test_build_requests_are_pure_and_explicit(registry)
		test_rotation_axis_refinement_expands_request_suite(registry)

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_variant_settings(registry: Node) -> void:
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_size"), Vector2i(5, 5), "Lighting grid should default to 5x5")
	assert_eq(settings.get("rotation_bin_count"), 6, "Rotation verification suite should default to 6 orthographic views")
	var rotation_views: Array = settings.get("rotation_views", [])
	assert_eq(rotation_views.size(), 6, "Rotation view metadata should expose the 6 baseline verification views")
	if rotation_views.size() == 6:
		assert_eq(rotation_views[0].get("label", ""), "crown", "First rotation view should be crown")
		assert_eq(rotation_views[3].get("label", ""), "pavilion", "Fourth rotation view should be pavilion")


func test_lighting_blend_center_and_corner(registry: Node) -> void:
	var center_blend: Array = registry.compute_gameplay_lighting_blend(Vector2(0.5, 0.5))
	assert_true(center_blend.size() == 1, "Center sample should collapse to one lighting bin")
	assert_eq(center_blend[0].get("lighting_bin"), Vector2i(2, 2), "Center bin should be 2,2 in a 5x5 grid")

	var corner_blend: Array = registry.compute_gameplay_lighting_blend(Vector2.ZERO)
	assert_true(corner_blend.size() == 1, "Corner sample should collapse to one lighting bin")
	assert_eq(corner_blend[0].get("lighting_bin"), Vector2i(0, 0), "Corner bin should be 0,0")


func test_lighting_blend_weights_sum(registry: Node) -> void:
	var blend: Array = registry.compute_gameplay_lighting_blend(Vector2(0.37, 0.61))
	var total := 0.0
	for entry in blend:
		total += float(entry.get("weight", 0.0))
	assert_true(blend.size() >= 2 and blend.size() <= 4, "Off-grid sample should use 2-4 lighting bins")
	assert_near(total, 1.0, 0.0001, "Lighting blend weights should sum to 1")


func test_rotation_blend_weights_sum(registry: Node) -> void:
	var blend: Array = registry.compute_gameplay_rotation_blend(0.42)
	var total := 0.0
	for entry in blend:
		total += float(entry.get("weight", 0.0))
	assert_true(blend.size() <= 2, "Rotation blend should use at most two bins")
	assert_near(total, 1.0, 0.0001, "Rotation blend weights should sum to 1")


func test_build_requests_are_pure_and_explicit(registry: Node) -> void:
	var before_profile: Dictionary = registry.get_gameplay_texture_profile()
	var requests: Array = registry.build_gameplay_bake_requests_for_tile(
		&"quartz",
		Vector2i(96, 96),
		Vector2i(48, 48)
	)
	var after_profile: Dictionary = registry.get_gameplay_texture_profile()
	assert_true(not requests.is_empty(), "Quartz should build gameplay bake requests on demand")
	assert_eq(before_profile, after_profile, "Ad-hoc request generation should not mutate cache profile state")
	for request in requests:
		assert_eq(request.get("draw_size", Vector2i.ZERO), Vector2i(96, 96), "Requests should keep explicit draw_size")
		assert_eq(request.get("target_size", Vector2i.ZERO), Vector2i(48, 48), "Requests should keep explicit target_size")


func test_rotation_axis_refinement_expands_request_suite(registry: Node) -> void:
	var requests: Array = registry.build_gameplay_bake_requests_for_tile(
		&"quartz",
		Vector2i(64, 64),
		Vector2i(64, 64),
		{
			"rotation_axes": [&"pitch", &"roll"],
			"rotation_axis_steps": 2,
			"rotation_step_degrees": 15.0,
		}
	)
	var rotation_requests: Array = []
	for request in requests:
		if request.get("variant_type", &"") == &"rotation":
			rotation_requests.append(request)
	assert_eq(rotation_requests.size(), 14, "Rotation suite should add 4 frames per requested axis step pair on top of the 6 baseline views")
	var found_roll := false
	var found_pitch := false
	for request in rotation_requests:
		if request.get("rotation_axis", &"") == &"roll":
			found_roll = true
		if request.get("rotation_axis", &"") == &"pitch":
			found_pitch = true
	assert_true(found_roll, "Rotation refinement should include roll-axis verification frames when requested")
	assert_true(found_pitch, "Rotation refinement should include pitch-axis verification frames when requested")


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
