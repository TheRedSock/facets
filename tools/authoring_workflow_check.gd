extends SceneTree
## End-to-end durable authoring -> frozen request -> production factory/cache.
func _initialize() -> void:
	var destination := "res://artifacts/authoring-workflow/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(destination)
	var document := GemAuthoringDocument.new()
	var error := document.open("res://data/lapidary/stones/ruby.tres")
	if error.is_empty(): error = document.edit(["stone_id"], &"authored_ruby")
	if error.is_empty(): error = document.edit(["material", "absorbers", 0, "amount"], 0.73)
	if error.is_empty(): error = document.save(destination.path_join("authored ruby ø.tres"))
	if error.is_empty(): error = document.open(document.path)
	if not error.is_empty(): _fail(error); return
	var request := GemAssetRequest.new()
	request.asset_id = &"authored_ruby"; request.stone = document.snapshot()
	request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	request.print_style = GemPrint.load_house()
	request.clips = [load("res://data/lapidary/clips/idle.tres")]
	request.rung = "interact"; request.samples = 16
	request.resolution = Vector2i(64, 64); request.output_size = Vector2i(32, 32)
	var input := GemAuthoringDocument.new(); input.create(request)
	error = input.freeze(destination.path_join("request.res"))
	if not error.is_empty(): _fail(error); return
	error = input.open(destination.path_join("request.res"))
	if not error.is_empty(): _fail(error); return
	var batch := GemAssetBatch.new(); batch.requests = [input.snapshot()]
	var planned := GemAssetPlanner.plan(batch)
	if not planned.error.is_empty(): _fail(planned.error); return
	var job: GemFrameJob = planned.jobs[0]
	var worker := GemFrameWorker.new(destination.path_join("store"))
	var start := Time.get_ticks_msec()
	var rendered := worker.run(job)
	if rendered.get("status") != "complete": worker.release(); _fail(str(rendered)); return
	var original_key := GemFramePlan.display_key(job)
	var image := GemFrameWorker._display_image(worker.store.read(original_key), job, GemFramePlan.display_engine(job))
	if image == null or image.get_size() != request.output_size or image.get_pixel(16, 16).a < 0.5:
		worker.release(); _fail("Built image missing or incorrectly framed"); return
	if image.save_png(destination.path_join("saved-preview.png")) != OK:
		worker.release(); _fail("Cannot save validation image"); return
	var before := worker.counters.duplicate()
	job.stone.material.source_note = "Edited evidence only"
	job.stone.material.species.display_name = "Renamed species"
	job.stone.material.absorbers[0].chromophore.display_name = "Renamed absorber"
	var reused := worker.run(job)
	if reused.get("status") != "complete" or GemFramePlan.display_key(job) != original_key or worker.counters.rendered != before.rendered or worker.counters.display_hits != before.display_hits + 1:
		worker.release(); _fail("Metadata-only edit caused optical work"); return
	job.print_style = job.print_style.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.print_style.exposure *= 0.9
	if worker.run(job).get("status") != "complete" or worker.counters.rendered != 1 or worker.counters.reprinted != 1:
		worker.release(); _fail("Print-only change did not reuse master"); return
	job.stone.material.absorbers[0].amount *= 0.5
	if worker.run(job).get("status") != "complete" or worker.counters.rendered != 2:
		worker.release(); _fail("Physical change failed to retrace"); return
	var report := {"status": "passed", "counters": worker.counters, "wall_ms": Time.get_ticks_msec() - start,
		"request_sha256": FileAccess.get_sha256(destination.path_join("request.res")), "image_sha256": FileAccess.get_sha256(destination.path_join("saved-preview.png"))}
	worker.release()
	if not GemArtifactStore.atomic_write(destination.path_join("report.json"), JSON.stringify(report, "\t").to_utf8_buffer()): _fail("Cannot publish report"); return
	print("Authoring workflow PASS: " + destination + " " + JSON.stringify(report))
	print("CHECK_COMPLETE: authoring_workflow_check"); quit()

func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	print("CHECK_COMPLETE: authoring_workflow_check"); quit(1)
