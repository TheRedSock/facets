class_name GemRenderer
extends RefCounted

## Procedural 2D fallback renderer — simplified Blinn-Phong lighting for faceted gems.
## No scene-tree dependency — can run headlessly.
## Physical accuracy comes from the traced path; this is a lightweight fallback.
##
## Performance contract: facet normals in GemProjectedCutResource are pre-normalized at
## cut generation time.  This renderer skips redundant normalization calls.

const DEFAULT_LIGHT_DIR := Vector3(-0.4, -0.5, 0.75)
const DEFAULT_VIEW_DIR := Vector3(0.0, 0.0, 1.0)
const AMBIENT := 0.15
const FALLBACK_SHININESS := 32.0
const FALLBACK_SPECULAR := 0.4
const FALLBACK_CONTRAST := 0.3
const GemMaterialSamplerScript = preload("res://core/visuals/gem_material_sampler.gd")


## Computes the flat-shaded colour for a single facet.
## contrast: 0=flat Half-Lambert, 1=full standard Lambert (dramatic).
##
## Note: This is the public single-facet API.  The batch function
## compute_all_facet_colors() inlines this logic to avoid per-facet overhead.
static func compute_facet_color(
	normal: Vector3,
	base_color: Color,
	shininess: float = FALLBACK_SHININESS,
	specular_intensity: float = FALLBACK_SPECULAR,
	light_dir: Vector3 = DEFAULT_LIGHT_DIR,
	contrast: float = FALLBACK_CONTRAST,
) -> Color:
	var l := light_dir.normalized()
	var n := normal.normalized()

	# Diffuse: blend between Half-Lambert (soft) and standard Lambert (dramatic)
	# based on the contrast parameter.
	var ndotl := n.dot(l)
	var half_lambert := ndotl * 0.5 + 0.5           # range [0, 1], never fully dark
	var standard_lambert := maxf(ndotl, 0.0)          # range [0, 1], hard shadow
	var diffuse := lerpf(half_lambert, standard_lambert, contrast)

	# Blinn-Phong specular.
	var half_vec := (l + DEFAULT_VIEW_DIR).normalized()
	var spec := pow(maxf(n.dot(half_vec), 0.0), shininess)

	# Combine.
	var shade := AMBIENT + (1.0 - AMBIENT) * diffuse
	return Color(
		clampf(base_color.r * shade + specular_intensity * spec, 0.0, 1.0),
		clampf(base_color.g * shade + specular_intensity * spec, 0.0, 1.0),
		clampf(base_color.b * shade + specular_intensity * spec, 0.0, 1.0),
		base_color.a,
	)


## Computes colours for every facet in a cut, respecting the visual's
## display_color and optional modifier overrides.
##
## Simplified Blinn-Phong fallback — physical accuracy comes from the traced path.
##
## Pipeline order (per facet):
##   1. Modifier adjustments (darken/brighten/desaturate)
##   2. Colour zoning (gradient), phenomenon cue
##   3. Material surface/volume patterns, reactive effects
##   4. Inlined Blinn-Phong lighting
##   5. Per-facet jitter
static func compute_all_facet_colors(
	cut,
	visual: GemVisualResource,
	light_dir: Vector3 = DEFAULT_LIGHT_DIR,
	modifiers: Dictionary = {},
) -> PackedColorArray:
	var count = int(cut.facet_count())
	var colors = PackedColorArray()
	colors.resize(count)

	var base := visual.display_color
	var texture_overlay_mode := texture_uses_overlay_mode(visual)
	if visual.use_texture and not texture_overlay_mode:
		base = Color.WHITE

	# Modifier adjustments.
	if modifiers.has("darken"):
		base = base.darkened(modifiers["darken"])
	if modifiers.has("brighten"):
		base = base.lightened(modifiers["brighten"])
	if modifiers.has("desaturate"):
		var amount: float = modifiers["desaturate"]
		base.s = clampf(base.s - amount, 0.0, 1.0)

	# ---- Pre-compute shared values ----

	var l := light_dir.normalized()
	var half_vec := (l + DEFAULT_VIEW_DIR).normalized()
	var contrast := FALLBACK_CONTRAST
	var shininess := FALLBACK_SHININESS
	var specular_intensity := FALLBACK_SPECULAR
	var one_minus_ambient := 1.0 - AMBIENT
	var transparent_mode := visual.material_mode == GemVisualResource.MATERIAL_MODE_FACETED_TRANSPARENT

	var grad_zone_ok := (
		visual.gradient_zone_spectrum.size() == 81
		and _zone_spectrum_has_signal(visual.gradient_zone_spectrum)
	)
	var phen_zone_ok := (
		visual.phenomenon_zone_spectrum.size() == 81
		and _zone_spectrum_has_signal(visual.phenomenon_zone_spectrum)
	)

	# Feature flags (avoid per-facet branching on disabled features).
	var has_gradient := (
		transparent_mode
		and
		visual.gradient_strength > 0.001
		and (grad_zone_ok or visual.gradient_color.a > 0.001)
	)
	var has_phenomenon := (
		transparent_mode
		and
		visual.phenomenon_strength > 0.001
		and (phen_zone_ok or visual.phenomenon_color.a > 0.001)
	)
	var has_material_surface := (
		visual.surface_pattern_mix > 0.001
		and visual.surface_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE
	)
	var has_material_volume := (
		visual.volume_pattern_mix > 0.001
		and visual.volume_pattern_type != GemVisualResource.MATERIAL_PATTERN_NONE
	)
	var has_material_reactive := (
		visual.reactive_strength > 0.001
		and visual.reactive_effect_type != GemVisualResource.MATERIAL_REACTIVE_NONE
	)

	# Pre-computed cut data availability flags.
	var has_centroids = cut.facet_centroids.size() == count
	var has_precomputed_jitter = cut.facet_jitter.size() == count
	var needs_centroid := has_gradient or has_material_surface or has_material_volume or has_material_reactive

	var gradient_axis := Vector2.RIGHT
	var phenomenon_axis := Vector2.RIGHT
	if has_gradient:
		gradient_axis = Vector2.RIGHT.rotated(deg_to_rad(visual.gradient_angle_degrees)).normalized()
	if has_phenomenon:
		phenomenon_axis = Vector2.RIGHT.rotated(deg_to_rad(visual.phenomenon_angle_degrees)).normalized()

	var gradient_target := visual.gradient_color
	if grad_zone_ok:
		gradient_target = GemVisualResource.zone_spectrum_to_display_color(visual.gradient_zone_spectrum)
	var phenomenon_target := visual.phenomenon_color
	if phen_zone_ok:
		phenomenon_target = GemVisualResource.zone_spectrum_to_display_color(visual.phenomenon_zone_spectrum)

	# ---- Single per-facet pass ----

	for i in count:
		# Normal is pre-normalized at cut generation time (see GemCutPrimitives.normal_for).
		var n: Vector3 = cut.facet_normals[i]
		var facet_base := base
		var centroid := Vector2.ZERO
		if needs_centroid:
			if has_centroids:
				centroid = cut.facet_centroids[i]
			else:
				centroid = _compute_facet_centroid(cut, i)

		# Color zoning: linear or radial blend toward gradient_color.
		if has_gradient:
			var t := _compute_gradient_mix(centroid, visual, gradient_axis) * visual.gradient_strength
			facet_base = Color(
				lerpf(facet_base.r, gradient_target.r, t),
				lerpf(facet_base.g, gradient_target.g, t),
				lerpf(facet_base.b, gradient_target.b, t),
				facet_base.a)

		if has_phenomenon:
			var phenomenon_t := _compute_phenomenon_mix(n, phenomenon_axis, visual.phenomenon_sharpness)
			var phenomenon_blend := phenomenon_t * visual.phenomenon_strength
			facet_base = Color(
				lerpf(facet_base.r, phenomenon_target.r, phenomenon_blend),
				lerpf(facet_base.g, phenomenon_target.g, phenomenon_blend),
				lerpf(facet_base.b, phenomenon_target.b, phenomenon_blend),
				facet_base.a)

		var object_position := Vector3(
			(centroid.x - 0.5) * 2.0,
			(centroid.y - 0.5) * 2.0,
			0.0
		)
		var local_specular_intensity := specular_intensity
		if has_material_surface:
			var surface_material: Dictionary = GemMaterialSamplerScript.apply_surface_material(
				visual,
				facet_base,
				centroid,
				object_position,
				n
			)
			facet_base = surface_material.get("color", facet_base)
			local_specular_intensity *= float(surface_material.get("specular_mult", 1.0))
		if has_material_volume:
			var volume_material: Dictionary = GemMaterialSamplerScript.sample_volume_material(visual, object_position)
			var volume_mix := visual.volume_pattern_mix * (
				0.42 if visual.material_mode == GemVisualResource.MATERIAL_MODE_PATTERNED_TRANSLUCENT else 0.22
			)
			facet_base = facet_base.lerp(
				volume_material.get("color", facet_base),
				clampf(volume_mix, 0.0, 1.0)
			)

		# ---- Inlined Blinn-Phong lighting ----
		var ndotl = n.dot(l)
		var half_lambert = ndotl * 0.5 + 0.5
		var standard_lambert = maxf(ndotl, 0.0)
		var diffuse := lerpf(half_lambert, standard_lambert, contrast)
		var spec := pow(maxf(n.dot(half_vec), 0.0), shininess)
		var shade := AMBIENT + one_minus_ambient * diffuse
		var spec_contrib := local_specular_intensity * spec

		var cr := clampf(facet_base.r * shade + spec_contrib, 0.0, 1.0)
		var cg := clampf(facet_base.g * shade + spec_contrib, 0.0, 1.0)
		var cb := clampf(facet_base.b * shade + spec_contrib, 0.0, 1.0)
		var ca := facet_base.a

		if has_material_reactive:
			var reactive_color: Color = GemMaterialSamplerScript.sample_reactive_color(visual, object_position, n, l)
			cr = clampf(cr + reactive_color.r, 0.0, 1.0)
			cg = clampf(cg + reactive_color.g, 0.0, 1.0)
			cb = clampf(cb + reactive_color.b, 0.0, 1.0)

		# Per-facet jitter: deterministic brightness variation from pre-computed values.
		var jitter := 0.0
		if has_precomputed_jitter:
			jitter = cut.facet_jitter[i]
		else:
			# Fallback: compute from vertices (for cuts not finalized via standard pipeline).
			var jitter_centroid: Vector2
			if has_centroids:
				jitter_centroid = cut.facet_centroids[i]
			else:
				jitter_centroid = _compute_facet_centroid(cut, i)
			var hash_val = sin(jitter_centroid.x * 127.1 + jitter_centroid.y * 311.7) * 43758.5453
			hash_val = hash_val - floorf(hash_val)
			jitter = (hash_val - 0.5) * 0.08
		cr = clampf(cr + jitter, 0.0, 1.0)
		cg = clampf(cg + jitter, 0.0, 1.0)
		cb = clampf(cb + jitter, 0.0, 1.0)

		colors[i] = Color(cr, cg, cb, ca)

	return colors


## Returns the centroid of a facet's vertices in [0,1] unit space.
static func _compute_facet_centroid(cut, facet_index: int) -> Vector2:
	var verts: PackedVector2Array = cut.facet_vertices[facet_index]
	var centroid = Vector2.ZERO
	for v in verts:
		centroid += v
	return centroid / verts.size()


## Returns the Y coordinate of a facet's centroid in [0,1] unit space.
## Kept as a lightweight fallback for gradient computation when centroids
## are not pre-computed.
static func _facet_centroid_y(cut, facet_index: int) -> float:
	var verts: PackedVector2Array = cut.facet_vertices[facet_index]
	var cy = 0.0
	for v in verts:
		cy += v.y
	return cy / verts.size()


static func _compute_gradient_mix(
	centroid: Vector2,
	visual: GemVisualResource,
	gradient_axis: Vector2,
) -> float:
	var centered := centroid - Vector2(0.5, 0.5)
	match visual.gradient_mode:
		GemVisualResource.GRADIENT_MODE_RADIAL:
			return clampf(centered.length() / 0.70710678, 0.0, 1.0)
		GemVisualResource.GRADIENT_MODE_RADIAL_INVERSE:
			return 1.0 - clampf(centered.length() / 0.70710678, 0.0, 1.0)
		_:
			return clampf(0.5 + centered.dot(gradient_axis), 0.0, 1.0)


static func _compute_phenomenon_mix(
	normal: Vector3,
	phenomenon_axis: Vector2,
	sharpness: float,
) -> float:
	var planar := Vector2(normal.x, normal.y)
	if planar.length_squared() < 0.00001:
		return 0.5
	var axis_alignment := planar.normalized().dot(phenomenon_axis)
	return pow(clampf(axis_alignment * 0.5 + 0.5, 0.0, 1.0), sharpness)


static func _zone_spectrum_has_signal(spectrum: PackedFloat32Array) -> bool:
	for i in spectrum.size():
		if spectrum[i] > 1e-6:
			return true
	return false


## Builds UVs so the texture reads as one continuous surface across all facets.
## Higher texture_zoom uses a smaller region of the texture, while texture_offset
## slides that sampled region around within the source image. The optional
## facet warp then "unprojects" each facet locally based on its pseudo-3D normal
## so the shared texture field bends with the gemstone planes.
static func build_texture_uvs(
	unit_vertices: PackedVector2Array,
	facet_normal: Vector3,
	visual: GemVisualResource,
) -> PackedVector2Array:
	var shared_uvs := _build_shared_texture_space_uvs(unit_vertices, visual)
	if shared_uvs.is_empty() or visual.texture_facet_warp <= 0.001:
		return shared_uvs
	return _warp_texture_uvs_for_facet(shared_uvs, facet_normal, visual.texture_facet_warp)


static func _build_shared_texture_space_uvs(
	unit_vertices: PackedVector2Array,
	visual: GemVisualResource,
) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	if unit_vertices.is_empty():
		return uvs
	uvs.resize(unit_vertices.size())

	var zoom := maxf(visual.texture_zoom, 1.0)
	var half_span := 0.5 / zoom
	var center := Vector2(0.5, 0.5) + visual.texture_offset
	var min_uv := center - Vector2.ONE * half_span
	var max_uv := center + Vector2.ONE * half_span

	if min_uv.x < 0.0:
		max_uv.x -= min_uv.x
		min_uv.x = 0.0
	if min_uv.y < 0.0:
		max_uv.y -= min_uv.y
		min_uv.y = 0.0
	if max_uv.x > 1.0:
		min_uv.x -= max_uv.x - 1.0
		max_uv.x = 1.0
	if max_uv.y > 1.0:
		min_uv.y -= max_uv.y - 1.0
		max_uv.y = 1.0

	min_uv.x = clampf(min_uv.x, 0.0, 1.0)
	min_uv.y = clampf(min_uv.y, 0.0, 1.0)
	max_uv.x = clampf(max_uv.x, 0.0, 1.0)
	max_uv.y = clampf(max_uv.y, 0.0, 1.0)

	var span := Vector2(
		maxf(max_uv.x - min_uv.x, 0.0001),
		maxf(max_uv.y - min_uv.y, 0.0001)
	)

	for i in unit_vertices.size():
		var vertex := unit_vertices[i]
		uvs[i] = Vector2(
			min_uv.x + vertex.x * span.x,
			min_uv.y + vertex.y * span.y
		)
	return uvs


static func _warp_texture_uvs_for_facet(
	shared_uvs: PackedVector2Array,
	facet_normal: Vector3,
	warp_strength: float,
) -> PackedVector2Array:
	if shared_uvs.is_empty():
		return shared_uvs

	var normal := facet_normal.normalized()
	var tangent3 := Vector3(normal.z, 0.0, -normal.x)
	if tangent3.length_squared() < 0.00001:
		tangent3 = Vector3.RIGHT
	else:
		tangent3 = tangent3.normalized()

	var bitangent3 := normal.cross(tangent3)
	if bitangent3.length_squared() < 0.00001:
		bitangent3 = Vector3.DOWN
	else:
		bitangent3 = bitangent3.normalized()

	var proj_t := Vector2(tangent3.x, tangent3.y)
	var proj_b := Vector2(bitangent3.x, bitangent3.y)
	if proj_t.length_squared() < 0.00001 or proj_b.length_squared() < 0.00001:
		return shared_uvs

	# Prevent extreme near-edge-on normals from exploding the UV inverse.
	proj_t = proj_t.normalized() * maxf(proj_t.length(), 0.35)
	proj_b = proj_b.normalized() * maxf(proj_b.length(), 0.35)

	var det := proj_t.x * proj_b.y - proj_t.y * proj_b.x
	if absf(det) < 0.0001:
		return shared_uvs

	var centroid := Vector2.ZERO
	for uv in shared_uvs:
		centroid += uv
	centroid /= shared_uvs.size()

	var warped := PackedVector2Array()
	warped.resize(shared_uvs.size())
	var inv_det := 1.0 / det
	for i in shared_uvs.size():
		var local := shared_uvs[i] - centroid
		var unprojected := Vector2(
			(local.x * proj_b.y - local.y * proj_b.x) * inv_det,
			(-local.x * proj_t.y + local.y * proj_t.x) * inv_det
		)
		warped[i] = centroid + local.lerp(unprojected, warp_strength)
	return warped


## Converts the facet's shaded colour into a grayscale texture modulate so the
## texture follows the gem's light and shadow while preserving its own hues.
static func compute_texture_overlay_color(facet_color: Color, visual: GemVisualResource) -> Color:
	var brightness := clampf(facet_color.get_luminance() * 0.9 + 0.18, 0.0, 1.0)
	var alpha := clampf(visual.texture_blend * facet_color.a, 0.0, 1.0)
	return Color(brightness, brightness, brightness, alpha)


static func texture_uses_overlay_mode(visual: GemVisualResource) -> bool:
	if visual == null or not visual.use_texture or visual.color_texture == null:
		return false
	var image := visual.color_texture.get_image()
	if image == null:
		return false
	return image.detect_alpha() != Image.ALPHA_NONE


## Computes semi-transparent overlay colours for pavilion extinction fragments.
## Simplified fallback: uses darkened display_color as the extinction tint.
## Fragments that would reflect light poorly appear darker (more opaque).
static func compute_pavilion_colors(
	cut,
	visual: GemVisualResource,
	light_dir: Vector3 = DEFAULT_LIGHT_DIR,
) -> PackedColorArray:
	var colors = PackedColorArray()
	var count = int(cut.pavilion_count())
	if count == 0:
		return colors
	colors.resize(count)

	var l = light_dir.normalized()

	# Extinction colour: darkened display_color.
	var ext_color = visual.display_color.darkened(0.7)
	ext_color.a = 1.0

	for i in count:
		# Pavilion normals are pre-normalized at generation time.
		var n: Vector3 = cut.pavilion_normals[i]
		# Light return: how well the pavilion fragment reflects light back.
		var light_return := clampf(n.dot(l), 0.0, 1.0)
		# Poor light return → stronger extinction (more opaque overlay).
		var darkness := (1.0 - light_return)
		var alpha := darkness * 0.35
		colors[i] = Color(ext_color.r, ext_color.g, ext_color.b, clampf(alpha, 0.0, 0.85))

	return colors
