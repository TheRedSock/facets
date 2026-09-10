extends SceneTree
## Real source mutations in an isolated worker project, never in live sources.
var output_root: String
var bundle: String
var failures := 0

func _initialize() -> void:
	output_root = "res://artifacts/pipeline-cache/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	bundle = ProjectSettings.globalize_path(output_root + "/worker")
	var job := GemFramePlan.animation(load("res://data/lapidary/stones/quartz.tres"), load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.INTERACT)[0]
	job.resolution = Vector2i(32, 32)
	job.output_size = job.resolution
	job.samples = 4
	var jobs: Array[GemFrameJob] = [job]
	if GemJobBundle.write(bundle, jobs, {}, 1).is_empty():
		quit(1)
		return
	var worker := GemFrameWorker.new(output_root + "/store")
	if worker.run(job).is_empty():
		failures += 1
	worker.release()
	var geometry := GemGeometryWorker.new(output_root + "/store")
	if geometry.run(job, 1).is_empty():
		failures += 1
	geometry.release()
	GemArtifactStore.atomic_write(bundle.path_join("probe.gd"), FileAccess.get_file_as_bytes("res://tools/pipeline_cache_probe.gd"))
	_run("import", PackedStringArray(["--headless", "--editor", "--quit"]))
	_edit("gem_crystal.glsl")
	_run("stale-bundle", PackedStringArray(["--headless", "--script", "res://tools/gem_frame_worker.gd"]), true)
	_probe("crystal", true)
	_edit("gem_print.glsl")
	_probe("print", false)
	_edit("gem_mesh.glsl")
	_probe("shared", true)
	print("Pipeline cache GPU: %d failures; evidence %s" % [failures, output_root])
	quit(1 if failures else 0)

func _edit(file: String) -> void:
	var path := bundle.path_join("core/lapidary/tracer/shaders/" + file)
	var source := FileAccess.get_file_as_string(path)
	if file == "gem_print.glsl":
		if not source.contains("vec4(enc, cov)"):
			failures += 1
			return
		source = source.replace("vec4(enc, cov)", "vec4(enc * 0.5, cov)")
	if not GemArtifactStore.atomic_write(path, (source + "\n// Isolated source revision probe.\n").to_utf8_buffer()):
		failures += 1

func _probe(phase: String, headless: bool) -> void:
	var arguments := PackedStringArray(["--script", "res://probe.gd", "--", "--phase=" + phase, "--store=" + ProjectSettings.globalize_path(output_root + "/store")])
	if headless:
		arguments.insert(0, "--headless")
	_run(phase, arguments)

func _run(label: String, arguments: PackedStringArray, expect_stale := false) -> void:
	var output := []
	var all_args := PackedStringArray(["--audio-driver", "Dummy", "--path", bundle, "--quit-after", "600"])
	all_args.append_array(arguments)
	var code := OS.execute(OS.get_executable_path(), all_args, output, true, false)
	var log_text := "\n".join(output)
	GemArtifactStore.atomic_write(output_root.path_join(label + ".log"), log_text.to_utf8_buffer())
	if expect_stale:
		if code != 1 or not log_text.contains("Worker source mismatch"):
			failures += 1
			printerr(log_text)
	elif code != 0 or log_text.contains("SCRIPT ERROR:") or log_text.contains("ERROR:"):
		failures += 1
		printerr(log_text)
	else:
		print("Pipeline subprocess ", label, " passed")
