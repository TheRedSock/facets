extends SceneTree
## Windowed GPU search; writes candidate resources and evidence under artifacts/.
## --stone=quartz --quick selects a small preview. Catalog data is never edited.
var output := "res://artifacts/cut-search"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var id := "quartz"
	var quick := "--quick" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--stone="):
			id = argument.trim_prefix("--stone=")
	if not id.is_valid_filename():
		printerr("Invalid specimen name")
		quit(1)
		return
	var source := load("res://data/lapidary/stones/%s.tres" % id) as GemStone
	if source == null or source.shape.mode != "faceted":
		printerr("Search requires an authored faceted specimen")
		quit(1)
		return
	output = output.path_join(id)
	DirAccess.make_dir_recursive_absolute(output)
	var resolution := 48 if quick else 96
	var samples := 8 if quick else 32
	var tracer := GemTracer.create(resolution, resolution)
	if tracer == null:
		quit(1)
		return
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy.denoise_passes = 0
	var training: Array[Dictionary] = []
	var heldout: Array[Dictionary] = []
	for index in 4:
		training.append(_scenario(index, false))
		heldout.append(_scenario(index, true))
	var baseline := GemCutSearch.evaluate(tracer, source, training, policy, samples)
	var baseline_test := GemCutSearch.evaluate(tracer, source, heldout, policy, samples)
	var records: Array[Dictionary] = []
	var started := Time.get_ticks_msec()
	var angles := [34.0, 38.0, 42.0, 46.0, 50.0]
	for angle in angles:
		for table in [0.48, 0.56, 0.64]:
			for scale in [0.85, 1.0, 1.15]:
				var stone := GemCutSearch.candidate(source, angle, table, scale)
				var job := GemFrameJob.new()
				job.stone = stone
				job.rig = training[0]["rig"]
				job.print_style = GemPrint.load_house()
				job.quality = policy
				var error := GemJobValidator.validate(job)
				if not error.is_empty():
					printerr("Candidate rejected: " + error)
					continue
				var result := GemCutSearch.evaluate(tracer, stone, training, policy, samples)
				result["pavilion_deg"] = angle
				result["table_ratio"] = table
				result["crown_scale"] = scale
				records.append(result)
		print("Cut search %s: %d/45 candidates, %.1f seconds" % [id, records.size(), (Time.get_ticks_msec() - started) / 1000.0])
		await process_frame
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] > b["score"])
	if records.is_empty():
		tracer.release()
		quit(1)
		return
	for rank in mini(3, records.size()):
		var record := records[rank]
		var stone := GemCutSearch.candidate(source, record.pavilion_deg, record.table_ratio, record.crown_scale)
		record["heldout"] = GemCutSearch.evaluate(tracer, stone, heldout, policy, samples)
		GemResourceBundle.save(stone, output.path_join("candidate-%d.res" % rank))
	var winner := records[0]
	var report := {"source": source.fingerprint(), "engine": GemRenderIdentity.worker_digest(),
		"specimen": id, "resolution": resolution, "samples": samples, "policy": policy,
		"objective": "0.75 mean face-up linear Y + 0.25 worst-view Y; not a cut grade",
		"limits": "Bounded grid search, approximate anisotropic transport, no automatic catalog promotion; inspect held-out views and visual output.",
		"training_scenarios": training.map(func(s: Dictionary) -> Dictionary: return s["description"]),
		"heldout_scenarios": heldout.map(func(s: Dictionary) -> Dictionary: return s["description"]),
		"baseline_training": baseline, "baseline_heldout": baseline_test, "candidates": records,
		"elapsed_ms": Time.get_ticks_msec() - started}
	GemArtifactStore.atomic_write(output.path_join("report.json"), JSON.stringify(report, "\t").to_utf8_buffer())
	print("Training baseline %.6f -> %.6f; held-out %.6f -> %.6f" % [baseline.score, winner.score, baseline_test.score, winner.heldout.score])
	tracer.release()
	# Render comparison at a useful review size with the actual production print.
	tracer = GemTracer.create(256, 256)
	policy.denoise_passes = 3
	var selected := GemCutSearch.candidate(source, winner.pavilion_deg, winner.table_ratio, winner.crown_scale)
	for variant in [{"name": "baseline", "stone": source}, {"name": "candidate", "stone": selected}]:
		for index in 2:
			var scenario := heldout[index]
			tracer.configure_stone(LapidaryStoneCompiler.compile(variant.stone), scenario.lighting, policy)
			tracer.set_clip_sample(scenario.orientation, 0.0, Vector4.ONE, 1.4)
			tracer.accumulate(128)
			tracer.finalize_print(GemPrint.load_house(), false, 1.0, Vector2i(256, 256)).save_png(output.path_join("%s-%d.png" % [variant.name, index]))
	tracer.release()
	quit(0)

func _scenario(index: int, heldout: bool) -> Dictionary:
	var rig := GemLightRig.new()
	rig.background_spectrum.model = GemSpectrum.Model.CIE_D65
	rig.white_spectrum = rig.background_spectrum
	rig.bg_zenith = 0.25
	rig.bg_horizon = 0.08
	rig.bg_below = 0.005
	var azimuth := 37.0 * index + (23.0 if heldout else 0.0)
	var elevation := 25.0 + 13.0 * index + (5.0 if heldout else 0.0)
	var radius := 11.0 + 4.0 * index + (2.0 if heldout else 0.0)
	for role in 2:
		var light := GemRigLight.new()
		light.role = role
		light.azimuth_deg = azimuth + 100.0 * role
		light.elevation_deg = elevation - 20.0 * role
		light.angular_radius_deg = radius + 15.0 * role
		light.power = 3.0 if role == 0 else 0.75
		light.spectrum = rig.background_spectrum
		rig.lights.append(light)
	var tilt_x := -12.0 + 8.0 * index + (3.0 if heldout else 0.0)
	var tilt_y := 7.0 if index % 2 == 0 else -7.0
	if heldout:
		tilt_y *= 1.7
	return {"rig": rig, "lighting": GemRigCompiler.compile(rig),
		"orientation": Quaternion(Vector3.UP, deg_to_rad(tilt_y)) * Quaternion(Vector3.RIGHT, deg_to_rad(tilt_x)),
		"description": {"key_azimuth_deg": azimuth, "key_elevation_deg": elevation, "key_radius_deg": radius,
			"tilt_x_deg": tilt_x, "tilt_y_deg": tilt_y, "illumination": "D65; key3/fill0.75; background0.25/0.08/0.005"}}
