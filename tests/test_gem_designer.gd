extends SceneTree

## Headless checks for showroom orientation sampling and bake request counts.

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
	_require(visual != null, "quartz visual")
	var cut_model = registry.get_visual_cut_model(visual)
	var cut = registry.get_visual_cut(visual)
	_require(cut_model != null and cut != null, "geometry")

	_test_camera_frame_orthonormal()
	_test_showroom_roll_preserves_z()
	_test_explicit_request_count(registry, visual, cut_model, cut)
	_test_registry_lookup(registry)

	var n_theta := GemViewSphereSamplingScript.fibonacci_point_count_for_theta_degrees(10.0)
	_require(n_theta >= 16, "N(theta)")
	var dirs := GemViewSphereSamplingScript.build_fibonacci_unit_vectors(32)
	_require(dirs.size() == 32, "dirs")
	for i in dirs.size():
		_require(absf(dirs[i].length() - 1.0) < 0.001, "unit")

	print("test_gem_designer: ok")
	quit(0)


func _test_camera_frame_orthonormal() -> void:
	var dirs := GemViewSphereSamplingScript.build_fibonacci_unit_vectors(100)
	for i in dirs.size():
		var b := GemViewSphereSamplingScript.build_camera_frame_for_direction(dirs[i])
		_require(b.is_finite(), "finite basis")
		_require(absf(b.x.length() - 1.0) < 0.02 and absf(b.y.length() - 1.0) < 0.02 and absf(b.z.length() - 1.0) < 0.02, "unit cols")
		_require(absf(b.x.dot(b.y)) < 0.02 and absf(b.x.dot(b.z)) < 0.02 and absf(b.y.dot(b.z)) < 0.02, "orthogonal")
		var z := dirs[i].normalized()
		_require(b.z.dot(z) > 0.999, "z aligns view")


func _test_showroom_roll_preserves_z() -> void:
	var d := Vector3(1.0, 1.0, 0.0).normalized()
	var b0 := GemViewSphereSamplingScript.build_showroom_orientation(d, 0.0)
	var b90 := GemViewSphereSamplingScript.build_showroom_orientation(d, PI * 0.5)
	_require(b0.z.dot(b90.z) > 0.999, "roll preserves view dir")
	var up0 := b0.y
	var up90 := b90.y
	_require(absf(up0.dot(up90)) < 0.05, "roll rotates up in tangent plane")


func _test_explicit_request_count(
	registry: Node,
	visual: GemVisualResource,
	cut_model,
	cut,
) -> void:
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
			"include_showroom": true,
			"showroom_direction_count": 32,
			"showroom_roll_steps": 4,
		}
	)
	_require(explicit.size() == 128, "32*4 showroom frames")
	var first: Dictionary = explicit[0]
	_require(String(first.get("variant_type", "")) == "showroom", "variant type")
	_require(first.has("view_basis_override"), "basis override")
	_require(first.has("showroom_orientation"), "quaternion manifest field")
	var qarr: Array = first.get("showroom_orientation", [])
	_require(qarr.size() >= 4, "quat array")
	var q := Quaternion(float(qarr[1]), float(qarr[2]), float(qarr[3]), float(qarr[0]))
	_require(absf(q.length() - 1.0) < 1e-5, "unit quaternion")
	for entry_variant in explicit:
		var entry: Dictionary = entry_variant
		var qb: Array = entry.get("showroom_orientation", [])
		var qq := Quaternion(float(qb[1]), float(qb[2]), float(qb[3]), float(qb[0]))
		_require(absf(qq.length() - 1.0) < 1e-4, "unit quat row")


func _test_registry_lookup(registry: Node) -> void:
	var fake_entries: Array = []
	var q_id := Quaternion.IDENTITY
	fake_entries.append({
		"variant_type": "showroom",
		"tile_id": &"test_tile_showroom",
		"showroom_direction_index": 0,
		"showroom_roll_index": 0,
		"showroom_orientation": [q_id.w, q_id.x, q_id.y, q_id.z],
		"texture_path": "",
	})
	registry.set_showroom_bake_session(&"test_tile_showroom", fake_entries)
	var frames: Array = registry.find_nearest_showroom_frames(&"test_tile_showroom", q_id, 4)
	_require(frames.size() >= 1, "nearest frame")
	var wsum := 0.0
	for f in frames:
		wsum += float(f.get("weight", 0.0))
	_require(absf(wsum - 1.0) < 1e-3, "weights sum")


func _require(condition: bool, message: String) -> void:
	if not condition:
		push_error("ASSERT: %s" % message)
		quit(1)
