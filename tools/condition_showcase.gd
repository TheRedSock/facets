extends SceneTree
## Object-space defect sweeps. No automatic grade recipe is enabled by this tool.
func _initialize() -> void:
	var samples := 256 if "--high" in OS.get_cmdline_user_args() else 64
	var out := "res://artifacts/conditions/aperture/%dspp/" % samples
	DirAccess.make_dir_recursive_absolute(out)
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm = stone.material.species.base_scatter_per_mm
	stone.condition.banding.contrast = 0.0
	var clean := LapidaryStoneCompiler.compile(stone)
	var chip := GemDefectCompiler.edge_chip(clean, stone.size_mm, 51, 0.5, 0.20)
	var fracture := GemDefect.new()
	fracture.center_mm = Vector3(0.65, 0.0, -0.1)
	fracture.half_extent_mm = Vector3(1.2, 0.7, 0.008)
	fracture.orientation = Quaternion(Vector3.UP, 0.6) * Quaternion(Vector3.BACK, 0.25)
	fracture.seed = 28
	fracture.fracture_profile.aperture_variation = 1.0
	fracture.fracture_profile.correlation_mm = 0.2
	fracture.fracture_profile.roughness_mm = 0.002
	var water := GemMaterial.new()
	water.species = GemSpecies.new()
	water.species.ordinary.b = PackedFloat64Array([0.7689, 0, 0])
	water.source_note = "Constant n=1.33 test filling, not a measured water spectrum."
	var kinds := ["fracture", "contact"] if "--fracture-only" in OS.get_cmdline_user_args() else ["clean", "chip", "fracture", "contact", "filled"]
	var measurements := []
	for kind in kinds:
		stone.condition.defects.clear()
		if kind == "chip":
			stone.condition.defects.append(chip)
		elif kind in ["fracture", "contact", "filled"]:
			fracture.filling = water if kind == "filled" else null
			fracture.fracture_profile.closure_mm = 0.008 if kind in ["contact", "filled"] else 0.0
			stone.condition.defects.append(fracture)
		var inst := LapidaryStoneCompiler.compile(stone)
		tracer.configure_stone(inst, GemRigCompiler.compile(rig), GemRung.policy(GemRung.HERO))
		for angle in [0.0, 0.35]:
			tracer.set_stone_orientation(Quaternion(Vector3.RIGHT, angle))
			tracer.reset_accumulation()
			var begin := Time.get_ticks_usec()
			for batch in samples / 16:
				tracer.accumulate(16)
			tracer.finalize_print(GemPrint.load_house()).save_png(out + "%s_%.2f.png" % [kind, angle])
			var elapsed := (Time.get_ticks_usec() - begin) / 1000.0
			measurements.append({"condition": kind, "angle": angle, "samples": samples, "elapsed_ms": elapsed})
			print("%s %.2f %dspp %.1fms" % [kind, angle, samples, elapsed])
	GemArtifactStore.atomic_write(out + "timings.json", JSON.stringify(measurements, "\t").to_utf8_buffer())
	tracer.release()
	quit()
