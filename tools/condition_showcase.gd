extends SceneTree
## Object-space defect sweeps. No automatic grade recipe is enabled by this tool.
func _initialize() -> void:
	var out := "res://artifacts/conditions/"
	DirAccess.make_dir_recursive_absolute(out)
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate(true)
	stone.grade.cut = 1.0
	stone.grade.crystal = 1.0
	var clean := LapidaryStoneCompiler.compile(stone)
	var chip := GemDefectCompiler.edge_chip(clean, stone.size_mm, 51, 0.5, 0.20)
	var fracture := GemDefect.new()
	fracture.center_mm = Vector3(0.65, 0.0, -0.1)
	fracture.half_extent_mm = Vector3(1.2, 0.7, 0.008)
	fracture.orientation = Quaternion(Vector3.UP, 0.6) * Quaternion(Vector3.BACK, 0.25)
	fracture.seed = 28
	var water := GemMaterial.new()
	water.species = GemSpecies.new()
	water.species.sellmeier_b = Vector3(0.7689, 0, 0)
	water.source_note = "Constant n=1.33 test filling, not a measured water spectrum."
	for kind in ["clean", "chip", "fracture", "filled"]:
		stone.condition.defects.clear()
		if kind == "chip":
			stone.condition.defects.append(chip)
		elif kind in ["fracture", "filled"]:
			fracture.filling = water if kind == "filled" else null
			stone.condition.defects.append(fracture)
		var inst := LapidaryStoneCompiler.compile(stone)
		tracer.configure_stone(inst, GemRigCompiler.pack(rig), GemRung.policy(GemRung.HERO))
		tracer.set_environment(GemRigCompiler.environment(rig))
		for angle in [0.0, 0.35]:
			tracer.set_stone_orientation(Quaternion(Vector3.RIGHT, angle))
			tracer.reset_accumulation()
			var begin := Time.get_ticks_usec()
			for batch in 4:
				tracer.accumulate(16)
			tracer.finalize_print(GemPrint.load_house()).save_png(out + "%s_%.2f.png" % [kind, angle])
			print("%s %.2f 64spp %.1fms" % [kind, angle, (Time.get_ticks_usec() - begin) / 1000.0])
	tracer.release()
	quit()
