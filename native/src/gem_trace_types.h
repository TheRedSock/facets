#pragma once
// Shared types for the native gem tracer.

#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/classes/image.hpp>

#include <vector>
#include <cmath>
#include <algorithm>

namespace gem {

// ---------------------------------------------------------------------------
// Constants matching GemOpticsTracer.gd
// ---------------------------------------------------------------------------
constexpr double AIR_IOR = 1.00029;
constexpr double EPSILON = 0.0005;
constexpr int    MAX_TRACE_BOUNCES = 12;
constexpr int    MAX_OVERRIDE_TRACE_BOUNCES = 24;
constexpr double MIN_BRANCH_WEIGHT = 0.001;
constexpr int    DEFAULT_SAMPLE_COUNT = 2;
constexpr double VIEW_MARGIN = 1.18;
constexpr int    MIN_ROWS_PER_TRACE_THREAD = 8;
constexpr int    MIN_PIXELS_PER_TRACE_THREAD = 6144;
constexpr int    MIN_WORK_UNITS_PER_TRACE_THREAD = 20000;

// ACES tonemapping constants
constexpr double ACES_A = 2.51;
constexpr double ACES_B = 0.03;
constexpr double ACES_C = 2.43;
constexpr double ACES_D = 0.59;
constexpr double ACES_E = 0.14;

// GemVisualResource material mode constants
constexpr int MATERIAL_MODE_FACETED_TRANSPARENT = 0;
constexpr int MATERIAL_MODE_PATTERNED_OPAQUE    = 1;
constexpr int MATERIAL_MODE_PATTERNED_TRANSLUCENT = 2;

// GemVisualResource material pattern constants
constexpr int MATERIAL_PATTERN_NONE       = 0;
constexpr int MATERIAL_PATTERN_BANDS      = 1;
constexpr int MATERIAL_PATTERN_CONCENTRIC = 2;
constexpr int MATERIAL_PATTERN_FIBERS     = 3;
constexpr int MATERIAL_PATTERN_CELLS      = 4;
constexpr int MATERIAL_PATTERN_CLOUDS     = 5;
constexpr int MATERIAL_PATTERN_LAYERS     = 6;

// GemVisualResource reactive effect constants
constexpr int MATERIAL_REACTIVE_NONE         = 0;
constexpr int MATERIAL_REACTIVE_CHATTOYANCY  = 1;
constexpr int MATERIAL_REACTIVE_OPALESCENCE  = 2;
constexpr int MATERIAL_REACTIVE_IRIDESCENCE  = 3;

// GemVisualResource gradient mode constants
constexpr int GRADIENT_MODE_LINEAR         = 0;
constexpr int GRADIENT_MODE_RADIAL         = 1;
constexpr int GRADIENT_MODE_RADIAL_INVERSE = 2;

// GemVisualResource environment preset constants
constexpr int OPTICS_ENVIRONMENT_NEUTRAL         = 0;
constexpr int OPTICS_ENVIRONMENT_DARK_STUDIO     = 1;
constexpr int OPTICS_ENVIRONMENT_GEM_BOOTH       = 2;
constexpr int OPTICS_ENVIRONMENT_GAMEPLAY_STUDIO = 3;
constexpr int OPTICS_ENVIRONMENT_DEEP_COLOR      = 4;

// ---------------------------------------------------------------------------
// MSAA sample pattern (matching GDScript SAMPLE_PATTERN)
// ---------------------------------------------------------------------------
struct SampleOffset { double x, y; };
constexpr SampleOffset SAMPLE_PATTERN[5] = {
    { 0.5,  0.5  }, // center
    { 0.25, 0.25 }, // top-left
    { 0.75, 0.25 }, // top-right
    { 0.25, 0.75 }, // bottom-left
    { 0.75, 0.75 }, // bottom-right
};
constexpr int MAX_SAMPLE_COUNT = 5;

// ---------------------------------------------------------------------------
// Hit record returned by intersection queries
// ---------------------------------------------------------------------------
struct HitResult {
    bool     did_hit      = false;
    double   distance     = 1e30;
    int      triangle_idx = -1;
    godot::Vector3 position;
    godot::Vector3 normal;
    godot::StringName zone;
    bool     front_face   = true;
};

// ---------------------------------------------------------------------------
// Spectral sample (wavelength_t + per-channel weight)
// ---------------------------------------------------------------------------
struct SpectralSample {
    double t;
    godot::Vector3 weight;
};

// ---------------------------------------------------------------------------
// Environment light card
// ---------------------------------------------------------------------------
struct LightCard {
    godot::Vector3 dir;
    godot::Color   color = godot::Color(1, 1, 1, 1);
    double sharp_power    = 72.0;
    double broad_power    = 14.0;
    double sharp_strength = 0.5;
    double broad_strength = 0.3;
    // Spectral temperature: 0 = use color directly, >0 = Planck blackbody (Kelvin)
    double temperature_kelvin = 0.0;
    // Gradient card: edge_color at lobe periphery, gradient_power controls ramp shape
    godot::Color edge_color    = godot::Color(1, 1, 1, 1);
    double gradient_power      = 1.0;
};

// ---------------------------------------------------------------------------
// Environment setup (resolved once per trace)
// ---------------------------------------------------------------------------
struct EnvironmentSetup {
    godot::Color sky_low       = godot::Color(0.12f, 0.15f, 0.20f, 1.0f);
    godot::Color sky_top       = godot::Color(0.28f, 0.33f, 0.42f, 1.0f);
    godot::Color horizon       = godot::Color(0.62f, 0.48f, 0.32f, 1.0f);
    godot::Color ground_dark   = godot::Color(0.015f, 0.012f, 0.010f, 1.0f);
    godot::Color ground_lift   = godot::Color(0.08f, 0.06f, 0.04f, 1.0f);
    std::vector<LightCard> cards;
    godot::Vector3 blocker_dir;
    double blocker_power       = 10.0;
    double blocker_strength    = 0.0;
    // Ground plane bounce: virtual Lambertian surface below the gem
    double ground_albedo       = 0.0;   // 0 = disabled (current behavior)
    godot::Color ground_tint   = godot::Color(0.90f, 0.85f, 0.78f, 1.0f);
    double ground_distance     = 0.8;   // Normalized gem-radii below center
};

// ---------------------------------------------------------------------------
// Surface lighting setup (resolved once per trace)
// ---------------------------------------------------------------------------
struct SurfaceSetup {
    godot::StringName variant_type;
    godot::Vector2    lighting_uv;
    godot::Color      scatter_color;
    godot::Color      highlight_tint;
    godot::Color      specular_color;
    godot::Color      rim_tint;
    double            optics_ior_mid = 1.62;
    godot::Vector3    default_light_dir;
};

// ---------------------------------------------------------------------------
// Trace flags (resolved once per trace from visual)
// ---------------------------------------------------------------------------
struct TraceFlags {
    bool   is_patterned_opaque  = false;
    bool   has_volume_sampling  = false;
    bool   has_surface_material = false;
    bool   has_reactive         = false;
    double transmission_factor  = 1.0;
    double cloudiness           = 0.0;
};

// ---------------------------------------------------------------------------
// Zone surface scales
// ---------------------------------------------------------------------------
struct ZoneSurfaceScales {
    double front     = 1.0;
    double back      = 1.0;
    double spec      = 1.0;
    double body      = 1.0;
    double caustic   = 1.0;
    double interface_ = 1.0; // 'interface' is reserved in MSVC
};

// ---------------------------------------------------------------------------
// Material sample results (from procedural patterns)
// ---------------------------------------------------------------------------
struct SurfaceMaterialSample {
    godot::Color color;
    double pattern_value  = 0.5;
    double accent_value   = 0.0;
    double roughness_mult = 1.0;
    double specular_mult  = 1.0;
};

struct VolumeMaterialSample {
    godot::Color color;
    double pattern_value   = 0.5;
    double accent_value    = 0.5;
    double absorption_mult = 1.0;
    double scattering_mult = 1.0;
};

struct PatternSample {
    double value  = 0.5;
    double accent = 0.5;
};

struct CellularResult {
    double distance      = 0.0;
    double edge_distance = 0.0;
    double seed          = 0.5;
};

// ---------------------------------------------------------------------------
// Flattened visual properties (extracted once from GemVisualResource)
// ---------------------------------------------------------------------------
struct VisualProps {
    // Colour
    godot::Color base_color = godot::Color(1, 1, 1, 1);
    int material_mode = MATERIAL_MODE_FACETED_TRANSPARENT;
    godot::Color material_secondary_color;
    godot::Color material_tertiary_color;
    bool use_texture = false;
    double texture_blend = 1.0;
    double texture_zoom = 1.0;
    godot::Vector2 texture_offset;
    double texture_facet_warp = 0.35;

    // Surface pattern
    int surface_pattern_type = MATERIAL_PATTERN_NONE;
    double surface_pattern_mix = 0.0;
    godot::Vector2 surface_pattern_scale = godot::Vector2(1, 1);
    double surface_pattern_rotation_degrees = 0.0;
    double surface_pattern_density = 1.0;
    double surface_pattern_contrast = 0.5;
    double surface_pattern_warp_strength = 0.0;
    double surface_pattern_warp_scale = 1.0;
    double surface_pattern_specular_variation = 0.0;
    double surface_pattern_roughness_variation = 0.0;

    // Volume pattern
    int volume_pattern_type = MATERIAL_PATTERN_NONE;
    double volume_pattern_mix = 0.0;
    godot::Vector3 volume_pattern_scale = godot::Vector3(1, 1, 1);
    godot::Vector3 volume_pattern_axis = godot::Vector3(0, 1, 0);
    double volume_pattern_density = 1.0;
    double volume_pattern_contrast = 0.5;
    double volume_pattern_warp_strength = 0.0;
    double volume_pattern_warp_scale = 1.0;
    double volume_absorption_variation = 0.0;
    double volume_scattering_variation = 0.0;

    // Reactive
    int reactive_effect_type = MATERIAL_REACTIVE_NONE;
    godot::Color reactive_color;
    godot::Color reactive_secondary_color;
    double reactive_strength = 0.0;
    double reactive_sharpness = 2.0;
    double reactive_density = 1.0;
    double reactive_scale = 1.0;
    godot::Vector3 reactive_axis = godot::Vector3(1, 0, 0);

    // Material properties
    double shininess = 32.0;
    double specular_intensity = 0.4;
    double transparency = 0.0;
    godot::Color depth_tint;
    double saturation_boost = 0.0;
    double contrast = 0.3;
    double hue_dispersion = 0.0;

    // Rim
    double rim_intensity = 0.0;
    godot::Color rim_color = godot::Color(1, 1, 1, 1);
    double rim_power = 2.0;

    // Translucency
    double translucency = 0.0;
    godot::Color translucency_color = godot::Color(1, 1, 1, 1);

    // Secondary specular
    double secondary_specular = 0.0;
    double secondary_light_angle = 120.0;

    // Sparkle
    double sparkle_intensity = 0.0;
    double sparkle_threshold = 0.85;

    // Gradient
    godot::Color gradient_color;
    double gradient_strength = 0.0;
    int gradient_mode = GRADIENT_MODE_LINEAR;
    double gradient_angle_degrees = 90.0;

    // Phenomenon
    godot::Color phenomenon_color;
    double phenomenon_strength = 0.0;
    double phenomenon_angle_degrees = 0.0;
    double phenomenon_sharpness = 1.0;

    // Zone brilliance / extinction
    double brilliance_contrast = 0.0;
    double extinction = 0.0;

    // Optics
    double optics_ior = 1.62;
    double optics_dispersion = 0.018;
    godot::Color optics_absorption_color;
    double optics_absorption_strength = 1.1;
    double optics_surface_roughness = 0.02;
    double optics_scattering_strength = 0.0;
    godot::Color optics_scattering_color = godot::Color(1, 1, 1, 1);
    double optics_trace_view_scale = 1.0;
    double optics_birefringence_strength = 0.0;
    godot::Vector3 optics_optic_axis = godot::Vector3(0, 1, 0);
    double optics_lighting_view_pitch_degrees = 0.0;
    double optics_lighting_view_yaw_degrees = 0.0;
    double optics_rotation_view_pitch_degrees = -26.0;
    double optics_rotation_view_yaw_degrees = 36.0;
    int optics_environment_preset = OPTICS_ENVIRONMENT_NEUTRAL;
    double optics_environment_rotation_degrees = 0.0;
    double optics_environment_energy = 1.0;
    double optics_light_energy = 2.4;

    // Per-gem environment overrides (-1 / transparent = use preset default)
    double optics_ground_albedo_override   = -1.0;
    godot::Color optics_ground_tint_override = godot::Color(0, 0, 0, 0);
    double optics_ground_distance_override = -1.0;
    double optics_light_temperature_kelvin = 0.0;

    double rotation_degrees = 0.0;

    // Per-gem tuning overrides (-1.0 = use default/auto, 1.0 = no change for multipliers)
    double optics_interface_highlight_scale = 1.0;
    double optics_sparkle_power_multiplier = 1.0;
    double optics_rim_strength_multiplier = 1.0;
    double optics_blocker_strength_multiplier = 1.0;
    double optics_cloudiness_override = -1.0;      // -1 = auto from scattering/roughness/translucency
    double optics_transmission_override = -1.0;     // -1 = auto from material_mode
    double optics_grade_exposure = -1.0;            // -1 = auto formula
    double optics_grade_saturation = -1.0;          // -1 = auto formula
};

// ---------------------------------------------------------------------------
// Trace context (everything the per-pixel loop needs, fully resolved)
// ---------------------------------------------------------------------------
struct TraceContext {
    godot::Vector2i target_size;
    godot::Basis    inverse_basis;
    double          half_width  = 0.0;
    double          half_height = 0.0;
    double          origin_z    = 0.0;
    godot::Vector3  dir;
    godot::Vector3  light_dir;
    godot::Vector3  view_dir;
    int             sample_count = 2;
    int             max_bounces  = MAX_TRACE_BOUNCES;
    double          radius       = 0.5;
    godot::Vector3  optic_axis   = godot::Vector3(0, 1, 0);

    std::vector<SpectralSample> spectral_samples;

    VisualProps     visual;
    TraceFlags      flags;
    EnvironmentSetup environment;
    SurfaceSetup    surface;

    // Request-level overrides (empty/negative = use compiled defaults)
    godot::Dictionary zone_surface_scale_overrides;
    double grade_exposure_base = -1.0;
    double grade_range_compression_base = -1.0;
    double grade_highlight_rolloff_base = -1.0;
    double grade_saturation_base = -1.0;
    double grade_body_push_cap = -1.0;
    double grade_post_saturation_base = -1.0;
    double grade_opaque_exposure_scale = -1.0;
    double grade_translucent_exposure_scale = -1.0;

    // Optional texture image (null if not used)
    godot::Ref<godot::Image> texture_image;
};

// ---------------------------------------------------------------------------
// Inline math helpers
// ---------------------------------------------------------------------------
inline double clampd(double v, double lo, double hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
inline int clampi(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
inline double lerpd(double a, double b, double t) {
    return a + (b - a) * t;
}
inline double smoothstepd(double edge0, double edge1, double x) {
    double t = clampd((x - edge0) / (edge1 - edge0 + 1e-12), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
inline godot::Vector3 vec3_clamp(godot::Vector3 v, double lo, double hi) {
    return godot::Vector3(clampd(v.x, lo, hi), clampd(v.y, lo, hi), clampd(v.z, lo, hi));
}
inline godot::Color color_lerp(godot::Color a, godot::Color b, double t) {
    return godot::Color(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t
    );
}

} // namespace gem
