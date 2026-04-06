extends SceneTree

## Headless checks for designer bake request builders + Fibonacci sampling.

const GemViewSphereSamplingScript = preload("res://core/visuals/gem_view_sphere_sampling.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var root = get_root()
	var registry = root.get_node_or_null("GemVisualRegistry")
	if registry == null:
		push_error("GemVisualRegistry missing")
		quit(1)
		return
	var visual: GemVisualResource = registry.get_visual(&"quartz")
	assert(visual != null, "quartz visual")
	var cut_model = registry.get_visual_cut_model(visual)
	var cut = registry.get_visual_cut(visual)
	assert(cut_model != null and cut != null, "geometry")
	var explicit: Array = registry.build_explicit_bake_requests(
		&"test_designer",
		visual,
		cut_model,
		cut,
		Vector2i(64, 64),
		Vector2i(64, 64),
		{
			"include_lighting": false,
			"include_rotation_suite": false,
			"include_view_sphere_fibonacci": true,
			"fibonacci_theta_degrees": 25.0,
		}
	)
	assert(explicit.size() > 10, "fibonacci should produce many views")
	var first: Dictionary = explicit[0]
	assert(String(first.get("variant_type", "")) == "view_sphere", "variant type")
	assert(first.has("view_dir_model"), "view_dir_model")
	for entry_variant in explicit:
		var entry: Dictionary = entry_variant
		var pitch_deg := float(entry.get("view_pitch_degrees", 0.0))
		var yaw_deg := float(entry.get("view_yaw_degrees", 0.0))
		var roll_deg := float(entry.get("view_roll_degrees", 0.0))
		var basis := Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
		basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * basis
		if not is_zero_approx(roll_deg):
			basis = Basis(Vector3.BACK, deg_to_rad(roll_deg)) * basis
		var reconstructed_dir := (basis.inverse() * Vector3.BACK).normalized()
		var stored_dir_arr: Array = entry.get("view_dir_model", [])
		assert(stored_dir_arr.size() >= 3, "stored fibonacci dir")
		var stored_dir := Vector3(
			float(stored_dir_arr[0]),
			float(stored_dir_arr[1]),
			float(stored_dir_arr[2])
		).normalized()
		assert(reconstructed_dir.dot(stored_dir) > 0.9999, "fibonacci basis reconstruction")
	var n := GemViewSphereSamplingScript.fibonacci_point_count_for_theta_degrees(10.0)
	assert(n >= 16, "N(theta)")
	var dirs := GemViewSphereSamplingScript.build_fibonacci_unit_vectors(32)
	assert(dirs.size() == 32, "dirs")
	for i in dirs.size():
		assert(absf(dirs[i].length() - 1.0) < 0.001, "unit")
	print("test_gem_designer: ok")
	quit(0)
