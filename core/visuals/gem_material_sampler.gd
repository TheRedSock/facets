class_name GemMaterialSampler
extends RefCounted

## Shared procedural material-field sampling for both the traced bake path and
## the lightweight procedural renderer.

const VIEW_DIR := Vector3(0.0, 0.0, 1.0)


static func apply_surface_material(
	visual: GemVisualResource,
	base_color: Color,
	uv: Vector2,
	object_position: Vector3,
	normal: Vector3,
	texture_image: Image = null,
) -> Dictionary:
	var color := base_color
	var pattern_value := 0.5
	var accent_value := 0.0
	if visual != null and visual.surface_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE:
		var surface_sample := _sample_surface_pattern(visual, uv, object_position, normal)
		pattern_value = float(surface_sample.get("value", 0.5))
		accent_value = float(surface_sample.get("accent", pattern_value))
		color = _mix_palette(
			color,
			_resolve_secondary_color(visual, color),
			_resolve_tertiary_color(visual, color),
			pattern_value,
			accent_value,
			visual.surface_pattern_mix
		)
	if visual != null and visual.use_texture and texture_image != null:
		var texture_sample := _sample_texture(texture_image, uv, normal, visual)
		color = color.lerp(texture_sample, clampf(visual.texture_blend, 0.0, 1.0))
	return {
		"color": color,
		"pattern_value": pattern_value,
		"accent_value": accent_value,
		"roughness_mult": clampf(
			1.0 + visual.surface_pattern_roughness_variation * ((pattern_value - 0.5) * 2.0),
			0.25,
			2.5
		),
		"specular_mult": clampf(
			1.0 + visual.surface_pattern_specular_variation * ((accent_value - 0.5) * 2.0),
			0.1,
			3.0
		),
	}


static func sample_volume_material(
	visual: GemVisualResource,
	object_position: Vector3,
) -> Dictionary:
	var color := visual.base_color if visual != null else Color.WHITE
	if visual == null or visual.volume_pattern_type == GemVisualResource.MATERIAL_PATTERN_NONE:
		return {
			"color": color,
			"pattern_value": 0.5,
			"accent_value": 0.5,
			"absorption_mult": 1.0,
			"scattering_mult": 1.0,
		}
	var volume_sample := _sample_volume_pattern(visual, object_position)
	var pattern_value := float(volume_sample.get("value", 0.5))
	var accent_value := float(volume_sample.get("accent", pattern_value))
	color = _mix_palette(
		color,
		_resolve_secondary_color(visual, color),
		_resolve_tertiary_color(visual, color),
		pattern_value,
		accent_value,
		visual.volume_pattern_mix
	)
	return {
		"color": color,
		"pattern_value": pattern_value,
		"accent_value": accent_value,
		"absorption_mult": clampf(
			1.0 + visual.volume_absorption_variation * ((pattern_value - 0.5) * 2.0),
			0.12,
			4.0
		),
		"scattering_mult": clampf(
			1.0 + visual.volume_scattering_variation * ((accent_value - 0.5) * 2.0),
			0.12,
			4.0
		),
	}


static func sample_reactive_color(
	visual: GemVisualResource,
	object_position: Vector3,
	normal: Vector3,
	light_dir: Vector3,
	view_dir: Vector3 = VIEW_DIR,
) -> Color:
	if visual == null or visual.reactive_effect_type == GemVisualResource.MATERIAL_REACTIVE_NONE:
		return Color(0.0, 0.0, 0.0, 0.0)
	if visual.reactive_strength <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var resolved_view := view_dir.normalized()
	var half_vec := (light_dir.normalized() + resolved_view).normalized()
	if half_vec.is_zero_approx():
		half_vec = resolved_view
	var basis := _basis_from_axis(visual.reactive_axis)
	var reactive_coord := _project_point(object_position * maxf(visual.reactive_scale, 0.1), basis)
	match visual.reactive_effect_type:
		GemVisualResource.MATERIAL_REACTIVE_CHATTOYANCY:
			return _sample_chatoyancy(visual, reactive_coord, half_vec, basis)
		GemVisualResource.MATERIAL_REACTIVE_OPALESCENCE:
			return _sample_opalescence(visual, reactive_coord, object_position, normal, half_vec)
		GemVisualResource.MATERIAL_REACTIVE_IRIDESCENCE:
			return _sample_iridescence(visual, reactive_coord, normal, half_vec)
		_:
			return Color(0.0, 0.0, 0.0, 0.0)


static func transmission_factor(visual: GemVisualResource) -> float:
	if visual == null:
		return 1.0
	match visual.material_mode:
		GemVisualResource.MATERIAL_MODE_PATTERNED_OPAQUE:
			return 0.0
		GemVisualResource.MATERIAL_MODE_PATTERNED_TRANSLUCENT:
			return 0.78
		_:
			return 1.0


static func _sample_surface_pattern(
	visual: GemVisualResource,
	uv: Vector2,
	object_position: Vector3,
	normal: Vector3,
) -> Dictionary:
	var coord := _surface_coord(uv, object_position, visual)
	if visual.surface_pattern_type == GemVisualResource.MATERIAL_PATTERN_CONCENTRIC:
		coord = _surface_object_coord(object_position, visual)
	var facet_warp_strength := maxf(visual.surface_pattern_warp_strength, visual.texture_facet_warp * 0.75)
	if facet_warp_strength > 0.0001:
		coord = _apply_procedural_facet_warp(coord, object_position, normal, facet_warp_strength)
	if visual.surface_pattern_warp_strength > 0.0001:
		var warp_noise := _noise2(coord * maxf(visual.surface_pattern_warp_scale, 0.1))
		var warp_angle := warp_noise * TAU
		coord += Vector2(cos(warp_angle), sin(warp_angle)) * visual.surface_pattern_warp_strength * 0.35
	var density := maxf(visual.surface_pattern_density, 0.1)
	match visual.surface_pattern_type:
		GemVisualResource.MATERIAL_PATTERN_BANDS:
			return _band_sample(coord, density, visual.surface_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_CONCENTRIC:
			return _ring_sample(coord, density, visual.surface_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_FIBERS:
			return _fiber_sample(coord, density, visual.surface_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_CELLS:
			return _cell_sample_2d(coord * density * 2.0, visual.surface_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_CLOUDS:
			return _cloud_sample_2d(coord * density * 1.8, visual.surface_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_LAYERS:
			return _layer_sample(coord, density, visual.surface_pattern_contrast)
		_:
			return {"value": 0.5, "accent": 0.5}


static func _sample_volume_pattern(
	visual: GemVisualResource,
	object_position: Vector3,
) -> Dictionary:
	var density := maxf(visual.volume_pattern_density, 0.1)
	var coord := _project_point(object_position, _basis_from_axis(visual.volume_pattern_axis))
	coord *= maxf(visual.volume_pattern_scale.length(), 0.1)
	if visual.volume_pattern_warp_strength > 0.0001:
		var warp_noise := _noise3(coord * maxf(visual.volume_pattern_warp_scale, 0.1))
		coord += Vector3(
			cos(warp_noise * TAU),
			sin(warp_noise * TAU),
			cos((warp_noise + 0.31) * TAU)
		) * visual.volume_pattern_warp_strength * 0.24
	match visual.volume_pattern_type:
		GemVisualResource.MATERIAL_PATTERN_BANDS:
			var band := _band_sample(Vector2(coord.x, coord.z), density, visual.volume_pattern_contrast)
			return band
		GemVisualResource.MATERIAL_PATTERN_CONCENTRIC:
			var ring := _ring_sample(Vector2(coord.x, coord.y), density, visual.volume_pattern_contrast)
			return ring
		GemVisualResource.MATERIAL_PATTERN_FIBERS:
			var fiber := _fiber_sample(Vector2(coord.x, coord.z), density, visual.volume_pattern_contrast)
			return fiber
		GemVisualResource.MATERIAL_PATTERN_CELLS:
			return _cell_sample_3d(coord * density * 2.0, visual.volume_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_CLOUDS:
			return _cloud_sample_3d(coord * density * 1.7, visual.volume_pattern_contrast)
		GemVisualResource.MATERIAL_PATTERN_LAYERS:
			return _volume_layer_sample(coord, density, visual.volume_pattern_contrast)
		_:
			return {"value": 0.5, "accent": 0.5}


static func _surface_coord(uv: Vector2, object_position: Vector3, visual: GemVisualResource) -> Vector2:
	var centered := (uv - Vector2(0.5, 0.5))
	centered += Vector2(object_position.z, -object_position.z) * 0.08
	var angle := deg_to_rad(visual.surface_pattern_rotation_degrees)
	var rotated := Vector2(
		centered.x * cos(angle) - centered.y * sin(angle),
		centered.x * sin(angle) + centered.y * cos(angle)
	)
	return Vector2(
		rotated.x * maxf(visual.surface_pattern_scale.x, 0.1),
		rotated.y * maxf(visual.surface_pattern_scale.y, 0.1)
	)


static func _surface_object_coord(object_position: Vector3, visual: GemVisualResource) -> Vector2:
	var centered := Vector2(object_position.x, object_position.y)
	var angle := deg_to_rad(visual.surface_pattern_rotation_degrees)
	var rotated := Vector2(
		centered.x * cos(angle) - centered.y * sin(angle),
		centered.x * sin(angle) + centered.y * cos(angle)
	)
	return Vector2(
		rotated.x * maxf(visual.surface_pattern_scale.x, 0.1),
		rotated.y * maxf(visual.surface_pattern_scale.y, 0.1)
	)


static func _apply_procedural_facet_warp(
	coord: Vector2,
	object_position: Vector3,
	normal: Vector3,
	warp_strength: float,
) -> Vector2:
	var tilt := clampf(1.0 - maxf(normal.z, 0.0), 0.0, 1.0)
	var facet_axis := Vector2(normal.x, -normal.y)
	if facet_axis.length_squared() <= 0.0001:
		facet_axis = Vector2.RIGHT
	else:
		facet_axis = facet_axis.normalized()
	var facet_perp := Vector2(-facet_axis.y, facet_axis.x)
	var bend_angle := (normal.x * 0.8 - normal.y * 0.6) * warp_strength * (0.08 + tilt * 0.12)
	var rotated := Vector2(
		coord.x * cos(bend_angle) - coord.y * sin(bend_angle),
		coord.x * sin(bend_angle) + coord.y * cos(bend_angle)
	)
	var along := rotated.dot(facet_axis)
	var across := rotated.dot(facet_perp)
	along *= 1.0 + tilt * warp_strength * 0.04
	across += along * (normal.x * normal.y) * warp_strength * 0.08
	across *= 1.0 - tilt * warp_strength * 0.03
	return facet_axis * along + facet_perp * across


static func _band_sample(coord: Vector2, density: float, contrast: float) -> Dictionary:
	var phase := coord.x * density * TAU * 3.2 + _noise2(coord * 1.9) * 1.8
	var raw := 0.5 + 0.5 * sin(phase)
	var value := _apply_contrast(raw, contrast)
	var accent := pow(1.0 - absf(raw * 2.0 - 1.0), lerpf(2.4, 0.8, contrast))
	return {"value": value, "accent": clampf(accent, 0.0, 1.0)}


static func _ring_sample(coord: Vector2, density: float, contrast: float) -> Dictionary:
	var scaled := coord * density * 1.7
	var nearest := _cellular2(scaled)
	var ring_distance := float(nearest.get("distance", 0.0)) * 9.6 + _noise2(scaled * 0.45 + Vector2(3.1, 9.7)) * 1.3
	var raw := 0.5 + 0.5 * sin(ring_distance * TAU)
	var line_phase := absf(sin(ring_distance * TAU))
	var line_mask := pow(clampf(1.0 - line_phase, 0.0, 1.0), lerpf(4.5, 12.0, contrast))
	line_mask = maxf(line_mask, clampf(1.0 - float(nearest.get("edge_distance", 0.0)) * 4.0, 0.0, 1.0) * 0.45)
	var value := _apply_contrast(raw * 0.82 + _fbm2(scaled * 0.28) * 0.18, contrast)
	return {"value": value, "accent": clampf(line_mask, 0.0, 1.0)}


static func _fiber_sample(coord: Vector2, density: float, contrast: float) -> Dictionary:
	var broad_noise := _fbm2(Vector2(coord.x * 0.24, coord.y * 0.62) + Vector2(11.7, 3.1))
	var thickness_field := _fbm2(Vector2(coord.y * 0.38, coord.x * 0.06) + Vector2(41.0, 2.0))
	var longitudinal_warp := (_noise2(Vector2(coord.y * 0.14, 5.4)) - 0.5) * 1.1
	longitudinal_warp += (_fbm2(Vector2(coord.y * 0.08, 13.6)) - 0.5) * 1.3
	var local_density := density * lerpf(0.36, 2.08, broad_noise * 0.72 + thickness_field * 0.28)
	var macro_band := 0.5 + 0.5 * sin(coord.x * density * TAU * 1.18 + longitudinal_warp * 0.55 + broad_noise * 1.4)
	var phase := coord.x * local_density * TAU * 4.4 + longitudinal_warp
	var stripe := 1.0 - absf(sin(phase))
	var width_noise := _fbm2(Vector2(coord.x * 0.12, coord.y * 0.84) + Vector2(17.0, 8.0))
	var width_bias := lerpf(0.12, 0.94, width_noise)
	var softened := smoothstep(width_bias - 0.28, width_bias + 0.10, stripe)
	var band_variation := _noise2(Vector2(coord.y * 0.9, coord.x * 0.05) + Vector2(23.0, 4.0))
	var accent := pow(clampf(softened, 0.0, 1.0), lerpf(1.8, 5.8, contrast))
	accent *= lerpf(0.48, 1.0, broad_noise)
	accent *= lerpf(0.65, 1.0, band_variation)
	var grain := _fbm2(Vector2(coord.y * 1.7, coord.x * 0.12) + Vector2(31.0, 6.0))
	var grain_shadow := _fbm2(Vector2(coord.y * 0.34, coord.x * 0.02) + Vector2(2.0, 27.0))
	var raw := clampf(
		0.04
		+ accent * 0.68
		+ macro_band * 0.30
		+ grain * 0.10
		+ band_variation * 0.10
		- grain_shadow * 0.12,
		0.0,
		1.0
	)
	return {"value": _apply_contrast(raw, contrast), "accent": accent}


static func _cell_sample_2d(coord: Vector2, contrast: float) -> Dictionary:
	var nearest := _cellular2(coord)
	var edge_distance := float(nearest.get("edge_distance", 0.0))
	var foam_mask := pow(clampf(1.0 - edge_distance * 3.2, 0.0, 1.0), lerpf(1.2, 2.8, contrast))
	var body := _fbm2(coord * 0.46 + Vector2(float(nearest.get("seed", 0.5)) * 3.7, 7.1))
	var raw := clampf(body * 0.62 + (1.0 - foam_mask) * 0.18 + float(nearest.get("seed", 0.5)) * 0.2, 0.0, 1.0)
	return {"value": _apply_contrast(raw, contrast), "accent": foam_mask}


static func _cloud_sample_2d(coord: Vector2, contrast: float) -> Dictionary:
	var raw := _fbm2(coord)
	return {"value": _apply_contrast(raw, contrast), "accent": clampf(raw * 1.15, 0.0, 1.0)}


static func _layer_sample(coord: Vector2, density: float, contrast: float) -> Dictionary:
	var phase := coord.y * density * TAU * 3.8 + _noise2(coord * 2.3) * 1.6
	var raw := 0.5 + 0.5 * sin(phase)
	var accent := clampf(0.5 + 0.5 * cos(phase * 0.5), 0.0, 1.0)
	return {"value": _apply_contrast(raw, contrast), "accent": accent}


static func _cell_sample_3d(coord: Vector3, contrast: float) -> Dictionary:
	var nearest := _cellular3(coord)
	var edge_distance := float(nearest.get("edge_distance", 0.0))
	var accent := clampf(1.0 - edge_distance * 2.6, 0.0, 1.0)
	var raw := clampf(float(nearest.get("seed", 0.5)) * 0.68 + accent * 0.32, 0.0, 1.0)
	return {"value": _apply_contrast(raw, contrast), "accent": accent}


static func _cloud_sample_3d(coord: Vector3, contrast: float) -> Dictionary:
	var raw := _fbm3(coord)
	return {"value": _apply_contrast(raw, contrast), "accent": clampf(raw * 1.12, 0.0, 1.0)}


static func _volume_layer_sample(coord: Vector3, density: float, contrast: float) -> Dictionary:
	var phase := coord.y * density * TAU * 3.0 + _noise3(coord * 1.8) * 2.2
	var raw := 0.5 + 0.5 * sin(phase)
	var accent := clampf(0.5 + 0.5 * sin(coord.z * density * TAU * 1.4 + phase), 0.0, 1.0)
	return {"value": _apply_contrast(raw, contrast), "accent": accent}


static func _sample_chatoyancy(
	visual: GemVisualResource,
	reactive_coord: Vector3,
	half_vec: Vector3,
	basis: Dictionary,
) -> Color:
	var axis: Vector3 = basis.get("axis", Vector3.RIGHT)
	var tangent: Vector3 = basis.get("tangent", Vector3.UP)
	var sweep := reactive_coord.x * visual.reactive_density + half_vec.dot(tangent) * 2.8
	var band := exp(-pow(sweep, 2.0) * lerpf(1.4, 6.0, minf(visual.reactive_sharpness / 8.0, 1.0)))
	var angle_term := pow(maxf(absf(half_vec.dot(axis)), 0.0), maxf(visual.reactive_sharpness, 0.5))
	var base_color := visual.reactive_color if visual.reactive_color.a > 0.001 else _resolve_secondary_color(visual, visual.base_color)
	var strength := band * angle_term * visual.reactive_strength
	return base_color * clampf(strength, 0.0, 4.0)


static func _sample_opalescence(
	visual: GemVisualResource,
	reactive_coord: Vector3,
	object_position: Vector3,
	normal: Vector3,
	half_vec: Vector3,
) -> Color:
	var scale := visual.reactive_density * 1.3
	var cloud_a := _fbm3(reactive_coord * scale + object_position * 0.8 + Vector3(5.0, 11.0, 2.0))
	var cloud_b := _fbm3(reactive_coord * scale * 2.1 + Vector3(17.0, 7.0, 13.0))
	var cloud_c := _noise3(reactive_coord * scale * 3.1 + Vector3(3.0, 19.0, 23.0))
	var nebula := clampf(cloud_a * 0.54 + cloud_b * 0.32 + cloud_c * 0.14, 0.0, 1.0)
	var zone_mask := smoothstep(0.44, 0.78, nebula)
	var glint := 0.32 + 0.68 * pow(
		maxf(normal.normalized().dot(half_vec), 0.0),
		lerpf(4.0, 14.0, minf(visual.reactive_sharpness / 8.0, 1.0))
	)
	var prism_shift := _fract(
		cloud_a * 0.33
		+ cloud_b * 0.27
		+ cloud_c * 0.19
		+ object_position.dot(Vector3(0.58, 0.96, 0.74)) * 0.12
		+ half_vec.dot(Vector3(0.44, 0.18, 0.88)) * 0.21
	)
	var spectral_a := Color.from_hsv(prism_shift, 0.92, 1.0, 1.0)
	var spectral_b := Color.from_hsv(_fract(prism_shift + 0.18), 0.88, 1.0, 1.0)
	var spectral_c := Color.from_hsv(_fract(prism_shift + 0.42), 0.94, 1.0, 1.0)
	var warm := visual.reactive_color if visual.reactive_color.a > 0.001 else spectral_a
	var cool := visual.reactive_secondary_color if visual.reactive_secondary_color.a > 0.001 else spectral_b
	var blend_a := _noise3(reactive_coord * 1.1 + Vector3(9.0, 3.0, 21.0))
	var blend_b := _noise3(reactive_coord * 1.7 + Vector3(13.0, 15.0, 7.0))
	var flash_color := warm.lerp(cool, blend_a)
	flash_color = flash_color.lerp(spectral_c, blend_b * 0.65)
	var strength := zone_mask * glint * visual.reactive_strength
	return flash_color * clampf(strength, 0.0, 5.0)


static func _sample_iridescence(
	visual: GemVisualResource,
	reactive_coord: Vector3,
	normal: Vector3,
	half_vec: Vector3,
) -> Color:
	var facing := clampf(1.0 - maxf(normal.normalized().dot(VIEW_DIR), 0.0), 0.0, 1.0)
	var shift := _fract(reactive_coord.x * visual.reactive_density * 0.18 + half_vec.y * 0.33 + facing * 0.46)
	var base := visual.reactive_color if visual.reactive_color.a > 0.001 else Color.from_hsv(shift, 0.7, 1.0, 1.0)
	var secondary := visual.reactive_secondary_color if visual.reactive_secondary_color.a > 0.001 else Color.from_hsv(_fract(shift + 0.28), 0.75, 1.0, 1.0)
	var strength := pow(facing, maxf(visual.reactive_sharpness, 0.5)) * visual.reactive_strength
	return base.lerp(secondary, 0.5 + 0.5 * sin(shift * TAU)) * clampf(strength, 0.0, 4.0)


static func _mix_palette(
	base_color: Color,
	secondary_color: Color,
	tertiary_color: Color,
	pattern_value: float,
	accent_value: float,
	mix_amount: float,
) -> Color:
	if mix_amount <= 0.0001:
		return base_color
	var mixed := base_color.lerp(secondary_color, clampf(pattern_value * mix_amount, 0.0, 1.0))
	if tertiary_color.a > 0.001:
		mixed = mixed.lerp(tertiary_color, clampf(accent_value * mix_amount * 0.75, 0.0, 1.0))
	return mixed


static func _resolve_secondary_color(visual: GemVisualResource, base_color: Color) -> Color:
	if visual.material_secondary_color.a > 0.001:
		return visual.material_secondary_color
	if visual.gradient_color.a > 0.001:
		return visual.gradient_color
	return base_color.darkened(0.18)


static func _resolve_tertiary_color(visual: GemVisualResource, base_color: Color) -> Color:
	if visual.material_tertiary_color.a > 0.001:
		return visual.material_tertiary_color
	if visual.phenomenon_color.a > 0.001:
		return visual.phenomenon_color
	return base_color.lightened(0.12)


static func _sample_texture(texture_image: Image, uv: Vector2, normal: Vector3, visual: GemVisualResource) -> Color:
	if texture_image == null:
		return visual.base_color
	var width := texture_image.get_width()
	var height := texture_image.get_height()
	if width <= 0 or height <= 0:
		return visual.base_color
	var warped_uv := uv
	if visual.texture_facet_warp > 0.001:
		var normal_offset := Vector2(normal.x, -normal.y) * visual.texture_facet_warp * 0.08
		warped_uv += normal_offset
	var sample_uv := warped_uv
	sample_uv = (sample_uv - Vector2(0.5, 0.5)) / maxf(visual.texture_zoom, 1.0) + Vector2(0.5, 0.5) + visual.texture_offset
	sample_uv.x = clampf(sample_uv.x, 0.0, 1.0)
	sample_uv.y = clampf(sample_uv.y, 0.0, 1.0)
	var x := clampi(int(round(sample_uv.x * float(width - 1))), 0, width - 1)
	var y := clampi(int(round(sample_uv.y * float(height - 1))), 0, height - 1)
	return texture_image.get_pixel(x, y)


static func _apply_contrast(value: float, contrast: float) -> float:
	var centered := value - 0.5
	var scale := lerpf(0.68, 2.1, clampf(contrast, 0.0, 1.0))
	return clampf(0.5 + centered * scale, 0.0, 1.0)


static func _project_point(point: Vector3, basis: Dictionary) -> Vector3:
	var tangent: Vector3 = basis.get("tangent", Vector3.RIGHT)
	var bitangent: Vector3 = basis.get("bitangent", Vector3.FORWARD)
	var axis: Vector3 = basis.get("axis", Vector3.UP)
	return Vector3(point.dot(tangent), point.dot(bitangent), point.dot(axis))


static func _basis_from_axis(axis: Vector3) -> Dictionary:
	var resolved_axis := axis.normalized()
	if resolved_axis.is_zero_approx():
		resolved_axis = Vector3.UP
	var tangent := resolved_axis.cross(Vector3.UP)
	if tangent.length_squared() <= 0.0001:
		tangent = resolved_axis.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := resolved_axis.cross(tangent).normalized()
	return {
		"axis": resolved_axis,
		"tangent": tangent,
		"bitangent": bitangent,
	}


static func _noise2(point: Vector2) -> float:
	var cell := Vector2(floor(point.x), floor(point.y))
	var local := point - cell
	var smooth := local * local * (Vector2(3.0, 3.0) - 2.0 * local)
	var a := _hash2(cell)
	var b := _hash2(cell + Vector2.RIGHT)
	var c := _hash2(cell + Vector2.DOWN)
	var d := _hash2(cell + Vector2.ONE)
	return lerpf(
		lerpf(a, b, smooth.x),
		lerpf(c, d, smooth.x),
		smooth.y
	)


static func _noise3(point: Vector3) -> float:
	var cell := Vector3(floor(point.x), floor(point.y), floor(point.z))
	var local := point - cell
	var smooth := Vector3(
		local.x * local.x * (3.0 - 2.0 * local.x),
		local.y * local.y * (3.0 - 2.0 * local.y),
		local.z * local.z * (3.0 - 2.0 * local.z)
	)
	var x00 := lerpf(_hash3(cell), _hash3(cell + Vector3.RIGHT), smooth.x)
	var x10 := lerpf(_hash3(cell + Vector3.UP), _hash3(cell + Vector3(1.0, 1.0, 0.0)), smooth.x)
	var x01 := lerpf(_hash3(cell + Vector3.FORWARD), _hash3(cell + Vector3(1.0, 0.0, 1.0)), smooth.x)
	var x11 := lerpf(_hash3(cell + Vector3(0.0, 1.0, 1.0)), _hash3(cell + Vector3.ONE), smooth.x)
	var y0 := lerpf(x00, x10, smooth.y)
	var y1 := lerpf(x01, x11, smooth.y)
	return lerpf(y0, y1, smooth.z)


static func _fbm2(point: Vector2) -> float:
	var total := 0.0
	var weight := 0.5
	var frequency := 1.0
	var normalizer := 0.0
	for _i in 3:
		total += _noise2(point * frequency) * weight
		normalizer += weight
		weight *= 0.5
		frequency *= 2.0
	return total / maxf(normalizer, 0.0001)


static func _fbm3(point: Vector3) -> float:
	var total := 0.0
	var weight := 0.5
	var frequency := 1.0
	var normalizer := 0.0
	for _i in 3:
		total += _noise3(point * frequency) * weight
		normalizer += weight
		weight *= 0.5
		frequency *= 2.0
	return total / maxf(normalizer, 0.0001)


static func _cellular2(point: Vector2) -> Dictionary:
	var base := Vector2i(int(floor(point.x)), int(floor(point.y)))
	var nearest := INF
	var second := INF
	var best_seed := 0.5
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var cell := Vector2i(base.x + ox, base.y + oy)
			var cell_point := Vector2(float(cell.x), float(cell.y))
			var feature := cell_point + Vector2(
				_hash2(cell_point + Vector2(17.0, 3.0)),
				_hash2(cell_point + Vector2(5.0, 29.0))
			)
			var distance := feature.distance_to(point)
			if distance < nearest:
				second = nearest
				nearest = distance
				best_seed = _hash2(cell_point + Vector2(41.0, 11.0))
			elif distance < second:
				second = distance
	return {
		"distance": nearest,
		"edge_distance": maxf(second - nearest, 0.0),
		"seed": best_seed,
	}


static func _cellular3(point: Vector3) -> Dictionary:
	var base := Vector3i(int(floor(point.x)), int(floor(point.y)), int(floor(point.z)))
	var nearest := INF
	var second := INF
	var best_seed := 0.5
	for oz in range(-1, 2):
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var cell := Vector3i(base.x + ox, base.y + oy, base.z + oz)
				var cell_point := Vector3(float(cell.x), float(cell.y), float(cell.z))
				var feature := cell_point + Vector3(
					_hash3(cell_point + Vector3(17.0, 3.0, 9.0)),
					_hash3(cell_point + Vector3(5.0, 29.0, 13.0)),
					_hash3(cell_point + Vector3(23.0, 7.0, 31.0))
				)
				var distance := feature.distance_to(point)
				if distance < nearest:
					second = nearest
					nearest = distance
					best_seed = _hash3(cell_point + Vector3(41.0, 11.0, 19.0))
				elif distance < second:
					second = distance
	return {
		"distance": nearest,
		"edge_distance": maxf(second - nearest, 0.0),
		"seed": best_seed,
	}


static func _hash2(point: Vector2) -> float:
	return _fract(sin(point.dot(Vector2(127.1, 311.7))) * 43758.5453123)


static func _hash3(point: Vector3) -> float:
	return _fract(sin(point.dot(Vector3(127.1, 311.7, 74.7))) * 43758.5453123)


static func _fract(value: float) -> float:
	return value - floorf(value)
