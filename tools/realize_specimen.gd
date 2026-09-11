extends SceneTree
## --recipe=... --quality=... --seed=... --base=... --output=....res
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: args[pair[0]] = pair[1]
	var path: String = args.get("recipe", "res://data/lapidary/recipes/quartz_condition_study.tres")
	var output: String = args.get("output", "res://generated/specimens/quartz.res")
	var seed_text: String = args.get("seed", "1")
	if not ResourceLoader.exists(path) or output.get_extension() != "res" or not seed_text.is_valid_int():
		printerr("FAIL: existing recipe, integer seed and binary .res output required"); quit(1); return
	var base: GemStone = null
	if args.has("base"):
		if not ResourceLoader.exists(args.base): printerr("FAIL: base specimen missing"); quit(1); return
		base = load(args.base) as GemStone
		if base == null: printerr("FAIL: base must be GemStone"); quit(1); return
	var result := GemSpecimenFactory.realize(load(path) as GemSpecimenRecipe, StringName(args.get("quality", "reference")), int(seed_text), base)
	if not result.error.is_empty(): printerr("FAIL: " + result.error); quit(1); return
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK or GemResourceBundle.save(result.stone, output) != OK:
		printerr("FAIL: cannot save realized specimen"); quit(1); return
	if not GemArtifactStore.atomic_write(output.get_basename() + ".json", JSON.stringify(result.report, "\t", true, true).to_utf8_buffer()):
		printerr("FAIL: cannot save realization provenance"); quit(1); return
	print("Realized specimen: ", output, " ", JSON.stringify(result.report.parameters)); quit()
