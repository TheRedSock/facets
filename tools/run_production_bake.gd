extends SceneTree

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const ProductionBakeProfileScript = preload("res://tools/production_bake_profile.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		push_error("Production bake requires GemVisualRegistry autoload")
		quit(1)
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	var profile_path := String(args.get("profile", "")).strip_edges()
	if profile_path.is_empty():
		push_error("Usage: --profile=res://config/bake_profiles/gameplay.json")
		quit(1)
		return
	var profile: Dictionary = ProductionBakeProfileScript.load_profile_file(profile_path)
	if profile.is_empty():
		quit(1)
		return
	var tile_ids: Array = ProductionBakeProfileScript.resolve_gems_list(profile.get("gems", "all"), registry)
	if tile_ids.is_empty():
		push_error("Production bake: no gems to bake (check profile `gems` and registry)")
		quit(1)
		return
	var options: Dictionary = ProductionBakeProfileScript.profile_to_bake_options(profile, profile_path)
	var cell := maxi(int(profile.get("cell_size", 112)), 16)
	var cell_size := Vector2i(cell, cell)
	var draw_sz: Vector2i = options.get("draw_size", cell_size)
	var job = OfflineGemBakeJobScript.new()
	print("Production traced bake")
	print("Profile: %s (%s)" % [String(profile.get("profile_id", "")), profile_path])
	print("Gems: %d  Cell: %dx%d  Draw: %dx%d  Output: %s" % [
		tile_ids.size(),
		cell_size.x,
		cell_size.y,
		draw_sz.x,
		draw_sz.y,
		String(options.get("output_root", "")),
	])
	var result: Dictionary = job.run_batch(registry, tile_ids, cell_size, options)
	print("Status: %s" % String(result.get("status", "unknown")))
	print("Manifest: %s" % String(result.get("manifest_path", "")))
	print("Entries: %d" % int(result.get("entry_count", 0)))
	quit(0 if result.get("status", "") == "ok" else 1)


func _parse_args(args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in args:
		if not arg.begins_with("--"):
			continue
		var trimmed := arg.substr(2)
		var parts := trimmed.split("=", false, 1)
		if parts.size() == 2:
			parsed[parts[0]] = parts[1]
		else:
			parsed[trimmed] = true
	return parsed
