extends SceneTree
## A/B the committed baseline with the working shader, excluding compilation.
## Save baseline-math.glsl and baseline-path.glsl under artifacts/crystal-performance
## from the revision being compared before running this optional GPU tool.
const ROOT := "res://artifacts/crystal-performance/"
var failures := 0

func _initialize() -> void:
	for file in ["baseline-math.glsl", "baseline-path.glsl"]:
		if not FileAccess.file_exists(ROOT + file):
			printerr("Missing baseline source: " + ROOT + file)
			quit(1)
			return
	var report := []
	for id in ["quartz", "ruby"]:
		var stone: GemStone = load("res://data/lapidary/stones/" + id + ".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		stone.material.scatter_per_mm = 0
		stone.condition = GemCondition.new()
		var instance := LapidaryStoneCompiler.compile(stone)
		var lighting := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
		var policy := GemRung.policy(GemRung.REFERENCE)
		policy.crystal_transport = true
		policy.volume = false
		policy.max_bounces = 256
		var reference := PackedFloat32Array()
		for label in ["baseline", "working"]:
			var math_path := ROOT + "baseline-math.glsl" if label == "baseline" else GemTracer.SHADER_DIR + "gem_crystal.glsl"
			var path_path := ROOT + "baseline-path.glsl" if label == "baseline" else GemTracer.SHADER_DIR + "gem_crystal_path.glsl"
			var source := FileAccess.get_file_as_string(GemTracer.SHADER_PATH)
			source = source.replace("#version 450", "#version 450\n#define CRYSTAL_TRANSPORT 1\n" + GemCrystalShader.at_precision(FileAccess.get_file_as_string(math_path)))
			source = source.replace('#include "gem_crystal_path.glsl"', GemCrystalShader.geometry() + FileAccess.get_file_as_string(path_path))
			var shader_path: String = ROOT + "assembled-" + label + ".glsl"
			GemArtifactStore.atomic_write(shader_path, source.to_utf8_buffer())
			var tracer := GemTracer.create(128, 128)
			if tracer == null:
				printerr("GPU unavailable")
				quit(1)
				return
			if not tracer._compile_shader(shader_path, "benchmark"):
				tracer.release()
				quit(1)
				return
			# Transfer ownership under the expected name; never alias/free a RID twice.
			tracer._shaders["trace_crystal"] = tracer._shaders["benchmark"]
			tracer._shaders.erase("benchmark")
			tracer._pipelines["trace_crystal"] = tracer._pipelines["benchmark"]
			tracer._pipelines.erase("benchmark")
			if not tracer.configure_stone(instance, lighting, policy):
				printerr(tracer.configuration_error)
				tracer.release()
				quit(1)
				return
			tracer.set_stone_orientation(Quaternion(Vector3.UP, 0.3) * Quaternion(Vector3.RIGHT, -0.2))
			tracer.accumulate(2) # Warm shader and dispatch sizing outside timing.
			var milliseconds := []
			var maximum := 0.0
			for repetition in 3:
				tracer.reset_accumulation()
				milliseconds.append(tracer.accumulate(16))
				var pixels := tracer.read_linear_master().get_data().to_float32_array()
				if reference.is_empty():
					reference = pixels
				for index in pixels.size():
					if not is_finite(pixels[index]):
						failures += 1
					maximum = maxf(maximum, absf(pixels[index] - reference[index]))
				if not tracer.transport_error().is_empty():
					failures += 1
				print({"stone": id, "variant": label, "repeat": repetition, "ms": milliseconds[-1]})
			milliseconds.sort()
			var record := {"stone": id, "variant": label, "resolution": 128, "samples": 16,
				"adapter": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info(),
				"math_sha256": FileAccess.get_sha256(math_path), "transport_sha256": FileAccess.get_sha256(path_path),
				"trace_ms_sorted": milliseconds, "median_trace_ms": milliseconds[1], "maximum_XYZ_difference": maximum, "diagnostics": tracer.crystal_diagnostics()}
			report.append(record)
			print(JSON.stringify(record))
			if maximum > 0.0001:
				failures += 1
			tracer.release()
	GemArtifactStore.atomic_write(ROOT + "report.json", JSON.stringify(report, "\t").to_utf8_buffer())
	quit(1 if failures else 0)
