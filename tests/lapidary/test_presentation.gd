extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)
func _initialize() -> void:
	var settings := GemPresentation.new()
	var rest := Quaternion(Vector3.RIGHT, deg_to_rad(-12))
	for file in DirAccess.get_files_at("res://data/lapidary/stones"):
		if not file.ends_with(".tres"): continue
		var stone: GemStone = load("res://data/lapidary/stones/" + file)
		var physical := GemContentIdentity.digest(stone.transport_inputs())
		var prepared := GemPresentationCompiler.prepare(stone, settings, rest)
		check(prepared.error.is_empty(), file + " framing admission")
		if not prepared.error.is_empty(): continue
		var pose := GemPresentationCompiler.sample(prepared, rest, Vector2i(256, 256), 1.25)
		var center: Vector3 = (prepared.bounds.lower + prepared.bounds.upper) * 0.5
		var pixels := Vector2((center.x - pose.camera_offset.x) / 2.5 * 256 + 128, -(center.y - pose.camera_offset.y) / 2.5 * 256 + 128)
		check(pixels.distance_to(Vector2(127.5, 127.5)) < 0.001, file + " projected bounds centered on pixel grid")
		if stone.shape.outline == &"pear": check((pose.orientation * Vector3.RIGHT).y < -0.97, file + " apex points down")
		var initial_anchor: Vector3 = pose.orientation * prepared.pivot
		var initial_projection: Vector2 = Vector2(initial_anchor.x, initial_anchor.y) - pose.camera_offset
		for angle in [0.3, 1.7, PI]:
			var moved := GemPresentationCompiler.sample(prepared, rest * Quaternion(Vector3.UP, angle), Vector2i(256, 256), 1.25)
			var anchor: Vector3 = moved.orientation * prepared.pivot
			check((Vector2(anchor.x, anchor.y) - moved.camera_offset).distance_to(initial_projection) < 0.00001, file + " chosen pivot stays fixed")
		check(GemContentIdentity.digest(stone.transport_inputs()) == physical, file + " geometry/lattice unchanged")
	var stone: GemStone = load("res://data/lapidary/stones/diamond.tres")
	settings.pivot_mode = GemPresentation.PivotMode.ORIGIN
	var fixed := GemPresentationCompiler.prepare(stone, settings, rest)
	var first := GemPresentationCompiler.sample(fixed, rest, Vector2i(256, 256), 1.25)
	var later := GemPresentationCompiler.sample(fixed, rest * Quaternion(Vector3.UP, 1), Vector2i(256, 256), 1.25)
	check(first.camera_offset == later.camera_offset, "native pivot keeps camera fixed instead of recentering every frame")
	var request := GemAssetRequest.new(); request.asset_id = &"diamond"; request.stone = stone
	request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres"); request.print_style = GemPrint.load_house()
	request.clips.append(load("res://data/lapidary/clips/idle.tres"))
	var batch := GemAssetBatch.new(); batch.requests.append(request)
	var planned := GemAssetPlanner.plan(batch)
	check(planned.error.is_empty(), "default asset request uses presentation")
	if planned.error.is_empty():
		var job: GemFrameJob = planned.jobs[0]
		var optical := GemFramePlan.master_key(job); var geometry := GemGeometryPlan.key(job, 4)
		job.camera_offset.x += 0.01
		check(GemFramePlan.master_key(job) != optical and GemGeometryPlan.key(job, 4) != geometry, "camera offsets invalidate optics and geometry")
		job.camera_offset.x = NAN
		check(not GemJobValidator.validate(job).is_empty(), "invalid camera offsets rejected")
	request.stone = stone.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	request.stone.shape = null
	check(not GemAssetPlanner.plan(batch).error.is_empty(), "missing shape rejected before presentation compilation")
	check(not GemPresentationCompiler.prepare(null, settings, rest).error.is_empty(), "missing presentation stone rejected")
	settings.center_mode = GemPresentation.CenterMode.CUSTOM; settings.custom_center = Vector2(0.2, -0.1)
	settings.pivot_mode = GemPresentation.PivotMode.CUSTOM; settings.custom_pivot = Vector3(0.1, -0.2, 0.3)
	var custom := GemPresentationCompiler.prepare(stone, settings, rest)
	check(custom.center == settings.custom_center and custom.pivot == settings.custom_pivot, "independent custom center and native pivot")
	settings.pivot_mode = GemPresentation.PivotMode.BODY_BOUNDS
	var body := GemPresentationCompiler.prepare(stone, settings, rest)
	check(body.pivot == body.bounds.body_center, "body bounds selects native solid center")
	var native := GemPresentationCompiler.sample(GemPresentationCompiler.prepare(stone, null, rest), rest, Vector2i(256, 256), 1.25)
	check(native.camera_offset == Vector2.ZERO and native.orientation == GemFramePlan.canonical_orientation(rest), "null presentation retains native pose")
	settings.orientation_deg.x = 1e30
	check(not settings.validate().is_empty(), "unbounded presentation angles rejected")
	settings.orientation_deg = Vector3.ZERO
	settings.custom_pivot.x = NAN
	check(not settings.validate().is_empty(), "invalid presentation rejected")
	print("Presentation: %d checks, %d failures" % [checks, failures]); print("CHECK_COMPLETE: test_presentation"); quit(1 if failures else 0)

