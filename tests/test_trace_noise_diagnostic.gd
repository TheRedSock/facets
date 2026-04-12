## Diagnostic trace test for verifying noise-free output.
## Run: godot --headless --script tests/test_trace_noise_diagnostic.gd
extends SceneTree

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")

func _init() -> void:
	var ok := true
	print("=== Trace Noise Diagnostic ===")
	print("")

	# Load Fluorite (the gem that exhibits the noise issue)
	var visual: GemVisualResource = load("res://data/visuals/fluorite.tres")
	if visual == null:
		print("FAIL: Could not load fluorite visual")
		quit(1)
		return

	var mesh = GemMeshGeneratorsScript.generate_from_visual(visual)
	if mesh == null:
		print("FAIL: Could not generate mesh for fluorite")
		quit(1)
		return

	var tracer = OfflineGemBakeJobScript.create_tracer()
	if tracer == null:
		print("FAIL: Could not create tracer")
		quit(1)
		return

	# Run physics tests first
	print("--- Physics Tests ---")
	var physics: Dictionary = tracer.run_physics_tests()
	var all_passed := true
	for key in physics.keys():
		var test: Dictionary = physics[key]
		var passed: bool = test.get("passed", false)
		if not passed:
			print("  FAIL: %s — expected %s, got %s" % [key, str(test.get("expected")), str(test.get("actual"))])
			all_passed = false
	if all_passed:
		print("  All physics tests passed.")
	else:
		ok = false
	print("")

	# Trace at multiple view angles and measure per-pixel noise
	var angles := [
		{"name": "top_down", "pitch": 0.0, "yaw": 0.0},
		{"name": "side_pitch_down", "pitch": -90.0, "yaw": 0.0},
		{"name": "bottom_up", "pitch": 180.0, "yaw": 0.0},
		{"name": "side_pitch_up", "pitch": 90.0, "yaw": 0.0},
	]

	var size := 256
	var spp := 256

	for angle in angles:
		print("--- Tracing: %s (pitch=%.0f) ---" % [angle["name"], angle["pitch"]])

		var request := {
			"draw_size": Vector2i(size, size),
			"target_size": Vector2i(size, size),
			"trace_size": Vector2i(size, size),
			"light_dir": Vector3(-0.4, -0.5, 0.75).normalized(),
			"rotation_degrees": 0.0,
			"view_pitch_degrees": angle["pitch"],
			"view_yaw_degrees": angle["yaw"],
			"sample_count": 1,
			"samples_per_pixel": spp,
			"seed": 42,
		}

		var start_usec := Time.get_ticks_usec()
		var image: Image = tracer.trace_to_image(mesh, visual, request)
		var elapsed_ms := (Time.get_ticks_usec() - start_usec) / 1000.0

		if image == null:
			print("  FAIL: trace returned null")
			ok = false
			continue

		print("  Size: %dx%d, Time: %.1f ms" % [image.get_width(), image.get_height(), elapsed_ms])

		# Measure noise: compute local variance in a 3x3 neighborhood
		# for each non-transparent pixel. High variance = noise.
		var w := image.get_width()
		var h := image.get_height()
		var max_local_var := 0.0
		var total_var := 0.0
		var pixel_count := 0
		var high_noise_count := 0
		var noise_threshold := 0.015  # sRGB variance threshold for "noisy"

		for y in range(1, h - 1):
			for x in range(1, w - 1):
				var center := image.get_pixel(x, y)
				if center.a < 0.5:
					continue

				# Compute variance of luminance in 3x3 neighborhood
				var lum_sum := 0.0
				var lum_sq_sum := 0.0
				var count := 0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var p := image.get_pixel(x + ox, y + oy)
						if p.a < 0.5:
							continue
						var lum := 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
						lum_sum += lum
						lum_sq_sum += lum * lum
						count += 1

				if count < 5:
					continue

				var mean_lum := lum_sum / count
				var var_lum := maxf(lum_sq_sum / count - mean_lum * mean_lum, 0.0)

				# Also compute chrominance variance (detect chromatic noise)
				var rg_sum := 0.0
				var rg_sq := 0.0
				var gb_sum := 0.0
				var gb_sq := 0.0
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						var p := image.get_pixel(x + ox, y + oy)
						if p.a < 0.5:
							continue
						var rg := p.r - p.g
						var gb := p.g - p.b
						rg_sum += rg
						rg_sq += rg * rg
						gb_sum += gb
						gb_sq += gb * gb

				var chroma_var := maxf(rg_sq / count - (rg_sum / count) ** 2, 0.0) \
								+ maxf(gb_sq / count - (gb_sum / count) ** 2, 0.0)

				var combined_var := var_lum + chroma_var
				total_var += combined_var
				pixel_count += 1
				max_local_var = maxf(max_local_var, combined_var)
				if combined_var > noise_threshold:
					high_noise_count += 1

		var avg_var := total_var / maxf(pixel_count, 1)
		var noise_pct := 100.0 * high_noise_count / maxf(pixel_count, 1)

		print("  Pixels analyzed: %d" % pixel_count)
		print("  Avg local variance: %.6f" % avg_var)
		print("  Max local variance: %.6f" % max_local_var)
		print("  Noisy pixels (var>%.3f): %d (%.1f%%)" % [noise_threshold, high_noise_count, noise_pct])

		if noise_pct > 5.0:
			print("  WARNING: >5%% noisy pixels — chromatic noise likely visible")
			ok = false
		elif noise_pct > 1.0:
			print("  NOTE: 1-5%% noisy pixels — mild noise, may be acceptable")
		else:
			print("  CLEAN: <1%% noisy pixels")

		# Save the image for visual inspection
		var save_path := "user://trace_diagnostic_%s.png" % angle["name"]
		image.save_png(save_path)
		print("  Saved: %s" % save_path)
		print("")

	print("=== Diagnostic Complete ===")
	if ok:
		print("RESULT: PASS")
	else:
		print("RESULT: ISSUES DETECTED (see above)")
	quit(0 if ok else 1)
