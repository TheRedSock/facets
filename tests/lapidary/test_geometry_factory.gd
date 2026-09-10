extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var jobs := GemFramePlan.animation(stone, load("res://data/lapidary/clips/flash.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.PREVIEW)
	var job: GemFrameJob = jobs[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var key := GemGeometryPlan.key(job, 4)
	job.samples = 32
	job.sample_seed = 753
	job.exposure = 2
	job.rig_yaw = 0.7
	job.role_multipliers = Vector4(1, 2, 3, 4)
	job.output_size = Vector2i(16, 16)
	job.stone.material.scatter_per_mm = 2
	job.stone.condition.banding.contrast = 0.8
	job.stone.grade.clarity = 0.1
	job.stone.material.species.ordinary.b[0] += 0.1
	check(GemGeometryPlan.key(job, 4) == key, "lighting, optical coefficients, grade, estimator and print do not change geometry")
	check(GemGeometryPlan.key(job, 2) != key, "coverage grid participates in geometry identity")
	job.orientation = Quaternion(Vector3.UP, 0.1)
	check(GemGeometryPlan.key(job, 4) != key, "camera pose changes geometry")
	job = jobs[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.condition.workmanship.polar_error_deg = 0.1
	check(GemGeometryPlan.key(job, 4) != key, "workmanship affects geometry identity")
	var defect := GemDefect.new()
	job.stone.condition.defects.append(defect)
	var void_key := GemGeometryPlan.key(job, 4)
	defect.filling = job.stone.material
	check(GemGeometryPlan.key(job, 4) != void_key, "filled region presence changes semantic material identity")
	var filled_key := GemGeometryPlan.key(job, 4)
	defect.filling.scatter_per_mm = 1
	defect.finish.alpha_u = 0.002
	check(GemGeometryPlan.key(job, 4) == filled_key, "filling coefficients and boundary finish do not change primary geometry")
	check(not GemGeometryPlan.validate(job, 3).is_empty(), "unsupported coverage rejected")
	job.resolution = Vector2i(4096, 4096)
	job.quality.device_memory_budget_mib = 4096
	check(GemGeometryPlan.validate(job, 4).contains("payload"), "large geometry payload rejected before GPU allocation")
	job.resolution = Vector2i(128, 128)
	job.quality.device_memory_budget_mib = 2
	check(GemGeometryPlan.validate(job, 4).contains("Geometry plus film"), "geometry buffer included in memory admission")
	var root := "res://artifacts/geometry-factory/%d" % Time.get_ticks_usec()
	var bundle := GemJobBundle.write(root + "/bundle", jobs, {}, 4)
	check(not bundle.is_empty() and bundle.geometry.size() == 1, "exposure animation schedules only one geometry companion")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(bundle))
	check(GemGeometryPlan.references_error(wire).is_empty(), "JSON manifest round-trip: " + GemGeometryPlan.references_error(wire))
	for frame: Dictionary in bundle.jobs.values():
		check(bundle.geometry.has(frame.get("geometry")), "every display variant references its shared companion")
	var malformed := bundle.duplicate(true)
	malformed.geometry.clear()
	check(not GemGeometryPlan.references_error(malformed).is_empty(), "dangling companion references rejected")
	var entry: Dictionary = bundle.geometry.values()[0]
	var stale_source := root + "/bundle/core/lapidary/tracer/shaders/obsolete.glsl"
	var stale_job := root + "/bundle/jobs/" + "obsolete-job".sha256_text() + ".res"
	GemArtifactStore.atomic_write(stale_source, "obsolete generated source".to_utf8_buffer())
	GemArtifactStore.atomic_write(stale_job, "obsolete generated job".to_utf8_buffer())
	GemArtifactStore.atomic_write(root + "/bundle/notes.txt", "unrelated note".to_utf8_buffer())
	check(not GemJobBundle.write(root + "/bundle", jobs, {}, 4).is_empty(), "generated bundle can be refreshed")
	check(not FileAccess.file_exists(stale_source) and not FileAccess.file_exists(stale_job), "refresh removes obsolete generated sources and jobs")
	check(FileAccess.file_exists(root + "/bundle/notes.txt"), "refresh retains unrelated notes")
	GemArtifactStore.atomic_write(root + "/unowned/notes.txt", "not a bundle".to_utf8_buffer())
	check(not GemJobBundle._claim(ProjectSettings.globalize_path(root + "/unowned")), "cannot claim an unrelated nonempty directory")
	var restored: GemFrameJob = load(root + "/bundle/" + entry.path)
	check(GemGeometryPlan.key(restored, 4) == bundle.geometry.keys()[0], "portable binary input retains exact companion identity")
	var geometry := GemGeometryAov.new()
	geometry.width = 4
	geometry.height = 4
	geometry.coverage_side = 1
	geometry.data.resize(16 * GemGeometryAov.STRIDE)
	for pixel in 16:
		for field in 4:
			geometry.data.encode_s32(pixel * GemGeometryAov.STRIDE + 32 + field * 4, -1)
	var expected := {"width": 4, "height": 4, "coverage_side": 1}
	var engine := GemRenderIdentity.optical_digest()
	var metadata := expected.duplicate()
	metadata.merge({"kind": "primary_geometry", "engine": engine, "codec": "gao1", "status": "complete"})
	var source := GemArtifactStore.new(root + "/source")
	var destination := GemArtifactStore.new(root + "/destination")
	check(source.publish(key, geometry.encode(), metadata) and destination.initialize(), "publish lossless companion fixture")
	var manifest := {"schema": 1, "engine": engine, "jobs": {}, "geometry": {key: expected}}
	var maintenance := GemStoreMaintenance.new()
	check(maintenance.collect(source.root, [manifest], 0, true).get("kept_recipes") == 1, "requested geometry survives retention without optical jobs")
	var transfer := GemStoreTransfer.new()
	check(transfer.merge(destination.root, PackedStringArray([source.root]), manifest, true).get("recipes_to_import") == 1, "geometry-only farm results consolidate")
	check(GemGeometryPlan.payload_error(destination.read(key), expected, engine).is_empty(), "transferred geometry decodes with requested semantics")
	expected.coverage_side = 2
	check(transfer.merge(destination.root, PackedStringArray([source.root]), manifest).is_empty(), "transfer rejects payload coverage mismatch")
	expected.coverage_side = 1.5
	check(maintenance.collect(source.root, [manifest], 0).is_empty(), "malformed retention request cannot delete geometry")
	manifest.geometry = {}
	check(maintenance.collect(source.root, [manifest], 0, true).get("kept_recipes") == 0, "unrequested geometry is disposable")
	print("Geometry factory: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
