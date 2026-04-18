extends RefCounted

const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")
const OfflineGemBakeJobScript = preload("res://tools/offline_gem_bake_job.gd")


static func load_profile_file(path: String) -> Dictionary:
	var trimmed := path.strip_edges()
	if trimmed.is_empty():
		return {}
	var file := FileAccess.open(trimmed, FileAccess.READ)
	if file == null:
		push_error("Production bake profile: could not open %s" % trimmed)
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Production bake profile: expected JSON object in %s" % trimmed)
		return {}
	return parsed


static func resolve_gems_list(gems_value, registry: Node) -> Array:
	if registry == null:
		return []
	if gems_value is Array:
		var out: Array = []
		var seen: Dictionary = {}
		for raw in gems_value:
			var tid := StringName(String(raw).strip_edges())
			if tid == &"" or seen.has(tid):
				continue
			seen[tid] = true
			out.append(tid)
		return out
	var normalized := String(gems_value).strip_edges().to_lower()
	if normalized.is_empty() or normalized == "all":
		return _filter_gameplay_gems(registry.get_visual_ids(), registry)
	var tile_ids: Array = []
	var seen2: Dictionary = {}
	for token in String(gems_value).split(",", false):
		var t := StringName(token.strip_edges())
		if t == &"" or seen2.has(t):
			continue
		seen2[t] = true
		tile_ids.append(t)
	return tile_ids


## Filters a list of visual IDs to only those with a corresponding tile
## definition in TileRegistry.  This excludes material studies, debug visuals,
## and other non-gameplay gems that have a GemVisualResource but no tile .tres.
static func _filter_gameplay_gems(visual_ids: Array, registry: Node) -> Array:
	var tile_registry: Node = null
	if registry.get_tree() != null and registry.get_tree().root != null:
		tile_registry = registry.get_tree().root.get_node_or_null("TileRegistry")
	if tile_registry == null or not tile_registry.has_definitions():
		# Cannot filter without TileRegistry; return unfiltered.
		return visual_ids
	var filtered: Array = []
	var skipped: Array = []
	for visual_id in visual_ids:
		if tile_registry.get_definition(visual_id) != null:
			filtered.append(visual_id)
		else:
			skipped.append(visual_id)
	if not skipped.is_empty():
		print("Production bake: skipping %d non-gameplay visual(s): %s" % [
			skipped.size(),
			", ".join(skipped.map(func(s): return String(s)))
		])
	return filtered


## Maps profile JSON (version-controlled spec) to OfflineGemBakeJob `options`.
static func profile_to_bake_options(profile: Dictionary, profile_res_path: String = "") -> Dictionary:
	var opts: Dictionary = {}
	if profile.has("output_root"):
		opts["output_root"] = String(profile.get("output_root"))
	var cell := maxi(int(profile.get("cell_size", 112)), 16)
	var draw := maxi(int(profile.get("draw_size", cell)), 16)
	opts["draw_size"] = Vector2i(draw, draw)
	opts["sample_count"] = clampi(
		maxi(int(profile.get("sample_count", 1)), 1),
		1,
		OfflineGemBakeJobScript.max_supported_sample_count()
	)
	var spp := clampi(int(profile.get("samples_per_pixel", GemTracedBakeContractScript.DEFAULT_SAMPLES_PER_PIXEL)), 16, 512)
	opts["samples_per_pixel"] = spp
	if profile.has("thread_count"):
		opts["thread_count"] = maxi(int(profile.get("thread_count", 0)), 0)
	if profile.has("variant_workers"):
		opts["variant_worker_count"] = maxi(int(profile.get("variant_workers", 0)), 0)
	if bool(profile.get("skip_lighting", false)):
		opts["skip_lighting"] = true
		opts["lighting_grid_size"] = Vector2i.ZERO
	else:
		var preset := String(profile.get("lighting_grid_preset", "quality")).strip_edges().to_lower()
		if not preset.is_empty():
			opts["lighting_grid_preset"] = StringName(preset)
	if bool(profile.get("skip_rotations", false)):
		opts["skip_rotations"] = true
		opts["rotation_base_view_count"] = 0
		opts["rotation_axis_steps"] = 0
	else:
		opts["rotation_base_view_count"] = maxi(int(profile.get("rotation_base_view_count", 6)), 0)
		opts["rotation_axis_steps"] = maxi(int(profile.get("rotation_axis_steps", 0)), 0)
		opts["rotation_step_degrees"] = maxf(float(profile.get("rotation_step_degrees", 18.0)), 1.0)
		var axes_raw = profile.get("rotation_axes", [])
		if axes_raw is String:
			axes_raw = String(axes_raw).replace(";", ",").split(",", false)
		if axes_raw is Array and not axes_raw.is_empty():
			var axes: Array[StringName] = []
			var seen: Dictionary = {}
			for raw_axis in axes_raw:
				var axis := StringName(String(raw_axis).strip_edges().to_lower())
				if axis == &"" or seen.has(axis):
					continue
				if not GemTracedBakeContractScript.SUPPORTED_ROTATION_AXES.has(axis):
					continue
				seen[axis] = true
				axes.append(axis)
			if not axes.is_empty():
				opts["rotation_axes"] = axes
	if bool(profile.get("skip_stylize", false)):
		opts["skip_stylize"] = true
	if bool(profile.get("trace_profile", false)):
		opts["trace_profile"] = true
	var image_format := GemTracedBakeContractScript.normalize_image_format(
		profile.get("format", GemTracedBakeContractScript.DEFAULT_IMAGE_FORMAT)
	)
	opts["image_format"] = image_format
	var base_quality := float(profile.get("base_quality", 92.0))
	if base_quality > 1.0:
		base_quality = base_quality / 100.0
	opts["webp_quality"] = clampf(base_quality, 0.5, 1.0)
	var pid := String(profile.get("profile_id", "")).strip_edges()
	if not pid.is_empty():
		opts["profile_id"] = pid
	if not profile_res_path.is_empty():
		opts["bake_profile_path"] = profile_res_path
	if profile.has("vram_compress"):
		opts["vram_compress"] = bool(profile.get("vram_compress"))
	if profile.has("atlas_output"):
		opts["atlas_output"] = bool(profile.get("atlas_output"))
	var default_env := String(profile.get("default_environment", "")).strip_edges()
	if not default_env.is_empty():
		opts["default_environment"] = default_env
	if profile.has("seed"):
		opts["seed"] = int(profile.get("seed", 42))
	return opts
