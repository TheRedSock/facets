class_name GemOpticsTracer
extends RefCounted

## GDScript CPU traced gemstone bake — **FALLBACK ONLY**.
##
## The primary tracer is the native C++ GemTraceKernel GDExtension (native/).
## This GDScript version is kept as:
##   1. A readable reference implementation of the trace algorithm
##   2. A fallback for environments where the C++ extension is not compiled
##
## Do not instantiate this class directly from gameplay tooling or regression
## tests. Route tracer selection through `OfflineGemBakeJob.create_tracer()` and
## related helper methods so the repo-facing pipeline stays native-first.
##
## The bake pipeline (OfflineGemBakeJob) auto-selects the native kernel when
## available, falling back to this class otherwise. Both expose the same API:
## trace_to_image() and get_last_trace_profile().
##
## If modifying the trace algorithm, update native/src/gem_trace_kernel.cpp
## first (primary), then mirror the change here (fallback).

const GemMaterialSamplerScript = preload("res://core/visuals/gem_material_sampler.gd")

const AIR_IOR := 1.00029
const EPSILON := 0.0005
const MAX_TRACE_BOUNCES := 12
const MAX_OVERRIDE_TRACE_BOUNCES := 24
const MIN_BRANCH_WEIGHT := 0.001
const DEFAULT_SAMPLE_COUNT := 2
const VIEW_MARGIN := 1.18
const LOW_FIRE_WAVELENGTH_SAMPLES := [0.0, 0.5, 1.0]
const HIGH_FIRE_WAVELENGTH_SAMPLES := [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0]
const ACES_A := 2.51
const ACES_B := 0.03
const ACES_C := 2.43
const ACES_D := 0.59
const ACES_E := 0.14
const MIN_ROWS_PER_TRACE_THREAD := 8
const MIN_PIXELS_PER_TRACE_THREAD := 6144
const MIN_WORK_UNITS_PER_TRACE_THREAD := 20000
const SAMPLE_PATTERN := [
	Vector2(0.5, 0.5),
	Vector2(0.25, 0.25),
	Vector2(0.75, 0.25),
	Vector2(0.25, 0.75),
	Vector2(0.75, 0.75),
]

var _last_trace_profile: Dictionary = {}


static func max_supported_sample_count() -> int:
	return SAMPLE_PATTERN.size()


func get_last_trace_profile() -> Dictionary:
	return _last_trace_profile.duplicate(true)


func trace_to_image(mesh_resource: GemMeshResource, visual: GemVisualResource, request: Dictionary) -> Image:
	_last_trace_profile.clear()
	if mesh_resource == null or visual == null:
		return null
	var target_size: Vector2i = request.get("trace_size", request.get("draw_size", request.get("target_size", Vector2i.ZERO)))
	if target_size.x <= 0 or target_size.y <= 0:
		return null
	var profile_enabled := bool(request.get("trace_profile", false))
	var trace_profile := _make_trace_profile(profile_enabled)
	var trace_view_start_usec := Time.get_ticks_usec() if profile_enabled else 0
	var trace_view := _build_trace_view(mesh_resource, visual, request)
	_record_trace_elapsed(trace_profile, "trace_view_elapsed_ms", trace_view_start_usec)
	var trace_data: Dictionary = trace_view.get("trace_data", {})
	var bounds: AABB = trace_view.get("bounds", AABB())
	var radius := maxf(float(trace_view.get("bounding_radius", 0.0)), 0.25)
	var aspect := float(target_size.x) / maxf(float(target_size.y), 1.0)
	var view_scale := clampf(float(request.get("view_scale", 1.0)), 0.5, 2.0)
	var half_height := maxf(bounds.size.y, radius * 2.0) * VIEW_MARGIN * 0.5 / view_scale
	var half_width := half_height * aspect
	var origin_z := bounds.position.z + bounds.size.z + radius * 2.4
	var inverse_basis: Basis = trace_view.get("inverse_basis", Basis.IDENTITY)
	var dir := (inverse_basis * Vector3(0.0, 0.0, -1.0)).normalized()
	var light_dir_world: Vector3 = request.get("light_dir", Vector3(-0.4, -0.5, 0.75)).normalized()
	if light_dir_world.is_zero_approx():
		light_dir_world = Vector3(-0.4, -0.5, 0.75)
	var light_dir := (inverse_basis * light_dir_world).normalized()
	var trace_request: Dictionary = request.duplicate(true)
	trace_request["trace_flags"] = _build_trace_flags(visual)
	trace_request["environment_setup"] = _build_environment_setup(light_dir, trace_request, visual)
	trace_request["surface_setup"] = _build_surface_setup(visual, trace_request, light_dir)
	var sample_count := clampi(int(request.get("sample_count", DEFAULT_SAMPLE_COUNT)), 1, max_supported_sample_count())
	var view_dir := -dir
	var spectral_samples := _build_spectral_samples(visual)
	var texture_image: Image = null
	if visual.use_texture and visual.color_texture != null:
		texture_image = visual.color_texture.get_image()

	# Bundle all read-only state so worker threads can access it without
	# touching instance variables (the tracer class is stateless).
	var ctx := {
		"target_size": target_size,
		"trace_data": trace_data,
		"inverse_basis": inverse_basis,
		"half_width": half_width,
		"half_height": half_height,
		"origin_z": origin_z,
		"dir": dir,
		"light_dir": light_dir,
		"view_dir": view_dir,
		"sample_count": sample_count,
		"spectral_samples": spectral_samples,
		"visual": visual,
		"radius": radius,
		"request": trace_request,
		"texture_image": texture_image,
		"profile_enabled": profile_enabled,
	}

	var thread_budget := clampi(
		int(request.get("thread_budget", request.get("thread_count", OS.get_processor_count() - 1))),
		1,
		32
	)
	var thread_count := resolve_trace_thread_count(
		request,
		target_size,
		sample_count,
		spectral_samples.size()
	)
	if profile_enabled:
		trace_profile["thread_budget"] = thread_budget
		trace_profile["thread_count"] = thread_count
		trace_profile["sample_count"] = sample_count
		trace_profile["spectral_sample_count"] = spectral_samples.size()
		trace_profile["target_size"] = target_size
		trace_profile["max_trace_bounces"] = _resolve_max_trace_bounces(request)

	if thread_count <= 1:
		var band_result: Dictionary = _trace_row_band(ctx, 0, target_size.y)
		var band: PackedColorArray = band_result.get("pixels", PackedColorArray())
		_merge_trace_profile(trace_profile, band_result.get("profile", {}))
		_last_trace_profile = trace_profile.duplicate(true)
		return _finalize_traced_image(_color_array_to_image(band, target_size, trace_profile), trace_profile)

	var rows_per_thread := ceili(float(target_size.y) / float(thread_count))
	var threads: Array[Thread] = []
	for t in thread_count:
		var row_start := t * rows_per_thread
		var row_end := mini((t + 1) * rows_per_thread, target_size.y)
		if row_start >= target_size.y:
			break
		var thread := Thread.new()
		thread.start(_trace_row_band.bind(ctx, row_start, row_end))
		threads.append(thread)

	var pixels := PackedColorArray()
	pixels.resize(target_size.x * target_size.y)
	for t in threads.size():
		var band_result: Dictionary = threads[t].wait_to_finish()
		var band: PackedColorArray = band_result.get("pixels", PackedColorArray())
		_merge_trace_profile(trace_profile, band_result.get("profile", {}))
		var row_start := t * rows_per_thread
		for i in band.size():
			pixels[row_start * target_size.x + i] = band[i]
	_last_trace_profile = trace_profile.duplicate(true)
	return _finalize_traced_image(_color_array_to_image(pixels, target_size, trace_profile), trace_profile)


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
	var row_limit := maxi(target_size.y / MIN_ROWS_PER_TRACE_THREAD, 1)
	var pixel_limit := maxi(pixel_count / MIN_PIXELS_PER_TRACE_THREAD, 1)
	var work_units := pixel_count * maxi(sample_count, 1) * maxi(spectral_sample_count, 1)
	var work_limit := maxi(work_units / MIN_WORK_UNITS_PER_TRACE_THREAD, 1)
	return maxi(mini(mini(thread_budget, row_limit), mini(pixel_limit, work_limit)), 1)


func _resolve_trace_thread_count(
	request: Dictionary,
	target_size: Vector2i,
	sample_count: int,
	spectral_sample_count: int,
) -> int:
	return resolve_trace_thread_count(request, target_size, sample_count, spectral_sample_count)


## Traces a horizontal band of rows and returns a dictionary containing a flat
## row-major PackedColorArray and optional per-band timing counters.
func _trace_row_band(ctx: Dictionary, row_start: int, row_end: int) -> Dictionary:
	var target_size: Vector2i = ctx["target_size"]
	var trace_data: Dictionary = ctx["trace_data"]
	var inverse_basis: Basis = ctx["inverse_basis"]
	var half_width: float = ctx["half_width"]
	var half_height: float = ctx["half_height"]
	var origin_z: float = ctx["origin_z"]
	var dir: Vector3 = ctx["dir"]
	var light_dir: Vector3 = ctx["light_dir"]
	var view_dir: Vector3 = ctx["view_dir"]
	var sample_count: int = ctx["sample_count"]
	var spectral_samples: Array = ctx["spectral_samples"]
	var visual: GemVisualResource = ctx["visual"]
	var radius: float = ctx["radius"]
	var request: Dictionary = ctx["request"]
	var texture_image: Image = ctx.get("texture_image", null)
	var band_profile := _make_trace_profile(bool(ctx.get("profile_enabled", false)))

	var band_pixels := (row_end - row_start) * target_size.x
	var result := PackedColorArray()
	result.resize(band_pixels)
	var pixel_index := 0

	for y in range(row_start, row_end):
		for x in target_size.x:
			var rgb_sum := Vector3.ZERO
			var hit_count := 0.0
			for sample_index in sample_count:
				var offset: Vector2 = SAMPLE_PATTERN[sample_index]
				var u := ((float(x) + offset.x) / float(target_size.x)) * 2.0 - 1.0
				var v := 1.0 - ((float(y) + offset.y) / float(target_size.y)) * 2.0
				var origin := inverse_basis * Vector3(u * half_width, v * half_height, origin_z)
				var first_hit_start_usec := Time.get_ticks_usec() if not band_profile.is_empty() else 0
				var first_hit := _intersect_scene(origin, dir, trace_data, -1)
				_record_trace_elapsed(band_profile, "primary_intersect_elapsed_ms", first_hit_start_usec)
				_increment_trace_counter(band_profile, "primary_intersect_count")
				if first_hit.is_empty():
					continue
				hit_count += 1.0
				for spectral_sample in spectral_samples:
					var wavelength_t := float(spectral_sample.get("t", 0.5))
					var weight: Vector3 = spectral_sample.get("weight", Vector3.ONE)
					var wavelength_trace_start_usec := Time.get_ticks_usec() if not band_profile.is_empty() else 0
					var intensity := _trace_wavelength_from_hit(
						first_hit,
						origin,
						dir,
						trace_data,
						visual,
						light_dir,
						request,
						wavelength_t,
						AIR_IOR,
						radius,
						0,
						band_profile
					)
					_record_trace_elapsed(band_profile, "spectral_trace_elapsed_ms", wavelength_trace_start_usec)
					_increment_trace_counter(band_profile, "spectral_trace_count")
					rgb_sum += Vector3(
						weight.x * intensity,
						weight.y * intensity,
						weight.z * intensity
					)
				var surface_lighting_start_usec := Time.get_ticks_usec() if not band_profile.is_empty() else 0
				rgb_sum += _compute_surface_lighting(
					first_hit.position,
					first_hit.normal,
					StringName(first_hit.get("zone", &"")),
					light_dir,
					view_dir,
					radius,
					visual,
					request,
					texture_image
				)
				_record_trace_elapsed(band_profile, "surface_lighting_elapsed_ms", surface_lighting_start_usec)
				_increment_trace_counter(band_profile, "surface_lighting_count")
			if hit_count <= 0.0:
				result[pixel_index] = Color(0.0, 0.0, 0.0, 0.0)
			else:
				var color := _apply_output_grade(rgb_sum / hit_count, visual)
				result[pixel_index] = Color(
					color.x,
					color.y,
					color.z,
					clampf(hit_count / float(sample_count), 0.0, 1.0)
				)
			pixel_index += 1
	return {
		"pixels": result,
		"profile": band_profile,
	}


func _color_array_to_image(colors: PackedColorArray, target_size: Vector2i, trace_profile: Dictionary = {}) -> Image:
	var image := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	var encode_start_usec := Time.get_ticks_usec() if not trace_profile.is_empty() else 0
	image.set_data(
		target_size.x,
		target_size.y,
		false,
		Image.FORMAT_RGBA8,
		_encode_color_array_rgba8(colors)
	)
	_record_trace_elapsed(trace_profile, "encode_elapsed_ms", encode_start_usec)
	return image


func _encode_color_array_rgba8(colors: PackedColorArray) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(colors.size() * 4)
	for i in colors.size():
		var color := colors[i]
		var byte_index := i * 4
		bytes[byte_index] = int(round(clampf(color.r, 0.0, 1.0) * 255.0))
		bytes[byte_index + 1] = int(round(clampf(color.g, 0.0, 1.0) * 255.0))
		bytes[byte_index + 2] = int(round(clampf(color.b, 0.0, 1.0) * 255.0))
		bytes[byte_index + 3] = int(round(clampf(color.a, 0.0, 1.0) * 255.0))
	return bytes


func _finalize_traced_image(image: Image, trace_profile: Dictionary = {}) -> Image:
	if image == null:
		return null
	var alpha_cleanup_start_usec := Time.get_ticks_usec() if not trace_profile.is_empty() else 0
	_clean_alpha_edges(image)
	_record_trace_elapsed(trace_profile, "alpha_cleanup_elapsed_ms", alpha_cleanup_start_usec)
	_last_trace_profile = trace_profile.duplicate(true)
	return image


func _build_trace_view(
	mesh_resource: GemMeshResource,
	visual: GemVisualResource,
	request: Dictionary,
) -> Dictionary:
	var trace_data: Dictionary = mesh_resource.build_trace_data().duplicate(false)
	trace_data["optic_axis"] = _resolve_optic_axis(visual)
	var basis := _build_view_basis(visual, request)
	var source_bounds: AABB = trace_data.get("bounds", mesh_resource.compute_bounds())
	return {
		"trace_data": trace_data,
		"view_basis": basis,
		"inverse_basis": basis.inverse(),
		"bounds": _transform_aabb(source_bounds, basis),
		"bounding_radius": float(trace_data.get("bounding_radius", mesh_resource.compute_bounding_radius())),
	}


func _build_view_basis(visual: GemVisualResource, request: Dictionary) -> Basis:
	var view_angles := _resolve_view_angles(request, visual)
	var basis := Basis(Vector3.RIGHT, deg_to_rad(view_angles.x))
	var mesh_includes_cut_rotation := bool(request.get("mesh_includes_cut_rotation", false))
	var yaw_degrees := view_angles.y
	var roll_degrees := float(request.get("view_roll_degrees", 0.0))
	if not mesh_includes_cut_rotation:
		yaw_degrees += float(request.get("rotation_degrees", 0.0))
		roll_degrees += visual.rotation_degrees
	basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees)) * basis
	if not is_zero_approx(roll_degrees):
		basis = Basis(Vector3.BACK, deg_to_rad(roll_degrees)) * basis
	return basis


func _transform_aabb(bounds: AABB, basis: Basis) -> AABB:
	var corners := [
		bounds.position,
		bounds.position + Vector3(bounds.size.x, 0.0, 0.0),
		bounds.position + Vector3(0.0, bounds.size.y, 0.0),
		bounds.position + Vector3(0.0, 0.0, bounds.size.z),
		bounds.position + Vector3(bounds.size.x, bounds.size.y, 0.0),
		bounds.position + Vector3(bounds.size.x, 0.0, bounds.size.z),
		bounds.position + Vector3(0.0, bounds.size.y, bounds.size.z),
		bounds.position + bounds.size,
	]
	var min_v := Vector3(INF, INF, INF)
	var max_v := Vector3(-INF, -INF, -INF)
	for corner in corners:
		var transformed: Vector3 = basis * corner
		min_v.x = minf(min_v.x, transformed.x)
		min_v.y = minf(min_v.y, transformed.y)
		min_v.z = minf(min_v.z, transformed.z)
		max_v.x = maxf(max_v.x, transformed.x)
		max_v.y = maxf(max_v.y, transformed.y)
		max_v.z = maxf(max_v.z, transformed.z)
	if min_v.x == INF:
		return AABB()
	return AABB(min_v, max_v - min_v)


func _trace_wavelength(
	origin: Vector3,
	dir: Vector3,
	trace_data: Dictionary,
	visual: GemVisualResource,
	light_dir: Vector3,
	request: Dictionary,
	wavelength_t: float,
	current_ior: float,
	radius: float,
	depth: int,
	last_triangle_index: int,
	profile: Dictionary = {},
) -> float:
	var trace_flags: Dictionary = request.get("trace_flags", {})
	if depth >= _resolve_max_trace_bounces(request):
		return _sample_environment(dir, light_dir, request, visual, wavelength_t)
	if bool(trace_flags.get("is_patterned_opaque", false)):
		return 0.0
	var intersect_start_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
	var hit := _intersect_scene(origin, dir, trace_data, last_triangle_index)
	_record_trace_elapsed(profile, "secondary_intersect_elapsed_ms", intersect_start_usec)
	_increment_trace_counter(profile, "secondary_intersect_count")
	if hit.is_empty():
		return _sample_environment(dir, light_dir, request, visual, wavelength_t)
	return _trace_wavelength_from_hit(
		hit,
		origin,
		dir,
		trace_data,
		visual,
		light_dir,
		request,
		wavelength_t,
		current_ior,
		radius,
		depth,
		profile
	)


func _trace_wavelength_from_hit(
	hit: Dictionary,
	origin: Vector3,
	dir: Vector3,
	trace_data: Dictionary,
	visual: GemVisualResource,
	light_dir: Vector3,
	request: Dictionary,
	wavelength_t: float,
	current_ior: float,
	radius: float,
	depth: int,
	profile: Dictionary = {},
) -> float:
	if hit.is_empty():
		return _sample_environment(dir, light_dir, request, visual, wavelength_t)
	var trace_flags: Dictionary = request.get("trace_flags", {})
	_increment_trace_counter(profile, "primary_hit_reuse_count")

	var segment_attenuation := 1.0
	var scattering_contribution := 0.0
	if current_ior > AIR_IOR + 0.0001:
		var volume_sample := {}
		if bool(trace_flags.get("has_volume_sampling", false)):
			var volume_sample_start_usec := Time.get_ticks_usec() if not profile.is_empty() else 0
			volume_sample = _sample_segment_volume(visual, origin, hit.position, radius)
			_record_trace_elapsed(profile, "volume_sampling_elapsed_ms", volume_sample_start_usec)
			_increment_trace_counter(profile, "volume_sampling_count")
		segment_attenuation = _compute_segment_attenuation(
			visual,
			wavelength_t,
			float(hit.distance),
			volume_sample
		)
		scattering_contribution = _compute_segment_scattering(
			visual,
			wavelength_t,
			float(hit.distance),
			volume_sample
		)

	var outward_normal: Vector3 = hit.normal
	var shading_normal := outward_normal if hit.front_face else -outward_normal
	var eta_i := current_ior
	var eta_t := AIR_IOR
	if hit.front_face:
		eta_t = _wavelength_ior(visual, wavelength_t)

	var fresnel := _fresnel_dielectric(dir, shading_normal, eta_i, eta_t)
	var reflection_dir := (dir - 2.0 * dir.dot(shading_normal) * shading_normal).normalized()
	var reflection := 0.0
	if fresnel > MIN_BRANCH_WEIGHT:
		reflection = _trace_wavelength(
			hit.position + reflection_dir * EPSILON,
			reflection_dir,
			trace_data,
			visual,
			light_dir,
			request,
			wavelength_t,
			eta_i,
			radius,
			depth + 1,
			hit.triangle_index,
			profile
		)
	var total := reflection * fresnel

	var transmission_factor := float(
		trace_flags.get("transmission_factor", GemMaterialSamplerScript.transmission_factor(visual))
	)
	var refraction_components: Array[Dictionary] = []
	if transmission_factor > 0.001:
		refraction_components = _build_refraction_components(
			dir,
			shading_normal,
			trace_data,
			visual,
			wavelength_t,
			eta_i,
			eta_t,
			hit.front_face
		)
	if refraction_components.is_empty():
		# Total Internal Reflection — all energy goes to the reflected ray.
		total = reflection
	else:
		for component in refraction_components:
			var component_dir: Vector3 = component.get("dir", Vector3.ZERO)
			if component_dir.is_zero_approx():
				continue
			var component_weight := float(component.get("weight", 1.0))
			var component_ior := float(component.get("ior", eta_t))
			var branch_weight := (1.0 - fresnel) * component_weight * transmission_factor
			if branch_weight <= MIN_BRANCH_WEIGHT:
				continue
			var transmitted := _trace_wavelength(
				hit.position + component_dir * EPSILON,
				component_dir,
				trace_data,
				visual,
				light_dir,
				request,
				wavelength_t,
				component_ior,
				radius,
				depth + 1,
				hit.triangle_index,
				profile
			)
			var cloudiness := float(trace_flags.get("cloudiness", 0.0))
			transmitted *= 1.0 - cloudiness * (0.12 if hit.front_face else 0.06)
			total += transmitted * branch_weight

	total *= segment_attenuation
	# Interface highlight only on exterior front-face hits (depth 0).
	# Inside the gem, light interaction is purely Fresnel reflection/refraction.
	if hit.front_face and depth == 0:
		total += _compute_interface_highlight(
			visual,
			hit.zone,
			shading_normal,
			light_dir,
			request,
			(-dir).normalized(),
			wavelength_t
		) * (0.12 + fresnel * 0.34)
	total += scattering_contribution
	return clampf(total, 0.0, 18.0)


func _intersect_scene(origin: Vector3, dir: Vector3, trace_data: Dictionary, last_triangle_index: int) -> Dictionary:
	var bvh_bounds: Array = trace_data.get("bvh_node_bounds", [])
	if not bvh_bounds.is_empty():
		return _intersect_scene_bvh(origin, dir, trace_data, last_triangle_index)
	return _intersect_scene_linear(origin, dir, trace_data, last_triangle_index)


func _intersect_scene_linear(origin: Vector3, dir: Vector3, trace_data: Dictionary, last_triangle_index: int) -> Dictionary:
	var a_list: Array = trace_data.get("triangle_vertices_a", [])
	var b_list: Array = trace_data.get("triangle_vertices_b", [])
	var c_list: Array = trace_data.get("triangle_vertices_c", [])
	var normal_list: Array = trace_data.get("triangle_normals", [])
	var zone_list: PackedStringArray = trace_data.get("triangle_zones", PackedStringArray())
	var nearest_t := INF
	var nearest_index := -1
	var nearest_normal := Vector3.ZERO
	for i in a_list.size():
		if i == last_triangle_index:
			continue
		var t := _intersect_triangle(origin, dir, a_list[i], b_list[i], c_list[i])
		if t <= EPSILON or t >= nearest_t:
			continue
		nearest_t = t
		nearest_index = i
		nearest_normal = normal_list[i]
	if nearest_index < 0:
		return {}
	var position := origin + dir * nearest_t
	var front_face := dir.dot(nearest_normal) < 0.0
	return {
		"distance": nearest_t,
		"triangle_index": nearest_index,
		"position": position,
		"normal": nearest_normal,
		"zone": StringName(zone_list[nearest_index] if nearest_index < zone_list.size() else &""),
		"front_face": front_face,
	}


func _intersect_scene_bvh(origin: Vector3, dir: Vector3, trace_data: Dictionary, last_triangle_index: int) -> Dictionary:
	var a_list: Array = trace_data.get("triangle_vertices_a", [])
	var b_list: Array = trace_data.get("triangle_vertices_b", [])
	var c_list: Array = trace_data.get("triangle_vertices_c", [])
	var normal_list: Array = trace_data.get("triangle_normals", [])
	var zone_list: PackedStringArray = trace_data.get("triangle_zones", PackedStringArray())
	var triangle_indices: Array = trace_data.get("bvh_triangle_indices", [])
	var node_bounds: Array = trace_data.get("bvh_node_bounds", [])
	var node_left: Array = trace_data.get("bvh_node_left", [])
	var node_right: Array = trace_data.get("bvh_node_right", [])
	var node_start: Array = trace_data.get("bvh_node_start", [])
	var node_count: Array = trace_data.get("bvh_node_count", [])
	if node_bounds.is_empty():
		return _intersect_scene_linear(origin, dir, trace_data, last_triangle_index)
	var nearest_t := INF
	var nearest_index := -1
	var nearest_normal := Vector3.ZERO
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var node_index: int = stack.pop_back()
		if node_index < 0 or node_index >= node_bounds.size():
			continue
		var node_hit_t := _intersect_aabb(origin, dir, node_bounds[node_index], nearest_t)
		if node_hit_t >= nearest_t:
			continue
		var leaf_count: int = node_count[node_index]
		if leaf_count > 0:
			var leaf_start: int = node_start[node_index]
			for i in range(leaf_start, leaf_start + leaf_count):
				var tri_index: int = triangle_indices[i]
				if tri_index == last_triangle_index:
					continue
				var t := _intersect_triangle(origin, dir, a_list[tri_index], b_list[tri_index], c_list[tri_index])
				if t <= EPSILON or t >= nearest_t:
					continue
				nearest_t = t
				nearest_index = tri_index
				nearest_normal = normal_list[tri_index]
			continue
		var left_index: int = node_left[node_index]
		var right_index: int = node_right[node_index]
		var left_hit := _intersect_aabb(origin, dir, node_bounds[left_index], nearest_t) if left_index >= 0 else INF
		var right_hit := _intersect_aabb(origin, dir, node_bounds[right_index], nearest_t) if right_index >= 0 else INF
		if left_hit < right_hit:
			if right_hit < nearest_t:
				stack.append(right_index)
			if left_hit < nearest_t:
				stack.append(left_index)
		else:
			if left_hit < nearest_t:
				stack.append(left_index)
			if right_hit < nearest_t:
				stack.append(right_index)
	if nearest_index < 0:
		return {}
	var position := origin + dir * nearest_t
	var front_face := dir.dot(nearest_normal) < 0.0
	return {
		"distance": nearest_t,
		"triangle_index": nearest_index,
		"position": position,
		"normal": nearest_normal,
		"zone": StringName(zone_list[nearest_index] if nearest_index < zone_list.size() else &""),
		"front_face": front_face,
	}


func _intersect_triangle(origin: Vector3, dir: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var edge1 := b - a
	var edge2 := c - a
	var p := dir.cross(edge2)
	var det := edge1.dot(p)
	if absf(det) <= 0.0000001:
		return INF
	var inv_det := 1.0 / det
	var tvec := origin - a
	var u := tvec.dot(p) * inv_det
	if u < 0.0 or u > 1.0:
		return INF
	var qvec := tvec.cross(edge1)
	var v := dir.dot(qvec) * inv_det
	if v < 0.0 or (u + v) > 1.0:
		return INF
	var t := edge2.dot(qvec) * inv_det
	return t if t > EPSILON else INF


func _intersect_aabb(origin: Vector3, dir: Vector3, bounds: AABB, current_max_t: float = INF) -> float:
	var min_v := bounds.position
	var max_v := bounds.position + bounds.size
	var t_min := 0.0
	var t_max := current_max_t
	for axis in 3:
		var axis_origin := _axis_component(origin, axis)
		var axis_dir := _axis_component(dir, axis)
		var axis_min := _axis_component(min_v, axis)
		var axis_max := _axis_component(max_v, axis)
		if absf(axis_dir) <= 0.0000001:
			if axis_origin < axis_min or axis_origin > axis_max:
				return INF
			continue
		var inv_dir := 1.0 / axis_dir
		var t0 := (axis_min - axis_origin) * inv_dir
		var t1 := (axis_max - axis_origin) * inv_dir
		if t0 > t1:
			var swap := t0
			t0 = t1
			t1 = swap
		t_min = maxf(t_min, t0)
		t_max = minf(t_max, t1)
		if t_max < t_min:
			return INF
	return t_min


func _axis_component(value: Vector3, axis: int) -> float:
	match axis:
		1:
			return value.y
		2:
			return value.z
		_:
			return value.x


func _wavelength_ior(visual: GemVisualResource, wavelength_t: float) -> float:
	var base := maxf(visual.optics_ior, 1.0)
	var spread := maxf(visual.optics_dispersion, 0.0)
	# Cauchy-like dispersion: n(λ) ≈ A + B/λ².  Map wavelength_t ∈ [0,1] to an
	# effective inverse-square term so shorter wavelengths (t→0, blue) refract
	# more and longer wavelengths (t→1, red) refract less.
	# λ_eff ranges from 0.38 µm (blue) to 0.72 µm (red) mapped linearly from t.
	var lambda_eff := lerpf(0.38, 0.72, clampf(wavelength_t, 0.0, 1.0))
	var lambda_ref := 0.55  # reference wavelength (green-yellow midpoint)
	var cauchy_term := (1.0 / (lambda_eff * lambda_eff) - 1.0 / (lambda_ref * lambda_ref))
	# Scale so spread maps directly to total IOR variation across the spectrum.
	var cauchy_scale := 1.0 / (1.0 / (0.38 * 0.38) - 1.0 / (0.72 * 0.72))
	return maxf(base + spread * cauchy_term * cauchy_scale, 1.0)


func _compute_segment_attenuation(
	visual: GemVisualResource,
	wavelength_t: float,
	distance: float,
	medium_sample: Dictionary = {},
) -> float:
	var tint = medium_sample.get("color", visual.optics_absorption_color)
	if tint.a <= 0.001:
		tint = visual.depth_tint if visual.depth_tint.a > 0.001 else visual.base_color
	var channel_tint := _sample_color_wavelength(tint, wavelength_t)
	var coeff := maxf(1.0 - channel_tint, 0.0) * maxf(
		visual.optics_absorption_strength * float(medium_sample.get("absorption_mult", 1.0)),
		0.0
	)
	return exp(-coeff * maxf(distance, 0.0))


func _compute_segment_scattering(
	visual: GemVisualResource,
	wavelength_t: float,
	distance: float,
	medium_sample: Dictionary = {},
) -> float:
	var strength := maxf(
		visual.optics_scattering_strength * float(medium_sample.get("scattering_mult", 1.0)),
		visual.translucency * 0.6
	)
	if strength <= 0.0001:
		return 0.0
	var scatter_color = medium_sample.get("color", visual.optics_scattering_color)
	if scatter_color.a <= 0.001:
		scatter_color = visual.translucency_color
	var raw_scatter := _sample_color_wavelength(scatter_color, wavelength_t) * (1.0 - exp(-strength * maxf(distance, 0.0))) * 0.42
	# Attenuate scattered light by absorption along the remaining exit path.
	# Use half the segment distance as a statistical estimate of exit path length.
	var tint = medium_sample.get("color", visual.optics_absorption_color)
	if tint.a <= 0.001:
		tint = visual.depth_tint if visual.depth_tint.a > 0.001 else visual.base_color
	var abs_coeff := maxf(1.0 - _sample_color_wavelength(tint, wavelength_t), 0.0) * maxf(
		visual.optics_absorption_strength * float(medium_sample.get("absorption_mult", 1.0)),
		0.0
	)
	var exit_attenuation := exp(-abs_coeff * maxf(distance * 0.5, 0.0))
	return raw_scatter * exit_attenuation


func _sample_environment(dir: Vector3, light_dir: Vector3, request: Dictionary, visual: GemVisualResource, wavelength_t: float) -> float:
	var t := clampf(dir.y * 0.5 + 0.5, 0.0, 1.0)
	var env_energy := maxf(visual.optics_environment_energy, 0.01)
	var environment_setup: Dictionary = request.get("environment_setup", _build_environment_setup(light_dir, request, visual))
	var sky_low: Color = environment_setup.get("sky_low", Color(0.12, 0.15, 0.20, 1.0))
	var sky_top: Color = environment_setup.get("sky_top", Color(0.28, 0.33, 0.42, 1.0))
	var horizon_color: Color = environment_setup.get("horizon", Color(0.62, 0.48, 0.32, 1.0))
	var horizon := horizon_color * exp(-pow(dir.y / 0.22, 2.0))
	var ground_mix := clampf(-dir.y, 0.0, 1.0)
	var ground_dark: Color = environment_setup.get("ground_dark", Color(0.015, 0.012, 0.010, 1.0))
	var ground_lift: Color = environment_setup.get("ground_lift", Color(0.08, 0.06, 0.04, 1.0))
	var ground := ground_dark.lerp(ground_lift, ground_mix * 0.22)
	var env := sky_low.lerp(sky_top, pow(t, 1.35))
	env = env.lerp(ground, ground_mix)
	env = (env + horizon) * env_energy
	var roughness := clampf(visual.optics_surface_roughness, 0.0, 1.0)
	var total := _sample_color_wavelength(env, wavelength_t)
	var cards: Array = environment_setup.get("cards", [])
	for raw_card in cards:
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw_card
		var card_dir: Vector3 = card.get("dir", light_dir)
		var alignment := maxf(dir.dot(card_dir), 0.0)
		var power := lerpf(
			float(card.get("sharp_power", 72.0)),
			float(card.get("broad_power", 14.0)),
			roughness
		)
		var strength := lerpf(
			float(card.get("sharp_strength", 0.5)),
			float(card.get("broad_strength", 0.3)),
			roughness
		)
		var card_color: Color = card.get("color", Color.WHITE)
		total += _sample_color_wavelength(card_color, wavelength_t) * pow(alignment, power) * strength * visual.optics_light_energy
	var blocker_dir: Vector3 = environment_setup.get("blocker_dir", light_dir)
	var blocker_alignment := maxf(dir.dot(blocker_dir), 0.0)
	var blocker_power := float(environment_setup.get("blocker_power", 10.0))
	var blocker_strength := float(environment_setup.get("blocker_strength", 0.0))
	total -= pow(blocker_alignment, blocker_power) * blocker_strength
	return clampf(total, 0.0, 18.0)


func _resolve_environment_profile(visual: GemVisualResource) -> Dictionary:
	match visual.optics_environment_preset:
		GemVisualResource.OPTICS_ENVIRONMENT_GAMEPLAY_STUDIO:
			return {
				"sky_low": Color(0.08, 0.09, 0.12, 1.0),
				"sky_top": Color(0.20, 0.23, 0.30, 1.0),
				"horizon": Color(0.46, 0.40, 0.34, 1.0),
				"ground_dark": Color(0.016, 0.014, 0.014, 1.0),
				"ground_lift": Color(0.06, 0.052, 0.048, 1.0),
				"cards": [
					_environment_card(
						Vector3(0.02, 0.30, 0.95),
						Color(1.0, 0.99, 0.97, 1.0),
						820.0,
						12.0,
						2.4,
						2.0
					),
					_environment_card(
						Vector3(0.72, 0.12, 0.68),
						Color(1.0, 0.94, 0.88, 1.0),
						92.0,
						8.0,
						0.34,
						0.36
					),
					_environment_card(
						Vector3(-0.72, 0.14, 0.64),
						Color(0.92, 0.97, 1.0, 1.0),
						92.0,
						8.0,
						0.32,
						0.34
					),
					_environment_card(
						Vector3(-0.06, -0.54, 0.84),
						Color(1.0, 0.92, 0.82, 1.0),
						24.0,
						6.0,
						0.10,
						0.14
					),
				],
				"blocker_local_dir": Vector3(-0.10, -0.18, 0.98),
				"blocker_power": 8.0,
				"blocker_strength": 0.10,
			}
		GemVisualResource.OPTICS_ENVIRONMENT_DARK_STUDIO:
			return {
				"sky_low": Color(0.018, 0.020, 0.028, 1.0),
				"sky_top": Color(0.055, 0.060, 0.085, 1.0),
				"horizon": Color(0.16, 0.12, 0.09, 1.0),
				"ground_dark": Color(0.003, 0.003, 0.004, 1.0),
				"ground_lift": Color(0.020, 0.016, 0.012, 1.0),
				"cards": [
					_environment_card(
						Vector3(0.02, 0.44, 0.90),
						Color(1.0, 0.99, 0.97, 1.0),
						1150.0,
						14.0,
						4.8,
						2.8
					),
					_environment_card(
						Vector3(0.72, 0.12, 0.68),
						Color(0.96, 0.94, 1.0, 1.0),
						120.0,
						8.0,
						0.56,
						0.44
					),
					_environment_card(
						Vector3(-0.78, 0.18, 0.56),
						Color(1.0, 0.985, 0.95, 1.0),
						220.0,
						10.0,
						0.62,
						0.48
					),
					_environment_card(
						Vector3(-0.10, -0.70, 0.70),
						Color(1.0, 0.90, 0.80, 1.0),
						42.0,
						6.0,
						0.28,
						0.22
					),
				],
				"blocker_local_dir": Vector3(-0.26, -0.30, 0.92),
				"blocker_power": 10.0,
				"blocker_strength": 0.30,
			}
		GemVisualResource.OPTICS_ENVIRONMENT_GEM_BOOTH:
			return {
				"sky_low": Color(0.06, 0.07, 0.09, 1.0),
				"sky_top": Color(0.16, 0.18, 0.22, 1.0),
				"horizon": Color(0.36, 0.30, 0.24, 1.0),
				"ground_dark": Color(0.012, 0.010, 0.010, 1.0),
				"ground_lift": Color(0.05, 0.04, 0.03, 1.0),
				"cards": [
					_environment_card(
						Vector3(0.00, 0.36, 0.94),
						Color(1.0, 0.985, 0.96, 1.0),
						900.0,
						14.0,
						3.8,
						2.4
					),
					_environment_card(
						Vector3(0.86, 0.08, 0.50),
						Color(1.0, 0.96, 0.92, 1.0),
						160.0,
						8.0,
						0.48,
						0.38
					),
					_environment_card(
						Vector3(-0.72, 0.10, 0.62),
						Color(0.92, 0.96, 1.0, 1.0),
						120.0,
						8.0,
						0.44,
						0.36
					),
				],
				"blocker_local_dir": Vector3(-0.14, -0.24, 0.96),
				"blocker_power": 9.0,
				"blocker_strength": 0.16,
			}
		_:
			return {
				"sky_low": Color(0.12, 0.15, 0.20, 1.0),
				"sky_top": Color(0.28, 0.33, 0.42, 1.0),
				"horizon": Color(0.62, 0.48, 0.32, 1.0),
				"ground_dark": Color(0.015, 0.012, 0.010, 1.0),
				"ground_lift": Color(0.08, 0.06, 0.04, 1.0),
				"cards": [
					_environment_card(
						Vector3(0.00, 0.24, 0.97),
						Color(1.0, 0.96, 0.88, 1.0),
						900.0,
						90.0,
						4.6,
						2.0
					),
					_environment_card(
						Vector3(0.56, 0.18, 0.80),
						Color(0.95, 0.92, 0.98, 1.0),
						48.0,
						14.0,
						0.42,
						0.26
					),
					_environment_card(
						Vector3(-0.74, 0.14, 0.62),
						Color(1.0, 0.99, 0.97, 1.0),
						64.0,
						18.0,
						0.34,
						0.20
					),
				],
				"blocker_local_dir": Vector3(-0.18, -0.30, 0.94),
				"blocker_power": 10.0,
				"blocker_strength": 0.18,
			}


func _environment_card(
	local_dir: Vector3,
	color: Color,
	sharp_power: float,
	broad_power: float,
	sharp_strength: float,
	broad_strength: float,
) -> Dictionary:
	return {
		"local_dir": local_dir.normalized(),
		"color": color,
		"sharp_power": sharp_power,
		"broad_power": broad_power,
		"sharp_strength": sharp_strength,
		"broad_strength": broad_strength,
	}


func _build_environment_setup(light_dir: Vector3, request: Dictionary, visual: GemVisualResource) -> Dictionary:
	var lighting_uv: Vector2 = request.get("lighting_uv", Vector2.ZERO)
	var profile := _resolve_environment_profile(visual)
	var side_axis := light_dir.cross(Vector3.UP)
	if side_axis.length_squared() <= 0.0001:
		side_axis = light_dir.cross(Vector3.RIGHT)
	side_axis = side_axis.normalized()
	var key_dir := (
		light_dir
		+ side_axis * lighting_uv.x * 0.65
		+ Vector3.UP * (-lighting_uv.y) * 0.30
	).normalized()
	var up_axis := side_axis.cross(key_dir).normalized()
	var env_rotation := deg_to_rad(visual.optics_environment_rotation_degrees)
	var rot_cos := cos(env_rotation)
	var rot_sin := sin(env_rotation)
	var rotated_right := side_axis * rot_cos + up_axis * rot_sin
	var rotated_up := up_axis * rot_cos - side_axis * rot_sin
	var cards: Array[Dictionary] = []
	for raw_card in profile.get("cards", []):
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = raw_card
		var local_dir: Vector3 = source.get("local_dir", Vector3(0.0, 0.0, 1.0))
		var resolved := source.duplicate(true)
		resolved["dir"] = (
			rotated_right * local_dir.x
			+ rotated_up * local_dir.y
			+ key_dir * local_dir.z
		).normalized()
		cards.append(resolved)
	var blocker_local: Vector3 = profile.get("blocker_local_dir", Vector3(-0.15, -0.20, 1.0))
	return {
		"sky_low": profile.get("sky_low", Color(0.12, 0.15, 0.20, 1.0)),
		"sky_top": profile.get("sky_top", Color(0.28, 0.33, 0.42, 1.0)),
		"horizon": profile.get("horizon", Color(0.62, 0.48, 0.32, 1.0)),
		"ground_dark": profile.get("ground_dark", Color(0.015, 0.012, 0.010, 1.0)),
		"ground_lift": profile.get("ground_lift", Color(0.08, 0.06, 0.04, 1.0)),
		"cards": cards,
		"blocker_dir": (
			rotated_right * blocker_local.x
			+ rotated_up * blocker_local.y
			+ key_dir * blocker_local.z
		).normalized(),
		"blocker_power": profile.get("blocker_power", 10.0),
		"blocker_strength": float(profile.get("blocker_strength", 0.0)) * (1.0 + lighting_uv.length() * 0.08),
	}


func _build_trace_flags(visual: GemVisualResource) -> Dictionary:
	return {
		"is_patterned_opaque": visual.material_mode == GemVisualResource.MATERIAL_MODE_PATTERNED_OPAQUE,
		"has_volume_sampling": visual.volume_pattern_mix > 0.001
			and visual.volume_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE,
		"has_surface_material": (
			visual.surface_pattern_mix > 0.001
			and visual.surface_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE
		) or (visual.use_texture and visual.color_texture != null),
		"has_reactive": visual.reactive_strength > 0.0001
			and visual.reactive_effect_type != GemVisualResource.MATERIAL_REACTIVE_NONE,
		"transmission_factor": GemMaterialSamplerScript.transmission_factor(visual),
		"cloudiness": clampf(
			visual.optics_scattering_strength * 1.2
			+ visual.optics_surface_roughness * 0.3
			+ visual.translucency * 0.1,
			0.0,
			0.5
		),
	}


func _build_surface_setup(
	visual: GemVisualResource,
	request: Dictionary,
	light_dir: Vector3,
) -> Dictionary:
	var environment_setup: Dictionary = request.get("environment_setup", {})
	var scatter_color := visual.optics_scattering_color
	if scatter_color.a <= 0.001:
		scatter_color = visual.translucency_color if visual.translucency_color.a > 0.001 else visual.base_color
	var highlight_tint := _resolve_highlight_tint(visual)
	return {
		"variant_type": request.get("variant_type", &""),
		"lighting_uv": request.get("lighting_uv", Vector2.ZERO),
		"environment_cards": environment_setup.get("cards", []),
		"scatter_color": scatter_color,
		"highlight_tint": highlight_tint,
		"specular_color": highlight_tint,
		"rim_tint": visual.rim_color if visual.rim_color.a > 0.001 else Color.WHITE,
		"optics_ior_mid": _wavelength_ior(visual, 0.5),
		"default_light_dir": light_dir,
	}


func _compute_surface_lighting(
	position: Vector3,
	normal: Vector3,
	zone: StringName,
	light_dir: Vector3,
	view_dir: Vector3,
	radius: float,
	visual: GemVisualResource,
	request: Dictionary,
	texture_image: Image = null,
) -> Vector3:
	var trace_flags: Dictionary = request.get("trace_flags", {})
	var surface_setup: Dictionary = request.get("surface_setup", {})
	var variant_type: StringName = surface_setup.get("variant_type", request.get("variant_type", &""))
	var lighting_uv: Vector2 = surface_setup.get("lighting_uv", request.get("lighting_uv", Vector2.ZERO))
	var environment_setup: Dictionary = request.get("environment_setup", {})
	var environment_cards: Array = surface_setup.get(
		"environment_cards",
		environment_setup.get("cards", [])
	)
	var body_color := _resolve_body_color(position, normal, radius, visual)
	var object_position := position / maxf(radius, 0.0001)
	var uv := Vector2(
		clampf(object_position.x * 0.5 + 0.5, 0.0, 1.0),
		clampf(object_position.y * 0.5 + 0.5, 0.0, 1.0)
	)
	var surface_material := {
		"color": body_color,
		"roughness_mult": 1.0,
		"specular_mult": 1.0,
	}
	if bool(trace_flags.get("has_surface_material", false)):
		surface_material = GemMaterialSamplerScript.apply_surface_material(
			visual,
			body_color,
			uv,
			object_position,
			normal,
			texture_image
		)
	body_color = surface_material.get("color", body_color)
	var reactive_color := Color(0.0, 0.0, 0.0, 0.0)
	var scatter_color: Color = surface_setup.get("scatter_color", visual.optics_scattering_color)
	var highlight_tint: Color = _resolve_highlight_tint(
		visual,
		body_color if body_color.a > 0.001 else Color.TRANSPARENT
	)
	# For strongly absorbing gems, bias specular color toward body color so
	# highlights read as tinted (light-blue for sapphire, light-red for ruby)
	# rather than achromatic grey.  Low-absorption gems (diamond, quartz) keep
	# near-white highlights, matching real dielectric Fresnel behavior.
	var absorption_tint_factor := clampf(visual.optics_absorption_strength * 0.25, 0.0, 0.72)
	var specular_color: Color = highlight_tint.lerp(body_color, absorption_tint_factor)
	var rim_tint: Color = surface_setup.get(
		"rim_tint",
		visual.rim_color if visual.rim_color.a > 0.001 else Color.WHITE
	)
	var face_color := body_color.lerp(specular_color, 0.02 + visual.specular_intensity * 0.02)
	var caustic_base := body_color.lerp(specular_color, 0.12 + visual.hue_dispersion * 0.14 + visual.sparkle_intensity * 0.03)
	var roughness := clampf(
		visual.optics_surface_roughness * float(surface_material.get("roughness_mult", 1.0)),
		0.0,
		1.0
	)
	var specular_mult := float(surface_material.get("specular_mult", 1.0))
	var optics_ior := float(surface_setup.get("optics_ior_mid", _wavelength_ior(visual, 0.5)))
	var effective_light_dir := light_dir
	if variant_type == &"lighting" and radius > 0.0001:
		# Second lighting offset: the same lighting_uv that rotated the global
		# light direction (in GemVisualRegistry._compute_variant_light_dir) now
		# shifts the effective point-light origin, creating per-facet parallax.
		# This double-offset is intentional — it produces richer variation for
		# runtime interpolation between lighting bins.  Corner bins have the
		# most exaggerated combined shift.
		var key_origin := Vector3(
			(light_dir.x + lighting_uv.x * 0.95) * radius * 2.8,
			(light_dir.y - lighting_uv.y * 0.70) * radius * 2.4,
			maxf(light_dir.z, 0.22) * radius * 3.4
		)
		effective_light_dir = (key_origin - position).normalized()
	if bool(trace_flags.get("has_reactive", false)):
		reactive_color = GemMaterialSamplerScript.sample_reactive_color(
			visual,
			object_position,
			normal,
			effective_light_dir,
			view_dir
		)
	var front_alignment := maxf(normal.dot(effective_light_dir), 0.0)
	var back_alignment := maxf(-normal.dot(effective_light_dir), 0.0)
	var front_power := lerpf(18.0, 4.0, roughness)
	var front_strength := pow(front_alignment, front_power) * visual.optics_light_energy * (0.08 + visual.contrast * 0.18)
	var scatter_strength := maxf(visual.optics_scattering_strength, visual.translucency * 0.55)
	var back_strength := pow(back_alignment, 3.2) * visual.optics_light_energy * scatter_strength * 0.08
	# Blinn-Phong specular (matches procedural renderer model).
	var half_vec := (effective_light_dir + view_dir).normalized()
	var spec_alignment := maxf(normal.dot(half_vec), 0.0)
	var spec_power := lerpf(120.0, 16.0, roughness)
	var spec_strength := pow(spec_alignment, spec_power) * visual.optics_light_energy * (0.12 + visual.specular_intensity * 0.52) * specular_mult
	var secondary_light_dir: Vector3 = (Basis(Vector3.UP, deg_to_rad(visual.secondary_light_angle)) * effective_light_dir).normalized()
	var secondary_half: Vector3 = (secondary_light_dir + view_dir).normalized()
	var secondary_alignment := maxf(normal.dot(secondary_half), 0.0)
	var secondary_strength := pow(secondary_alignment, lerpf(96.0, 18.0, roughness)) * visual.secondary_specular * visual.optics_light_energy * 0.16 * specular_mult
	var card_glare_strength := 0.0
	var card_return_strength := 0.0
	var card_fill_strength := 0.0
	for raw_card in environment_cards:
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw_card
		var card_dir: Vector3 = card.get("dir", effective_light_dir)
		var card_front := maxf(normal.dot(card_dir), 0.0)
		if card_front <= 0.0:
			continue
		var card_half := (card_dir + view_dir).normalized()
		var card_spec_alignment := maxf(normal.dot(card_half), 0.0)
		var card_power := lerpf(
			float(card.get("sharp_power", 72.0)),
			maxf(float(card.get("broad_power", 18.0)), 8.0),
			roughness
		)
		var card_energy := lerpf(
			float(card.get("sharp_strength", 0.5)),
			float(card.get("broad_strength", 0.3)),
			roughness
		)
		card_glare_strength += pow(card_spec_alignment, card_power) * card_energy * 0.16
		card_fill_strength += pow(card_front, lerpf(10.0, 3.5, roughness)) * card_energy * 0.05
		var refracted_card := _refract(-card_dir, normal, AIR_IOR, optics_ior)
		if refracted_card.is_zero_approx():
			continue
		var return_alignment := maxf((-refracted_card).dot(view_dir), 0.0)
		var fresnel_in := _fresnel_dielectric(-card_dir, normal, AIR_IOR, optics_ior)
		card_return_strength += pow(return_alignment, lerpf(42.0, 10.0, roughness)) * card_energy * (1.0 - fresnel_in) * (0.24 + visual.extinction * 0.10)
	var planar_light := Vector2(effective_light_dir.x, effective_light_dir.y)
	var normalized_position := Vector2(object_position.x, object_position.y)
	var lateral_mask := 0.5
	var caustic_band := 0.0
	if planar_light.length_squared() > 0.0001:
		var planar_dir := planar_light.normalized()
		var side_alignment := clampf(normalized_position.dot(planar_dir), -1.0, 1.0)
		lateral_mask = clampf(side_alignment * 0.5 + 0.5, 0.0, 1.0)
		caustic_band = exp(-pow((side_alignment - 0.24) / 0.46, 2.0)) * maxf(front_alignment, 0.0)
	if variant_type == &"lighting":
		front_strength *= lerpf(0.80, 1.16, lateral_mask)
		spec_strength *= lerpf(0.50, 1.45, lateral_mask)
		back_strength *= lerpf(0.28, 0.52, 1.0 - lateral_mask)
	var zone_multiplier := _zone_light_multiplier(zone, visual)
	var zone_surface := _resolve_zone_surface_scales(zone, visual)
	front_strength *= zone_multiplier * float(zone_surface.get("front", 1.0))
	back_strength *= float(zone_surface.get("back", 1.0))
	spec_strength += card_glare_strength * lerpf(zone_multiplier, 1.0 + visual.sparkle_intensity * 0.10, 0.4)
	spec_strength *= lerpf(zone_multiplier, 1.0 + visual.sparkle_intensity * 0.14, 0.35)
	spec_strength *= float(zone_surface.get("spec", 1.0))
	secondary_strength *= lerpf(zone_multiplier, 1.0, 0.35) * float(zone_surface.get("spec", 1.0))
	var caustic_color := body_color.lerp(caustic_base, 0.42 + visual.hue_dispersion * 0.20)
	var body_strength := (
		0.006
		+ scatter_strength * 0.10
		+ roughness * 0.03
		+ visual.translucency * 0.02
		+ card_fill_strength
	) * visual.optics_light_energy * lerpf(0.82, 1.02, front_alignment)
	if variant_type == &"lighting":
		body_strength *= lerpf(0.84, 1.08, lateral_mask)
	body_strength *= lerpf(0.82, 1.04, zone_multiplier - 1.0 + 0.5) * float(zone_surface.get("body", 1.0))
	var caustic_strength := (
		card_return_strength
		+ caustic_band * (0.018 + visual.sparkle_intensity * 0.012)
	) * visual.optics_light_energy * float(zone_surface.get("caustic", 1.0))
	var sparkle_strength := maxf(pow(spec_alignment, lerpf(260.0, 48.0, roughness)) - visual.sparkle_threshold, 0.0) * visual.sparkle_intensity * visual.optics_light_energy * 2.4 * specular_mult
	var rim_alignment := maxf(1.0 - maxf(normal.dot(view_dir), 0.0), 0.0)
	var rim_strength := pow(rim_alignment, lerpf(5.8, 2.2, visual.rim_power / 5.0)) * visual.rim_intensity * visual.optics_light_energy * 0.26
	var facet_glare_strength := 0.0
	match visual.material_mode:
		GemVisualResource.MATERIAL_MODE_PATTERNED_OPAQUE:
			facet_glare_strength = (
				pow(spec_alignment, lerpf(92.0, 18.0, roughness)) * 0.46
				+ card_glare_strength * 0.72
				+ pow(front_alignment, lerpf(12.0, 4.2, roughness)) * 0.08
			) * visual.optics_light_energy * (0.16 + visual.specular_intensity * 0.32) * specular_mult
			face_color = body_color.lerp(specular_color, 0.08)
			front_strength *= 0.18
			back_strength = 0.0
			spec_strength *= 0.34
			secondary_strength *= 0.24
			sparkle_strength = 0.0
			caustic_strength = 0.0
			rim_strength *= 0.44
			body_strength = 0.12 + front_alignment * 0.11 + zone_multiplier * 0.02
		GemVisualResource.MATERIAL_MODE_PATTERNED_TRANSLUCENT:
			front_strength *= 0.72
			spec_strength *= 0.44
			secondary_strength *= 0.34
			sparkle_strength *= 0.18
			caustic_strength *= 0.2
			body_strength *= 1.18
	# Dampen surface lighting for high-absorption gems — their appearance should
	# be dominated by internal spectral light return, not surface fill terms.
	# Fresnel surface reflection (~4-8%) stays implicitly in the spec terms;
	# this dampens the body fill, card return, and caustic extras that were
	# historically over-weighted to compensate for weak mirrored-pavilion TIR.
	var surface_absorption_scale := 1.0 / (1.0 + visual.optics_absorption_strength * 0.42)
	return Vector3(
		face_color.r * front_strength + scatter_color.r * back_strength + specular_color.r * (spec_strength + secondary_strength + sparkle_strength + facet_glare_strength) + rim_tint.r * rim_strength + caustic_color.r * caustic_strength + body_color.r * body_strength + reactive_color.r,
		face_color.g * front_strength + scatter_color.g * back_strength + specular_color.g * (spec_strength + secondary_strength + sparkle_strength + facet_glare_strength) + rim_tint.g * rim_strength + caustic_color.g * caustic_strength + body_color.g * body_strength + reactive_color.g,
		face_color.b * front_strength + scatter_color.b * back_strength + specular_color.b * (spec_strength + secondary_strength + sparkle_strength + facet_glare_strength) + rim_tint.b * rim_strength + caustic_color.b * caustic_strength + body_color.b * body_strength + reactive_color.b
	) * surface_absorption_scale


func _compute_interface_highlight(
	visual: GemVisualResource,
	zone: StringName,
	normal: Vector3,
	light_dir: Vector3,
	request: Dictionary,
	view_dir: Vector3,
	wavelength_t: float,
) -> float:
	var roughness := clampf(visual.optics_surface_roughness, 0.0, 1.0)
	var cards: Array = request.get("environment_setup", {}).get("cards", [])
	var highlight_tint: Color = request.get("surface_setup", {}).get(
		"highlight_tint",
		_resolve_highlight_tint(visual)
	)
	if cards.is_empty():
		cards = [{"dir": light_dir, "sharp_strength": 1.0, "broad_strength": 0.4, "sharp_power": 420.0, "broad_power": 46.0}]
	var total := 0.0
	for raw_card in cards:
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw_card
		var card_dir: Vector3 = card.get("dir", light_dir)
		var card_half := (card_dir + view_dir).normalized()
		var spec_alignment := maxf(normal.dot(card_half), 0.0)
		if spec_alignment <= 0.0:
			continue
		var core_power := lerpf(maxf(float(card.get("sharp_power", 420.0)), 240.0), 48.0, roughness)
		var halo_power := lerpf(maxf(float(card.get("broad_power", 46.0)), 24.0), 10.0, roughness)
		var card_energy := lerpf(
			float(card.get("sharp_strength", 1.0)),
			float(card.get("broad_strength", 0.4)),
			roughness
		)
		var core := pow(spec_alignment, core_power) * visual.optics_light_energy * card_energy * (
			0.020
			+ visual.sparkle_intensity * 0.030
			+ visual.specular_intensity * 0.020
		)
		var halo := pow(spec_alignment, halo_power) * visual.optics_light_energy * card_energy * (
			0.006
			+ visual.specular_intensity * 0.010
		)
		total += core + halo
	return _sample_color_wavelength(highlight_tint, wavelength_t) * total * float(
		_resolve_zone_surface_scales(zone, visual).get("interface", 1.0)
	)


func _resolve_view_angles(request: Dictionary, visual: GemVisualResource) -> Vector2:
	var variant_type: StringName = request.get("variant_type", &"")
	if variant_type == &"rotation":
		return Vector2(
			float(request.get("view_pitch_degrees", visual.optics_rotation_view_pitch_degrees)),
			float(request.get("view_yaw_degrees", visual.optics_rotation_view_yaw_degrees))
		)
	if variant_type == &"lighting":
		return Vector2(
			float(request.get("view_pitch_degrees", visual.optics_lighting_view_pitch_degrees)),
			float(request.get("view_yaw_degrees", visual.optics_lighting_view_yaw_degrees))
		)
	return Vector2(
		float(request.get("view_pitch_degrees", visual.optics_rotation_view_pitch_degrees)),
		float(request.get("view_yaw_degrees", visual.optics_rotation_view_yaw_degrees))
	)


func _fresnel_dielectric(dir: Vector3, normal: Vector3, eta_i: float, eta_t: float) -> float:
	var cos_i := clampf(-dir.dot(normal), -1.0, 1.0)
	var r0 := pow((eta_i - eta_t) / maxf(eta_i + eta_t, 0.0001), 2.0)
	return clampf(r0 + (1.0 - r0) * pow(1.0 - absf(cos_i), 5.0), 0.0, 1.0)


func _refract(dir: Vector3, normal: Vector3, eta_i: float, eta_t: float) -> Vector3:
	var eta := eta_i / maxf(eta_t, 0.0001)
	var cos_i := clampf(-dir.dot(normal), -1.0, 1.0)
	var k := 1.0 - eta * eta * (1.0 - cos_i * cos_i)
	if k < 0.0:
		return Vector3.ZERO
	return (dir * eta + normal * (eta * cos_i - sqrt(k))).normalized()


func _build_refraction_components(
	dir: Vector3,
	normal: Vector3,
	trace_data: Dictionary,
	visual: GemVisualResource,
	wavelength_t: float,
	eta_i: float,
	eta_t: float,
	is_entry_hit: bool,
) -> Array[Dictionary]:
	var components: Array[Dictionary] = []
	if not is_entry_hit or eta_i > AIR_IOR + 0.0001 or visual.optics_birefringence_strength <= 0.0001:
		var single_dir := _refract(dir, normal, eta_i, eta_t)
		if not single_dir.is_zero_approx():
			components.append({
				"dir": single_dir,
				"ior": eta_t,
				"weight": 1.0,
			})
		return components
	var optic_axis: Vector3 = trace_data.get("optic_axis", Vector3.UP)
	if optic_axis.is_zero_approx():
		optic_axis = Vector3.UP
	optic_axis = optic_axis.normalized()
	var base_ior := eta_t
	var split := visual.optics_birefringence_strength
	var ordinary_ior := maxf(base_ior + split, 1.0)
	var extraordinary_ior := maxf(
		_compute_extraordinary_ior(base_ior, visual.optics_birefringence_strength, optic_axis, dir, normal),
		1.0
	)
	var ordinary_dir := _refract(dir, normal, eta_i, ordinary_ior)
	var extraordinary_dir := _refract(dir, normal, eta_i, extraordinary_ior)
	if not ordinary_dir.is_zero_approx():
		components.append({
			"dir": ordinary_dir,
			"ior": ordinary_ior,
			"weight": 0.5,
		})
	if not extraordinary_dir.is_zero_approx():
		components.append({
			"dir": extraordinary_dir,
			"ior": extraordinary_ior,
			"weight": 0.5,
		})
	if components.is_empty():
		var fallback_dir := _refract(dir, normal, eta_i, eta_t)
		if not fallback_dir.is_zero_approx():
			components.append({
				"dir": fallback_dir,
				"ior": eta_t,
				"weight": 1.0,
			})
	elif components.size() == 1:
		components[0]["weight"] = 1.0
	return components


func _compute_extraordinary_ior(
	base_ior: float,
	birefringence_strength: float,
	optic_axis: Vector3,
	dir: Vector3,
	normal: Vector3,
) -> float:
	var seed_dir := _refract(dir, normal, AIR_IOR, base_ior)
	if seed_dir.is_zero_approx():
		seed_dir = (-normal).normalized()
	var ordinary_ior := maxf(base_ior + birefringence_strength, 1.0)
	var extraordinary_axis_ior := maxf(base_ior - birefringence_strength, 1.0)
	var cos_theta := clampf(absf(seed_dir.normalized().dot(optic_axis)), 0.0, 1.0)
	var sin_sq := 1.0 - cos_theta * cos_theta
	# Standard uniaxial crystal formula: along optic axis → ordinary index,
	# perpendicular to optic axis → extraordinary index.
	var inv_sq := (
		cos_theta * cos_theta / maxf(ordinary_ior * ordinary_ior, 0.0001)
		+ sin_sq / maxf(extraordinary_axis_ior * extraordinary_axis_ior, 0.0001)
	)
	return sqrt(1.0 / maxf(inv_sq, 0.0001))


func _resolve_optic_axis(visual: GemVisualResource) -> Vector3:
	var axis := visual.optics_optic_axis
	if axis.is_zero_approx():
		return Vector3.UP
	return axis.normalized()


func _build_spectral_samples(visual: GemVisualResource) -> Array[Dictionary]:
	var wavelengths := HIGH_FIRE_WAVELENGTH_SAMPLES \
		if visual.optics_dispersion >= 0.02 or visual.sparkle_intensity >= 0.8 \
		else LOW_FIRE_WAVELENGTH_SAMPLES
	var normalizer := Vector3.ZERO
	var raw_weights: Array[Vector3] = []
	for wavelength_t in wavelengths:
		var basis := _spectral_rgb_basis(float(wavelength_t))
		raw_weights.append(basis)
		normalizer += basis
	normalizer.x = maxf(normalizer.x, 0.0001)
	normalizer.y = maxf(normalizer.y, 0.0001)
	normalizer.z = maxf(normalizer.z, 0.0001)
	var normalized_samples: Array[Dictionary] = []
	for i in wavelengths.size():
		var raw: Vector3 = raw_weights[i]
		normalized_samples.append({
			"t": float(wavelengths[i]),
			"weight": Vector3(
				raw.x / normalizer.x,
				raw.y / normalizer.y,
				raw.z / normalizer.z
			),
		})
	return normalized_samples


func _spectral_rgb_basis(wavelength_t: float) -> Vector3:
	# Attempt to approximate CIE color matching functions for spectral→RGB mapping.
	# t=0 maps to ~700nm (red), t=0.5 to ~550nm (green), t=1.0 to ~380nm (violet).
	# Critical: the violet end must NOT have large red contribution — real L-cone
	# response at 380-420nm is tiny (~0.02-0.05), not 0.5+.
	var t := clampf(wavelength_t, 0.0, 1.0)
	if t < 0.16:
		return Vector3(1.0, lerpf(0.02, 0.34, t / 0.16), 0.0)
	if t < 0.32:
		var local_t := (t - 0.16) / 0.16
		return Vector3(lerpf(1.0, 0.42, local_t), lerpf(0.34, 0.92, local_t), lerpf(0.0, 0.04, local_t))
	if t < 0.5:
		var local_t := (t - 0.32) / 0.18
		return Vector3(lerpf(0.42, 0.08, local_t), 1.0, lerpf(0.04, 0.14, local_t))
	if t < 0.68:
		var local_t := (t - 0.5) / 0.18
		return Vector3(lerpf(0.08, 0.0, local_t), lerpf(1.0, 0.72, local_t), lerpf(0.14, 1.0, local_t))
	if t < 0.84:
		var local_t := (t - 0.68) / 0.16
		return Vector3(lerpf(0.0, 0.02, local_t), lerpf(0.72, 0.12, local_t), 1.0)
	# Violet tail: minimal red response (CIE L-cone drops to ~0.02 at 400nm).
	var tail_t := (t - 0.84) / 0.16
	return Vector3(lerpf(0.02, 0.05, tail_t), 0.0, lerpf(1.0, 0.45, tail_t))


func _sample_color_wavelength(color: Color, wavelength_t: float) -> float:
	var basis := _spectral_rgb_basis(wavelength_t)
	var weight_sum := maxf(basis.x + basis.y + basis.z, 0.0001)
	return clampf((color.r * basis.x + color.g * basis.y + color.b * basis.z) / weight_sum, 0.0, 8.0)


func _resolve_body_color(
	position: Vector3,
	normal: Vector3,
	radius: float,
	visual: GemVisualResource,
) -> Color:
	var body_color := visual.base_color
	if visual.gradient_strength > 0.001 and visual.gradient_color.a > 0.001 and radius > 0.0001:
		var normalized_position := Vector2(position.x, position.y) / radius
		var gradient_mix := 0.0
		match visual.gradient_mode:
			GemVisualResource.GRADIENT_MODE_RADIAL:
				gradient_mix = clampf(normalized_position.length(), 0.0, 1.0)
			GemVisualResource.GRADIENT_MODE_RADIAL_INVERSE:
				gradient_mix = 1.0 - clampf(normalized_position.length(), 0.0, 1.0)
			_:
				var gradient_angle := deg_to_rad(visual.gradient_angle_degrees)
				var gradient_dir := Vector2(cos(gradient_angle), -sin(gradient_angle)).normalized()
				gradient_mix = clampf(normalized_position.dot(gradient_dir) * 0.5 + 0.5, 0.0, 1.0)
		body_color = body_color.lerp(visual.gradient_color, gradient_mix * visual.gradient_strength)
	if visual.phenomenon_strength > 0.001 and visual.phenomenon_color.a > 0.001:
		var phenomenon_angle := deg_to_rad(visual.phenomenon_angle_degrees)
		var phenomenon_dir := Vector2(cos(phenomenon_angle), sin(phenomenon_angle)).normalized()
		var facet_dir := Vector2(normal.x, -normal.y)
		if not facet_dir.is_zero_approx():
			var phenomenon_mix := clampf(facet_dir.normalized().dot(phenomenon_dir) * 0.5 + 0.5, 0.0, 1.0)
			phenomenon_mix = pow(phenomenon_mix, maxf(visual.phenomenon_sharpness, 0.01))
			body_color = body_color.lerp(visual.phenomenon_color, phenomenon_mix * visual.phenomenon_strength)
	if radius > 0.0001 and visual.volume_pattern_mix > 0.001 and visual.volume_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE:
		var volume_material: Dictionary = GemMaterialSamplerScript.sample_volume_material(visual, position / radius)
		var volume_mix := visual.volume_pattern_mix * (
			0.32 if visual.material_mode == GemVisualResource.MATERIAL_MODE_PATTERNED_TRANSLUCENT else 0.16
		)
		body_color = body_color.lerp(volume_material.get("color", body_color), clampf(volume_mix, 0.0, 1.0))
	return body_color


func _resolve_highlight_tint(visual: GemVisualResource, body_color: Color = Color.TRANSPARENT) -> Color:
	var tint_source := body_color
	if tint_source.a <= 0.001:
		tint_source = visual.optics_absorption_color
	if tint_source.a <= 0.001:
		tint_source = visual.depth_tint if visual.depth_tint.a > 0.001 else visual.base_color
	var tint_rgb := Vector3(
		maxf(tint_source.r, 0.0001),
		maxf(tint_source.g, 0.0001),
		maxf(tint_source.b, 0.0001)
	)
	var max_channel := maxf(tint_rgb.x, maxf(tint_rgb.y, tint_rgb.z))
	if max_channel > 0.0001:
		tint_rgb /= max_channel
	# Wider pastel range so strongly colored gems get visible tint even on highlights.
	var pastel_tint := Vector3(
		lerpf(0.42, 0.96, tint_rgb.x),
		lerpf(0.42, 0.96, tint_rgb.y),
		lerpf(0.42, 0.96, tint_rgb.z)
	)
	var tint_strength := clampf(
		0.08
		+ minf(visual.optics_absorption_strength, 3.0) * 0.090
		+ maxf(visual.saturation_boost, 0.0) * 0.22
		+ visual.contrast * 0.06,
		0.08,
		0.56
	)
	if visual.optics_absorption_strength <= 0.35 and visual.hue_dispersion > 0.05:
		tint_strength *= 0.45
	elif visual.optics_absorption_strength <= 0.6 and maxf(visual.saturation_boost, 0.0) <= 0.05:
		tint_strength *= 0.65
	var resolved := Vector3.ONE.lerp(pastel_tint, tint_strength)
	return Color(resolved.x, resolved.y, resolved.z, 1.0)


func _sample_segment_volume(
	visual: GemVisualResource,
	start_pos: Vector3,
	end_pos: Vector3,
	radius: float,
) -> Dictionary:
	if visual == null or radius <= 0.0001:
		return {}
	if visual.volume_pattern_mix <= 0.0001 or visual.volume_pattern_type == GemVisualResource.MATERIAL_PATTERN_NONE:
		return {}
	var sample_positions := [0.22, 0.5, 0.78]
	var sum_r := 0.0
	var sum_g := 0.0
	var sum_b := 0.0
	var sum_a := 0.0
	var sum_absorption := 0.0
	var sum_scattering := 0.0
	for t in sample_positions:
		var object_position := start_pos.lerp(end_pos, t) / radius
		var sample: Dictionary = GemMaterialSamplerScript.sample_volume_material(visual, object_position)
		var sample_color: Color = sample.get("color", visual.base_color)
		sum_r += sample_color.r
		sum_g += sample_color.g
		sum_b += sample_color.b
		sum_a += sample_color.a
		sum_absorption += float(sample.get("absorption_mult", 1.0))
		sum_scattering += float(sample.get("scattering_mult", 1.0))
	var count := float(sample_positions.size())
	return {
		"color": Color(sum_r / count, sum_g / count, sum_b / count, sum_a / count),
		"absorption_mult": sum_absorption / count,
		"scattering_mult": sum_scattering / count,
	}


func _zone_light_multiplier(zone: StringName, visual: GemVisualResource) -> float:
	var contrast := clampf(visual.brilliance_contrast, 0.0, 1.0)
	match zone:
		&"table":
			return 1.0 + contrast * 0.28
		&"star":
			return 1.0 + contrast * 0.16
		&"girdle":
			return 1.0 - contrast * 0.18
		&"pavilion", &"culet":
			return 1.0 - visual.extinction * 0.42
		_:
			return 1.0


func _resolve_zone_surface_scales(zone: StringName, visual: GemVisualResource) -> Dictionary:
	match zone:
		&"table":
			return {
				"front": 0.56,
				"back": 0.90,
				"spec": 0.62,
				"body": 0.92,
				"caustic": 1.06,
				"interface": 0.48,
			}
		&"rose_center":
			return {
				"front": 0.54,
				"back": 0.92,
				"spec": 0.60,
				"body": 0.94,
				"caustic": 1.08,
				"interface": 0.50,
			}
		&"rose":
			return {
				"front": 0.72,
				"back": 1.0,
				"spec": 0.76,
				"body": 1.08,
				"caustic": 1.04,
				"interface": 0.72,
			}
		&"girdle":
			return {
				"front": 0.78,
				"back": 1.0,
				"spec": 0.80,
				"body": 1.06,
				"caustic": 1.02,
				"interface": 0.80,
			}
		&"step":
			return {
				"front": 0.80,
				"back": 1.0,
				"spec": 0.82,
				"body": 1.06,
				"caustic": 1.03,
				"interface": 0.78,
			}
		&"star":
			return {
				"front": 0.68,
				"back": 1.0,
				"spec": 0.72,
				"body": 0.96,
				"caustic": 1.02,
				"interface": 0.70,
			}
		&"bezel":
			return {
				"front": 0.76,
				"back": 1.0,
				"spec": 0.78,
				"body": 0.98,
				"caustic": 1.02,
				"interface": 0.76,
			}
		_:
			return {
				"front": 1.0,
				"back": 1.0,
				"spec": 1.0,
				"body": 1.0,
				"caustic": 1.0,
				"interface": 1.0,
			}


func _apply_output_grade(color: Vector3, visual: GemVisualResource) -> Vector3:
	var exposure := (
		0.72
		+ visual.optics_light_energy * 0.08
		+ visual.specular_intensity * 0.06
		+ visual.sparkle_intensity * 0.008
	)
	match visual.material_mode:
		GemVisualResource.MATERIAL_MODE_PATTERNED_OPAQUE:
			exposure *= 0.60
		GemVisualResource.MATERIAL_MODE_PATTERNED_TRANSLUCENT:
			exposure *= 0.82
	var graded := color * exposure
	graded = Vector3(
		_apply_aces_channel(graded.x),
		_apply_aces_channel(graded.y),
		_apply_aces_channel(graded.z)
	)
	var range_compression := clampf(
		0.04
		+ visual.specular_intensity * 0.03
		+ visual.contrast * 0.05
		+ minf(visual.sparkle_intensity, 1.2) * 0.01,
		0.04,
		0.14
	)
	graded = _compress_luma_range(graded, range_compression)
	var highlight_rolloff := clampf(
		0.08
		+ visual.specular_intensity * 0.08
		+ minf(visual.sparkle_intensity, 1.2) * 0.03,
		0.08,
		0.22
	)
	graded = _soft_highlight_rolloff(graded, highlight_rolloff)
	var saturation := clampf(
		visual.saturation_boost
		+ visual.contrast * 0.08
		+ visual.hue_dispersion * 0.16
		+ visual.specular_intensity * 0.03
		+ minf(visual.optics_absorption_strength, 3.0) * 0.022
		+ 0.01,
		-0.2,
		0.48
	)
	graded = _adjust_saturation(graded, saturation)
	# Apply a second saturation pass after gamma to counteract gamma's
	# expansion of dark channels (which visually desaturates colored gems).
	var post_gamma := Vector3(
		clampf(pow(maxf(graded.x, 0.0), 1.0 / 2.2), 0.0, 1.0),
		clampf(pow(maxf(graded.y, 0.0), 1.0 / 2.2), 0.0, 1.0),
		clampf(pow(maxf(graded.z, 0.0), 1.0 / 2.2), 0.0, 1.0)
	)
	post_gamma = _soft_highlight_rolloff(post_gamma, highlight_rolloff * 0.5)
	# Body-color saturation floor: for absorbing gems, push desaturated pixels
	# toward the gem's dominant hue.  Short internal paths (star/bezel facets)
	# produce nearly achromatic results because absorption needs material
	# thickness to develop color.  This ensures the gem always reads as its
	# body color, matching how real colored gems appear even in thin sections.
	var body_push_strength := clampf(visual.optics_absorption_strength * 0.18, 0.0, 0.55)
	if body_push_strength > 0.01:
		var body_hue := Vector3(visual.base_color.r, visual.base_color.g, visual.base_color.b)
		var body_hue_len := body_hue.length()
		if body_hue_len > 0.001:
			body_hue /= body_hue_len
			var pg_len := post_gamma.length()
			if pg_len > 0.001:
				var pg_dir := post_gamma / pg_len
				# Measure how far from the body hue this pixel is.
				var hue_distance := clampf((pg_dir - body_hue).length() * 0.7, 0.0, 1.0)
				post_gamma = post_gamma.lerp(body_hue * pg_len, body_push_strength * hue_distance)
	var post_sat := clampf(
		0.01
		+ minf(visual.optics_absorption_strength, 2.5) * 0.016
		+ maxf(visual.saturation_boost, 0.0) * 0.10,
		0.01,
		0.08
	)
	return _adjust_saturation(post_gamma, post_sat)


func _clean_alpha_edges(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return
	var source: Image = image.duplicate()
	for y in height:
		for x in width:
			var pixel: Color = source.get_pixel(x, y)
			if pixel.a <= 0.0001:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			if pixel.a >= 0.995:
				continue
			var neighbor_sum := Vector3.ZERO
			var neighbor_weight := 0.0
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or nx >= width or ny < 0 or ny >= height:
						continue
					var neighbor: Color = source.get_pixel(nx, ny)
					if neighbor.a <= pixel.a + 0.05:
						continue
					var weight: float = neighbor.a / float(abs(ox) + abs(oy) + 1)
					neighbor_sum += Vector3(neighbor.r, neighbor.g, neighbor.b) * weight
					neighbor_weight += weight
			var cleaned_rgb := Vector3(pixel.r, pixel.g, pixel.b)
			if neighbor_weight > 0.0001:
				var neighbor_rgb := neighbor_sum / neighbor_weight
				var mix_amount := clampf((1.0 - pixel.a) * 0.78, 0.0, 0.92)
				cleaned_rgb = cleaned_rgb.lerp(neighbor_rgb, mix_amount)
			if pixel.a < 0.03:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			image.set_pixel(x, y, Color(cleaned_rgb.x, cleaned_rgb.y, cleaned_rgb.z, pixel.a))


func _apply_aces_channel(value: float) -> float:
	var v := maxf(value, 0.0)
	return clampf((v * (ACES_A * v + ACES_B)) / (v * (ACES_C * v + ACES_D) + ACES_E), 0.0, 1.0)


func _resolve_max_trace_bounces(request: Dictionary) -> int:
	return clampi(int(request.get("max_trace_bounces", MAX_TRACE_BOUNCES)), 1, MAX_OVERRIDE_TRACE_BOUNCES)


func _compress_luma_range(color: Vector3, amount: float) -> Vector3:
	if amount <= 0.0001:
		return color
	var luma := color.dot(Vector3(0.2126, 0.7152, 0.0722))
	var pivot := 0.46
	var compressed_luma := pivot + (luma - pivot) * (1.0 - amount * 0.78)
	return _set_luma(color, clampf(compressed_luma, 0.0, 1.0))


func _soft_highlight_rolloff(color: Vector3, amount: float) -> Vector3:
	if amount <= 0.0001:
		return color
	var rolled := Vector3.ZERO
	for i in 3:
		var channel := color[i]
		var shoulder := smoothstep(0.58, 1.0, channel)
		rolled[i] = clampf(channel - shoulder * amount * (channel - 0.58), 0.0, 1.0)
	return rolled


func _adjust_saturation(color: Vector3, amount: float) -> Vector3:
	var luma := color.dot(Vector3(0.2126, 0.7152, 0.0722))
	var gray := Vector3.ONE * luma
	return gray.lerp(color, 1.0 + amount)


func _set_luma(color: Vector3, target_luma: float) -> Vector3:
	var current_luma := color.dot(Vector3(0.2126, 0.7152, 0.0722))
	if current_luma <= 0.0001:
		return Vector3.ONE * target_luma
	return Vector3(
		clampf(color.x * (target_luma / current_luma), 0.0, 1.0),
		clampf(color.y * (target_luma / current_luma), 0.0, 1.0),
		clampf(color.z * (target_luma / current_luma), 0.0, 1.0)
	)


func _make_trace_profile(enabled: bool) -> Dictionary:
	if not enabled:
		return {}
	return {
		"trace_view_elapsed_ms": 0.0,
		"primary_intersect_elapsed_ms": 0.0,
		"secondary_intersect_elapsed_ms": 0.0,
		"spectral_trace_elapsed_ms": 0.0,
		"surface_lighting_elapsed_ms": 0.0,
		"volume_sampling_elapsed_ms": 0.0,
		"alpha_cleanup_elapsed_ms": 0.0,
		"encode_elapsed_ms": 0.0,
		"primary_intersect_count": 0,
		"secondary_intersect_count": 0,
		"spectral_trace_count": 0,
		"surface_lighting_count": 0,
		"volume_sampling_count": 0,
		"primary_hit_reuse_count": 0,
	}


func _record_trace_elapsed(profile: Dictionary, field_name: String, start_usec: int) -> void:
	if profile.is_empty() or start_usec <= 0:
		return
	profile[field_name] = float(profile.get(field_name, 0.0)) + float(Time.get_ticks_usec() - start_usec) / 1000.0


func _increment_trace_counter(profile: Dictionary, field_name: String, amount: int = 1) -> void:
	if profile.is_empty():
		return
	profile[field_name] = int(profile.get(field_name, 0)) + amount


func _merge_trace_profile(target: Dictionary, source: Dictionary) -> void:
	if target.is_empty() or source.is_empty():
		return
	for key in source.keys():
		var value = source[key]
		if typeof(value) == TYPE_FLOAT:
			target[key] = float(target.get(key, 0.0)) + float(value)
		elif typeof(value) == TYPE_INT:
			target[key] = int(target.get(key, 0)) + int(value)
		elif not target.has(key):
			target[key] = value
