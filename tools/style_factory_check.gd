extends SceneTree
## Real GPU print, then a standalone headless worker styles the cached print.
var failures := 0
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var output := "res://artifacts/style-factory/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var job := GemFramePlan.animation(load("res://data/lapidary/stones/ruby.tres"), load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/rigs/gameplay_studio.tres"), GemPrint.load_house(), GemRung.INTERACT)[0]
	job.resolution = Vector2i(64, 64); job.output_size = Vector2i(32, 32); job.samples = 16
	var jobs: Array[GemFrameJob] = [job]
	for bands in [0, 6]:
		var styled: GemFrameJob = job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		styled.game_style = load("res://data/lapidary/styles/illustrative_sprite.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		styled.game_style.luminance_bands = bands
		jobs.append(styled)
	var bundle := ProjectSettings.globalize_path(output + "/worker")
	var manifest := GemJobBundle.write(bundle, jobs, {})
	check(not manifest.is_empty() and manifest.estimate.unique_masters == 1 and manifest.estimate.unique_displays == 3, "portable jobs share optics")
	var worker := GemFrameWorker.new(output + "/store")
	check(worker.run(job).get("status") == "complete" and worker.counters.rendered == 1, "GPU produces physical baseline")
	worker.release()
	var master_before: PackedByteArray = worker.store.read(GemFramePlan.master_key(job)).payload
	run_process(bundle, ["--headless", "--editor", "--quit"], output + "/import.log")
	run_process(bundle, ["--headless", "--script", "res://tools/gem_frame_worker.gd", "--", "--output=" + ProjectSettings.globalize_path(worker.store.root)], output + "/headless-style.log")
	check(FileAccess.get_file_as_string(output + "/headless-style.log").contains('"restyled":2'), "headless worker realizes both art variants")
	check(worker.store.read(GemFramePlan.master_key(job)).payload == master_before, "styling preserves master bytes")
	var base := decode(worker.store.read(GemFramePlan.print_key(job)).payload)
	for styled in jobs:
		var record := worker.store.read(GemFramePlan.display_key(styled))
		check(not record.is_empty(), "requested display exists")
		if record.is_empty(): continue
		var actual := decode(record.payload)
		var expected := GemStylePipeline.apply(base, styled.game_style)
		check(actual.get_data() == expected.get_data(), "portable style matches local processing byte for byte")
	var retained := GemStoreMaintenance.new().collect(worker.store.root, [manifest], 0, true)
	check(not retained.is_empty(), "explicit baseline request retains headless styling source")
	var destination := GemArtifactStore.new(output + "/transfer")
	check(destination.initialize(), "initialize destination")
	var transfer := GemStoreTransfer.new().merge(destination.root, PackedStringArray([worker.store.root]), manifest, true)
	check(not transfer.is_empty() and transfer.missing.is_empty() and transfer.recipes_to_import == 4, "farm transfer carries one master and three requested displays")
	print("Style factory: %d checks, %d failures; %s" % [checks, failures, output])
	quit(1 if failures else 0)

func decode(payload: PackedByteArray) -> Image:
	var image := Image.new()
	check(image.load_webp_from_buffer(payload) == OK, "decode WebP")
	image.convert(Image.FORMAT_RGBA8)
	return image

func run_process(directory: String, arguments: Array, log_path: String) -> void:
	var output := []
	var args := PackedStringArray(["--audio-driver", "Dummy", "--path", directory, "--quit-after", "600"])
	args.append_array(PackedStringArray(arguments))
	var code := OS.execute(OS.get_executable_path(), args, output, true, false)
	var log_text := "\n".join(output)
	GemArtifactStore.atomic_write(log_path, log_text.to_utf8_buffer())
	check(code == 0 and not log_text.contains("SCRIPT ERROR:") and not log_text.contains("ERROR:"), "subprocess " + log_path.get_file())
	if code != 0 or log_text.contains("SCRIPT ERROR:") or log_text.contains("ERROR:"): printerr(log_text)
