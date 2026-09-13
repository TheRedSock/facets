extends SceneTree
## --manifest=... --store=... --out=... --codec=webp_lossless|bc7|astc4x4 --page=512
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	var input: Variant = JSON.parse_string(FileAccess.get_file_as_string(args.get("manifest", "res://generated/gem-job-bundle/manifest.json")))
	if not input is Dictionary or not input.get("clips") is Dictionary:
		printerr("Invalid job manifest")
		quit(1)
		return
	var packer := GemPagePacker.new(GemArtifactStore.new(args.get("store", "res://generated/gemfactory")), args.get("out", "res://generated/gem-library"))
	packer.codec = args.get("codec", "webp_lossless")
	packer.page_edge = int(args.get("page", 512))
	var result := packer.pack(input["clips"])
	if result.is_empty():
		quit(1)
		return
	print("Delivery library: ", JSON.stringify(result["statistics"]))
	var pack_path: String = args.get("pack", packer.output.get_base_dir().path_join("gem-assets.pck"))
	if GemPagePacker.write_game_pack(packer.output.path_join("library.json"), pack_path) != OK:
		printerr("Cannot publish game asset pack")
		quit(1)
		return
	print("Game asset pack: ", pack_path)
	print("CHECK_COMPLETE: pack_gem_library")
	quit()
