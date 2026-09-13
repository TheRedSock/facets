extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)
func bounds(aov: GemGeometryAov) -> Rect2i:
	var lower := Vector2i(aov.width, aov.height); var upper := Vector2i(-1, -1)
	for y in aov.height:
		for x in aov.width:
			if aov.record(x, y).coverage > 0:
				lower = lower.min(Vector2i(x, y)); upper = upper.max(Vector2i(x, y))
	return Rect2i(lower, upper - lower + Vector2i.ONE)
func _initialize() -> void:
	var output := "res://artifacts/presentation-check"
	DirAccess.make_dir_recursive_absolute(output)
	var worker := GemFrameWorker.new(output + "/store")
	var tracer := GemTracer.create(256, 256)
	if tracer == null: print("CHECK_COMPLETE: presentation_check"); quit(1); return
	var reports := []
	for file in DirAccess.get_files_at("res://data/lapidary/stones"):
		if not file.ends_with(".tres"): continue
		var stone: GemStone = load("res://data/lapidary/stones/" + file)
		var clip := GemClip.new(); clip.clip_id = &"idle"; clip.duration_s = 1; clip.fps = 1
		clip.orientation_keys = [GemOrientationKey.new(0.0,Quaternion(Vector3.RIGHT,deg_to_rad(-12))) ]
		var request := GemAssetRequest.new(); request.asset_id = stone.stone_id; request.stone = stone
		request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres"); request.print_style = GemPrint.load_house()
		request.resolution = Vector2i(256, 256); request.output_size = request.resolution; request.samples = 128; request.clips.append(clip)
		var batch := GemAssetBatch.new(); batch.requests.append(request)
		var planned := GemAssetPlanner.plan(batch)
		check(planned.error.is_empty(), file + " plan")
		if not planned.error.is_empty(): continue
		var job: GemFrameJob = planned.jobs[0]
		check(tracer.configure_stone(LapidaryStoneCompiler.compile(stone), GemRigCompiler.compile(job.rig), job.quality), file + " configure")
		tracer.set_clip_sample(job.orientation, job.rig_yaw, job.role_multipliers, job.ortho_half, job.camera_offset)
		var aov := tracer.geometry_aov(4)
		var box := bounds(aov)
		var center := Vector2(box.position) + Vector2(box.size - Vector2i.ONE) * 0.5
		check(center.distance_to(Vector2(127.5, 127.5)) <= 0.71, file + " raster coverage centered")
		check(box.position.x > 0 and box.position.y > 0 and box.end.x < 256 and box.end.y < 256, file + " unclipped")
		aov.normal_image().save_png(output.path_join(String(stone.stone_id) + "-geometry.png"))
		reports.append({"stone": stone.stone_id, "center": [center.x, center.y], "bounds": [box.position.x, box.position.y, box.size.x, box.size.y]})
		if stone.shape.outline == &"pear":
			var result := worker.run(job)
			check(not result.is_empty(), file + " optical render")
			if not result.is_empty():
				var image := Image.new(); image.load_webp_from_buffer(worker.store.read(GemFramePlan.display_key(job)).payload)
				image.save_png(output.path_join(String(stone.stone_id) + ".png"))
	# Independent image-grid translation check: +8 pixel camera shift moves coverage left eight.
	var stone: GemStone = load("res://data/lapidary/stones/diamond.tres")
	tracer.configure_stone(LapidaryStoneCompiler.compile(stone), GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres")), GemRung.policy(GemRung.PREVIEW))
	tracer.set_clip_sample(Quaternion.IDENTITY, 0.0)
	var origin := tracer.geometry_aov(2)
	tracer.set_clip_sample(Quaternion.IDENTITY, 0.0, Vector4.ONE, 1.25, Vector2(8.0 * 2.5 / 256, 0))
	var shifted := tracer.geometry_aov(2)
	var mismatches := 0
	for y in 256:
		for x in 248:
			if origin.record(x + 8, y).coverage != shifted.record(x, y).coverage: mismatches += 1
	check(mismatches == 0, "camera origin shift equals an independent eight-pixel grid translation")
	# Compile and exercise the shared camera mapping in every optical backend.
	for mode in ["scalar", "polarized", "crystal"]:
		var job := GemFrameJob.new()
		job.stone = load("res://data/lapidary/stones/" + ("diamond" if mode == "polarized" else "quartz") + ".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		job.stone.material.scatter_per_mm = 0; job.stone.condition = GemCondition.new()
		job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres"); job.print_style = GemPrint.load_house()
		job.resolution = Vector2i(64, 64); job.output_size = job.resolution; job.samples = 16
		job.orientation = Quaternion.from_euler(Vector3(0.1, 0.2, 0)); job.camera_offset = Vector2(0.18, -0.11)
		job.quality = GemRung.policy(GemRung.PREVIEW)
		if mode == "polarized": job.quality["polarization"] = true
		if mode == "crystal": job.quality["crystal_transport"] = true
		var result := worker.run(job)
		check(not result.is_empty(), mode + " camera render")
		if not result.is_empty():
			var optical := Image.new(); optical.load_webp_from_buffer(worker.store.read(GemFramePlan.display_key(job)).payload)
			var probe := GemTracer.create(64, 64)
			check(probe.configure_stone(LapidaryStoneCompiler.compile(job.stone), GemRigCompiler.compile(job.rig), job.quality), mode + " probe configuration")
			probe.set_clip_sample(job.orientation, job.rig_yaw, job.role_multipliers, job.ortho_half, job.camera_offset)
			var expected := bounds(probe.geometry_aov(4))
			probe.release()
			var actual := optical.get_used_rect()
			check(Vector2(expected.position-actual.position).length() <= 1.5 and Vector2(expected.end-actual.end).length() <= 1.5, mode + " optical/geometry framing parity")
	tracer.release(); worker.release()
	GemArtifactStore.atomic_write(output.path_join("report.json"), JSON.stringify(reports, "\t").to_utf8_buffer())
	print("Presentation GPU: %d checks, %d failures" % [checks, failures]); print("CHECK_COMPLETE: presentation_check"); quit(1 if failures else 0)
