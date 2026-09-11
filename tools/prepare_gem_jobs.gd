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
	var game_style: GemStyle = null
	if args.has("style"):
		if not ResourceLoader.exists(args.style):
			printerr("Style resource does not exist"); quit(1); return
		game_style = load(args.style) as GemStyle
		if game_style == null or not game_style.validate().is_empty():
			printerr("Invalid GemStyle resource"); quit(1); return
	var rung := GemRung.rung_from_name(args.get("rung", "clip_bake"))
	if rung < 0:
		printerr("Unknown quality rung")
		quit(1)
		return
	var jobs: Array[GemFrameJob] = []
	var clips := {}
	var specimens:Array[GemStone]=[]
	if args.has("specimen"):
		if args.has("stone") or not ResourceLoader.exists(args.specimen):
			printerr("Choose an existing --specimen resource or a catalog --stone, not both");quit(1);return
		var specimen:=load(args.specimen) as GemStone
		if specimen==null:printerr("Specimen resource must be a GemStone");quit(1);return
		specimens.append(specimen)
	else:
		for filename in DirAccess.get_files_at("res://data/lapidary/stones"):
			if filename.ends_with(".tres") and (not args.has("stone") or filename==args.stone+".tres"):
				specimens.append(load("res://data/lapidary/stones/"+filename))
	for stone in specimens:
		for name in ["idle", "turn", "flash"]:
			if args.has("clip") and name != args["clip"]:
				continue
			var clip: GemClip = load("res://data/lapidary/clips/" + name + ".tres")
			var frames := GemFramePlan.animation(stone, clip, rig, print_style, rung)
			var ids := []
			for job in frames:
				job.game_style = game_style
				if args.has("resolution"):
					job.resolution = Vector2i.ONE * int(args["resolution"])
					job.output_size = job.resolution
				if args.has("samples"):
					job.samples = int(args["samples"])
				ids.append(GemFramePlan.display_key(job))
				if game_style != null and not game_style.is_identity() and args.get("retain-prints", "false") == "true":
					var unstyled: GemFrameJob = job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
					unstyled.game_style = null
					jobs.append(unstyled)
			jobs.append_array(frames)
			clips[String(stone.stone_id) + "/" + name] = {"frames": ids, "fps": clip.fps, "loop": clip.loop}
	if jobs.is_empty():
		printerr("No matching stone/clip jobs")
		quit(1)
		return
	var geometry_value := str(args.get("geometry-coverage", "0"))
	if not geometry_value.is_valid_int():
		printerr("Geometry coverage must be an integer: 0, 1, 2, 4 or 8")
		quit(1)
		return
	var geometry_side := int(geometry_value)
	var manifest := GemJobBundle.write(output, jobs, clips, geometry_side)
	if manifest.is_empty() or GemJobBundle.archive(output, output + ".zip") != OK:
		printerr("Failed to write portable job bundle")
		quit(1)
		return
	print("Portable jobs: ", output, " ", JSON.stringify(manifest["estimate"]), " geometry companions: ", manifest.geometry.size())
	quit()
