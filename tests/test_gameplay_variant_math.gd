extends SceneTree

## Focused checks for gameplay sprite variant blending math.

const GemViewSphereSamplingScript = preload("res://core/visuals/gem_view_sphere_sampling.gd")

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
		var original_settings: Dictionary = registry.get_gameplay_variant_settings()
		registry.set_gameplay_variant_settings(GemTracedBakeContract.default_variant_settings(), false)
		test_variant_settings(registry)
		test_lighting_blend_center_and_corner(registry)
		test_lighting_blend_weights_sum(registry)
		test_virtual_lighting_grid_can_be_coarser(registry)
		test_rotation_blend_weights_sum(registry)
		test_variant_settings_can_be_reconfigured(registry)
		test_zero_variant_families_are_supported(registry)
		test_build_requests_are_pure_and_explicit(registry)
		test_rotation_axis_refinement_expands_request_suite(registry)
		test_360_rotation_frame_shortcut(registry)
		test_showroom_variant_settings_roundtrip()
		test_showroom_angular_label()
		registry.set_gameplay_variant_settings(original_settings, false)

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_variant_settings(registry: Node) -> void:
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_preset"), &"quality", "Lighting preset should default to quality")
	assert_eq(settings.get("lighting_grid_size"), Vector2i(5, 5), "Lighting grid should default to 5x5")
	assert_eq(settings.get("lighting_runtime_grid_size"), Vector2i(5, 5), "Runtime lighting grid should default to the baked grid")
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


func test_virtual_lighting_grid_can_be_coarser(registry: Node) -> void:
	var defaults: Dictionary = registry.get_gameplay_variant_settings()
	registry.set_gameplay_variant_settings({
		"lighting_grid_preset": &"quality",
		"lighting_runtime_grid_size": Vector2i(3, 3),
	}, false)
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_preset"), &"quality", "Preset-backed lighting grid should remain quality")
	assert_eq(settings.get("lighting_grid_size"), Vector2i(5, 5), "Quality preset should keep a 5x5 baked lighting grid")
	assert_eq(settings.get("lighting_runtime_grid_size"), Vector2i(3, 3), "Runtime lighting grid should allow a coarser 3x3 region map")
	var blend: Array = registry.compute_gameplay_lighting_blend(Vector2(0.25, 0.5))
	var weight_by_bin: Dictionary = {}
	for entry in blend:
		weight_by_bin[entry.get("lighting_bin", Vector2i(-1, -1))] = float(entry.get("weight", 0.0))
	assert_eq(weight_by_bin.size(), 2, "Coarser runtime lighting grid should still collapse to a 4-bin-or-fewer bilinear blend")
	assert_near(float(weight_by_bin.get(Vector2i(0, 2), 0.0)), 0.5, 0.0001, "Left runtime region should map to the left baked lighting keyframe")
	assert_near(float(weight_by_bin.get(Vector2i(2, 2), 0.0)), 0.5, 0.0001, "Right runtime region should map to the center baked lighting keyframe")
	registry.set_gameplay_variant_settings(defaults, false)


func test_rotation_blend_weights_sum(registry: Node) -> void:
	var blend: Array = registry.compute_gameplay_rotation_blend(0.42)
	var total := 0.0
	for entry in blend:
		total += float(entry.get("weight", 0.0))
	assert_true(blend.size() <= 2, "Rotation blend should use at most two bins")
	assert_near(total, 1.0, 0.0001, "Rotation blend weights should sum to 1")


func test_variant_settings_can_be_reconfigured(registry: Node) -> void:
	var defaults: Dictionary = registry.get_gameplay_variant_settings()
	registry.set_gameplay_variant_settings({
		"lighting_grid_preset": &"performance",
		"rotation_axes": [&"pitch", &"yaw"],
		"rotation_axis_steps": 1,
		"rotation_step_degrees": 12.0,
	}, false)
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_preset"), &"performance", "Lighting preset should reflect the configured manifest/workbench settings")
	assert_eq(settings.get("lighting_grid_size"), Vector2i(3, 3), "Lighting grid should reflect the configured manifest/workbench settings")
	assert_eq(settings.get("rotation_bin_count"), 4, "Axis-specific rotation sweeps should suppress baseline orthographic views")
	var axis_blend: Array = registry.compute_gameplay_rotation_axis_blend(&"pitch", 0.33)
	var total := 0.0
	for entry in axis_blend:
		total += float(entry.get("weight", 0.0))
	assert_eq(axis_blend.size(), 2, "Axis-specific rotation preview should blend between two pitch bins")
	assert_near(total, 1.0, 0.0001, "Axis-specific rotation weights should sum to 1")
	registry.set_gameplay_variant_settings(defaults, false)


func test_zero_variant_families_are_supported(registry: Node) -> void:
	var defaults: Dictionary = registry.get_gameplay_variant_settings()
	registry.set_gameplay_variant_settings({
		"lighting_grid_size": Vector2i.ZERO,
		"rotation_base_view_count": 0,
		"rotation_axis_steps": 0,
		"rotation_axes": [],
	}, false)
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("lighting_grid_preset"), &"custom", "Zeroed lighting grid should normalize to a custom preset")
	assert_eq(settings.get("lighting_grid_size"), Vector2i.ZERO, "Lighting grid should allow 0x0 to disable lighting renders")
	assert_eq(settings.get("lighting_runtime_grid_size"), Vector2i.ZERO, "Runtime lighting grid should also disable when baked lighting is disabled")
	assert_eq(settings.get("rotation_bin_count"), 0, "Rotation bin count should be 0 when baseline and sweep rotations are disabled")
	assert_true(registry.compute_gameplay_lighting_blend(Vector2(0.5, 0.5)).is_empty(), "Lighting blend should be empty when lighting renders are disabled")
	assert_true(registry.compute_gameplay_rotation_blend(0.5).is_empty(), "Rotation blend should be empty when rotation renders are disabled")
	registry.set_gameplay_variant_settings(defaults, false)


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
	assert_eq(rotation_requests.size(), 8, "Rotation suite should emit only requested axis sweep frames when axes are specified")
	var found_roll := false
	var found_pitch := false
	for request in rotation_requests:
		if request.get("rotation_axis", &"") == &"roll":
			found_roll = true
		if request.get("rotation_axis", &"") == &"pitch":
			found_pitch = true
	assert_true(found_roll, "Rotation refinement should include roll-axis verification frames when requested")
	assert_true(found_pitch, "Rotation refinement should include pitch-axis verification frames when requested")


func test_360_rotation_frame_shortcut(registry: Node) -> void:
	var defaults: Dictionary = registry.get_gameplay_variant_settings()
	registry.set_gameplay_variant_settings({
		"rotation_base_view_count": 6,
		"rotation_axes": [&"yaw"],
		"360_rotation_frames": 24,
	}, false)
	var settings: Dictionary = registry.get_gameplay_variant_settings()
	assert_eq(settings.get("rotation_base_view_count"), 0, "Rotation axes should disable baseline orthographic views")
	assert_eq(settings.get("rotation_axis_steps"), 12, "360-frame shortcut should derive half-frame axis steps")
	assert_near(float(settings.get("rotation_step_degrees", 0.0)), 15.0, 0.0001, "360-frame shortcut should derive per-frame degrees")
	assert_eq(settings.get("rotation_bin_count"), 24, "360-frame shortcut should produce the requested full-turn frame count")
	var views: Array = settings.get("rotation_views", [])
	if views.size() == 24:
		assert_eq(views[0].get("label", ""), "yaw_00", "Full-turn rotation should start at the uniform yaw frame")
		assert_eq(views[23].get("label", ""), "yaw_23", "Full-turn rotation should end before duplicating 360 degrees")
	registry.set_gameplay_variant_settings(defaults, false)


func test_showroom_variant_settings_roundtrip() -> void:
	var raw := {
		"showroom_direction_count": 200,
		"showroom_roll_steps": 8,
	}
	var n := GemTracedBakeContract.normalize_variant_settings(raw)
	assert_eq(int(n.get("showroom_direction_count", 0)), 200, "showroom direction count survives normalization")
	assert_eq(int(n.get("showroom_roll_steps", 0)), 8, "showroom roll steps survives normalization")
	var q0 := Quaternion(0.1, 0.2, 0.3, 0.9).normalized()
	var stored := [q0.w, q0.x, q0.y, q0.z]
	var q1 := Quaternion(float(stored[1]), float(stored[2]), float(stored[3]), float(stored[0]))
	assert_true(q0.dot(q1) > 0.9999, "manifest quaternion round-trip")


func test_showroom_angular_label() -> void:
	var theta := GemViewSphereSamplingScript.showroom_angular_resolution_degrees(200)
	assert_near(theta, 14.4, 0.15, "approx 14.4° for n=200")


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
