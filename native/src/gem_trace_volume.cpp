// gem_trace_volume.cpp — Beer-Lambert, Henyey-Greenstein scattering, fluorescence.
#include "gem_trace_volume.h"
#include <cmath>

namespace gem { namespace volume {

namespace {

bool gradient_has_authoring(const GemTraceProps& p) {
    if (p.gradient_zone_spectrum.size() == 81) {
        return true;
    }
    return p.gradient_color.a > 0.001;
}

bool phenomenon_has_authoring(const GemTraceProps& p) {
    if (p.phenomenon_zone_spectrum.size() == 81) {
        return true;
    }
    return p.phenomenon_color.a > 0.001;
}

// Normalized shape ∈ [0, 1.5] for legacy RGB uplift modulation.
bool zone_normalized_shape(
    const GemTraceProps& props,
    bool is_gradient,
    double lambda_nm,
    double* out_norm) {
    const std::vector<float>& zone = is_gradient ? props.gradient_zone_spectrum : props.phenomenon_zone_spectrum;
    Color fallback = is_gradient ? props.gradient_color : props.phenomenon_color;

    if (zone.size() == 81) {
        return false;
    }
    if (fallback.a < 0.001) {
        return false;
    }
    double spectral = spectral::spectral_uplift(fallback, lambda_nm);
    double ref_r = spectral::spectral_uplift(fallback, 610.0);
    double ref_g = spectral::spectral_uplift(fallback, 540.0);
    double ref_b = spectral::spectral_uplift(fallback, 460.0);
    double peak = dmax(dmax(ref_r, ref_g), dmax(ref_b, 0.01));
    *out_norm = clampd(spectral / peak, 0.0, 1.5);
    return true;
}

double sample_zone_target_alpha(
    const std::vector<float>& zone,
    const GemTraceProps& props,
    double lambda_nm) {
    return dmax(
        spectral::sample_curve_at_lambda(zone, lambda_nm) * props.absorption_strength_scale,
        0.0);
}

} // namespace

// ---------------------------------------------------------------------------
// Beer-Lambert attenuation
// ---------------------------------------------------------------------------

double beer_lambert(const GemTraceProps& props, double lambda_nm,
                    double distance, Vector3 ray_dir,
                    double absorption_mult) {
    if (props.effective_absorption().empty()) return 1.0;
    double alpha = spectral::evaluate_absorption(props, lambda_nm, ray_dir);
    alpha *= absorption_mult;
    return std::exp(-alpha * dmax(distance, 0.0));
}

// ---------------------------------------------------------------------------
// Gradient/phenomenon color zoning
// ---------------------------------------------------------------------------

double gradient_absorption_mod(const GemTraceProps& props,
                               Vector3 obj_pos, double lambda_nm, double base_alpha) {
    if (props.material_mode != MATERIAL_MODE_FACETED_TRANSPARENT)
        return base_alpha;
    if (props.gradient_strength < 0.001 || !gradient_has_authoring(props))
        return base_alpha;

    // Centered object-space coordinates. For non-centroidal cuts (trillion,
    // pear, marquise) gradient_center shifts the origin so RADIAL zones
    // wrap the visible mass rather than a geometric point far from center.
    double cx = (double)obj_pos.x - (double)props.gradient_center.x;
    double cy = (double)obj_pos.y - (double)props.gradient_center.y;

    // Compute spatial gradient factor t ∈ [0, 1]
    double t = 0.0;
    switch (props.gradient_mode) {
        case GRADIENT_MODE_LINEAR: {
            double angle_rad = props.gradient_angle_degrees * PI / 180.0;
            double dx = std::cos(angle_rad);
            double dy = std::sin(angle_rad);
            t = clampd((cx * dx + cy * dy) * 0.5 + 0.5, 0.0, 1.0);
            break;
        }
        case GRADIENT_MODE_RADIAL: {
            double r = std::sqrt(cx * cx + cy * cy);
            t = clampd(r * 1.2, 0.0, 1.0);
            break;
        }
        case GRADIENT_MODE_RADIAL_INVERSE: {
            double r = std::sqrt(cx * cx + cy * cy);
            t = clampd(1.0 - r * 1.2, 0.0, 1.0);
            break;
        }
    }

    double strength = t * props.gradient_strength;
    if (strength < 0.001) return base_alpha;

    if (props.gradient_zone_spectrum.size() == 81) {
        double zone_alpha = sample_zone_target_alpha(props.gradient_zone_spectrum, props, lambda_nm);
        return lerpd(base_alpha, zone_alpha, strength);
    }

    double normalized = 0.0;
    if (!zone_normalized_shape(props, true, lambda_nm, &normalized))
        return base_alpha;

    // Legacy RGB uplift path: REDUCE where the authored RGB color is strong
    // (let that color through), INCREASE where it's weak.
    double factor = 1.0 - strength * (normalized - 0.35) * 2.0;
    return base_alpha * clampd(factor, 0.1, 3.0);
}

double phenomenon_absorption_mod(const GemTraceProps& props,
                                 Vector3 ray_dir, double lambda_nm, double base_alpha) {
    if (props.material_mode != MATERIAL_MODE_FACETED_TRANSPARENT)
        return base_alpha;
    if (props.phenomenon_strength < 0.001 || !phenomenon_has_authoring(props))
        return base_alpha;

    // Compute directional phenomenon factor.
    // The phenomenon_angle_degrees defines the axis of color change.
    // Rays traveling along this axis see maximum color shift.
    double angle_rad = props.phenomenon_angle_degrees * PI / 180.0;
    Vector3 axis((float)std::cos(angle_rad), (float)std::sin(angle_rad), 0.0f);
    axis = axis.normalized();

    double dot = std::abs((double)ray_dir.normalized().dot(axis));
    double t = std::pow(clampd(dot, 0.0, 1.0), props.phenomenon_sharpness);
    double strength = t * props.phenomenon_strength;
    if (strength < 0.001) return base_alpha;

    if (props.phenomenon_zone_spectrum.size() == 81) {
        double zone_alpha = sample_zone_target_alpha(props.phenomenon_zone_spectrum, props, lambda_nm);
        return lerpd(base_alpha, zone_alpha, strength);
    }

    double normalized = 0.0;
    if (!zone_normalized_shape(props, false, lambda_nm, &normalized))
        return base_alpha;

    double factor = 1.0 - strength * (normalized - 0.35) * 2.0;
    return base_alpha * clampd(factor, 0.1, 3.0);
}

double beer_lambert_zoned(const GemTraceProps& props, double lambda_nm,
                          double distance, Vector3 ray_dir,
                          Vector3 obj_pos, double absorption_mult) {
    if (props.effective_absorption().empty()) return 1.0;
    double alpha = spectral::evaluate_absorption(props, lambda_nm, ray_dir);
    alpha *= absorption_mult;

    // Apply gradient zoning
    alpha = gradient_absorption_mod(props, obj_pos, lambda_nm, alpha);

    // Apply phenomenon (angle-dependent color change)
    alpha = phenomenon_absorption_mod(props, ray_dir, lambda_nm, alpha);

    return std::exp(-alpha * dmax(distance, 0.0));
}

// ---------------------------------------------------------------------------
// Sample scatter distance from exponential distribution
// ---------------------------------------------------------------------------

double sample_scatter_distance(double sigma_s, TraceRNG& rng) {
    if (sigma_s <= 1e-12) return 1e30; // effectively infinite
    double u = rng.next();
    double safe_u = 1.0 - u;
    if (safe_u < 1e-15) safe_u = 1e-15;
    return -std::log(safe_u) / sigma_s;
}

// ---------------------------------------------------------------------------
// Henyey-Greenstein phase function sampling
// ---------------------------------------------------------------------------

Vector3 sample_henyey_greenstein(Vector3 incident_dir, double g, TraceRNG& rng) {
    double u = rng.next();
    double cos_theta;
    if (std::abs(g) < 1e-6) {
        // Isotropic
        cos_theta = 1.0 - 2.0 * u;
    } else {
        double s = (1.0 - g * g) / (1.0 - g + 2.0 * g * u);
        cos_theta = clampd((1.0 + g * g - s * s) / (2.0 * g), -1.0, 1.0);
    }
    double sin_theta_sq = 1.0 - cos_theta * cos_theta;
    double sin_theta = std::sqrt(sin_theta_sq > 0.0 ? sin_theta_sq : 0.0);
    double phi = TWO_PI * rng.next();

    // Build local frame from incident direction
    Vector3 tangent, bitangent;
    fresnel::build_orthonormal_basis(incident_dir, tangent, bitangent);

    return (tangent * (float)(sin_theta * std::cos(phi))
          + bitangent * (float)(sin_theta * std::sin(phi))
          + incident_dir * (float)cos_theta).normalized();
}

// ---------------------------------------------------------------------------
// Fluorescence wavelength shift
// ---------------------------------------------------------------------------

bool try_fluorescence(const GemTraceProps& props, double& wavelength_nm, TraceRNG& rng,
                      double yield_cap) {
    double yield = dmin(props.effective_fluorescence_yield(), yield_cap);
    if (yield <= 0.0) return false;

    // Gaussian excitation probability
    double delta = (wavelength_nm - props.fluorescence_excitation_center_nm)
                 / dmax(props.fluorescence_excitation_width_nm, 1.0);
    double excitation = std::exp(-0.5 * delta * delta);

    if (rng.next() >= yield * excitation) return false;

    // Shift wavelength to emission band (Gaussian sample)
    wavelength_nm = props.fluorescence_emission_center_nm
                  + rng.next_gaussian() * props.fluorescence_emission_width_nm;
    wavelength_nm = clampd(wavelength_nm, LAMBDA_MIN, LAMBDA_MAX);
    return true;
}

double fluorescence_emission_boost(const GemTraceProps& props,
                                   double emitted_wavelength_nm,
                                   Vector3 ray_dir) {
    if (props.effective_fluorescence_yield() <= 0.0) return 1.0;
    if (props.effective_absorption().empty()) return 1.0;

    // Nominal remaining path inside the gem after emission. Typical object-space
    // gems span ~1 unit across the widest axis and ~0.6 along the height, so
    // the average escape distance for a photon emitted deep in the body is a
    // fraction of that. 0.4 keeps the guard conservative: it only kicks in
    // when the authored absorption would otherwise eat the emitted photon.
    constexpr double kNominalEscapePath = 0.4;

    double alpha = spectral::evaluate_absorption(props, emitted_wavelength_nm, ray_dir);
    double depth = alpha * kNominalEscapePath;
    // Cap so post-emission survival over the nominal path is at least 50%.
    constexpr double kMaxDepth = 0.69314718; // ln(2)
    if (depth <= kMaxDepth) return 1.0;

    // Boost throughput by the excess optical depth above the cap. The next
    // beer_lambert call still attenuates exp(-alpha * distance), so boosting
    // upstream by exp(depth - kMaxDepth) leaves the photon with at least the
    // 50% survival budget on its first post-emission segment. Absorption
    // beyond the segment is handled normally.
    return std::exp(depth - kMaxDepth);
}

}} // namespace gem::volume
