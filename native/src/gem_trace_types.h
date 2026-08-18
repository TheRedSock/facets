// gem_trace_types.h — Shared types and constants for the new spectral path tracer.
// Replaces the old Whitted-style tracer types.
#pragma once

#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/classes/image.hpp>

#include <vector>
#include <cmath>
#include <string>
#include <atomic>

namespace gem {

using godot::Vector3;
using godot::Vector2;
using godot::Vector2i;
using godot::Color;
using godot::StringName;
using godot::Basis;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

static constexpr double AIR_IOR = 1.0;
static constexpr double TRACE_EPSILON = 0.0005;
static constexpr int    MAX_BOUNCES = 128;
static constexpr int    RR_START_BOUNCE = 5;        // Start throughput cutoff after this many bounces
static constexpr int    HERO_WAVELENGTHS = 4;       // Wavelengths per path (multi-hero spectral)
static constexpr double PI = 3.14159265358979323846;
static constexpr double TWO_PI = 6.28318530717958647692;
static constexpr double INV_PI = 0.31830988618379067154;

// View margin for camera projection (retained from old kernel)
static constexpr double VIEW_MARGIN = 1.18;

// Thread pool sizing (retained from old kernel)
static constexpr int MIN_ROWS_PER_TRACE_THREAD = 8;
static constexpr int MIN_PIXELS_PER_TRACE_THREAD = 6144;
static constexpr int MIN_WORK_UNITS_PER_TRACE_THREAD = 20000;

// Spectral constants
static constexpr double LAMBDA_MIN = 380.0;   // nm
static constexpr double LAMBDA_MAX = 780.0;   // nm
static constexpr double LAMBDA_RANGE = 400.0;  // nm
static constexpr int    SPECTRUM_SAMPLES = 81; // 5nm intervals, 380-780nm
static constexpr double SPECTRUM_STEP = 5.0;   // nm

// CIE 1931 ȳ(λ) integral over 380-780nm at 5nm intervals.
// = Σ CIE_Y[i] * SPECTRUM_STEP ≈ 106.856895
// Used to normalize the spectral MC estimator so that Y=1 corresponds
// to unit spectral radiance under the equal-energy illuminant.
static constexpr double CIE_Y_INTEGRAL = 106.856895;

// ACES tonemapping constants
static constexpr double ACES_A = 2.51;
static constexpr double ACES_B = 0.03;
static constexpr double ACES_C = 2.43;
static constexpr double ACES_D = 0.59;
static constexpr double ACES_E = 0.14;

// Material modes
static constexpr int MATERIAL_MODE_FACETED_TRANSPARENT = 0;
static constexpr int MATERIAL_MODE_PATTERNED_OPAQUE = 1;
static constexpr int MATERIAL_MODE_PATTERNED_TRANSLUCENT = 2;

// Pattern types
static constexpr int MATERIAL_PATTERN_NONE = 0;
static constexpr int MATERIAL_PATTERN_BANDS = 1;
static constexpr int MATERIAL_PATTERN_CONCENTRIC = 2;
static constexpr int MATERIAL_PATTERN_FIBERS = 3;
static constexpr int MATERIAL_PATTERN_CELLS = 4;
static constexpr int MATERIAL_PATTERN_CLOUDS = 5;
static constexpr int MATERIAL_PATTERN_LAYERS = 6;
static constexpr int MATERIAL_PATTERN_GROWTH_ZONING = 7;
static constexpr int MATERIAL_PATTERN_STRUCTURED_HAZE = 8;

// Reactive types
static constexpr int MATERIAL_REACTIVE_NONE = 0;
static constexpr int MATERIAL_REACTIVE_CHATOYANCY = 1;
static constexpr int MATERIAL_REACTIVE_OPALESCENCE = 2;
static constexpr int MATERIAL_REACTIVE_IRIDESCENCE = 3;

// Gradient modes
static constexpr int GRADIENT_MODE_LINEAR = 0;
static constexpr int GRADIENT_MODE_RADIAL = 1;
static constexpr int GRADIENT_MODE_RADIAL_INVERSE = 2;

// ---------------------------------------------------------------------------
// GemTraceProps — all material/visual properties needed at trace time.
// Populated from GemMineralTemplate + GemVisualResource + request.
// ---------------------------------------------------------------------------

struct GemTraceProps {
    // --- From GemMineralTemplate (crystal physics) ---

    // Sellmeier dispersion: n²(λ) = 1 + B1·λ²/(λ²-C1) + B2·λ²/(λ²-C2) + B3·λ²/(λ²-C3)
    // B values are dimensionless, C values are in μm².
    Vector3 sellmeier_b = Vector3(0.696f, 0.408f, 0.898f);   // default: quartz
    Vector3 sellmeier_c = Vector3(0.00468f, 0.01351f, 97.934f);

    // Absorption spectrum: α(λ) at 5nm intervals, 380-780nm.
    // 81 values. Units: extinction coefficient per model-space unit.
    // Empty = fully transparent (no absorption).
    std::vector<float> absorption_spectrum;

    // Scattering
    double scattering_coefficient = 0.0; // σ_s, model-space units. 0 = no scattering.
    double scattering_anisotropy = 0.0;  // Henyey-Greenstein g. 0=isotropic, +1=forward, -1=back.

    // Fluorescence
    double fluorescence_quantum_yield = 0.0;
    double fluorescence_excitation_center_nm = 550.0;
    double fluorescence_excitation_width_nm = 30.0;
    double fluorescence_emission_center_nm = 694.0;
    double fluorescence_emission_width_nm = 15.0;

    // Birefringence
    double birefringence_delta_n = 0.0; // 0 = isotropic
    Vector3 optic_axis = Vector3(0, 1, 0);

    // Pleochroism (direction-dependent absorption along extraordinary axis).
    // If empty, absorption is the same in all directions.
    std::vector<float> pleochroism_absorption_spectrum;

    // Surface roughness (GGX α parameter, 0 = perfect mirror, >0 = rough)
    double surface_roughness = 0.01;

    // --- From GemVisualResource (per-gem) ---

    int material_mode = MATERIAL_MODE_FACETED_TRANSPARENT;

    // Per-gem absorption override: if non-empty, REPLACES template absorption_spectrum.
    std::vector<float> absorption_spectrum_override;

    // Multiplier on the active absorption spectrum magnitude.
    double absorption_strength_scale = 1.0;

    // Per-gem scattering override (-1 = use template default)
    double scattering_coefficient_override = -1.0;

    // Per-gem roughness override (-1 = use template default)
    double surface_roughness_override = -1.0;

    // Per-gem fluorescence quantum yield override (-1 = use template default)
    double fluorescence_quantum_yield_override = -1.0;

    // Surface roughness anisotropy (0 = isotropic, >0 = elongated highlights)
    double surface_anisotropy = 0.0;
    double surface_anisotropy_override = -1.0;
    Vector3 anisotropy_axis = Vector3(0, 1, 0);

    // Display color (for procedural fallback / UI only, NOT used in transport)
    Color display_color = Color(1, 1, 1, 1);

    // Color zoning (gradient)
    Color gradient_color = Color(0, 0, 0, 0); // transparent = no gradient
    double gradient_strength = 0.0;
    int gradient_mode = GRADIENT_MODE_LINEAR;
    double gradient_angle_degrees = 90.0;

    // Phenomenon (color-change, e.g., alexandrite)
    Color phenomenon_color = Color(0, 0, 0, 0);
    double phenomenon_strength = 0.0;
    double phenomenon_angle_degrees = 0.0;
    double phenomenon_sharpness = 1.0;

    // Gradient center offset (in normalized object space, radius-units).
    // Used by RADIAL / RADIAL_INVERSE modes so non-centroidal cuts (trillion, pear,
    // marquise) can re-center the radial zone. (0, 0) = geometric origin.
    Vector2 gradient_center = Vector2(0, 0);

    // Optional 81-sample target absorption curves (380–780 nm). When non-empty, the
    // tracer blends the body absorption toward these zone curves instead of using
    // RGB uplift from gradient_color / phenomenon_color.
    std::vector<float> gradient_zone_spectrum;
    std::vector<float> phenomenon_zone_spectrum;

    // Per-wavelength geometry splitting.
    // When true, trace_row_band runs 4 independent single-wavelength paths
    // (one per hero λ) through the gem instead of sharing one path. Costs
    // ~4x trace time but produces physically-correct dispersion — each λ
    // refracts along its own Snell direction at every surface, so high-
    // dispersion gems (diamond, zircon) exhibit real "fire".
    bool enable_dispersion = false;

    // Surface pattern fields (all retained from current)
    int surface_pattern_type = MATERIAL_PATTERN_NONE;
    double surface_pattern_mix = 0.0;
    Vector2 surface_pattern_scale = Vector2(1, 1);
    double surface_pattern_rotation_degrees = 0.0;
    double surface_pattern_density = 1.0;
    double surface_pattern_contrast = 0.5;
    double surface_pattern_warp_strength = 0.0;
    double surface_pattern_warp_scale = 1.0;
    double surface_pattern_specular_variation = 0.0;
    double surface_pattern_roughness_variation = 0.0;

    // Volume pattern fields (all retained from current)
    int volume_pattern_type = MATERIAL_PATTERN_NONE;
    double volume_pattern_mix = 0.0;
    Vector3 volume_pattern_scale = Vector3(1, 1, 1);
    Vector3 volume_pattern_axis = Vector3(0, 1, 0);
    double volume_pattern_density = 1.0;
    double volume_pattern_contrast = 0.5;
    double volume_pattern_warp_strength = 0.0;
    double volume_pattern_warp_scale = 1.0;
    double volume_absorption_variation = 0.0;
    double volume_scattering_variation = 0.0;

    // Structured haze density system (Phase 5)
    double haze_base_density = 0.0;        // Effective σ_s when pattern = STRUCTURED_HAZE
    double haze_density_variation = 0.5;   // Spatial variation strength (0=uniform, 1=high contrast)
    double haze_growth_correlation = 0.5;  // How much haze follows growth zone structure (0=clouds, 1=banded)
    double haze_distribution_skew = 0.8;   // Log-normal skew (0=symmetric, 2=heavy right tail)

    // Reactive effects (chatoyancy, opalescence, iridescence)
    int reactive_effect_type = MATERIAL_REACTIVE_NONE;
    Color reactive_color = Color(0, 0, 0, 0);
    Color reactive_secondary_color = Color(0, 0, 0, 0);
    double reactive_strength = 0.0;
    double reactive_sharpness = 2.0;
    double reactive_density = 1.0;
    double reactive_scale = 1.0;
    Vector3 reactive_axis = Vector3(1, 0, 0);

    // Texture
    bool use_texture = false;
    double texture_blend = 1.0;
    double texture_zoom = 1.0;
    Vector2 texture_offset = Vector2(0, 0);
    double texture_facet_warp = 0.35;
    Color material_secondary_color = Color(0, 0, 0, 0);
    Color material_tertiary_color = Color(0, 0, 0, 0);

    // View
    double rotation_degrees = 0.0;

    // Denoising
    double denoise_strength = 0.0;  // 0 = no denoise, 1 = full OIDN denoise

    // Per-zone roughness overrides (populated from GemVisualResource)
    static constexpr int MAX_ZONE_ROUGHNESS_ENTRIES = 8;
    struct ZoneRoughnessEntry {
        uint32_t zone_hash = 0;
        double roughness_mult = 1.0;
    };
    ZoneRoughnessEntry zone_roughness[MAX_ZONE_ROUGHNESS_ENTRIES];
    int zone_roughness_count = 0;

    // Surface wear Lambertian diffuse scatter.
    // Adds angle-independent diffuse reflection at frosted exterior wear masks,
    // producing the bright/white marks characteristic of real gem scratches
    // and abrasion. Roughness alone only broadens the specular lobe (neutral-
    // to-dark); this adds actual diffuse energy return.
    double damage_diffuse_albedo = 0.0;  // 0 = off, 0.2-0.3 typical T1

    // Frosted wear tint (for scratch / abrasion / edge wear). Decoupled from
    // body display_color so near-white gems can still produce visible wear
    // against a near-white body. damage_tint_strength blends between body
    // color (0) and authored tint (1).
    Color damage_tint = Color(0.95f, 0.95f, 0.95f, 1.0f);
    double damage_tint_strength = 1.0;

    // Tint for dirt / discolouration patches. Conceptually contamination
    // rather than material wear, so a warm grey/brown reads as "not clean"
    // without competing with the gem body colour.
    Color damage_dirt_tint = Color(0.70f, 0.63f, 0.50f, 1.0f);

    // Inclusion material properties
    double inclusion_ior = 1.5;
    double inclusion_absorption = 2.0;
    double inclusion_scatter = 0.5;
    double inclusion_typical_size = 0.02; // midpoint of profile size_range
    bool has_inclusions = false;

    // --- Resolved effective values (computed during context build) ---

    const std::vector<float>& effective_absorption() const {
        return absorption_spectrum_override.empty()
            ? absorption_spectrum : absorption_spectrum_override;
    }

    double effective_scattering() const {
        // Structured haze: haze_base_density replaces the normal scattering path.
        if (volume_pattern_type == MATERIAL_PATTERN_STRUCTURED_HAZE && haze_base_density > 0.0)
            return haze_base_density;
        return (scattering_coefficient_override >= 0.0)
            ? scattering_coefficient_override : scattering_coefficient;
    }

    double effective_roughness() const {
        return (surface_roughness_override >= 0.0)
            ? surface_roughness_override : surface_roughness;
    }

    double effective_roughness_for_zone(uint32_t zone_hash) const {
        double base = effective_roughness();
        for (int i = 0; i < zone_roughness_count; i++) {
            if (zone_roughness[i].zone_hash == zone_hash)
                return base * zone_roughness[i].roughness_mult;
        }
        return base;
    }

    double effective_fluorescence_yield() const {
        return (fluorescence_quantum_yield_override >= 0.0)
            ? fluorescence_quantum_yield_override : fluorescence_quantum_yield;
    }

    double effective_anisotropy() const {
        return (surface_anisotropy_override >= 0.0)
            ? surface_anisotropy_override : surface_anisotropy;
    }
};

// ---------------------------------------------------------------------------
// Light card (analytical light source)
// ---------------------------------------------------------------------------

struct LightCard {
    Vector3 dir;                     // direction (normalized, world space)
    Color color = Color(1, 1, 1, 1); // center color
    double sharp_power = 200.0;      // specular exponent at low roughness
    double broad_power = 10.0;       // specular exponent at high roughness
    double sharp_strength = 1.0;     // energy at low roughness
    double broad_strength = 0.5;     // energy at high roughness
    double temperature_kelvin = 0.0; // Planck temperature (0 = use color with spectral uplifting)
    Color edge_color = Color(1, 1, 1, 1); // peripheral card color
    double gradient_power = 1.0;     // center-to-edge gradient shape
};

// ---------------------------------------------------------------------------
// Environment setup (resolved for tracing)
// ---------------------------------------------------------------------------

struct EnvironmentSetup {
    // Sky gradient (fallback when no HDR map)
    Color sky_low, sky_top, horizon;
    Color ground_dark, ground_lift;

    // Light cards (world-space directions)
    std::vector<LightCard> cards;

    // Blocker
    Vector3 blocker_dir;
    double blocker_power = 10.0;
    double blocker_strength = 0.19;

    // Ground plane bounce
    double ground_albedo = 0.15;
    Color ground_tint = Color(0.92f, 0.87f, 0.80f, 1.0f);
    double ground_distance = 0.8;

    // HDR environment map data (null if not loaded)
    // hdr_float_storage owns the memory; hdr_data points into it.
    std::vector<float> hdr_float_storage;
    const float* hdr_data = nullptr;
    int hdr_width = 0;
    int hdr_height = 0;
    bool has_hdr = false;

    // Environment importance sampling CDF (precomputed from HDR map)
    std::vector<float> marginal_cdf;        // height entries
    std::vector<float> conditional_cdf;     // width*height entries
    float marginal_integral = 0.0f;

    // Output grade
    double exposure = 1.0;

    // Light/environment energy multipliers
    double light_energy = 2.4;
    double environment_energy = 1.0;

    // Per-environment card power cap. -1 = use default (40.0).
    double card_power_cap = -1.0;

    // Dual-illuminant: secondary illuminant temperature (K) and mix factor.
    // When mix > 0, the kernel traces two independent spectral accumulations
    // (primary ~D65, secondary at this temperature) per pixel and combines
    // them at XYZ stage pre-tonemap.
    double secondary_illuminant_temperature = 2856.0;
    double secondary_illuminant_mix = 0.0;
};

// ---------------------------------------------------------------------------
// Embree hit result
// ---------------------------------------------------------------------------

struct HitResult {
    bool did_hit = false;
    Vector3 position;
    Vector3 normal;            // shading normal (may be smoothed by edge rounding)
    Vector3 geometric_normal;  // flat facet normal (always the true geometric surface)
    double distance = 0.0;
    int triangle_idx = -1;
    int facet_idx = -1;
    bool front_face = true;    // determined from geometric_normal, not shading normal
    StringName zone;
    uint32_t zone_hash = 0;   // precomputed hash of zone for fast roughness lookup
    double surface_wear_mask = 0.0; // exterior frosted wear coverage at this hit
    int surface_wear_type = -1;
    Vector3 surface_wear_tangent = Vector3(0, 0, 0); // along-capsule dir for scratches
    Vector3 surface_wear_ridge_normal = Vector3(0, 0, 0); // adjacent facet normal for edge wear
};

struct SurfaceWearEntry {
    int type = 0; // 0 scratch, 1 abrasion, 2 edge wear, 3 dirt
    int facet_index = -1;
    Vector3 p0;
    Vector3 p1;
    Vector3 normal = Vector3(0, 1, 0);
    // Adjacent facet normal for edge wear (type 2). Unused for other types.
    // Set at generation time so the ridge-bevel shading can bias the effective
    // normal between the two facets meeting at the worn edge.
    Vector3 adjacent_normal = Vector3(0, 1, 0);
    double radius = 0.0;
    double intensity = 1.0;
    double seed = 0.0;
};

// ---------------------------------------------------------------------------
// Volume material sample (from procedural patterns)
// ---------------------------------------------------------------------------

struct VolumeMaterialSample {
    Color color = Color(1, 1, 1, 1);
    double pattern_value = 0.5;
    double accent_value = 0.5;
    double absorption_mult = 1.0;
    double scattering_mult = 1.0;
};

struct SurfaceMaterialSample {
    Color color = Color(1, 1, 1, 1);
    double pattern_value = 0.5;
    double accent_value = 0.0;
    double roughness_mult = 1.0;
    double specular_mult = 1.0;
};

struct PatternSample {
    double value = 0.5;
    double accent = 0.5;
};

struct CellularResult {
    double distance = 0.0;
    double edge_distance = 0.0;
    double seed = 0.5;
};

// ---------------------------------------------------------------------------
// Trace context (per-image, built once before tracing begins)
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// SPP-dependent variance budget
// ---------------------------------------------------------------------------
// Precomputed caps for high-variance features, scaled to the rendering budget.
// At low SPP, features that inject stochastic variance (fluorescence,
// inclusion scattering) are capped to values that converge within the available
// sample count. At high SPP, the authored values are used as-is.
//
// Scattering cap: REMOVED. The OIDN denoiser handles scatter noise directly.
// The old cap (0.0125 * sqrt(spp), raised 4x with denoise) was a pre-denoiser
// workaround that prevented scattering from expressing at moderate coefficients.
// With the denoiser integrated, authored scattering values pass through ungated.
//
// The remaining caps are derived from the relationship:
//   required_SPP ≈ (feature_strength / safe_base)² × reference_SPP
// Inverted: safe_cap = safe_base × sqrt(SPP / reference_SPP)

struct VarianceBudget {
    double fluorescence_yield_cap;  // max effective fluorescence quantum yield
    double inclusion_scatter_cap;   // max effective inclusion scatter_strength

    static VarianceBudget from_spp(int spp, bool denoise_active = false) {
        VarianceBudget vb;
        double s = std::sqrt((double)(spp > 0 ? spp : 1));
        // Fluorescence yield: 0.10 converges at 256 SPP → k = 0.10/16 = 0.00625
        vb.fluorescence_yield_cap = 0.00625 * s;
        // Inclusion scatter: 0.20 converges at 256 SPP → k = 0.20/16 = 0.0125
        vb.inclusion_scatter_cap = 0.0125 * s;
        return vb;
    }

    /// Scattering: pass through authored value ungated (denoiser handles noise).
    inline double gate_scattering(double authored) const {
        return authored;
    }
    inline double gate_fluorescence_yield(double authored) const {
        return authored < fluorescence_yield_cap ? authored : fluorescence_yield_cap;
    }
    inline double gate_inclusion_scatter(double authored) const {
        return authored < inclusion_scatter_cap ? authored : inclusion_scatter_cap;
    }
};

struct TraceContext {
    GemTraceProps props;
    EnvironmentSetup environment;

    // Camera
    Vector3 view_dir;
    Basis inverse_basis;
    double half_width = 0.0;
    double half_height = 0.0;
    double origin_z = 0.0;

    // Image dimensions
    Vector2i target_size;

    // Sampling
    int samples_per_pixel = 64;
    uint64_t base_seed = 42;

    // Mesh info
    double radius = 0.0;

    // Feature flags (computed from props)
    bool has_volume_patterns = false;
    bool has_surface_patterns = false;
    bool has_reactive = false;
    bool is_opaque = false;
    bool is_translucent = false;

    // Texture image (for texture-mapped gems)
    godot::Ref<godot::Image> texture_image;

    // Light direction (for opaque/translucent surface lighting)
    Vector3 light_dir;

    // SPP-dependent variance budget (computed from samples_per_pixel)
    VarianceBudget variance_budget;

    // Denoise active flag — enables higher scattering caps and AOV collection.
    bool denoise_active = false;

    // Diagnostic output: render first-hit surface wear mask as grayscale.
    bool debug_surface_wear_mask = false;
};

// ---------------------------------------------------------------------------
// TraceStats — thread-safe counters aggregated across all trace threads.
// ---------------------------------------------------------------------------

struct TraceStats {
    std::atomic<int64_t> primary_intersect_count{0};
    std::atomic<int64_t> secondary_intersect_count{0};   // NEE exit probe intersections
    std::atomic<int64_t> spectral_trace_count{0};         // trace_path / trace_path_spectral calls
    std::atomic<int64_t> surface_lighting_count{0};       // environment::sample() evaluations
    std::atomic<int64_t> volume_scatter_count{0};         // scatter events
    std::atomic<int64_t> bounce_count{0};                 // total bounces across all paths
    std::atomic<int64_t> starvation_terminations{0};      // paths terminated by NEE starvation
    std::atomic<int64_t> surface_wear_entry_count{0};     // analytic wear entries in scene
    std::atomic<int64_t> surface_wear_sample_count{0};    // first camera hits tested for wear
    std::atomic<int64_t> surface_wear_hit_count{0};       // first camera hits with mask > threshold
    std::atomic<int64_t> surface_wear_mask_sum_micros{0}; // first-hit mask sum × 1e6
    std::atomic<int64_t> surface_wear_mask_max_micros{0}; // max first-hit mask × 1e6
};

// ---------------------------------------------------------------------------
// Math helpers
// ---------------------------------------------------------------------------

inline double clampd(double v, double lo, double hi) {
    return (v < lo) ? lo : ((v > hi) ? hi : v);
}

inline int clampi(int v, int lo, int hi) {
    return (v < lo) ? lo : ((v > hi) ? hi : v);
}

inline double lerpd(double a, double b, double t) {
    return a + (b - a) * t;
}

inline double smoothstepd(double edge0, double edge1, double x) {
    double t = clampd((x - edge0) / (edge1 - edge0 + 1e-12), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}

inline double dmax(double a, double b) { return a > b ? a : b; }
inline double dmin(double a, double b) { return a < b ? a : b; }

inline Vector3 vec3_clamp(Vector3 v, double lo, double hi) {
    return Vector3(clampd(v.x, lo, hi), clampd(v.y, lo, hi), clampd(v.z, lo, hi));
}

inline Color color_lerp(Color a, Color b, double t) {
    return Color(
        a.r + (b.r - a.r) * t,
        a.g + (b.g - a.g) * t,
        a.b + (b.b - a.b) * t,
        a.a + (b.a - a.a) * t
    );
}

} // namespace gem
