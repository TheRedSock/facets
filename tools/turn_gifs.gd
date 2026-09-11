extends SceneTree
## Inspection animations through production planner/worker, with no game style.
## godot --path . --script res://tools/turn_gifs.gd -- --res=256 --frames=120 --fps=30
## --rung=hero --spp=256 --stones=quartz,ruby --output=res://artifacts/lookdev/turn_gif
## --python=python --plan-only. Both --name=value and --name value are accepted.
## Cached frames can be exported again headlessly. Source PNGs are always retained.
const DEFAULT_OUTPUT := "res://artifacts/lookdev/turn_gif"
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"
const STONES_DIR := "res://data/lapidary/stones"
var _error := ""

func _initialize() -> void:
	var opts := _options(OS.get_cmdline_user_args())
	if not _error.is_empty(): _fail(_error); return
	var batch := _batch(opts)
	if batch == null: _fail(_error); return
	var planned := GemAssetPlanner.plan(batch)
	if not planned.error.is_empty(): _fail(planned.error); return
	var output: String = opts.output
	if DirAccess.make_dir_recursive_absolute(output) != OK: _fail("Cannot create output directory"); return
	if GemResourceBundle.save(batch, output.path_join("request.res")) != OK: _fail("Cannot save inspection request"); return
	var report := {"schema": 1, "status": "planned", "options": opts, "rig": RIG_PATH,
		"game_style": "none", "print": "house", "rest_tilt_deg": [-12, 0, 0], "axis": [0, 1, 0],
		"turn_degrees": 360, "duplicate_endpoint": false, "estimate": planned.estimate,
		"effective_policy": planned.jobs[0].quality, "effective_samples": planned.jobs[0].samples,
		"specimens": planned.specimens, "worker_engine": GemRenderIdentity.worker_digest(), "clips": planned.clips, "results": []}
	if not _report(output, report): _fail("Cannot save plan"); return
	print("TURN_GIFS PLAN ", JSON.stringify(planned.estimate))
	if opts.plan_only: quit(); return
	var check_output: Array = []
	if OS.execute(opts.python, [ProjectSettings.globalize_path("res://tools/turn_gifs_encode.py"), "--check"], check_output, true) != 0:
		_fail("Encoder unavailable: " + str(check_output)); return
	var worker := GemFrameWorker.new(output.path_join("store"))
	if not worker.store.initialize(): _fail("Cannot initialize inspection store"); return
	var start := Time.get_ticks_msec()
	var offset := 0
	for request in batch.requests:
		var id := String(request.asset_id)
		var directory := output.path_join(id)
		if DirAccess.make_dir_recursive_absolute(directory) != OK: worker.release(); _fail("Cannot create frames directory"); return
		var stone_report := {"stone": id, "frames": [], "status": "rendering"}
		report.results.append(stone_report)
		for frame in int(opts.frames):
			var job: GemFrameJob = planned.jobs[offset]
			offset += 1
			var frame_start := Time.get_ticks_msec()
			var result := worker.run(job)
			if result.is_empty() or result.get("status", "") != "complete":
				worker.release(); _fail("Frame %s/%d: %s %s" % [id, frame, worker.last_error, result]); return
			var key := GemFramePlan.display_key(job)
			var record := worker.store.read(key)
			var image := Image.new()
			if image.load_webp_from_buffer(record.get("payload", PackedByteArray())) != OK:
				worker.release(); _fail("Cannot decode completed frame"); return
			var path := directory.path_join("frame_%04d.png" % frame)
			if image.save_png(path) != OK: worker.release(); _fail("Cannot save PNG"); return
			stone_report.frames.append({"index": frame, "display": key, "master": result.master,
				"png_sha256": FileAccess.get_sha256(path), "wall_ms": Time.get_ticks_msec() - frame_start})
			report.status = "rendering"; report.counters = worker.counters.duplicate()
			if not _report(output, report): worker.release(); _fail("Cannot update progress"); return
			print("TURN_GIFS FRAME %s %d/%d  %.2fs  total %.1fmin" % [id, frame + 1, int(opts.frames),
				float(Time.get_ticks_msec() - frame_start) / 1000, float(Time.get_ticks_msec() - start) / 60000])
		var encoded: Array = []
		var code := OS.execute(opts.python, [ProjectSettings.globalize_path("res://tools/turn_gifs_encode.py"),
			ProjectSettings.globalize_path(directory), ProjectSettings.globalize_path(output.path_join(id + ".gif")),
			str(opts.fps), "--frames", str(opts.frames), "--size", str(opts.res)], encoded, true)
		if code != 0: worker.release(); _fail("Encoding %s: %s" % [id, encoded]); return
		stone_report.status = "complete"
		print("TURN_GIFS ENCODED ", id, " ", str(encoded))
	worker.release()
	report.status = "complete"; report.wall_seconds = float(Time.get_ticks_msec() - start) / 1000
	if not _report(output, report): _fail("Cannot save final report"); return
	print("TURN_GIFS COMPLETE ", batch.requests.size(), " stones -> ", output)
	quit()

func _options(args: PackedStringArray) -> Dictionary:
	var opts := {"output": DEFAULT_OUTPUT, "res": 256, "frames": 120, "fps": 30, "spp": 0,
		"rung": "hero", "stones": "", "python": "python", "plan_only": false}
	var i := 0
	while i < args.size():
		var argument := args[i]
		if argument == "--plan-only": opts.plan_only = true; i += 1; continue
		if argument == "--keep-frames": i += 1; continue
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if not argument.begins_with("--") or not opts.has(pair[0]) or pair[0] == "plan_only":
			_error = "Unknown option: " + argument; return opts
		var value := ""
		if pair.size() == 2: value = pair[1]
		elif i + 1 < args.size(): i += 1; value = args[i]
		else: _error = "Missing value: " + argument; return opts
		if pair[0] in ["res", "frames", "fps", "spp"]:
			if not value.is_valid_int() or int(value) <= 0: _error = "Expected positive integer: " + argument; return opts
			opts[pair[0]] = int(value)
		else: opts[pair[0]] = value
		i += 1
	if int(opts.res) > 2048 or int(opts.frames) > 4096 or int(opts.fps) > 50:
		_error = "Inspection limits: res <= 2048, frames <= 4096, fps <= 50"
	if GemRung.rung_from_name(opts.rung) < 0: _error = "Unknown rung: " + str(opts.rung)
	return opts

func _batch(opts: Dictionary) -> GemAssetBatch:
	var batch := GemAssetBatch.new()
	batch.frame_budget = 65536
	var selected := PackedStringArray()
	if not String(opts.stones).is_empty(): selected = String(opts.stones).split(",", false)
	var available := []
	for filename in DirAccess.get_files_at(STONES_DIR):
		if filename.ends_with(".tres"): available.append(filename.get_basename())
	for id in selected:
		if id not in available: _error = "Unknown catalog stone: " + id; return null
	var clip := GemClip.new()
	clip.clip_id = &"inspection_rotation"; clip.fps = opts.fps
	clip.duration_s = float(opts.frames) / float(opts.fps); clip.loop = true
	clip.stone_motion = GemClip.StoneMotion.TURNTABLE
	clip.rest_tilt_deg = Vector3(-12, 0, 0); clip.turntable_axis = Vector3.UP; clip.turntable_degrees = 360
	for id: String in available:
		if not selected.is_empty() and id not in selected: continue
		var request := GemAssetRequest.new()
		request.asset_id = StringName(id); request.stone = load(STONES_DIR.path_join(id + ".tres"))
		request.clips.append(clip); request.rig = load(RIG_PATH); request.print_style = GemPrint.load_house()
		request.rung = opts.rung; request.resolution = Vector2i.ONE * int(opts.res)
		request.output_size = request.resolution; request.samples = opts.spp
		request.game_style = null
		batch.requests.append(request)
	return batch

func _report(output: String, report: Dictionary) -> bool:
	return GemArtifactStore.atomic_write(output.path_join("report.json"), JSON.stringify(report, "\t", true, true).to_utf8_buffer())

func _fail(message: String) -> void:
	printerr("TURN_GIFS FAILED: " + message)
	quit(1)
