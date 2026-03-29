class_name GemRenderer
extends RefCounted

## Pure-math lighting calculations for faceted gem rendering.
## No scene-tree dependency — can run headlessly.

const DEFAULT_LIGHT_DIR := Vector3(-0.4, -0.5, 0.75)
const DEFAULT_VIEW_DIR := Vector3(0.0, 0.0, 1.0)
const AMBIENT := 0.15


## Computes the flat-shaded colour for a single facet.
## contrast: 0=flat Half-Lambert, 1=full standard Lambert (dramatic).
static func compute_facet_color(
	normal: Vector3,
	base_color: Color,
	shininess: float = 32.0,
	specular_intensity: float = 0.4,
	light_dir: Vector3 = DEFAULT_LIGHT_DIR,
	contrast: float = 0.3,
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
## material properties and optional modifier overrides.
##
## Adds per-facet shading variation so neighbouring facets are always
## distinguishable, even when their normals are similar.
static func compute_all_facet_colors(
	cut: GemCutResource,
	visual: GemVisualResource,
	light_dir: Vector3 = DEFAULT_LIGHT_DIR,
	modifiers: Dictionary = {},
) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(cut.facet_count())

	var base := visual.base_color

	# Modifier adjustments.
	if modifiers.has("darken"):
		base = base.darkened(modifiers["darken"])
	if modifiers.has("brighten"):
		base = base.lightened(modifiers["brighten"])
	if modifiers.has("desaturate"):
		var amount: float = modifiers["desaturate"]
		base.s = clampf(base.s - amount, 0.0, 1.0)

	# Optional depth tint for back-facing facets.
	var has_depth_tint := visual.depth_tint.a > 0.01
	var depth_color := visual.depth_tint

	for i in cut.facet_count():
		var n := cut.facet_normals[i]
		var facet_base := base

		# Depth-tint: mix in the tint colour for facets facing away from the viewer.
		if has_depth_tint:
			var facing := clampf(n.z, 0.0, 1.0)
			facet_base = base.lerp(depth_color, (1.0 - facing) * depth_color.a)

		# Texture sampling: use the colour at each facet's centroid.
		if visual.use_texture and visual.color_texture != null:
			facet_base = _sample_texture_at_facet(visual.color_texture, cut, i)

		colors[i] = compute_facet_color(
			n, facet_base, visual.shininess, visual.specular_intensity, light_dir,
			visual.contrast)

	# Prismatic hue dispersion: shift each facet's hue based on its normal angle.
	# Simulates light splitting into a spectrum ("fire") in high-refractive gems.
	if visual.hue_dispersion > 0.001:
		for i in cut.facet_count():
			var n := cut.facet_normals[i]
			# Use the normal's XY angle as the hue offset source.
			# atan2 gives a smooth rotation around the gem.
			var angle := atan2(n.y, n.x)  # -PI to PI
			var hue_shift := (angle / TAU) * visual.hue_dispersion
			var c := colors[i]
			c.h = fmod(c.h + hue_shift + 1.0, 1.0)
			# Boost saturation slightly so the hue shift is visible.
			c.s = clampf(c.s + visual.hue_dispersion * 0.5, 0.0, 1.0)
			colors[i] = c

	# Per-facet variation: add a subtle deterministic brightness jitter so
	# neighbouring facets with near-identical normals remain distinguishable.
	# The variation is based on the facet centroid position, producing a
	# consistent, non-random pattern that alternates between adjacent facets.
	for i in cut.facet_count():
		var verts := cut.facet_vertices[i]
		var cx := 0.0
		var cy := 0.0
		for v in verts:
			cx += v.x
			cy += v.y
		cx /= verts.size()
		cy /= verts.size()

		# Hash-like variation from centroid: produces values that differ
		# between nearby facets because their centroids differ.
		var hash_val := sin(cx * 127.1 + cy * 311.7) * 43758.5453
		hash_val = hash_val - floorf(hash_val)  # fractional part, 0..1
		var jitter := (hash_val - 0.5) * 0.08   # ±4% brightness variation

		var c := colors[i]
		colors[i] = Color(
			clampf(c.r + jitter, 0.0, 1.0),
			clampf(c.g + jitter, 0.0, 1.0),
			clampf(c.b + jitter, 0.0, 1.0),
			c.a,
		)

	# Saturation boost.
	if not is_zero_approx(visual.saturation_boost):
		for i in colors.size():
			var c := colors[i]
			c.s = clampf(c.s + visual.saturation_boost, 0.0, 1.0)
			colors[i] = c

	return colors


## Samples a texture at the centroid of a facet (for patterned gems like opals).
static func _sample_texture_at_facet(
	tex: Texture2D, cut: GemCutResource, facet_index: int,
) -> Color:
	var verts := cut.facet_vertices[facet_index]
	var centroid := Vector2.ZERO
	for v in verts:
		centroid += v
	centroid /= verts.size()
	# centroid is in [0,1] unit space — use as UV directly.
	var img := tex.get_image()
	if img == null:
		return Color.WHITE
	var px := clampi(int(centroid.x * img.get_width()), 0, img.get_width() - 1)
	var py := clampi(int(centroid.y * img.get_height()), 0, img.get_height() - 1)
	return img.get_pixel(px, py)
