extends SceneTree
## Dense procedural mesh setup benchmark; --label=NAME selects ignored output.
## Compare saved linear films with compare_scene_setup.py, not file hashes alone.

func _initialize() -> void:
	var label := "current"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="): label = argument.trim_prefix("--label=")
	if not label.is_valid_filename(): printerr("Invalid benchmark label"); quit(1); return
	var destination := "res://artifacts/scene-cache/" + label + "/"
	DirAccess.make_dir_recursive_absolute(destination)
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.size_mm = 4
	stone.material.scatter_per_mm = 0
	stone.condition.rounding = GemRounding.new()
	stone.condition.rounding.radius_mm = .12
	var start := Time.get_ticks_usec()
	var instance := LapidaryStoneCompiler.compile(stone)
	if instance.has("rounded_solid"):
		var reference:Dictionary=instance.rounded_solid.reference_mesh(6)
		if not reference.error.is_empty():printerr(reference.error);quit(1);return
		instance["mesh"]=reference.mesh;instance.erase("rounded_solid")
	var compilation_ms := (Time.get_ticks_usec() - start) / 1000.0
	if instance.has("compilation_error"): printerr(instance.compilation_error); quit(1); return
	var tracer := GemTracer.create(64, 64)
	if tracer == null: quit(1); return
	var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["denoise_passes"] = 0
	var reports := []
	for iteration in 4:
		start = Time.get_ticks_usec()
		if not tracer.configure_stone(instance, lighting, policy): printerr(tracer.configuration_error); tracer.release(); quit(1); return
		var configure_ms := (Time.get_ticks_usec() - start) / 1000.0
		tracer.set_clip_sample(Quaternion(Vector3.UP, .1 + .2 * iteration), 0, Vector4.ONE, 1.25)
		tracer.accumulate(16)
		if not tracer.transport_error().is_empty(): printerr(tracer.transport_error()); tracer.release(); quit(1); return
		var bytes := tracer.read_xyz().to_byte_array()
		GemArtifactStore.atomic_write(destination + "frame%d.bin" % iteration, bytes)
		reports.append({"iteration": iteration, "configure_ms": configure_ms, "profile": tracer.profile(), "film_sha256": FileAccess.get_sha256(destination + "frame%d.bin" % iteration)})
		print(JSON.stringify(reports[-1]))
	GemArtifactStore.atomic_write(destination + "report.json", JSON.stringify({"compilation_ms": compilation_ms, "triangles": instance.mesh.triangle_count(), "frames": reports}, "\t").to_utf8_buffer())
	tracer.release()
	quit()
