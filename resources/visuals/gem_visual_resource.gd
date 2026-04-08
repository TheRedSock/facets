class_name GemVisualResource
extends Resource

## Defines the visual appearance of a specific gem type.
## References a GemCutSpecResource (resolved at runtime by GemVisualRegistry)
## and specifies colour, material properties, and edge rendering.

const GemCutSpecResourceScript = preload("res://resources/visuals/gem_cut_spec_resource.gd")

const GRADIENT_MODE_LINEAR := 0
const GRADIENT_MODE_RADIAL := 1
const GRADIENT_MODE_RADIAL_INVERSE := 2
const OPTICS_ENVIRONMENT_NEUTRAL := 0
const OPTICS_ENVIRONMENT_DARK_STUDIO := 1
const OPTICS_ENVIRONMENT_GEM_BOOTH := 2
const OPTICS_ENVIRONMENT_GAMEPLAY_STUDIO := 3
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
const MATERIAL_REACTIVE_NONE := 0
const MATERIAL_REACTIVE_CHATTOYANCY := 1
const MATERIAL_REACTIVE_OPALESCENCE := 2
const MATERIAL_REACTIVE_IRIDESCENCE := 3

@export_group("Identity")
@export var visual_id: StringName = &""
@export var cut_spec: Resource = null
@export var cut_overrides: Dictionary = {}
## Migration-only compatibility label. Active geometry resolution should use
## `cut_spec` directly.
@export var cut_id: StringName = &""
## Rotates the cut in degrees before lighting and fit normalization.
## This keeps cut families axis-aligned while allowing per-gem orientation.
@export_range(-180.0, 180.0) var rotation_degrees: float = 0.0

# ==== Color ====

@export_group("Color")
@export var base_color: Color = Color.WHITE
## Colour shift applied to facets facing away from the viewer,
## simulating light passing through a transparent stone.
@export var depth_tint: Color = Color.TRANSPARENT
@export_range(-0.5, 0.5) var saturation_boost: float = 0.0
## Prismatic hue dispersion ("fire").  Each facet shifts its hue
## based on its angle, simulating light splitting into a spectrum.
## 0.0 = no dispersion (most gems).  0.3+ = visible rainbow fire (diamond).
@export_range(0.0, 0.5) var hue_dispersion: float = 0.0
## Brightens table/star facets and darkens girdle facets, simulating the
## characteristic "window" of light through a well-cut gem's table.
@export_range(0.0, 1.0) var brilliance_contrast: float = 0.0
## Simulates pavilion extinction — the geometric dark patterns caused by
## light bouncing off internal facets and failing to return to the viewer.
## Higher values produce stronger dark patches — effective for
## transparent/brilliant gems, should be low for opaque/matte stones.
@export_range(0.0, 1.0) var extinction: float = 0.0

@export_subgroup("Gradient")
## Blends the base colour toward this colour using the selected zoning mode,
## simulating natural colour zoning (e.g. amethyst purple-to-white or
## tourmaline-style edge/core separation).
@export var gradient_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var gradient_strength: float = 0.0
@export_enum("Linear", "Radial", "Radial Inverse") var gradient_mode: int = GRADIENT_MODE_LINEAR
@export_range(-180.0, 180.0) var gradient_angle_degrees: float = 90.0

@export_subgroup("Phenomenon")
## Static dual-tone cue for color-change stones (e.g. alexandrite, blue garnet).
## The secondary colour is blended per facet based on facet orientation rather
## than using prismatic dispersion intended for diamond-like fire.
@export var phenomenon_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var phenomenon_strength: float = 0.0
@export_range(-180.0, 180.0) var phenomenon_angle_degrees: float = 0.0
@export_range(0.5, 4.0) var phenomenon_sharpness: float = 1.0

@export_subgroup("Rim Lighting")
## Bright edge glow on facets facing away from the viewer (Fresnel effect).
## Simulates light catching the gem perimeter.
@export_range(0.0, 1.0) var rim_intensity: float = 0.0
@export var rim_color: Color = Color.WHITE
## Controls the falloff curve: higher = tighter rim, lower = broader glow.
@export_range(1.0, 5.0) var rim_power: float = 2.0

@export_subgroup("Translucency")
## Simulates light entering from behind the gem and bleeding through to the
## front (subsurface scattering approximation).  Additive on front-facing
## facets, unlike depth_tint which replaces colour on back-facing facets.
@export_range(0.0, 1.0) var translucency: float = 0.0
@export var translucency_color: Color = Color.WHITE

@export_subgroup("Sparkle")
## Dramatic brightness boost on facets whose specular alignment exceeds the
## threshold.  Simulates the intense white flashes seen in real gems.
@export_range(0.0, 3.0) var sparkle_intensity: float = 0.0
## Specular alignment above which the sparkle kicks in (0 = all facets, 1 = none).
@export_range(0.0, 1.0) var sparkle_threshold: float = 0.85

# ==== Lighting ====

@export_group("Lighting")
@export_range(1.0, 256.0) var shininess: float = 32.0
@export_range(0.0, 1.0) var specular_intensity: float = 0.4
@export_range(0.0, 1.0) var transparency: float = 0.0
## Controls the light-to-dark range across facets.
## 0.0 = flat, uniform shading (common stones).
## 1.0 = dramatic, high-contrast faceting (precious gems).
@export_range(0.0, 1.0) var contrast: float = 0.3

@export_subgroup("Secondary Specular")
## A second Blinn-Phong specular highlight from a different light angle,
## simulating internal reflections within a faceted stone.
@export_range(0.0, 1.0) var secondary_specular: float = 0.0
## Angle offset (degrees) from the primary light for the secondary highlight.
@export_range(0.0, 360.0) var secondary_light_angle: float = 120.0

@export_subgroup("Edge Rendering")
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export_range(0.0, 3.0) var edge_width: float = 0.0

# ==== Detailing ====

@export_group("Detailing")
## Broad material family used by the traced and procedural paths.
@export_enum("Faceted Transparent", "Patterned Opaque", "Patterned Translucent") var material_mode: int = MATERIAL_MODE_FACETED_TRANSPARENT
@export var material_secondary_color: Color = Color.TRANSPARENT
@export var material_tertiary_color: Color = Color.TRANSPARENT
## If true, sample from color_texture instead of flat base_color.
## Useful for opals, agates, and other patterned gems.
@export var use_texture: bool = false
@export var color_texture: Texture2D = null
@export_range(0.0, 1.0) var texture_blend: float = 1.0
@export_range(1.0, 4.0) var texture_zoom: float = 1.0
@export var texture_offset: Vector2 = Vector2.ZERO
@export_range(0.0, 1.0) var texture_facet_warp: float = 0.35

@export_subgroup("Surface Field")
@export_enum("None", "Bands", "Concentric", "Fibers", "Cells", "Clouds", "Layers") var surface_pattern_type: int = MATERIAL_PATTERN_NONE
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
@export_enum("None", "Bands", "Concentric", "Fibers", "Cells", "Clouds", "Layers") var volume_pattern_type: int = MATERIAL_PATTERN_NONE
@export_range(0.0, 1.0) var volume_pattern_mix: float = 0.0
@export var volume_pattern_scale: Vector3 = Vector3.ONE
@export var volume_pattern_axis: Vector3 = Vector3.UP
@export_range(0.1, 8.0) var volume_pattern_density: float = 1.0
@export_range(0.0, 1.0) var volume_pattern_contrast: float = 0.5
@export_range(0.0, 1.0) var volume_pattern_warp_strength: float = 0.0
@export_range(0.1, 8.0) var volume_pattern_warp_scale: float = 1.0
@export_range(-1.0, 1.0) var volume_absorption_variation: float = 0.0
@export_range(-1.0, 1.0) var volume_scattering_variation: float = 0.0

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

@export_subgroup("Refraction")
## Dielectric index of refraction used by the offline traced bake path.
## Typical gemstones live roughly in the 1.45-2.45 range.
@export_range(1.0, 3.0) var optics_ior: float = 1.62
## Channel-to-channel IOR spread used for spectral splitting.
## Blue gets a slightly higher IOR than red when this is non-zero.
@export_range(0.0, 0.2) var optics_dispersion: float = 0.018
## Uniaxial birefringence amount for the traced path.
## 0.0 disables double refraction. Corundum is roughly 0.008.
@export_range(0.0, 0.05) var optics_birefringence_strength: float = 0.0
@export var optics_optic_axis: Vector3 = Vector3.UP

@export_subgroup("Absorption & Scattering")
## Beer-Lambert absorption tint for the traced path. If left transparent, the
## traced bake derives a tint from base_color and depth_tint.
@export var optics_absorption_color: Color = Color.TRANSPARENT
@export_range(0.0, 8.0) var optics_absorption_strength: float = 1.1
## Surface polish / microsurface roughness for the traced path.
@export_range(0.0, 1.0) var optics_surface_roughness: float = 0.02
## Forward-scattering approximation for cloudy or silky gems.
@export_range(0.0, 1.0) var optics_scattering_strength: float = 0.0
@export var optics_scattering_color: Color = Color.WHITE

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
## Scales the environment and direct light contribution used during traced baking.
@export_enum("Neutral Sky", "Dark Studio", "Gem Booth", "Gameplay Studio") var optics_environment_preset: int = OPTICS_ENVIRONMENT_NEUTRAL
@export_range(-180.0, 180.0) var optics_environment_rotation_degrees: float = 0.0
@export_range(0.0, 4.0) var optics_environment_energy: float = 1.0
@export_range(0.0, 8.0) var optics_light_energy: float = 2.4

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


const _VISUAL_JSON_SKIP := [&"cut_spec", &"cut_overrides", &"cut_id", &"color_texture"]


## Serialize all visual (non-geometry) properties to a JSON-safe dictionary.
func build_visual_json_dict() -> Dictionary:
	var result := {}
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var n: StringName = prop.name
		if n.begins_with(&"resource_") or n == &"script":
			continue
		if n in _VISUAL_JSON_SKIP:
			continue
		result[String(n)] = _to_json_safe_value(get(n))
	return result


## Apply a JSON-parsed dictionary of visual properties.
func apply_visual_json_dict(data: Dictionary) -> void:
	var prop_types := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR:
			prop_types[StringName(prop.name)] = prop.type
	for key in data.keys():
		var sn := StringName(key)
		if sn in _VISUAL_JSON_SKIP:
			continue
		if not prop_types.has(sn):
			continue
		set(sn, _from_json_value(data[key], prop_types[sn]))


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
	return value
