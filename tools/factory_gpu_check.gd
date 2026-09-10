extends SceneTree
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate(true)
	stone.grade.crystal = 0.4
	var clip: GemClip = load("res://data/lapidary/clips/idle.tres")
	var jobs := GemFramePlan.animation(stone, clip, load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.PREVIEW)
	var job := jobs[0]
	job.resolution = Vector2i(64, 64)
	job.output_size = Vector2i(32, 32)
	job.samples = 16
	var root := "res://artifacts/factory-gpu/%d" % Time.get_ticks_usec()
	var worker := GemFrameWorker.new(root)
	var partial := worker.run(job, 5)
	check(partial.get("status") == "partial" and partial.get("samples") == 5, "partial render checkpoint")
	worker.release()
	worker = GemFrameWorker.new(root)
	var finished := worker.run(job)
	check(finished.get("status") == "complete" and worker.counters["resumed_samples"] == 5, "new worker resumes exact sample position")
	var cached := worker.run(job)
	check(cached.get("status") == "complete" and worker.counters["display_hits"] == 1, "completed frame avoids GPU work")
	var master_key := GemFramePlan.master_key(job)
	job.exposure = 0.75
	worker.run(job)
	check(worker.counters["rendered"] == 1 and worker.counters["reprinted"] == 1, "new exposure reuses stored linear master")
	var resumed := GemArtifactStore.decode_linear(worker.store.read(master_key)["payload"])
	worker.release()
	worker = GemFrameWorker.new(root + "_whole")
	job.exposure = 1.0
	worker.run(job)
	var whole := GemArtifactStore.decode_linear(worker.store.read(master_key)["payload"])
	var max_error := 0.0
	var a := resumed.get_data().to_float32_array()
	var b := whole.get_data().to_float32_array()
	for i in a.size():
		max_error = maxf(max_error, absf(a[i] - b[i]))
	check(max_error < 0.00001, "resumed reconstruction matches uninterrupted rendering: %.8f" % max_error)
	worker.release()
	print("Factory GPU: %d failures; checkpoint difference %.8f" % [failures, max_error])
	quit(1 if failures else 0)
