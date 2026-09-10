extends SceneTree
## CPU-only consolidation of stopped farm output stores. Dry run by default.
## --source=... (repeat) --destination=... --manifest=... --apply=true
## --conflict=error|keep_existing. Source argument order defines precedence.
func _initialize() -> void:
	var sources := PackedStringArray()
	var destination := "res://generated/gemfactory"
	var manifest_path := "res://generated/gem-job-bundle/manifest.json"
	var apply := false
	var policy := "error"
	var initialize := false
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"source": sources.append(pair[1])
			"destination": destination = pair[1]
			"manifest": manifest_path = pair[1]
			"apply": apply = pair[1] == "true"
			"conflict": policy = pair[1]
			"initialize-destination": initialize = pair[1] == "true"
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		printerr("Invalid job manifest")
		quit(1)
		return
	var transfer := GemStoreTransfer.new()
	if initialize and not GemArtifactStore.new(destination).initialize():
		printerr("Destination must be an empty directory or an existing marked store")
		quit(1)
		return
	var result := transfer.merge(destination, sources, manifest, apply, policy)
	if result.is_empty():
		GemArtifactStore.atomic_write("res://artifacts/farm-transfer.json", JSON.stringify(transfer.last_report, "\t").to_utf8_buffer())
		printerr(transfer.last_error)
		quit(1)
		return
	GemArtifactStore.atomic_write("res://artifacts/farm-transfer.json", JSON.stringify(result, "\t").to_utf8_buffer())
	print(JSON.stringify(result))
	quit(0)
