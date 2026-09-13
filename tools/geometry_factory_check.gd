extends SceneTree
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var jobs := GemFramePlan.animation(stone, load("res://data/lapidary/clips/flash.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.INTERACT)
	for job in jobs:
		job.resolution = Vector2i(64, 64)
		job.output_size = Vector2i(32, 32)
		job.samples = 8
	var root := "res://artifacts/geometry-factory-gpu/%d" % Time.get_ticks_usec()
	var geometry_worker := GemGeometryWorker.new(root + "/source")
	var job := jobs[0]
	var result := geometry_worker.run(job, 4)
	check(result.get("optical_samples") == 0 and geometry_worker.counters.generated == 1, "companion generated with zero optical samples")
	var geometry_key := GemGeometryPlan.key(job, 4)
	var original := geometry_worker.store.read(geometry_key)
	var decoded := GemGeometryAov.decode(original.payload)
	check(decoded != null and decoded.width == 64 and decoded.coverage_side == 4, "actual GPU companion decodes")
	decoded.normal_image().save_png(ProjectSettings.globalize_path(root + "/normals.png"))
	geometry_worker.release()
	geometry_worker = GemGeometryWorker.new(root + "/source")
	job.stone.material.scatter_per_mm = 0.5
	job.exposure = 1.7
	job.sample_seed = 22
	result = geometry_worker.run(job, 4)
	check(not result.is_empty() and geometry_worker.tracer == null and geometry_worker.counters.cache_hits == 1, "changed optical inputs use cached geometry without creating a tracer")
	job.orientation = Quaternion(Vector3.UP, 0.2)
	geometry_worker.run(job, 4)
	check(geometry_worker.counters.generated == 1 and geometry_worker.tracer.samples_accumulated == 0, "new pose generates geometry only")
	geometry_worker.release()
	var clip_ids := []
	var worker := GemFrameWorker.new(root + "/source")
	for frame in jobs:
		check(not worker.run(frame).is_empty(), "optical frame remains independently renderable")
		clip_ids.append(GemFramePlan.display_key(frame))
	worker.release()
	var clips := {"quartz/flash": {"frames": clip_ids, "fps": 30.0, "loop": false}}
	var bundle := GemJobBundle.write(root + "/bundle", jobs, clips, 4)
	bundle = JSON.parse_string(JSON.stringify(bundle))
	for frame in jobs:
		geometry_worker.run(frame, 4)
	geometry_worker.release()
	var destination := GemArtifactStore.new(root + "/merged")
	check(destination.initialize(), "initialize isolated farm destination")
	var transfer := GemStoreTransfer.new()
	var merged := transfer.merge(destination.root, PackedStringArray([root + "/source"]), bundle, true)
	check(not merged.is_empty() and merged.get("missing", []).is_empty(), "all requested geometry and optical farm results merge: " + transfer.last_error)
	var consumer := GemGeometryWorker.new(destination.root)
	for frame in jobs:
		consumer.run(frame, 4)
	check(consumer.tracer == null and consumer.counters.cache_hits == jobs.size(), "merged companions need no GPU on consumer")
	var packer := GemPagePacker.new(destination, root + "/library")
	var packed := packer.pack(clips)
	check(not packed.is_empty() and packed.frames.size() == bundle.jobs.size() and not packed.has("geometry"), "game library includes display frames and excludes geometry companions")
	var report := {"checks": checks, "failures": failures, "geometry_recipes": bundle.geometry.size(),
		"geometry_consumer": consumer.counters, "merge": merged, "library": packed.get("statistics", {})}
	GemArtifactStore.atomic_write(root + "/report.json", JSON.stringify(report, "\t").to_utf8_buffer())
	print("Geometry factory GPU: ", JSON.stringify(report))
	print("CHECK_COMPLETE: geometry_factory_check"); quit(1 if failures else 0)
