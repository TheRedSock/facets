extends SceneTree
var failures := 0
var checks := 0

class QuietWorker extends GemFrameWorker:
	func _fail(message: String) -> Dictionary:
		last_error = message
		return {}

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func reject(job: GemFrameJob, reason: String) -> void:
	var worker := QuietWorker.new("res://artifacts/job-validation/store")
	check(worker.run(job).is_empty() and worker.tracer == null and worker.last_error.contains(reason), "CPU rejection: " + reason + " (" + worker.last_error + ")")

func _initialize() -> void:
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var clip: GemClip = load("res://data/lapidary/clips/idle.tres")
	var base: GemFrameJob
	for file in DirAccess.get_files_at("res://data/lapidary/stones"):
		if file.get_extension() != "tres":
			continue
		var stone: GemStone = load("res://data/lapidary/stones/" + file)
		var job := GemFramePlan.animation(stone, clip, rig, GemPrint.load_house(), GemRung.CLIP_BAKE)[0]
		var error := GemJobValidator.validate(job)
		check(error.is_empty(), "catalog admission " + file + ": " + error)
		if file == "quartz.tres":
			base = job
	check(base != null, "quartz fixture loaded")
	if base == null:
		quit(1)
		return
	reject(null, "missing")
	var job: GemFrameJob = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.material = null
	reject(job, "missing material")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.size_mm = NAN
	reject(job, "physical size")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.orientation = Quaternion(0, 0, 0, 0)
	reject(job, "unit quaternion")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.ortho_half = -1
	reject(job, "framing")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.role_multipliers.z = INF
	reject(job, "multipliers")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.resolution = Vector2i(8192, 8192)
	reject(job, "payload limit")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.quality.device_memory_budget_mib = 1
	reject(job, "memory budget")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.quality.max_bounces = "128"
	reject(job, "integer quality")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.quality.polarisation = true
	reject(job, "Unknown quality")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.quality.polarization = true
	reject(job, "isotropic")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.cut.crown_rows[0].angle_deg = NAN
	reject(job, "row angle")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.cut = null
	reject(job, "explicit GemCutTemplate")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.grade.cut = INF
	reject(job, "grade.cut")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.shape.mode = "loft"
	job.stone.shape.outline_points = PackedVector2Array([Vector2(0, 0), Vector2(1, 1), Vector2(0, 1), Vector2(1, 0)])
	reject(job, "topology")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone.condition.defects.append(null)
	reject(job, "missing defect")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var defect := GemDefect.new()
	defect.half_extent_mm.z = -1
	job.stone.condition.defects.append(defect)
	reject(job, "half-extents")
	defect.enabled = false
	check(GemJobValidator.validate(job).is_empty(), "disabled exploratory defect is not rendered or rejected")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.rig.lights.append(null)
	reject(job, "missing light")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.rig.lights[0].power = -1
	reject(job, "light cone or power")
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.print_style.contrast = NAN
	reject(job, "Print contrast")
	var black := GemSpectrum.new()
	black.model = GemSpectrum.Model.SAMPLED
	black.wavelength_step_nm = 400
	black.samples = PackedFloat32Array([0, 0])
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.rig.background_spectrum = black
	reject(job, "no energy")
	black.normalization = GemSpectrum.Normalization.NONE
	check(GemJobValidator.validate(job).is_empty(), "zero unnormalized background is valid dark space")
	job.rig.white_spectrum = black
	reject(job, "visible energy")
	# Check nested capability admission, even when the host itself is supported.
	job = base.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.stone = load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	job.quality.polarization = true
	check(GemJobValidator.validate(job).is_empty(), "isotropic polarized diamond accepted")
	defect = GemDefect.new()
	defect.filling = base.stone.material
	job.stone.condition.defects.append(defect)
	reject(job, "defect filling: polarization")
	print("Job validation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
