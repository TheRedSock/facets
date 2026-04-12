// gem_trace_volume.cpp — Beer-Lambert, Henyey-Greenstein scattering, fluorescence.
#include "gem_trace_volume.h"
#include <cmath>

namespace gem { namespace volume {

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
                               Vector3 obj_pos, double lambda_nm) {
    if (props.gradient_strength < 0.001 || props.gradient_color.a < 0.001)
        return 1.0;

    // Compute spatial gradient factor t ∈ [0, 1]
    double t = 0.0;
    switch (props.gradient_mode) {
        case GRADIENT_MODE_LINEAR: {
            double angle_rad = props.gradient_angle_degrees * PI / 180.0;
            double dx = std::cos(angle_rad);
            double dy = std::sin(angle_rad);
            t = clampd(((double)obj_pos.x * dx + (double)obj_pos.y * dy) * 0.5 + 0.5, 0.0, 1.0);
            break;
        }
        case GRADIENT_MODE_RADIAL: {
            double r = std::sqrt((double)obj_pos.x * (double)obj_pos.x
                               + (double)obj_pos.y * (double)obj_pos.y);
            t = clampd(r * 1.2, 0.0, 1.0);
            break;
        }
        case GRADIENT_MODE_RADIAL_INVERSE: {
            double r = std::sqrt((double)obj_pos.x * (double)obj_pos.x
                               + (double)obj_pos.y * (double)obj_pos.y);
            t = clampd(1.0 - r * 1.2, 0.0, 1.0);
            break;
        }
    }

    double strength = t * props.gradient_strength;
    if (strength < 0.001) return 1.0;

    // Spectral contribution of gradient_color at this wavelength.
    // High values mean the gradient_color has strong presence at lambda_nm.
    double spectral = spectral::spectral_uplift(props.gradient_color, lambda_nm);

    // Normalize against a reference wavelength so the modulation is balanced.
    // Use the peak of spectral_uplift for this color (approximate at 540nm).
    double ref_r = spectral::spectral_uplift(props.gradient_color, 610.0);
    double ref_g = spectral::spectral_uplift(props.gradient_color, 540.0);
    double ref_b = spectral::spectral_uplift(props.gradient_color, 460.0);
    double peak = dmax(dmax(ref_r, ref_g), dmax(ref_b, 0.01));
    double normalized = clampd(spectral / peak, 0.0, 1.5);

    // Modulate absorption: REDUCE where gradient_color is strong (let that
    // color through), INCREASE where it's weak (absorb competing colors).
    // At full strength: factor ranges from ~0.2 (color peak) to ~2.5 (trough).
    double factor = 1.0 - strength * (normalized - 0.35) * 2.0;
    return clampd(factor, 0.1, 3.0);
}

double phenomenon_absorption_mod(const GemTraceProps& props,
                                 Vector3 ray_dir, double lambda_nm) {
    if (props.phenomenon_strength < 0.001 || props.phenomenon_color.a < 0.001)
        return 1.0;

    // Compute directional phenomenon factor.
    // The phenomenon_angle_degrees defines the axis of color change.
    // Rays traveling along this axis see maximum color shift.
    double angle_rad = props.phenomenon_angle_degrees * PI / 180.0;
    Vector3 axis((float)std::cos(angle_rad), (float)std::sin(angle_rad), 0.0f);
    axis = axis.normalized();

    double dot = std::abs((double)ray_dir.normalized().dot(axis));
    double t = std::pow(clampd(dot, 0.0, 1.0), props.phenomenon_sharpness);
    double strength = t * props.phenomenon_strength;
    if (strength < 0.001) return 1.0;

    double spectral = spectral::spectral_uplift(props.phenomenon_color, lambda_nm);
    double ref_r = spectral::spectral_uplift(props.phenomenon_color, 610.0);
    double ref_g = spectral::spectral_uplift(props.phenomenon_color, 540.0);
    double ref_b = spectral::spectral_uplift(props.phenomenon_color, 460.0);
    double peak = dmax(dmax(ref_r, ref_g), dmax(ref_b, 0.01));
    double normalized = clampd(spectral / peak, 0.0, 1.5);

    double factor = 1.0 - strength * (normalized - 0.35) * 2.0;
    return clampd(factor, 0.1, 3.0);
}

double beer_lambert_zoned(const GemTraceProps& props, double lambda_nm,
                          double distance, Vector3 ray_dir,
                          Vector3 obj_pos, double absorption_mult) {
    if (props.effective_absorption().empty()) return 1.0;
    double alpha = spectral::evaluate_absorption(props, lambda_nm, ray_dir);
    alpha *= absorption_mult;

    // Apply gradient color zoning
    alpha *= gradient_absorption_mod(props, obj_pos, lambda_nm);

    // Apply phenomenon (angle-dependent color change)
    alpha *= phenomenon_absorption_mod(props, ray_dir, lambda_nm);

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

bool try_fluorescence(const GemTraceProps& props, double& wavelength_nm, TraceRNG& rng) {
    if (props.fluorescence_quantum_yield <= 0.0) return false;

    // Gaussian excitation probability
    double delta = (wavelength_nm - props.fluorescence_excitation_center_nm)
                 / dmax(props.fluorescence_excitation_width_nm, 1.0);
    double excitation = std::exp(-0.5 * delta * delta);

    if (rng.next() >= props.fluorescence_quantum_yield * excitation) return false;

    // Shift wavelength to emission band (Gaussian sample)
    wavelength_nm = props.fluorescence_emission_center_nm
                  + rng.next_gaussian() * props.fluorescence_emission_width_nm;
    wavelength_nm = clampd(wavelength_nm, LAMBDA_MIN, LAMBDA_MAX);
    return true;
}

}} // namespace gem::volume
