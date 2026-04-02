class_name OfflineGemBakeJob
extends RefCounted

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")
const GemOpticsTracerScript = preload("res://core/visuals/gem_optics_tracer.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")

const DEFAULT_OUTPUT_ROOT := GemTracedBakeContractScript.DEFAULT_OUTPUT_ROOT
const DEFAULT_MANIFEST_NAME := GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME

signal progress_updated(progress: Dictionary)


func run_batch(
	registry: Node,
	tile_ids: Array,
	cell_size: Vector2i,
	options: Dictionary = {},
) -> Dictionary:
	if registry == null or cell_size.x <= 0 or cell_size.y <= 0:
		return {"status": "invalid_arguments", "entries": []}

	var output_root := String(options.get("output_root", DEFAULT_OUTPUT_ROOT))
	var draw_size: Vector2i = options.get("draw_size", cell_size)
	var sample_count := clampi(
		int(options.get("sample_count", 1)),
		1,
		GemOpticsTracerScript.max_supported_sample_count()
	)
	var tracer = GemOpticsTracerScript.new()
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var filtered_requests := _build_filtered_requests(registry, tile_ids, cell_size, draw_size, sample_count, options)
	var start_usec := Time.get_ticks_usec()

	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})

	_ensure_dir(output_root)
	for request_index in filtered_requests.size():
		var traced_request: Dictionary = filtered_requests[request_index]
		var tile_id: StringName = traced_request.get("tile_id", &"")
		var visual: GemVisualResource = traced_request.get("visual", null)
		var mesh_resource: GemMeshResource = traced_request.get("mesh_resource", null)
		var request_start_usec := Time.get_ticks_usec()
		_emit_progress({
			"stage": "baking",
			"completed": request_index,
			"total": filtered_requests.size(),
			"progress": _compute_progress_fraction(request_index, filtered_requests.size()),
			"tile_id": tile_id,
			"variant_type": traced_request.get("variant_type", &""),
			"variant_key": traced_request.get("variant_key", &""),
			"elapsed_ms": (request_start_usec - start_usec) / 1000.0,
		})
		var image := tracer.trace_to_image(mesh_resource, visual, traced_request)
		if image == null:
			_emit_progress({
				"stage": "skipped",
				"completed": request_index + 1,
				"total": filtered_requests.size(),
				"progress": _compute_progress_fraction(request_index + 1, filtered_requests.size()),
				"tile_id": tile_id,
				"variant_type": traced_request.get("variant_type", &""),
				"variant_key": traced_request.get("variant_key", &""),
				"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
				"variant_elapsed_ms": (Time.get_ticks_usec() - request_start_usec) / 1000.0,
				"status": "trace_failed",
			})
			continue
		image = GemBakeStylizerScript.apply(image, visual, traced_request)
		var variant_key := String(traced_request.get("variant_key", ""))
		var texture_path := GemTracedBakeContractScript.build_texture_path(output_root, String(tile_id), variant_key)
		_ensure_dir(_join_path(output_root, String(tile_id)))
		var save_err := image.save_png(ProjectSettings.globalize_path(texture_path))
		if save_err == OK:
			var entry := GemTracedBakeContractScript.build_manifest_entry(
				visual,
				traced_request,
				texture_path,
				cell_size,
				draw_size,
				sample_count
			)
			entries.append(entry)
			per_tile_counts[tile_id] = int(per_tile_counts.get(tile_id, 0)) + 1
		_emit_progress({
			"stage": "baked",
			"completed": request_index + 1,
			"total": filtered_requests.size(),
			"progress": _compute_progress_fraction(request_index + 1, filtered_requests.size()),
			"tile_id": tile_id,
			"variant_type": traced_request.get("variant_type", &""),
			"variant_key": traced_request.get("variant_key", &""),
			"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
			"variant_elapsed_ms": (Time.get_ticks_usec() - request_start_usec) / 1000.0,
			"status": "ok" if save_err == OK else "save_failed",
			"saved_entries": entries.size(),
		})

	return _finalize_batch_result(output_root, cell_size, draw_size, sample_count, filtered_requests, entries, per_tile_counts, start_usec)


func run_batch_async(
	host: Node,
	registry: Node,
	tile_ids: Array,
	cell_size: Vector2i,
	options: Dictionary = {},
) -> Dictionary:
	return await _run_batch_internal(registry, tile_ids, cell_size, options, host)


func _run_batch_internal(
	registry: Node,
	tile_ids: Array,
	cell_size: Vector2i,
	options: Dictionary,
	yield_host: Node,
) -> Dictionary:
	if registry == null or cell_size.x <= 0 or cell_size.y <= 0:
		return {"status": "invalid_arguments", "entries": []}

	var output_root := String(options.get("output_root", DEFAULT_OUTPUT_ROOT))
	var draw_size: Vector2i = options.get("draw_size", cell_size)
	var sample_count := clampi(
		int(options.get("sample_count", 1)),
		1,
		GemOpticsTracerScript.max_supported_sample_count()
	)
	var tracer = GemOpticsTracerScript.new()
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var filtered_requests := _build_filtered_requests(registry, tile_ids, cell_size, draw_size, sample_count, options)
	var start_usec := Time.get_ticks_usec()

	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})

	_ensure_dir(output_root)
	for request_index in filtered_requests.size():
		var traced_request: Dictionary = filtered_requests[request_index]
		var tile_id: StringName = traced_request.get("tile_id", &"")
		var visual: GemVisualResource = traced_request.get("visual", null)
		var mesh_resource: GemMeshResource = traced_request.get("mesh_resource", null)
		var request_start_usec := Time.get_ticks_usec()
		_emit_progress({
			"stage": "baking",
			"completed": request_index,
			"total": filtered_requests.size(),
			"progress": _compute_progress_fraction(request_index, filtered_requests.size()),
			"tile_id": tile_id,
			"variant_type": traced_request.get("variant_type", &""),
			"variant_key": traced_request.get("variant_key", &""),
			"elapsed_ms": (request_start_usec - start_usec) / 1000.0,
		})
		var image := tracer.trace_to_image(mesh_resource, visual, traced_request)
		if image == null:
			_emit_progress({
				"stage": "skipped",
				"completed": request_index + 1,
				"total": filtered_requests.size(),
				"progress": _compute_progress_fraction(request_index + 1, filtered_requests.size()),
				"tile_id": tile_id,
				"variant_type": traced_request.get("variant_type", &""),
				"variant_key": traced_request.get("variant_key", &""),
				"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
				"variant_elapsed_ms": (Time.get_ticks_usec() - request_start_usec) / 1000.0,
				"status": "trace_failed",
			})
			if yield_host != null and yield_host.get_tree() != null:
				await yield_host.get_tree().process_frame
			continue
		image = GemBakeStylizerScript.apply(image, visual, traced_request)
		var variant_key := String(traced_request.get("variant_key", ""))
		var texture_path := GemTracedBakeContractScript.build_texture_path(output_root, String(tile_id), variant_key)
		_ensure_dir(_join_path(output_root, String(tile_id)))
		var save_err := image.save_png(ProjectSettings.globalize_path(texture_path))
		if save_err == OK:
			var entry := GemTracedBakeContractScript.build_manifest_entry(
				visual,
				traced_request,
				texture_path,
				cell_size,
				draw_size,
				sample_count
			)
			entries.append(entry)
			per_tile_counts[tile_id] = int(per_tile_counts.get(tile_id, 0)) + 1
		_emit_progress({
			"stage": "baked",
			"completed": request_index + 1,
			"total": filtered_requests.size(),
			"progress": _compute_progress_fraction(request_index + 1, filtered_requests.size()),
			"tile_id": tile_id,
			"variant_type": traced_request.get("variant_type", &""),
			"variant_key": traced_request.get("variant_key", &""),
			"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
			"variant_elapsed_ms": (Time.get_ticks_usec() - request_start_usec) / 1000.0,
			"status": "ok" if save_err == OK else "save_failed",
			"saved_entries": entries.size(),
		})
		if yield_host != null and yield_host.get_tree() != null:
			await yield_host.get_tree().process_frame

	return _finalize_batch_result(output_root, cell_size, draw_size, sample_count, filtered_requests, entries, per_tile_counts, start_usec)


func _request_matches_filters(request: Dictionary, options: Dictionary) -> bool:
	var lighting_filters: Array = options.get("lighting_bins", [])
	var rotation_filters: Array = options.get("rotation_bins", [])
	var variant_type: StringName = request.get("variant_type", &"")
	if variant_type == &"lighting" and not lighting_filters.is_empty():
		return lighting_filters.has(request.get("lighting_bin", Vector2i(-1, -1)))
	if variant_type == &"rotation" and not rotation_filters.is_empty():
		return rotation_filters.has(request.get("rotation_bin", -1))
	return true


func _ensure_dir(path: String) -> void:
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(global_path)


func _join_path(base: String, tail: String) -> String:
	if base.ends_with("/"):
		return "%s%s" % [base, tail]
	return "%s/%s" % [base, tail]


func _compute_progress_fraction(completed: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return clampf(float(completed) / float(total), 0.0, 1.0)


func _emit_progress(progress: Dictionary) -> void:
	progress_updated.emit(progress)


func _build_filtered_requests(
	registry: Node,
	tile_ids: Array,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
	options: Dictionary,
) -> Array:
	var filtered_requests: Array[Dictionary] = []
	var mesh_cache: Dictionary = {}
	for tile_id in tile_ids:
		var visual: GemVisualResource = registry.get_visual(tile_id)
		if visual == null:
			continue
		var rotation_variant_options := {}
		if options.has("rotation_axis_steps"):
			rotation_variant_options["rotation_axis_steps"] = int(options.get("rotation_axis_steps", 0))
		if options.has("rotation_step_degrees"):
			rotation_variant_options["rotation_step_degrees"] = float(options.get("rotation_step_degrees", 0.0))
		if options.has("rotation_axes"):
			rotation_variant_options["rotation_axes"] = options.get("rotation_axes", [])
		var requests: Array = registry.build_gameplay_bake_requests_for_tile(
			tile_id,
			draw_size,
			cell_size,
			rotation_variant_options
		)
		for request in requests:
			if not _request_matches_filters(request, options):
				continue
			var enriched_request: Dictionary = request.duplicate(true)
			var mesh_cache_key := _resolve_request_mesh_cache_key(visual, enriched_request)
			var mesh_resource = mesh_cache.get(mesh_cache_key, null)
			if mesh_resource == null:
				mesh_resource = _build_request_mesh(visual, enriched_request)
				if mesh_resource == null:
					continue
				mesh_cache[mesh_cache_key] = mesh_resource
			enriched_request["sample_count"] = sample_count
			if options.has("thread_count"):
				enriched_request["thread_count"] = int(options.get("thread_count", 1))
			enriched_request["mesh_resource"] = mesh_resource
			enriched_request["visual"] = visual
			enriched_request["mesh_includes_cut_rotation"] = _request_uses_variant_mesh(visual, enriched_request)
			filtered_requests.append(enriched_request)
	return filtered_requests


func _build_request_mesh(visual: GemVisualResource, request: Dictionary):
	if _request_uses_variant_mesh(visual, request):
		var request_cut: GemCutResource = request.get("cut", null)
		if request_cut != null:
			return GemMeshGeneratorsScript.generate_from_cut(request_cut)
	return GemMeshGeneratorsScript.generate(visual.cut_id)


func _resolve_request_mesh_cache_key(visual: GemVisualResource, request: Dictionary) -> String:
	if _request_uses_variant_mesh(visual, request):
		return "variant:%s" % String(request.get("cut_key_override", request.get("variant_key", visual.cut_id)))
	return "canonical:%s" % String(visual.cut_id)


func _request_uses_variant_mesh(visual: GemVisualResource, request: Dictionary) -> bool:
	if visual == null:
		return false
	var request_cut: GemCutResource = request.get("cut", null)
	if request_cut == null:
		return false
	if request.get("variant_type", &"") == &"rotation":
		return true
	return visual.cut_id != &"classic_round" and visual.cut_id != &"old_european_round"


func _finalize_batch_result(
	output_root: String,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
	filtered_requests: Array,
	entries: Array,
	per_tile_counts: Dictionary,
	start_usec: int,
) -> Dictionary:
	var merged_entries := _merge_manifest_entries(_join_path(output_root, DEFAULT_MANIFEST_NAME), entries)
	var merged_tile_counts := _count_entries_by_tile(merged_entries)
	var manifest := {
		"backend_id": &"offline_traced",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"output_root": output_root,
		"cell_size": cell_size,
		"draw_size": draw_size,
		"sample_count": sample_count,
		"tile_counts": merged_tile_counts,
		"entries": merged_entries,
	}
	var manifest_path := _join_path(output_root, DEFAULT_MANIFEST_NAME)
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_emit_progress({
			"stage": "error",
			"completed": entries.size(),
			"total": filtered_requests.size(),
			"progress": _compute_progress_fraction(filtered_requests.size(), filtered_requests.size()),
			"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
			"status": "manifest_write_failed",
		})
		return {
			"status": "manifest_write_failed",
			"manifest_path": manifest_path,
			"entries": merged_entries,
		}
	file.store_string(JSON.stringify(manifest, "\t"))
	_emit_progress({
		"stage": "complete",
		"completed": filtered_requests.size(),
		"total": filtered_requests.size(),
		"progress": 1.0,
		"elapsed_ms": (Time.get_ticks_usec() - start_usec) / 1000.0,
		"saved_entries": entries.size(),
		"manifest_path": manifest_path,
	})
	return {
		"status": "ok",
		"manifest_path": manifest_path,
		"entry_count": merged_entries.size(),
		"entries": merged_entries,
	}


func _merge_manifest_entries(manifest_path: String, new_entries: Array) -> Array:
	var merged_by_key: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var existing_file := FileAccess.open(manifest_path, FileAccess.READ)
		if existing_file != null:
			var parsed = JSON.parse_string(existing_file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and GemTracedBakeContractScript.manifest_matches_current(parsed):
				var existing_entries: Array = parsed.get("entries", [])
				for raw_entry in existing_entries:
					if typeof(raw_entry) != TYPE_DICTIONARY:
						continue
					var entry: Dictionary = raw_entry
					var variant_key := String(entry.get("variant_key", ""))
					if variant_key.is_empty():
						continue
					merged_by_key[variant_key] = entry.duplicate(true)
	for raw_entry in new_entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var variant_key := String(entry.get("variant_key", ""))
		if variant_key.is_empty():
			continue
		merged_by_key[variant_key] = entry.duplicate(true)
	var merged_entries: Array[Dictionary] = []
	var variant_keys := merged_by_key.keys()
	variant_keys.sort()
	for variant_key in variant_keys:
		merged_entries.append(merged_by_key[variant_key])
	return merged_entries


func _count_entries_by_tile(entries: Array) -> Dictionary:
	var counts: Dictionary = {}
	for raw_entry in entries:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var tile_id := StringName(entry.get("tile_id", &""))
		if tile_id == &"":
			continue
		counts[tile_id] = int(counts.get(tile_id, 0)) + 1
	return counts
