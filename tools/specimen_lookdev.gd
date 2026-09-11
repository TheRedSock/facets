extends SceneTree
## Physical quality study: five presets, three poses and two authored rigs.
## --resolution=256 --samples=128 --seed=17 --quality=one_preset (optional)
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: args[pair[0]] = pair[1]
	var recipe: GemSpecimenRecipe = load("res://data/lapidary/recipes/quartz_condition_study.tres")
	var size := int(args.get("resolution", "256"))
	var samples := int(args.get("samples", "128"))
	var seed_value := int(args.get("seed", "17"))
	var sample_seed := int(args.get("sample-seed", "71"))
	var output := "res://artifacts/specimen-study/%d-%d-seed%d-samples%d-%s" % [size, samples, seed_value, sample_seed, args.get("quality", "all")]
	var worker := GemFrameWorker.new(output + "/store")
	var reports := []
	var row := 0
	var sheet := Image.create_empty(112 * 6, 112 * recipe.presets.size(), false, Image.FORMAT_RGBA8)
	for preset in recipe.presets:
		if args.has("quality") and args.quality != String(preset.preset_id): continue
		var result := GemSpecimenFactory.realize(recipe, preset.preset_id, seed_value)
		if not result.error.is_empty(): printerr("FAIL: " + result.error); worker.release(); quit(1); return
		DirAccess.make_dir_recursive_absolute(output)
		GemResourceBundle.save(result.stone, output.path_join(String(preset.preset_id) + ".res"))
		var column := 0
		for rig_name in ["gameplay_studio", "reference_daylight"]:
			for pose in 3:
				var job := GemFrameJob.new()
				job.stone = result.stone; job.rig = load("res://data/lapidary/rigs/" + rig_name + ".tres"); job.print_style = GemPrint.load_house()
				job.quality = GemRung.policy(GemRung.PREVIEW)
				job.resolution = Vector2i.ONE * size; job.output_size = job.resolution; job.samples = samples; job.sample_seed = sample_seed
				job.orientation = Quaternion(Vector3.UP, pose * 0.25) * Quaternion(Vector3.RIGHT, -0.15)
				job.rig_yaw = pose * 0.2
				var start := Time.get_ticks_usec()
				var counters_before := worker.counters.duplicate()
				var rendered := worker.run(job)
				if rendered.is_empty(): printerr("FAIL: " + worker.last_error); worker.release(); quit(1); return
				var elapsed := (Time.get_ticks_usec() - start) / 1000.0
				var image := Image.new()
				if image.load_webp_from_buffer(worker.store.read(GemFramePlan.display_key(job)).payload) != OK: worker.release(); quit(1); return
				var name := "%s-%s-%d" % [preset.preset_id, rig_name, pose]
				image.save_png(output.path_join(name + ".png"))
				var primary_key := GemFramePlan.display_key(job)
				job.output_size = Vector2i(112, 112)
				if worker.run(job).is_empty(): printerr("FAIL: sprite mastering"); worker.release(); quit(1); return
				var sprite := Image.new()
				if sprite.load_webp_from_buffer(worker.store.read(GemFramePlan.display_key(job)).payload) != OK: worker.release(); quit(1); return
				sprite.save_png(output.path_join(name + "-112.png"))
				sheet.blit_rect(sprite, Rect2i(0, 0, 112, 112), Vector2i(column * 112, row * 112))
				var report := {"preset": String(preset.preset_id), "rig": rig_name, "pose": pose, "frame_ms": elapsed,
					"display": primary_key, "sprite": GemFramePlan.display_key(job), "realization": result.report,
					"rendered": worker.counters.rendered - counters_before.rendered, "reprinted": worker.counters.reprinted - counters_before.reprinted,
					"cache_hits": worker.counters.display_hits - counters_before.display_hits}
				reports.append(report); print(JSON.stringify({"frame": name, "ms": elapsed})); column += 1
		row += 1
	worker.release()
	if row == 0: printerr("FAIL: no matching quality preset"); quit(1); return
	sheet.save_png(output.path_join("sheet.png"))
	GemArtifactStore.atomic_write(output.path_join("report.json"), JSON.stringify(reports, "\t", true, true).to_utf8_buffer())
	print("Specimen study: " + output); quit()
