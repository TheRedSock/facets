extends SceneTree

const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")

const DEFAULT_OUTPUT_ROOT := GemTracedBakeContractScript.DEFAULT_OUTPUT_ROOT
const DEFAULT_MANIFEST_NAME := GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		push_error("Manifest rebuild requires GemVisualRegistry autoload")
		quit(1)
		return

	var args := _parse_args(OS.get_cmdline_user_args())
	var size := maxi(int(args.get("size", 112)), 16)
	var draw_size_value := maxi(int(args.get("draw_size", size)), 16)
	var output_root := String(args.get("output", DEFAULT_OUTPUT_ROOT))
	var tile_ids := _resolve_tile_ids(args.get("gems", "all"), registry)
	if tile_ids.is_empty():
		push_error("No matching gem visuals found for manifest rebuild")
		quit(1)
		return

	var cell_size := Vector2i(size, size)
	var draw_size := Vector2i(draw_size_value, draw_size_value)
	var rotation_variant_options := {}
	var rotation_axes := _parse_rotation_axes(String(args.get("rotation_axes", "")))
	if not rotation_axes.is_empty():
		rotation_variant_options["rotation_axes"] = rotation_axes
	var rotation_axis_steps := maxi(int(args.get("rotation_axis_steps", 0)), 0)
	if rotation_axis_steps > 0:
		rotation_variant_options["rotation_axis_steps"] = rotation_axis_steps
	var rotation_step_degrees := float(args.get("rotation_step_degrees", 0.0))
	if rotation_step_degrees > 0.0:
		rotation_variant_options["rotation_step_degrees"] = rotation_step_degrees
	# Showroom yaw/pitch sweep support (matches run_offline_gem_bake flags).
	var showroom_axis_steps := maxi(int(args.get("showroom_axis_steps", 0)), 0)
	if showroom_axis_steps > 0:
		rotation_variant_options["showroom_axis_steps"] = clampi(showroom_axis_steps, 1, 360)
	var showroom_axes_raw := String(args.get("showroom_axes", "")).strip_edges()
	if not showroom_axes_raw.is_empty():
		rotation_variant_options["showroom_axes"] = showroom_axes_raw.replace(";", ",").split(",", false)
	# If the user is rebuilding a showroom-only manifest, skip lighting+rotation
	# suite requests so we don't try to register entries that were never baked.
	if bool(args.get("skip_lighting", false)):
		rotation_variant_options["lighting_grid_size"] = Vector2i.ZERO
	if bool(args.get("skip_rotations", false)):
		rotation_variant_options["rotation_axis_steps"] = 0
		rotation_variant_options["rotation_base_view_count"] = 0
	var entries: Array[Dictionary] = []
	var tile_counts: Dictionary = {}
	var all_requests: Array = []
	for tile_id in tile_ids:
		var visual: GemVisualResource = registry.get_visual(tile_id)
		if visual == null:
			continue
		var requests: Array = registry.build_gameplay_bake_requests_for_tile(
			tile_id,
			draw_size,
			cell_size,
			rotation_variant_options
		)
		for request in requests:
			all_requests.append(request)
			var variant_key := String(request.get("variant_key", ""))
			if variant_key.is_empty():
				continue
			# Try each supported image format to find existing baked files.
			var texture_path := ""
			var found_format := GemTracedBakeContractScript.DEFAULT_IMAGE_FORMAT
			for fmt in GemTracedBakeContractScript.SUPPORTED_IMAGE_FORMATS:
				var candidate := GemTracedBakeContractScript.build_texture_path(output_root, String(tile_id), variant_key, fmt)
				if FileAccess.file_exists(candidate):
					texture_path = candidate
					found_format = fmt
					break
			if texture_path.is_empty():
				continue
			request["image_format"] = found_format
			entries.append(GemTracedBakeContractScript.build_manifest_entry(
				visual,
				request,
				texture_path,
				cell_size,
				draw_size,
				int(args.get("samples", 1))
			))
			tile_counts[tile_id] = int(tile_counts.get(tile_id, 0)) + 1

	var base_vs := GemTracedBakeContractScript.build_manifest_variant_settings(rotation_variant_options)
	var rot_layers := GemTracedBakeContractScript.infer_rotation_layer_count_from_requests(all_requests)
	var manifest_vs := GemTracedBakeContractScript.merge_atlas_metadata_into_variant_settings(
		base_vs,
		rot_layers
	)
	var manifest := {
		"backend_id": &"offline_traced",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"output_root": output_root,
		"cell_size": cell_size,
		"draw_size": draw_size,
		"sample_count": int(args.get("samples", 1)),
		"variant_settings": manifest_vs,
		"tile_counts": tile_counts,
		"entries": entries,
	}
	var manifest_path := _join_path(output_root, DEFAULT_MANIFEST_NAME)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write manifest: %s" % manifest_path)
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	print("Rebuilt traced manifest")
	print("Manifest: %s" % manifest_path)
	print("Entries: %d" % entries.size())
	quit(0)


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


func _resolve_tile_ids(raw_value: String, registry: Node) -> Array:
	var normalized := raw_value.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "all":
		return registry.get_visual_ids()
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

func _join_path(base: String, tail: String) -> String:
	if base.ends_with("/"):
		return "%s%s" % [base, tail]
	return "%s/%s" % [base, tail]
