class_name OfflineGemBakeJob
extends RefCounted

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemBakeStylizerScript = preload("res://core/visuals/gem_bake_stylizer.gd")
const GemTracedBakeContractScript = preload("res://core/visuals/gem_traced_bake_contract.gd")

const DEFAULT_OUTPUT_ROOT := GemTracedBakeContractScript.DEFAULT_OUTPUT_ROOT
const DEFAULT_MANIFEST_NAME := GemTracedBakeContractScript.DEFAULT_MANIFEST_NAME
const MAX_AUTO_VARIANT_WORKERS := 4

signal progress_updated(progress: Dictionary)


static func is_native_trace_kernel_available() -> bool:
	return ClassDB.class_exists(&"GemTraceKernel")


static func get_trace_backend_id() -> StringName:
	if is_native_trace_kernel_available():
		return &"native_cpp"
	push_error("GemTraceKernel native extension is required but not available. Build the extension: cd native && python -m SCons platform=windows target=template_debug")
	return &"unavailable"


static func create_tracer():
	if is_native_trace_kernel_available():
		var kernel = ClassDB.instantiate(&"GemTraceKernel")
		if kernel != null:
			return kernel
	push_error("GemTraceKernel native extension is required but not available. The GDScript fallback tracer has been deprecated.")
	return null


## Enrich one trace request like batch bakes (environment, mesh, samples, stylize, etc.).
## Used by the gem designer preview so it matches showroom/offline normalization.
func build_designer_enriched_request(
	base_request: Dictionary,
	visual: GemVisualResource,
	mesh_resource: GemMeshResource,
	sample_count: int,
	options: Dictionary,
) -> Dictionary:
	var req := base_request.duplicate(true)
	req["visual"] = visual
	req["mesh_resource"] = mesh_resource
	var arr: Array = [req]
	var enriched := _enrich_request_list(arr, sample_count, options)
	if enriched.is_empty():
		return req
	return enriched[0]


## Maximum MSAA sample count supported by the trace kernel (5-point quincunx pattern).
static func max_supported_sample_count() -> int:
	return 5


## Thread count heuristic for traced bake jobs. Inlined from the former
## GemOpticsTracer.resolve_trace_thread_count() to remove the dependency.
const _MIN_ROWS_PER_TRACE_THREAD := 8
const _MIN_PIXELS_PER_TRACE_THREAD := 6144
const _MIN_WORK_UNITS_PER_TRACE_THREAD := 20000

static func resolve_trace_thread_count(
	request: Dictionary,
	target_size: Vector2i,
	sample_count: int,
	spectral_sample_count: int,
) -> int:
	var thread_budget := clampi(
		int(request.get("thread_budget", request.get("thread_count", OS.get_processor_count() - 1))),
		1,
		32
	)
	if request.has("thread_count"):
		return maxi(mini(thread_budget, maxi(target_size.y, 1)), 1)
	var pixel_count := maxi(target_size.x * target_size.y, 1)
	var row_limit := maxi(target_size.y / _MIN_ROWS_PER_TRACE_THREAD, 1)
	var pixel_limit := maxi(pixel_count / _MIN_PIXELS_PER_TRACE_THREAD, 1)
	var work_units := pixel_count * maxi(sample_count, 1) * maxi(spectral_sample_count, 1)
	var work_limit := maxi(work_units / _MIN_WORK_UNITS_PER_TRACE_THREAD, 1)
	return maxi(mini(mini(thread_budget, row_limit), mini(pixel_limit, work_limit)), 1)


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
		max_supported_sample_count()
	)
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	var request_build_start_usec := Time.get_ticks_usec()
	var filtered_requests := _build_filtered_requests(
		registry,
		tile_ids,
		cell_size,
		draw_size,
		sample_count,
		options
	)
	var profiling := _make_batch_profile((Time.get_ticks_usec() - request_build_start_usec) / 1000.0)
	var start_usec := Time.get_ticks_usec()
	var parallel_plan := _resolve_parallel_execution_plan(filtered_requests.size(), options)
	_apply_parallel_execution_plan(filtered_requests, parallel_plan)
	_record_parallel_execution_plan(profiling, parallel_plan)

	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})

	_ensure_dir(output_root)
	if bool(parallel_plan.get("pipeline_enabled", false)):
		var pending_index := 0
		var active_workers: Array[Dictionary] = []
		var worker_count := int(parallel_plan.get("variant_worker_count", 1))
		while pending_index < filtered_requests.size() and active_workers.size() < worker_count:
			active_workers.append(_launch_trace_worker(
				filtered_requests[pending_index],
				pending_index,
				filtered_requests.size(),
				start_usec,
				profiling
			))
			pending_index += 1
		while not active_workers.is_empty():
			var worker: Dictionary = active_workers.pop_front()
			var traced_request: Dictionary = worker.get("request", {})
			var trace_result: Dictionary = {}
			var thread: Thread = worker.get("thread", null)
			if thread != null:
				trace_result = thread.wait_to_finish()
			else:
				trace_result = _trace_request_worker(traced_request)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				int(worker.get("request_index", 0)),
				int(worker.get("request_start_usec", Time.get_ticks_usec())),
				trace_result
			)
			if pending_index < filtered_requests.size():
				active_workers.append(_launch_trace_worker(
					filtered_requests[pending_index],
					pending_index,
					filtered_requests.size(),
					start_usec,
					profiling
				))
				pending_index += 1
	else:
		for request_index in filtered_requests.size():
			var traced_request: Dictionary = filtered_requests[request_index]
			var request_start_usec := _emit_baking_start(
				traced_request,
				request_index,
				filtered_requests.size(),
				start_usec,
				profiling
			)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				request_index,
				request_start_usec,
				_trace_request_worker(traced_request)
			)

	return _finalize_batch_result(
		output_root,
		cell_size,
		draw_size,
		sample_count,
		filtered_requests,
		entries,
		per_tile_counts,
		start_usec,
		variant_settings,
		profiling,
		options
	)


## Run traces for pre-built request dicts (e.g. designer explicit / Fibonacci sphere). Each must include visual + cut_model.
func run_explicit_request_batch(
	source_requests: Array,
	cell_size: Vector2i,
	options: Dictionary = {},
) -> Dictionary:
	if cell_size.x <= 0 or cell_size.y <= 0:
		return {"status": "invalid_arguments", "entries": []}
	var output_root := String(options.get("output_root", DEFAULT_OUTPUT_ROOT))
	var draw_size: Vector2i = options.get("draw_size", cell_size)
	var sample_count := clampi(
		int(options.get("sample_count", 1)),
		1,
		max_supported_sample_count()
	)
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	var filtered_requests := _enrich_request_list(source_requests, sample_count, options)
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var profiling := _make_batch_profile(0.0)
	var start_usec := Time.get_ticks_usec()
	var parallel_plan := _resolve_parallel_execution_plan(filtered_requests.size(), options)
	_apply_parallel_execution_plan(filtered_requests, parallel_plan)
	_record_parallel_execution_plan(profiling, parallel_plan)
	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})
	_ensure_dir(output_root)
	if bool(parallel_plan.get("pipeline_enabled", false)):
		var pending_index := 0
		var active_workers: Array[Dictionary] = []
		var worker_count := int(parallel_plan.get("variant_worker_count", 1))
		while pending_index < filtered_requests.size() and active_workers.size() < worker_count:
			active_workers.append(_launch_trace_worker(
				filtered_requests[pending_index],
				pending_index,
				filtered_requests.size(),
				start_usec,
				profiling
			))
			pending_index += 1
		while not active_workers.is_empty():
			var worker: Dictionary = active_workers.pop_front()
			var traced_request: Dictionary = worker.get("request", {})
			var trace_result: Dictionary = {}
			var thread: Thread = worker.get("thread", null)
			if thread != null:
				trace_result = thread.wait_to_finish()
			else:
				trace_result = _trace_request_worker(traced_request)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				int(worker.get("request_index", 0)),
				int(worker.get("request_start_usec", Time.get_ticks_usec())),
				trace_result
			)
			if pending_index < filtered_requests.size():
				active_workers.append(_launch_trace_worker(
					filtered_requests[pending_index],
					pending_index,
					filtered_requests.size(),
					start_usec,
					profiling
				))
				pending_index += 1
	else:
		for request_index in filtered_requests.size():
			var traced_request: Dictionary = filtered_requests[request_index]
			var request_start_usec := _emit_baking_start(
				traced_request,
				request_index,
				filtered_requests.size(),
				start_usec,
				profiling
			)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				request_index,
				request_start_usec,
				_trace_request_worker(traced_request)
			)
	return _finalize_batch_result(
		output_root,
		cell_size,
		draw_size,
		sample_count,
		filtered_requests,
		entries,
		per_tile_counts,
		start_usec,
		variant_settings,
		profiling,
		options
	)


func run_explicit_request_batch_async(
	host: Node,
	source_requests: Array,
	cell_size: Vector2i,
	options: Dictionary = {},
) -> Dictionary:
	if cell_size.x <= 0 or cell_size.y <= 0:
		return {"status": "invalid_arguments", "entries": []}
	var output_root := String(options.get("output_root", DEFAULT_OUTPUT_ROOT))
	var draw_size: Vector2i = options.get("draw_size", cell_size)
	var sample_count := clampi(
		int(options.get("sample_count", 1)),
		1,
		max_supported_sample_count()
	)
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	var filtered_requests := _enrich_request_list(source_requests, sample_count, options)
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var profiling := _make_batch_profile(0.0)
	var start_usec := Time.get_ticks_usec()
	var parallel_plan := _resolve_parallel_execution_plan(filtered_requests.size(), options)
	_apply_parallel_execution_plan(filtered_requests, parallel_plan)
	_record_parallel_execution_plan(profiling, parallel_plan)
	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})
	_ensure_dir(output_root)
	if bool(parallel_plan.get("pipeline_enabled", false)):
		var pending_index := 0
		var active_workers: Array[Dictionary] = []
		var worker_count := int(parallel_plan.get("variant_worker_count", 1))
		while pending_index < filtered_requests.size() and active_workers.size() < worker_count:
			active_workers.append(_launch_trace_worker(
				filtered_requests[pending_index],
				pending_index,
				filtered_requests.size(),
				start_usec,
				profiling
			))
			pending_index += 1
		while not active_workers.is_empty():
			var worker: Dictionary = active_workers.pop_front()
			var traced_request: Dictionary = worker.get("request", {})
			var trace_result: Dictionary = {}
			var thread: Thread = worker.get("thread", null)
			if thread != null:
				trace_result = thread.wait_to_finish()
			else:
				trace_result = _trace_request_worker(traced_request)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				int(worker.get("request_index", 0)),
				int(worker.get("request_start_usec", Time.get_ticks_usec())),
				trace_result
			)
			if host != null and host.get_tree() != null:
				await host.get_tree().process_frame
			if pending_index < filtered_requests.size():
				active_workers.append(_launch_trace_worker(
					filtered_requests[pending_index],
					pending_index,
					filtered_requests.size(),
					start_usec,
					profiling
				))
				pending_index += 1
	else:
		for request_index in filtered_requests.size():
			var traced_request: Dictionary = filtered_requests[request_index]
			var request_start_usec := _emit_baking_start(
				traced_request,
				request_index,
				filtered_requests.size(),
				start_usec,
				profiling
			)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				request_index,
				request_start_usec,
				_trace_request_worker(traced_request)
			)
			if host != null and host.get_tree() != null:
				await host.get_tree().process_frame
	return _finalize_batch_result(
		output_root,
		cell_size,
		draw_size,
		sample_count,
		filtered_requests,
		entries,
		per_tile_counts,
		start_usec,
		variant_settings,
		profiling,
		options
	)


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
		max_supported_sample_count()
	)
	var entries: Array[Dictionary] = []
	var per_tile_counts: Dictionary = {}
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	var request_build_start_usec := Time.get_ticks_usec()
	var filtered_requests := _build_filtered_requests(
		registry,
		tile_ids,
		cell_size,
		draw_size,
		sample_count,
		options
	)
	var profiling := _make_batch_profile((Time.get_ticks_usec() - request_build_start_usec) / 1000.0)
	var start_usec := Time.get_ticks_usec()
	var parallel_plan := _resolve_parallel_execution_plan(filtered_requests.size(), options)
	_apply_parallel_execution_plan(filtered_requests, parallel_plan)
	_record_parallel_execution_plan(profiling, parallel_plan)

	_emit_progress({
		"stage": "queued",
		"completed": 0,
		"total": filtered_requests.size(),
		"progress": 0.0,
		"elapsed_ms": 0.0,
		"output_root": output_root,
	})

	_ensure_dir(output_root)
	if bool(parallel_plan.get("pipeline_enabled", false)):
		var pending_index := 0
		var active_workers: Array[Dictionary] = []
		var worker_count := int(parallel_plan.get("variant_worker_count", 1))
		while pending_index < filtered_requests.size() and active_workers.size() < worker_count:
			active_workers.append(_launch_trace_worker(
				filtered_requests[pending_index],
				pending_index,
				filtered_requests.size(),
				start_usec,
				profiling
			))
			pending_index += 1
		while not active_workers.is_empty():
			var worker: Dictionary = active_workers.pop_front()
			var traced_request: Dictionary = worker.get("request", {})
			var trace_result: Dictionary = {}
			var thread: Thread = worker.get("thread", null)
			if thread != null:
				trace_result = thread.wait_to_finish()
			else:
				trace_result = _trace_request_worker(traced_request)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				int(worker.get("request_index", 0)),
				int(worker.get("request_start_usec", Time.get_ticks_usec())),
				trace_result
			)
			if yield_host != null and yield_host.get_tree() != null:
				await yield_host.get_tree().process_frame
			if pending_index < filtered_requests.size():
				active_workers.append(_launch_trace_worker(
					filtered_requests[pending_index],
					pending_index,
					filtered_requests.size(),
					start_usec,
					profiling
				))
				pending_index += 1
	else:
		for request_index in filtered_requests.size():
			var traced_request: Dictionary = filtered_requests[request_index]
			var request_start_usec := _emit_baking_start(
				traced_request,
				request_index,
				filtered_requests.size(),
				start_usec,
				profiling
			)
			_process_trace_result(
				output_root,
				cell_size,
				draw_size,
				sample_count,
				filtered_requests,
				entries,
				per_tile_counts,
				start_usec,
				profiling,
				traced_request,
				request_index,
				request_start_usec,
				_trace_request_worker(traced_request)
			)
			if yield_host != null and yield_host.get_tree() != null:
				await yield_host.get_tree().process_frame

	return _finalize_batch_result(
		output_root,
		cell_size,
		draw_size,
		sample_count,
		filtered_requests,
		entries,
		per_tile_counts,
		start_usec,
		variant_settings,
		profiling,
		options
	)


func _request_matches_filters(request: Dictionary, options: Dictionary) -> bool:
	var variant_type: StringName = request.get("variant_type", &"")
	# Skip entire variant types when requested.
	if variant_type == &"lighting" and bool(options.get("skip_lighting", false)):
		return false
	if variant_type == &"rotation" and bool(options.get("skip_rotations", false)):
		return false
	if variant_type == &"showroom" and bool(options.get("skip_showroom", false)):
		return false
	# Filter to specific bins when provided.
	var lighting_filters: Array = options.get("lighting_bins", [])
	var rotation_filters: Array = options.get("rotation_bins", [])
	var rotation_label_filters: Array = options.get("rotation_labels", [])
	if variant_type == &"lighting" and not lighting_filters.is_empty():
		return lighting_filters.has(request.get("lighting_bin", Vector2i(-1, -1)))
	if variant_type == &"rotation":
		if not rotation_label_filters.is_empty():
			return rotation_label_filters.has(request.get("rotation_label", &""))
		if not rotation_filters.is_empty():
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
	var variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(options)
	var base_requests: Array = []
	for tile_id in tile_ids:
		var visual: GemVisualResource = registry.get_visual(tile_id)
		if visual == null:
			continue
		var requests: Array = registry.build_gameplay_bake_requests_for_tile(
			tile_id,
			draw_size,
			cell_size,
			variant_settings
		)
		for request in requests:
			if not _request_matches_filters(request, options):
				continue
			base_requests.append(request)
	return _enrich_request_list(base_requests, sample_count, options)


func _enrich_request_list(base_requests: Array, sample_count: int, options: Dictionary) -> Array:
	var filtered_requests: Array[Dictionary] = []
	var mesh_cache: Dictionary = {}
	for request in base_requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		var enriched_request: Dictionary = request.duplicate(true)
		var visual: GemVisualResource = enriched_request.get("visual", null)
		if visual == null:
			continue
		# Resolve environment with CLI/profile override first, then visual, then default.
		if options.has("environment_override"):
			var env_override = options.get("environment_override")
			if env_override != null and env_override.has_method("to_trace_dict"):
				enriched_request["environment_profile"] = env_override.to_trace_dict()
		elif not enriched_request.has("environment_profile"):
			if visual.bake_environment != null and visual.bake_environment.has_method("to_trace_dict"):
				enriched_request["environment_profile"] = visual.bake_environment.to_trace_dict()
			else:
				var default_env := load("res://data/environments/gameplay_studio.tres")
				if default_env != null and default_env.has_method("to_trace_dict"):
					enriched_request["environment_profile"] = default_env.to_trace_dict()
		# Pass through request-level overrides from options
		if options.has("zone_surface_scales") and not enriched_request.has("zone_surface_scales"):
			enriched_request["zone_surface_scales"] = options.get("zone_surface_scales")
		if options.has("output_grade") and not enriched_request.has("output_grade"):
			enriched_request["output_grade"] = options.get("output_grade")
		var mesh_cache_key := _resolve_request_mesh_cache_key(visual, enriched_request)
		var mesh_resource = mesh_cache.get(mesh_cache_key, null)
		var mesh_build_elapsed_ms := 0.0
		if mesh_resource == null:
			var mesh_build_start_usec := Time.get_ticks_usec()
			mesh_resource = _build_request_mesh(visual, enriched_request)
			if mesh_resource == null:
				continue
			mesh_build_elapsed_ms = (Time.get_ticks_usec() - mesh_build_start_usec) / 1000.0
			mesh_cache[mesh_cache_key] = mesh_resource
		enriched_request["sample_count"] = sample_count
		if options.has("thread_count"):
			enriched_request["thread_count"] = int(options.get("thread_count", 1))
		if options.has("trace_profile"):
			enriched_request["trace_profile"] = bool(options.get("trace_profile", false))
		if options.has("samples_per_pixel"):
			enriched_request["samples_per_pixel"] = int(options.get("samples_per_pixel", GemTracedBakeContractScript.DEFAULT_SAMPLES_PER_PIXEL))
		if options.has("seed"):
			enriched_request["seed"] = int(options.get("seed", 42))
		if options.has("skip_stylize"):
			enriched_request["skip_stylize"] = bool(options.get("skip_stylize", false))
		# Image format and quality.
		var image_format := GemTracedBakeContractScript.normalize_image_format(
			options.get("image_format", GemTracedBakeContractScript.DEFAULT_IMAGE_FORMAT)
		)
		enriched_request["image_format"] = image_format
		if image_format == GemTracedBakeContractScript.IMAGE_FORMAT_WEBP:
			var base_quality := float(options.get("webp_quality", GemTracedBakeContractScript.DEFAULT_WEBP_QUALITY))
			enriched_request["image_quality"] = GemTracedBakeContractScript.compute_adaptive_webp_quality(visual, base_quality)
		enriched_request["mesh_resource"] = mesh_resource
		enriched_request["visual"] = visual
		enriched_request["mesh_includes_cut_rotation"] = _request_uses_variant_mesh(visual, enriched_request)
		enriched_request["mesh_build_elapsed_ms"] = mesh_build_elapsed_ms
		enriched_request["mesh_cache_key"] = mesh_cache_key
		filtered_requests.append(enriched_request)
	return filtered_requests


func _build_request_mesh(visual: GemVisualResource, request: Dictionary):
	var request_model = request.get("cut_model", null)
	if request_model != null:
		return GemMeshGeneratorsScript.generate_from_model(request_model)
	return GemMeshGeneratorsScript.generate_from_visual(visual)


func _resolve_request_mesh_cache_key(visual: GemVisualResource, request: Dictionary) -> String:
	if _request_uses_variant_mesh(visual, request):
		return "variant:%s" % String(request.get(
			"cut_key_override",
			request.get("geometry_signature", request.get("variant_key", visual.get_cut_spec_id()))
		))
	return "canonical:%s" % String(request.get("geometry_signature", visual.get_cut_spec_id()))


func _request_uses_variant_mesh(visual: GemVisualResource, request: Dictionary) -> bool:
	if visual == null:
		return false
	return request.get("cut_model", null) != null


func _resolve_parallel_execution_plan(request_count: int, options: Dictionary = {}) -> Dictionary:
	var processor_count := maxi(int(options.get("processor_count_override", OS.get_processor_count())), 1)
	var cpu_budget := maxi(processor_count - 1, 1)
	var requested_trace_threads := maxi(int(options.get("thread_count", 0)), 0)
	var requested_variant_workers := maxi(
		int(options.get("variant_worker_count", options.get("variant_workers", 0))),
		0
	)
	var variant_worker_count := 1
	if request_count > 1:
		if requested_variant_workers > 0:
			variant_worker_count = requested_variant_workers
		elif requested_trace_threads > 0:
			@warning_ignore("integer_division")
			variant_worker_count = maxi(int(cpu_budget / maxi(requested_trace_threads, 1)), 1)
		elif cpu_budget >= 24 and request_count >= 6:
			variant_worker_count = 4
		elif cpu_budget >= 16 and request_count >= 4:
			variant_worker_count = 3
		elif cpu_budget >= 8 and request_count >= 2:
			variant_worker_count = 2
	variant_worker_count = clampi(
		variant_worker_count,
		1,
		mini(maxi(request_count, 1), MAX_AUTO_VARIANT_WORKERS)
	)
	if requested_trace_threads > 0:
		@warning_ignore("integer_division")
		var max_safe_workers := maxi(int(cpu_budget / maxi(requested_trace_threads, 1)), 1)
		variant_worker_count = mini(variant_worker_count, max_safe_workers)
	@warning_ignore("integer_division")
	var trace_thread_budget := requested_trace_threads if requested_trace_threads > 0 else maxi(
		int(cpu_budget / maxi(variant_worker_count, 1)),
		1
	)
	return {
		"processor_count": processor_count,
		"cpu_budget": cpu_budget,
		"requested_trace_threads": requested_trace_threads,
		"requested_variant_workers": requested_variant_workers,
		"trace_thread_budget": trace_thread_budget,
		"variant_worker_count": variant_worker_count,
		"pipeline_enabled": variant_worker_count > 1 and request_count > 1,
	}


func _apply_parallel_execution_plan(filtered_requests: Array, plan: Dictionary) -> void:
	var trace_thread_budget := int(plan.get("trace_thread_budget", 1))
	var variant_worker_count := int(plan.get("variant_worker_count", 1))
	var has_explicit_thread_override := int(plan.get("requested_trace_threads", 0)) > 0
	for raw_request in filtered_requests:
		if typeof(raw_request) != TYPE_DICTIONARY:
			continue
		var traced_request: Dictionary = raw_request
		traced_request["thread_budget"] = trace_thread_budget
		if has_explicit_thread_override:
			traced_request["thread_count"] = trace_thread_budget
		else:
			traced_request.erase("thread_count")
		traced_request["variant_worker_count"] = variant_worker_count


func _record_parallel_execution_plan(profile: Dictionary, plan: Dictionary) -> void:
	profile["processor_count"] = int(plan.get("processor_count", 1))
	profile["cpu_budget"] = int(plan.get("cpu_budget", 1))
	profile["trace_thread_budget"] = int(plan.get("trace_thread_budget", 1))
	profile["variant_worker_count"] = int(plan.get("variant_worker_count", 1))
	profile["pipeline_enabled"] = bool(plan.get("pipeline_enabled", false))


func _emit_baking_start(
	traced_request: Dictionary,
	request_index: int,
	total: int,
	start_usec: int,
	profiling: Dictionary,
) -> int:
	var request_start_usec := Time.get_ticks_usec()
	_emit_progress({
		"stage": "baking",
		"completed": request_index,
		"total": total,
		"progress": _compute_progress_fraction(request_index, total),
		"tile_id": traced_request.get("tile_id", &""),
		"variant_type": traced_request.get("variant_type", &""),
		"variant_key": traced_request.get("variant_key", &""),
		"elapsed_ms": (request_start_usec - start_usec) / 1000.0,
		"mesh_build_elapsed_ms": float(traced_request.get("mesh_build_elapsed_ms", 0.0)),
		"thread_count": int(traced_request.get("thread_count", 1)),
		"variant_worker_count": int(traced_request.get("variant_worker_count", 1)),
	})
	_record_batch_profile_value(
		profiling,
		"mesh_build_elapsed_ms",
		float(traced_request.get("mesh_build_elapsed_ms", 0.0))
	)
	return request_start_usec


func _trace_request_worker(traced_request: Dictionary) -> Dictionary:
	var tracer = create_tracer()
	var mesh_resource: GemMeshResource = traced_request.get("mesh_resource", null)
	var visual: GemVisualResource = traced_request.get("visual", null)
	var trace_start_usec := Time.get_ticks_usec()
	var image: Image = tracer.trace_to_image(mesh_resource, visual, traced_request)
	var profile: Dictionary = tracer.get_last_trace_profile()
	return {
		"image": image,
		"trace_elapsed_ms": (Time.get_ticks_usec() - trace_start_usec) / 1000.0,
		"trace_detail_profile": profile,
	}


func _launch_trace_worker(
	traced_request: Dictionary,
	request_index: int,
	total: int,
	start_usec: int,
	profiling: Dictionary,
) -> Dictionary:
	var request_start_usec := _emit_baking_start(
		traced_request,
		request_index,
		total,
		start_usec,
		profiling
	)
	var thread := Thread.new()
	var start_error := thread.start(_trace_request_worker.bind(traced_request))
	return {
		"thread": thread if start_error == OK else null,
		"request": traced_request,
		"request_index": request_index,
		"request_start_usec": request_start_usec,
		"start_error": start_error,
	}


func _process_trace_result(
	output_root: String,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
	filtered_requests: Array,
	entries: Array,
	per_tile_counts: Dictionary,
	start_usec: int,
	profiling: Dictionary,
	traced_request: Dictionary,
	request_index: int,
	request_start_usec: int,
	trace_result: Dictionary,
) -> void:
	var tile_id: StringName = traced_request.get("tile_id", &"")
	var visual: GemVisualResource = traced_request.get("visual", null)
	var image: Image = trace_result.get("image", null)
	var trace_elapsed_ms := float(trace_result.get("trace_elapsed_ms", 0.0))
	var trace_detail_profile: Dictionary = trace_result.get("trace_detail_profile", {})
	_record_batch_profile_value(profiling, "trace_elapsed_ms", trace_elapsed_ms)
	_merge_profile_dict(profiling, "trace_detail_profile", trace_detail_profile)
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
			"mesh_build_elapsed_ms": float(traced_request.get("mesh_build_elapsed_ms", 0.0)),
			"trace_elapsed_ms": trace_elapsed_ms,
			"trace_detail_profile": trace_detail_profile,
			"status": "trace_failed",
		})
		return
	var stylize_start_usec := Time.get_ticks_usec()
	if not bool(traced_request.get("skip_stylize", false)):
		image = GemBakeStylizerScript.apply(image, visual, traced_request)
	var stylize_elapsed_ms := (Time.get_ticks_usec() - stylize_start_usec) / 1000.0
	_record_batch_profile_value(profiling, "stylize_elapsed_ms", stylize_elapsed_ms)
	var variant_key := String(traced_request.get("variant_key", ""))
	var image_format := GemTracedBakeContractScript.normalize_image_format(
		traced_request.get("image_format", GemTracedBakeContractScript.DEFAULT_IMAGE_FORMAT)
	)
	var texture_path := GemTracedBakeContractScript.build_texture_path(output_root, String(tile_id), variant_key, image_format)
	_ensure_dir(_join_path(output_root, String(tile_id)))
	var save_start_usec := Time.get_ticks_usec()
	var save_err: Error
	if image_format == GemTracedBakeContractScript.IMAGE_FORMAT_WEBP:
		var quality := float(traced_request.get("image_quality", GemTracedBakeContractScript.DEFAULT_WEBP_QUALITY))
		var lossy := quality < 1.0
		save_err = image.save_webp(ProjectSettings.globalize_path(texture_path), lossy, quality)
	else:
		save_err = image.save_png(ProjectSettings.globalize_path(texture_path))
	var save_elapsed_ms := (Time.get_ticks_usec() - save_start_usec) / 1000.0
	_record_batch_profile_value(profiling, "save_elapsed_ms", save_elapsed_ms)
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
		"mesh_build_elapsed_ms": float(traced_request.get("mesh_build_elapsed_ms", 0.0)),
		"trace_elapsed_ms": trace_elapsed_ms,
		"trace_detail_profile": trace_detail_profile,
		"stylize_elapsed_ms": stylize_elapsed_ms,
		"save_elapsed_ms": save_elapsed_ms,
		"status": "ok" if save_err == OK else "save_failed",
		"saved_entries": entries.size(),
	})


func _finalize_batch_result(
	output_root: String,
	cell_size: Vector2i,
	draw_size: Vector2i,
	sample_count: int,
	filtered_requests: Array,
	entries: Array,
	_per_tile_counts: Dictionary,
	start_usec: int,
	variant_settings: Dictionary = {},
	profiling: Dictionary = {},
	batch_options: Dictionary = {},
) -> Dictionary:
	var merged_entries := _merge_manifest_entries(
		_join_path(output_root, DEFAULT_MANIFEST_NAME),
		entries,
		{}
	)
	var merged_tile_counts := _count_entries_by_tile(merged_entries)
	var base_variant_settings := GemTracedBakeContractScript.build_manifest_variant_settings(variant_settings)
	var rotation_layer_count := GemTracedBakeContractScript.infer_rotation_layer_count_from_requests(
		filtered_requests
	)
	var merged_variant_settings := GemTracedBakeContractScript.merge_atlas_metadata_into_variant_settings(
		base_variant_settings,
		rotation_layer_count
	)
	var manifest := {
		"backend_id": &"offline_traced",
		"stylize_version": GemTracedBakeContractScript.BAKED_LOOK_VERSION,
		"output_root": output_root,
		"cell_size": cell_size,
		"draw_size": draw_size,
		"sample_count": sample_count,
		"image_format": String(variant_settings.get(
			"image_format",
			GemTracedBakeContractScript.DEFAULT_IMAGE_FORMAT
		)),
		"variant_settings": merged_variant_settings,
		"tile_counts": merged_tile_counts,
		"entries": merged_entries,
	}
	var profile_id := String(batch_options.get("profile_id", "")).strip_edges()
	if not profile_id.is_empty():
		manifest["profile_id"] = profile_id
	var bake_profile_path := String(batch_options.get("bake_profile_path", "")).strip_edges()
	if not bake_profile_path.is_empty():
		manifest["bake_profile_path"] = bake_profile_path
	if batch_options.has("vram_compress"):
		manifest["vram_compress"] = bool(batch_options.get("vram_compress"))
	if batch_options.has("atlas_output"):
		manifest["atlas_output"] = bool(batch_options.get("atlas_output"))
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
		"profile": profiling.duplicate(true),
	})
	return {
		"status": "ok",
		"manifest_path": manifest_path,
		"entry_count": merged_entries.size(),
		"entries": merged_entries,
		"profile": profiling.duplicate(true),
	}


func _make_batch_profile(request_build_elapsed_ms: float) -> Dictionary:
	return {
		"request_build_elapsed_ms": request_build_elapsed_ms,
		"mesh_build_elapsed_ms": 0.0,
		"trace_elapsed_ms": 0.0,
		"stylize_elapsed_ms": 0.0,
		"save_elapsed_ms": 0.0,
		"processor_count": 1,
		"cpu_budget": 1,
		"trace_thread_budget": 1,
		"variant_worker_count": 1,
		"pipeline_enabled": false,
		"trace_detail_profile": {},
	}


func _record_batch_profile_value(profile: Dictionary, field_name: String, value: float) -> void:
	profile[field_name] = float(profile.get(field_name, 0.0)) + value


func _merge_profile_dict(profile: Dictionary, field_name: String, values: Dictionary) -> void:
	if values.is_empty():
		return
	var merged: Dictionary = profile.get(field_name, {}).duplicate(true)
	for key in values.keys():
		var value = values[key]
		if typeof(value) == TYPE_FLOAT:
			merged[key] = float(merged.get(key, 0.0)) + float(value)
		elif typeof(value) == TYPE_INT:
			merged[key] = int(merged.get(key, 0)) + int(value)
		elif not merged.has(key):
			merged[key] = value
	profile[field_name] = merged


func _merge_manifest_entries(manifest_path: String, new_entries: Array, manifest_context: Dictionary = {}) -> Array:
	var merged_by_key: Dictionary = {}
	if FileAccess.file_exists(manifest_path):
		var existing_file := FileAccess.open(manifest_path, FileAccess.READ)
		if existing_file != null:
			var parsed = JSON.parse_string(existing_file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY and GemTracedBakeContractScript.manifest_matches_current(
				parsed,
				manifest_context
			):
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
