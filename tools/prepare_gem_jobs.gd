extends SceneTree
## Explicit batch or catalog convenience input -> one validated request planner.
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: args[pair[0]] = pair[1]
	var output: String = args.get("out", "res://generated/gem-job-bundle")
	var batch: GemAssetBatch
	if args.has("batch"):
		for key in args:
			if key not in ["batch", "out", "geometry-coverage"]:
				_fail("A batch carries its own variants and policies; unexpected override: " + key); return
		if not ResourceLoader.exists(args.batch): _fail("Asset batch does not exist"); return
		batch = load(args.batch) as GemAssetBatch
		if batch == null: _fail("Expected GemAssetBatch resource"); return
		# Only the batch wrapper is edited here; planner validates and detaches
		# each request before realization or clip sampling.
		batch = batch.duplicate()
	else:
		batch = _convenience_batch(args)
		if batch == null: return
	if args.has("geometry-coverage"):
		var coverage: String = args["geometry-coverage"]
		if not coverage.is_valid_int(): _fail("Geometry coverage must be an integer"); return
		batch.geometry_coverage_side = int(coverage)
	var planned := GemAssetPlanner.plan(batch)
	if not planned.error.is_empty(): _fail(planned.error); return
	var manifest := GemJobBundle.write(output, planned.jobs, planned.clips, planned.geometry_coverage_side)
	if manifest.is_empty() or GemJobBundle.archive(output, output + ".zip") != OK:
		_fail("Failed to write portable job bundle"); return
	print("Portable jobs: ", output, " ", JSON.stringify(manifest.estimate), " geometry companions: ", manifest.geometry.size())
	quit()

func _convenience_batch(args: Dictionary) -> GemAssetBatch:
	var batch := GemAssetBatch.new()
	var template := GemAssetRequest.new()
	template.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	template.print_style = GemPrint.load_house()
	template.rung = args.get("rung", "clip_bake")
	if args.has("style"):
		if not ResourceLoader.exists(args.style): _fail("Style resource does not exist"); return null
		template.game_style = load(args.style) as GemStyle
		if template.game_style == null: _fail("Expected GemStyle resource"); return null
	template.retain_prints = args.get("retain-prints", "false") == "true"
	for key in ["resolution", "samples"]:
		if args.has(key) and (not str(args[key]).is_valid_int() or int(args[key]) <= 0):
			_fail(key + " must be a positive integer"); return null
	if args.has("resolution"):
		template.resolution = Vector2i.ONE * int(args.resolution)
		template.output_size = template.resolution
	if args.has("samples"): template.samples = int(args.samples)
	for name in ["idle", "turn", "flash"]:
		if not args.has("clip") or name == args.clip:
			template.clips.append(load("res://data/lapidary/clips/" + name + ".tres"))
	if args.has("recipe"):
		if args.has("specimen") or args.has("stone") or not args.has("quality") or not ResourceLoader.exists(args.recipe):
			_fail("Choose an existing --recipe with explicit --quality, or a specimen/catalog source"); return null
		template.recipe = load(args.recipe) as GemSpecimenRecipe
		if template.recipe == null or template.recipe.base == null: _fail("Invalid specimen recipe"); return null
		var seed_text: String = args.get("seed", "1")
		if not seed_text.is_valid_int(): _fail("Specimen seed must be an integer"); return null
		template.specimen_seed = int(seed_text); template.preset_id = StringName(args.quality)
		template.asset_id = template.recipe.base.stone_id
		batch.requests.append(template)
	elif args.has("quality") or args.has("seed"):
		_fail("--quality and --seed require an explicit specimen --recipe"); return null
	else:
		var specimens: Array[GemStone] = []
		if args.has("specimen"):
			if args.has("stone") or not ResourceLoader.exists(args.specimen): _fail("Choose an existing specimen or catalog stone"); return null
			var stone := load(args.specimen) as GemStone
			if stone == null: _fail("Expected GemStone resource"); return null
			specimens.append(stone)
		else:
			for filename in DirAccess.get_files_at("res://data/lapidary/stones"):
				if filename.ends_with(".tres") and (not args.has("stone") or filename == args.stone + ".tres"):
					specimens.append(load("res://data/lapidary/stones/" + filename))
		for stone in specimens:
			var request: GemAssetRequest = template.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
			request.stone = stone; request.asset_id = stone.stone_id
			batch.requests.append(request)
	return batch

func _fail(message: String) -> void:
	printerr("FAIL: " + message); quit(1)
