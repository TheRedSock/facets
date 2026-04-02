extends SceneTree

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemOpticsTracerScript = preload("res://core/visuals/gem_optics_tracer.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		push_error("Offline bake runner requires GemVisualRegistry autoload")
		quit(1)
		return

	var args := _parse_args(OS.get_cmdline_user_args())
	var size := maxi(int(args.get("size", 112)), 16)
	var draw_size := maxi(int(args.get("draw_size", size)), 16)
	var tile_ids := _resolve_tile_ids(args.get("gems", "all"), registry)
	if tile_ids.is_empty():
		push_error("No matching gem visuals found for offline bake")
		quit(1)
		return
	var sample_count := clampi(
		maxi(int(args.get("samples", 1)), 1),
		1,
		GemOpticsTracerScript.max_supported_sample_count()
	)
	var options := {
		"output_root": args.get("output", "user://traced_bakes"),
		"draw_size": Vector2i(draw_size, draw_size),
		"sample_count": sample_count,
	}
	var thread_count := int(args.get("threads", 0))
	if thread_count > 0:
		options["thread_count"] = thread_count
	var lighting_bins := _parse_lighting_bins(String(args.get("lighting_bins", "")))
	if not lighting_bins.is_empty():
		options["lighting_bins"] = lighting_bins
	var rotation_bins := _parse_rotation_bins(String(args.get("rotation_bins", "")))
	if not rotation_bins.is_empty():
		options["rotation_bins"] = rotation_bins
	var rotation_axes := _parse_rotation_axes(String(args.get("rotation_axes", "")))
	if not rotation_axes.is_empty():
		options["rotation_axes"] = rotation_axes
	var rotation_axis_steps := maxi(int(args.get("rotation_axis_steps", 0)), 0)
	if rotation_axis_steps > 0:
		options["rotation_axis_steps"] = rotation_axis_steps
	var rotation_step_degrees := float(args.get("rotation_step_degrees", 0.0))
	if rotation_step_degrees > 0.0:
		options["rotation_step_degrees"] = rotation_step_degrees
	var job = OfflineGemBakeJobScript.new()
	job.progress_updated.connect(_on_job_progress)
	print("Starting offline traced bake")
	print("Gems: %s" % _tile_ids_to_text(tile_ids))
	print("Cell size: %dx%d  Draw size: %dx%d  Samples: %d  Threads: %s  Output: %s" % [
		size,
		size,
		draw_size,
		draw_size,
		sample_count,
		str(options.get("thread_count", "auto")),
		String(options["output_root"]),
	])
	var result: Dictionary = job.run_batch(registry, tile_ids, Vector2i(size, size), options)
	print("Offline traced bake: %s" % result.get("status", "unknown"))
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


func _parse_tile_ids(raw_value: String) -> Array:
	var tile_ids: Array = []
	var seen: Dictionary = {}
	for token in raw_value.split(",", false):
		var trimmed := token.strip_edges()
		if trimmed.is_empty():
			continue
		var tile_id := StringName(trimmed)
		if seen.has(tile_id):
			continue
		seen[tile_id] = true
		tile_ids.append(tile_id)
	return tile_ids


func _resolve_tile_ids(raw_value: String, registry: Node) -> Array:
	var normalized := raw_value.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "all":
		return registry.get_visual_ids()
	return _parse_tile_ids(raw_value)


func _parse_rotation_bins(raw_value: String) -> Array:
	var bins: Array = []
	var seen: Dictionary = {}
	for token in raw_value.replace(";", ",").split(",", false):
		var trimmed := token.strip_edges()
		if trimmed.is_empty():
			continue
		var rotation_bin := int(trimmed)
		if seen.has(rotation_bin):
			continue
		seen[rotation_bin] = true
		bins.append(rotation_bin)
	return bins


func _parse_rotation_axes(raw_value: String) -> Array:
	var axes: Array[StringName] = []
	var seen: Dictionary = {}
	for token in raw_value.replace(";", ",").split(",", false):
		var trimmed := token.strip_edges().to_lower()
		if trimmed.is_empty():
			continue
		var axis := StringName(trimmed)
		if axis != &"pitch" and axis != &"yaw" and axis != &"roll":
			continue
		if seen.has(axis):
			continue
		seen[axis] = true
		axes.append(axis)
	return axes


func _parse_lighting_bins(raw_value: String) -> Array:
	var bins: Array = []
	var seen: Dictionary = {}
	for token in raw_value.replace("|", ";").split(";", false):
		var trimmed := token.strip_edges()
		if trimmed.is_empty():
			continue
		var pair: PackedStringArray = []
		if trimmed.contains("x"):
			pair = trimmed.split("x", false, 1)
		elif trimmed.contains(","):
			pair = trimmed.split(",", false, 1)
		if pair.size() != 2:
			continue
		var lighting_bin := Vector2i(int(pair[0].strip_edges()), int(pair[1].strip_edges()))
		if seen.has(lighting_bin):
			continue
		seen[lighting_bin] = true
		bins.append(lighting_bin)
	return bins


func _on_job_progress(progress: Dictionary) -> void:
	var stage := String(progress.get("stage", ""))
	var completed := int(progress.get("completed", 0))
	var total := int(progress.get("total", 0))
	var elapsed_ms := float(progress.get("elapsed_ms", 0.0))
	var variant_elapsed_ms := float(progress.get("variant_elapsed_ms", 0.0))
	var tile_id := String(progress.get("tile_id", &""))
	var variant_key := String(progress.get("variant_key", &""))
	match stage:
		"queued":
			print("Queued %d traced variants" % total)
		"baking":
			print("[%d/%d] Baking %s %s  |  elapsed %.1fms" % [
				completed + 1,
				total,
				tile_id,
				variant_key,
				elapsed_ms,
			])
		"baked":
			print("[%d/%d] %s %s  |  variant %.1fms  total %.1fms  saved=%d  status=%s" % [
				completed,
				total,
				tile_id,
				variant_key,
				variant_elapsed_ms,
				elapsed_ms,
				int(progress.get("saved_entries", 0)),
				String(progress.get("status", "unknown")),
			])
		"skipped":
			print("[%d/%d] Skipped %s %s  |  %.1fms" % [
				completed,
				total,
				tile_id,
				variant_key,
				variant_elapsed_ms,
			])
		"complete":
			print("Completed traced bake in %.1fms  |  saved=%d  |  %s" % [
				elapsed_ms,
				int(progress.get("saved_entries", 0)),
				String(progress.get("manifest_path", "")),
			])


func _tile_ids_to_text(tile_ids: Array) -> String:
	var names: PackedStringArray = []
	for tile_id in tile_ids:
		names.append(String(tile_id))
	return ",".join(names)
