class_name GemBakeStylizer
extends RefCounted

## Image-space stylization pass for offline traced gameplay bakes.
## This keeps the traced lighting/refraction structure intact while nudging
## the final texture toward a cleaner match-3 presentation.

const MICRO_BLUR_RADIUS := 1


static func apply(image: Image, visual: GemVisualResource, request: Dictionary = {}) -> Image:
	if image == null or visual == null:
		return image
	var mix := clampf(visual.stylize_mix, 0.0, 1.0)
	if mix <= 0.0001:
		return image

	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return image

	var pixel_count := width * height
	var rgb: Array[Vector3] = []
	rgb.resize(pixel_count)
	var alpha := PackedFloat32Array()
	alpha.resize(pixel_count)
	for y in height:
		for x in width:
			var idx := _index(x, y, width)
			var pixel := image.get_pixel(x, y)
			rgb[idx] = Vector3(pixel.r, pixel.g, pixel.b)
			alpha[idx] = pixel.a

	var smoothed_rgb := _box_blur_rgb(rgb, alpha, width, height, MICRO_BLUR_RADIUS, true)
	var guides := _build_guides(rgb, smoothed_rgb, alpha, width, height, visual)
	var edge_mask: PackedFloat32Array = guides.get("edge", PackedFloat32Array())
	var highlight_mask: PackedFloat32Array = guides.get("highlight", PackedFloat32Array())
	var interior_mask: PackedFloat32Array = guides.get("interior", PackedFloat32Array())

	var styled_rgb: Array[Vector3] = []
	styled_rgb.resize(pixel_count)
	for y in height:
		for x in width:
			var idx := _index(x, y, width)
			var a := alpha[idx]
			if a <= 0.0001:
				styled_rgb[idx] = Vector3.ZERO
				continue
			var fringe := smoothstep(0.08, 0.7, a)
			var base_rgb: Vector3 = rgb[idx]
			var soft_rgb: Vector3 = smoothed_rgb[idx]
			var edge_strength := edge_mask[idx] if idx < edge_mask.size() else 0.0
			var highlight_strength := highlight_mask[idx] if idx < highlight_mask.size() else 0.0
			var interior_strength := interior_mask[idx] if idx < interior_mask.size() else 0.0
			var detail := base_rgb - soft_rgb
			var detail_magnitude := detail.length()
			var micro_mask := clampf(1.0 - edge_strength * 1.35, 0.0, 1.0)
			micro_mask *= clampf(1.0 - detail_magnitude * 10.0, 0.0, 1.0)
			var smooth_mix := mix * visual.stylize_microdetail_suppression * micro_mask * fringe
			var styled := base_rgb.lerp(soft_rgb, smooth_mix)
			var silhouette_strength := 1.0 - smoothstep(0.40, 0.92, a)

			styled = _apply_plane_contrast(
				styled,
				mix * visual.stylize_plane_contrast * (0.82 + interior_strength * 0.18)
			)
			styled = _lift_shadow_floor(
				styled,
				visual.stylize_shadow_floor * (0.45 + interior_strength * 0.55) * fringe
			)
			var color_shift_gain := mix * visual.stylize_internal_color_shift_gain
			color_shift_gain *= interior_strength * fringe
			styled = _adjust_saturation(styled, color_shift_gain)
			var tone_band_amount := mix * (0.28 + visual.stylize_plane_contrast * 0.52)
			tone_band_amount *= 0.55 + interior_strength * 0.45
			styled = _apply_tone_steps(styled, maxi(visual.stylize_tone_steps, 2), tone_band_amount)

			var edge_gain := mix * visual.stylize_facet_edge_gain * edge_strength * fringe
			var internal_edge_bias := lerpf(0.60, 1.0, silhouette_strength)
			styled += detail * (0.42 + edge_gain * 0.26) * edge_gain * internal_edge_bias
			var edge_ink_amount := mix * visual.stylize_edge_ink_strength * edge_strength * fringe
			edge_ink_amount *= 0.34 + silhouette_strength * 0.66
			edge_ink_amount *= 0.75 + (1.0 - highlight_strength) * 0.25
			styled = styled.lerp(_build_ink_color(visual, styled), edge_ink_amount)
			var highlight_snap := mix * visual.stylize_highlight_snap * highlight_strength * fringe
			styled = _apply_highlight_snap(styled, highlight_snap)
			styled_rgb[idx] = _clamp_rgb(styled)

	var highlight_seed: Array[Vector3] = []
	highlight_seed.resize(pixel_count)
	var highlight_weights := PackedFloat32Array()
	highlight_weights.resize(pixel_count)
	for idx in pixel_count:
		var a := alpha[idx]
		if a <= 0.0001:
			highlight_seed[idx] = Vector3.ZERO
			highlight_weights[idx] = 0.0
			continue
		var weight := highlight_mask[idx] if idx < highlight_mask.size() else 0.0
		highlight_seed[idx] = styled_rgb[idx] * weight
		highlight_weights[idx] = weight

	var bloom_radius := _resolve_bloom_radius(request, width, height)
	var bloom_rgb := _box_blur_rgb(
		highlight_seed,
		highlight_weights,
		width,
		height,
		bloom_radius,
		false
	)
	var bloom_gain := mix * visual.stylize_highlight_bloom_gain
	var output_rgb: Array[Vector3] = []
	output_rgb.resize(pixel_count)
	for y in height:
		for x in width:
			var idx := _index(x, y, width)
			var a := alpha[idx]
			if a <= 0.0001:
				output_rgb[idx] = Vector3.ZERO
				continue
			var fringe := smoothstep(0.08, 0.7, a)
			var final_rgb: Vector3 = styled_rgb[idx]
			if bloom_gain > 0.0001 and idx < bloom_rgb.size():
				final_rgb += bloom_rgb[idx] * bloom_gain * 0.42 * fringe
			final_rgb = _clamp_rgb(final_rgb)
			output_rgb[idx] = final_rgb
	return _build_image_from_rgb_alpha(output_rgb, alpha, width, height)


static func _build_guides(
	rgb: Array[Vector3],
	smoothed_rgb: Array[Vector3],
	alpha: PackedFloat32Array,
	width: int,
	height: int,
	visual: GemVisualResource,
) -> Dictionary:
	var edge := PackedFloat32Array()
	var highlight := PackedFloat32Array()
	var interior := PackedFloat32Array()
	var count := width * height
	edge.resize(count)
	highlight.resize(count)
	interior.resize(count)
	var highlight_threshold := clampf(visual.stylize_highlight_bloom_threshold, 0.4, 0.98)
	for y in height:
		for x in width:
			var idx := _index(x, y, width)
			var a := alpha[idx]
			if a <= 0.0001:
				edge[idx] = 0.0
				highlight[idx] = 0.0
				interior[idx] = 0.0
				continue
			var center: Vector3 = rgb[idx]
			var center_luma := _luma(center)
			var center_chroma := _chroma(center)
			var left := _sample_rgb(rgb, alpha, width, height, x - 1, y, center)
			var right := _sample_rgb(rgb, alpha, width, height, x + 1, y, center)
			var up := _sample_rgb(rgb, alpha, width, height, x, y - 1, center)
			var down := _sample_rgb(rgb, alpha, width, height, x, y + 1, center)
			var luma_grad := absf(_luma(right) - _luma(left)) + absf(_luma(down) - _luma(up))
			var chroma_grad := absf(_chroma(right) - _chroma(left)) + absf(_chroma(down) - _chroma(up))
			var high_pass := (center - smoothed_rgb[idx]).length()
			var edge_strength := clampf(
				luma_grad * 1.12 + chroma_grad * 0.84 + high_pass * 2.0,
				0.0,
				1.0
			)
			edge_strength *= smoothstep(0.05, 0.8, a)
			edge[idx] = edge_strength

			var highlight_strength := smoothstep(
				highlight_threshold,
				1.0,
				maxf(center.x, maxf(center.y, center.z))
			)
			highlight_strength *= smoothstep(0.1, 0.85, a)
			highlight_strength *= 0.74 + edge_strength * 0.26
			highlight[idx] = clampf(highlight_strength, 0.0, 1.0)

			var interior_strength := clampf(1.0 - edge_strength * 1.15, 0.0, 1.0)
			interior_strength *= smoothstep(0.1, 0.9, a)
			interior_strength *= clampf(
				0.35
				+ (1.0 - center_luma) * 0.75
				+ center_chroma * 0.4,
				0.0,
				1.0
			)
			interior[idx] = clampf(interior_strength, 0.0, 1.0)
	return {
		"edge": edge,
		"highlight": highlight,
		"interior": interior,
	}


static func _box_blur_rgb(
	rgb: Array[Vector3],
	weights: PackedFloat32Array,
	width: int,
	height: int,
	radius: int,
	fallback_to_source: bool,
) -> Array[Vector3]:
	var result: Array[Vector3] = []
	result.resize(rgb.size())
	if radius <= 0:
		for idx in rgb.size():
			result[idx] = rgb[idx] if fallback_to_source else Vector3.ZERO
		return result
	var horizontal := _blur_axis_weighted(rgb, weights, width, height, radius, true, false)
	var vertical := _blur_axis_weighted(
		horizontal.get("rgb", []),
		horizontal.get("weights", PackedFloat32Array()),
		width,
		height,
		radius,
		false,
		true
	)
	var final_rgb: Array = vertical.get("rgb", [])
	var final_weights: PackedFloat32Array = vertical.get("weights", PackedFloat32Array())
	for idx in rgb.size():
		var total_weight := final_weights[idx] if idx < final_weights.size() else 0.0
		if total_weight > 0.0001:
			result[idx] = final_rgb[idx] / total_weight
		elif fallback_to_source:
			result[idx] = rgb[idx]
		else:
			result[idx] = Vector3.ZERO
	return result


static func _blur_axis_weighted(
	rgb: Array,
	weights: PackedFloat32Array,
	width: int,
	height: int,
	radius: int,
	horizontal: bool,
	premultiplied: bool,
) -> Dictionary:
	var result_rgb: Array[Vector3] = []
	result_rgb.resize(rgb.size())
	var result_weights := PackedFloat32Array()
	result_weights.resize(weights.size())
	if width <= 0 or height <= 0:
		return {
			"rgb": result_rgb,
			"weights": result_weights,
		}
	if horizontal:
		for y in height:
			var sum_rgb := Vector3.ZERO
			var sum_weight := 0.0
			for sample_x in range(-radius, radius + 1):
				var clamped_x := clampi(sample_x, 0, width - 1)
				var sample_idx := _index(clamped_x, y, width)
				var sample_weight := weights[sample_idx]
				sum_rgb += rgb[sample_idx] if premultiplied else rgb[sample_idx] * sample_weight
				sum_weight += sample_weight
			for x in width:
				var idx := _index(x, y, width)
				result_rgb[idx] = sum_rgb
				result_weights[idx] = sum_weight
				if x == width - 1:
					continue
				var remove_x := clampi(x - radius, 0, width - 1)
				var add_x := clampi(x + radius + 1, 0, width - 1)
				var remove_idx := _index(remove_x, y, width)
				var add_idx := _index(add_x, y, width)
				var remove_weight := weights[remove_idx]
				var add_weight := weights[add_idx]
				sum_rgb -= rgb[remove_idx] if premultiplied else rgb[remove_idx] * remove_weight
				sum_rgb += rgb[add_idx] if premultiplied else rgb[add_idx] * add_weight
				sum_weight += add_weight - remove_weight
	else:
		for x in width:
			var sum_rgb := Vector3.ZERO
			var sum_weight := 0.0
			for sample_y in range(-radius, radius + 1):
				var clamped_y := clampi(sample_y, 0, height - 1)
				var sample_idx := _index(x, clamped_y, width)
				var sample_weight := weights[sample_idx]
				sum_rgb += rgb[sample_idx] if premultiplied else rgb[sample_idx] * sample_weight
				sum_weight += sample_weight
			for y in height:
				var idx := _index(x, y, width)
				result_rgb[idx] = sum_rgb
				result_weights[idx] = sum_weight
				if y == height - 1:
					continue
				var remove_y := clampi(y - radius, 0, height - 1)
				var add_y := clampi(y + radius + 1, 0, height - 1)
				var remove_idx := _index(x, remove_y, width)
				var add_idx := _index(x, add_y, width)
				var remove_weight := weights[remove_idx]
				var add_weight := weights[add_idx]
				sum_rgb -= rgb[remove_idx] if premultiplied else rgb[remove_idx] * remove_weight
				sum_rgb += rgb[add_idx] if premultiplied else rgb[add_idx] * add_weight
				sum_weight += add_weight - remove_weight
	return {
		"rgb": result_rgb,
		"weights": result_weights,
	}


static func _build_image_from_rgb_alpha(
	rgb: Array[Vector3],
	alpha: PackedFloat32Array,
	width: int,
	height: int,
) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	for idx in rgb.size():
		var color: Vector3 = rgb[idx]
		var a := alpha[idx] if idx < alpha.size() else 1.0
		var byte_index := idx * 4
		bytes[byte_index] = int(round(clampf(color.x, 0.0, 1.0) * 255.0))
		bytes[byte_index + 1] = int(round(clampf(color.y, 0.0, 1.0) * 255.0))
		bytes[byte_index + 2] = int(round(clampf(color.z, 0.0, 1.0) * 255.0))
		bytes[byte_index + 3] = int(round(clampf(a, 0.0, 1.0) * 255.0))
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)


static func _sample_rgb(
	rgb: Array[Vector3],
	alpha: PackedFloat32Array,
	width: int,
	height: int,
	x: int,
	y: int,
	fallback: Vector3,
) -> Vector3:
	if x < 0 or x >= width or y < 0 or y >= height:
		return fallback
	var idx := _index(x, y, width)
	if alpha[idx] <= 0.0001:
		return fallback
	return rgb[idx]


static func _apply_plane_contrast(color: Vector3, amount: float) -> Vector3:
	if amount <= 0.0001:
		return color
	var luma := _luma(color)
	var centered := luma - 0.5
	var contrasted_luma := 0.5 + centered * (1.0 + amount * 0.95)
	contrasted_luma += signf(centered) * pow(absf(centered), 1.28) * amount * 0.14
	contrasted_luma = clampf(contrasted_luma, 0.0, 1.0)
	return _set_luma(color, contrasted_luma)


static func _lift_shadow_floor(color: Vector3, floor_value: float) -> Vector3:
	var clamped_floor := clampf(floor_value, 0.0, 0.35)
	if clamped_floor <= 0.0001:
		return color
	var luma := _luma(color)
	if luma >= clamped_floor:
		return color
	return _set_luma(color, clamped_floor)


static func _adjust_saturation(color: Vector3, amount: float) -> Vector3:
	if is_zero_approx(amount):
		return color
	var luma := _luma(color)
	var gray := Vector3.ONE * luma
	return gray.lerp(color, 1.0 + amount)


static func _apply_tone_steps(color: Vector3, steps: int, amount: float) -> Vector3:
	if steps <= 1 or amount <= 0.0001:
		return color
	var luma := _luma(color)
	var clamped_luma := clampf(luma, 0.0, 1.0)
	var band := clampi(int(floor(clamped_luma * float(steps))), 0, steps - 1)
	var snapped_luma := (float(band) + 0.5) / float(steps)
	var target_luma := lerpf(clamped_luma, snapped_luma, clampf(amount, 0.0, 1.0))
	# Scale all channels proportionally to preserve chrominance (hue + saturation).
	# This prevents spectral dispersion detail from being collapsed into grey bands.
	if clamped_luma > 0.0001:
		var scale := target_luma / clamped_luma
		return _clamp_rgb(color * scale)
	return Vector3.ONE * target_luma


static func _apply_highlight_snap(color: Vector3, amount: float) -> Vector3:
	if amount <= 0.0001:
		return color
	var luma := _luma(color)
	var target_luma := clampf(lerpf(luma, maxf(luma, 0.82), amount * 0.78), 0.0, 1.0)
	var snapped := _set_luma(color, target_luma)
	snapped = _adjust_saturation(snapped, amount * 0.06)
	var white_mix := clampf(amount * 0.035, 0.0, 0.035)
	return _clamp_rgb(snapped.lerp(Vector3.ONE, white_mix))


static func _build_ink_color(visual: GemVisualResource, color: Vector3) -> Vector3:
	var base_rgb := Vector3(visual.display_color.r, visual.display_color.g, visual.display_color.b)
	var ink_rgb := _adjust_saturation(base_rgb, -0.12)
	var ink_luma := clampf(_luma(color) * 0.34 + 0.07, 0.07, 0.28)
	return _set_luma(ink_rgb, ink_luma)


static func _set_luma(color: Vector3, target_luma: float) -> Vector3:
	var current_luma := _luma(color)
	if current_luma <= 0.0001:
		return Vector3.ONE * target_luma
	return _clamp_rgb(color * (target_luma / current_luma))


static func _resolve_bloom_radius(request: Dictionary, width: int, height: int) -> int:
	var requested_size: Vector2i = request.get("draw_size", Vector2i(width, height))
	var max_dimension := maxi(width, height)
	max_dimension = maxi(max_dimension, requested_size.x)
	max_dimension = maxi(max_dimension, requested_size.y)
	if max_dimension >= 176:
		return 3
	if max_dimension >= 88:
		return 2
	return 1


static func _index(x: int, y: int, width: int) -> int:
	return y * width + x


static func _luma(color: Vector3) -> float:
	return color.dot(Vector3(0.2126, 0.7152, 0.0722))


static func _chroma(color: Vector3) -> float:
	return maxf(color.x, maxf(color.y, color.z)) - minf(color.x, minf(color.y, color.z))


static func _clamp_rgb(color: Vector3) -> Vector3:
	return Vector3(
		clampf(color.x, 0.0, 1.0),
		clampf(color.y, 0.0, 1.0),
		clampf(color.z, 0.0, 1.0)
	)
