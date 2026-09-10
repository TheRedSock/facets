extends SceneTree
## Reproducible procedural-shape look check. Outputs are intentionally ignored.
func _initialize() -> void:
	var out := "res://artifacts/geometry/"
	DirAccess.make_dir_recursive_absolute(out)
	var tracer := GemTracer.create(256, 256)
	if tracer == null:
		quit(1)
		return
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var stone: GemStone = load("res://data/lapidary/stones/sapphire.tres").duplicate(true)
	stone.grade.cut = 1.0
	stone.grade.crystal = 1.0
	var samples := 64
	for kind in ["cabochon", "concave", "faceted"]:
		stone.shape = GemShape.cabochon_outline(&"oval")
		if kind == "concave":
			stone.shape.mode = "loft"
			stone.shape.outline_points = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(0.4, 1), Vector2(0.4, -0.2), Vector2(-0.4, -0.2), Vector2(-0.4, 1), Vector2(-1, 1)])
			stone.shape.loft_sections = PackedVector2Array([Vector2(-0.2, 0.8), Vector2(0, 1), Vector2(0.25, 0.85)])
		elif kind == "faceted":
			stone.shape = GemShape.faceted_outline(&"oval")
		var inst := LapidaryStoneCompiler.compile(stone)
		var begin := Time.get_ticks_usec()
		tracer.configure_stone(inst, GemRigCompiler.pack(rig), GemRung.policy(GemRung.HERO))
		var compile_ms := (Time.get_ticks_usec() - begin) / 1000.0
		tracer.set_environment(GemRigCompiler.environment(rig))
		tracer.set_stone_orientation(Quaternion(Vector3.RIGHT, 0.35) * Quaternion(Vector3.UP, 0.2))
		for batch in samples / 16:
			tracer.accumulate(16)
		tracer.finalize_print(GemPrint.load_house()).save_png(out + kind + ".png")
		print("%s setup %.1fms, %d triangles, profile %s" % [kind, compile_ms, (inst["mesh"] as GemMesh).triangle_count() if inst.has("mesh") else 0, tracer.profile()])
	tracer.release()
	quit()
