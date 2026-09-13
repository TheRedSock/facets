extends SceneTree
## Windowed parent checks actual library textures; standalone workers render/replay.
func _initialize() -> void:
	var batch: GemAssetBatch = load("res://data/lapidary/batches/quartz_quality_lighting.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var clip := GemClip.new()
	clip.clip_id = &"inspect"; clip.duration_s = 1; clip.fps = 2; clip.loop = false
	clip.stone_motion = GemClip.StoneMotion.TURNTABLE; clip.turntable_degrees = 30
	for request in batch.requests:
		request.clips = [clip]; request.rung = "interact"
		request.resolution = Vector2i(48, 48); request.output_size = Vector2i(32, 32); request.samples = 16
	var alias: GemAssetRequest = batch.requests[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	alias.asset_id = &"quartz_reference_alias"; batch.requests.append(alias)
	var planned := GemAssetPlanner.plan(batch)
	if not planned.error.is_empty(): _fail(planned.error); return
	if planned.jobs.size() != 10 or planned.estimate.unique_masters != 8 or planned.estimate.unique_displays != 8:
		_fail("Variant/alias expansion does not match explicit demand"); return
	var path := ProjectSettings.globalize_path("res://artifacts/asset-batch/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var bundle := path.path_join("worker")
	var output := path.path_join("store")
	var manifest := GemJobBundle.write(bundle, planned.jobs, planned.clips, batch.geometry_coverage_side)
	if manifest.is_empty(): _fail("Cannot package asset batch"); return
	if manifest.geometry.size() != 4: _fail("Lighting variants should share four geometry companions"); return
	var run := PackedStringArray(["--script", "res://tools/gem_frame_worker.gd", "--", "--output=" + output])
	var cached := run.duplicate(); cached.insert(0, "--headless")
	var stages := [PackedStringArray(["--headless", "--editor", "--quit"]), run, cached]
	for stage in stages.size():
		var arguments := PackedStringArray(["--audio-driver", "Dummy", "--path", bundle, "--quit-after", "600"])
		arguments.append_array(stages[stage])
		var lines := []
		var code := OS.execute(OS.get_executable_path(), arguments, lines, true, false)
		var log_text := "\n".join(lines)
		GemArtifactStore.atomic_write(path.path_join("stage-%d.log" % stage), log_text.to_utf8_buffer())
		if code != 0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text or "FAIL:" in log_text:
			_fail("Standalone batch worker: " + log_text); return
		if stage == 2:
			var last_display := {}; var last_geometry := {}
			for line in log_text.split("\n"):
				if not line.begins_with("{"): continue
				var value: Variant = JSON.parse_string(line)
				if value is Dictionary and value.has("job"): last_display = value.counters
				if value is Dictionary and value.has("geometry"): last_geometry = value.counters
			if last_display.get("display_hits") != 8 or last_display.get("rendered") != 0 or last_display.get("reprinted") != 0 or last_geometry.get("cache_hits") != 4 or last_geometry.get("generated") != 0:
				_fail("Headless batch must reuse eight displays and four shared geometries"); return
	var packer := GemPagePacker.new(GemArtifactStore.new(output), path.path_join("library"))
	var index := packer.pack(planned.clips)
	if index.is_empty() or index.statistics.frame_count != 8 or index.clips.size() != 5:
		_fail("Packed variants lost their aliases or retained duplicate frames"); return
	var library := GemAssetLibrary.new()
	if not library.open(path.path_join("library/library.json")): _fail(library.last_error); return
	if library.page_loads != 0: _fail("Opening metadata eagerly loaded textures"); return
	var a := library.frame("quartz_reference/inspect", 0)
	var b := library.frame("quartz_reference_alias/inspect", 0)
	if a == null or b == null or a.atlas != b.atlas or library.page_loads != 1:
		_fail("Identical delivery aliases should share the selectively loaded page"); return
	for request in batch.requests:
		if library.frame(String(request.asset_id) + "/inspect", 1) == null:
			_fail("Missing separately addressable variant texture"); return
	print("Asset batch PASS: 5 variants/aliases, 10 requested frames, 8 optical masters, portable cache and selective library; " + path)
	print("CHECK_COMPLETE: asset_batch_check"); quit()

func _fail(message: String) -> void:
	printerr("FAIL: " + message); print("CHECK_COMPLETE: asset_batch_check"); quit(1)
