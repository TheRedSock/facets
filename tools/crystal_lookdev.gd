extends SceneTree
## Physical clear-crystal diagnostics; source catalog milkiness is deliberately
## removed, never silently ignored by the crystal transport backend.
func _initialize() -> void:
	var worker := GemFrameWorker.new("res://artifacts/crystal-transport/store")
	var report := []
	for id in ["quartz", "ruby"]:
		var stone: GemStone = load("res://data/lapidary/stones/" + id + ".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material.scatter_per_mm = 0
		stone.condition = GemCondition.new()
		var jobs := GemFramePlan.animation(stone, load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.REFERENCE)
		var job := jobs[0]
		job.resolution = Vector2i(128, 128)
		job.output_size = job.resolution
		job.samples = 16
		job.quality["crystal_transport"] = true
		job.quality["volume"] = false
		job.quality["max_bounces"] = 256
		job.orientation = Quaternion(Vector3.UP, 0.3) * Quaternion(Vector3.RIGHT, -0.2)
		var started := Time.get_ticks_usec()
		var result := worker.run(job)
		var job_wall_ms := (Time.get_ticks_usec() - started) / 1000.0
		if result.is_empty():
			printerr(worker.last_error)
			worker.release()
			quit(1)
			return
		var record := worker.store.read(GemFramePlan.display_key(job))
		var image := Image.new()
		image.load_webp_from_buffer(record.payload)
		image.save_png("res://artifacts/crystal-transport/" + id + ".png")
		var master := worker.store.read(GemFramePlan.master_key(job))
		report.append({"stone": id, "job_wall_ms": job_wall_ms, "master": master.metadata, "counters": worker.counters.duplicate()})
		print(JSON.stringify(report[-1]))
	worker.release()
	GemArtifactStore.atomic_write("res://artifacts/crystal-transport/report.json", JSON.stringify(report, "\t").to_utf8_buffer())
	quit(0)
