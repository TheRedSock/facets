extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var source := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
	for y in range(1, 6):
		for x in range(1, 6):
			source.set_pixel(x, y, Color(0.8, 0.3, 0.1, 0.5 if x == 1 else 1))
	var original := source.get_data()
	var style := GemStyle.new()
	check(GemStylePipeline.apply(source, null).get_data() == original, "absent style preserves exact bytes")
	check(GemStylePipeline.apply(source, style).get_data() == original, "identity preserves exact bytes")
	style.saturation = 0
	var gray := GemStylePipeline.apply(source, style)
	var c := gray.get_pixel(3, 3)
	check(c.r == c.g and c.g == c.b, "zero saturation is neutral")
	# Independent sRGB decoding/encoding calculation for the linear luminance.
	var input := source.get_pixel(3, 3)
	var y_linear := decode(input.r) * 0.2126 + decode(input.g) * 0.7152 + decode(input.b) * 0.0722
	check(absf(c.r - encode(y_linear)) <= 0.5 / 255.0 + 1e-7, "neutral tone follows linear luminance")
	style = GemStyle.new(); style.contour_pixels = 1; style.contour_opacity = 1
	var contour := GemStylePipeline.apply(source, style)
	check(contour.get_pixel(5, 3).r == 0 and contour.get_pixel(3, 3) == source.get_pixel(3, 3), "inner contour changes boundary and preserves interior")
	for test_style in [style, load("res://data/lapidary/styles/illustrative_sprite.tres")]:
		var output := GemStylePipeline.apply(source, test_style)
		for i in 49:
			check(output.get_data()[i * 4 + 3] == original[i * 4 + 3], "coverage byte preserved")
		check(output.get_data() == GemStylePipeline.apply(source, test_style).get_data(), "deterministic style")
	check(source.get_data() == original, "input image remains immutable")
	style.contour_pixels = 5
	check(not style.validate().is_empty() and GemStylePipeline.apply(source, style) == null, "invalid style rejected")
	style = GemStyle.new(); style.tint.a = 0.5
	check(not style.validate().is_empty(), "color alpha cannot alter physical coverage")
	style = GemStyle.new(); style.contrast = NAN
	check(not style.validate().is_empty(), "nonfinite style rejected")
	var job := GemFramePlan.animation(load("res://data/lapidary/stones/quartz.tres"), load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.INTERACT)[0]
	var master_key := GemFramePlan.master_key(job)
	var print_key := GemFramePlan.print_key(job)
	job.game_style = GemStyle.new()
	check(GemFramePlan.display_key(job) == print_key, "identity style shares print recipe")
	job.game_style = load("res://data/lapidary/styles/illustrative_sprite.tres")
	check(GemFramePlan.display_key(job) != print_key and GemFramePlan.print_key(job) == print_key and GemFramePlan.master_key(job) == master_key, "styling changes only final recipe")
	check(GemGeometryPlan.key(job, 1) == geometry_without_style(job), "style does not change geometry companion")
	job.resolution = Vector2i(7, 7); job.output_size = Vector2i(7, 7)
	var worker := GemFrameWorker.new("res://artifacts/style-tests/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	check(worker.store.publish(GemFramePlan.print_key(job), source.save_webp_to_buffer(false), {"kind": "display", "master": GemFramePlan.master_key(job), "engine": GemRenderIdentity.pipeline_digest("print"), "width": 7, "height": 7, "codec": "webp_lossless", "space": "srgb_straight_alpha", "status": "complete"}), "publish cached print fixture")
	check(worker.run(job).get("status") == "complete" and worker.tracer == null, "restyle cached print headlessly without GPU")
	check(worker.counters.restyled == 1 and worker.counters.rendered == 0 and worker.counters.reprinted == 0, "restyling avoids trace and mastering")
	check(worker.run(job).get("status") == "complete" and worker.counters.display_hits == 1, "styled frame cache hit")
	worker.release()
	print("Style: %d checks, %d failures" % [checks, failures]); print("CHECK_COMPLETE: test_style"); quit(1 if failures else 0)

func geometry_without_style(job: GemFrameJob) -> String:
	var copy: GemFrameJob = job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	copy.game_style = null
	return GemGeometryPlan.key(copy, 1)

func decode(value: float) -> float:
	return value / 12.92 if value <= 0.04045 else pow((value + 0.055) / 1.055, 2.4)

func encode(value: float) -> float:
	return value * 12.92 if value <= 0.0031308 else 1.055 * pow(value, 1.0 / 2.4) - 0.055
