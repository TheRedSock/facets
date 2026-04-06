extends SceneTree

const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")

var _status_path := ""
var _status_context: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	var args := _parse_args(OS.get_cmdline_user_args())
	_status_path = String(args.get("status_path", ""))
	_status_context = {
		"job_id": String(args.get("job_id", "")),
		"pid": OS.get_process_id(),
	}
	if registry == null:
		_write_status({
			"stage": "error",
			"status": "missing_registry",
		})
		push_error("Offline bake runner requires GemVisualRegistry autoload")
		quit(1)
		return

	var size := maxi(int(args.get("size", 112)), 16)
	var draw_size := maxi(int(args.get("draw_size", size)), 16)
	var tile_ids := _resolve_tile_ids(args.get("gems", "all"), registry)
	if tile_ids.is_empty():
		_write_status({
			"stage": "error",
			"status": "no_matching_gems",
		})
		push_error("No matching gem visuals found for offline bake")
		quit(1)
		return
	var sample_count := clampi(
		maxi(int(args.get("samples", 1)), 1),
		1,
		OfflineGemBakeJobScript.max_supported_sample_count()
	)
	var options := {
		"output_root": args.get("output", "user://traced_bakes"),
		"draw_size": Vector2i(draw_size, draw_size),
		"sample_count": sample_count,
	}
	if bool(args.get("trace_profile", false)):
		options["trace_profile"] = true
	var max_trace_bounces := int(args.get("max_trace_bounces", 0))
	if max_trace_bounces > 0:
		options["max_trace_bounces"] = GemTracedBakeContractScript.resolve_max_trace_bounces(
			max_trace_bounces
		)
	var thread_count := int(args.get("threads", 0))
	if thread_count > 0:
		options["thread_count"] = thread_count
	var variant_worker_count := int(args.get("variant_workers", args.get("variant_parallelism", 0)))
	if variant_worker_count > 0:
		options["variant_worker_count"] = variant_worker_count
	# --skip_lighting / --skip_rotations disable variant types entirely.
	var skip_lighting := args.has("skip_lighting") or args.has("no_lighting")
	var skip_rotations := args.has("skip_rotations") or args.has("no_rotations")
	if skip_lighting:
		options["skip_lighting"] = true
		options["lighting_grid_size"] = Vector2i.ZERO
	if skip_rotations:
		options["skip_rotations"] = true
		options["rotation_base_view_count"] = 0
		options["rotation_axis_steps"] = 0
	var lighting_preset := String(args.get("lighting_preset", "")).strip_edges().to_lower()
	if not lighting_preset.is_empty() and not skip_lighting:
		options["lighting_grid_preset"] = StringName(lighting_preset)
	var lighting_grid_size := _parse_grid_size(String(args.get("lighting_grid", "")))
	if lighting_grid_size == Vector2i.ZERO:
		# Allow bare "--lighting_grid=0" as shorthand for "--skip_lighting".
		var raw_grid_value := String(args.get("lighting_grid", "")).strip_edges()
		if raw_grid_value == "0" or raw_grid_value == "none":
			skip_lighting = true
			options["skip_lighting"] = true
			options["lighting_grid_size"] = Vector2i.ZERO
		else:
			var grid_x := maxi(int(args.get("lighting_grid_x", 0)), 0)
			var grid_y := maxi(int(args.get("lighting_grid_y", 0)), 0)
			if grid_x > 0 and grid_y > 0:
				lighting_grid_size = Vector2i(grid_x, grid_y)
	if lighting_grid_size != Vector2i.ZERO and not skip_lighting:
		options["lighting_grid_size"] = lighting_grid_size
	var lighting_runtime_grid_size := _parse_grid_size(String(args.get("lighting_runtime_grid", "")))
	if lighting_runtime_grid_size == Vector2i.ZERO:
		var runtime_grid_x := maxi(int(args.get("lighting_runtime_grid_x", 0)), 0)
		var runtime_grid_y := maxi(int(args.get("lighting_runtime_grid_y", 0)), 0)
		if runtime_grid_x > 0 and runtime_grid_y > 0:
			lighting_runtime_grid_size = Vector2i(runtime_grid_x, runtime_grid_y)
	if lighting_runtime_grid_size != Vector2i.ZERO:
		options["lighting_runtime_grid_size"] = lighting_runtime_grid_size
	var lighting_bins := _parse_lighting_bins(String(args.get("lighting_bins", "")))
	if not lighting_bins.is_empty():
		options["lighting_bins"] = lighting_bins
	var rotation_bins := _parse_rotation_bins(String(args.get("rotation_bins", "")))
	if not rotation_bins.is_empty():
		options["rotation_bins"] = rotation_bins
	var rotation_labels := _parse_rotation_labels(String(args.get("rotation_labels", "")))
	if not rotation_labels.is_empty():
		options["rotation_labels"] = rotation_labels
	var rotation_axes := _parse_rotation_axes(String(args.get("rotation_axes", "")))
	if not rotation_axes.is_empty():
		options["rotation_axes"] = rotation_axes
	if args.has("rotation_base_view_count"):
		options["rotation_base_view_count"] = maxi(int(args.get("rotation_base_view_count", 0)), 0)
	var rotation_axis_steps := maxi(int(args.get("rotation_axis_steps", 0)), 0)
	if rotation_axis_steps > 0:
		options["rotation_axis_steps"] = rotation_axis_steps
	var rotation_step_degrees := float(args.get("rotation_step_degrees", 0.0))
	if rotation_step_degrees > 0.0:
		options["rotation_step_degrees"] = rotation_step_degrees
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	# skip_stylize is not a variant setting — add it after variant settings are resolved
	# so it doesn't pass through normalize_variant_settings.
	if args.has("skip_stylize"):
		options["skip_stylize"] = true
	_status_context["settings"] = {
		"tile_ids": tile_ids.duplicate(),
		"cell_size": Vector2i(size, size),
		"draw_size": Vector2i(draw_size, draw_size),
		"sample_count": sample_count,
		"max_trace_bounces": int(options.get("max_trace_bounces", 0)),
		"thread_count": int(options.get("thread_count", 0)),
		"variant_worker_count": int(options.get("variant_worker_count", 0)),
		"output_root": String(options["output_root"]),
		"variant_settings": variant_settings,
	}
	var job = OfflineGemBakeJobScript.new()
	job.progress_updated.connect(_on_job_progress)
	_write_status({
		"stage": "starting",
		"completed": 0,
		"total": 0,
		"progress": 0.0,
	})
	print("Starting offline traced bake")
	print("Gems: %s" % _tile_ids_to_text(tile_ids))
	print("Cell size: %dx%d  Draw size: %dx%d  Samples: %d  Max bounces: %s  Threads: %s  Variant workers: %s  Output: %s" % [
		size,
		size,
		draw_size,
		draw_size,
		sample_count,
		str(options.get("max_trace_bounces", "default")),
		str(options.get("thread_count", "auto")),
		str(options.get("variant_worker_count", "auto")),
		String(options["output_root"]),
	])
	print("Lighting preset: %s  Baked grid: %s  Runtime grid: %s" % [
		String(variant_settings.get("lighting_grid_preset", &"custom")),
		str(variant_settings.get("lighting_grid_size", Vector2i.ZERO)),
		str(variant_settings.get("lighting_runtime_grid_size", Vector2i.ZERO)),
	])
	var result: Dictionary = job.run_batch(registry, tile_ids, Vector2i(size, size), options)
	_write_status({
		"stage": "complete" if result.get("status", "") == "ok" else "error",
		"status": String(result.get("status", "unknown")),
		"completed": int(result.get("entry_count", 0)),
		"total": int(result.get("entry_count", 0)),
		"progress": 1.0 if result.get("status", "") == "ok" else 0.0,
		"manifest_path": String(result.get("manifest_path", "")),
		"entry_count": int(result.get("entry_count", 0)),
		"profile": result.get("profile", {}),
	})
	print("Offline traced bake: %s" % result.get("status", "unknown"))
	print("Manifest: %s" % String(result.get("manifest_path", "")))
	print("Entries: %d" % int(result.get("entry_count", 0)))
	var result_profile: Dictionary = result.get("profile", {})
	if not result_profile.is_empty():
		print("Profile: request_build=%.1fms  mesh=%.1fms  trace=%.1fms  stylize=%.1fms  save=%.1fms" % [
			float(result_profile.get("request_build_elapsed_ms", 0.0)),
			float(result_profile.get("mesh_build_elapsed_ms", 0.0)),
			float(result_profile.get("trace_elapsed_ms", 0.0)),
			float(result_profile.get("stylize_elapsed_ms", 0.0)),
			float(result_profile.get("save_elapsed_ms", 0.0)),
		])
		var trace_detail_profile: Dictionary = result_profile.get("trace_detail_profile", {})
		print("Execution: cpu_budget=%d  trace_thread_budget=%d  actual_trace_threads=%d  variant_workers=%d  pipeline=%s" % [
			int(result_profile.get("cpu_budget", 0)),
			int(result_profile.get("trace_thread_budget", 0)),
			int(trace_detail_profile.get("thread_count", 0)),
			int(result_profile.get("variant_worker_count", 0)),
			str(bool(result_profile.get("pipeline_enabled", false))),
		])
		_print_trace_detail_profile(trace_detail_profile)
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


func _parse_rotation_labels(raw_value: String) -> Array:
	var labels: Array = []
	var seen: Dictionary = {}
	for token in raw_value.replace(";", ",").split(",", false):
		var trimmed := token.strip_edges()
		if trimmed.is_empty():
			continue
		var label := StringName(trimmed)
		if seen.has(label):
			continue
		seen[label] = true
		labels.append(label)
	return labels


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


func _parse_grid_size(raw_value: String) -> Vector2i:
	var trimmed := raw_value.strip_edges().to_lower()
	if trimmed.is_empty():
		return Vector2i.ZERO
	var separator := "x" if trimmed.contains("x") else ","
	var parts := trimmed.split(separator, false, 1)
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(maxi(int(parts[0].strip_edges()), 0), maxi(int(parts[1].strip_edges()), 0))


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
	_write_status(progress)
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
			print("[%d/%d] Baking %s %s  |  elapsed %.1fms  mesh %.1fms" % [
				completed + 1,
				total,
				tile_id,
				variant_key,
				elapsed_ms,
				float(progress.get("mesh_build_elapsed_ms", 0.0)),
			])
		"baked":
			print("[%d/%d] %s %s  |  variant %.1fms  trace %.1fms  stylize %.1fms  save %.1fms  total %.1fms  saved=%d  status=%s" % [
				completed,
				total,
				tile_id,
				variant_key,
				variant_elapsed_ms,
				float(progress.get("trace_elapsed_ms", 0.0)),
				float(progress.get("stylize_elapsed_ms", 0.0)),
				float(progress.get("save_elapsed_ms", 0.0)),
				elapsed_ms,
				int(progress.get("saved_entries", 0)),
				String(progress.get("status", "unknown")),
			])
			_print_trace_detail_profile(progress.get("trace_detail_profile", {}))
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
			var profile: Dictionary = progress.get("profile", {})
			if not profile.is_empty():
				print("Batch profile: request_build=%.1fms  mesh=%.1fms  trace=%.1fms  stylize=%.1fms  save=%.1fms" % [
					float(profile.get("request_build_elapsed_ms", 0.0)),
					float(profile.get("mesh_build_elapsed_ms", 0.0)),
					float(profile.get("trace_elapsed_ms", 0.0)),
					float(profile.get("stylize_elapsed_ms", 0.0)),
					float(profile.get("save_elapsed_ms", 0.0)),
				])
				_print_trace_detail_profile(profile.get("trace_detail_profile", {}))


func _tile_ids_to_text(tile_ids: Array) -> String:
	var names: PackedStringArray = []
	for tile_id in tile_ids:
		names.append(String(tile_id))
	return ",".join(names)


func _print_trace_detail_profile(profile: Dictionary) -> void:
	if profile.is_empty():
		return
	print("Trace detail: view %.1fms  primary %.1fms  secondary %.1fms  spectral %.1fms  surface %.1fms  volume %.1fms  alpha %.1fms  encode %.1fms" % [
		float(profile.get("trace_view_elapsed_ms", 0.0)),
		float(profile.get("primary_intersect_elapsed_ms", 0.0)),
		float(profile.get("secondary_intersect_elapsed_ms", 0.0)),
		float(profile.get("spectral_trace_elapsed_ms", 0.0)),
		float(profile.get("surface_lighting_elapsed_ms", 0.0)),
		float(profile.get("volume_sampling_elapsed_ms", 0.0)),
		float(profile.get("alpha_cleanup_elapsed_ms", 0.0)),
		float(profile.get("encode_elapsed_ms", 0.0)),
	])
	print("Trace counts: primary=%d  secondary=%d  spectral=%d  surface=%d  volume=%d  reused_primary=%d  threads=%d" % [
		int(profile.get("primary_intersect_count", 0)),
		int(profile.get("secondary_intersect_count", 0)),
		int(profile.get("spectral_trace_count", 0)),
		int(profile.get("surface_lighting_count", 0)),
		int(profile.get("volume_sampling_count", 0)),
		int(profile.get("primary_hit_reuse_count", 0)),
		int(profile.get("thread_count", 0)),
	])


func _write_status(payload: Dictionary) -> void:
	if _status_path.is_empty():
		return
	var resolved_status_path := _resolve_status_path(_status_path)
	var status_dir := resolved_status_path.get_base_dir()
	if not status_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(status_dir)
	var merged := _status_context.duplicate(true)
	for key in payload.keys():
		merged[key] = payload[key]
	merged["updated_at_unix"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(resolved_status_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(merged, "\t"))


func _resolve_status_path(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path(path)
