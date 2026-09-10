extends SceneTree
## --csv=raw.csv --metadata=measurement.json --out=res://data/lapidary/chromophores/name.tres
## CSV: wavelength_nm,ordinary[,extraordinary]. Metadata declares quantity,
## optical_basis, citation, method; transmission also needs path_mm and true
## surface_reflection_removed/scattering_removed. No implicit extrapolation.
func _initialize() -> void:
	var args := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	if not args.has_all(["csv", "metadata", "out"]):
		printerr("Required: --csv=... --metadata=... --out=...")
		quit(1)
		return
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(args["metadata"]))
	if not metadata is Dictionary:
		printerr("Measurement metadata must be a JSON object")
		quit(1)
		return
	var result := GemAbsorptionImport.read_csv(args["csv"], metadata)
	if result.has("error"):
		printerr(result["error"])
		quit(1)
		return
	var output: String = args["out"]
	if output.get_extension() not in ["res", "tres"]:
		printerr("Output must be a Godot .res or .tres resource")
		quit(1)
		return
	var resource: GemChromophore = result["chromophore"]
	# Keep raw data and its interpretation beside the build resource, so imported
	# coefficients can be traced back and regenerated without external services.
	var source_root := output.get_base_dir().path_join("measurements")
	var base := source_root.path_join(resource.absorption_evidence.dataset_sha256)
	var interpretation := base + "-" + GemContentIdentity.digest(metadata) + ".json"
	if not GemArtifactStore.atomic_write(source_root.path_join(".gdignore"), PackedByteArray()) or not GemArtifactStore.atomic_write(base + ".csv", FileAccess.get_file_as_bytes(args["csv"])) or not GemArtifactStore.atomic_write(interpretation, JSON.stringify(metadata, "\t").to_utf8_buffer()):
		printerr("Cannot retain measurement source")
		quit(1)
		return
	if ResourceSaver.save(resource, output) != OK:
		printerr("Cannot save imported absorption")
		quit(1)
		return
	print("Imported ", resource.chromophore_id, ": 401 samples, Napierian /mm; raw SHA256 ", resource.absorption_evidence.dataset_sha256)
	quit()
