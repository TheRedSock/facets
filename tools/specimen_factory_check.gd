extends SceneTree
## Portable realized quality states; optical workers never evaluate the recipe.
func _initialize() -> void:
	var recipe: GemSpecimenRecipe = load("res://data/lapidary/recipes/quartz_condition_study.tres")
	var jobs: Array[GemFrameJob] = []
	var clips := {}
	for preset in recipe.presets:
		var realized := GemSpecimenFactory.realize(recipe, preset.preset_id, 17)
		if not realized.error.is_empty(): printerr("FAIL: " + realized.error); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
		var ids := []
		for pose in 2:
			var job := GemFrameJob.new()
			job.stone = realized.stone
			job.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
			job.print_style = GemPrint.load_house(); job.quality = GemRung.policy(GemRung.INTERACT)
			job.resolution = Vector2i(48, 48); job.output_size = Vector2i(32, 32); job.samples = 16
			job.orientation = Quaternion(Vector3.UP, pose * 0.3)
			jobs.append(job); ids.append(GemFramePlan.display_key(job))
		clips["quartz/" + String(preset.preset_id)] = {"frames": ids, "fps": 2, "loop": false}
	var root_path := ProjectSettings.globalize_path("res://artifacts/specimen-factory/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var bundle := root_path.path_join("worker")
	var output := root_path.path_join("store")
	var manifest := GemJobBundle.write(bundle, jobs, clips, 2)
	if manifest.is_empty(): printerr("FAIL: cannot package realized specimens"); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
	for key: String in manifest.jobs:
		var saved: GemFrameJob = load(bundle.path_join(manifest.jobs[key].path))
		if saved.stone.get_meta("realization", {}).get("recipe_id") != String(recipe.recipe_id):
			printerr("FAIL: portable realization provenance missing"); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
	var run := PackedStringArray(["--script", "res://tools/gem_frame_worker.gd", "--", "--output=" + output])
	var cached := run.duplicate(); cached.insert(0, "--headless")
	var stages := [PackedStringArray(["--headless", "--editor", "--quit"]), run, cached]
	for index in stages.size():
		var arguments := PackedStringArray(["--audio-driver", "Dummy", "--path", bundle, "--quit-after", "600"])
		arguments.append_array(stages[index])
		var lines := []
		var code := OS.execute(OS.get_executable_path(), arguments, lines, true, false)
		var log_text := "\n".join(lines)
		GemArtifactStore.atomic_write(root_path.path_join("stage-%d.log" % index), log_text.to_utf8_buffer())
		if code != 0 or "SCRIPT ERROR:" in log_text or "ERROR:" in log_text:
			printerr("FAIL: portable specimen worker: " + log_text); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
	var store := GemArtifactStore.new(output)
	for job in jobs:
		if store.read(GemFramePlan.display_key(job)).is_empty() or store.read(GemGeometryPlan.key(job, 2)).is_empty():
			printerr("FAIL: missing realized specimen result"); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
	var packer := GemPagePacker.new(store, root_path.path_join("library"))
	var library := packer.pack(clips)
	if library.is_empty() or int(library.statistics.frame_count) != jobs.size():
		printerr("FAIL: specimen delivery packing"); print("CHECK_COMPLETE: specimen_factory_check"); quit(1); return
	print("Specimen factory PASS: five quality states, two poses, portable provenance, geometry, headless cache and delivery; " + root_path)
	print("CHECK_COMPLETE: specimen_factory_check"); quit()
