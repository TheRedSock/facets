extends SceneTree
## Independent-seed low-SPP/reconstructed and raw reference appearance check.
func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm = 0.0
	stone.condition.banding.contrast = 0.0
	var lights := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["spectral_geometry"] = "full"
	policy["birefringence"] = false
	policy["max_bounces"] = 256
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var sheet := Image.create(1024, 512, false, Image.FORMAT_RGBA8)
	var cases := [
		{"name": "polished", "alpha": 0.0, "multiple": false, "scatter": 0.0},
		{"name": "single_scattering", "alpha": 0.3, "multiple": false, "scatter": 0.0},
		{"name": "smith_multiple", "alpha": 0.3, "multiple": true, "scatter": 0.0},
		{"name": "smith_milk", "alpha": 0.15, "multiple": true, "scatter": 0.3}]
	var out := "res://artifacts/microsurface/lookdev"
	DirAccess.make_dir_recursive_absolute(out)
	var reports := []
	for column in cases.size():
		var item: Dictionary = cases[column]
		stone.condition.finish.alpha_u = item.alpha
		stone.condition.finish.alpha_v = item.alpha
		stone.condition.finish.multiple_scattering = item.multiple
		stone.material.scatter_per_mm = item.scatter
		var compiled := LapidaryStoneCompiler.compile(stone)
		if not tracer.configure_stone(compiled, lights, policy):
			printerr(tracer.configuration_error)
			quit(1)
			return
		tracer.set_clip_sample(Quaternion(Vector3.RIGHT, deg_to_rad(-12.0)), 0.0, Vector4.ONE, 1.25)
		tracer.set_seed(8123)
		var low_ms := tracer.accumulate(128)
		var low := tracer.finalize_print(GemPrint.load_house())
		var low_raw := tracer.finalize_print(GemPrint.load_house(), GemPrint.View.HOUSE_PRINT, 1.0, Vector2i.ZERO, false)
		if not tracer.transport_error().is_empty():
			printerr("FAIL: " + tracer.transport_error())
			quit(1)
			return
		tracer.reset_accumulation()
		tracer.set_seed(8591)
		var high_ms := tracer.accumulate(2048)
		var high := tracer.finalize_print(GemPrint.load_house(), GemPrint.View.HOUSE_PRINT, 1.0, Vector2i.ZERO, false)
		if not tracer.transport_error().is_empty():
			printerr("FAIL: " + tracer.transport_error())
			quit(1)
			return
		low.save_png(out.path_join(item.name+"_128.png"))
		low_raw.save_png(out.path_join(item.name+"_128_raw.png"))
		high.save_png(out.path_join(item.name+"_2048.png"))
		sheet.blit_rect(low, Rect2i(0, 0, 256, 256), Vector2i(column*256, 0))
		sheet.blit_rect(high, Rect2i(0, 0, 256, 256), Vector2i(column*256, 256))
		item["low_ms"] = low_ms
		item["reference_ms"] = high_ms
		item["filtered_error"] = GemPagePacker.compression_error(high.get_data(), low.get_data())
		item["raw_error"] = GemPagePacker.compression_error(high.get_data(), low_raw.get_data())
		item["diagnostics"] = tracer.surface_diagnostics()
		reports.append(item)
		print(JSON.stringify(item))
	tracer.release()
	sheet.save_png(out.path_join("comparison.png"))
	var report := {"results": reports, "resolution": 256, "samples": [128, 2048], "seeds": [8123, 8591],
		"engine": GemRenderIdentity.pipeline_digest("scalar"), "print_engine": GemRenderIdentity.pipeline_digest("print"),
		"policy": policy, "godot": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name()}
	GemArtifactStore.atomic_write(out.path_join("report.json"), JSON.stringify(report, "\t").to_utf8_buffer())
	quit()
