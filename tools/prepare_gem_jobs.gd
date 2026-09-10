extends SceneTree
## Headless job authoring. --out=... --stone=quartz --clip=idle --rung=preview
## Optional --resolution=64 --samples=16 are explicit job policy overrides.
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var output: String = args.get("out", "res://generated/gem-job-bundle")
	var rig: GemLightRig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	var print_style := GemPrint.load_house()
	var rung := GemRung.rung_from_name(args.get("rung", "clip_bake"))
	if rung < 0:
		printerr("Unknown quality rung")
		quit(1)
		return
	var jobs: Array[GemFrameJob] = []
	var clips := {}
	for filename in DirAccess.get_files_at("res://data/lapidary/stones"):
		if not filename.ends_with(".tres") or (args.has("stone") and filename != args["stone"] + ".tres"):
			continue
		var stone: GemStone = load("res://data/lapidary/stones/" + filename)
		for name in ["idle", "turn", "flash"]:
			if args.has("clip") and name != args["clip"]:
				continue
			var clip: GemClip = load("res://data/lapidary/clips/" + name + ".tres")
			var frames := GemFramePlan.animation(stone, clip, rig, print_style, rung)
			var ids := []
			for job in frames:
				if args.has("resolution"):
					job.resolution = Vector2i.ONE * int(args["resolution"])
					job.output_size = job.resolution
				if args.has("samples"):
					job.samples = int(args["samples"])
				ids.append(GemFramePlan.display_key(job))
			jobs.append_array(frames)
			clips[String(stone.stone_id) + "/" + name] = {"frames": ids, "fps": clip.fps, "loop": clip.loop}
	if jobs.is_empty():
		printerr("No matching stone/clip jobs")
		quit(1)
		return
	var manifest := GemJobBundle.write(output, jobs, clips)
	if manifest.is_empty() or GemJobBundle.archive(output, output + ".zip") != OK:
		printerr("Failed to write portable job bundle")
		quit(1)
		return
	print("Portable jobs: ", output, " ", JSON.stringify(manifest["estimate"]))
	quit()
