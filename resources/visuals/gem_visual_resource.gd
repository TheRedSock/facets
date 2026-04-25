class_name GemVisualResource
extends Resource

## Defines the visual appearance of a specific gem type.
## References a GemCutSpecResource (resolved at runtime by GemVisualRegistry),
## a GemMineralTemplate for crystal physics, and specifies colour, material
## properties, and edge rendering.

const GemCutSpecResourceScript = preload("res://resources/visuals/gem_cut_spec_resource.gd")

const GRADIENT_MODE_LINEAR := 0
const GRADIENT_MODE_RADIAL := 1
const GRADIENT_MODE_RADIAL_INVERSE := 2
const MATERIAL_MODE_FACETED_TRANSPARENT := 0
const MATERIAL_MODE_PATTERNED_OPAQUE := 1
const MATERIAL_MODE_PATTERNED_TRANSLUCENT := 2
const MATERIAL_PATTERN_NONE := 0
const MATERIAL_PATTERN_BANDS := 1
const MATERIAL_PATTERN_CONCENTRIC := 2
const MATERIAL_PATTERN_FIBERS := 3
const MATERIAL_PATTERN_CELLS := 4
const MATERIAL_PATTERN_CLOUDS := 5
const MATERIAL_PATTERN_LAYERS := 6
const MATERIAL_PATTERN_GROWTH_ZONING := 7
const MATERIAL_REACTIVE_NONE := 0
const MATERIAL_REACTIVE_CHATTOYANCY := 1
const MATERIAL_REACTIVE_OPALESCENCE := 2
const MATERIAL_REACTIVE_IRIDESCENCE := 3

@export_group("Identity")
@export var visual_id: StringName = &""
## Mark as true for study, prototype, or otherwise non-production gems.
## These are excluded from batch bakes when using the "production" keyword.
@export var experimental: bool = false
@export var cut_spec: Resource = null
@export var cut_overrides: Dictionary = {}
## Migration-only compatibility label. Active geometry resolution should use
## `cut_spec` directly.
@export var cut_id: StringName = &""
## Rotates the cut in degrees before lighting and fit normalization.
## This keeps cut families axis-aligned while allowing per-gem orientation.
@export_range(-180.0, 180.0) var rotation_degrees: float = 0.0
## Facet edge rounding override (-1 = use cut spec default, 0+ = explicit value).
@export_range(-1.0, 1.0) var facet_edge_rounding_override: float = -1.0

# ==== Physical Source ====

@export_group("Physical Source")
## Reference to the mineral template for crystal physics (Sellmeier, absorption, etc.).
## All gems of the same mineral species share one template.
@export var mineral_template: Resource = null
## Optic axis for pleochroism (extraordinary-ray direction in model space). Used by the
## native tracer when the mineral has a `pleochroism_absorption_spectrum`. Must be
## non-zero when overriding; `Vector3.ZERO` keeps the tracer default axis.
@export var optic_axis: Vector3 = Vector3.ZERO
## Per-gem absorption spectrum override. If non-empty (81 floats at 5nm intervals),
## REPLACES the template's absorption_spectrum. Use this for different chromophores
## in the same crystal (e.g., ruby vs sapphire are both corundum, different Cr/Fe/Ti).
@export var absorption_spectrum_override: PackedFloat32Array = PackedFloat32Array()
## Per-gem pleochroism spectrum override. Spectrum (81 floats) sampled when the ray
## propagates ALONG the `optic_axis` direction. The main `absorption_spectrum(_override)`
## is sampled when the ray propagates PERPENDICULAR to the axis. The tracer blends
## the two with cos²(angle) so viewing down the c-axis of a dichroic gem (e.g. ruby
## viewed along c = orange-red, perpendicular = purple-red) reads its second pleochroic
## colour. Leave empty to disable pleochroism on this visual (falls back to the
## mineral template's `pleochroism_absorption_spectrum` if it has one).
@export var pleochroism_absorption_spectrum_override: PackedFloat32Array = PackedFloat32Array()
## Multiplier on the active absorption spectrum. 1.0 = use as-is.
## >1.0 = deeper color, <1.0 = lighter color. Scales the extinction coefficient.
@export_range(0.01, 10.0) var absorption_strength_scale: float = 1.0
## Per-gem surface roughness override. -1 = use mineral template default.
@export_range(-1.0, 1.0) var surface_roughness_override: float = -1.0
## Per-gem scattering coefficient override. -1 = use mineral template default.
@export_range(-1.0, 50.0) var scattering_coefficient_override: float = -1.0
## Per-gem fluorescence quantum yield override. -1 = use mineral template default.
@export_range(-1.0, 1.0) var fluorescence_quantum_yield_override: float = -1.0
## Per-gem surface anisotropy override. -1 = use mineral template default.
@export_range(-1.0, 1.0) var surface_roughness_anisotropy_override: float = -1.0

# ==== Color ====

@export_group("Color")
## Display color for UI and procedural fallback. NOT used in ray transport.
@export var display_color: Color = Color.WHITE

@export_subgroup("Gradient")
## Optional 81-sample target absorption curve for the gradient zone (380–780 nm, 5 nm steps),
## in the same authoring space as absorption spectra. When non-empty, the native tracer
## blends body absorption toward this curve in the gradient region instead of uplifting
## `gradient_color`. Empty = legacy RGB uplift path.
@export var gradient_zone_spectrum: PackedFloat32Array = PackedFloat32Array()
## Blends the display colour toward this colour using the selected zoning mode,
## simulating natural colour zoning (e.g. amethyst purple-to-white or
## tourmaline-style edge/core separation). Active only for faceted transparent gems;
## patterned materials should use their explicit material palette/pattern controls.
## Ignored by the tracer when `gradient_zone_spectrum` has 81 samples (procedural fallback still uses it if spectrum empty).
@export var gradient_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var gradient_strength: float = 0.0
@export_enum("Linear", "Radial", "Radial Inverse") var gradient_mode: int = GRADIENT_MODE_LINEAR
@export_range(-180.0, 180.0) var gradient_angle_degrees: float = 90.0
## Object-space XY offset (in radius-normalized units) applied before evaluating
## RADIAL / RADIAL_INVERSE modes. Use when the cut's geometric origin sits off
## the visual center of mass (trillion, pear, marquise) so the radial zone wraps
## the visible silhouette instead of a distant geometric point.
@export var gradient_center: Vector2 = Vector2.ZERO

@export_subgroup("Phenomenon")
## Optional 81-sample target absorption curve for angle-dependent phenomenon response.
## When non-empty, the tracer blends toward this curve instead of RGB uplift from
## `phenomenon_color`.
@export var phenomenon_zone_spectrum: PackedFloat32Array = PackedFloat32Array()
## Static dual-tone cue for color-change stones (e.g. alexandrite, blue garnet).
## The secondary colour is blended per facet based on facet orientation rather
## than using prismatic dispersion intended for diamond-like fire. Active only for
## faceted transparent gems; patterned materials should use reactive/material fields.
@export var phenomenon_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var phenomenon_strength: float = 0.0
@export_range(-180.0, 180.0) var phenomenon_angle_degrees: float = 0.0
@export_range(0.5, 4.0) var phenomenon_sharpness: float = 1.0

# ==== Lighting ====

@export_group("Lighting")
@export_subgroup("Edge Rendering")
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export_range(0.0, 3.0) var edge_width: float = 0.0

# ==== Detailing ====

@export_group("Detailing")
## Broad material family used by the traced and procedural paths.
@export_enum("Faceted Transparent", "Patterned Opaque", "Patterned Translucent") var material_mode: int = MATERIAL_MODE_FACETED_TRANSPARENT
## Explicit palette controls for patterned material modes.
@export var material_secondary_color: Color = Color.TRANSPARENT
@export var material_tertiary_color: Color = Color.TRANSPARENT
## If true, sample from color_texture instead of flat display_color.
## Useful for opals, agates, and other patterned gems.
@export var use_texture: bool = false
@export var color_texture: Texture2D = null
@export_range(0.0, 1.0) var texture_blend: float = 1.0
@export_range(1.0, 4.0) var texture_zoom: float = 1.0
@export var texture_offset: Vector2 = Vector2.ZERO
@export_range(0.0, 1.0) var texture_facet_warp: float = 0.35

@export_subgroup("Surface Field")
@export_enum("None", "Bands", "Concentric", "Fibers", "Cells", "Clouds", "Layers", "Growth Zoning") var surface_pattern_type: int = MATERIAL_PATTERN_NONE
@export_range(0.0, 1.0) var surface_pattern_mix: float = 0.0
@export var surface_pattern_scale: Vector2 = Vector2.ONE
@export_range(-180.0, 180.0) var surface_pattern_rotation_degrees: float = 0.0
@export_range(0.1, 8.0) var surface_pattern_density: float = 1.0
@export_range(0.0, 1.0) var surface_pattern_contrast: float = 0.5
@export_range(0.0, 1.0) var surface_pattern_warp_strength: float = 0.0
@export_range(0.1, 8.0) var surface_pattern_warp_scale: float = 1.0
@export_range(-1.0, 1.0) var surface_pattern_specular_variation: float = 0.0
@export_range(-1.0, 1.0) var surface_pattern_roughness_variation: float = 0.0

@export_subgroup("Volume Field")
@export_enum("None", "Bands", "Concentric", "Fibers", "Cells", "Clouds", "Layers", "Growth Zoning") var volume_pattern_type: int = MATERIAL_PATTERN_NONE
@export_range(0.0, 1.0) var volume_pattern_mix: float = 0.0
@export var volume_pattern_scale: Vector3 = Vector3.ONE
@export var volume_pattern_axis: Vector3 = Vector3.UP
@export_range(0.1, 8.0) var volume_pattern_density: float = 1.0
@export_range(0.0, 1.0) var volume_pattern_contrast: float = 0.5
@export_range(0.0, 1.0) var volume_pattern_warp_strength: float = 0.0
@export_range(0.1, 8.0) var volume_pattern_warp_scale: float = 1.0
@export_range(-1.0, 1.0) var volume_absorption_variation: float = 0.0
@export_range(-1.0, 1.0) var volume_scattering_variation: float = 0.0

@export_subgroup("Inclusions")
## Discrete inclusion geometry profile. null = no inclusions.
@export var inclusion_profile: Resource = null

@export_subgroup("Angle Reactive")
@export_enum("None", "Chatoyancy", "Opalescence", "Iridescence") var reactive_effect_type: int = MATERIAL_REACTIVE_NONE
@export var reactive_color: Color = Color.TRANSPARENT
@export var reactive_secondary_color: Color = Color.TRANSPARENT
@export_range(0.0, 3.0) var reactive_strength: float = 0.0
@export_range(0.5, 12.0) var reactive_sharpness: float = 2.0
@export_range(0.1, 8.0) var reactive_density: float = 1.0
@export_range(0.1, 8.0) var reactive_scale: float = 1.0
@export var reactive_axis: Vector3 = Vector3.RIGHT

# ==== Traced Optics ====

@export_group("Traced Optics")

@export_subgroup("Camera")
## Additional traced-bake framing scale applied after cut-specific fit compensation.
## Increase for stones that read too small in the traced showroom camera.
@export_range(0.5, 2.0) var optics_trace_view_scale: float = 1.0
## Default traced showroom camera angles. Request-level overrides still win.
@export_range(-89.0, 89.0) var optics_lighting_view_pitch_degrees: float = 0.0
@export_range(-180.0, 180.0) var optics_lighting_view_yaw_degrees: float = 0.0
@export_range(-89.0, 89.0) var optics_rotation_view_pitch_degrees: float = -26.0
@export_range(-180.0, 180.0) var optics_rotation_view_yaw_degrees: float = 36.0

@export_subgroup("Environment")
## Environment to use for baking. If null, uses the default gameplay environment.
@export var bake_environment: Resource = null
## Rotates the entire environment (sky + cards + blocker) around the vertical axis.
@export_range(-180.0, 180.0) var optics_environment_rotation_degrees: float = 0.0

@export_subgroup("Dispersion")
## When true, the tracer runs one independent path per hero wavelength, so each
## wavelength refracts along its own Snell direction at every surface. Produces
## physically-correct prismatic "fire" for high-dispersion gems (diamond, zircon,
## sphene). Cost: ~4x slower trace; leave off for low-dispersion gems.
@export var enable_dispersion: bool = false

# ==== Stylization ====

@export_group("Stylization")
## Blends between the traced result and the gameplay stylization pass.
## This keeps the traced output as the physical base while allowing
## readability-driven shaping for board textures.
@export_range(0.0, 1.0) var stylize_mix: float = 0.65
## Strength of facet-edge crisping driven by image-space discontinuity guides.
@export_range(0.0, 1.0) var stylize_facet_edge_gain: float = 0.55
## Pushes lit planes brighter and dark planes deeper by compressing midtones.
@export_range(0.0, 1.0) var stylize_plane_contrast: float = 0.35
## Minimum light preserved inside dark regions after the stylized tone remap.
@export_range(0.0, 0.35) var stylize_shadow_floor: float = 0.08
## Strength of the tightly-thresholded internal bloom pass.
@export_range(0.0, 1.0) var stylize_highlight_bloom_gain: float = 0.22
## Brightness threshold where the stylized bloom starts to appear.
@export_range(0.4, 1.0) var stylize_highlight_bloom_threshold: float = 0.8
## Suppresses low-amplitude micro detail while preserving major facet edges.
@export_range(0.0, 1.0) var stylize_microdetail_suppression: float = 0.28
## Extra guided saturation for internal dispersion/absorption color structure.
@export_range(0.0, 1.0) var stylize_internal_color_shift_gain: float = 0.2
## Quantizes lighting into a small number of broad tone bands for a more
## cel-shaded presentation while keeping the traced light response intact.
@export_range(2, 8, 1) var stylize_tone_steps: int = 5
## Darkens strong facet discontinuities with a tinted ink-like edge treatment.
@export_range(0.0, 1.0) var stylize_edge_ink_strength: float = 0.16
## Snaps very bright highlights into cleaner, more graphic specular shapes.
@export_range(0.0, 1.0) var stylize_highlight_snap: float = 0.24
## Per-gem WebP quality override for the offline bake pipeline.
## -1.0 = use the adaptive quality heuristic (based on dispersion, sparkle, etc.).
## 0.5-0.99 = explicit lossy quality.
## 1.0 = lossless WebP output for this gem.
@export_range(-1.0, 1.0) var bake_quality_override: float = -1.0


func resolve_cut_spec():
	var base_spec = cut_spec
	if base_spec == null:
		return null
	if not (base_spec is GemCutSpecResourceScript):
		return null
	if cut_overrides.is_empty():
		return base_spec.duplicate_spec()
	return base_spec.apply_overrides(cut_overrides)


func get_cut_spec_id() -> StringName:
	if cut_spec != null:
		return cut_spec.get_label_id()
	if cut_id != &"":
		return cut_id
	return &""


## Resolve effective edge rounding: per-gem override → cut spec default → 0.
## When using the cut-spec default (no per-gem override), applies polish coupling:
## minerals with lower surface roughness (higher polish) auto-suppress rounding.
## Diamond (0.005) → ~17% of cut default, corundum/garnet (0.008) → ~67%, quartz/beryl (0.01+) → full.
func get_effective_edge_rounding() -> float:
	if facet_edge_rounding_override >= 0.0:
		return facet_edge_rounding_override
	var base := 0.0
	if cut_spec != null and &"facet_edge_rounding" in cut_spec:
		base = cut_spec.facet_edge_rounding
	if base <= 0.0:
		return 0.0
	# Polish coupling: remap mineral roughness [0.004, 0.01] → [0, 1].
	# High-polish minerals (diamond 0.005, corundum 0.008) auto-suppress;
	# medium-polish (quartz/beryl 0.01+) pass through at full strength.
	var roughness := 0.01  # conservative default when no mineral template
	if mineral_template != null and &"default_surface_roughness" in mineral_template:
		roughness = mineral_template.default_surface_roughness
	var polish_factor := clampf((roughness - 0.004) / 0.006, 0.0, 1.0)
	return base * polish_factor


## Approximate sRGB from an 81-sample curve for procedural 2D fallback only.
static func zone_spectrum_to_display_color(spectrum: PackedFloat32Array) -> Color:
	if spectrum.size() != 81:
		return Color.WHITE
	var peak := 0.0001
	for i in 81:
		peak = maxf(peak, spectrum[i])
	if peak < 1e-8:
		return Color.WHITE
	# Rough band proxies: ~650 nm, ~530 nm, ~460 nm (indices 54, 30, 16).
	var r := clampf(spectrum[54] / peak, 0.0, 1.0)
	var g := clampf(spectrum[30] / peak, 0.0, 1.0)
	var b := clampf(spectrum[16] / peak, 0.0, 1.0)
	return Color(r, g, b)


const VISUAL_JSON_SCHEMA_VERSION := 1

## Geometry + resource refs excluded from the generic property loop (handled explicitly).
const _VISUAL_JSON_SKIP := [&"cut_spec", &"cut_overrides", &"cut_id", &"color_texture", &"mineral_template", &"bake_environment", &"inclusion_profile"]


## Serialize all visual (non-geometry) properties to a JSON-safe dictionary.
func build_visual_json_dict() -> Dictionary:
	var result := {"visual_json_schema_version": VISUAL_JSON_SCHEMA_VERSION}
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var n: StringName = prop.name
		if n.begins_with(&"resource_") or n == &"script":
			continue
		if n in _VISUAL_JSON_SKIP:
			continue
		result[String(n)] = _to_json_safe_value(get(n))
	if mineral_template != null and mineral_template.resource_path:
		result["mineral_template_path"] = mineral_template.resource_path
	if bake_environment != null and bake_environment.resource_path:
		result["bake_environment_path"] = bake_environment.resource_path
	if color_texture != null and color_texture.resource_path:
		result["color_texture_path"] = color_texture.resource_path
	return result


## Apply a JSON-parsed dictionary of visual properties.
func apply_visual_json_dict(data: Dictionary) -> void:
	var ver := int(data.get("visual_json_schema_version", 1))
	if ver > VISUAL_JSON_SCHEMA_VERSION:
		push_warning("GemVisualResource: visual JSON schema %d newer than supported %d" % [ver, VISUAL_JSON_SCHEMA_VERSION])

	var mpath := String(data.get("mineral_template_path", ""))
	if not mpath.is_empty() and ResourceLoader.exists(mpath):
		mineral_template = load(mpath)
	var epath := String(data.get("bake_environment_path", ""))
	if not epath.is_empty() and ResourceLoader.exists(epath):
		bake_environment = load(epath)
	var tpath := String(data.get("color_texture_path", ""))
	if not tpath.is_empty() and ResourceLoader.exists(tpath):
		color_texture = load(tpath)

	var prop_types := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR:
			prop_types[StringName(prop.name)] = prop.type
	for key in data.keys():
		var sk := String(key)
		if sk == "visual_json_schema_version" or sk.ends_with("_path"):
			continue
		var sn := StringName(key)
		if sn in _VISUAL_JSON_SKIP:
			continue
		if not prop_types.has(sn):
			continue
		var t: int = int(prop_types[sn])
		if t == TYPE_OBJECT:
			continue
		set(sn, _from_json_value(data[key], t))


static func _to_json_safe_value(value) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_STRING_NAME:
			return String(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			return Array(value)
		_:
			return value


static func _from_json_value(value, target_type: int) -> Variant:
	match target_type:
		TYPE_COLOR:
			if typeof(value) == TYPE_ARRAY and value.size() >= 4:
				return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return Color(float(value[0]), float(value[1]), float(value[2]), 1.0)
		TYPE_VECTOR2:
			if typeof(value) == TYPE_ARRAY and value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
		TYPE_VECTOR3:
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
		TYPE_STRING_NAME:
			return StringName(String(value))
		TYPE_FLOAT:
			return float(value)
		TYPE_INT:
			return int(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return String(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			if typeof(value) == TYPE_ARRAY:
				var arr := PackedFloat32Array()
				for v in value:
					arr.append(float(v))
				return arr
	return value
