class_name GemOpticsTracer
extends RefCounted

## CPU traced gemstone bake used by the offline bake job.

const AIR_IOR := 1.00029
const EPSILON := 0.0005
const MAX_TRACE_BOUNCES := 20
const DEFAULT_SAMPLE_COUNT := 2
const VIEW_MARGIN := 1.18
const LOW_FIRE_WAVELENGTH_SAMPLES := [0.0, 0.5, 1.0]
const HIGH_FIRE_WAVELENGTH_SAMPLES := [0.0, 0.16, 0.32, 0.5, 0.68, 0.84, 1.0]
const ACES_A := 2.51
const ACES_B := 0.03
const ACES_C := 2.43
const ACES_D := 0.59
const ACES_E := 0.14
const SAMPLE_PATTERN := [
	Vector2(0.5, 0.5),
	Vector2(0.25, 0.25),
	Vector2(0.75, 0.25),
	Vector2(0.25, 0.75),
	Vector2(0.75, 0.75),
]


static func max_supported_sample_count() -> int:
	return SAMPLE_PATTERN.size()


func trace_to_image(mesh_resource: GemMeshResource, visual: GemVisualResource, request: Dictionary) -> Image:
	if mesh_resource == null or visual == null:
		return null
	var target_size: Vector2i = request.get("trace_size", request.get("draw_size", request.get("target_size", Vector2i.ZERO)))
	if target_size.x <= 0 or target_size.y <= 0:
		return null

	var rotated_trace := _build_rotated_trace(mesh_resource, visual, request)
	var bounds: AABB = rotated_trace.get("bounds", AABB())
	var radius := maxf(float(rotated_trace.get("bounding_radius", 0.0)), 0.25)
	var aspect := float(target_size.x) / maxf(float(target_size.y), 1.0)
	var view_scale := clampf(float(request.get("view_scale", 1.0)), 0.5, 2.0)
	var half_height := maxf(bounds.size.y, radius * 2.0) * VIEW_MARGIN * 0.5 / view_scale
	var half_width := half_height * aspect
	var origin_z := bounds.position.z + bounds.size.z + radius * 2.4
	var dir := Vector3(0.0, 0.0, -1.0)
	var light_dir: Vector3 = request.get("light_dir", Vector3(-0.4, -0.5, 0.75)).normalized()
	if light_dir.is_zero_approx():
		light_dir = Vector3(-0.4, -0.5, 0.75)
	var trace_request: Dictionary = request.duplicate(true)
	trace_request["environment_setup"] = _build_environment_setup(light_dir, trace_request, visual)
	var sample_count := clampi(int(request.get("sample_count", DEFAULT_SAMPLE_COUNT)), 1, max_supported_sample_count())
	var view_dir := -dir
	var spectral_samples := _build_spectral_samples(visual)

	# Bundle all read-only state so worker threads can access it without
	# touching instance variables (the tracer class is stateless).
	var ctx := {
		"target_size": target_size,
		"rotated_trace": rotated_trace,
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
	}

	var thread_count := clampi(
		int(request.get("thread_count", OS.get_processor_count() - 1)),
		1, 32
	)
	# Not worth threading for tiny images or very few rows.
	if target_size.y < thread_count * 4:
		thread_count = 1

	if thread_count <= 1:
		var band := _trace_row_band(ctx, 0, target_size.y)
		return _finalize_traced_image(_band_to_image(band, target_size, 0))

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

	var image := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	for t in threads.size():
		var band: PackedColorArray = threads[t].wait_to_finish()
		var row_start := t * rows_per_thread
		var width := target_size.x
		for i in band.size():
			image.set_pixel(i % width, row_start + i / width, band[i])
	return _finalize_traced_image(image)


## Traces a horizontal band of rows and returns the pixel colors as a flat
## PackedColorArray (row-major, width = ctx.target_size.x).  Each invocation
## is self-contained and safe to call from any thread.
func _trace_row_band(ctx: Dictionary, row_start: int, row_end: int) -> PackedColorArray:
	var target_size: Vector2i = ctx["target_size"]
	var rotated_trace: Dictionary = ctx["rotated_trace"]
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
				var origin := Vector3(u * half_width, v * half_height, origin_z)
				var first_hit := _intersect_scene(origin, dir, rotated_trace, -1)
				if first_hit.is_empty():
					continue
				hit_count += 1.0
				for spectral_sample in spectral_samples:
					var wavelength_t := float(spectral_sample.get("t", 0.5))
					var weight: Vector3 = spectral_sample.get("weight", Vector3.ONE)
					var intensity := _trace_wavelength(
						origin,
						dir,
						rotated_trace,
						visual,
						light_dir,
						request,
						wavelength_t,
						AIR_IOR,
						0,
						-1
					)
					rgb_sum += Vector3(
						weight.x * intensity,
						weight.y * intensity,
						weight.z * intensity
					)
				rgb_sum += _compute_surface_lighting(
					first_hit.position,
					first_hit.normal,
					StringName(first_hit.get("zone", &"")),
					light_dir,
					view_dir,
					radius,
					visual,
					request
				)
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
	return result


## Helper to build an Image from a single full-image band.
func _band_to_image(band: PackedColorArray, target_size: Vector2i, row_start: int) -> Image:
	var image := Image.create(target_size.x, target_size.y, false, Image.FORMAT_RGBA8)
	var width := target_size.x
	for i in band.size():
		image.set_pixel(i % width, row_start + i / width, band[i])
	return image


func _finalize_traced_image(image: Image) -> Image:
	if image == null:
		return null
	_clean_alpha_edges(image)
	return image


func _build_rotated_trace(
	mesh_resource: GemMeshResource,
	visual: GemVisualResource,
	request: Dictionary,
) -> Dictionary:
	var trace_data := mesh_resource.build_trace_data()
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
	var a_list: Array = trace_data.get("triangle_vertices_a", [])
	var b_list: Array = trace_data.get("triangle_vertices_b", [])
	var c_list: Array = trace_data.get("triangle_vertices_c", [])
	var normal_list: Array = trace_data.get("triangle_normals", [])
	var transformed_a: Array[Vector3] = []
	var transformed_b: Array[Vector3] = []
	var transformed_c: Array[Vector3] = []
	var transformed_normals: Array[Vector3] = []
	var bounds := AABB()
	var initialized := false
	for i in a_list.size():
		var a: Vector3 = basis * a_list[i]
		var b: Vector3 = basis * b_list[i]
		var c: Vector3 = basis * c_list[i]
		var normal: Vector3 = (basis * normal_list[i]).normalized()
		transformed_a.append(a)
		transformed_b.append(b)
		transformed_c.append(c)
		transformed_normals.append(normal)
		var tri_bounds := GemMeshResource._triangle_bounds(a, b, c)
		if not initialized:
			bounds = tri_bounds
			initialized = true
		else:
			bounds = bounds.merge(tri_bounds)
	return {
		"triangle_vertices_a": transformed_a,
		"triangle_vertices_b": transformed_b,
		"triangle_vertices_c": transformed_c,
		"triangle_normals": transformed_normals,
		"triangle_zones": trace_data.get("triangle_zones", PackedStringArray()),
		"triangle_facet_indices": trace_data.get("triangle_facet_indices", PackedInt32Array()),
		"bounds": bounds,
		"bounding_radius": mesh_resource.compute_bounding_radius(),
		"optic_axis": (basis * _resolve_optic_axis(visual)).normalized(),
	}


func _trace_wavelength(
	origin: Vector3,
	dir: Vector3,
	trace_data: Dictionary,
	visual: GemVisualResource,
	light_dir: Vector3,
	request: Dictionary,
	wavelength_t: float,
	current_ior: float,
	depth: int,
	last_triangle_index: int,
) -> float:
	if depth >= MAX_TRACE_BOUNCES:
		return _sample_environment(dir, light_dir, request, visual, wavelength_t)
	var hit := _intersect_scene(origin, dir, trace_data, last_triangle_index)
	if hit.is_empty():
		return _sample_environment(dir, light_dir, request, visual, wavelength_t)

	var segment_attenuation := 1.0
	var scattering_contribution := 0.0
	if current_ior > AIR_IOR + 0.0001:
		segment_attenuation = _compute_segment_attenuation(visual, wavelength_t, float(hit.distance))
		scattering_contribution = _compute_segment_scattering(visual, wavelength_t, float(hit.distance))

	var outward_normal: Vector3 = hit.normal
	var shading_normal := outward_normal if hit.front_face else -outward_normal
	var eta_i := current_ior
	var eta_t := AIR_IOR
	if hit.front_face:
		eta_t = _wavelength_ior(visual, wavelength_t)

	var reflection_dir := (dir - 2.0 * dir.dot(shading_normal) * shading_normal).normalized()
	var reflection := _trace_wavelength(
		hit.position + reflection_dir * EPSILON,
		reflection_dir,
		trace_data,
		visual,
		light_dir,
		request,
		wavelength_t,
		eta_i,
		depth + 1,
		hit.triangle_index
	)
	var fresnel := _fresnel_dielectric(dir, shading_normal, eta_i, eta_t)
	var total := reflection * fresnel

	var refraction_components := _build_refraction_components(
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
			var transmitted := _trace_wavelength(
				hit.position + component_dir * EPSILON,
				component_dir,
				trace_data,
				visual,
				light_dir,
				request,
				wavelength_t,
				component_ior,
				depth + 1,
				hit.triangle_index
			)
			var cloudiness := clampf(
				visual.optics_scattering_strength * 1.2
				+ visual.optics_surface_roughness * 0.3
				+ visual.translucency * 0.1,
				0.0,
				0.5
			)
			transmitted *= 1.0 - cloudiness * (0.12 if hit.front_face else 0.06)
			total += transmitted * (1.0 - fresnel) * component_weight

	total *= segment_attenuation
	# Interface highlight only on exterior front-face hits (depth 0).
	# Inside the gem, light interaction is purely Fresnel reflection/refraction.
	if hit.front_face and depth == 0:
		total += _compute_interface_highlight(
			visual,
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
		"zone": StringName(trace_data.get("triangle_zones", PackedStringArray())[nearest_index] if nearest_index < trace_data.get("triangle_zones", PackedStringArray()).size() else &""),
		"front_face": front_face,
	}


func _intersect_scene_bvh(origin: Vector3, dir: Vector3, trace_data: Dictionary, last_triangle_index: int) -> Dictionary:
	var a_list: Array = trace_data.get("triangle_vertices_a", [])
	var b_list: Array = trace_data.get("triangle_vertices_b", [])
	var c_list: Array = trace_data.get("triangle_vertices_c", [])
	var normal_list: Array = trace_data.get("triangle_normals", [])
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
		"zone": StringName(trace_data.get("triangle_zones", PackedStringArray())[nearest_index] if nearest_index < trace_data.get("triangle_zones", PackedStringArray()).size() else &""),
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
	var chroma := clampf(wavelength_t, 0.0, 1.0) * 2.0 - 1.0
	var shaped: float = chroma + signf(chroma) * pow(absf(chroma), 1.65) * 0.34
	return maxf(base + spread * shaped, 1.0)


func _compute_segment_attenuation(visual: GemVisualResource, wavelength_t: float, distance: float) -> float:
	var tint := visual.optics_absorption_color
	if tint.a <= 0.001:
		tint = visual.depth_tint if visual.depth_tint.a > 0.001 else visual.base_color
	var channel_tint := _sample_color_wavelength(tint, wavelength_t)
	var coeff := maxf(1.0 - channel_tint, 0.0) * maxf(visual.optics_absorption_strength, 0.0)
	return exp(-coeff * maxf(distance, 0.0))


func _compute_segment_scattering(visual: GemVisualResource, wavelength_t: float, distance: float) -> float:
	var strength := maxf(visual.optics_scattering_strength, visual.translucency * 0.6)
	if strength <= 0.0001:
		return 0.0
	var scatter_color := visual.optics_scattering_color
	if scatter_color.a <= 0.001:
		scatter_color = visual.translucency_color
	return _sample_color_wavelength(scatter_color, wavelength_t) * (1.0 - exp(-strength * maxf(distance, 0.0))) * 0.42


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
						120.0,
						4.8,
						2.2
					),
					_environment_card(
						Vector3(0.72, 0.12, 0.68),
						Color(0.96, 0.94, 1.0, 1.0),
						120.0,
						22.0,
						0.56,
						0.30
					),
					_environment_card(
						Vector3(-0.78, 0.18, 0.56),
						Color(1.0, 0.985, 0.95, 1.0),
						220.0,
						34.0,
						0.62,
						0.36
					),
					_environment_card(
						Vector3(-0.10, -0.70, 0.70),
						Color(1.0, 0.90, 0.80, 1.0),
						42.0,
						10.0,
						0.28,
						0.16
					),
				],
				"blocker_local_dir": Vector3(-0.26, -0.30, 0.92),
				"blocker_power": 10.0,
				"blocker_strength": 0.24,
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
						90.0,
						3.8,
						1.9
					),
					_environment_card(
						Vector3(0.86, 0.08, 0.50),
						Color(1.0, 0.96, 0.92, 1.0),
						160.0,
						26.0,
						0.48,
						0.26
					),
					_environment_card(
						Vector3(-0.72, 0.10, 0.62),
						Color(0.92, 0.96, 1.0, 1.0),
						120.0,
						24.0,
						0.44,
						0.24
					),
				],
				"blocker_local_dir": Vector3(-0.14, -0.24, 0.96),
				"blocker_power": 9.0,
				"blocker_strength": 0.12,
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


func _compute_surface_lighting(
	position: Vector3,
	normal: Vector3,
	zone: StringName,
	light_dir: Vector3,
	view_dir: Vector3,
	radius: float,
	visual: GemVisualResource,
	request: Dictionary,
) -> Vector3:
	var variant_type: StringName = request.get("variant_type", &"")
	var lighting_uv: Vector2 = request.get("lighting_uv", Vector2.ZERO)
	var environment_setup: Dictionary = request.get("environment_setup", {})
	var environment_cards: Array = environment_setup.get("cards", [])
	var body_color := _resolve_body_color(position, normal, radius, visual)
	var scatter_color := visual.optics_scattering_color
	if scatter_color.a <= 0.001:
		scatter_color = visual.translucency_color if visual.translucency_color.a > 0.001 else body_color
	# Dielectric surface specular is the color of the light source (white),
	# NOT the gem color.  Only rim glow uses the gem tint.
	var specular_color := Color(1.0, 0.98, 0.94, 1.0)
	var rim_tint := visual.rim_color if visual.rim_color.a > 0.001 else Color.WHITE
	var face_color := body_color.lerp(specular_color, 0.08 + visual.specular_intensity * 0.08)
	var caustic_base := body_color.lerp(Color.WHITE, 0.16 + visual.hue_dispersion * 0.18 + visual.sparkle_intensity * 0.04)
	var roughness := clampf(visual.optics_surface_roughness, 0.0, 1.0)
	var optics_ior := _wavelength_ior(visual, 0.5)
	var effective_light_dir := light_dir
	if variant_type == &"lighting" and radius > 0.0001:
		var key_origin := Vector3(
			(light_dir.x + lighting_uv.x * 0.95) * radius * 2.8,
			(light_dir.y - lighting_uv.y * 0.70) * radius * 2.4,
			maxf(light_dir.z, 0.22) * radius * 3.4
		)
		effective_light_dir = (key_origin - position).normalized()
	var front_alignment := maxf(normal.dot(effective_light_dir), 0.0)
	var back_alignment := maxf(-normal.dot(effective_light_dir), 0.0)
	var front_power := lerpf(18.0, 4.0, roughness)
	var front_strength := pow(front_alignment, front_power) * visual.optics_light_energy * (0.08 + visual.contrast * 0.18)
	var scatter_strength := maxf(visual.optics_scattering_strength, visual.translucency * 0.55)
	var back_strength := pow(back_alignment, 3.2) * visual.optics_light_energy * scatter_strength * 0.08
	var reflected_light := (-effective_light_dir).reflect(normal).normalized()
	var spec_alignment := maxf(reflected_light.dot(view_dir), 0.0)
	var spec_power := lerpf(120.0, 16.0, roughness)
	var spec_strength := pow(spec_alignment, spec_power) * visual.optics_light_energy * (0.12 + visual.specular_intensity * 0.52)
	var secondary_light_dir: Vector3 = (Basis(Vector3.UP, deg_to_rad(visual.secondary_light_angle)) * effective_light_dir).normalized()
	var secondary_reflection: Vector3 = (-secondary_light_dir).reflect(normal).normalized()
	var secondary_alignment := maxf(secondary_reflection.dot(view_dir), 0.0)
	var secondary_strength := pow(secondary_alignment, lerpf(96.0, 18.0, roughness)) * visual.secondary_specular * visual.optics_light_energy * 0.16
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
		var card_reflected := (-card_dir).reflect(normal).normalized()
		var card_spec_alignment := maxf(card_reflected.dot(view_dir), 0.0)
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
		card_glare_strength += pow(card_spec_alignment, card_power) * card_energy * 0.20
		card_fill_strength += pow(card_front, lerpf(10.0, 3.5, roughness)) * card_energy * 0.05
		var refracted_card := _refract(-card_dir, normal, AIR_IOR, optics_ior)
		if refracted_card.is_zero_approx():
			continue
		var return_alignment := maxf((-refracted_card).dot(view_dir), 0.0)
		var fresnel_in := _fresnel_dielectric(-card_dir, normal, AIR_IOR, optics_ior)
		card_return_strength += pow(return_alignment, lerpf(42.0, 10.0, roughness)) * card_energy * (1.0 - fresnel_in) * (0.24 + visual.extinction * 0.10)
	var planar_light := Vector2(effective_light_dir.x, effective_light_dir.y)
	var normalized_position := Vector2.ZERO
	if radius > 0.0001:
		normalized_position = Vector2(position.x, position.y) / radius
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
	front_strength *= zone_multiplier
	spec_strength += card_glare_strength * lerpf(zone_multiplier, 1.0 + visual.sparkle_intensity * 0.10, 0.4)
	spec_strength *= lerpf(zone_multiplier, 1.0 + visual.sparkle_intensity * 0.14, 0.35)
	secondary_strength *= lerpf(zone_multiplier, 1.0, 0.35)
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
	body_strength *= lerpf(0.82, 1.04, zone_multiplier - 1.0 + 0.5)
	var caustic_strength := (
		card_return_strength
		+ caustic_band * (0.018 + visual.sparkle_intensity * 0.012)
	) * visual.optics_light_energy
	var sparkle_strength := maxf(pow(spec_alignment, lerpf(260.0, 48.0, roughness)) - visual.sparkle_threshold, 0.0) * visual.sparkle_intensity * visual.optics_light_energy * 2.4
	var rim_alignment := maxf(1.0 - maxf(normal.dot(view_dir), 0.0), 0.0)
	var rim_strength := pow(rim_alignment, lerpf(5.8, 2.2, visual.rim_power / 5.0)) * visual.rim_intensity * visual.optics_light_energy * 0.26
	return Vector3(
		face_color.r * front_strength + scatter_color.r * back_strength + specular_color.r * (spec_strength + secondary_strength + sparkle_strength) + rim_tint.r * rim_strength + caustic_color.r * caustic_strength + body_color.r * body_strength,
		face_color.g * front_strength + scatter_color.g * back_strength + specular_color.g * (spec_strength + secondary_strength + sparkle_strength) + rim_tint.g * rim_strength + caustic_color.g * caustic_strength + body_color.g * body_strength,
		face_color.b * front_strength + scatter_color.b * back_strength + specular_color.b * (spec_strength + secondary_strength + sparkle_strength) + rim_tint.b * rim_strength + caustic_color.b * caustic_strength + body_color.b * body_strength
	)


func _compute_interface_highlight(
	visual: GemVisualResource,
	normal: Vector3,
	light_dir: Vector3,
	request: Dictionary,
	view_dir: Vector3,
	wavelength_t: float,
) -> float:
	var roughness := clampf(visual.optics_surface_roughness, 0.0, 1.0)
	var cards: Array = request.get("environment_setup", {}).get("cards", [])
	if cards.is_empty():
		cards = [{"dir": light_dir, "sharp_strength": 1.0, "broad_strength": 0.4, "sharp_power": 420.0, "broad_power": 46.0}]
	var total := 0.0
	for raw_card in cards:
		if typeof(raw_card) != TYPE_DICTIONARY:
			continue
		var card: Dictionary = raw_card
		var card_dir: Vector3 = card.get("dir", light_dir)
		var reflected_light := (-card_dir).reflect(normal).normalized()
		var spec_alignment := maxf(reflected_light.dot(view_dir), 0.0)
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
	return _sample_color_wavelength(Color(1.0, 0.99, 0.97, 1.0), wavelength_t) * total


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
	var inv_sq := (
		cos_theta * cos_theta / maxf(extraordinary_axis_ior * extraordinary_axis_ior, 0.0001)
		+ sin_sq / maxf(ordinary_ior * ordinary_ior, 0.0001)
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
	var t := clampf(wavelength_t, 0.0, 1.0)
	if t < 0.16:
		return Vector3(1.0, lerpf(0.02, 0.34, t / 0.16), 0.0)
	if t < 0.32:
		var local_t := (t - 0.16) / 0.16
		return Vector3(1.0, lerpf(0.34, 0.92, local_t), lerpf(0.0, 0.04, local_t))
	if t < 0.5:
		var local_t := (t - 0.32) / 0.18
		return Vector3(lerpf(1.0, 0.18, local_t), 1.0, lerpf(0.04, 0.14, local_t))
	if t < 0.68:
		var local_t := (t - 0.5) / 0.18
		return Vector3(lerpf(0.18, 0.0, local_t), lerpf(1.0, 0.84, local_t), lerpf(0.14, 1.0, local_t))
	if t < 0.84:
		var local_t := (t - 0.68) / 0.16
		return Vector3(0.0, lerpf(0.84, 0.22, local_t), 1.0)
	var tail_t := (t - 0.84) / 0.16
	return Vector3(lerpf(0.16, 0.62, tail_t), 0.0, 1.0)


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
	return body_color


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


func _apply_output_grade(color: Vector3, visual: GemVisualResource) -> Vector3:
	var exposure := (
		1.02
		+ visual.optics_light_energy * 0.16
		+ visual.specular_intensity * 0.14
		+ visual.sparkle_intensity * 0.03
	)
	var graded := color * exposure
	graded = Vector3(
		_apply_aces_channel(graded.x),
		_apply_aces_channel(graded.y),
		_apply_aces_channel(graded.z)
	)
	var saturation := clampf(
		visual.saturation_boost
		+ visual.contrast * 0.08
		+ visual.hue_dispersion * 0.16
		+ visual.specular_intensity * 0.04
		+ minf(visual.optics_absorption_strength, 3.0) * 0.025
		+ 0.02,
		-0.2,
		0.45
	)
	graded = _adjust_saturation(graded, saturation)
	# Apply a second saturation pass after gamma to counteract gamma's
	# expansion of dark channels (which visually desaturates colored gems).
	var post_gamma := Vector3(
		clampf(pow(maxf(graded.x, 0.0), 1.0 / 2.2), 0.0, 1.0),
		clampf(pow(maxf(graded.y, 0.0), 1.0 / 2.2), 0.0, 1.0),
		clampf(pow(maxf(graded.z, 0.0), 1.0 / 2.2), 0.0, 1.0)
	)
	var post_sat := clampf(minf(visual.optics_absorption_strength, 2.5) * 0.02, 0.0, 0.08)
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


func _adjust_saturation(color: Vector3, amount: float) -> Vector3:
	var luma := color.dot(Vector3(0.2126, 0.7152, 0.0722))
	var gray := Vector3.ONE * luma
	return gray.lerp(color, 1.0 + amount)
