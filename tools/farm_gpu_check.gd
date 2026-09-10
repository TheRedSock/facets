extends SceneTree
## Two independent worker stores -> verified consolidation -> GPU-free cache hits.
func _initialize() -> void:
	var root := "res://artifacts/farm-gpu/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var clip: GemClip = load("res://data/lapidary/clips/flash.tres")
	var jobs: Array[GemFrameJob] = []
	var sources := PackedStringArray()
	var manifest := {"schema": 1, "engine": GemRenderIdentity.optical_digest(), "jobs": {}}
	var failures := 0
	for id in ["quartz", "diamond"]:
		var worker := GemFrameWorker.new(root.path_join(id))
		sources.append(worker.store.root)
		var frames := GemFramePlan.animation(load("res://data/lapidary/stones/" + id + ".tres"), clip, rig, GemPrint.load_house(), GemRung.PREVIEW)
		for job in frames:
			job.resolution = Vector2i(32, 32)
			job.output_size = Vector2i(24, 24)
			job.samples = 16
			jobs.append(job)
			manifest.jobs[GemFramePlan.display_key(job)] = {"master": GemFramePlan.master_key(job)}
			if worker.run(job).is_empty():
				failures += 1
		if worker.counters.rendered != 1:
			failures += 1
		worker.release()
	var destination := GemArtifactStore.new(root.path_join("merged"))
	if not destination.initialize():
		failures += 1
	var transfer := GemStoreTransfer.new()
	var merged := transfer.merge(destination.root, sources, manifest, true)
	if merged.is_empty() or not merged.get("missing", [0]).is_empty():
		printerr(transfer.last_error)
		failures += 1
	var consumer := GemFrameWorker.new(destination.root)
	for job in jobs:
		if consumer.run(job).is_empty():
			failures += 1
	if consumer.tracer != null or consumer.counters.display_hits != jobs.size():
		failures += 1
	consumer.release()
	var retry := transfer.merge(destination.root, sources, manifest, true)
	if retry.get("recipes_to_import", -1) != 0:
		failures += 1
	var report := {"failures": failures, "jobs": jobs.size(), "merge": merged, "consumer": consumer.counters}
	GemArtifactStore.atomic_write(root.path_join("report.json"), JSON.stringify(report, "\t").to_utf8_buffer())
	print("Farm GPU: " + JSON.stringify(report))
	quit(1 if failures else 0)
