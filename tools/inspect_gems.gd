extends SceneTree
## Production-path catalog stills and independent-stream noise inspection.
## --stones=quartz,ruby --size=112 --samples=128 --output=res://artifacts/inspection
## --plan-only validates and saves requests without requiring a GPU.
var error := ""

func _initialize() -> void:
	var options := {"stones": "", "size": "112", "samples": "128", "output": "res://artifacts/inspection", "rung": "clip_bake"}
	var plan_only := false
	for argument in OS.get_cmdline_user_args():
		if argument == "--plan-only": plan_only = true; continue
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if not argument.begins_with("--") or pair.size() != 2 or not options.has(pair[0]): _fail("Unknown or missing option: " + argument); return
		options[pair[0]] = pair[1]
	for key in ["size", "samples"]:
		if not String(options[key]).is_valid_int() or int(options[key]) < 1: _fail("Expected positive integer: " + key); return
	if int(options.size) > 2048 or int(options.samples) > 65536: _fail("Inspection size/sample limit exceeded"); return
	var names := PackedStringArray()
	for file in DirAccess.get_files_at("res://data/lapidary/stones"):
		if file.ends_with(".tres"): names.append(file.get_basename())
	names.sort()
	var selected := String(options.stones).split(",", false) if not String(options.stones).is_empty() else names
	var batch := GemAssetBatch.new()
	for id in selected:
		if id not in names: _fail("Unknown stone: " + id); return
		var request := GemAssetRequest.new()
		request.asset_id = StringName(id)
		request.stone = load("res://data/lapidary/stones/%s.tres" % id)
		request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
		request.print_style = GemPrint.load_house()
		request.clips = [load("res://data/lapidary/clips/idle.tres")]
		request.rung = options.rung
		request.resolution = Vector2i.ONE * int(options.size) * 2
		request.output_size = Vector2i.ONE * int(options.size)
		request.samples = int(options.samples)
		batch.requests.append(request)
	var planned := GemAssetPlanner.plan(batch)
	if not planned.error.is_empty(): _fail(planned.error); return
	var output: String = options.output
	if DirAccess.make_dir_recursive_absolute(output) != OK or GemResourceBundle.save(batch, output.path_join("request.res")) != OK: _fail("Cannot save inspection request"); return
	var report := {"status": "planned", "estimate": planned.estimate, "options": options, "specimens": planned.specimens, "results": [], "noise_metric": "opaque-pixel encoded-RGB two-stream RMSE / sqrt(2), in 8-bit LSB; sampling variation, not model error"}
	if plan_only:
		if not _save_report(output, report): _fail("Cannot save report"); return
		print("INSPECTION PLANNED: ", JSON.stringify(planned.estimate)); quit(); return
	var worker := GemFrameWorker.new(output.path_join("store"))
	var tiles := []
	for index in planned.jobs.size():
		var job: GemFrameJob = planned.jobs[index]
		var images: Array[Image] = []
		var frame_report := {"asset": String(batch.requests[index].asset_id), "streams": []}
		for stream in 2:
			job.sample_seed = job.stone.seed + stream * 91711
			var start := Time.get_ticks_usec()
			var result := worker.run(job)
			if result.get("status") != "complete": worker.release(); _fail(worker.last_error); return
			var image := GemFrameWorker._display_image(worker.store.read(GemFramePlan.display_key(job)), job, GemFramePlan.display_engine(job))
			if image == null: worker.release(); _fail("Cannot decode completed frame"); return
			var path := output.path_join("%s-%d.png" % [frame_report.asset, stream])
			if image.save_png(path) != OK: worker.release(); _fail("Cannot save frame"); return
			images.append(image)
			frame_report.streams.append({"sample_seed": job.sample_seed, "master": result.master, "display": GemFramePlan.display_key(job), "wall_ms": (Time.get_ticks_usec() - start) / 1000.0, "png_sha256": FileAccess.get_sha256(path)})
		var count := 0
		var squared := 0.0
		for y in images[0].get_height():
			for x in images[0].get_width():
				var a := images[0].get_pixel(x, y); var b := images[1].get_pixel(x, y)
				if minf(a.a, b.a) < 0.99: continue
				squared += Vector3(a.r-b.r, a.g-b.g, a.b-b.b).length_squared(); count += 3
		if count == 0: worker.release(); _fail("Empty opaque comparison domain"); return
		frame_report.noise_lsb = sqrt(squared / count / 2.0) * 255.0
		frame_report.channels = count
		report.results.append(frame_report)
		tiles.append({"image": images[0], "label": frame_report.asset})
	worker.release()
	if LapidarySheetComposer.compose(tiles, mini(4, tiles.size())).save_png(output.path_join("sheet.png")) != OK: _fail("Cannot save sheet"); return
	report.status = "complete"; report.counters = worker.counters
	if not _save_report(output, report): _fail("Cannot save report"); return
	print("INSPECTION COMPLETE: ", selected.size(), " specimens, saved request and paired-stream evidence")
	quit()

func _save_report(output: String, report: Dictionary) -> bool:
	return GemArtifactStore.atomic_write(output.path_join("report.json"), JSON.stringify(report, "  ").to_utf8_buffer())

func _fail(message: String) -> void:
	printerr("FAIL: " + message); quit(1)
