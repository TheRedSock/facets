extends SceneTree
## Dry-run by default. --store=... --manifest=... (repeatable)
## --budget-mib=2048 retains spare recent masters; required jobs always survive.
## --apply=true performs the reported collection. Never run alongside render jobs.
func _initialize() -> void:
	var root := "res://generated/gemfactory"
	var manifests := []
	var budget_mib := 2048
	var apply := false
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0]:
			"store": root = pair[1]
			"manifest":
				var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(pair[1]))
				manifests.append(manifest)
			"budget-mib": budget_mib = int(pair[1])
			"apply": apply = pair[1] == "true"
	if manifests.is_empty():
		manifests.append(JSON.parse_string(FileAccess.get_file_as_string("res://generated/gem-job-bundle/manifest.json")))
	var maintenance := GemStoreMaintenance.new()
	var result := maintenance.collect(root, manifests, budget_mib * 1024 * 1024, apply)
	if result.is_empty():
		printerr(maintenance.last_error)
		quit(1)
		return
	GemArtifactStore.atomic_write("res://artifacts/store-maintenance.json", JSON.stringify(result, "\t").to_utf8_buffer())
	result.erase("paths")
	print(JSON.stringify(result))
	print("CHECK_COMPLETE: maintain_gem_store")
	quit()
